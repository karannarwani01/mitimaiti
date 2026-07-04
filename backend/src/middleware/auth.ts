import { Request, Response, NextFunction } from 'express';
import { supabase } from '../config/supabase';
import { redis } from '../config/redis';
import { AppError } from '../utils/errors';
import { AuthenticatedRequest, AuthUser } from '../types';

const LAST_ACTIVE_DEBOUNCE_MS = 5 * 60 * 1000;

/**
 * Authentication middleware.
 * Verifies Supabase JWT, checks Redis blacklist, loads user.
 * NO plan/premium checks — every user is equal.
 */
export async function authenticate(
  req: Request,
  _res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new AppError(401, 'Missing or malformed authorization token', 'AUTH_MISSING');
  }

  const token = authHeader.slice(7);
  if (!token) {
    throw new AppError(401, 'Authorization token is empty', 'AUTH_EMPTY');
  }

  // Verify with Supabase Auth
  const {
    data: { user: authUser },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !authUser) {
    throw new AppError(401, 'Invalid or expired token', 'AUTH_INVALID');
  }

  // Check Redis blacklist
  try {
    const blacklisted = await redis.get(`jwt_blacklist:${authUser.id}`);
    if (blacklisted) {
      throw new AppError(401, 'Token has been revoked', 'AUTH_REVOKED');
    }
  } catch (err) {
    if (err instanceof AppError) throw err;
    // Redis down — continue without blacklist check
  }

  // Lookup user in PostgreSQL by primary auth_id.
  let { data: dbUser } = await supabase
    .from('users')
    .select('id, auth_id, phone, is_banned, is_hidden')
    .eq('auth_id', authUser.id)
    .maybeSingle();

  // Fallback: this token may be a linked/secondary identity (e.g. a Google
  // login attached to a phone profile). Resolve the alias → the real profile.
  if (!dbUser) {
    const { data: alias } = await supabase
      .from('auth_identities')
      .select('user_id')
      .eq('auth_id', authUser.id)
      .maybeSingle();
    if (alias) {
      const { data: aliased } = await supabase
        .from('users')
        .select('id, auth_id, phone, is_banned, is_hidden')
        .eq('id', alias.user_id)
        .maybeSingle();
      dbUser = aliased ?? null;
    }
  }

  if (!dbUser) {
    throw new AppError(404, 'User account not found', 'USER_NOT_FOUND');
  }

  if (dbUser.is_banned) {
    throw new AppError(403, 'Account is banned', 'ACCOUNT_BANNED');
  }

  // Check suspension from user_safety
  const { data: safety } = await supabase
    .from('user_safety')
    .select('is_suspended, suspension_until, is_permanently_banned')
    .eq('user_id', dbUser.id)
    .single();

  if (safety?.is_permanently_banned) {
    throw new AppError(403, 'Account is permanently banned', 'ACCOUNT_BANNED');
  }

  if (safety?.is_suspended && safety.suspension_until) {
    const suspendedUntil = new Date(safety.suspension_until);
    if (suspendedUntil > new Date()) {
      throw new AppError(403, `Account is suspended until ${suspendedUntil.toISOString()}`, 'ACCOUNT_SUSPENDED');
    }
  }

  // Attach user to request
  const reqUser: AuthUser = {
    id: dbUser.id,
    authId: dbUser.auth_id,
    phone: dbUser.phone,
  };

  (req as AuthenticatedRequest).user = reqUser;

  // Debounced last_active update
  try {
    const lastActiveKey = `last_active:${dbUser.id}`;
    const lastUpdate = await redis.get(lastActiveKey);
    const now = Date.now();

    if (!lastUpdate || now - parseInt(lastUpdate, 10) > LAST_ACTIVE_DEBOUNCE_MS) {
      redis.set(lastActiveKey, now.toString(), 'EX', 600).catch(() => {});
      supabase
        .from('users')
        .update({ last_active: new Date().toISOString() })
        .eq('id', dbUser.id)
        .then(() => {});
    }
  } catch {
    // Non-critical
  }

  next();
}

/**
 * Admin-only middleware. Must be used after authenticate.
 * Checks for admin role via a simple admin_users check or user metadata.
 */
export async function requireAdmin(
  req: Request,
  _res: Response,
  next: NextFunction
): Promise<void> {
  const user = (req as AuthenticatedRequest).user;

  // Check Supabase auth metadata for admin role
  const { data: authData } = await supabase.auth.admin.getUserById(user.authId);

  const isAdmin = authData?.user?.app_metadata?.role === 'admin';

  if (!isAdmin) {
    throw new AppError(403, 'Admin access required', 'ADMIN_REQUIRED');
  }

  user.role = 'admin';
  next();
}

export default authenticate;
