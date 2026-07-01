import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { supabase } from '../config/supabase';
import { AppError, asyncHandler } from '../utils/errors';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { strictRateLimit } from '../middleware/rateLimit';
import { AuthenticatedRequest, ReportReason, ReportPriority } from '../types';

const router = Router();

// ─── Constants ──────────────────────────────────────────────────────────────

const AUTO_HIDE_THRESHOLD = 5;

// ─── Schemas ────────────────────────────────────────────────────────────────

const reportSchema = z.object({
  reported_id: z.string().uuid('Invalid user ID'),
  reason: z.enum(['fake', 'harassment', 'spam', 'photos', 'underage', 'safety'] as const),
  details: z.string().max(1000, 'Details must be 1000 characters or less').optional(),
});

const blockSchema = z.object({
  blocked_id: z.string().uuid('Invalid user ID'),
});

const appealSchema = z.object({
  strikeId: z.string().uuid('Invalid strike ID'),
  text: z.string().min(10, 'Appeal text must be at least 10 characters').max(1000, 'Appeal text must be 1000 characters or less'),
});

// ─── Auto-priority mapping ─────────────────────────────────────────────────

function computeReportPriority(reason: ReportReason): ReportPriority {
  const priorityMap: Record<ReportReason, ReportPriority> = {
    underage: 'P0',
    safety: 'P0',
    harassment: 'P1',
    fake: 'P2',
    spam: 'P2',
    photos: 'P2',
  };
  return priorityMap[reason];
}

// ─── POST /v1/safety/report ─────────────────────────────────────────────────

router.post(
  '/report',
  authenticate,
  strictRateLimit,
  validate(reportSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { reported_id: reportedId, reason, details } = req.body;

    // Cannot report yourself
    if (reportedId === user.id) {
      throw new AppError(400, 'Cannot report yourself', 'SELF_REPORT');
    }

    // Check target exists
    const { data: target } = await supabase
      .from('users')
      .select('id, is_active, is_hidden')
      .eq('id', reportedId)
      .single();

    if (!target) {
      throw new AppError(404, 'Reported user not found', 'USER_NOT_FOUND');
    }

    // Check for duplicate recent report (within 1 hour)
    const oneHourAgo = new Date(Date.now() - 3600000).toISOString();
    const { data: recentReport } = await supabase
      .from('reports')
      .select('id')
      .eq('reporter_id', user.id)
      .eq('reported_id', reportedId)
      .gte('created_at', oneHourAgo)
      .limit(1)
      .maybeSingle();

    if (recentReport) {
      throw new AppError(
        400,
        'You have already reported this user recently. Please wait before reporting again.',
        'DUPLICATE_REPORT'
      );
    }

    const priority = computeReportPriority(reason);

    // Create report
    const { data: report, error: reportError } = await supabase
      .from('reports')
      .insert({
        reporter_id: user.id,
        reported_id: reportedId,
        reason,
        details: details || null,
        priority,
        status: 'pending',
      })
      .select()
      .single();

    if (reportError) {
      throw new AppError(500, 'Failed to create report', 'REPORT_FAILED');
    }

    // Log critical reports immediately
    if (priority === 'P0') {
      console.warn(
        `[Safety] P0 CRITICAL REPORT: ${report.id} - Reason: ${reason} - Reporter: ${user.id} - Target: ${reportedId}`
      );
    }

    // Check total report count on this user (all time)
    const { count: totalReportCount } = await supabase
      .from('reports')
      .select('*', { count: 'exact', head: true })
      .eq('reported_id', reportedId);

    // Auto-hide if 5+ reports on this user
    if (totalReportCount && totalReportCount >= AUTO_HIDE_THRESHOLD && !target.is_hidden) {
      await supabase
        .from('users')
        .update({ is_hidden: true })
        .eq('id', reportedId);

      console.warn(
        `[Safety] AUTO-HIDE: User ${reportedId} received ${totalReportCount} total reports, setting is_hidden=true`
      );
    }

    res.status(201).json({
      success: true,
      data: {
        reportId: report.id,
        priority,
        status: 'pending',
        message: 'Thank you for keeping our community safe. We will review this report.',
      },
    });
  })
);

// ─── POST /v1/safety/block ──────────────────────────────────────────────────

router.post(
  '/block',
  authenticate,
  validate(blockSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { blocked_id: blockedId } = req.body;

    // Cannot block yourself
    if (blockedId === user.id) {
      throw new AppError(400, 'Cannot block yourself', 'SELF_BLOCK');
    }

    // Verify target exists
    const { data: targetUser } = await supabase
      .from('users')
      .select('id')
      .eq('id', blockedId)
      .single();

    if (!targetUser) {
      throw new AppError(404, 'User not found', 'USER_NOT_FOUND');
    }

    // Check if already blocked (either direction)
    const { data: existingBlock } = await supabase
      .from('blocked_users')
      .select('id')
      .or(
        `and(blocker_id.eq.${user.id},blocked_id.eq.${blockedId}),and(blocker_id.eq.${blockedId},blocked_id.eq.${user.id})`
      )
      .limit(1)
      .maybeSingle();

    if (existingBlock) {
      throw new AppError(400, 'Block already exists between these users', 'ALREADY_BLOCKED');
    }

    // Insert blocks in both directions for bidirectional invisibility
    const { error: blockError } = await supabase
      .from('blocked_users')
      .insert([
        { blocker_id: user.id, blocked_id: blockedId },
        { blocker_id: blockedId, blocked_id: user.id },
      ]);

    if (blockError) {
      throw new AppError(500, 'Failed to block user', 'BLOCK_FAILED');
    }

    // Dissolve any active match between them
    const { data: activeMatches } = await supabase
      .from('matches')
      .select('id')
      .or(
        `and(user_a_id.eq.${user.id},user_b_id.eq.${blockedId}),and(user_a_id.eq.${blockedId},user_b_id.eq.${user.id})`
      )
      .eq('status', 'active');

    if (activeMatches && activeMatches.length > 0) {
      const matchIds = activeMatches.map((m: any) => m.id);

      await supabase
        .from('matches')
        .update({
          status: 'dissolved',
          is_dissolved: true,
          dissolved_at: new Date().toISOString(),
          dissolved_reason: 'blocked',
        })
        .in('id', matchIds);

      console.log(
        `[Safety] Dissolved ${matchIds.length} active match(es) between ${user.id} and ${blockedId}`
      );
    }

    res.json({
      success: true,
      message: 'User blocked successfully. They will no longer appear in your feed or conversations.',
      data: {
        blockedId,
        matchesDissolved: activeMatches?.length || 0,
      },
    });
  })
);

// ─── GET /v1/safety/health ──────────────────────────────────────────────────

router.get(
  '/health',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;

    // Get user safety record
    const { data: safetyRecord } = await supabase
      .from('user_safety')
      .select('*')
      .eq('user_id', user.id)
      .single();

    // Get strikes with their appeal status
    const { data: strikes } = await supabase
      .from('strikes')
      .select('id, reason, severity, is_appealed, appeal_status, created_at, expires_at')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false });

    // Count active (non-expired, non-overturned) strikes
    const now = new Date();
    const activeStrikes = (strikes || []).filter((s: any) => {
      const isExpired = s.expires_at && new Date(s.expires_at) < now;
      const isOverturned = s.appeal_status === 'overturned';
      return !isExpired && !isOverturned;
    });

    // Get appeal status for any pending appeals
    const pendingAppeals = (strikes || []).filter(
      (s: any) => s.is_appealed && s.appeal_status === 'pending'
    );

    res.json({
      success: true,
      data: {
        strikeCount: activeStrikes.length,
        totalStrikesEver: strikes?.length || 0,
        suspension: {
          isSuspended: safetyRecord?.is_suspended || false,
          suspensionUntil: safetyRecord?.suspension_until || null,
          isPermanentlyBanned: safetyRecord?.is_permanently_banned || false,
        },
        strikes: (strikes || []).map((s: any) => ({
          id: s.id,
          reason: s.reason,
          severity: s.severity,
          isAppealed: s.is_appealed || false,
          appealStatus: s.appeal_status || null,
          isExpired: s.expires_at ? new Date(s.expires_at) < now : false,
          createdAt: s.created_at,
          expiresAt: s.expires_at,
        })),
        appeals: {
          pendingCount: pendingAppeals.length,
          pending: pendingAppeals.map((s: any) => ({
            strikeId: s.id,
            reason: s.reason,
          })),
        },
      },
    });
  })
);

// ─── POST /v1/safety/appeal ─────────────────────────────────────────────────

router.post(
  '/appeal',
  authenticate,
  strictRateLimit,
  validate(appealSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { strikeId, text } = req.body;

    // Find the strike and verify ownership
    const { data: strike, error: strikeError } = await supabase
      .from('strikes')
      .select('*')
      .eq('id', strikeId)
      .eq('user_id', user.id)
      .single();

    if (strikeError || !strike) {
      throw new AppError(404, 'Strike not found', 'STRIKE_NOT_FOUND');
    }

    // Check if strike is still active (not expired)
    if (strike.expires_at && new Date(strike.expires_at) < new Date()) {
      throw new AppError(
        400,
        'This strike has already expired and cannot be appealed',
        'STRIKE_EXPIRED'
      );
    }

    // Only 1 appeal per strike
    if (strike.is_appealed) {
      throw new AppError(
        400,
        'This strike has already been appealed. Only one appeal is allowed per strike.',
        'ALREADY_APPEALED'
      );
    }

    // Create the appeal
    const { data: appeal, error: appealError } = await supabase
      .from('appeals')
      .insert({
        strike_id: strikeId,
        user_id: user.id,
        text,
        status: 'pending',
      })
      .select()
      .single();

    if (appealError) {
      throw new AppError(500, 'Failed to submit appeal', 'APPEAL_FAILED');
    }

    // Mark the strike as appealed
    const { error: updateError } = await supabase
      .from('strikes')
      .update({
        is_appealed: true,
        appeal_status: 'pending',
      })
      .eq('id', strikeId);

    if (updateError) {
      throw new AppError(500, 'Failed to update strike appeal status', 'STRIKE_UPDATE_FAILED');
    }

    res.status(201).json({
      success: true,
      data: {
        appealId: appeal.id,
        strikeId,
        status: 'pending',
        message: 'Your appeal has been submitted and will be reviewed within 24-48 hours.',
      },
    });
  })
);

export default router;
