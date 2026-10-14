import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { sha256 } from '@bible/core';
import type { AppEnv, User } from './types';
import { auth } from './auth';
import { data } from './data';
import { aiRoutes } from './ai';
import { comparisons, expireComparisons } from './comparisons';
import { reading } from './reading';
import { scripture } from './scripture';
import { account } from './account';
import { exportsApi } from './export';
import { fail, now, canDebug } from './http';
import { rateLimit } from './budget';
import { sharedPreview } from './shared-preview';
import {shareAccess,shareAi} from './share-ai';
const app = new Hono<AppEnv>();
app.use('*', async (c, next) => {
  c.set('requestId', crypto.randomUUID());
  c.header('X-Request-Id', c.get('requestId'));
  c.header('X-Content-Type-Options', 'nosniff');
  c.header('Cache-Control', 'no-store');
  if (c.env.ENVIRONMENT === 'production')
    c.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  // No request bodies, bearer values, or religious/private content are logged.
  await next();
});
app.onError((e, c) => {
  if (e instanceof HTTPException) return e.getResponse();
  return c.json(
    {
      error: {
        code: 'internal_error',
        message: 'The request could not be completed',
        requestId: c.get('requestId'),
      },
    },
    500,
  );
});
app.notFound((c) =>
  c.json(
    { error: { code: 'not_found', message: 'Endpoint not found', requestId: c.get('requestId') } },
    404,
  ),
);
app.get('/health', (c) =>
  c.json({ ok: true, version: '0.1.0', aiEnabled: c.env.AI_ENABLED === 'true' }),
);
app.use('/auth/*', async (c, next) => {
  await rateLimit(c.env, 'auth:' + (c.req.header('CF-Connecting-IP') ?? 'local'), 30);
  await next();
});
app.route('/auth', auth);
app.route('/public', sharedPreview);
app.route('/share', shareAi);
app.use('/v1/*', async (c, next) => {
  const header = c.req.header('Authorization');
  if (!header?.startsWith('Bearer ') || header.length > 200)
    fail(401, 'authentication_required', 'Please log in');
  const tokenHash = await sha256(header.slice(7));
  const user = await c.env.DB.prepare(
    'SELECT u.id,u.display_name,u.role,u.data_epoch FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>?',
  )
    .bind(tokenHash, now())
    .first<User & { data_epoch: number }>();
  if (!user) fail(401, 'session_expired', 'Please log in again');
  const { data_epoch, ...publicUser } = user;
  c.set('user', publicUser);
  c.set('dataEpoch', data_epoch);
  c.set('tokenHash', tokenHash);
  await rateLimit(c.env, 'user:' + user.id, 120);
  await next();
});
app.get('/v1/me', (c) => c.json({ user: { ...c.get('user'), canDebug: canDebug(c.env, c.get('user')) } }));
app.post('/v1/logout', async (c) => {
  await c.env.DB.prepare('DELETE FROM sessions WHERE token_hash=?').bind(c.get('tokenHash')).run();
  return c.body(null, 204);
});
app.route('/v1', shareAccess);
app.route('/v1', data);
app.route('/v1', reading);
app.route('/v1', scripture);
app.route('/v1', aiRoutes);
app.route('/v1', comparisons);
app.route('/v1', account);
app.route('/v1', exportsApi);

export { app };
export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledEvent, env: AppEnv['Bindings']) {
    const t = now();
    await expireComparisons(env);
    await env.DB.batch([
      env.DB.prepare('DELETE FROM auth_flows WHERE expires_at<?').bind(t),
      env.DB.prepare('DELETE FROM auth_codes WHERE expires_at<?').bind(t),
      env.DB.prepare('DELETE FROM sessions WHERE expires_at<?').bind(t),
      env.DB.prepare('DELETE FROM invitations WHERE expires_at<?').bind(t),
      env.DB.prepare('DELETE FROM rate_windows WHERE window<?').bind(Math.floor(t / 60) - 1440),
      env.DB.prepare('DELETE FROM public_cache WHERE expires_at<?').bind(t),
      env.DB.prepare('DELETE FROM export_snapshots WHERE expires_at<?').bind(t),
      env.DB.prepare(
        "UPDATE generation_requests SET status='failed',updated_at=? WHERE status IN ('running','reserved') AND updated_at<?",
      ).bind(t, t - 600),
      env.DB.prepare(
        "UPDATE comparison_jobs SET status='failed',updated_at=? WHERE status IN ('running','reserved') AND updated_at<?",
      ).bind(t, t - 900),
      env.DB.prepare(
        "UPDATE budget_reservations SET state='settled' WHERE state='reserved' AND created_at<?",
      ).bind(t - 900),
    ]);
  },
};
