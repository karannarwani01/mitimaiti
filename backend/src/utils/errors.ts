import { Request, Response, NextFunction, RequestHandler } from 'express';
import { captureError } from '../config/sentry';

/**
 * Custom application error with HTTP status code and machine-readable error code.
 */
export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: string;
  public readonly isOperational: boolean;

  constructor(statusCode: number, message: string, code: string = 'INTERNAL_ERROR') {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.isOperational = true;
    Object.setPrototypeOf(this, AppError.prototype);
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * Wraps an async route handler so thrown errors are forwarded to Express error middleware.
 */
export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<any>
): RequestHandler {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

/**
 * Global Express error handler. Must be registered after all routes.
 */
/** Best-effort: persist an error to the error_log table (viewable in the
 *  Supabase dashboard). Fire-and-forget — never blocks or throws. */
function logErrorToDb(req: Request, err: any, code: string, statusCode: number): void {
  import('../config/supabase')
    .then(({ supabase }) =>
      supabase.from('error_log').insert({
        code,
        status_code: statusCode,
        method: req.method,
        path: (req.originalUrl || req.url || '').slice(0, 500),
        message: (err?.message || String(err)).slice(0, 1000),
        stack: (err?.stack || '').slice(0, 4000),
      })
    )
    .then(() => {})
    .catch(() => {});
}

export function globalErrorHandler(
  err: Error | AppError,
  req: Request,
  res: Response,
  _next: NextFunction
): void {
  if (err instanceof AppError) {
    // Operational, but 5xx still means something broke server-side — log it
    // so failures aren't invisible (previously these never hit the logs).
    if (err.statusCode >= 500) {
      console.error(
        `[AppError ${err.statusCode}] ${err.code}: ${err.message}`,
        err.stack
      );
      captureError(err, { code: err.code, statusCode: err.statusCode });
      logErrorToDb(req, err, err.code, err.statusCode);
    }
    res.status(err.statusCode).json({
      success: false,
      error: {
        code: err.code,
        message: err.message,
      },
    });
    return;
  }

  // Log + report unexpected errors (the ones you most need to see in prod)
  console.error('[Unhandled Error]', err);
  captureError(err);
  logErrorToDb(req, err, 'UNHANDLED', 500);

  // Supabase errors often have a status property
  const supaErr = err as any;
  if (supaErr.status && typeof supaErr.status === 'number') {
    res.status(supaErr.status).json({
      success: false,
      error: {
        code: 'SUPABASE_ERROR',
        message: supaErr.message || 'Database error',
      },
    });
    return;
  }

  // Multer file size errors
  if (err.message && err.message.includes('File too large')) {
    res.status(413).json({
      success: false,
      error: {
        code: 'FILE_TOO_LARGE',
        message: 'Uploaded file exceeds the maximum allowed size',
      },
    });
    return;
  }

  // Zod validation errors
  if (err.name === 'ZodError') {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Request validation failed',
        details: (err as any).errors,
      },
    });
    return;
  }

  res.status(500).json({
    success: false,
    error: {
      code: 'INTERNAL_ERROR',
      message:
        process.env.NODE_ENV === 'production'
          ? 'An unexpected error occurred'
          : err.message,
    },
  });
}
