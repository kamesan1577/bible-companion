import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser } from './helpers/db';
import { reserveBudget, settleBudget } from '../src/budget';
const passage = { book: 'ACT', start: { chapter: 18, verse: 18 }, end: { chapter: 18, verse: 18 } };
describe('private reading API', () => {
  it('requires authentication', async () => {
    expect((await app.request('/v1/imports', {}, testEnv())).status).toBe(401);
  });
  it('idempotent import and ownership protect read, chat, export and delete', async () => {
    const env = testEnv();
    const a = await seedUser(env);
    const b = await seedUser(env);
    const input = { idempotencyKey: crypto.randomUUID(), sharedText: '使徒18:18 JCB' };
    const post = () =>
      app.request(
        '/v1/imports',
        { method: 'POST', headers: a.headers, body: JSON.stringify(input) },
        env,
      );
    const first = await post();
    expect(first.status).toBe(201);
    const imported = (await first.json()) as { id: string };
    const retry = await post();
    expect(retry.status).toBe(200);
    expect(((await retry.json()) as { id: string }).id).toBe(imported.id);
    expect(
      (await app.request('/v1/imports/' + imported.id, { headers: b.headers }, env)).status,
    ).toBe(404);
    expect(
      (
        await app.request(
          '/v1/imports/' + imported.id,
          { method: 'DELETE', headers: b.headers },
          env,
        )
      ).status,
    ).toBe(404);
    expect(
      (
        await app.request(
          '/v1/conversations',
          { method: 'POST', headers: b.headers, body: JSON.stringify({ importId: imported.id }) },
          env,
        )
      ).status,
    ).toBe(404);
    const chat = await app.request(
      '/v1/conversations',
      { method: 'POST', headers: a.headers, body: JSON.stringify({ importId: imported.id }) },
      env,
    );
    expect(chat.status).toBe(201);
    const chatId = ((await chat.json()) as { id: string }).id;
    expect(
      (await app.request('/v1/conversations/' + chatId, { headers: b.headers }, env)).status,
    ).toBe(404);
    const exported = (await (
      await app.request('/v1/me/export', { headers: b.headers }, env)
    ).json()) as { imports: unknown[] };
    expect(exported.imports).toEqual([]);
    const conflict = await app.request(
      '/v1/imports',
      { method: 'POST', headers: a.headers, body: JSON.stringify({ ...input, ranges: [passage] }) },
      env,
    );
    expect(conflict.status).toBe(409);
  });
  it('does not persist raw copyright text', async () => {
    const env = testEnv();
    const user = await seedUser(env);
    const secret = 'Private quoted text';
    await app.request(
      '/v1/imports',
      {
        method: 'POST',
        headers: user.headers,
        body: JSON.stringify({
          idempotencyKey: crypto.randomUUID(),
          sharedText: '使徒18:18\n' + secret,
        }),
      },
      env,
    );
    const rows = await env.DB.prepare('SELECT * FROM imports').all();
    expect(JSON.stringify(rows)).not.toContain(secret);
  });
});
describe('atomic budgets', () => {
  it('enforces user and global limit and settles once', async () => {
    const env = testEnv();
    const user = await seedUser(env);
    env.DAILY_USER_BUDGET = '1000';
    env.DAILY_APP_BUDGET = '1000';
    await reserveBudget(env, user.id, 'a');
    await reserveBudget(env, user.id, 'b');
    await expect(reserveBudget(env, user.id, 'c')).rejects.toThrow();
    await settleBudget(env, 'a', 200);
    await settleBudget(env, 'a', 0);
    const row = await env.DB.prepare('SELECT * FROM budget_days').first<{
      reserved: number;
      consumed: number;
    }>();
    expect(row).toMatchObject({ reserved: 500, consumed: 200 });
    await reserveBudget(env, user.id, 'd', 300);
    await expect(reserveBudget(env, user.id, 'e', 1)).rejects.toThrow();
  });
  it('charges unknown failed usage conservatively', async () => {
    const env = testEnv();
    const user = await seedUser(env);
    await reserveBudget(env, user.id, 'a');
    await settleBudget(env, 'a');
    expect(await env.DB.prepare('SELECT consumed FROM budget_days').first()).toEqual({
      consumed: 500,
    });
  });
});
