import { Request, Response, NextFunction } from 'express';
import { redis } from '../config/redis';
import { AppError } from '../utils/errors';
import { AuthenticatedRequest } from '../types';

const DEFAULT_WINDOW_SECONDS = 60;
const DEFAULT_MAX_REQUESTS = 60;

interface RateLimitOptions {
  windowSeconds?: number;
  maxRequests?: number;
  keyPrefix?: string;
  /**
   * For unauthenticated routes: request-body fields to key the limit by
   * (e.g. ['phone', 'email']). Mobile carriers use carrier-grade NAT, so many
   * real users share one public IP — IP-keyed OTP limits let strangers
   * exhaust each other's login budget. Falls back to IP when none present.
   */
  identityFields?: string[];
  /**
   * When Redis is unavailable, the global limiter fails OPEN (availability
   * over protection). Sensitive limiters (auth/OTP) set this so they instead
   * fall back to an in-process limiter — a Redis outage must not remove the
   * only guard against SMS-bombing and OTP brute-force.
   */
  fallbackInProcess?: boolean;
}

// ─── In-process fallback (only used when Redis is down AND fallbackInProcess) ──
// Fixed-window counter in local memory. Per-instance (Render runs 1 web
// instance today), best-effort, and self-pruning so it can't grow unbounded.
const localBuckets = new Map<string, { count: number; resetAt: number }>();

function inProcessCheck(key: string, windowSeconds: number, maxRequests: number): boolean {
  const now = Date.now();
  const bucket = localBuckets.get(key);
  if (!bucket || now >= bucket.resetAt) {
    localBuckets.set(key, { count: 1, resetAt: now + windowSeconds * 1000 });
    if (localBuckets.size > 10000) {
      for (const [k, v] of localBuckets) if (now >= v.resetAt) localBuckets.delete(k);
    }
    return true;
  }
  bucket.count += 1;
  return bucket.count <= maxRequests;
}

/**
 * Redis-based rate limiter middleware.
 * Uses a sliding window counter per user.
 *
 * Default: 60 requests per 60-second window.
 */
export function rateLimit(options: RateLimitOptions = {}) {
  const {
    windowSeconds = DEFAULT_WINDOW_SECONDS,
    maxRequests = DEFAULT_MAX_REQUESTS,
    keyPrefix = 'rl',
    identityFields,
    fallbackInProcess = false,
  } = options;

  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const user = (req as AuthenticatedRequest).user;

    if (!user) {
      // Unauthenticated route: prefer an identity key (phone/email from the
      // body) so CGNAT users don't share a budget; fall back to IP.
      if (identityFields) {
        for (const field of identityFields) {
          const value = (req.body as any)?.[field];
          if (typeof value === 'string' && value.trim().length > 0) {
            const key = `${keyPrefix}:id:${value.trim().toLowerCase()}`;
            await checkLimit(key, windowSeconds, maxRequests, res, next, fallbackInProcess);
            return;
          }
        }
      }
      const ip = req.ip || req.socket.remoteAddress || 'unknown';
      const key = `${keyPrefix}:ip:${ip}`;
      await checkLimit(key, windowSeconds, maxRequests, res, next, fallbackInProcess);
      return;
    }

    const key = `${keyPrefix}:${user.id}`;
    await checkLimit(key, windowSeconds, maxRequests, res, next, fallbackInProcess);
  };
}

async function checkLimit(
  key: string,
  windowSeconds: number,
  maxRequests: number,
  res: Response,
  next: NextFunction,
  fallbackInProcess = false
): Promise<void> {
  try {
    const current = await redis.incr(key);

    if (current === 1) {
      // First request in this window - set expiry
      await redis.expire(key, windowSeconds);
    }

    // Set rate limit headers
    const ttl = await redis.ttl(key);
    res.setHeader('X-RateLimit-Limit', maxRequests);
    res.setHeader('X-RateLimit-Remaining', Math.max(0, maxRequests - current));
    res.setHeader('X-RateLimit-Reset', Math.floor(Date.now() / 1000) + Math.max(0, ttl));

    if (current > maxRequests) {
      throw new AppError(
        429,
        `Rate limit exceeded. Try again in ${Math.max(0, ttl)} seconds.`,
        'RATE_LIMIT_EXCEEDED'
      );
    }
  } catch (err) {
    // Re-throw AppError (rate limit exceeded) — a real 429, not a Redis fault.
    if (err instanceof AppError) throw err;

    // Redis down. Sensitive limiters (auth/OTP) fall back to an in-process
    // limiter so a Redis outage can't disable SMS-bomb / brute-force
    // protection. The global limiter fails open (availability first) as before.
    if (fallbackInProcess) {
      if (!inProcessCheck(key, windowSeconds, maxRequests)) {
        throw new AppError(429, 'Rate limit exceeded. Try again shortly.', 'RATE_LIMIT_EXCEEDED');
      }
      console.warn('[RateLimit] Redis unavailable — using in-process fallback for', key);
    } else {
      console.warn('[RateLimit] Redis unavailable, skipping rate limit check');
    }
  }

  next();
}

/**
 * Stricter rate limiter for sensitive endpoints (e.g. auth, reports).
 * 10 requests per 60 seconds.
 */
export const strictRateLimit = rateLimit({
  windowSeconds: 60,
  maxRequests: 10,
  keyPrefix: 'rl_strict',
  fallbackInProcess: true,
});

/**
 * OTP send limiter: 5 sends per hour per phone/email (protects the Twilio/
 * Resend budget and stops SMS-bombing a victim's number), with an IP
 * fallback for malformed bodies.
 */
export const otpSendRateLimit = rateLimit({
  windowSeconds: 3600,
  maxRequests: 5,
  keyPrefix: 'rl_otp_send',
  identityFields: ['phone', 'email'],
  fallbackInProcess: true,
});

/**
 * OTP verify limiter: 10 attempts per 10 minutes per phone/email — enough
 * for typos, too few to brute-force a 6-digit code.
 */
export const otpVerifyRateLimit = rateLimit({
  windowSeconds: 600,
  maxRequests: 10,
  keyPrefix: 'rl_otp_verify',
  identityFields: ['phone', 'email'],
  fallbackInProcess: true,
});

export default rateLimit;
