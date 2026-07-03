import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { supabase } from '../config/supabase';
import { AppError, asyncHandler } from '../utils/errors';
import { authenticate, requireAdmin } from '../middleware/auth';
import { validate, validateParams } from '../middleware/validate';
import { AuthenticatedRequest, AdminAction } from '../types';
import { sendPush } from '../services/notifications';

const router = Router();

// All admin routes require authentication + admin role
router.use(authenticate);
router.use(requireAdmin);

// ─── Schemas ─────────────────────────────────────────────────────────────────

const moderationActionSchema = z.object({
  reportId: z.string().uuid('Invalid report ID'),
  action: z.enum(['dismiss', 'warn', 'suspend', 'ban']),
  note: z.string().min(1).max(1000),
  instantBan: z.boolean().optional().default(false),
});

const dailyPromptSchema = z.object({
  question: z.string().min(5).max(200),
  category: z.string().min(1).max(50).optional(),
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD format')
    .optional(),
});

// ─── GET /v1/admin/queue ─────────────────────────────────────────────────────
// Moderation queue sorted by priority P0 -> P1 -> P2.
// Includes reporter count, elapsed time. Paginated.

router.get(
  '/queue',
  asyncHandler(async (req: Request, res: Response) => {
    const page = parseInt(req.query.page as string) || 1;
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 100);
    const offset = (page - 1) * limit;
    const status = (req.query.status as string) || 'pending';
    const priority = req.query.priority as string | undefined;

    // Priority ordering: P0 first, then P1, then P2
    // We use a custom sort: P0=0, P1=1, P2=2
    let query = supabase
      .from('reports')
      .select('*', { count: 'exact' })
      .eq('status', status)
      .order('priority', { ascending: true })  // P0 < P1 < P2 alphabetically
      .order('created_at', { ascending: true }) // FIFO within priority
      .range(offset, offset + limit - 1);

    if (priority) {
      query = query.eq('priority', priority);
    }

    const { data: reports, count, error } = await query;

    if (error) {
      throw new AppError(500, 'Failed to fetch moderation queue', 'QUEUE_ERROR');
    }

    // Enrich reports with reporter count and elapsed time
    const enrichedReports = (reports || []).map((report) => {
      const createdAt = new Date(report.created_at);
      const elapsedMs = Date.now() - createdAt.getTime();
      const elapsedMinutes = Math.floor(elapsedMs / 60000);
      const elapsedHours = Math.floor(elapsedMinutes / 60);

      let elapsedDisplay: string;
      if (elapsedHours >= 24) {
        elapsedDisplay = `${Math.floor(elapsedHours / 24)}d ${elapsedHours % 24}h`;
      } else if (elapsedHours > 0) {
        elapsedDisplay = `${elapsedHours}h ${elapsedMinutes % 60}m`;
      } else {
        elapsedDisplay = `${elapsedMinutes}m`;
      }

      return {
        ...report,
        // DB column is reported_id; the admin frontend consumes reported_user_id
        reported_user_id: report.reported_id,
        elapsed_time: elapsedDisplay,
        elapsed_minutes: elapsedMinutes,
      };
    });

    // Get reporter counts for each reported user (how many unique reporters)
    const reportedUserIds = [...new Set((reports || []).map((r) => r.reported_id))];
    const reporterCounts: Record<string, number> = {};

    if (reportedUserIds.length > 0) {
      for (const reportedUserId of reportedUserIds) {
        const { count: reporterCount } = await supabase
          .from('reports')
          .select('reporter_id', { count: 'exact', head: true })
          .eq('reported_id', reportedUserId)
          .eq('status', 'pending');

        reporterCounts[reportedUserId] = reporterCount || 0;
      }
    }

    const finalReports = enrichedReports.map((report) => ({
      ...report,
      reporter_count: reporterCounts[report.reported_id] || 0,
    }));

    res.json({
      success: true,
      data: {
        reports: finalReports,
        pagination: {
          page,
          limit,
          total: count || 0,
          totalPages: Math.ceil((count || 0) / limit),
        },
      },
    });
  })
);

// ─── GET /v1/admin/queue/:id ─────────────────────────────────────────────────
// Single report with full profiles of reporter + reported.

router.get(
  '/queue/:id',
  asyncHandler(async (req: Request, res: Response) => {
    const { id } = req.params;

    const { data: report, error } = await supabase
      .from('reports')
      .select('*')
      .eq('id', id)
      .single();

    if (error || !report) {
      throw new AppError(404, 'Report not found', 'REPORT_NOT_FOUND');
    }

    // Fetch full profiles for both reporter and reported
    const [
      { data: reporter },
      { data: reported },
      { data: reporterBasic },
      { data: reportedBasic },
      { data: reportedSindhi },
      { data: reportedPhotos },
      { data: priorReports },
      { data: priorStrikes },
    ] = await Promise.all([
      supabase
        .from('users')
        .select('id, phone, created_at, is_verified, is_suspended, is_banned')
        .eq('id', report.reporter_id)
        .single(),
      supabase
        .from('users')
        .select('id, phone, created_at, is_verified, is_suspended, is_banned, strikes')
        .eq('id', report.reported_id)
        .single(),
      supabase
        .from('basic_profiles')
        .select('display_name, city, country, bio')
        .eq('user_id', report.reporter_id)
        .single(),
      supabase
        .from('basic_profiles')
        .select('display_name, bio, city, country, date_of_birth')
        .eq('user_id', report.reported_id)
        .single(),
      supabase
        .from('sindhi_profiles')
        .select('*')
        .eq('user_id', report.reported_id)
        .single(),
      supabase
        .from('photos')
        .select('id, url_medium, url_thumb, is_primary, sort_order')
        .eq('user_id', report.reported_id)
        .order('sort_order'),
      supabase
        .from('reports')
        .select('id, reason, priority, status, created_at')
        .eq('reported_id', report.reported_id)
        .neq('id', id)
        .order('created_at', { ascending: false })
        .limit(20),
      supabase
        .from('strikes')
        .select('id, reason, action, status, created_at, expires_at')
        .eq('user_id', report.reported_id)
        .order('created_at', { ascending: false }),
    ]);

    res.json({
      success: true,
      data: {
        report,
        reporter: {
          ...reporter,
          displayName: reporterBasic?.display_name,
          city: reporterBasic?.city,
          country: reporterBasic?.country,
        },
        reported: {
          ...reported,
          displayName: reportedBasic?.display_name,
          bio: reportedBasic?.bio,
          city: reportedBasic?.city,
          country: reportedBasic?.country,
          dateOfBirth: reportedBasic?.date_of_birth,
          sindhiProfile: reportedSindhi,
          photos: reportedPhotos || [],
        },
        priorReports: priorReports || [],
        priorStrikes: priorStrikes || [],
      },
    });
  })
);

// ─── POST /v1/admin/action ───────────────────────────────────────────────────
// Body: {reportId, action: 'dismiss'|'warn'|'suspend'|'ban', note}
// Strike flow: warn = strike #1, suspend = strike #2, ban = strike #3.
// instantBan: skip strike flow.

router.post(
  '/action',
  validate(moderationActionSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const admin = (req as AuthenticatedRequest).user;
    const { reportId, action, note, instantBan } = req.body as {
      reportId: string;
      action: AdminAction;
      note: string;
      instantBan?: boolean;
    };

    // Get the report
    const { data: report, error } = await supabase
      .from('reports')
      .select('*')
      .eq('id', reportId)
      .single();

    if (error || !report) {
      throw new AppError(404, 'Report not found', 'REPORT_NOT_FOUND');
    }

    if (report.status !== 'pending') {
      throw new AppError(400, 'Report has already been reviewed', 'ALREADY_REVIEWED');
    }

    const reportedUserId = report.reported_id;

    // Get current strike count
    const { data: userRow } = await supabase
      .from('users')
      .select('strikes')
      .eq('id', reportedUserId)
      .single();

    const currentStrikes = userRow?.strikes || 0;

    switch (action) {
      // ── Dismiss: mark resolved, no action on user ─────────────────────
      case 'dismiss': {
        await supabase
          .from('reports')
          .update({
            status: 'dismissed',
            moderator_id: admin.id,
            resolution_note: note,
            reviewed_at: new Date().toISOString(),
          })
          .eq('id', reportId);

        break;
      }

      // ── Warn: strike #1 + notification ────────────────────────────────
      case 'warn': {
        // Mark report as actioned
        await supabase
          .from('reports')
          .update({
            status: 'actioned',
            moderator_id: admin.id,
            resolution_note: `Warning: ${note}`,
            reviewed_at: new Date().toISOString(),
          })
          .eq('id', reportId);

        // Add strike
        await supabase.from('strikes').insert({
          user_id: reportedUserId,
          reason: note,
          action: 'warn',
          report_id: reportId,
          moderator_id: admin.id,
          status: 'active',
          expires_at: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString(), // 90 days
        });

        // Increment strike count
        await supabase
          .from('users')
          .update({ strikes: currentStrikes + 1 })
          .eq('id', reportedUserId);

        // Notify user
        await sendPush(reportedUserId, 'strike_issued', {
          title: 'Account Warning',
          body: 'Your account has received a community guideline warning. Please review our guidelines.',
        });

        break;
      }

      // ── Suspend: strike #2 + 7-day suspension ────────────────────────
      case 'suspend': {
        const suspendUntil = new Date();
        suspendUntil.setDate(suspendUntil.getDate() + 7); // 7 days

        // Suspend user
        await supabase
          .from('users')
          .update({
            is_suspended: true,
            ban_expires: suspendUntil.toISOString(),
            strikes: currentStrikes + 1,
          })
          .eq('id', reportedUserId);

        // Update user_safety
        await supabase
          .from('user_safety')
          .update({
            is_suspended: true,
            suspension_until: suspendUntil.toISOString(),
          })
          .eq('user_id', reportedUserId);

        // Mark report
        await supabase
          .from('reports')
          .update({
            status: 'actioned',
            moderator_id: admin.id,
            resolution_note: `Suspended 7 days: ${note}`,
            reviewed_at: new Date().toISOString(),
          })
          .eq('id', reportId);

        // Add strike
        await supabase.from('strikes').insert({
          user_id: reportedUserId,
          reason: note,
          action: 'suspend',
          report_id: reportId,
          moderator_id: admin.id,
          status: 'active',
          expires_at: suspendUntil.toISOString(),
        });

        // Notify user
        await sendPush(reportedUserId, 'strike_issued', {
          title: 'Account Suspended',
          body: `Your account has been suspended for 7 days due to a community guideline violation.`,
        });

        break;
      }

      // ── Ban: strike #3 + permanent ban (or instant ban) ───────────────
      case 'ban': {
        const isPermanent = instantBan || currentStrikes >= 2;

        // Ban user
        await supabase
          .from('users')
          .update({
            is_banned: true,
            is_active: false,
            ban_expires: isPermanent ? null : new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
            strikes: currentStrikes + 1,
          })
          .eq('id', reportedUserId);

        // Update user_safety
        await supabase
          .from('user_safety')
          .update({
            is_permanently_banned: isPermanent,
          })
          .eq('user_id', reportedUserId);

        // Mark report
        await supabase
          .from('reports')
          .update({
            status: 'actioned',
            moderator_id: admin.id,
            resolution_note: `${isPermanent ? 'Permanently banned' : 'Banned'}${instantBan ? ' (instant)' : ''}: ${note}`,
            reviewed_at: new Date().toISOString(),
          })
          .eq('id', reportId);

        // Add strike
        await supabase.from('strikes').insert({
          user_id: reportedUserId,
          reason: note,
          action: instantBan ? 'instant_ban' : 'ban',
          report_id: reportId,
          moderator_id: admin.id,
          status: 'active',
        });

        // Disable discovery
        await supabase
          .from('user_settings')
          .update({ discovery_enabled: false })
          .eq('user_id', reportedUserId);

        break;
      }
    }

    res.json({
      success: true,
      data: {
        reportId,
        action,
        reportedUserId,
        instantBan: instantBan || false,
        message: `Moderation action "${action}" applied successfully`,
      },
    });
  })
);

// ─── GET /v1/admin/user/:id ──────────────────────────────────────────────────
// Full user profile dump including all tables, strike history, report history.

router.get(
  '/user/:id',
  // Guard the raw :id — it is interpolated into a PostgREST .or() filter
  // string below; a UUID gate prevents filter injection (defence-in-depth
  // behind requireAdmin).
  validateParams(z.object({ id: z.string().uuid('Invalid user id') })),
  asyncHandler(async (req: Request, res: Response) => {
    const { id } = req.params;

    const [
      { data: user },
      { data: basic },
      { data: sindhi },
      { data: chatti },
      { data: personality },
      { data: photos },
      { data: settings },
      { data: privileges },
      { data: safety },
      { data: reports },
      { data: strikes },
      { data: matches },
    ] = await Promise.all([
      supabase.from('users').select('*').eq('id', id).single(),
      supabase.from('basic_profiles').select('*').eq('user_id', id).single(),
      supabase.from('sindhi_profiles').select('*').eq('user_id', id).single(),
      supabase.from('chatti_profiles').select('*').eq('user_id', id).single(),
      supabase.from('personality_profiles').select('*').eq('user_id', id).single(),
      supabase.from('photos').select('*').eq('user_id', id).order('sort_order'),
      supabase.from('user_settings').select('*').eq('user_id', id).single(),
      supabase.from('user_privileges').select('*').eq('user_id', id).single(),
      supabase.from('user_safety').select('*').eq('user_id', id).single(),
      supabase
        .from('reports')
        .select('*')
        .eq('reported_id', id)
        .order('created_at', { ascending: false })
        .limit(50),
      supabase
        .from('strikes')
        .select('*')
        .eq('user_id', id)
        .order('created_at', { ascending: false }),
      supabase
        .from('matches')
        .select('id, user_a_id, user_b_id, status, created_at, dissolved_at')
        .or(`user_a_id.eq.${id},user_b_id.eq.${id}`)
        .order('created_at', { ascending: false })
        .limit(20),
    ]);

    if (!user) {
      throw new AppError(404, 'User not found', 'USER_NOT_FOUND');
    }

    // Get aggregate stats
    const [
      { count: likesGiven },
      { count: likesReceived },
      { count: activeMatches },
      { count: messagesSent },
      { count: reportsAgainst },
      { count: reportsFiled },
    ] = await Promise.all([
      supabase
        .from('actions')
        .select('*', { count: 'exact', head: true })
        .eq('actor_id', id)
        .eq('kind', 'like'),
      supabase
        .from('actions')
        .select('*', { count: 'exact', head: true })
        .eq('target_id', id)
        .eq('kind', 'like'),
      supabase
        .from('matches')
        .select('*', { count: 'exact', head: true })
        .or(`user_a_id.eq.${id},user_b_id.eq.${id}`)
        .eq('status', 'active'),
      supabase
        .from('messages')
        .select('*', { count: 'exact', head: true })
        .eq('sender_id', id),
      supabase
        .from('reports')
        .select('*', { count: 'exact', head: true })
        .eq('reported_id', id),
      supabase
        .from('reports')
        .select('*', { count: 'exact', head: true })
        .eq('reporter_id', id),
    ]);

    res.json({
      success: true,
      data: {
        user,
        profile: { basic, sindhi, chatti, personality },
        photos: photos || [],
        settings,
        privileges,
        safety,
        reports: reports || [],
        strikes: strikes || [],
        recentMatches: matches || [],
        stats: {
          likesGiven: likesGiven || 0,
          likesReceived: likesReceived || 0,
          activeMatches: activeMatches || 0,
          messagesSent: messagesSent || 0,
          reportsAgainst: reportsAgainst || 0,
          reportsFiled: reportsFiled || 0,
        },
      },
    });
  })
);

// ─── POST /v1/admin/daily-prompt ─────────────────────────────────────────────
// Override today's prompt. Store in daily_prompts with is_override=true.

router.post(
  '/daily-prompt',
  validate(dailyPromptSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const { question, category, date } = req.body;

    const promptDate = date || new Date().toISOString().split('T')[0];

    // Deactivate any existing prompt for this date
    await supabase
      .from('daily_prompts')
      .update({ is_active: false })
      .eq('date', promptDate);

    // Create new prompt with is_override=true
    const { data: prompt, error } = await supabase
      .from('daily_prompts')
      .insert({
        question,
        category: category || 'general',
        date: promptDate,
        is_active: true,
        is_override: true,
      })
      .select()
      .single();

    if (error) {
      throw new AppError(500, 'Failed to create daily prompt', 'PROMPT_CREATE_FAILED');
    }

    res.status(201).json({
      success: true,
      data: {
        promptId: prompt.id,
        question,
        category: category || 'general',
        date: promptDate,
        isOverride: true,
      },
    });
  })
);

// ─── GET /v1/admin/stats ─────────────────────────────────────────────────────
// Dashboard stats: pending queue size, avg review time, bans this week,
// active users (30d), new signups today.

router.get(
  '/stats',
  asyncHandler(async (_req: Request, res: Response) => {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();

    const [
      { count: pendingQueueSize },
      { count: pendingP0 },
      { count: pendingP1 },
      { count: pendingP2 },
      { data: reviewedReports },
      { count: bansThisWeek },
      { count: suspensionsThisWeek },
      { count: warningsThisWeek },
      { count: activeUsers30d },
      { count: newSignupsToday },
      { count: totalUsers },
      { count: activeMatchCount },
    ] = await Promise.all([
      // Pending queue size
      supabase
        .from('reports')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'pending'),
      // P0 count
      supabase
        .from('reports')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'pending')
        .eq('priority', 'P0'),
      // P1 count
      supabase
        .from('reports')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'pending')
        .eq('priority', 'P1'),
      // P2 count
      supabase
        .from('reports')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'pending')
        .eq('priority', 'P2'),
      // Reviewed reports this week (for avg review time)
      supabase
        .from('reports')
        .select('created_at, reviewed_at')
        .in('status', ['actioned', 'dismissed'])
        .not('reviewed_at', 'is', null)
        .gte('reviewed_at', weekAgo)
        .limit(500),
      // Bans this week
      supabase
        .from('strikes')
        .select('*', { count: 'exact', head: true })
        .in('action', ['ban', 'instant_ban'])
        .gte('created_at', weekAgo),
      // Suspensions this week
      supabase
        .from('strikes')
        .select('*', { count: 'exact', head: true })
        .eq('action', 'suspend')
        .gte('created_at', weekAgo),
      // Warnings this week
      supabase
        .from('strikes')
        .select('*', { count: 'exact', head: true })
        .eq('action', 'warn')
        .gte('created_at', weekAgo),
      // Active users (30d)
      supabase
        .from('users')
        .select('*', { count: 'exact', head: true })
        .eq('is_active', true)
        .eq('is_banned', false)
        .gte('last_active', thirtyDaysAgo),
      // New signups today
      supabase
        .from('users')
        .select('*', { count: 'exact', head: true })
        .gte('created_at', todayStart),
      // Total users
      supabase
        .from('users')
        .select('*', { count: 'exact', head: true })
        .eq('is_active', true),
      // Active matches
      supabase
        .from('matches')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'active'),
    ]);

    // Calculate average review time (in minutes)
    let avgReviewTimeMinutes = 0;
    if (reviewedReports && reviewedReports.length > 0) {
      const totalMinutes = reviewedReports.reduce((sum, report) => {
        const created = new Date(report.created_at).getTime();
        const reviewed = new Date(report.reviewed_at).getTime();
        return sum + (reviewed - created) / 60000;
      }, 0);
      avgReviewTimeMinutes = Math.round(totalMinutes / reviewedReports.length);
    }

    res.json({
      success: true,
      data: {
        moderation: {
          pendingQueueSize: pendingQueueSize || 0,
          pendingByPriority: {
            P0: pendingP0 || 0,
            P1: pendingP1 || 0,
            P2: pendingP2 || 0,
          },
          avgReviewTimeMinutes,
          thisWeek: {
            bans: bansThisWeek || 0,
            suspensions: suspensionsThisWeek || 0,
            warnings: warningsThisWeek || 0,
          },
        },
        users: {
          total: totalUsers || 0,
          activeUsers30d: activeUsers30d || 0,
          newSignupsToday: newSignupsToday || 0,
        },
        matches: {
          activeMatches: activeMatchCount || 0,
        },
      },
    });
  })
);

// ─── GET /v1/admin/user/search ───────────────────────────────────────────────
// Search users by phone (substring) or display name (case-insensitive substring).

router.get(
  '/user/search',
  asyncHandler(async (req: Request, res: Response) => {
    const q = String(req.query.q ?? '').trim();
    if (q.length < 2) {
      throw new AppError(400, 'Query must be at least 2 characters', 'QUERY_TOO_SHORT');
    }
    const limit = Math.min(parseInt(String(req.query.limit ?? '20'), 10) || 20, 100);

    const { data: usersByPhone } = await supabase
      .from('users')
      .select('id, phone, is_verified, is_banned, is_hidden, profile_completeness, created_at')
      .ilike('phone', `%${q}%`)
      .limit(limit);

    const { data: basicsByName } = await supabase
      .from('basic_profiles')
      .select('user_id, display_name, city, country')
      .ilike('display_name', `%${q}%`)
      .limit(limit);

    const userIds = new Set([
      ...(usersByPhone ?? []).map((u: any) => u.id),
      ...(basicsByName ?? []).map((b: any) => b.user_id),
    ]);

    const { data: merged } = await supabase
      .from('users')
      .select('id, phone, is_verified, is_banned, is_hidden, profile_completeness, created_at')
      .in('id', Array.from(userIds))
      .limit(limit);

    const basicsMap = new Map(
      (basicsByName ?? []).map((b: any) => [b.user_id, { displayName: b.display_name, city: b.city, country: b.country }])
    );

    const results = (merged ?? []).map((u: any) => ({
      id: u.id,
      phone: u.phone,
      isVerified: u.is_verified,
      isBanned: u.is_banned,
      isHidden: u.is_hidden,
      profileCompleteness: u.profile_completeness,
      createdAt: u.created_at,
      ...(basicsMap.get(u.id) || {}),
    }));

    res.json({ success: true, data: { users: results } });
  })
);

// ─── GET /v1/admin/appeals ───────────────────────────────────────────────────

router.get(
  '/appeals',
  asyncHandler(async (req: Request, res: Response) => {
    const status = req.query.status ? String(req.query.status) : undefined;
    const page = Math.max(parseInt(String(req.query.page ?? '1'), 10) || 1, 1);
    const limit = Math.min(parseInt(String(req.query.limit ?? '20'), 10) || 20, 100);
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    let query = supabase
      .from('appeals')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (status && ['pending', 'approved', 'denied'].includes(status)) {
      query = query.eq('status', status);
    }

    const { data: appeals, count, error } = await query;
    if (error) throw new AppError(500, 'Failed to fetch appeals', 'APPEALS_FETCH_FAILED');

    res.json({
      success: true,
      data: { appeals: appeals ?? [], page, limit, total: count ?? 0 },
    });
  })
);

// ─── POST /v1/admin/appeals/review ───────────────────────────────────────────

const reviewAppealSchema = z.object({
  appealId: z.string().uuid('Invalid appeal ID'),
  action: z.enum(['approve', 'deny']),
  reason: z.string().min(1).max(1000),
});

router.post(
  '/appeals/review',
  validate(reviewAppealSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const reviewer = (req as AuthenticatedRequest).user;
    const { appealId, action, reason } = req.body;

    const { data: appeal, error: fetchError } = await supabase
      .from('appeals')
      .select('*')
      .eq('id', appealId)
      .single();

    if (fetchError || !appeal) {
      throw new AppError(404, 'Appeal not found', 'APPEAL_NOT_FOUND');
    }

    if (appeal.status !== 'pending') {
      throw new AppError(400, 'Appeal already reviewed', 'APPEAL_ALREADY_REVIEWED');
    }

    const newStatus = action === 'approve' ? 'approved' : 'denied';

    const { error: updateError } = await supabase
      .from('appeals')
      .update({
        status: newStatus,
        reviewed_by: reviewer.id,
        reviewer_note: reason,
        reviewed_at: new Date().toISOString(),
      })
      .eq('id', appealId);

    if (updateError) {
      throw new AppError(500, 'Failed to update appeal', 'APPEAL_UPDATE_FAILED');
    }

    // Sync the strike's appeal_status
    await supabase
      .from('strikes')
      .update({ appeal_status: newStatus })
      .eq('id', appeal.strike_id);

    res.json({ success: true, data: { appealId, status: newStatus } });
  })
);

// ─── GET /v1/admin/daily-prompt ──────────────────────────────────────────────

router.get(
  '/daily-prompt',
  asyncHandler(async (req: Request, res: Response) => {
    const upcoming = req.query.upcoming === 'true';
    const page = Math.max(parseInt(String(req.query.page ?? '1'), 10) || 1, 1);
    const limit = Math.min(parseInt(String(req.query.limit ?? '20'), 10) || 20, 100);
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    let query = supabase
      .from('daily_prompts')
      .select('*', { count: 'exact' })
      .order('date', { ascending: upcoming })
      .range(from, to);

    if (upcoming) {
      const today = new Date().toISOString().split('T')[0];
      query = query.gte('date', today);
    }

    const { data, count, error } = await query;
    if (error) throw new AppError(500, 'Failed to fetch prompts', 'PROMPTS_FETCH_FAILED');

    res.json({
      success: true,
      data: { prompts: data ?? [], page, limit, total: count ?? 0 },
    });
  })
);

// ─── PATCH /v1/admin/daily-prompt/:id ────────────────────────────────────────

const updatePromptSchema = z.object({
  question: z.string().min(5).max(200).optional(),
  category: z.string().min(1).max(50).optional(),
  is_active: z.boolean().optional(),
});

router.patch(
  '/daily-prompt/:id',
  validate(updatePromptSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const { id } = req.params;
    const updates = req.body;

    if (Object.keys(updates).length === 0) {
      throw new AppError(400, 'No fields to update', 'NO_UPDATES');
    }

    const { data, error } = await supabase
      .from('daily_prompts')
      .update(updates)
      .eq('id', id)
      .select()
      .single();

    if (error || !data) {
      throw new AppError(404, 'Prompt not found or update failed', 'PROMPT_UPDATE_FAILED');
    }

    res.json({ success: true, data: { prompt: data } });
  })
);

// ─── DELETE /v1/admin/daily-prompt/:id ───────────────────────────────────────

router.delete(
  '/daily-prompt/:id',
  asyncHandler(async (req: Request, res: Response) => {
    const { id } = req.params;
    const { error } = await supabase
      .from('daily_prompts')
      .delete()
      .eq('id', id);

    if (error) {
      throw new AppError(500, 'Failed to delete prompt', 'PROMPT_DELETE_FAILED');
    }

    res.json({ success: true });
  })
);

export default router;
