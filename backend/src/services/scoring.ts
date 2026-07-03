import { redis } from '../config/redis';
import { supabase } from '../config/supabase';
import { AppError } from '../utils/errors';
import {
  CulturalScoreResult,
  CulturalBadge,
  CulturalBreakdown,
  FamilyInvolvement,
  SindhiFluency,
  Dietary,
  Intent,
} from '../types';

// ─── Constants ───────────────────────────────────────────────────────────────

const CACHE_TTL_SECONDS = 3600; // 1 hour
const CACHE_PREFIX = 'pair';

// ─── Cache Key (canonical ordering — lower UUID first) ───────────────────────

function cacheKey(idA: string, idB: string): string {
  const [first, second] = idA < idB ? [idA, idB] : [idB, idA];
  return `${CACHE_PREFIX}:${first}:${second}`;
}

// ─── DB Row Shapes ───────────────────────────────────────────────────────────

interface UserSindhiRow {
  user_id: string;
  family_values_legacy: FamilyInvolvement;
  sindhi_fluency: SindhiFluency;
  festivals: string[];
  food_preference: Dietary;
  generation: string; // '1st', '2nd', '3rd', '4th+'
}

interface UserRow {
  id: string;
  intent: Intent;
}

interface UserData {
  sindhi: UserSindhiRow | null;
  user: UserRow | null;
}

// ─── Dimension 1: Family Values (max 25) ─────────────────────────────────────

export function scoreFamilyValues(a: FamilyInvolvement | null, b: FamilyInvolvement | null): number {
  if (!a || !b) return 0;

  // Both 'very involved' = 25
  if (a === 'very' && b === 'very') return 25;

  // One 'moderate' (other is 'very' or 'moderate') = 15
  if (a === 'moderate' || b === 'moderate') return 15;

  // One 'independent' = 10
  if (a === 'independent' || b === 'independent') return 10;

  return 0;
}

// ─── Dimension 2: Language (max 20) ──────────────────────────────────────────

export function scoreLanguage(a: SindhiFluency | null, b: SindhiFluency | null): number {
  if (!a || !b) return 0;

  // 'none' on either side = no shared Sindhi
  if (a === 'none' || b === 'none') return 0;

  // Both native = 20
  if (a === 'native' && b === 'native') return 20;

  // Both fluent = 16
  if (a === 'fluent' && b === 'fluent') return 16;

  // Both native or fluent (mixed) = 18
  const highFluency: SindhiFluency[] = ['native', 'fluent'];
  if (highFluency.includes(a) && highFluency.includes(b)) return 18;

  // Middle tiers. Previously 'conversational' and 'learning' fell through
  // every branch and scored 0 — two conversational speakers ranked the same
  // as two people with no Sindhi at all.
  const rank = (f: SindhiFluency): number =>
    ({ native: 4, fluent: 4, conversational: 3, basic: 2, learning: 1, none: 0 }[f] ?? 0);
  const lower = Math.min(rank(a), rank(b));
  const higher = Math.max(rank(a), rank(b));

  if (lower === 3) return higher === 4 ? 12 : 10;      // conversational w/ high | both conversational
  if (lower === 2) return higher >= 3 ? 8 : 8;         // basic with anyone who speaks
  if (lower === 1) return higher >= 3 ? 8 : 6;         // learning w/ a speaker | learning+basic/learning

  return 0;
}

// ─── Dimension 3: Festivals (max 20) — Jaccard similarity ───────────────────

export function scoreFestivals(a: string[] | null, b: string[] | null): number {
  if (!a || !b) return 0;

  const setA = new Set(a.map((f) => f.toLowerCase().trim()));
  const setB = new Set(b.map((f) => f.toLowerCase().trim()));

  if (setA.size === 0 && setB.size === 0) return 0;
  if (setA.size === 0 || setB.size === 0) return 0;

  let intersection = 0;
  for (const item of setA) {
    if (setB.has(item)) intersection++;
  }

  const union = setA.size + setB.size - intersection;
  if (union === 0) return 0;

  const jaccard = intersection / union;
  return Math.round(jaccard * 20);
}

// ─── Dimension 4: Food / Dietary (max 15) ───────────────────────────────────

export function scoreFood(a: Dietary | null, b: Dietary | null): number {
  if (!a || !b) return 0;

  // The Dietary type carries alias spellings ('vegetarian' vs 'veg',
  // 'non_vegetarian' vs 'non-veg') — previously unnormalized, so
  // vegetarian+veg scored 5 instead of 15.
  const normalize = (d: Dietary): string =>
    ({ vegetarian: 'veg', non_vegetarian: 'non-veg' }[d as string] ?? d);
  const na = normalize(a);
  const nb = normalize(b);

  // Same dietary = 15
  if (na === nb) return 15;

  // Compatible pairs = 10
  const compatiblePairs: Record<string, string[]> = {
    veg: ['jain', 'vegan', 'eggetarian'],
    jain: ['veg', 'vegan'],
    vegan: ['veg', 'jain'],
    eggetarian: ['veg'],
    'non-veg': ['eggetarian'],
  };

  if (compatiblePairs[na]?.includes(nb) || compatiblePairs[nb]?.includes(na)) return 10;

  return 5;
}

// ─── Dimension 5: Diaspora Generation (max 10) ──────────────────────────────

export function scoreDiaspora(a: number | null, b: number | null): number {
  if (a == null || b == null) return 0;

  const diff = Math.abs(a - b);

  // Same generation = 10
  if (diff === 0) return 10;

  // +/- 1 generation = 6
  if (diff === 1) return 6;

  // +/- 2 or more = 2
  return 2;
}

// ─── Dimension 6: Intent Match (max 10) ──────────────────────────────────────

export function scoreIntent(a: Intent | null, b: Intent | null): number {
  if (!a || !b) return 0;

  // Both marriage = 10
  if (a === 'marriage' && b === 'marriage') return 10;

  // Both same intent = 10
  if (a === b) return 10;

  // Open + any = 7
  if (a === 'open' || b === 'open') return 7;

  // Casual + marriage = 2
  if (
    (a === 'casual' && b === 'marriage') ||
    (a === 'marriage' && b === 'casual')
  ) {
    return 2;
  }

  return 5;
}

// ─── Badge Assignment ────────────────────────────────────────────────────────

export function assignBadge(total: number): CulturalBadge {
  if (total >= 85) return 'gold';
  if (total >= 65) return 'green';
  if (total >= 40) return 'orange';
  return 'none';
}

// ─── Data Fetching ───────────────────────────────────────────────────────────

async function fetchUserData(userId: string): Promise<UserData> {
  const [sindhiRes, userRes] = await Promise.all([
    supabase
      .from('sindhi_profiles')
      .select('user_id, family_values_legacy, sindhi_fluency, festivals, food_preference, generation')
      .eq('user_id', userId)
      .single(),
    supabase
      .from('users')
      .select('id, intent')
      .eq('id', userId)
      .single(),
  ]);

  return {
    sindhi: (sindhiRes.data as UserSindhiRow) || null,
    user: (userRes.data as UserRow) || null,
  };
}

// ─── Core Scoring Function ───────────────────────────────────────────────────

/**
 * Compute the cultural compatibility score between two users.
 *
 * 100-point scale across 6 dimensions:
 *   - Family Values (25): user_sindhi.family_involvement
 *   - Language (20): user_sindhi.fluency
 *   - Festivals (20): Jaccard similarity of user_sindhi.festivals
 *   - Food (15): user_sindhi.dietary
 *   - Diaspora Generation (10): user_sindhi.generation
 *   - Intent Match (10): users.intent
 */
export async function computeCulturalScore(
  userAId: string,
  userBId: string
): Promise<CulturalScoreResult> {
  const [dataA, dataB] = await Promise.all([
    fetchUserData(userAId),
    fetchUserData(userBId),
  ]);

  const family_values = scoreFamilyValues(
    dataA.sindhi?.family_values_legacy ?? null,
    dataB.sindhi?.family_values_legacy ?? null
  );

  const language = scoreLanguage(
    dataA.sindhi?.sindhi_fluency ?? null,
    dataB.sindhi?.sindhi_fluency ?? null
  );

  const festivals = scoreFestivals(
    dataA.sindhi?.festivals ?? null,
    dataB.sindhi?.festivals ?? null
  );

  const food = scoreFood(
    dataA.sindhi?.food_preference ?? null,
    dataB.sindhi?.food_preference ?? null
  );

  // Parse generation string to number for scoring
  const genToNum = (g: string | null): number | null => {
    if (!g) return null;
    const map: Record<string, number> = { '1st': 1, '2nd': 2, '3rd': 3, '4th+': 4 };
    return map[g] ?? null;
  };

  const diaspora = scoreDiaspora(
    genToNum(dataA.sindhi?.generation ?? null),
    genToNum(dataB.sindhi?.generation ?? null)
  );

  const intent = scoreIntent(
    dataA.user?.intent ?? null,
    dataB.user?.intent ?? null
  );

  const total = family_values + language + festivals + food + diaspora + intent;
  const badge = assignBadge(total);

  const breakdown: CulturalBreakdown = {
    family_values,
    language,
    festivals,
    food,
    diaspora,
    intent,
  };

  return { total, badge, breakdown };
}

// ─── Cached Entry Point ──────────────────────────────────────────────────────

/**
 * Get cultural score with Redis caching.
 * Cache key uses canonical ID ordering so score(A,B) === score(B,A).
 * TTL: 1 hour.
 */
export async function getCulturalScore(
  idA: string,
  idB: string
): Promise<CulturalScoreResult> {
  const key = cacheKey(idA, idB);

  // Try cache
  try {
    const cached = await redis.get(key);
    if (cached) {
      return JSON.parse(cached) as CulturalScoreResult;
    }
  } catch (err) {
    console.error('[Scoring] Redis read error, computing fresh:', err);
  }

  // Compute
  const result = await computeCulturalScore(idA, idB);

  // Store in cache
  try {
    await redis.set(key, JSON.stringify(result), 'EX', CACHE_TTL_SECONDS);
  } catch (err) {
    console.error('[Scoring] Redis write error:', err);
  }

  return result;
}

/**
 * Invalidate cached cultural score when a user updates their profile.
 */
export async function invalidateCulturalScoreCache(userId: string): Promise<void> {
  // Best-effort cache cleanup. Redis is configured with
  // enableOfflineQueue:false + maxRetriesPerRequest:1, so a scan/del issued
  // while the connection isn't ready rejects immediately. This runs AFTER
  // the profile write that triggered it, so a Redis hiccup must never turn
  // a successful update into a 500 — swallow and log; entries expire by TTL.
  try {
    let cursor = '0';
    do {
      const [newCursor, keys] = await redis.scan(
        cursor,
        'MATCH',
        `${CACHE_PREFIX}:*${userId}*`,
        'COUNT',
        100
      );
      cursor = newCursor;
      if (keys.length > 0) {
        await redis.del(...keys);
      }
    } while (cursor !== '0');
  } catch (err) {
    console.error(
      '[scoring] invalidateCulturalScoreCache failed (non-fatal):',
      err instanceof Error ? err.message : err
    );
  }
}

export default { computeCulturalScore, getCulturalScore, invalidateCulturalScoreCache };
