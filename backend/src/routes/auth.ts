import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { OAuth2Client } from 'google-auth-library';
import { supabase, supabaseAuth } from '../config/supabase';
import { redis } from '../config/redis';
import { AppError, asyncHandler } from '../utils/errors';
import { validate } from '../middleware/validate';
import { authenticate } from '../middleware/auth';
import { strictRateLimit, otpSendRateLimit, otpVerifyRateLimit } from '../middleware/rateLimit';
import { AuthenticatedRequest } from '../types';

const router = Router();

// ─── Schemas ────────────────────────────────────────────────────────────────────

const loginSchema = z.object({
  phone: z
    .string()
    .regex(
      /^\+[1-9]\d{6,14}$/,
      'Phone must be in E.164 format (e.g. +919876543210)'
    ),
});

const verifySchema = z.object({
  phone: z
    .string()
    .regex(
      /^\+[1-9]\d{6,14}$/,
      'Phone must be in E.164 format (e.g. +919876543210)'
    ),
  token: z
    .string()
    .min(6, 'OTP must be at least 6 characters')
    .max(6, 'OTP must be at most 6 characters'),
});

const emailLoginSchema = z.object({
  email: z.string().email('Email must be a valid address').max(254),
});

const emailVerifySchema = z.object({
  email: z.string().email('Email must be a valid address').max(254),
  token: z
    .string()
    .min(6, 'OTP must be at least 6 characters')
    .max(6, 'OTP must be at most 6 characters'),
});

const googleVerifySchema = z.object({
  idToken: z.string().min(20, 'idToken is required'),
});

const appleVerifySchema = z.object({
  idToken: z.string().min(20, 'idToken is required'),
  nonce: z.string().min(1).optional(),
  fullName: z
    .object({
      givenName: z.string().nullable().optional(),
      familyName: z.string().nullable().optional(),
    })
    .optional(),
});

const refreshSchema = z.object({
  refresh_token: z.string().min(1, 'Refresh token is required'),
});

const deleteSchema = z.object({
  action: z.enum(['logout', 'delete']),
  reason: z.string().max(500).optional(),
});

// ─── POST /v1/auth/login ────────────────────────────────────────────────────────
// Sends a phone OTP via Supabase Auth (Twilio under the hood).
// In development mode, skips Supabase and accepts a fixed OTP (123456).
// No age-gate here — that's checked during onboarding.

const isDev = process.env.NODE_ENV === 'development';

// In-memory store for dev OTP sessions
const devOtpSessions = new Map<string, { phone: string; createdAt: number }>();

router.post(
  '/login',
  otpSendRateLimit,
  validate(loginSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const { phone } = req.body;

    if (isDev) {
      // Dev mode: store phone and accept fixed OTP 123456
      devOtpSessions.set(phone, { phone, createdAt: Date.now() });
      console.log(`[Auth][DEV] OTP requested for ${phone} — use code 123456`);
      res.json({
        success: true,
        message: 'Verification code sent',
      });
      return;
    }

    const { error } = await supabaseAuth.auth.signInWithOtp({
      phone,
      options: {
        // Supabase sends the OTP via Twilio
        shouldCreateUser: true,
      },
    });

    if (error) {
      console.error('[Auth] Supabase OTP error:', JSON.stringify({ message: error.message, status: error.status, name: error.name }));
      // Surface rate-limit or provider errors cleanly
      if (error.message.includes('rate') || error.status === 429) {
        throw new AppError(
          429,
          'Too many OTP requests. Please wait before trying again.',
          'OTP_RATE_LIMITED'
        );
      }
      throw new AppError(
        500,
        'Failed to send verification code. Please try again.',
        'OTP_SEND_FAILED'
      );
    }

    res.json({
      success: true,
      message: 'Verification code sent',
    });
  })
);

// ─── POST /v1/auth/verify ───────────────────────────────────────────────────────
// Verifies the OTP, provisions new users, refreshes returning users.

router.post(
  '/verify',
  otpVerifyRateLimit,
  validate(verifySchema),
  asyncHandler(async (req: Request, res: Response) => {
    const { phone, token } = req.body;

    let authUserId: string;
    let sessionData: { access_token: string; refresh_token: string; expires_at?: number };

    if (isDev) {
      // Dev mode: accept fixed OTP 123456
      const otpSession = devOtpSessions.get(phone);
      if (!otpSession || token !== '123456') {
        throw new AppError(
          401,
          'Invalid or expired verification code',
          'OTP_INVALID'
        );
      }
      // Expire OTP sessions older than 5 minutes
      if (Date.now() - otpSession.createdAt > 5 * 60 * 1000) {
        devOtpSessions.delete(phone);
        throw new AppError(
          401,
          'Invalid or expired verification code',
          'OTP_INVALID'
        );
      }
      devOtpSessions.delete(phone);

      // Dev mode: generate a deterministic auth ID from phone number and mock session
      const crypto = await import('crypto');
      authUserId = crypto.createHash('sha256').update(`dev-${phone}`).digest('hex').slice(0, 36);
      // Format as UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      authUserId = `${authUserId.slice(0,8)}-${authUserId.slice(8,12)}-${authUserId.slice(12,16)}-${authUserId.slice(16,20)}-${authUserId.slice(20,32)}`;

      sessionData = {
        access_token: `dev_${crypto.randomBytes(32).toString('hex')}`,
        refresh_token: `dev_refresh_${crypto.randomBytes(32).toString('hex')}`,
        expires_at: Math.floor(Date.now() / 1000) + 3600,
      };

      console.log(`[Auth][DEV] Verified OTP for ${phone}, authUserId=${authUserId}`);
    } else {
      // Production: Verify OTP through Supabase Auth
      const {
        data: { session, user: authUser },
        error: authError,
      } = await supabaseAuth.auth.verifyOtp({
        phone,
        token,
        type: 'sms',
      });

      if (authError || !authUser || !session) {
        throw new AppError(
          401,
          'Invalid or expired verification code',
          'OTP_INVALID'
        );
      }
      authUserId = authUser.id;
      sessionData = session;
    }

    if (isDev) {
      // Dev mode: return mock user data without hitting the database
      const crypto = await import('crypto');
      const devUserId = crypto.createHash('md5').update(phone).digest('hex').slice(0, 36);
      const devId = `${devUserId.slice(0,8)}-${devUserId.slice(8,12)}-${devUserId.slice(12,16)}-${devUserId.slice(16,20)}-${devUserId.slice(20,32)}`;

      console.log(`[Auth][DEV] Returning mock user for ${phone}, id=${devId}`);

      res.status(201).json({
        success: true,
        data: {
          user: {
            id: devId,
            authId: authUserId,
            phone,
            isVerified: false,
            profileCompleteness: 0,
            isNew: true,
            needsOnboarding: true,
          },
          session: {
            accessToken: sessionData.access_token,
            refreshToken: sessionData.refresh_token,
            expiresAt: sessionData.expires_at,
          },
        },
      });
      return;
    }

    // ── Check if user already exists in our database ──
    const { data: existingUser } = await supabase
      .from('users')
      .select('*')
      .eq('auth_id', authUserId)
      .single();

    if (existingUser) {
      // ── Returning user ──

      // If account was scheduled for deletion, auto-recover on login
      const updates: Record<string, any> = {
        last_active: new Date().toISOString(),
      };

      if (existingUser.deletion_requested) {
        updates.deletion_requested = false;
        updates.deletion_scheduled_for = null;
        updates.is_active = true;

        // Re-enable discovery
        await supabase
          .from('user_settings')
          .update({ discovery_enabled: true })
          .eq('user_id', existingUser.id);
      }

      await supabase.from('users').update(updates).eq('id', existingUser.id);

      // Clear any JWT blacklist for this user
      await redis.del(`jwt_blacklist:${authUserId}`);

      res.json({
        success: true,
        data: {
          user: {
            id: existingUser.id,
            authId: existingUser.auth_id,
            phone: existingUser.phone,
            isVerified: existingUser.is_verified,
            profileCompleteness: existingUser.profile_completeness,
            isNew: false,
            needsOnboarding: existingUser.needs_onboarding ?? true,
          },
          session: {
            accessToken: sessionData.access_token,
            refreshToken: sessionData.refresh_token,
            expiresAt: sessionData.expires_at,
          },
        },
      });
    } else {
      // ── New user ──

      const { data: newUser, error: createError } = await supabase
        .from('users')
        .insert({
          auth_id: authUserId,
          phone,
          is_verified: false,
          is_active: true,
          is_banned: false,
          is_hidden: false,
          profile_completeness: 0,
          strikes: 0,
          deletion_requested: false,
          last_active: new Date().toISOString(),
        })
        .select()
        .single();

      if (createError || !newUser) {
        throw new AppError(
          500,
          'Failed to create user account',
          'USER_CREATE_FAILED'
        );
      }

      const userId = newUser.id;

      // Create default settings, privileges, and safety rows in parallel
      const [settingsResult, privilegesResult, safetyResult] =
        await Promise.all([
          supabase.from('user_settings').insert({
            user_id: userId,
            discovery_enabled: true,
            show_online_status: true,
            show_distance: true,
            push_notifications: true,
            email_notifications: false,
            age_min: 18,
            age_max: 50,
            distance_km: 100,
            gender_preference: 'everyone',
          }),

          supabase.from('user_privileges').insert({
            user_id: userId,
            daily_likes: 50,
            daily_super_likes: 1,
            daily_rewinds: 10,
            daily_comments: 5,
            likes_used: 0,
            super_likes_used: 0,
            rewinds_used: 0,
            comments_used: 0,
            last_reset_at: new Date().toISOString(),
          }),

          supabase.from('user_safety').insert({
            user_id: userId,
            is_suspended: false,
            is_permanently_banned: false,
            strikes: 0,
            last_reported_at: null,
            suspension_until: null,
          }),
        ]);

      // Check for insertion failures (non-critical but log-worthy)
      if (settingsResult.error) {
        console.error(
          '[Auth] Failed to create default settings:',
          settingsResult.error.message
        );
      }
      if (privilegesResult.error) {
        console.error(
          '[Auth] Failed to create default privileges:',
          privilegesResult.error.message
        );
      }
      if (safetyResult.error) {
        console.error(
          '[Auth] Failed to create safety row:',
          safetyResult.error.message
        );
      }

      res.status(201).json({
        success: true,
        data: {
          user: {
            id: newUser.id,
            authId: newUser.auth_id,
            phone: newUser.phone,
            isVerified: false,
            profileCompleteness: 0,
            isNew: true,
            needsOnboarding: true,
          },
          session: {
            accessToken: sessionData.access_token,
            refreshToken: sessionData.refresh_token,
            expiresAt: sessionData.expires_at,
          },
        },
      });
    }
  })
);

// ─── POST /v1/auth/email/login ──────────────────────────────────────────────────
// Sends a 6-digit OTP to the email via Supabase Auth (Supabase ships its own SMTP
// at low rate-limit; production should configure a custom SMTP provider in the
// Supabase dashboard — Resend free tier is sufficient).
//
// Mirrors /login (phone) so the mobile clients can switch identity type with a
// minimal UI change.

const devOtpSessionsByEmail = new Map<string, { email: string; createdAt: number }>();

router.post(
  '/email/login',
  otpSendRateLimit,
  validate(emailLoginSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const email = (req.body.email as string).toLowerCase();

    if (isDev) {
      devOtpSessionsByEmail.set(email, { email, createdAt: Date.now() });
      console.log(`[Auth][DEV] Email OTP requested for ${email} — use code 123456`);
      res.json({
        success: true,
        message: 'Verification code sent',
      });
      return;
    }

    const { error } = await supabaseAuth.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: true,
      },
    });

    if (error) {
      console.error('[Auth] Supabase email OTP error:', JSON.stringify({ message: error.message, status: error.status, name: error.name }));
      if (error.message.includes('rate') || error.status === 429) {
        throw new AppError(
          429,
          'Too many OTP requests. Please wait before trying again.',
          'OTP_RATE_LIMITED'
        );
      }
      throw new AppError(
        500,
        'Failed to send verification code. Please try again.',
        'OTP_SEND_FAILED'
      );
    }

    res.json({
      success: true,
      message: 'Verification code sent',
    });
  })
);

// ─── POST /v1/auth/email/verify ─────────────────────────────────────────────────
// Verifies the email OTP, provisions new email-only users, refreshes returning
// users. New users get a NULL phone column — they can add a phone later from
// Settings if we expose that flow.

router.post(
  '/email/verify',
  otpVerifyRateLimit,
  validate(emailVerifySchema),
  asyncHandler(async (req: Request, res: Response) => {
    const email = (req.body.email as string).toLowerCase();
    const { token } = req.body;

    let authUserId: string;
    let sessionData: { access_token: string; refresh_token: string; expires_at?: number };

    if (isDev) {
      const otpSession = devOtpSessionsByEmail.get(email);
      if (!otpSession || token !== '123456') {
        throw new AppError(401, 'Invalid or expired verification code', 'OTP_INVALID');
      }
      if (Date.now() - otpSession.createdAt > 5 * 60 * 1000) {
        devOtpSessionsByEmail.delete(email);
        throw new AppError(401, 'Invalid or expired verification code', 'OTP_INVALID');
      }
      devOtpSessionsByEmail.delete(email);

      const crypto = await import('crypto');
      const hashed = crypto.createHash('sha256').update(`dev-${email}`).digest('hex').slice(0, 32);
      authUserId = `${hashed.slice(0,8)}-${hashed.slice(8,12)}-${hashed.slice(12,16)}-${hashed.slice(16,20)}-${hashed.slice(20,32)}`;

      sessionData = {
        access_token: `dev_${crypto.randomBytes(32).toString('hex')}`,
        refresh_token: `dev_refresh_${crypto.randomBytes(32).toString('hex')}`,
        expires_at: Math.floor(Date.now() / 1000) + 3600,
      };

      console.log(`[Auth][DEV] Verified email OTP for ${email}, authUserId=${authUserId}`);

      res.status(201).json({
        success: true,
        data: {
          user: {
            id: authUserId,
            authId: authUserId,
            email,
            phone: null,
            isVerified: false,
            profileCompleteness: 0,
            isNew: true,
            needsOnboarding: true,
          },
          session: {
            accessToken: sessionData.access_token,
            refreshToken: sessionData.refresh_token,
            expiresAt: sessionData.expires_at,
          },
        },
      });
      return;
    }

    const {
      data: { session, user: authUser },
      error: authError,
    } = await supabaseAuth.auth.verifyOtp({
      email,
      token,
      type: 'email',
    });

    if (authError || !authUser || !session) {
      throw new AppError(401, 'Invalid or expired verification code', 'OTP_INVALID');
    }
    authUserId = authUser.id;
    sessionData = session;

    const { data: existingUser } = await supabase
      .from('users')
      .select('*')
      .eq('auth_id', authUserId)
      .single();

    if (existingUser) {
      const updates: Record<string, any> = {
        last_active: new Date().toISOString(),
      };

      if (existingUser.deletion_requested) {
        updates.deletion_requested = false;
        updates.deletion_scheduled_for = null;
        updates.is_active = true;

        await supabase
          .from('user_settings')
          .update({ discovery_enabled: true })
          .eq('user_id', existingUser.id);
      }

      await supabase.from('users').update(updates).eq('id', existingUser.id);
      await redis.del(`jwt_blacklist:${authUserId}`);

      res.json({
        success: true,
        data: {
          user: {
            id: existingUser.id,
            authId: existingUser.auth_id,
            email: existingUser.email,
            phone: existingUser.phone,
            isVerified: existingUser.is_verified,
            profileCompleteness: existingUser.profile_completeness,
            isNew: false,
            needsOnboarding: existingUser.needs_onboarding ?? true,
          },
          session: {
            accessToken: sessionData.access_token,
            refreshToken: sessionData.refresh_token,
            expiresAt: sessionData.expires_at,
          },
        },
      });
      return;
    }

    // New user — insert with email, phone left NULL (relies on migration 005).
    const { data: newUser, error: createError } = await supabase
      .from('users')
      .insert({
        auth_id: authUserId,
        email,
        phone: null,
        is_verified: false,
        is_active: true,
        is_banned: false,
        is_hidden: false,
        profile_completeness: 0,
        strikes: 0,
        deletion_requested: false,
        last_active: new Date().toISOString(),
      })
      .select()
      .single();

    if (createError || !newUser) {
      throw new AppError(500, 'Failed to create user account', 'USER_CREATE_FAILED');
    }

    const userId = newUser.id;

    const [settingsResult, privilegesResult, safetyResult] = await Promise.all([
      supabase.from('user_settings').insert({
        user_id: userId,
        discovery_enabled: true,
        show_online_status: true,
        show_distance: true,
        push_notifications: true,
        email_notifications: false,
        age_min: 18,
        age_max: 50,
        distance_km: 100,
        gender_preference: 'everyone',
      }),
      supabase.from('user_privileges').insert({
        user_id: userId,
        daily_likes: 50,
        daily_super_likes: 1,
        daily_rewinds: 10,
        daily_comments: 5,
        likes_used: 0,
        super_likes_used: 0,
        rewinds_used: 0,
        comments_used: 0,
        last_reset_at: new Date().toISOString(),
      }),
      supabase.from('user_safety').insert({
        user_id: userId,
        is_suspended: false,
        is_permanently_banned: false,
        strikes: 0,
        last_reported_at: null,
        suspension_until: null,
      }),
    ]);

    if (settingsResult.error) {
      console.error('[Auth] Failed to create default settings:', settingsResult.error.message);
    }
    if (privilegesResult.error) {
      console.error('[Auth] Failed to create default privileges:', privilegesResult.error.message);
    }
    if (safetyResult.error) {
      console.error('[Auth] Failed to create safety row:', safetyResult.error.message);
    }

    res.status(201).json({
      success: true,
      data: {
        user: {
          id: newUser.id,
          authId: newUser.auth_id,
          email: newUser.email,
          phone: newUser.phone,
          isVerified: false,
          profileCompleteness: 0,
          isNew: true,
          needsOnboarding: true,
        },
        session: {
          accessToken: sessionData.access_token,
          refreshToken: sessionData.refresh_token,
          expiresAt: sessionData.expires_at,
        },
      },
    });
  })
);

// ─── POST /v1/auth/google/verify ────────────────────────────────────────────────
// Verifies a Google ID token from the Android Credential Manager / Sign in with
// Google flow, then provisions or refreshes the user. The mobile client obtains
// the ID token from Google directly; we never touch a Google access token.
//
// GOOGLE_WEB_CLIENT_ID must match the Web OAuth Client ID configured in Google
// Cloud Console — the audience claim of the ID token will equal that value.
//
// On success, mints a Supabase session by calling supabaseAuth.auth.signInWithIdToken
// so the rest of the app's JWT/refresh plumbing stays identical to the phone +
// email paths.

const googleClientId = process.env.GOOGLE_WEB_CLIENT_ID || '';
const googleVerifier = new OAuth2Client(googleClientId);

router.post(
  '/google/verify',
  strictRateLimit,
  validate(googleVerifySchema),
  asyncHandler(async (req: Request, res: Response) => {
    if (!googleClientId) {
      throw new AppError(
        500,
        'Google sign-in is not configured on the server',
        'GOOGLE_NOT_CONFIGURED'
      );
    }

    const { idToken } = req.body;

    // 1. Verify the ID token signature + audience locally — fast and avoids any
    //    extra network hop to Google.
    let payload: import('google-auth-library').TokenPayload | undefined;
    try {
      const ticket = await googleVerifier.verifyIdToken({
        idToken,
        audience: googleClientId,
      });
      payload = ticket.getPayload();
    } catch (e) {
      throw new AppError(401, 'Invalid Google ID token', 'GOOGLE_TOKEN_INVALID');
    }

    if (!payload?.email || !payload.sub || payload.email_verified !== true) {
      throw new AppError(401, 'Google account email not verified', 'GOOGLE_EMAIL_UNVERIFIED');
    }

    const email = payload.email.toLowerCase();

    // 2. Hand the same idToken to Supabase Auth so it issues a Supabase session.
    //    Supabase will create / link an auth user keyed off the Google sub.
    const {
      data: { session, user: authUser },
      error: authError,
    } = await supabaseAuth.auth.signInWithIdToken({
      provider: 'google',
      token: idToken,
    });

    let authUserId: string;
    let sessionData: { access_token: string; refresh_token: string; expires_at?: number };

    if (authUser && session) {
      authUserId = authUser.id;
      sessionData = session;
    } else {
      // GoTrue wouldn't issue a Google session. The common cause is that this
      // Google email was linked to another auth user (e.g. a phone profile) and
      // GoTrue won't auto-link. If we recognise the email as an existing
      // profile, mint a session for THAT auth user directly so linked-Google
      // login lands on the right profile regardless of GoTrue's linking policy.
      const { data: byEmail } = await supabase
        .from('users')
        .select('auth_id')
        .eq('email', email)
        .maybeSingle();

      if (!byEmail?.auth_id) {
        throw new AppError(401, authError?.message || 'Google sign-in failed', 'GOOGLE_SUPABASE_SIGNIN_FAILED');
      }

      const { data: link, error: linkErr } = await supabaseAuth.auth.admin.generateLink({
        type: 'magiclink',
        email,
      });
      const otp = link?.properties?.email_otp;
      if (linkErr || !otp) {
        throw new AppError(401, 'Google sign-in failed', 'GOOGLE_SUPABASE_SIGNIN_FAILED');
      }
      const { data: verified, error: verifyErr } = await supabaseAuth.auth.verifyOtp({
        email,
        token: otp,
        type: 'email',
      });
      if (verifyErr || !verified?.session || !verified?.user) {
        throw new AppError(401, 'Google sign-in failed', 'GOOGLE_SUPABASE_SIGNIN_FAILED');
      }
      authUserId = verified.user.id;
      sessionData = verified.session;
    }

    // 3. Look up or provision our application-side users row.
    let { data: existingUser } = await supabase
      .from('users')
      .select('*')
      .eq('auth_id', authUserId)
      .maybeSingle();

    // Hardening: if GoTrue didn't route this Google login to the auth user the
    // email was linked to (no profile for this auth_id), but the verified email
    // already belongs to a profile, resolve to THAT profile and record this
    // auth_id as an alias so it — and every future request with this session —
    // maps to the right user. This makes linked-Google login work regardless of
    // Supabase's automatic same-email linking behaviour.
    if (!existingUser) {
      const { data: byEmail } = await supabase
        .from('users')
        .select('*')
        .eq('email', email)
        .maybeSingle();
      if (byEmail) {
        await supabase
          .from('auth_identities')
          .upsert({ auth_id: authUserId, user_id: byEmail.id, provider: 'google' });
        existingUser = byEmail;
      }
    }

    if (existingUser) {
      const updates: Record<string, any> = {
        last_active: new Date().toISOString(),
      };
      if (existingUser.deletion_requested) {
        updates.deletion_requested = false;
        updates.deletion_scheduled_for = null;
        updates.is_active = true;
        await supabase
          .from('user_settings')
          .update({ discovery_enabled: true })
          .eq('user_id', existingUser.id);
      }
      await supabase.from('users').update(updates).eq('id', existingUser.id);
      await redis.del(`jwt_blacklist:${authUserId}`);

      res.json({
        success: true,
        data: {
          user: {
            id: existingUser.id,
            authId: existingUser.auth_id,
            email: existingUser.email,
            phone: existingUser.phone,
            firstName: existingUser.first_name,
            isVerified: existingUser.is_verified,
            profileCompleteness: existingUser.profile_completeness,
            isNew: false,
            needsOnboarding: existingUser.needs_onboarding ?? true,
          },
          session: {
            accessToken: sessionData.access_token,
            refreshToken: sessionData.refresh_token,
            expiresAt: sessionData.expires_at,
          },
        },
      });
      return;
    }

    // New user — pre-fill name from Google profile. Prefer the full `name`
    // claim (e.g. "Karan Narwani") over `given_name` so the onboarding
    // "What's your full name?" field arrives populated.
    const displayName = payload.name || payload.given_name || null;

    const { data: newUser, error: createError } = await supabase
      .from('users')
      .insert({
        auth_id: authUserId,
        email,
        phone: null,
        first_name: displayName,
        is_verified: false,
        is_active: true,
        is_banned: false,
        is_hidden: false,
        profile_completeness: 0,
        strikes: 0,
        deletion_requested: false,
        last_active: new Date().toISOString(),
      })
      .select()
      .single();

    if (createError || !newUser) {
      throw new AppError(500, 'Failed to create user account', 'USER_CREATE_FAILED');
    }

    const userId = newUser.id;
    await Promise.all([
      supabase.from('user_settings').insert({
        user_id: userId,
        discovery_enabled: true,
        show_online_status: true,
        show_distance: true,
        push_notifications: true,
        email_notifications: false,
        age_min: 18,
        age_max: 50,
        distance_km: 100,
        gender_preference: 'everyone',
      }),
      supabase.from('user_privileges').insert({
        user_id: userId,
        daily_likes: 50,
        daily_super_likes: 1,
        daily_rewinds: 10,
        daily_comments: 5,
        likes_used: 0,
        super_likes_used: 0,
        rewinds_used: 0,
        comments_used: 0,
        last_reset_at: new Date().toISOString(),
      }),
      supabase.from('user_safety').insert({
        user_id: userId,
        is_suspended: false,
        is_permanently_banned: false,
        strikes: 0,
        last_reported_at: null,
        suspension_until: null,
      }),
    ]);

    res.status(201).json({
      success: true,
      data: {
        user: {
          id: newUser.id,
          authId: newUser.auth_id,
          email: newUser.email,
          phone: newUser.phone,
          firstName: newUser.first_name,
          isVerified: false,
          profileCompleteness: 0,
          isNew: true,
          needsOnboarding: true,
        },
        session: {
          accessToken: sessionData.access_token,
          refreshToken: sessionData.refresh_token,
          expiresAt: sessionData.expires_at,
        },
      },
    });
  })
);

// ─── POST /v1/auth/apple/verify ─────────────────────────────────────────────────
// Verifies an Apple identity token from Sign in with Apple on iOS, then
// provisions or refreshes the user. Supabase validates the token against the
// Apple provider configured in the project dashboard (Service ID + key);
// audience is the iOS app's bundle ID for native flows.
//
// fullName is only populated by Apple on the very first sign-in for a given
// Apple ID and only if the user agreed to share it; we backfill display_name
// from it on user creation.

router.post(
  '/apple/verify',
  strictRateLimit,
  validate(appleVerifySchema),
  asyncHandler(async (req: Request, res: Response) => {
    const { idToken, nonce, fullName } = req.body;

    const {
      data: { session, user: authUser },
      error: authError,
    } = await supabaseAuth.auth.signInWithIdToken({
      provider: 'apple',
      token: idToken,
      nonce,
    });

    if (authError || !authUser || !session) {
      throw new AppError(
        401,
        authError?.message || 'Apple sign-in failed',
        'APPLE_SUPABASE_SIGNIN_FAILED'
      );
    }

    const authUserId = authUser.id;
    const sessionData = session;
    const email = (authUser.email || '').toLowerCase() || null;

    const { data: existingUser } = await supabase
      .from('users')
      .select('*')
      .eq('auth_id', authUserId)
      .single();

    if (existingUser) {
      const updates: Record<string, any> = {
        last_active: new Date().toISOString(),
      };
      if (existingUser.deletion_requested) {
        updates.deletion_requested = false;
        updates.deletion_scheduled_for = null;
        updates.is_active = true;
        await supabase
          .from('user_settings')
          .update({ discovery_enabled: true })
          .eq('user_id', existingUser.id);
      }
      await supabase.from('users').update(updates).eq('id', existingUser.id);
      await redis.del(`jwt_blacklist:${authUserId}`);

      res.json({
        success: true,
        data: {
          user: {
            id: existingUser.id,
            authId: existingUser.auth_id,
            email: existingUser.email,
            phone: existingUser.phone,
            firstName: existingUser.first_name,
            isVerified: existingUser.is_verified,
            profileCompleteness: existingUser.profile_completeness,
            isNew: false,
            needsOnboarding: existingUser.needs_onboarding ?? true,
          },
          session: {
            accessToken: sessionData.access_token,
            refreshToken: sessionData.refresh_token,
            expiresAt: sessionData.expires_at,
          },
        },
      });
      return;
    }

    // Apple returns fullName only on the very first sign-in for an Apple ID
    // and only if the user agreed to share it. Combine given+family into a
    // single value for the onboarding "What's your full name?" field.
    const displayName =
      [fullName?.givenName, fullName?.familyName].filter(Boolean).join(' ') ||
      authUser.user_metadata?.full_name ||
      authUser.user_metadata?.given_name ||
      null;

    const { data: newUser, error: createError } = await supabase
      .from('users')
      .insert({
        auth_id: authUserId,
        email,
        phone: null,
        first_name: displayName,
        is_verified: false,
        is_active: true,
        is_banned: false,
        is_hidden: false,
        profile_completeness: 0,
        strikes: 0,
        deletion_requested: false,
        last_active: new Date().toISOString(),
      })
      .select()
      .single();

    if (createError || !newUser) {
      throw new AppError(500, 'Failed to create user account', 'USER_CREATE_FAILED');
    }

    const userId = newUser.id;
    await Promise.all([
      supabase.from('user_settings').insert({
        user_id: userId,
        discovery_enabled: true,
        show_online_status: true,
        show_distance: true,
        push_notifications: true,
        email_notifications: false,
        age_min: 18,
        age_max: 50,
        distance_km: 100,
        gender_preference: 'everyone',
      }),
      supabase.from('user_privileges').insert({
        user_id: userId,
        daily_likes: 50,
        daily_super_likes: 1,
        daily_rewinds: 10,
        daily_comments: 5,
        likes_used: 0,
        super_likes_used: 0,
        rewinds_used: 0,
        comments_used: 0,
        last_reset_at: new Date().toISOString(),
      }),
      supabase.from('user_safety').insert({
        user_id: userId,
        is_suspended: false,
        is_permanently_banned: false,
        strikes: 0,
        last_reported_at: null,
        suspension_until: null,
      }),
    ]);

    res.status(201).json({
      success: true,
      data: {
        user: {
          id: newUser.id,
          authId: newUser.auth_id,
          email: newUser.email,
          phone: newUser.phone,
          firstName: newUser.first_name,
          isVerified: false,
          profileCompleteness: 0,
          isNew: true,
          needsOnboarding: true,
        },
        session: {
          accessToken: sessionData.access_token,
          refreshToken: sessionData.refresh_token,
          expiresAt: sessionData.expires_at,
        },
      },
    });
  })
);

// ─── POST /v1/auth/refresh ──────────────────────────────────────────────────────

router.post(
  '/refresh',
  strictRateLimit,
  validate(refreshSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const { refresh_token: refreshToken } = req.body;

    const {
      data: { session },
      error,
    } = await supabaseAuth.auth.refreshSession({ refresh_token: refreshToken });

    if (error || !session) {
      throw new AppError(
        401,
        'Invalid or expired refresh token',
        'REFRESH_INVALID'
      );
    }

    // Check if user's JWT is blacklisted (logged out)
    const blacklisted = await redis.get(
      `jwt_blacklist:${session.user.id}`
    );
    if (blacklisted) {
      throw new AppError(401, 'Session has been revoked', 'SESSION_REVOKED');
    }

    // Verify user still exists and is in good standing
    const { data: user } = await supabase
      .from('users')
      .select('id, is_active, is_banned')
      .eq('auth_id', session.user.id)
      .single();

    if (!user) {
      throw new AppError(404, 'User account not found', 'USER_NOT_FOUND');
    }

    if (!user.is_active) {
      throw new AppError(403, 'Account is deactivated', 'ACCOUNT_INACTIVE');
    }

    if (user.is_banned) {
      throw new AppError(403, 'Account is banned', 'ACCOUNT_BANNED');
    }

    // Check suspension via user_safety
    const { data: safety } = await supabase
      .from('user_safety')
      .select('is_suspended, suspension_until, is_permanently_banned')
      .eq('user_id', user.id)
      .single();

    if (safety?.is_permanently_banned) {
      throw new AppError(
        403,
        'Account is permanently banned',
        'ACCOUNT_BANNED'
      );
    }

    if (safety?.is_suspended && safety.suspension_until) {
      const suspendedUntil = new Date(safety.suspension_until);
      if (suspendedUntil > new Date()) {
        throw new AppError(
          403,
          `Account is suspended until ${suspendedUntil.toISOString()}`,
          'ACCOUNT_SUSPENDED'
        );
      }
    }

    res.json({
      success: true,
      data: {
        accessToken: session.access_token,
        refreshToken: session.refresh_token,
        expiresAt: session.expires_at,
      },
    });
  })
);

// ─── POST /v1/auth/delete ───────────────────────────────────────────────────────
// action: 'logout' → blacklist JWT in Redis
// action: 'delete' → soft-delete: mark for deletion in 30 days, hide from discovery

router.post(
  '/delete',
  authenticate,
  validate(deleteSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { action, reason } = req.body;

    switch (action) {
      case 'logout': {
        // Blacklist the JWT for 7 days (matching typical token lifetime)
        await redis.set(
          `jwt_blacklist:${user.authId}`,
          '1',
          'EX',
          604800 // 7 days in seconds
        );

        res.json({
          success: true,
          message: 'Logged out successfully',
        });
        break;
      }

      case 'delete': {
        const deleteDate = new Date();
        deleteDate.setDate(deleteDate.getDate() + 30);

        // Mark user for deletion and hide from discovery
        await supabase
          .from('users')
          .update({
            deletion_requested: true,
            deletion_scheduled_for: deleteDate.toISOString(),
            is_hidden: true,
          })
          .eq('id', user.id);

        // Disable discovery so they don't appear in feeds
        await supabase
          .from('user_settings')
          .update({ discovery_enabled: false })
          .eq('user_id', user.id);

        // Blacklist the JWT
        await redis.set(
          `jwt_blacklist:${user.authId}`,
          '1',
          'EX',
          604800
        );

        // Store deletion reason if provided
        if (reason) {
          await supabase.from('deletion_feedback').insert({
            user_id: user.id,
            reason,
            scheduled_at: deleteDate.toISOString(),
          });
        }

        res.json({
          success: true,
          message:
            'Account scheduled for deletion in 30 days. Log in again to recover your account.',
          data: {
            deletionScheduledFor: deleteDate.toISOString(),
          },
        });
        break;
      }

      default:
        throw new AppError(400, 'Invalid action', 'INVALID_ACTION');
    }
  })
);

// ─── Account linking ─────────────────────────────────────────────────────────
// Let a signed-in user attach an email / Google identity to their EXISTING
// auth user, so future logins via any method resolve to the same profile.
// The whole app keys a profile off users.auth_id, and Supabase mints a
// separate auth user per sign-in method — so without this, "Sign in with
// Google" after a phone signup silently created a second empty profile.
//
// Mechanism: set the email on the phone auth user (admin.updateUserById).
// Email-OTP login then lands on the same auth user; and because the email is
// confirmed, a later Google sign-in with the same address auto-links to it.
//
// v1 note: a typed email is attached without a separate ownership challenge —
// logging in via it still requires the email OTP, and an address already tied
// to another account is rejected. An explicit verify-before-attach step is a
// planned hardening.

const linkEmailSchema = z.object({
  email: z.string().email('Enter a valid email address'),
});
const linkGoogleSchema = z.object({
  idToken: z.string().min(10, 'Missing Google ID token'),
});

/** True if a profile has no dating data worth preserving (safe to absorb). */
async function isProfileEmpty(userId: string): Promise<boolean> {
  const c = async (t: string, filter: string) =>
    (await supabase.from(t).select('*', { count: 'exact', head: true }).or(filter)).count ?? 0;
  const total =
    (await c('matches', `user_a_id.eq.${userId},user_b_id.eq.${userId}`)) +
    (await c('actions', `actor_id.eq.${userId},target_id.eq.${userId}`)) +
    ((await supabase.from('messages').select('*', { count: 'exact', head: true }).eq('sender_id', userId)).count ?? 0) +
    ((await supabase.from('user_photos').select('*', { count: 'exact', head: true }).eq('user_id', userId)).count ?? 0);
  return total === 0;
}

/**
 * Absorb an EMPTY current profile into the survivor that owns the target email.
 * The survivor keeps its OAuth identities (those can't move between Supabase
 * users); we move the loser's phone onto the survivor if it lacks one, then
 * delete the loser. Only call when the loser is confirmed empty.
 */
async function absorbEmptyProfileInto(
  loserUserId: string,
  loserAuthId: string,
  survivorUserId: string
): Promise<void> {
  const { data: sUser } = await supabase.from('users').select('auth_id').eq('id', survivorUserId).maybeSingle();
  const survivorAuthId = sUser?.auth_id as string | undefined;

  const { data: la } = await supabaseAuth.auth.admin.getUserById(loserAuthId);
  let phone = la?.user?.phone || '';

  for (const t of [
    'basic_profiles', 'sindhi_profiles', 'chatti_profiles', 'user_settings',
    'user_photos', 'user_interests', 'user_fcm_tokens', 'auth_identities',
  ]) {
    await supabase.from(t).delete().eq('user_id', loserUserId).then(() => {}, () => {});
  }
  const { error: delErr } = await supabase.from('users').delete().eq('id', loserUserId);
  if (delErr) {
    // A foreign-key row still references this profile (so it wasn't truly
    // empty) — abort rather than leave a half-merged, orphaned-auth state.
    throw new AppError(500, 'Could not merge accounts safely; please contact support.', 'MERGE_FAILED');
  }
  await supabaseAuth.auth.admin.deleteUser(loserAuthId).then(() => {}, () => {});

  if (phone && survivorAuthId) {
    const { data: sa } = await supabaseAuth.auth.admin.getUserById(survivorAuthId);
    if (!sa?.user?.phone) {
      if (!phone.startsWith('+')) phone = '+' + phone;
      await supabaseAuth.auth.admin.updateUserById(survivorAuthId, { phone, phone_confirm: true });
      await supabase.from('users').update({ phone }).eq('id', survivorUserId).then(() => {}, () => {});
    }
  }
}

/**
 * Attach `email` to the caller's auth user. If another profile already owns the
 * email and the CURRENT profile is empty, auto-merge (absorb the current empty
 * profile into that account) since the caller has proven ownership of both.
 * Returns { merged } — merged=true means the caller must re-authenticate.
 */
async function attachEmailToUser(
  authId: string,
  appUserId: string,
  email: string,
  failCode: string,
  emailVerified: boolean
): Promise<{ merged: boolean }> {
  const { data: clash } = await supabase
    .from('users')
    .select('id')
    .eq('email', email)
    .neq('id', appUserId)
    .maybeSingle();

  if (clash) {
    // SECURITY: only auto-merge when ownership of the email is PROVEN (e.g.
    // Google OAuth, or an OTP-verified email). A merely typed email must never
    // trigger a merge — otherwise an attacker could type a victim's email and
    // have their empty account absorbed into the victim's (account takeover).
    if (emailVerified && (await isProfileEmpty(appUserId))) {
      await absorbEmptyProfileInto(appUserId, authId, clash.id);
      return { merged: true };
    }
    if (emailVerified) {
      // Both accounts are active with real data — never silently merge those.
      throw new AppError(
        409,
        'That email belongs to another active account. Contact support to merge them.',
        'MERGE_CONFLICT'
      );
    }
    throw new AppError(409, 'That email is already linked to another account', 'EMAIL_IN_USE');
  }

  const { error } = await supabaseAuth.auth.admin.updateUserById(authId, {
    email,
    email_confirm: true,
  });
  if (error) {
    if (/already|exist|registered|duplicate/i.test(error.message || '')) {
      throw new AppError(409, 'That email is already registered', 'EMAIL_IN_USE');
    }
    throw new AppError(500, error.message || 'Failed to link email', failCode);
  }

  await supabase.from('users').update({ email }).eq('id', appUserId);
  return { merged: false };
}

// POST /v1/auth/link/email — attach a typed email to the current account.
router.post(
  '/link/email',
  authenticate,
  strictRateLimit,
  validate(linkEmailSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const email = (req.body.email as string).toLowerCase().trim();
    // Typed email is NOT proven — no auto-merge (see attachEmailToUser).
    const { merged } = await attachEmailToUser(user.authId, user.id, email, 'LINK_EMAIL_FAILED', false);
    res.json({ success: true, data: { email, merged } });
  })
);

// POST /v1/auth/link/google — attach the caller's Google email (ownership
// proven by the verified ID token) so Google login resolves to this profile.
router.post(
  '/link/google',
  authenticate,
  strictRateLimit,
  validate(linkGoogleSchema),
  asyncHandler(async (req: Request, res: Response) => {
    if (!googleClientId) {
      throw new AppError(500, 'Google sign-in is not configured on the server', 'GOOGLE_NOT_CONFIGURED');
    }
    const user = (req as AuthenticatedRequest).user;
    const { idToken } = req.body;

    let payload: import('google-auth-library').TokenPayload | undefined;
    try {
      const ticket = await googleVerifier.verifyIdToken({ idToken, audience: googleClientId });
      payload = ticket.getPayload();
    } catch {
      throw new AppError(401, 'Invalid Google ID token', 'GOOGLE_TOKEN_INVALID');
    }
    if (!payload?.email || payload.email_verified !== true) {
      throw new AppError(401, 'Google account email not verified', 'GOOGLE_EMAIL_UNVERIFIED');
    }

    const email = payload.email.toLowerCase();
    // Google OAuth proves ownership → auto-merge is safe.
    const { merged } = await attachEmailToUser(user.authId, user.id, email, 'LINK_GOOGLE_FAILED', true);
    res.json({ success: true, data: { email, provider: 'google', merged } });
  })
);

// GET /v1/auth/link/status — which sign-in methods are on this account.
router.get(
  '/link/status',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { data } = await supabaseAuth.auth.admin.getUserById(user.authId);
    const au = data?.user;
    const providers = new Set((au?.identities || []).map((i) => i.provider));
    const phone = au?.phone || user.phone || null;
    const email = au?.email || null;
    res.json({
      success: true,
      data: {
        phone,
        email,
        google: providers.has('google'),
        apple: providers.has('apple'),
        // Contact info is complete once BOTH a phone and an email are present —
        // no need to prompt the user to add another.
        complete: !!(phone && email),
      },
    });
  })
);

export default router;
