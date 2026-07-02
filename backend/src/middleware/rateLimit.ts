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
            await checkLimit(key, windowSeconds, maxRequests, res, next);
            return;
          }
        }
      }
      const ip = req.ip || req.socket.remoteAddress || 'unknown';
      const key = `${keyPrefix}:ip:${ip}`;
      await checkLimit(key, windowSeconds, maxRequests, res, next);
      return;
    }

    const key = `${keyPrefix}:${user.id}`;
    await checkLimit(key, windowSeconds, maxRequests, res, next);
  };
}

async function checkLimit(
  key: string,
  windowSeconds: number,
  maxRequests: number,
  res: Response,
  next: NextFunction
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
    // Re-throw AppError (rate limit exceeded) but swallow Redis connection errors
    if (err instanceof AppError) throw err;
    // Redis down — allow request through (fail open for availability)
    console.warn('[RateLimit] Redis unavailable, skipping rate limit check');
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
});

export default rateLimit;
