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

const uploadVoiceIntro = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024, // 5 MB ≈ well over 30s of AAC
    files: 1,
  },
  fileFilter: (_req, file, cb) => {
    const allowed = ['audio/m4a', 'audio/mp4', 'audio/x-m4a', 'audio/aac', 'audio/mpeg', 'audio/webm', 'audio/ogg', 'audio/wav'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new AppError(400, 'Voice intro must be an audio file', 'INVALID_FILE_TYPE'));
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
    // Previously had no schema slot, so they could never be saved. These flow
    // to basic_profiles via the generic loop (not in USER_TABLE_KEYS).
    want_kids: z.string().max(50).nullable().optional(),
    settling: z.string().max(50).nullable().optional(),
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
    // Previously had no schema slot. generation is CHECK-constrained in the DB
    // (migration 014) so a permissive string is safe; the DB enforces the enum.
    generation: z.string().max(20).nullable().optional(),
    family_origin_city: z.string().max(100).nullable().optional(),
    family_origin_country: z.string().max(100).nullable().optional(),
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
    languages: z.array(z.string().max(50)).max(20).optional(),
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
    // Shown in both clients' filter UI but previously had no column, so they
    // could not be saved OR applied (discovery.ts now reads these names).
    generation_filter: z.string().max(20).nullable().optional(),
    family_plans_filter: z.string().max(50).nullable().optional(),
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
  // Only count fields the user can ACTUALLY fill through onboarding + Edit
  // Profile, so a diligent user reaches 100%. The old list counted fields
  // with no UI (state, mother_tongue, joint_family_preference,
  // cultural_activities, traditional_attire, pet_preference) — making 100%
  // unreachable and the bar "stuck" ~79% — while ignoring fields users do
  // fill (education, occupation, religion, smoking, drinking, exercise,
  // want_kids, settling, languages).
  const fields: Array<{ table: keyof CompletenessData; field: string }> = [
    // Identity (onboarding)
    { table: 'basics', field: 'display_name' },
    { table: 'basics', field: 'date_of_birth' },
    { table: 'basics', field: 'gender' },
    { table: 'basics', field: 'city' },
    { table: 'basics', field: 'bio' },
    { table: 'basics', field: 'height_cm' },
    // Basics (Edit Profile)
    { table: 'basics', field: 'education' },
    { table: 'basics', field: 'occupation' },
    { table: 'basics', field: 'religion' },
    // Lifestyle
    { table: 'basics', field: 'smoking' },
    { table: 'basics', field: 'drinking' },
    { table: 'basics', field: 'exercise' },
    { table: 'basics', field: 'want_kids' },
    { table: 'basics', field: 'settling' },
    // Sindhi identity
    { table: 'sindhi', field: 'sindhi_fluency' },
    { table: 'sindhi', field: 'sindhi_dialect' },
    { table: 'sindhi', field: 'gotra' },
    { table: 'sindhi', field: 'community_sub_group' },
    { table: 'sindhi', field: 'generation' },
    { table: 'sindhi', field: 'family_origin_city' },
    { table: 'sindhi', field: 'family_origin_country' },
    // Cultural
    { table: 'chatti', field: 'family_values' },
    { table: 'chatti', field: 'food_preference' },
    { table: 'chatti', field: 'festivals_celebrated' },
    { table: 'chatti', field: 'cuisine_preferences' },
    // Personality
    { table: 'personality', field: 'interests' },
    { table: 'personality', field: 'music_preferences' },
    { table: 'personality', field: 'movie_genres' },
    { table: 'personality', field: 'travel_style' },
    { table: 'personality', field: 'languages' },
  ];

  const total = fields.length; // 30, all UI-fillable
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
  // These tables use user_id as PRIMARY KEY. Use a single ATOMIC upsert
  // (INSERT ... ON CONFLICT DO UPDATE) — the previous check-then-insert
  // raced two concurrent PATCH /me calls (double-tapped onboarding submit):
  // both saw "no row", both INSERTed, the loser got a duplicate-key 500 and
  // onboarding only succeeded on a manual retry.
  const { data, error } = await supabase
    .from(table)
    .upsert({ user_id: userId, ...fields }, { onConflict: 'user_id' })
    .select()
    .single();

  if (error) {
    throw new AppError(
      500,
      `Failed to save ${table}: ${error.message}`,
      'UPSERT_FAILED'
    );
  }
  return data!;
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
        // Server-driven feature flags so clients hide UI for capabilities that
        // aren't wired up in this environment (e.g. selfie verification needs
        // AWS Rekognition creds). Flip a flag on the server and the UI appears
        // without shipping an app update.
        capabilities: {
          selfie_verification: !!(
            process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY
          ),
        },
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
          // DUAL-WRITE: discovery/inbox/admin build cards from
          // basic_profiles.* — writing identity only to users left
          // basic_profiles permanently empty, so the feed 400'd with
          // PROFILE_INCOMPLETE for everyone (found in the post-008 runbook).
          basicProfilesUpdate[k] = v;
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
        if (USER_TABLE_KEYS.has(k)) {
          usersUpdate[k] = v;
          // Cards read intent from basic_profiles — mirror it (is_snoozed
          // stays users-only)
          if (k === 'intent') basicProfilesUpdate[k] = v;
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

// ─── PATCH /v1/me/media/:id/primary ─────────────────────────────────────────────
// Make one of your photos the primary (profile) photo. Videos can't be primary.

router.patch(
  '/media/:id/primary',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { id } = req.params;

    const { data: media, error: findError } = await supabase
      .from('photos')
      .select('id, is_video, is_primary')
      .eq('id', id)
      .eq('user_id', user.id)
      .single();

    if (findError || !media) {
      throw new AppError(404, 'Media not found', 'MEDIA_NOT_FOUND');
    }
    if (media.is_video) {
      throw new AppError(400, 'Videos cannot be the primary photo', 'PRIMARY_MUST_BE_PHOTO');
    }

    if (!media.is_primary) {
      // Promote FIRST, then demote the others. If the process dies between
      // the two statements the user briefly has two primaries (harmless —
      // readers take .eq(is_primary, true).limit(1)) instead of zero
      // (which breaks chat headers, Liked You cards and selfie verification).
      const { error: promoteError } = await supabase
        .from('photos')
        .update({ is_primary: true })
        .eq('id', id)
        .eq('user_id', user.id);
      if (promoteError) {
        throw new AppError(500, 'Failed to update primary photo', 'PRIMARY_UPDATE_FAILED');
      }
      await supabase
        .from('photos')
        .update({ is_primary: false })
        .eq('user_id', user.id)
        .neq('id', id);
    }

    res.json({ success: true, data: { primary_photo_id: id } });
  })
);

// ─── POST /v1/me/media/reorder ──────────────────────────────────────────────────
// Persist a new photo order. Body: { photo_ids: [id, id, ...] } in desired
// order; sort_order is rewritten to the array index. Every id must belong to
// the caller (partial lists are allowed — unlisted media keep their order
// after the listed ones only in the sense of retaining old sort values).

const reorderSchema = z.object({
  photo_ids: z.array(z.string().uuid('Invalid photo ID')).min(1).max(10),
});

router.post(
  '/media/reorder',
  authenticate,
  validate(reorderSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { photo_ids: photoIds } = req.body as { photo_ids: string[] };

    const { data: mine } = await supabase
      .from('photos')
      .select('id')
      .eq('user_id', user.id);

    const myIds = new Set((mine || []).map((p: any) => p.id));
    for (const pid of photoIds) {
      if (!myIds.has(pid)) {
        throw new AppError(400, 'Unknown photo in reorder list', 'INVALID_PHOTO_ID');
      }
    }

    await Promise.all(
      photoIds.map((pid, i) =>
        supabase.from('photos').update({ sort_order: i }).eq('id', pid).eq('user_id', user.id),
      ),
    );

    res.json({ success: true, data: { order: photoIds } });
  })
);

// ─── GET /v1/me/verify/challenge ────────────────────────────────────────────────
// gesture challenge: the server picks a random pose the user must
// copy in their verification selfie. Stored in Redis for 10 minutes; the selfie
// submission must reference the same pose. (The face is matched automatically
// by Rekognition; the pose keeps the selfie LIVE — a photo-of-a-photo won't be
// striking a pose we only just asked for.)

const VERIFY_POSES = [
  { id: 'peace', emoji: '✌️', name: 'Peace sign', instruction: 'Hold up a peace sign next to your face' },
  { id: 'thumbs_up', emoji: '👍', name: 'Thumbs up', instruction: 'Give a thumbs up next to your face' },
  { id: 'ok_sign', emoji: '👌', name: 'OK sign', instruction: 'Make an OK sign next to your face' },
  { id: 'open_palm', emoji: '✋', name: 'Open palm', instruction: 'Hold your open palm up beside your face' },
  { id: 'finger_heart', emoji: '🫰', name: 'Finger heart', instruction: 'Make a finger heart near your cheek' },
  { id: 'salute', emoji: '🫡', name: 'Salute', instruction: 'Salute with your hand at your forehead' },
  { id: 'fist', emoji: '✊', name: 'Fist', instruction: 'Hold a closed fist up next to your face' },
  { id: 'crossed_fingers', emoji: '🤞', name: 'Crossed fingers', instruction: 'Cross your fingers next to your face' },
] as const;

const VERIFY_CHALLENGE_TTL_SECONDS = 600;

router.get(
  '/verify/challenge',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const pose = VERIFY_POSES[Math.floor(Math.random() * VERIFY_POSES.length)];
    try {
      await redis.set(`verify_pose:${user.id}`, pose.id, 'EX', VERIFY_CHALLENGE_TTL_SECONDS);
    } catch {
      // Redis down → challenge can't be enforced; still return a pose so the
      // UX works. POST /verify treats a missing stored pose as unenforced.
    }
    res.json({
      success: true,
      data: {
        pose_id: pose.id,
        emoji: pose.emoji,
        name: pose.name,
        instruction: pose.instruction,
        expires_in: VERIFY_CHALLENGE_TTL_SECONDS,
      },
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

    // Face comparison runs on AWS Rekognition — without credentials the
    // feature is cleanly "coming soon" rather than a scary failure.
    if (!process.env.AWS_ACCESS_KEY_ID || !process.env.AWS_SECRET_ACCESS_KEY) {
      throw new AppError(
        503,
        'Selfie verification is coming soon — hang tight!',
        'VERIFICATION_UNAVAILABLE'
      );
    }

    if (!selfieFile) {
      throw new AppError(400, 'Selfie image is required', 'NO_SELFIE');
    }

    // Enforce the gesture challenge when one is outstanding: the submission
    // must reference the pose we issued (keeps the selfie live/fresh).
    const submittedPose = (req.body?.pose_id as string | undefined) || null;
    let issuedPose: string | null = null;
    try {
      issuedPose = await redis.get(`verify_pose:${user.id}`);
    } catch {
      // Redis down → can't enforce; proceed on face match alone.
    }
    if (issuedPose && submittedPose !== issuedPose) {
      throw new AppError(
        400,
        'Your verification challenge expired or does not match. Start again and copy the pose shown.',
        'POSE_CHALLENGE_MISMATCH'
      );
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
    // Rekognition only accepts JPEG/PNG and the photo pipeline stores WebP —
    // normalize BOTH images to JPEG, not just the selfie.
    const primaryPhotoBuffer = await sharp(
      Buffer.from(await photoResponse.arrayBuffer())
    )
      .rotate()
      .jpeg({ quality: 90 })
      .toBuffer();

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
    await redis.del(`verify_pose:${user.id}`).then(() => {}, () => {});

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

    // Table columns: token (NOT fcm_token) with UNIQUE(user_id, platform) —
    // the old insert wrote a nonexistent column against a nonexistent
    // constraint, so registration always 500'd.
    const { error } = await supabase
      .from('user_fcm_tokens')
      .upsert(
        {
          user_id: user.id,
          token,
          platform: platform || 'android',
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,platform' }
      );

    if (error) {
      throw new AppError(500, 'Failed to register FCM token', 'FCM_REGISTER_FAILED');
    }

    res.json({ success: true });
  })
);

// ─── POST /v1/me/voice-intro ────────────────────────────────────────────────────
// Upload a short voice introduction (Hinge-style). Stored in the photos
// bucket under the user's folder; URL saved on personality_profiles.

router.post(
  '/voice-intro',
  authenticate,
  rateLimit({ maxRequests: 10, windowSeconds: 3600, keyPrefix: 'rl_voice_intro' }),
  uploadVoiceIntro.single('audio'),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const file = req.file;

    if (!file) {
      throw new AppError(400, 'No audio file uploaded', 'NO_FILE');
    }

    const extMap: Record<string, string> = {
      'audio/m4a': 'm4a', 'audio/mp4': 'm4a', 'audio/x-m4a': 'm4a',
      'audio/aac': 'aac', 'audio/mpeg': 'mp3', 'audio/webm': 'webm',
      'audio/ogg': 'ogg', 'audio/wav': 'wav',
    };
    const ext = extMap[file.mimetype] || 'm4a';
    // Timestamped path so a re-record busts CDN/client caches
    const path = `${user.id}/voice_intro_${Date.now()}.${ext}`;

    const { error: uploadError } = await supabase.storage
      .from('photos')
      .upload(path, file.buffer, { contentType: file.mimetype, upsert: true });

    if (uploadError) {
      throw new AppError(500, 'Failed to upload voice intro', 'UPLOAD_FAILED');
    }

    const { data: urlData } = supabase.storage.from('photos').getPublicUrl(path);

    await upsertProfileTable('personality_profiles', user.id, {
      voice_intro_url: urlData.publicUrl,
    });

    res.status(201).json({
      success: true,
      data: { voiceIntroUrl: urlData.publicUrl },
    });
  })
);

// ─── DELETE /v1/me/voice-intro ──────────────────────────────────────────────────

router.delete(
  '/voice-intro',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    await upsertProfileTable('personality_profiles', user.id, {
      voice_intro_url: null,
    });
    res.json({ success: true });
  })
);

// ─── POST /v1/me/test-push ──────────────────────────────────────────────────────
// Send yourself a test push notification (debugging the FCM pipeline).
// Own device only; rate limited.

router.post(
  '/test-push',
  authenticate,
  rateLimit({ maxRequests: 3, windowSeconds: 3600, keyPrefix: 'rl_test_push' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;

    // The online flag suppresses pushes; a test must always attempt delivery
    try {
      const { redis } = await import('../config/redis');
      await redis.del(`online:${user.id}`);
    } catch {
      // Redis down — sendPush will handle it
    }

    const { sendPush } = await import('../services/notifications');
    const sent = await sendPush(user.id, 'new_message', {
      title: 'MitiMaiti test 🔔',
      body: 'Push notifications are working! Jeko chavan, sacho aa.',
    });

    res.json({
      success: true,
      data: {
        sent,
        hint: sent
          ? 'Delivered to FCM — check the device'
          : 'Not sent: no token registered, Firebase not configured, or daily cap reached',
      },
    });
  }),
);

export default router;
