import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { supabase } from '../config/supabase';
import { AppError, asyncHandler } from '../utils/errors';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { rateLimit } from '../middleware/rateLimit';
import { AuthenticatedRequest, FamilyPermissions } from '../types';
import { sendTemplateNotification } from '../services/notifications';

const router = Router();

// ─── Constants ──────────────────────────────────────────────────────────────

const MAX_FAMILY_MEMBERS = 3;
const INVITE_EXPIRY_HOURS = 48;
const MAX_SUGGESTIONS_PER_DAY = 5;
const INVITE_CODE_LENGTH = 6;

// ─── Default permissions (all enabled) ──────────────────────────────────────

const DEFAULT_PERMISSIONS: FamilyPermissions = {
  canViewProfile: true,
  canViewPhotos: true,
  canViewBasics: true,
  canViewSindhi: true,
  canViewMatches: false,
  canSuggest: true,
  canViewCulturalScore: true,
  canViewKundli: true,
};

// ─── Schemas ────────────────────────────────────────────────────────────────

const inviteSchema = z.object({
  roleTag: z.string().max(50).optional(),
});

const joinSchema = z.object({
  code: z
    .string()
    .regex(/^MM-[A-Z0-9]{6}$/, 'Invalid invite code format (expected MM-XXXXXX)'),
  role_tag: z.string().max(50, 'Role tag must be 50 characters or less'),
});

const updateMemberSchema = z.object({
  permissions: z.object({
    canViewProfile: z.boolean().optional(),
    canViewPhotos: z.boolean().optional(),
    canViewBasics: z.boolean().optional(),
    canViewSindhi: z.boolean().optional(),
    canViewMatches: z.boolean().optional(),
    canSuggest: z.boolean().optional(),
    canViewCulturalScore: z.boolean().optional(),
    canViewKundli: z.boolean().optional(),
  }).optional(),
  is_revoked: z.boolean().optional(),
  revoke_all: z.boolean().optional(),
});

const suggestSchema = z.object({
  suggestedUserId: z.string().uuid('Invalid suggested user ID'),
  note: z.string().max(200, 'Note must be 200 characters or less').optional(),
});

// ─── Helper: Generate MM-XXXXXX invite code ─────────────────────────────────

function generateInviteCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No I, O, 0, 1 for clarity
  let code = '';
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return `MM-${code}`;
}

// ─── Helper: Privacy wall — verify family member has valid access ───────────

async function verifyFamilyMemberAccess(
  familyUserId: string,
  requirePermission?: keyof FamilyPermissions
): Promise<{ membership: any; ownerId: string }> {
  const { data: membership, error } = await supabase
    .from('family_access')
    .select('*')
    .eq('family_user_id', familyUserId)
    .eq('is_revoked', false)
    .single();

  if (error || !membership) {
    throw new AppError(403, 'No active family connection found', 'NO_FAMILY_ACCESS');
  }

  // Check if the invite code has expired
  if (membership.expires_at && new Date(membership.expires_at) < new Date()) {
    throw new AppError(403, 'Family access has expired', 'FAMILY_EXPIRED');
  }

  // Check specific permission if required
  if (requirePermission) {
    const permissions = membership.permissions as FamilyPermissions;
    if (!permissions || !permissions[requirePermission]) {
      throw new AppError(
        403,
        `You do not have '${requirePermission}' permission`,
        'PERMISSION_DENIED'
      );
    }
  }

  return { membership, ownerId: membership.owner_id };
}

// ─── PRIVACY WALL: Family members CANNOT access messages, matches, or likes ─

function assertNotRestrictedEndpoint(path: string): void {
  const restricted = ['/messages', '/matches', '/likes', '/chat', '/inbox'];
  const normalized = path.toLowerCase();
  for (const r of restricted) {
    if (normalized.includes(r)) {
      throw new AppError(
        403,
        'Family members cannot access messages, matches, or likes',
        'FAMILY_PRIVACY_WALL'
      );
    }
  }
}

// ─── POST /v1/family/invite ─────────────────────────────────────────────────

router.post(
  '/invite',
  authenticate,
  validate(inviteSchema),
  rateLimit({ maxRequests: 10, windowSeconds: 60, keyPrefix: 'rl_family_invite' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;

    // Check current family member count (max 3)
    const { data: existingMembers, error: countError } = await supabase
      .from('family_access')
      .select('id')
      .eq('owner_id', user.id)
      .eq('is_revoked', false);

    if (countError) {
      throw new AppError(500, 'Failed to check family member count', 'FAMILY_CHECK_FAILED');
    }

    if (existingMembers && existingMembers.length >= MAX_FAMILY_MEMBERS) {
      throw new AppError(
        400,
        `Maximum ${MAX_FAMILY_MEMBERS} family members allowed. Revoke an existing member first.`,
        'MAX_FAMILY_MEMBERS'
      );
    }

    // Generate unique code with collision check
    let code: string;
    let attempts = 0;
    do {
      code = generateInviteCode();
      const { data: existing } = await supabase
        .from('family_access')
        .select('id')
        .eq('invite_code', code)
        .limit(1)
        .maybeSingle();
      if (!existing) break;
      attempts++;
    } while (attempts < 10);

    if (attempts >= 10) {
      throw new AppError(500, 'Failed to generate unique invite code', 'CODE_GEN_FAILED');
    }

    // Set expiry to 48 hours
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + INVITE_EXPIRY_HOURS);

    // Store in family_access as a pending invite
    const { data: invite, error: insertError } = await supabase
      .from('family_access')
      .insert({
        owner_id: user.id,
        invite_code: code,
        is_revoked: false,
        status: 'pending',
        expires_at: expiresAt.toISOString(),
        permissions: DEFAULT_PERMISSIONS,
      })
      .select()
      .single();

    if (insertError) {
      throw new AppError(500, 'Failed to create invite', 'INVITE_CREATE_FAILED');
    }

    // Build shareable deep link
    const appScheme = process.env.APP_DEEP_LINK_SCHEME || 'mitimaiti';
    const deepLink = `${appScheme}://family/join?code=${code}`;

    res.status(201).json({
      success: true,
      data: {
        inviteId: invite.id,
        code,
        deepLink,
        expiresAt: expiresAt.toISOString(),
        currentMembers: (existingMembers?.length || 0),
        maxMembers: MAX_FAMILY_MEMBERS,
      },
    });
  })
);

// ─── POST /v1/family/join ───────────────────────────────────────────────────

router.post(
  '/join',
  authenticate,
  validate(joinSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { code, role_tag: roleTag } = req.body;

    // Find the pending invite by code
    const { data: invite, error } = await supabase
      .from('family_access')
      .select('*')
      .eq('invite_code', code)
      .eq('status', 'pending')
      .eq('is_revoked', false)
      .single();

    if (error || !invite) {
      throw new AppError(404, 'Invalid or expired invite code', 'INVITE_NOT_FOUND');
    }

    // Check if expired
    if (new Date(invite.expires_at) < new Date()) {
      // Mark as expired
      await supabase
        .from('family_access')
        .update({ status: 'expired' })
        .eq('id', invite.id);
      throw new AppError(400, 'This invite code has expired', 'INVITE_EXPIRED');
    }

    // Cannot join your own invite
    if (invite.owner_id === user.id) {
      throw new AppError(400, 'Cannot join your own family invite', 'SELF_JOIN');
    }

    // Check if user is already a family member for this owner
    const { data: existingMember } = await supabase
      .from('family_access')
      .select('id')
      .eq('owner_id', invite.owner_id)
      .eq('family_user_id', user.id)
      .eq('is_revoked', false)
      .limit(1)
      .maybeSingle();

    if (existingMember) {
      throw new AppError(400, 'You are already a family member for this user', 'ALREADY_MEMBER');
    }

    // Check max 3 members for this owner
    const { data: currentMembers } = await supabase
      .from('family_access')
      .select('id')
      .eq('owner_id', invite.owner_id)
      .eq('is_revoked', false)
      .neq('status', 'pending');

    if (currentMembers && currentMembers.length >= MAX_FAMILY_MEMBERS) {
      throw new AppError(
        400,
        `This user already has the maximum of ${MAX_FAMILY_MEMBERS} family members`,
        'MAX_FAMILY_MEMBERS'
      );
    }

    // Activate the invite row: set family_user_id, role_tag, and status
    const { data: activatedAccess, error: updateError } = await supabase
      .from('family_access')
      .update({
        family_user_id: user.id,
        role_tag: roleTag,
        status: 'active',
        permissions: DEFAULT_PERMISSIONS,
        joined_at: new Date().toISOString(),
      })
      .eq('id', invite.id)
      .select()
      .single();

    if (updateError) {
      throw new AppError(500, 'Failed to join family', 'JOIN_FAILED');
    }

    // Notify the owner
    await sendTemplateNotification('family_joined', invite.owner_id);

    res.status(201).json({
      success: true,
      data: {
        accessId: activatedAccess.id,
        roleTag,
        permissions: DEFAULT_PERMISSIONS,
        ownerId: invite.owner_id,
      },
    });
  })
);

// ─── GET /v1/family ─────────────────────────────────────────────────────────

router.get(
  '/',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;

    // Get family members where this user is the owner
    const { data: members, error } = await supabase
      .from('family_access')
      .select('*')
      .eq('owner_id', user.id)
      .neq('status', 'pending')
      .order('joined_at', { ascending: false });

    if (error) {
      throw new AppError(500, 'Failed to fetch family members', 'FAMILY_FETCH_FAILED');
    }

    // Enrich with display names
    const enriched = [];
    for (const member of members || []) {
      if (!member.family_user_id) continue;

      const { data: basic } = await supabase
        .from('basic_profiles')
        .select('display_name')
        .eq('user_id', member.family_user_id)
        .single();

      enriched.push({
        id: member.id,
        familyUserId: member.family_user_id,
        displayName: basic?.display_name || 'Family Member',
        roleTag: member.role_tag,
        permissions: member.permissions as FamilyPermissions,
        isRevoked: member.is_revoked,
        joinedAt: member.joined_at,
      });
    }

    // Also check if this user is a family member of someone else
    const { data: memberOf } = await supabase
      .from('family_access')
      .select('id, owner_id, role_tag, permissions, is_revoked, joined_at')
      .eq('family_user_id', user.id)
      .eq('is_revoked', false)
      .eq('status', 'active');

    const memberOfEnriched = [];
    for (const access of memberOf || []) {
      const { data: ownerBasic } = await supabase
        .from('basic_profiles')
        .select('display_name')
        .eq('user_id', access.owner_id)
        .single();

      memberOfEnriched.push({
        id: access.id,
        ownerId: access.owner_id,
        ownerName: ownerBasic?.display_name || 'Unknown',
        roleTag: access.role_tag,
        permissions: access.permissions as FamilyPermissions,
      });
    }

    // Get pending invites for the owner
    const { data: pendingInvites } = await supabase
      .from('family_access')
      .select('id, invite_code, expires_at, created_at')
      .eq('owner_id', user.id)
      .eq('status', 'pending')
      .eq('is_revoked', false);

    res.json({
      success: true,
      data: {
        myFamilyMembers: enriched,
        memberOf: memberOfEnriched,
        pendingInvites: (pendingInvites || []).map((inv: any) => ({
          id: inv.id,
          code: inv.invite_code,
          expiresAt: inv.expires_at,
          createdAt: inv.created_at,
        })),
      },
    });
  })
);

// ─── PATCH /v1/family/:id ───────────────────────────────────────────────────

router.patch(
  '/:id',
  authenticate,
  validate(updateMemberSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { id } = req.params;
    const { permissions, is_revoked, revoke_all } = req.body;

    // Handle revoke_all: revoke all family members at once
    if (revoke_all === true) {
      const { data: allMembers, error: fetchError } = await supabase
        .from('family_access')
        .select('id')
        .eq('owner_id', user.id)
        .eq('is_revoked', false)
        .neq('status', 'pending');

      if (fetchError) {
        throw new AppError(500, 'Failed to fetch family members', 'FETCH_FAILED');
      }

      if (!allMembers || allMembers.length === 0) {
        throw new AppError(404, 'No active family members found', 'NO_MEMBERS');
      }

      const memberIds = allMembers.map((m: any) => m.id);

      const { error: revokeError } = await supabase
        .from('family_access')
        .update({ is_revoked: true, revoked_at: new Date().toISOString() })
        .in('id', memberIds);

      if (revokeError) {
        throw new AppError(500, 'Failed to revoke all family members', 'REVOKE_ALL_FAILED');
      }

      // Notify each revoked member
      for (const member of allMembers) {
        const { data: memberData } = await supabase
          .from('family_access')
          .select('family_user_id')
          .eq('id', member.id)
          .single();

        if (memberData?.family_user_id) {
          await sendTemplateNotification('access_revoked', memberData.family_user_id).catch(() => {});
        }
      }

      res.json({
        success: true,
        message: `All ${allMembers.length} family members have been revoked`,
        data: { revokedCount: allMembers.length },
      });
      return;
    }

    // Single member update: find the family_access record
    const { data: member, error: findError } = await supabase
      .from('family_access')
      .select('*')
      .eq('id', id)
      .single();

    if (findError || !member) {
      throw new AppError(404, 'Family member not found', 'MEMBER_NOT_FOUND');
    }

    // Only the owner can update permissions
    if (member.owner_id !== user.id) {
      throw new AppError(403, 'Only the account owner can modify family permissions', 'NOT_OWNER');
    }

    // Handle revocation
    if (is_revoked === true) {
      const { error: revokeError } = await supabase
        .from('family_access')
        .update({ is_revoked: true, revoked_at: new Date().toISOString() })
        .eq('id', id);

      if (revokeError) {
        throw new AppError(500, 'Failed to revoke family member', 'REVOKE_FAILED');
      }

      // Notify the revoked member
      if (member.family_user_id) {
        await sendTemplateNotification('access_revoked', member.family_user_id).catch(() => {});
      }

      res.json({
        success: true,
        message: 'Family member access revoked',
      });
      return;
    }

    // Handle permission updates (8 boolean toggles in permissions jsonb)
    if (permissions && Object.keys(permissions).length > 0) {
      // Validate all provided keys are valid FamilyPermissions keys
      const validKeys: (keyof FamilyPermissions)[] = [
        'canViewProfile', 'canViewPhotos', 'canViewBasics', 'canViewSindhi',
        'canViewMatches', 'canSuggest', 'canViewCulturalScore', 'canViewKundli',
      ];

      for (const key of Object.keys(permissions)) {
        if (!validKeys.includes(key as keyof FamilyPermissions)) {
          throw new AppError(
            400,
            `Invalid permission key: '${key}'. Valid keys: ${validKeys.join(', ')}`,
            'INVALID_PERMISSION_KEY'
          );
        }
      }

      // Merge with existing permissions
      const currentPermissions = (member.permissions || DEFAULT_PERMISSIONS) as FamilyPermissions;
      const updatedPermissions: FamilyPermissions = {
        ...currentPermissions,
        ...permissions,
      };

      const { data: updated, error: updateError } = await supabase
        .from('family_access')
        .update({ permissions: updatedPermissions })
        .eq('id', id)
        .select()
        .single();

      if (updateError) {
        throw new AppError(500, 'Failed to update permissions', 'UPDATE_FAILED');
      }

      res.json({
        success: true,
        data: {
          id: updated.id,
          permissions: updated.permissions as FamilyPermissions,
        },
      });
      return;
    }

    throw new AppError(400, 'No updates provided. Provide permissions or is_revoked.', 'EMPTY_UPDATE');
  })
);

// ─── POST /v1/family/suggest ────────────────────────────────────────────────

router.post(
  '/suggest',
  authenticate,
  validate(suggestSchema),
  rateLimit({ maxRequests: 10, windowSeconds: 60, keyPrefix: 'rl_family_suggest' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { suggestedUserId, note } = req.body;

    // PRIVACY WALL: This endpoint is for family members only
    // Verify the caller is an active family member
    const { membership, ownerId } = await verifyFamilyMemberAccess(user.id);

    // Check that the family member has not been revoked
    if (membership.is_revoked) {
      throw new AppError(403, 'Your family access has been revoked', 'ACCESS_REVOKED');
    }

    // Check daily suggestion limit (max 5/day per family member)
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const { data: todaySuggestions, error: countError } = await supabase
      .from('family_suggestions')
      .select('id')
      .eq('suggested_by', user.id)
      .gte('created_at', todayStart.toISOString());

    if (countError) {
      throw new AppError(500, 'Failed to check suggestion count', 'SUGGESTION_CHECK_FAILED');
    }

    if (todaySuggestions && todaySuggestions.length >= MAX_SUGGESTIONS_PER_DAY) {
      throw new AppError(
        429,
        `Maximum ${MAX_SUGGESTIONS_PER_DAY} suggestions per day. Try again tomorrow.`,
        'DAILY_SUGGESTION_LIMIT'
      );
    }

    // Verify the suggested user exists and is active
    const { data: suggestedUser } = await supabase
      .from('users')
      .select('id, is_active')
      .eq('id', suggestedUserId)
      .single();

    if (!suggestedUser || !suggestedUser.is_active) {
      throw new AppError(404, 'Suggested user not found', 'SUGGESTED_USER_NOT_FOUND');
    }

    // Cannot suggest the owner themselves
    if (suggestedUserId === ownerId) {
      throw new AppError(400, 'Cannot suggest the profile owner to themselves', 'SELF_SUGGEST');
    }

    // Cannot suggest yourself
    if (suggestedUserId === user.id) {
      throw new AppError(400, 'Cannot suggest yourself', 'SELF_SUGGEST');
    }

    // Check for duplicate suggestion
    const { data: existing } = await supabase
      .from('family_suggestions')
      .select('id')
      .eq('target_user_id', ownerId)
      .eq('suggested_user_id', suggestedUserId)
      .eq('suggested_by', user.id)
      .limit(1)
      .maybeSingle();

    if (existing) {
      throw new AppError(400, 'You have already suggested this profile', 'DUPLICATE_SUGGESTION');
    }

    // Create suggestion
    const { data: suggestion, error: insertError } = await supabase
      .from('family_suggestions')
      .insert({
        target_user_id: ownerId,
        suggested_user_id: suggestedUserId,
        suggested_by: user.id,
        note: note || null,
        status: 'pending',
      })
      .select()
      .single();

    if (insertError) {
      throw new AppError(500, 'Failed to create suggestion', 'SUGGESTION_FAILED');
    }

    // Notify the owner
    await sendTemplateNotification('family_suggestion', ownerId).catch(() => {});

    res.status(201).json({
      success: true,
      data: {
        suggestionId: suggestion.id,
        status: 'pending',
      },
    });
  })
);

// ─── GET /v1/family/feed ────────────────────────────────────────────────────

router.get(
  '/feed',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const cursor = req.query.cursor as string | undefined;
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);

    // PRIVACY WALL: Verify the caller is an active family member
    const { membership, ownerId } = await verifyFamilyMemberAccess(user.id);
    const permissions = membership.permissions as FamilyPermissions;

    // Get the owner's gender preference for the discovery feed
    const { data: ownerSettings } = await supabase
      .from('user_settings')
      .select('gender_preference, age_min, age_max')
      .eq('user_id', ownerId)
      .single();

    if (!ownerSettings) {
      throw new AppError(400, 'Owner profile settings not found', 'OWNER_SETTINGS_MISSING');
    }

    // Get blocked users for the owner (both directions)
    const { data: blocks } = await supabase
      .from('blocked_users')
      .select('blocker_id, blocked_id')
      .or(`blocker_id.eq.${ownerId},blocked_id.eq.${ownerId}`);

    const blockedIds = new Set<string>();
    (blocks || []).forEach((b: any) => {
      blockedIds.add(b.blocker_id === ownerId ? b.blocked_id : b.blocker_id);
    });

    // Also exclude the owner and the family member themselves
    blockedIds.add(ownerId);
    blockedIds.add(user.id);

    // Build discovery query based on owner's preferences
    const genderPreference = ownerSettings.gender_preference || 'everyone';
    const ageMin = ownerSettings.age_min || 18;
    const ageMax = ownerSettings.age_max || 50;

    const now = new Date();
    const maxDob = new Date(now.getFullYear() - ageMin, now.getMonth(), now.getDate())
      .toISOString()
      .split('T')[0];
    const minDob = new Date(now.getFullYear() - ageMax - 1, now.getMonth(), now.getDate())
      .toISOString()
      .split('T')[0];

    // Build the select fields based on permissions
    const selectFields: string[] = ['user_id', 'display_name', 'date_of_birth', 'gender', 'city', 'country', 'intent'];
    if (permissions.canViewBasics) selectFields.push('education', 'occupation');
    if (permissions.canViewProfile) selectFields.push('bio');

    let query = supabase
      .from('basic_profiles')
      .select(selectFields.join(', '))
      .gte('date_of_birth', minDob)
      .lte('date_of_birth', maxDob);

    if (genderPreference === 'men') {
      query = query.eq('gender', 'man');
    } else if (genderPreference === 'women') {
      query = query.eq('gender', 'woman');
    }

    if (cursor) {
      query = query.gt('user_id', cursor);
    }

    query = query.limit(limit * 2); // Fetch extra to account for exclusions

    const { data: candidates, error: queryError } = await query as { data: any[] | null; error: any };

    if (queryError) {
      throw new AppError(500, 'Failed to fetch family discovery feed', 'FEED_ERROR');
    }

    // Filter out blocked and excluded users
    const filtered = (candidates || []).filter(
      (c: any) => !blockedIds.has(c.user_id)
    ).slice(0, limit);

    // Enrich with photos (if permission allows) and verification status
    const enriched = [];
    for (const candidate of filtered) {
      const enrichedCard: Record<string, any> = {
        userId: candidate.user_id,
        displayName: candidate.display_name,
        age: candidate.date_of_birth
          ? Math.floor((Date.now() - new Date(candidate.date_of_birth).getTime()) / (365.25 * 24 * 60 * 60 * 1000))
          : null,
        city: candidate.city,
        country: candidate.country,
        intent: candidate.intent,
        gender: candidate.gender,
      };

      if (permissions.canViewBasics) {
        enrichedCard.education = candidate.education;
        enrichedCard.occupation = candidate.occupation;
      }

      if (permissions.canViewProfile) {
        enrichedCard.bio = candidate.bio;
      }

      // Photos (only if permitted)
      if (permissions.canViewPhotos) {
        const { data: photos } = await supabase
          .from('photos')
          .select('url_medium, url_thumb, is_primary')
          .eq('user_id', candidate.user_id)
          .order('sort_order')
          .limit(3);

        enrichedCard.photos = (photos || []).map((p: any) => ({
          urlMedium: p.url_medium,
          urlThumb: p.url_thumb,
          isPrimary: p.is_primary,
        }));
      }

      // Cultural badges (only if permitted)
      if (permissions.canViewCulturalScore) {
        try {
          const { getCulturalScore } = await import('../services/scoring');
          const cs = await getCulturalScore(ownerId, candidate.user_id);
          enrichedCard.culturalScore = cs.total;
          enrichedCard.culturalBadge = cs.badge;
        } catch {
          enrichedCard.culturalScore = null;
          enrichedCard.culturalBadge = null;
        }
      }

      // Prompts (only if permitted)
      if (permissions.canViewProfile) {
        const { data: prompts } = await supabase
          .from('prompt_answers')
          .select('prompt_id, answer, created_at')
          .eq('user_id', candidate.user_id)
          .order('created_at', { ascending: false })
          .limit(3);

        enrichedCard.prompts = prompts || [];
      }

      // Verification status
      const { data: userMeta } = await supabase
        .from('users')
        .select('is_verified')
        .eq('id', candidate.user_id)
        .single();

      enrichedCard.isVerified = userMeta?.is_verified || false;

      enriched.push(enrichedCard);
    }

    const lastCard = enriched[enriched.length - 1];

    res.json({
      success: true,
      data: {
        ownerId,
        cards: enriched,
        cursor: lastCard ? (lastCard as any).userId : null,
        hasMore: (candidates || []).length > limit,
        // Hard privacy wall enforcement: these fields are intentionally absent
        _privacyNote: 'Family members cannot access matches, chats, or likes',
      },
    });
  })
);

// ─── GET /v1/family/suggestions ─────────────────────────────────────────────

router.get(
  '/suggestions',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const cursor = req.query.cursor as string | undefined;
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 50);

    // This endpoint is for the OWNER user — return suggestions made by family members
    let query = supabase
      .from('family_suggestions')
      .select('*')
      .eq('target_user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (cursor) {
      query = query.lt('created_at', cursor);
    }

    const { data: suggestions, error } = await query;

    if (error) {
      throw new AppError(500, 'Failed to fetch suggestions', 'SUGGESTIONS_FETCH_FAILED');
    }

    // Enrich with suggester name and suggested profile info
    const enriched = [];
    for (const suggestion of suggestions || []) {
      // Get suggester (family member) name
      const { data: suggesterBasic } = await supabase
        .from('basic_profiles')
        .select('display_name')
        .eq('user_id', suggestion.suggested_by)
        .single();

      // Get suggested profile info
      const { data: suggestedBasic } = await supabase
        .from('basic_profiles')
        .select('display_name, city, country, date_of_birth')
        .eq('user_id', suggestion.suggested_user_id)
        .single();

      const { data: suggestedPhoto } = await supabase
        .from('photos')
        .select('url_thumb')
        .eq('user_id', suggestion.suggested_user_id)
        .eq('is_primary', true)
        .limit(1)
        .maybeSingle();

      enriched.push({
        id: suggestion.id,
        suggestedUserId: suggestion.suggested_user_id,
        suggestedBy: {
          userId: suggestion.suggested_by,
          displayName: suggesterBasic?.display_name || 'Family Member',
        },
        suggestedProfile: {
          displayName: suggestedBasic?.display_name || 'Unknown',
          city: suggestedBasic?.city,
          country: suggestedBasic?.country,
          age: suggestedBasic?.date_of_birth
            ? Math.floor((Date.now() - new Date(suggestedBasic.date_of_birth).getTime()) / (365.25 * 24 * 60 * 60 * 1000))
            : null,
          photo: suggestedPhoto?.url_thumb || null,
        },
        note: suggestion.note,
        status: suggestion.status,
        createdAt: suggestion.created_at,
      });
    }

    const lastSuggestion = suggestions?.[suggestions.length - 1];

    res.json({
      success: true,
      data: {
        suggestions: enriched,
        cursor: lastSuggestion?.created_at || null,
        hasMore: (suggestions?.length || 0) >= limit,
      },
    });
  })
);

export default router;
