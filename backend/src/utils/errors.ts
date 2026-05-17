import { Request, Response, NextFunction, RequestHandler } from 'express';

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
export function globalErrorHandler(
  err: Error | AppError,
  _req: Request,
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

  // Log unexpected errors
  console.error('[Unhandled Error]', err);

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
