import { Router, Request, Response } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { supabase } from '../config/supabase';
import { redis } from '../config/redis';
import { AppError, asyncHandler } from '../utils/errors';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { rateLimit } from '../middleware/rateLimit';
import { AuthenticatedRequest } from '../types';
import { invalidateCulturalScoreCache } from '../services/scoring';

const router = Router();

// ─── Constants ──────────────────────────────────────────────────────────────────

const SIGHTENGINE_API_USER = process.env.SIGHTENGINE_API_USER || '';
const SIGHTENGINE_API_SECRET = process.env.SIGHTENGINE_API_SECRET || '';
const AWS_REGION = process.env.AWS_REGION || 'us-east-1';

const MAX_PHOTOS = 6;
const MAX_VIDEOS = 1;
const MAX_VERIFY_ATTEMPTS_PER_DAY = 3;
const REKOGNITION_SIMILARITY_THRESHOLD = 85;

const IMAGE_SIZES = {
  thumb: { width: 200, quality: 80 },
  medium: { width: 600, quality: 80 },
  large: { width: 1200, quality: 80 },
} as const;

const ALLOWED_IMAGE_MIMES = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
];
const ALLOWED_VIDEO_MIMES = ['video/mp4', 'video/quicktime', 'video/webm'];
const ALLOWED_MIMES = [...ALLOWED_IMAGE_MIMES, ...ALLOWED_VIDEO_MIMES];

// ─── Multer Config ──────────────────────────────────────────────────────────────

const uploadMedia = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 50 * 1024 * 1024, // 50 MB (video can be larger)
    files: 1,
  },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_MIMES.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(
        new AppError(
          400,
          'Only JPEG, PNG, WebP, HEIC images and MP4/MOV/WebM videos are allowed',
          'INVALID_FILE_TYPE'
        )
      );
    }
  },
});

const uploadSelfie = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10 MB
    files: 1,
  },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_IMAGE_MIMES.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(
        new AppError(
          400,
          'Selfie must be a JPEG, PNG, WebP, or HEIC image',
          'INVALID_FILE_TYPE'
        )
      );
    }
  },
});

// ─── Zod Schemas for PATCH /v1/me ───────────────────────────────────────────────

const basicsSchema = z
  .object({
    display_name: z.string().min(2).max(50).optional(),
    date_of_birth: z.string().date().optional(),
    gender: z.enum(['man', 'woman', 'non-binary']).optional(),
    bio: z.string().max(500).optional(),
    height_cm: z.number().int().min(120).max(240).optional(),
    city: z.string().max(100).optional(),
    state: z.string().max(100).optional(),
    country: z.string().max(100).optional(),
    // Lifestyle — canonical client vocab: smoking/drinking = Never/Socially/
    // Regularly, exercise = Daily/Often/Sometimes/Never (compared
    // case-insensitively by the discovery filters). Previously these had no
    // schema slot, so they could never be saved at all.
    smoking: z.string().max(50).nullable().optional(),
    drinking: z.string().max(50).nullable().optional(),
    exercise: z.string().max(50).nullable().optional(),
  })
  .strict();

const sindhiSchema = z
  .object({
    mother_tongue: z.string().max(50).optional(),
    sindhi_dialect: z.string().max(50).optional(),
    sindhi_fluency: z
      .enum(['native', 'fluent', 'conversational', 'basic', 'learning', 'none'])
      .optional(),
    community_sub_group: z.string().max(100).optional(),
    gotra: z.string().max(100).optional(),
  })
  .strict();

const chattiSchema = z
  .object({
    family_values: z.enum(['traditional', 'moderate', 'liberal']).optional(),
    joint_family_preference: z.boolean().optional(),
    festivals_celebrated: z.array(z.string().max(50)).max(20).optional(),
    food_preference: z
      .enum(['vegetarian', 'non_vegetarian', 'vegan', 'jain', 'eggetarian'])
      .optional(),
    cuisine_preferences: z.array(z.string().max(50)).max(15).optional(),
    cultural_activities: z.array(z.string().max(50)).max(15).optional(),
    traditional_attire: z.string().max(100).optional(),
  })
  .strict();

const personalitySchema = z
  .object({
    interests: z.array(z.string().max(50)).max(20).optional(),
    music_preferences: z.array(z.string().max(50)).max(15).optional(),
    movie_genres: z.array(z.string().max(50)).max(15).optional(),
    travel_style: z.string().max(100).optional(),
    pet_preference: z.string().max(100).optional(),
    // Hinge-style profile prompts, stored as JSONB [{ question, answer }].
    // An empty array clears them.
    prompts: z
      .array(
        z.object({
          id: z.string().max(64).optional(),
          question: z.string().min(1).max(150),
          answer: z.string().min(1).max(300),
        }),
      )
      .max(3)
      .optional(),
  })
  .strict();

const settingsSchema = z
  .object({
    discovery_enabled: z.boolean().optional(),
    show_online_status: z.boolean().optional(),
    show_distance: z.boolean().optional(),
    show_full_name: z.boolean().optional(),
    push_notifications: z.boolean().optional(),
    email_notifications: z.boolean().optional(),
    age_min: z.number().int().min(18).max(99).optional(),
    age_max: z.number().int().min(18).max(99).optional(),
    distance_km: z.number().int().min(1).max(500).optional(),
    gender_preference: z.enum(['men', 'women', 'everyone']).optional(),
    incognito_mode: z.boolean().optional(),
    // Discovery filters (null clears a filter; discovery.ts reads these names)
    verified_only: z.boolean().optional(),
    intent_filter: z.enum(['casual', 'serious', 'open', 'marriage']).nullable().optional(),
    religion_filter: z.string().max(100).nullable().optional(),
    height_min: z.number().int().min(120).max(240).nullable().optional(),
    height_max: z.number().int().min(120).max(240).nullable().optional(),
    education_filter: z.string().max(100).nullable().optional(),
    smoking_filter: z.string().max(50).nullable().optional(),
    drinking_filter: z.string().max(50).nullable().optional(),
    fluency_filter: z
      .enum(['native', 'fluent', 'conversational', 'basic', 'learning', 'none'])
      .nullable()
      .optional(),
    // 'exclude_same' hides same-gotra profiles (traditional incompatibility);
    // any other value shows only candidates of that specific gotra.
    gotra_filter: z.string().max(100).nullable().optional(),
    dietary_filter: z
      .enum(['vegetarian', 'non_vegetarian', 'vegan', 'jain', 'eggetarian'])
      .nullable()
      .optional(),
    kundli_min: z.number().int().min(0).max(36).optional(),
  })
  .strict();

const userSchema = z
  .object({
    intent: z
      .enum(['casual', 'serious', 'open', 'marriage'])
      .optional(),
    education: z.string().max(100).optional(),
    occupation: z.string().max(100).optional(),
    company: z.string().max(100).optional(),
    religion: z.string().max(100).optional(),
    // Snooze pauses discovery without hiding the account permanently
    is_snoozed: z.boolean().optional(),
  })
  .strict();

const patchProfileSchema = z
  .object({
    basics: basicsSchema.optional(),
    sindhi: sindhiSchema.optional(),
    chatti: chattiSchema.optional(),
    personality: personalitySchema.optional(),
    settings: settingsSchema.optional(),
    user: userSchema.optional(),
  })
  .strict()
  .refine(
    (data) => Object.keys(data).length > 0,
    { message: 'At least one section must be provided' }
  );

// ─── Profile Completeness Calculator ────────────────────────────────────────────
// 28 total fields:
//   8 basics:   display_name, date_of_birth, gender, bio, height_cm, city, state, country
//   5 sindhi:   mother_tongue, sindhi_dialect, sindhi_fluency, community_sub_group, gotra
//   7 chatti:   family_values, joint_family_preference, festivals_celebrated,
//               food_preference, cuisine_preferences, cultural_activities, traditional_attire
//   3 culture from user_sindhi (overlap counted via sindhi table):
//               Already counted in sindhi fields; the spec says "3 culture from user_sindhi"
//               These are family_origin_city, family_origin_country, generation — stored in sindhi_profiles.
//               So total sindhi = 5 + 3 = 8 unique fields from sindhi_profiles
//   5 personality: interests, music_preferences, movie_genres, travel_style, pet_preference
// Re-reading the spec: 8 basics + 5 sindhi + 7 chatti + 3 culture + 5 personality = 28

interface CompletenessData {
  basics: Record<string, any> | null;
  sindhi: Record<string, any> | null;
  chatti: Record<string, any> | null;
  personality: Record<string, any> | null;
}

function calculateCompleteness(data: CompletenessData): number {
  const fields: Array<{ table: keyof CompletenessData; field: string }> = [
    // 8 basics
    { table: 'basics', field: 'display_name' },
    { table: 'basics', field: 'date_of_birth' },
    { table: 'basics', field: 'gender' },
    { table: 'basics', field: 'bio' },
    { table: 'basics', field: 'height_cm' },
    { table: 'basics', field: 'city' },
    { table: 'basics', field: 'state' },
    { table: 'basics', field: 'country' },
    // 5 sindhi
    { table: 'sindhi', field: 'mother_tongue' },
    { table: 'sindhi', field: 'sindhi_dialect' },
    { table: 'sindhi', field: 'sindhi_fluency' },
    { table: 'sindhi', field: 'community_sub_group' },
    { table: 'sindhi', field: 'gotra' },
    // 7 chatti
    { table: 'chatti', field: 'family_values' },
    { table: 'chatti', field: 'joint_family_preference' },
    { table: 'chatti', field: 'festivals_celebrated' },
    { table: 'chatti', field: 'food_preference' },
    { table: 'chatti', field: 'cuisine_preferences' },
    { table: 'chatti', field: 'cultural_activities' },
    { table: 'chatti', field: 'traditional_attire' },
    // 3 culture (from sindhi_profiles table)
    { table: 'sindhi', field: 'family_origin_city' },
    { table: 'sindhi', field: 'family_origin_country' },
    { table: 'sindhi', field: 'generation' },
    // 5 personality
    { table: 'personality', field: 'interests' },
    { table: 'personality', field: 'music_preferences' },
    { table: 'personality', field: 'movie_genres' },
    { table: 'personality', field: 'travel_style' },
    { table: 'personality', field: 'pet_preference' },
  ];

  const total = fields.length; // 28
  let filled = 0;

  for (const { table, field } of fields) {
    const row = data[table];
    if (!row) continue;

    const value = row[field];
    if (value === null || value === undefined || value === '') continue;

    // For arrays, only count as filled if non-empty
    if (Array.isArray(value) && value.length === 0) continue;

    // For booleans, any value (including false) counts as filled
    filled++;
  }

  return Math.round((filled / total) * 100);
}

// ─── Sightengine Moderation ─────────────────────────────────────────────────────

async function checkImageModeration(
  buffer: Buffer
): Promise<{ safe: boolean; nudityScore: number }> {
  if (!SIGHTENGINE_API_USER || !SIGHTENGINE_API_SECRET) {
    // If Sightengine is not configured, allow (dev mode)
    console.warn(
      '[Moderation] Sightengine not configured — skipping moderation check'
    );
    return { safe: true, nudityScore: 0 };
  }

  const FormData = (await import('form-data')).default;
  const form = new FormData();
  form.append('media', buffer, { filename: 'upload.jpg', contentType: 'image/jpeg' });
  form.append('models', 'nudity-2.1');
  form.append('api_user', SIGHTENGINE_API_USER);
  form.append('api_secret', SIGHTENGINE_API_SECRET);

  const response = await fetch('https://api.sightengine.com/1.0/check.json', {
    method: 'POST',
    body: form as any,
    headers: form.getHeaders(),
  });

  if (!response.ok) {
    console.error(
      '[Moderation] Sightengine API returned',
      response.status
    );
    // Fail open in case of API outage — log for review
    return { safe: true, nudityScore: 0 };
  }

  const result = (await response.json()) as any;

  // Sightengine nudity-2.1 returns scores for various categories
  const nudityScore = Math.max(
    result?.nudity?.sexual_activity ?? 0,
    result?.nudity?.sexual_display ?? 0,
    result?.nudity?.erotica ?? 0
  );

  return {
    safe: nudityScore <= 0.7,
    nudityScore,
  };
}

// ─── AWS Rekognition Face Comparison ────────────────────────────────────────────

async function compareFaces(
  sourceBuffer: Buffer,
  targetBuffer: Buffer
): Promise<{ match: boolean; similarity: number }> {
  // Dynamic import to avoid loading AWS SDK when not needed
  const {
    RekognitionClient,
    CompareFacesCommand,
  } = await import('@aws-sdk/client-rekognition');

  const client = new RekognitionClient({ region: AWS_REGION });

  const command = new CompareFacesCommand({
    SourceImage: { Bytes: sourceBuffer },
    TargetImage: { Bytes: targetBuffer },
    SimilarityThreshold: REKOGNITION_SIMILARITY_THRESHOLD,
  });

  const response = await client.send(command);

  if (!response.FaceMatches || response.FaceMatches.length === 0) {
    return { match: false, similarity: 0 };
  }

  const bestMatch = response.FaceMatches.reduce(
    (best: any, current: any) =>
      (current.Similarity ?? 0) > (best.Similarity ?? 0) ? current : best,
    response.FaceMatches[0]
  );

  const similarity = bestMatch.Similarity ?? 0;

  return {
    match: similarity >= REKOGNITION_SIMILARITY_THRESHOLD,
    similarity,
  };
}

// ─── Helper: upsert a profile sub-table ─────────────────────────────────────────

async function upsertProfileTable(
  table: string,
  userId: string,
  fields: Record<string, any>
): Promise<Record<string, any>> {
  // These tables use user_id as PRIMARY KEY (no separate id column),
  // so we must check existence via user_id, not id.
  const { data: existing } = await supabase
    .from(table)
    .select('user_id')
    .eq('user_id', userId)
    .maybeSingle();

  if (existing) {
    const { data, error } = await supabase
      .from(table)
      .update(fields)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) {
      throw new AppError(
        500,
        `Failed to update ${table}: ${error.message}`,
        'UPDATE_FAILED'
      );
    }
    return data!;
  } else {
    const { data, error } = await supabase
      .from(table)
      .insert({ user_id: userId, ...fields })
      .select()
      .single();

    if (error) {
      throw new AppError(
        500,
        `Failed to create ${table}: ${error.message}`,
        'INSERT_FAILED'
      );
    }
    return data!;
  }
}

// ─── Helper: Fetch all profile data for completeness ────────────────────────────

async function fetchProfileData(userId: string): Promise<CompletenessData> {
  const [
    { data: userRow },
    { data: basicProfile },
    { data: sindhi },
    { data: chatti },
    { data: personality },
  ] = await Promise.all([
    supabase.from('users').select('*').eq('id', userId).single(),
    supabase.from('basic_profiles').select('*').eq('user_id', userId).single(),
    supabase
      .from('sindhi_profiles')
      .select('*')
      .eq('user_id', userId)
      .single(),
    supabase
      .from('chatti_profiles')
      .select('*')
      .eq('user_id', userId)
      .single(),
    supabase
      .from('personality_profiles')
      .select('*')
      .eq('user_id', userId)
      .single(),
  ]);

  // calculateCompleteness expects the 8 "basics" fields under data.basics,
  // but PATCH /me stores most of them on the `users` table (with `dob`
  // rather than `date_of_birth`); only height_cm lives on basic_profiles.
  // Merge both so completeness actually credits saved basics.
  const basics = {
    ...(basicProfile || {}),
    display_name: userRow?.display_name ?? null,
    date_of_birth: userRow?.dob ?? null,
    gender: userRow?.gender ?? null,
    bio: userRow?.bio ?? null,
    city: userRow?.city ?? null,
    state: userRow?.state ?? null,
    country: userRow?.country ?? null,
  };

  return { basics, sindhi, chatti, personality };
}

// ─── GET /v1/me ─────────────────────────────────────────────────────────────────
// Returns the authenticated user's full profile across all tables.

router.get(
  '/',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;

    const [
      { data: userData },
      { data: basics },
      { data: sindhi },
      { data: chatti },
      { data: personality },
      { data: photos },
      { data: settings },
      { data: privileges },
      { data: safety },
    ] = await Promise.all([
      supabase.from('users').select('*').eq('id', user.id).single(),
      supabase
        .from('basic_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('sindhi_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('chatti_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('personality_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('photos')
        .select('*')
        .eq('user_id', user.id)
        .order('sort_order'),
      supabase
        .from('user_settings')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('user_privileges')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('user_safety')
        .select('*')
        .eq('user_id', user.id)
        .single(),
    ]);

    res.json({
      success: true,
      data: {
        user: userData,
        basics,
        sindhi,
        chatti,
        personality,
        photos: photos || [],
        settings,
        privileges,
        safety,
      },
    });
  })
);

// ─── PATCH /v1/me ───────────────────────────────────────────────────────────────
// Section-based profile update. Body: { basics?, sindhi?, chatti?, personality?, settings?, user? }

router.patch(
  '/',
  authenticate,
  validate(patchProfileSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const {
      basics,
      sindhi,
      chatti,
      personality,
      settings,
      user: userFields,
    } = req.body;

    const results: Record<string, any> = {};

    // Map sections to their database tables and execute updates in parallel
    const updatePromises: Array<PromiseLike<void>> = [];

    // basics splits across two tables:
    //   users table: display_name, date_of_birth (-> dob), gender, bio, city, state, country
    //   basic_profiles table: height_cm
    // Some payload keys map to differently-named DB columns.
    if (basics && Object.keys(basics).length > 0) {
      const USER_TABLE_KEYS = new Set([
        'display_name',
        'date_of_birth',
        'gender',
        'bio',
        'city',
        'state',
        'country',
      ]);
      const USER_COLUMN_MAP: Record<string, string> = {
        date_of_birth: 'dob',
      };
      const usersUpdate: Record<string, any> = {};
      const basicProfilesUpdate: Record<string, any> = {};
      for (const [k, v] of Object.entries(basics)) {
        if (USER_TABLE_KEYS.has(k)) {
          const col = USER_COLUMN_MAP[k] ?? k;
          usersUpdate[col] = v;
        } else basicProfilesUpdate[k] = v;
      }
      if (Object.keys(usersUpdate).length > 0) {
        updatePromises.push(
          supabase
            .from('users')
            .update(usersUpdate)
            .eq('id', user.id)
            .select()
            .single()
            .then(({ data, error }) => {
              if (error) {
                throw new AppError(
                  500,
                  `Failed to update users: ${error.message}`,
                  'UPDATE_FAILED'
                );
              }
              results.basics = { ...(results.basics || {}), ...data };
            })
        );
      }
      if (Object.keys(basicProfilesUpdate).length > 0) {
        updatePromises.push(
          upsertProfileTable('basic_profiles', user.id, basicProfilesUpdate).then(
            (data) => {
              results.basics = { ...(results.basics || {}), ...data };
            }
          )
        );
      }
    }

    if (sindhi && Object.keys(sindhi).length > 0) {
      updatePromises.push(
        upsertProfileTable('sindhi_profiles', user.id, sindhi).then((data) => {
          results.sindhi = data;
        })
      );
    }

    if (chatti && Object.keys(chatti).length > 0) {
      updatePromises.push(
        upsertProfileTable('chatti_profiles', user.id, chatti).then((data) => {
          results.chatti = data;
        })
      );
    }

    if (personality && Object.keys(personality).length > 0) {
      updatePromises.push(
        upsertProfileTable('personality_profiles', user.id, personality).then(
          (data) => {
            results.personality = data;
          }
        )
      );
    }

    if (settings && Object.keys(settings).length > 0) {
      updatePromises.push(
        upsertProfileTable('user_settings', user.id, settings).then((data) => {
          results.settings = data;
        })
      );
    }

    // userFields splits between users (intent) and basic_profiles (education,
    // occupation, company, religion).
    if (userFields && Object.keys(userFields).length > 0) {
      const USER_TABLE_KEYS = new Set(['intent', 'is_snoozed']);
      const usersUpdate: Record<string, any> = {};
      const basicProfilesUpdate: Record<string, any> = {};
      for (const [k, v] of Object.entries(userFields)) {
        if (USER_TABLE_KEYS.has(k)) usersUpdate[k] = v;
        else basicProfilesUpdate[k] = v;
      }
      if (Object.keys(usersUpdate).length > 0) {
        updatePromises.push(
          supabase
            .from('users')
            .update(usersUpdate)
            .eq('id', user.id)
            .select()
            .single()
            .then(({ data, error }) => {
              if (error) {
                throw new AppError(
                  500,
                  `Failed to update users (intent): ${error.message}`,
                  'UPDATE_FAILED'
                );
              }
              results.user = { ...(results.user || {}), ...data };
            })
        );
      }
      if (Object.keys(basicProfilesUpdate).length > 0) {
        updatePromises.push(
          upsertProfileTable('basic_profiles', user.id, basicProfilesUpdate).then(
            (data) => {
              results.user = { ...(results.user || {}), ...data };
            }
          )
        );
      }
    }

    await Promise.all(updatePromises);

    // Recalculate profile completeness
    const profileData = await fetchProfileData(user.id);
    const completeness = calculateCompleteness(profileData);

    // Onboarding is considered complete once the mandatory basics exist
    // (name + date of birth + gender). Only ever flip needs_onboarding to
    // false — never back to true — so a later profile edit that clears a
    // field can't kick an existing user back into the onboarding flow.
    const b = profileData.basics as Record<string, unknown>;
    const onboardingComplete = Boolean(
      b.display_name && b.date_of_birth && b.gender
    );

    const userUpdate: Record<string, unknown> = {
      profile_completeness: completeness,
      updated_at: new Date().toISOString(),
    };
    if (onboardingComplete) userUpdate.needs_onboarding = false;

    await supabase.from('users').update(userUpdate).eq('id', user.id);

    // Invalidate cultural score cache if culturally-relevant fields changed
    if (basics || sindhi || chatti || userFields) {
      await invalidateCulturalScoreCache(user.id);
    }

    res.json({
      success: true,
      data: {
        updated: results,
        profileCompleteness: completeness,
      },
    });
  })
);

// ─── POST /v1/me/media ──────────────────────────────────────────────────────────
// Upload a single photo or video. Photos are resized to 3 WebP sizes,
// EXIF-stripped, and moderation-checked via Sightengine.
// Limits: max 6 photos + 1 video per user.

router.post(
  '/media',
  authenticate,
  rateLimit({ maxRequests: 20, windowSeconds: 60, keyPrefix: 'rl_media' }),
  uploadMedia.single('file'),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const file = req.file;

    if (!file) {
      throw new AppError(400, 'No file uploaded', 'NO_FILE');
    }

    const isVideo = ALLOWED_VIDEO_MIMES.includes(file.mimetype);

    // Check existing media counts
    const { data: existingPhotos } = await supabase
      .from('photos')
      .select('id, is_video')
      .eq('user_id', user.id);

    const photos = (existingPhotos || []).filter((p: any) => !p.is_video);
    const videos = (existingPhotos || []).filter((p: any) => p.is_video);

    if (isVideo && videos.length >= MAX_VIDEOS) {
      throw new AppError(
        400,
        `Maximum ${MAX_VIDEOS} video allowed. Delete your existing video first.`,
        'MAX_VIDEOS'
      );
    }

    if (!isVideo && photos.length >= MAX_PHOTOS) {
      throw new AppError(
        400,
        `Maximum ${MAX_PHOTOS} photos allowed. You currently have ${photos.length}.`,
        'MAX_PHOTOS'
      );
    }

    const mediaId = uuidv4();
    const basePath = `users/${user.id}/media/${mediaId}`;

    if (isVideo) {
      // Upload video as-is (no server-side transcoding)
      const ext = file.mimetype === 'video/mp4' ? 'mp4' : 'webm';
      const videoPath = `${basePath}/video.${ext}`;

      const { error: uploadError } = await supabase.storage
        .from('photos')
        .upload(videoPath, file.buffer, {
          contentType: file.mimetype,
          upsert: true,
        });

      if (uploadError) {
        throw new AppError(
          500,
          'Failed to upload video to storage',
          'UPLOAD_FAILED'
        );
      }

      const { data: videoUrl } = supabase.storage
        .from('photos')
        .getPublicUrl(videoPath);

      const { data: mediaRecord, error: insertError } = await supabase
        .from('photos')
        .insert({
          id: mediaId,
          user_id: user.id,
          url_original: videoUrl.publicUrl,
          url_medium: videoUrl.publicUrl,
          url_thumb: videoUrl.publicUrl,
          is_primary: false,
          is_video: true,
          sort_order: (existingPhotos?.length || 0),
        })
        .select()
        .single();

      if (insertError) {
        throw new AppError(
          500,
          'Failed to save video record',
          'MEDIA_SAVE_FAILED'
        );
      }

      res.status(201).json({
        success: true,
        data: { media: mediaRecord },
      });
      return;
    }

    // ── Image processing pipeline ──

    // 1. Moderation check on the raw image
    const moderation = await checkImageModeration(file.buffer);
    if (!moderation.safe) {
      throw new AppError(
        400,
        'Image was rejected by our content moderation system. Please upload an appropriate photo.',
        'CONTENT_REJECTED'
      );
    }

    // 2. Resize to 3 WebP sizes, strip EXIF metadata
    const [thumb, medium, large] = await Promise.all([
      sharp(file.buffer)
        .rotate() // auto-rotate based on EXIF
        .resize(IMAGE_SIZES.thumb.width, undefined, {
          fit: 'inside',
          withoutEnlargement: true,
        })
        .webp({ quality: IMAGE_SIZES.thumb.quality })
        .withMetadata({ exif: undefined } as any) // strip EXIF
        .toBuffer(),
      sharp(file.buffer)
        .rotate()
        .resize(IMAGE_SIZES.medium.width, undefined, {
          fit: 'inside',
          withoutEnlargement: true,
        })
        .webp({ quality: IMAGE_SIZES.medium.quality })
        .withMetadata({ exif: undefined } as any)
        .toBuffer(),
      sharp(file.buffer)
        .rotate()
        .resize(IMAGE_SIZES.large.width, undefined, {
          fit: 'inside',
          withoutEnlargement: true,
        })
        .webp({ quality: IMAGE_SIZES.large.quality })
        .withMetadata({ exif: undefined } as any)
        .toBuffer(),
    ]);

    // 3. Upload all 3 sizes to Supabase Storage
    const [thumbRes, medRes, largeRes] = await Promise.all([
      supabase.storage.from('photos').upload(`${basePath}/thumb.webp`, thumb, {
        contentType: 'image/webp',
        upsert: true,
      }),
      supabase.storage
        .from('photos')
        .upload(`${basePath}/medium.webp`, medium, {
          contentType: 'image/webp',
          upsert: true,
        }),
      supabase.storage
        .from('photos')
        .upload(`${basePath}/large.webp`, large, {
          contentType: 'image/webp',
          upsert: true,
        }),
    ]);

    if (thumbRes.error || medRes.error || largeRes.error) {
      console.error('[/me/media] storage upload failed:', {
        thumb: thumbRes.error,
        medium: medRes.error,
        large: largeRes.error,
      });
      throw new AppError(
        500,
        'Failed to upload images to storage',
        'UPLOAD_FAILED'
      );
    }

    // 4. Get public URLs
    const { data: thumbUrl } = supabase.storage
      .from('photos')
      .getPublicUrl(`${basePath}/thumb.webp`);
    const { data: medUrl } = supabase.storage
      .from('photos')
      .getPublicUrl(`${basePath}/medium.webp`);
    const { data: largeUrl } = supabase.storage
      .from('photos')
      .getPublicUrl(`${basePath}/large.webp`);

    // 5. Create photo record
    const currentCount = photos.length;
    const { data: photoRecord, error: insertError } = await supabase
      .from('photos')
      .insert({
        id: mediaId,
        user_id: user.id,
        url_thumb: thumbUrl.publicUrl,
        url_medium: medUrl.publicUrl,
        url_original: largeUrl.publicUrl,
        is_primary: currentCount === 0, // first photo is primary
        is_video: false,
        sort_order: (existingPhotos?.length || 0),
      })
      .select()
      .single();

    if (insertError) {
      throw new AppError(
        500,
        'Failed to save photo record',
        'MEDIA_SAVE_FAILED'
      );
    }

    // 6. Recalculate profile completeness (photos may affect it indirectly)
    const profileData = await fetchProfileData(user.id);
    const completeness = calculateCompleteness(profileData);

    await supabase
      .from('users')
      .update({ profile_completeness: completeness })
      .eq('id', user.id);

    res.status(201).json({
      success: true,
      data: {
        media: photoRecord,
        profileCompleteness: completeness,
      },
    });
  })
);

// ─── DELETE /v1/me/media/:id ────────────────────────────────────────────────────
// Delete a photo or video by ID. Blocks deletion of the last remaining photo.

router.delete(
  '/media/:id',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { id } = req.params;

    // Verify ownership
    const { data: media, error: findError } = await supabase
      .from('photos')
      .select('*')
      .eq('id', id)
      .eq('user_id', user.id)
      .single();

    if (findError || !media) {
      throw new AppError(404, 'Media not found', 'MEDIA_NOT_FOUND');
    }

    // If it's a photo (not video), check minimum photo count
    if (!media.is_video) {
      const { data: allPhotos } = await supabase
        .from('photos')
        .select('id')
        .eq('user_id', user.id)
        .eq('is_video', false);

      if (allPhotos && allPhotos.length <= 1) {
        throw new AppError(
          400,
          'Cannot delete your only photo. Upload another first.',
          'MIN_PHOTOS'
        );
      }
    }

    // Delete from Supabase Storage
    const basePath = `users/${user.id}/media/${id}`;
    if (media.is_video) {
      // Try both extensions
      await supabase.storage
        .from('photos')
        .remove([`${basePath}/video.mp4`, `${basePath}/video.webm`]);
    } else {
      await supabase.storage
        .from('photos')
        .remove([
          `${basePath}/thumb.webp`,
          `${basePath}/medium.webp`,
          `${basePath}/large.webp`,
        ]);
    }

    // Delete the database record
    await supabase.from('photos').delete().eq('id', id);

    // If deleted photo was the primary, promote the next one
    if (media.is_primary && !media.is_video) {
      const { data: nextPhoto } = await supabase
        .from('photos')
        .select('id')
        .eq('user_id', user.id)
        .eq('is_video', false)
        .order('sort_order')
        .limit(1)
        .single();

      if (nextPhoto) {
        await supabase
          .from('photos')
          .update({ is_primary: true })
          .eq('id', nextPhoto.id);
      }
    }

    res.json({
      success: true,
      message: 'Media deleted successfully',
    });
  })
);

// ─── POST /v1/me/verify ─────────────────────────────────────────────────────────
// Selfie-based profile verification via AWS Rekognition.
// Compares the uploaded selfie to the user's primary photo.
// Max 3 attempts per day. Selfie is never persisted.

router.post(
  '/verify',
  authenticate,
  rateLimit({
    maxRequests: MAX_VERIFY_ATTEMPTS_PER_DAY,
    windowSeconds: 86400, // 24 hours
    keyPrefix: 'rl_verify',
  }),
  uploadSelfie.single('selfie'),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const selfieFile = req.file;

    if (!selfieFile) {
      throw new AppError(400, 'Selfie image is required', 'NO_SELFIE');
    }

    // Check if already verified
    const { data: userData } = await supabase
      .from('users')
      .select('is_verified')
      .eq('id', user.id)
      .single();

    if (userData?.is_verified) {
      throw new AppError(
        400,
        'Your profile is already verified',
        'ALREADY_VERIFIED'
      );
    }

    // Get primary photo
    const { data: primaryPhoto } = await supabase
      .from('photos')
      .select('url_original')
      .eq('user_id', user.id)
      .eq('is_primary', true)
      .eq('is_video', false)
      .single();

    if (!primaryPhoto) {
      throw new AppError(
        400,
        'You need a primary photo before verifying your profile',
        'NO_PRIMARY_PHOTO'
      );
    }

    // Download primary photo for comparison
    const photoResponse = await fetch(primaryPhoto.url_original);
    if (!photoResponse.ok) {
      throw new AppError(
        500,
        'Failed to retrieve primary photo for comparison',
        'PHOTO_FETCH_FAILED'
      );
    }
    const primaryPhotoBuffer = Buffer.from(
      await photoResponse.arrayBuffer()
    );

    // Normalize the selfie (strip EXIF, convert to JPEG for Rekognition)
    const selfieBuffer = await sharp(selfieFile.buffer)
      .rotate()
      .jpeg({ quality: 90 })
      .toBuffer();

    // Compare faces using AWS Rekognition
    let comparisonResult: { match: boolean; similarity: number };
    try {
      comparisonResult = await compareFaces(selfieBuffer, primaryPhotoBuffer);
    } catch (err: any) {
      // Handle specific Rekognition errors
      if (
        err.name === 'InvalidParameterException' ||
        err.message?.includes('no faces')
      ) {
        throw new AppError(
          400,
          'Could not detect a face in one or both images. Please use a clear, well-lit photo showing your face.',
          'FACE_NOT_DETECTED'
        );
      }
      console.error('[Verify] Rekognition error:', err.message);
      throw new AppError(
        500,
        'Face verification service is temporarily unavailable. Please try again later.',
        'VERIFICATION_SERVICE_ERROR'
      );
    }

    // Selfie buffer is intentionally NOT stored — it exists only in memory
    // and will be garbage collected after this request completes.

    if (!comparisonResult.match) {
      res.json({
        success: false,
        error: {
          code: 'VERIFICATION_FAILED',
          message:
            'The selfie did not match your primary photo closely enough. Please try again with better lighting and a clearer angle.',
        },
        data: {
          similarity: Math.round(comparisonResult.similarity),
          threshold: REKOGNITION_SIMILARITY_THRESHOLD,
        },
      });
      return;
    }

    // Verification passed — update user record
    await supabase
      .from('users')
      .update({
        is_verified: true,
        verified_at: new Date().toISOString(),
      })
      .eq('id', user.id);

    res.json({
      success: true,
      message: 'Profile verified successfully',
      data: {
        isVerified: true,
        verifiedAt: new Date().toISOString(),
        similarity: Math.round(comparisonResult.similarity),
      },
    });
  })
);

// ─── GET /v1/me/export ──────────────────────────────────────────────────────────
// GDPR-compliant data export. Returns all user data as a single JSON object.

router.get(
  '/export',
  authenticate,
  rateLimit({ maxRequests: 2, windowSeconds: 3600, keyPrefix: 'rl_export' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;

    const [
      { data: userData },
      { data: basics },
      { data: sindhi },
      { data: chatti },
      { data: personality },
      { data: photos },
      { data: settings },
      { data: privileges },
      { data: safety },
      { data: actions },
      { data: matches },
      { data: messages },
    ] = await Promise.all([
      supabase.from('users').select('*').eq('id', user.id).single(),
      supabase
        .from('basic_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('sindhi_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('chatti_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('personality_profiles')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('photos')
        .select('*')
        .eq('user_id', user.id)
        .order('sort_order'),
      supabase
        .from('user_settings')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('user_privileges')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase
        .from('user_safety')
        .select('*')
        .eq('user_id', user.id)
        .single(),
      supabase.from('actions').select('*').eq('actor_id', user.id),
      supabase
        .from('matches')
        .select('*')
        .or(`user_a_id.eq.${user.id},user_b_id.eq.${user.id}`),
      supabase.from('messages').select('*').eq('sender_id', user.id),
    ]);

    // Set response headers for download
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="mitimati-data-export-${user.id}.json"`
    );
    res.setHeader('Content-Type', 'application/json');

    res.json({
      success: true,
      data: {
        exportedAt: new Date().toISOString(),
        user: userData,
        profile: {
          basics,
          sindhi,
          chatti,
          personality,
        },
        photos: photos || [],
        settings,
        privileges,
        safety,
        actions: actions || [],
        matches: matches || [],
        messages: messages || [],
      },
    });
  })
);

// ─── POST /v1/me/fcm-token ──────────────────────────────────────────────────────
// Register or update the user's FCM device token for push notifications.

const fcmTokenSchema = z.object({
  token: z.string().min(10).max(4096),
  platform: z.enum(['ios', 'android', 'web']).optional(),
});

router.post(
  '/fcm-token',
  authenticate,
  validate(fcmTokenSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { token, platform } = req.body;

    const { error } = await supabase
      .from('user_fcm_tokens')
      .upsert(
        {
          user_id: user.id,
          fcm_token: token,
          platform: platform || null,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id' }
      );

    if (error) {
      throw new AppError(500, 'Failed to register FCM token', 'FCM_REGISTER_FAILED');
    }

    res.json({ success: true });
  })
);

export default router;
