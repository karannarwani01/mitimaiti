import * as Sentry from '@sentry/node';

// Error tracking. Entirely opt-in: does NOTHING unless SENTRY_DSN is set in the
// environment (Render env var), so local dev and CI are unaffected. Errors
// only — no performance tracing overhead, and no user PII shipped off-box
// (this is a dating app; the point is to see stack traces, not personal data).
const dsn = process.env.SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV || 'production',
    release: process.env.RENDER_GIT_COMMIT,
    tracesSampleRate: 0,
    sendDefaultPii: false,
  });
  // eslint-disable-next-line no-console
  console.log('[Sentry] error tracking enabled');
}

export const sentryEnabled = !!dsn;

/** Report an unexpected server error to Sentry. No-op unless SENTRY_DSN is set. */
export function captureError(err: unknown, context?: Record<string, unknown>): void {
  if (!dsn) return;
  try {
    Sentry.captureException(err, context ? { extra: context } : undefined);
  } catch {
    // never let telemetry break the request path
  }
}
