import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { supabase } from '../config/supabase';
import { redis } from '../config/redis';
import { AppError, asyncHandler } from '../utils/errors';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { getCulturalScore } from '../services/scoring';
import { getKundliScore } from '../services/kundli';
import { AuthenticatedRequest, FeedCard, CulturalBadge, KundliTier, FamilyValues, FoodPreference, SindhiFluency } from '../types';
import { cityDistance } from '../utils/geo';

const router = Router();

// ─── Constants ──────────────────────────────────────────────────────────────────

const PAGE_SIZE = 20;
const PASSPORT_DURATION_DAYS = 7;
const COLD_CITY_THRESHOLD = 10;
const EXPLORE_INJECT_MIN = 2;
const EXPLORE_INJECT_MAX = 3;
const CULTURAL_CACHE_TTL = 3600;      // 1 hour
const PASS_WINDOW_DAYS = 30;
const INACTIVE_DAYS = 30;

// Feed score weights (NO premium tiers — everyone is equal)
const WEIGHT = {
  cultural: 0.50,
  completeness: 0.15,
  activity: 0.15,
  intent: 0.15,
  freshness: 0.05,
};

// Gold (85%+, matching assignBadge in services/scoring) interleave target positions
const GOLD_THRESHOLD = 85;
const GOLD_POSITIONS = [0, 4, 9, 14, 19];

// ─── Schemas ────────────────────────────────────────────────────────────────────

const passportSchema = z.object({
  city: z.string().min(1, 'City is required').max(100),
  country: z.string().min(1, 'Country is required').max(100),
});

// ─── Helpers ────────────────────────────────────────────────────────────────────

function calculateAge(dob: string): number {
  const birth = new Date(dob);
  const today = new Date();
  let age = today.getFullYear() - birth.getFullYear();
  const monthDiff = today.getMonth() - birth.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birth.getDate())) {
    age--;
  }
  return age;
}

/**
 * Build canonical cache key for a pair of users.
 * Ensures score(A,B) === score(B,A).
 */
function pairKey(prefix: string, idA: string, idB: string): string {
  const [first, second] = idA < idB ? [idA, idB] : [idB, idA];
  return `${prefix}:${first}:${second}`;
}

/**
 * Safe Redis GET — returns null if Redis is unavailable.
 */
async function safeRedisGet(key: string): Promise<string | null> {
  try {
    return await redis.get(key);
  } catch {
    return null;
  }
}

/**
 * Safe Redis SET — silently swallows errors.
 */
async function safeRedisSet(key: string, value: string, ttl: number): Promise<void> {
  try {
    await redis.set(key, value, 'EX', ttl);
  } catch {
    // Redis down — continue without caching
  }
}

/**
 * Safe Redis DEL — silently swallows errors.
 */
async function safeRedisDel(...keys: string[]): Promise<void> {
  try {
    if (keys.length > 0) await redis.del(...keys);
  } catch {
    // Redis down — continue
  }
}

// ─── Scoring Helpers ────────────────────────────────────────────────────────────

interface ScoredCandidate {
  userId: string;
  profile: any;
  userMeta: any;
  culturalScore: number;
  culturalBadge: CulturalBadge;
  kundliScore: number | null;
  kundliTier: KundliTier | null;
  feedScore: number;
}

/**
 * Get cached or compute cultural score for a pair.
 * Falls back to direct computation if Redis is down.
 */
async function getCachedCulturalScore(
  myId: string,
  otherId: string,
): Promise<{ total: number; badge: CulturalBadge }> {
  const key = pairKey('pair', myId, otherId);

  // Try Redis cache
  const cached = await safeRedisGet(key);
  if (cached) {
    try {
      const parsed = JSON.parse(cached);
      return { total: parsed.total, badge: parsed.badge };
    } catch {
      // Corrupted cache — recompute
    }
  }

  // Compute via scoring service (which has its own caching layer)
  try {
    const result = await getCulturalScore(myId, otherId);

    // Also cache in our pair key for fast feed access
    await safeRedisSet(key, JSON.stringify({ total: result.total, badge: result.badge }), CULTURAL_CACHE_TTL);

    return { total: result.total, badge: result.badge };
  } catch {
    return { total: 0, badge: 'none' };
  }
}

/**
 * Get cached kundli score for a pair via the kundli service.
 * Only used for card display, NOT for ranking.
 * The service handles its own Redis caching (24h TTL).
 */
async function getCachedKundliScore(
  myId: string,
  otherId: string,
): Promise<{ score: number | null; tier: KundliTier | null }> {
  try {
    const result = await getKundliScore(myId, otherId);
    if (!result) return { score: null, tier: null };
    return { score: result.total, tier: result.tier };
  } catch {
    return { score: null, tier: null };
  }
}

/**
 * Compute feed ranking score.
 * cultural 50% + profile_completeness 15% + activity 15% + intent 15% + freshness 5%
 */
function computeFeedScore(
  culturalScore: number,
  profileCompleteness: number,
  lastActiveAt: string,
  intentMatch: boolean,
  createdAt: string,
): number {
  // Normalize cultural score (0-100 -> 0-1)
  const culturalNorm = Math.min(culturalScore, 100) / 100;

  // Normalize completeness (0-100 -> 0-1)
  const completenessNorm = Math.min(profileCompleteness, 100) / 100;

  // Activity: decay over 7 days (0 = 7d+ inactive, 1 = just active)
  const lastActive = new Date(lastActiveAt).getTime();
  const now = Date.now();
  const daysSinceActive = (now - lastActive) / (1000 * 60 * 60 * 24);
  const activityNorm = Math.max(0, 1 - daysSinceActive / 7);

  // Intent match: binary
  const intentNorm = intentMatch ? 1 : 0;

  // Freshness: new accounts get a boost for 14 days
  const daysSinceCreation = (now - new Date(createdAt).getTime()) / (1000 * 60 * 60 * 24);
  const freshnessNorm = Math.max(0, 1 - daysSinceCreation / 14);

  const score =
    culturalNorm * WEIGHT.cultural +
    completenessNorm * WEIGHT.completeness +
    activityNorm * WEIGHT.activity +
    intentNorm * WEIGHT.intent +
    freshnessNorm * WEIGHT.freshness;

  return Math.round(score * 10000) / 10000;
}

/**
 * Interleave gold-badge profiles at positions ~1, 5, 10, 15, 20.
 * Fill remaining with great (65-89%) + normal profiles.
 */
function interleaveFeed(candidates: ScoredCandidate[]): ScoredCandidate[] {
  if (candidates.length <= 5) return candidates;

  const gold: ScoredCandidate[] = [];
  const great: ScoredCandidate[] = [];
  const normal: ScoredCandidate[] = [];

  for (const c of candidates) {
    if (c.culturalScore >= GOLD_THRESHOLD) gold.push(c);
    else if (c.culturalScore >= 65) great.push(c);
    else normal.push(c);
  }

  // Sort each tier by feedScore descending
  gold.sort((a, b) => b.feedScore - a.feedScore);
  great.sort((a, b) => b.feedScore - a.feedScore);
  normal.sort((a, b) => b.feedScore - a.feedScore);

  // Merge great + normal as the fill pool
  const fill = [...great, ...normal];

  const result: ScoredCandidate[] = new Array(candidates.length);
  let goldIdx = 0;
  let fillIdx = 0;

  for (let i = 0; i < candidates.length; i++) {
    if (GOLD_POSITIONS.includes(i) && goldIdx < gold.length) {
      result[i] = gold[goldIdx++];
    } else if (fillIdx < fill.length) {
      result[i] = fill[fillIdx++];
    } else if (goldIdx < gold.length) {
      // Ran out of fill, use remaining gold
      result[i] = gold[goldIdx++];
    }
  }

  // Any remaining gold profiles that didn't fit
  while (goldIdx < gold.length) {
    result.push(gold[goldIdx++]);
  }
  while (fillIdx < fill.length) {
    result.push(fill[fillIdx++]);
  }

  // Remove any undefined slots (shouldn't happen, but defensive)
  return result.filter(Boolean);
}

// ─── GET /v1/feed ───────────────────────────────────────────────────────────────

router.get(
  '/',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const lastUserId = (req.query.last_user_id as string) || null;

    // ── Step 0: Load current user's profile, settings, and metadata ─────────

    const [
      { data: myBasic },
      { data: mySettings },
      { data: myUser },
    ] = await Promise.all([
      supabase.from('basic_profiles').select('*').eq('user_id', user.id).single(),
      supabase.from('user_settings').select('*').eq('user_id', user.id).single(),
      supabase.from('users').select('id, created_at, profile_completeness').eq('id', user.id).single(),
    ]);

    if (!myBasic) {
      throw new AppError(400, 'Complete your profile before discovering matches', 'PROFILE_INCOMPLETE');
    }

    // Determine discovery city: passport mode or actual city
    let discoveryCity = myBasic.city;
    let isPassportMode = false;

    try {
      const passportData = await safeRedisGet(`passport:${user.id}`);
      if (passportData) {
        const parsed = JSON.parse(passportData);
        discoveryCity = parsed.city;
        isPassportMode = true;
      }
    } catch {
      // Check DB fallback
      if (mySettings?.passport_city) {
        const passportExpiry = mySettings.passport_expires
          ? new Date(mySettings.passport_expires)
          : null;
        if (passportExpiry && passportExpiry > new Date()) {
          discoveryCity = mySettings.passport_city;
          isPassportMode = true;
        }
      }
    }

    // ── Step 1: Hard filters — build exclusion set ──────────────────────────

    const now = new Date();
    const thirtyDaysAgo = new Date(now.getTime() - PASS_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();
    const inactiveThreshold = new Date(now.getTime() - INACTIVE_DAYS * 24 * 60 * 60 * 1000).toISOString();

    // Parallel exclusion queries
    const [
      { data: blocks },
      { data: passedRecently },
      { data: snoozedUsers },
      { data: incognitoLikedMe },
    ] = await Promise.all([
      // Blocked both directions
      supabase
        .from('blocked_users')
        .select('blocker_id, blocked_id')
        .or(`blocker_id.eq.${user.id},blocked_id.eq.${user.id}`),

      // Passed within 30 days
      supabase
        .from('actions')
        .select('target_id')
        .eq('actor_id', user.id)
        .eq('kind', 'pass')
        .gte('created_at', thirtyDaysAgo),

      // Users in snooze mode
      supabase
        .from('users')
        .select('id')
        .eq('is_snoozed', true),

      // Incognito users who liked me (exception: they SHOULD appear)
      supabase
        .from('actions')
        .select('actor_id')
        .eq('target_id', user.id)
        .eq('kind', 'like'),
    ]);

    const blockedIds = new Set<string>();
    (blocks || []).forEach((b: any) => {
      blockedIds.add(b.blocker_id === user.id ? b.blocked_id : b.blocker_id);
    });

    const passedIds = new Set<string>(
      (passedRecently || []).map((a: any) => a.target_id),
    );

    const snoozedIds = new Set<string>(
      (snoozedUsers || []).map((s: any) => s.id),
    );

    const incognitoExceptionIds = new Set<string>(
      (incognitoLikedMe || []).map((a: any) => a.actor_id),
    );

    // Users I've already liked (don't show again)
    const { data: alreadyLiked } = await supabase
      .from('actions')
      .select('target_id')
      .eq('actor_id', user.id)
      .eq('kind', 'like');

    const likedIds = new Set<string>(
      (alreadyLiked || []).map((a: any) => a.target_id),
    );

    // Combined hard exclusion set
    const hardExclude = new Set<string>([
      user.id,
      ...blockedIds,
      ...passedIds,
      ...likedIds,
    ]);

    // ── Step 2: Apply user's 16 discovery filters ───────────────────────────

    const ageMin = mySettings?.age_min ?? 18;
    const ageMax = mySettings?.age_max ?? 50;
    const maxDob = new Date(now.getFullYear() - ageMin, now.getMonth(), now.getDate())
      .toISOString().split('T')[0];
    const minDob = new Date(now.getFullYear() - ageMax - 1, now.getMonth(), now.getDate())
      .toISOString().split('T')[0];

    // Gender preference mapping
    const genderPref = mySettings?.gender_preference || 'everyone';

    // Build base query for candidate profiles
    let query = supabase
      .from('basic_profiles')
      .select(`
        user_id,
        display_name,
        date_of_birth,
        gender,
        bio,
        height_cm,
        city,
        state,
        country,
        intent,
        education,
        occupation,
        religion
      `)
      .gte('date_of_birth', minDob)
      .lte('date_of_birth', maxDob);

    // Gender filter
    if (genderPref === 'men') {
      query = query.eq('gender', 'man');
    } else if (genderPref === 'women') {
      query = query.eq('gender', 'woman');
    }
    // 'any' / 'everyone' = no gender filter

    // City filter for discovery
    query = query.eq('city', discoveryCity);

    // Intent filter from settings
    if (mySettings?.intent_filter) {
      query = query.eq('intent', mySettings.intent_filter);
    }

    // Religion filter from settings
    if (mySettings?.religion_filter) {
      query = query.eq('religion', mySettings.religion_filter);
    }

    // Verified only filter
    // (We'll apply this after joining with users table)
    const verifiedOnly: boolean = mySettings?.verified_only === true;

    // Height filters
    if (mySettings?.height_min) {
      query = query.gte('height_cm', mySettings.height_min);
    }
    if (mySettings?.height_max) {
      query = query.lte('height_cm', mySettings.height_max);
    }

    // Education filter
    if (mySettings?.education_filter) {
      query = query.eq('education', mySettings.education_filter);
    }

    // Cursor pagination
    if (lastUserId) {
      query = query.gt('user_id', lastUserId);
    }

    // Fetch 3x to account for exclusions
    const fetchSize = PAGE_SIZE * 3;
    query = query.limit(fetchSize).order('user_id');

    const { data: candidateProfiles, error: queryError } = await query;

    if (queryError) {
      throw new AppError(500, 'Failed to fetch discovery candidates', 'FEED_QUERY_ERROR');
    }

    // ── Filter out hard-excluded, banned, hidden, inactive, incognito ───────

    const candidateIds = (candidateProfiles || [])
      .filter((c: any) => !hardExclude.has(c.user_id))
      .map((c: any) => c.user_id);

    if (candidateIds.length === 0) {
      // Cold city check
      const { count: cityCount } = await supabase
        .from('basic_profiles')
        .select('*', { count: 'exact', head: true })
        .eq('city', discoveryCity);

      if ((cityCount || 0) < COLD_CITY_THRESHOLD) {
        return res.json({
          success: true,
          data: {
            cards: [],
            cursor: null,
            has_more: false,
            cold_city: true,
            city_profile_count: cityCount || 0,
            message: `Only ${cityCount || 0} profiles in ${discoveryCity}. Explore other cities!`,
          },
        });
      }

      return res.json({
        success: true,
        data: {
          cards: [],
          cursor: null,
          has_more: false,
          cold_city: false,
        },
      });
    }

    // Get user metadata (active status, ban status, verification, completeness, etc.)
    const { data: usersMeta } = await supabase
      .from('users')
      .select('id, is_banned, is_hidden, is_verified, is_online, profile_completeness, last_active, created_at')
      .in('id', candidateIds);

    const metaMap = new Map<string, any>();
    (usersMeta || []).forEach((u: any) => metaMap.set(u.id, u));

    // Get incognito status
    const { data: incognitoSettings } = await supabase
      .from('user_settings')
      .select('user_id, incognito_mode')
      .in('user_id', candidateIds);

    const incognitoMap = new Map<string, boolean>();
    (incognitoSettings || []).forEach((s: any) => {
      incognitoMap.set(s.user_id, s.incognito_mode === true);
    });

    // Apply soft filters from additional settings (drinking, smoking, kids, fluency, gotra, etc.)
    // These require joining sindhi_profiles and personality_profiles
    // Include the current user so gotra_filter='exclude_same' can compare
    // against MY gotra (candidates-only meant it always no-oped).
    const { data: sindhiProfiles } = await supabase
      .from('sindhi_profiles')
      .select('user_id, sindhi_fluency, gotra')
      .in('user_id', [...candidateIds, user.id]);

    const sindhiMap = new Map<string, any>();
    (sindhiProfiles || []).forEach((s: any) => sindhiMap.set(s.user_id, s));

    const { data: personalityProfiles } = await supabase
      .from('personality_profiles')
      .select('user_id, smoking, drinking, interests')
      .in('user_id', candidateIds);

    const personalityMap = new Map<string, any>();
    (personalityProfiles || []).forEach((p: any) => personalityMap.set(p.user_id, p));

    // Build the filtered candidate list
    const profileMap = new Map<string, any>();
    (candidateProfiles || []).forEach((c: any) => profileMap.set(c.user_id, c));

    const filteredCandidateIds: string[] = [];

    for (const cId of candidateIds) {
      const meta = metaMap.get(cId);
      if (!meta) continue;

      // Hard filter: banned, hidden
      if (meta.is_banned || meta.is_hidden) continue;

      // Hard filter: inactive 30d+
      if (meta.last_active && new Date(meta.last_active) < new Date(inactiveThreshold)) continue;

      // Hard filter: snoozed
      if (snoozedIds.has(cId)) continue;

      // Hard filter: incognito (unless they liked me)
      if (incognitoMap.get(cId) && !incognitoExceptionIds.has(cId)) continue;

      // Soft filter: verified only
      if (verifiedOnly && !meta.is_verified) continue;

      // Soft filter: smoking (case-insensitive — clients send display casing)
      if (mySettings?.smoking_filter) {
        const personality = personalityMap.get(cId);
        if (
          personality?.smoking &&
          personality.smoking.toLowerCase() !== mySettings.smoking_filter.toLowerCase()
        ) continue;
      }

      // Soft filter: drinking (case-insensitive)
      if (mySettings?.drinking_filter) {
        const personality = personalityMap.get(cId);
        if (
          personality?.drinking &&
          personality.drinking.toLowerCase() !== mySettings.drinking_filter.toLowerCase()
        ) continue;
      }

      // Soft filter: fluency minimum
      if (mySettings?.fluency_filter) {
        const sindhi = sindhiMap.get(cId);
        const fluencyRank: Record<string, number> = { native: 4, fluent: 3, basic: 2, none: 1 };
        const minFluency = fluencyRank[mySettings.fluency_filter] || 0;
        const candidateFluency = fluencyRank[sindhi?.sindhi_fluency] || 0;
        if (candidateFluency < minFluency) continue;
      }

      // Soft filter: gotra. 'exclude_same' hides same-gotra profiles
      // (traditionally incompatible); any other value shows only that gotra.
      if (mySettings?.gotra_filter === 'exclude_same') {
        const sindhi = sindhiMap.get(cId);
        const mySindhiData = sindhiMap.get(user.id);
        if (sindhi?.gotra && mySindhiData?.gotra && sindhi.gotra === mySindhiData.gotra) continue;
      } else if (mySettings?.gotra_filter) {
        const sindhi = sindhiMap.get(cId);
        if (!sindhi?.gotra || sindhi.gotra.toLowerCase() !== mySettings.gotra_filter.toLowerCase()) continue;
      }

      // Soft filter: dietary
      if (mySettings?.dietary_filter) {
        const profile = profileMap.get(cId);
        // dietary could be on personality or chatti; check personality for now
        const personality = personalityMap.get(cId);
        if (personality?.dietary && personality.dietary !== mySettings.dietary_filter) continue;
      }

      // Soft filter: kundli minimum score
      // Skip at filter stage; we check after computing kundli score below

      filteredCandidateIds.push(cId);
    }

    if (filteredCandidateIds.length === 0) {
      return res.json({
        success: true,
        data: {
          cards: [],
          cursor: null,
          has_more: false,
          cold_city: false,
        },
      });
    }

    // ── Step 3 & 4: Compute/fetch cultural + kundli scores ──────────────────

    const scored: ScoredCandidate[] = [];
    const kundliMin = mySettings?.kundli_min ?? 0;

    // Process in parallel batches of 10
    const BATCH_SIZE = 10;
    for (let i = 0; i < filteredCandidateIds.length; i += BATCH_SIZE) {
      const batch = filteredCandidateIds.slice(i, i + BATCH_SIZE);

      const batchResults = await Promise.allSettled(
        batch.map(async (cId) => {
          const profile = profileMap.get(cId);
          const meta = metaMap.get(cId);
          if (!profile || !meta) return null;

          // Cultural score
          const { total: culturalScore, badge: culturalBadge } =
            await getCachedCulturalScore(user.id, cId);

          // Kundli score (display only, NOT for ranking)
          const { score: kundliScore, tier: kundliTier } =
            await getCachedKundliScore(user.id, cId);

          // Kundli minimum filter
          if (kundliMin > 0 && kundliScore !== null && kundliScore < kundliMin) {
            return null;
          }

          // Step 5: Feed score
          const intentMatch = profile.intent === myBasic.intent;
          const feedScore = computeFeedScore(
            culturalScore,
            meta.profile_completeness || 0,
            meta.last_active || meta.created_at,
            intentMatch,
            meta.created_at,
          );

          return {
            userId: cId,
            profile,
            userMeta: meta,
            culturalScore,
            culturalBadge,
            kundliScore,
            kundliTier,
            feedScore,
          } as ScoredCandidate;
        }),
      );

      for (const result of batchResults) {
        if (result.status === 'fulfilled' && result.value) {
          scored.push(result.value);
        }
      }
    }

    // ── Step 6: Interleave gold at target positions ─────────────────────────

    const interleaved = interleaveFeed(scored);

    // Take top PAGE_SIZE
    const page = interleaved.slice(0, PAGE_SIZE);

    // ── Explore injection: 2-3 cards from other cities ──────────────────────

    let exploreCards: ScoredCandidate[] = [];

    if (page.length >= 5 && !isPassportMode) {
      const exploreCount = Math.floor(Math.random() * (EXPLORE_INJECT_MAX - EXPLORE_INJECT_MIN + 1)) + EXPLORE_INJECT_MIN;

      const allExcludeIds = new Set([...hardExclude, ...filteredCandidateIds]);

      let exploreQuery = supabase
        .from('basic_profiles')
        .select('user_id, display_name, date_of_birth, gender, bio, height_cm, city, state, country, intent, education, occupation, religion')
        .neq('city', discoveryCity)
        .gte('date_of_birth', minDob)
        .lte('date_of_birth', maxDob);

      // Apply same gender filter to explore candidates
      if (genderPref === 'men') {
        exploreQuery = exploreQuery.eq('gender', 'man');
      } else if (genderPref === 'women') {
        exploreQuery = exploreQuery.eq('gender', 'woman');
      }

      const { data: exploreCandidates } = await exploreQuery.limit(exploreCount * 3);

      if (exploreCandidates && exploreCandidates.length > 0) {
        const exploreFiltered = exploreCandidates.filter(
          (c: any) => !allExcludeIds.has(c.user_id) && !snoozedIds.has(c.user_id),
        );

        // Re-apply the same safety gates as the main feed: banned, hidden,
        // inactive 30d+, and incognito users must never surface via explore.
        const exploreIds = exploreFiltered.map((c: any) => c.user_id);
        const exploreMetaMap = new Map<string, any>();
        const exploreIncognito = new Set<string>();

        if (exploreIds.length > 0) {
          const [{ data: exploreMeta }, { data: exploreSettings }] = await Promise.all([
            supabase
              .from('users')
              .select('id, is_banned, is_hidden, is_verified, is_online, profile_completeness, last_active, created_at')
              .in('id', exploreIds),
            supabase
              .from('user_settings')
              .select('user_id, incognito_mode')
              .in('user_id', exploreIds),
          ]);
          (exploreMeta || []).forEach((u: any) => exploreMetaMap.set(u.id, u));
          (exploreSettings || []).forEach((s: any) => {
            if (s.incognito_mode === true) exploreIncognito.add(s.user_id);
          });
        }

        const exploreSafe = exploreFiltered.filter((c: any) => {
          const meta = exploreMetaMap.get(c.user_id);
          if (!meta) return false;
          if (meta.is_banned || meta.is_hidden) return false;
          if (meta.last_active && new Date(meta.last_active) < new Date(inactiveThreshold)) return false;
          if (exploreIncognito.has(c.user_id) && !incognitoExceptionIds.has(c.user_id)) return false;
          return true;
        });

        for (const ec of exploreSafe.slice(0, exploreCount)) {
          const { total: cs, badge: cb } = await getCachedCulturalScore(user.id, ec.user_id);
          const meta = exploreMetaMap.get(ec.user_id);
          exploreCards.push({
            userId: ec.user_id,
            profile: ec,
            userMeta: meta || { is_verified: false, profile_completeness: 0 },
            culturalScore: cs,
            culturalBadge: cb,
            kundliScore: null,
            kundliTier: null,
            feedScore: 0,
          });
        }
      }
    }

    // ── Cold city handling ───────────────────────────────────────────────────

    let coldCity = false;
    let cityProfileCount: number | undefined;

    if (page.length < COLD_CITY_THRESHOLD) {
      const { count } = await supabase
        .from('basic_profiles')
        .select('*', { count: 'exact', head: true })
        .eq('city', discoveryCity);

      if ((count || 0) < COLD_CITY_THRESHOLD) {
        coldCity = true;
        cityProfileCount = count || 0;
      }
    }

    // ── Build response: fetch photos and prompts for page candidates ────────

    const allPageIds = [...page.map((c) => c.userId), ...exploreCards.map((c) => c.userId)];

    const [
      { data: photos },
      { data: prompts },
      { data: interests },
      { data: dailyPromptAnswers },
      { data: nameSettings },
    ] = await Promise.all([
      supabase
        .from('photos')
        .select('user_id, url_medium, url_original, url_thumb, sort_order, is_primary, is_verified, is_video')
        .in('user_id', allPageIds)
        .order('sort_order')
        .limit(allPageIds.length * 6),
      supabase
        .from('prompt_answers')
        .select('user_id, answer, prompt_id')
        .in('user_id', allPageIds)
        .order('created_at', { ascending: false })
        .limit(allPageIds.length * 3),
      supabase
        .from('personality_profiles')
        .select('user_id, interests')
        .in('user_id', allPageIds),
      supabase
        .from('users')
        .select('id, daily_prompt_answer')
        .in('id', allPageIds),
      supabase
        .from('user_settings')
        .select('user_id, show_full_name')
        .in('user_id', allPageIds),
    ]);

    // Users who disabled "Show Full Name" appear as first name only
    const hideFullNameIds = new Set<string>();
    (nameSettings || []).forEach((s: any) => {
      if (s.show_full_name === false) hideFullNameIds.add(s.user_id);
    });

    const photoMap = new Map<string, any[]>();
    (photos || []).forEach((p: any) => {
      if (!photoMap.has(p.user_id)) photoMap.set(p.user_id, []);
      photoMap.get(p.user_id)!.push(p);
    });

    const promptMap = new Map<string, any[]>();
    (prompts || []).forEach((p: any) => {
      if (!promptMap.has(p.user_id)) promptMap.set(p.user_id, []);
      promptMap.get(p.user_id)!.push(p);
    });

    const interestMap = new Map<string, string[]>();
    (interests || []).forEach((i: any) => {
      interestMap.set(i.user_id, i.interests || []);
    });

    const dailyPromptMap = new Map<string, string | null>();
    (dailyPromptAnswers || []).forEach((u: any) => {
      dailyPromptMap.set(u.id, u.daily_prompt_answer || null);
    });

    // Compute common interests with current user
    const myInterests = new Set<string>(interestMap.get(user.id) || []);

    // Fetch additional profile data for the cards (sindhi, chatti, basics for new fields)
    const [
      { data: sindhiForCards },
      { data: chattiForCards },
      { data: basicsForCards },
    ] = await Promise.all([
      supabase
        .from('sindhi_profiles')
        .select('user_id, sindhi_fluency, food_preference')
        .in('user_id', allPageIds),
      supabase
        .from('chatti_profiles')
        .select('user_id, family_values, food_preference')
        .in('user_id', allPageIds),
      supabase
        .from('basic_profiles')
        .select('user_id, company, smoking, drinking, exercise')
        .in('user_id', allPageIds),
    ]);

    const sindhiCardMap = new Map<string, any>();
    (sindhiForCards || []).forEach((s: any) => sindhiCardMap.set(s.user_id, s));

    const chattiCardMap = new Map<string, any>();
    (chattiForCards || []).forEach((c: any) => chattiCardMap.set(c.user_id, c));

    const basicsCardMap = new Map<string, any>();
    (basicsForCards || []).forEach((b: any) => basicsCardMap.set(b.user_id, b));

    function buildCard(c: ScoredCandidate, isExplore: boolean = false): FeedCard & { is_explore?: boolean } {
      const userPhotos = photoMap.get(c.userId) || [];
      const userPrompts = promptMap.get(c.userId) || [];
      const userInterests = interestMap.get(c.userId) || [];
      const commonCount = userInterests.filter((i) => myInterests.has(i)).length;
      const sindhiData = sindhiCardMap.get(c.userId);
      const chattiData = chattiCardMap.get(c.userId);
      const basicsData = basicsCardMap.get(c.userId);

      const firstName = c.profile.display_name?.split(' ')[0] || 'Unknown';
      const hideFullName = hideFullNameIds.has(c.userId);

      return {
        id: c.userId,
        first_name: firstName,
        display_name: hideFullName ? firstName : (c.profile.display_name || 'Unknown'),
        age: calculateAge(c.profile.date_of_birth),
        city: c.profile.city,
        state: c.profile.state || null,
        country: c.profile.country || null,
        bio: c.profile.bio || null,
        intent: c.profile.intent,
        is_verified: c.userMeta.is_verified || false,
        profile_completeness: c.userMeta.profile_completeness || 0,
        photos: userPhotos.map((p: any) => ({
          url: p.url_original,
          url_thumb: p.url_thumb || p.url_medium,
          url_medium: p.url_medium,
          is_primary: p.is_primary || false,
          sort_order: p.sort_order || 0,
          is_verified: p.is_verified || false,
          is_video: p.is_video || false,
        })),
        about_me: c.profile.bio || null,
        prompts: userPrompts.slice(0, 3),
        interests: userInterests,
        cultural_score: c.culturalScore,
        cultural_badge: c.culturalBadge,
        cultural_breakdown: null, // populated on detail view
        kundli_score: c.kundliScore,
        kundli_tier: c.kundliTier,
        kundli_breakdown: null, // populated on detail view
        common_interests: commonCount,
        daily_prompt_answer: dailyPromptMap.get(c.userId) || null,
        distance_km: cityDistance(discoveryCity || '', c.profile.city || ''),
        is_online: c.userMeta.is_online || false,
        last_active: c.userMeta.last_active_at || c.userMeta.last_active || null,
        // Sindhi identity
        sindhi_fluency: (sindhiData?.sindhi_fluency as SindhiFluency) || null,
        family_values: (chattiData?.family_values as FamilyValues) || null,
        food_preference: (chattiData?.food_preference || sindhiData?.food_preference) as FoodPreference || null,
        // Basics
        height_cm: c.profile.height_cm || null,
        education: c.profile.education || null,
        occupation: c.profile.occupation || null,
        company: basicsData?.company || null,
        religion: c.profile.religion || null,
        smoking: basicsData?.smoking || null,
        drinking: basicsData?.drinking || null,
        exercise: basicsData?.exercise || null,
        ...(isExplore ? { is_explore: true } : {}),
      };
    }

    const cards: (FeedCard & { is_explore?: boolean })[] = page.map((c) => buildCard(c, false));

    // Inject explore cards at random positions near the end
    for (const ec of exploreCards) {
      const insertPos = Math.max(cards.length - 5, Math.floor(cards.length * 0.6));
      const randomOffset = Math.floor(Math.random() * 5);
      cards.splice(Math.min(insertPos + randomOffset, cards.length), 0, buildCard(ec, true));
    }

    // Final trim to PAGE_SIZE + explore
    const finalCards = cards.slice(0, PAGE_SIZE + exploreCards.length);

    const lastCard = page[page.length - 1];
    const nextCursor = lastCard ? lastCard.userId : null;
    const hasMore = interleaved.length > PAGE_SIZE;

    res.json({
      success: true,
      data: {
        cards: finalCards,
        cursor: nextCursor,
        has_more: hasMore,
        cold_city: coldCity,
        ...(coldCity ? { city_profile_count: cityProfileCount } : {}),
        ...(isPassportMode ? { passport_city: discoveryCity } : {}),
      },
    });
  }),
);

// ─── POST /v1/feed/passport ─────────────────────────────────────────────────────

router.post(
  '/passport',
  authenticate,
  validate(passportSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { city, country } = req.body;

    // Check if passport is already active
    const existingPassport = await safeRedisGet(`passport:${user.id}`);
    if (existingPassport) {
      try {
        const parsed = JSON.parse(existingPassport);
        throw new AppError(
          409,
          `Passport already active for ${parsed.city}. Wait for it to expire or it will be replaced.`,
          'PASSPORT_ACTIVE',
        );
      } catch (err) {
        if (err instanceof AppError) throw err;
        // Corrupted data — allow overwrite
      }
    }

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + PASSPORT_DURATION_DAYS);

    const passportData = JSON.stringify({
      city,
      country,
      activated_at: new Date().toISOString(),
      expires_at: expiresAt.toISOString(),
    });

    const ttlSeconds = PASSPORT_DURATION_DAYS * 24 * 60 * 60;

    // Write to Redis with 7-day TTL
    await safeRedisSet(`passport:${user.id}`, passportData, ttlSeconds);

    // Persist to user_settings as durable fallback
    await supabase
      .from('user_settings')
      .update({
        passport_city: city,
        passport_country: country,
        passport_expires: expiresAt.toISOString(),
      })
      .eq('user_id', user.id);

    // Invalidate any cached feed for this user
    await safeRedisDel(`feed_cache:${user.id}`);

    res.status(201).json({
      success: true,
      data: {
        passport_city: city,
        passport_country: country,
        expires_at: expiresAt.toISOString(),
        duration_days: PASSPORT_DURATION_DAYS,
      },
    });
  }),
);

export default router;
