import dotenv from 'dotenv';
dotenv.config();

// Initialise error tracking as early as possible (after env is loaded).
import './config/sentry';

import 'express-async-errors';

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import compression from 'compression';
import http from 'http';
import path from 'path';
import fs from 'fs';

import { globalErrorHandler } from './utils/errors';
import { rateLimit } from './middleware/rateLimit';
import { startCronJobs } from './cron';
import { createSocketServer } from './socket';

// Route imports — NO premium routes
import authRoutes from './routes/auth';
import profileRoutes from './routes/profile';
import discoveryRoutes from './routes/discovery';
import actionRoutes from './routes/actions';
import chatRoutes from './routes/chat';
import familyRoutes from './routes/family';
import safetyRoutes from './routes/safety';
import adminRoutes from './routes/admin';

const app = express();
const PORT = parseInt(process.env.PORT || '4000', 10);

// Security headers
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));

// CORS — supports web, Android, iOS, and Capacitor/Expo origins
app.use(
  cors({
    origin: (origin, callback) => {
      const allowedOrigins = process.env.CORS_ORIGINS?.split(',').map(o => o.trim()) || [];
      // Allow requests with no origin (mobile apps, curl, server-to-server)
      if (!origin) return callback(null, true);
      // Allow configured origins
      if (allowedOrigins.includes('*') || allowedOrigins.includes(origin)) return callback(null, true);
      // Allow mobile deep link schemes (capacitor, expo, ionic)
      if (/^(capacitor|ionic|exp|mitimaiti):\/\//.test(origin)) return callback(null, true);
      // Allow localhost variants (dev)
      if (/^https?:\/\/(localhost|127\.0\.0\.1|10\.0\.2\.2)(:\d+)?$/.test(origin)) return callback(null, true);
      callback(null, false);
    },
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Platform', 'X-App-Version'],
    credentials: true,
    maxAge: 86400,
  })
);

// Logging
app.use(
  morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev', {
    skip: (req) => req.url === '/health',
  })
);

// Body parsing + compression
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true, limit: '2mb' }));
app.use(compression());

// Global rate limiting: 60 req/min
app.use(rateLimit());

// Health check — used by all platforms (web, iOS, Android)
app.get('/health', async (_req, res) => {
  const { supabase } = await import('./config/supabase');
  const { redis } = await import('./config/redis');

  let dbOk = false;
  let redisOk = false;
  let dbLatency = -1;
  let redisLatency = -1;

  try {
    const start = Date.now();
    const { error } = await supabase.from('users').select('id').limit(1);
    dbLatency = Date.now() - start;
    dbOk = !error;
  } catch {}

  try {
    const start = Date.now();
    await redis.ping();
    redisLatency = Date.now() - start;
    redisOk = true;
  } catch {}

  const status = dbOk && redisOk ? 'ok' : dbOk ? 'degraded' : 'error';

  res.json({
    status,
    version: '1.0.0',
    commit: process.env.RENDER_GIT_COMMIT?.slice(0, 7) || 'dev',
    platforms: ['web', 'android', 'ios'],
    db: { status: dbOk ? 'ok' : 'error', latencyMs: dbLatency },
    redis: { status: redisOk ? 'ok' : 'error', latencyMs: redisLatency },
    uptime: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

// API Routes — NO /v1/premium
app.use('/v1/auth', authRoutes);
app.use('/v1/me', profileRoutes);
app.use('/v1/feed', discoveryRoutes);
app.use('/v1/action', actionRoutes);
app.use('/v1/chat', chatRoutes);
app.use('/v1/family', familyRoutes);
app.use('/v1/safety', safetyRoutes);
app.use('/v1/admin', adminRoutes);
app.use('/v1/inbox', actionRoutes);

// OpenAPI spec — served as raw YAML for tooling (swagger-ui, postman, etc.)
const openapiPath = path.join(__dirname, '..', 'openapi.yaml');
app.get('/v1/openapi.yaml', (_req, res) => {
  res.type('application/yaml').send(fs.readFileSync(openapiPath, 'utf8'));
});

// 404
app.use((_req, res) => {
  res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Endpoint not found' } });
});

// Error handler
app.use(globalErrorHandler);

// Start server
const server = http.createServer(app);
createSocketServer(server);
startCronJobs();

server.listen(PORT, () => {
  console.log(`[MitiMaiti] Server running on port ${PORT} (${process.env.NODE_ENV || 'development'})`);
});

// Graceful shutdown
function gracefulShutdown(signal: string) {
  console.log(`[Server] ${signal} — shutting down...`);
  const { stopCronJobs } = require('./cron');
  stopCronJobs();

  server.close(() => {
    const { redis } = require('./config/redis');
    redis.quit().then(() => process.exit(0));
  });

  setTimeout(() => process.exit(1), 30000);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('unhandledRejection', (reason: any) => console.error('[Unhandled]', reason));
process.on('uncaughtException', (error: Error) => {
  console.error('[Uncaught]', error);
  gracefulShutdown('uncaughtException');
});

export default app;
