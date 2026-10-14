import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser } from './helpers/db';
async function fixture(count = 55) {
  const env = testEnv(),
    user = await seedUser(env);
  for (let i = 0; i < count; i++)
    await env.DB.prepare(
      'INSERT INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,created_at) VALUES(?,?,?,?,?,?)',
    )
      .bind(crypto.randomUUID(), user.id, crypto.randomUUID(), 'hash', '[]', 1)
      .run();
  return { env, user };
}
async function snapshot(
  env: ReturnType<typeof testEnv>,
  user: Awaited<ReturnType<typeof seedUser>>,
) {
  const response = await app.request(
    '/v1/me/export/snapshots',
    { method: 'POST', headers: user.headers, body: '{}' },
    env,
  );
  expect(response.status).toBe(201);
  return (await response.json()) as { snapshotId: string; maxPageBytes: number };
}
describe('bounded private export snapshots', () => {
  it('exports every same-second row once across bounded pages with no credentials', async () => {
    const { env, user } = await fixture();
    const snap = await snapshot(env, user);
    const ids: string[] = [];
    let cursor: string | null = null;
    do {
      const res = await app.request(
        `/v1/me/export/pages?snapshotId=${snap.snapshotId}&section=imports${cursor ? '&cursor=' + encodeURIComponent(cursor) : ''}`,
        { headers: user.headers },
        env,
      );
      expect(res.status).toBe(200);
      const bytes = await res.text();
      expect(new TextEncoder().encode(bytes).length).toBeLessThanOrEqual(1048576);
      expect(bytes).not.toContain(user.token);
      const page = JSON.parse(bytes);
      expect(page.items.length).toBeLessThanOrEqual(25);
      ids.push(...page.items.map((x: { id: string }) => x.id));
      cursor = page.nextCursor;
    } while (cursor);
    expect(ids).toHaveLength(55);
    expect(new Set(ids).size).toBe(55);
  });
  it('rejects cross-owner access, cross-section cursors and expired snapshots', async () => {
    const { env, user } = await fixture();
    const other = await seedUser(env);
    const snap = await snapshot(env, user);
    const url = `/v1/me/export/pages?snapshotId=${snap.snapshotId}&section=imports`;
    expect((await app.request(url, { headers: other.headers }, env)).status).toBe(404);
    const page = (await (await app.request(url, { headers: user.headers }, env)).json()) as {
      nextCursor: string;
    };
    expect(
      (
        await app.request(
          `/v1/me/export/pages?snapshotId=${snap.snapshotId}&section=messages&cursor=${encodeURIComponent(page.nextCursor)}`,
          { headers: user.headers },
          env,
        )
      ).status,
    ).toBe(400);
    await env.DB.prepare('UPDATE export_snapshots SET expires_at=0 WHERE id=?')
      .bind(snap.snapshotId)
      .run();
    expect((await app.request(url, { headers: user.headers }, env)).status).toBe(409);
  });
  it('requires restart after any concurrent private write or source policy change', async () => {
    const { env, user } = await fixture();
    for (const mutation of [
      async () => {
        await env.DB.prepare(
          'DELETE FROM imports WHERE id=(SELECT id FROM imports WHERE user_id=? LIMIT 1)',
        )
          .bind(user.id)
          .run();
      },
      async () => {
        await env.DB.prepare(
          "UPDATE public_sources SET rights_status='revoked' WHERE id='act-18-18'",
        ).run();
      },
    ]) {
      const snap = await snapshot(env, user);
      await mutation();
      const result = await app.request(
        `/v1/me/export/pages?snapshotId=${snap.snapshotId}&section=imports`,
        { headers: user.headers },
        env,
      );
      expect(result.status).toBe(409);
      expect(await result.text()).toContain('export_changed');
    }
  });
  it('large whole-account exports fail explicitly instead of loading or truncating all rows', async () => {
    const { env, user } = await fixture(1001);
    const result = await app.request('/v1/me/export', { headers: user.headers }, env);
    expect(result.status).toBe(413);
    expect(await result.text()).toContain('export_requires_pagination');
    expect((await snapshot(env, user)).maxPageBytes).toBe(1048576);
  });
  it('replaces a previous snapshot without retaining private content in snapshot records', async () => {
    const { env, user } = await fixture();
    const first = await snapshot(env, user),
      second = await snapshot(env, user);
    expect(first.snapshotId).not.toBe(second.snapshotId);
    expect(
      (
        await app.request(
          `/v1/me/export/pages?snapshotId=${first.snapshotId}&section=imports`,
          { headers: user.headers },
          env,
        )
      ).status,
    ).toBe(404);
    const row = await env.DB.prepare('SELECT * FROM export_snapshots WHERE id=?')
      .bind(second.snapshotId)
      .first();
    expect(JSON.stringify(row)).not.toContain(user.token);
    expect(
      await env.DB.prepare('SELECT COUNT(*) AS n FROM export_snapshots WHERE user_id=?')
        .bind(user.id)
        .first(),
    ).toEqual({ n: 1 });
  });
});
