import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    // Modules under test transitively import config/supabase and config/redis,
    // which need env vars at import time. Stub them — no test talks to a real
    // service (the redis URL points at an unroutable port so it fails fast
    // and the client's error handler swallows it).
    env: {
      SUPABASE_URL: 'https://stub.supabase.co',
      SUPABASE_SERVICE_ROLE_KEY: 'stub-service-key',
      REDIS_URL: 'redis://127.0.0.1:1',
      JWT_SECRET: 'test-secret',
      NODE_ENV: 'test',
    },
  },
});
