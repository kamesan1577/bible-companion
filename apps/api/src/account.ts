import { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv } from './types';
import { body, fail, now, requireDebugger } from './http';
export const account = new Hono<AppEnv>();
async function requireFreshAuthentication(c: Parameters<typeof body>[0]) {
  const session = await c.env.DB.prepare(
    'SELECT created_at FROM sessions WHERE token_hash=? AND user_id=?',
  )
    .bind(c.get('tokenHash'), c.get('user').id)
    .first<{ created_at: number }>();
  if (!session || session.created_at < now() - 300)
    fail(403, 'reauthentication_required', 'Log in again before deleting private data.');
}
account.delete('/me/reading-data', async (c) => {
  await body(c, z.object({ confirmation: z.literal('DELETE_MY_READING_DATA') }).strict());
  await requireFreshAuthentication(c);
  const userId = c.get('user').id;
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE users SET data_epoch=data_epoch+1 WHERE id=?').bind(userId),
    c.env.DB.prepare(
      "INSERT OR IGNORE INTO request_cancellations(user_id,id,kind,created_at) SELECT user_id,id,'comparison',? FROM comparison_jobs WHERE user_id=?",
    ).bind(now(), userId),
    c.env.DB.prepare('DELETE FROM imports WHERE user_id=?').bind(userId),
    c.env.DB.prepare('DELETE FROM comparison_jobs WHERE user_id=?').bind(userId),
    c.env.DB.prepare('DELETE FROM export_snapshots WHERE user_id=?').bind(userId),
  ]);
  return c.json({
    deleted: true,
    accountRetained: true,
    backupErasurePolicy: 'pending-deployment-decision',
  });
});
account.delete('/me', async (c) => {
  await body(c, z.object({ confirmation: z.literal('DELETE_MY_ACCOUNT') }).strict());
  await requireFreshAuthentication(c);
  const userId = c.get('user').id;
  // Trial ledger releases proven undispatched comparison allowance before general unknown usage.
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM comparison_jobs WHERE user_id=?').bind(userId),
    c.env.DB.prepare(
      "UPDATE budget_reservations SET state='settled' WHERE user_id=? AND state='reserved'",
    ).bind(userId),
    c.env.DB.prepare('DELETE FROM users WHERE id=?').bind(userId),
  ]);
  return c.json({
    deleted: true,
    sessionRevoked: true,
    backupErasurePolicy: 'pending-deployment-decision',
  });
});
account.delete('/developer/comparisons/:id/history', async (c) => {
  requireDebugger(c);
  const exists = await c.env.DB.prepare('SELECT id FROM comparison_jobs WHERE id=? AND user_id=?')
    .bind(c.req.param('id'), c.get('user').id)
    .first();
  if (!exists) fail(404, 'not_found', 'Comparison not found');
  await c.env.DB.batch([
    c.env.DB.prepare(
      "INSERT OR IGNORE INTO request_cancellations(user_id,id,kind,created_at) VALUES(?,?,'comparison',?)",
    ).bind(c.get('user').id, c.req.param('id'), now()),
    c.env.DB.prepare('DELETE FROM comparison_jobs WHERE id=? AND user_id=?').bind(
      c.req.param('id'),
      c.get('user').id,
    ),
  ]);
  const row = exists;
  if (!row) fail(404, 'not_found', 'Comparison not found');
  return c.body(null, 204);
});
