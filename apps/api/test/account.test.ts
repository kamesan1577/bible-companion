import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser } from './helpers/db';
import { reserveBudget } from '../src/budget';
const passage = { book: 'ACT', start: { chapter: 18, verse: 18 }, end: { chapter: 18, verse: 18 } };
async function reading(
  env: ReturnType<typeof testEnv>,
  user: Awaited<ReturnType<typeof seedUser>>,
) {
  const imported = (await (
    await app.request(
      '/v1/imports',
      {
        method: 'POST',
        headers: user.headers,
        body: JSON.stringify({ idempotencyKey: crypto.randomUUID(), ranges: [passage] }),
      },
      env,
    )
  ).json()) as { id: string };
  const conversation = (await (
    await app.request(
      '/v1/conversations',
      { method: 'POST', headers: user.headers, body: JSON.stringify({ importId: imported.id }) },
      env,
    )
  ).json()) as { id: string };
  await app.request(
    `/v1/conversations/${conversation.id}/questions`,
    {
      method: 'POST',
      headers: user.headers,
      body: JSON.stringify({
        requestId: crypto.randomUUID(),
        question: '私的な読書の疑問',
        sourceOnly: true,
      }),
    },
    env,
  );
  return { imported, conversation };
}
describe('private deletion and export lifecycle', () => {
  it('exports normalized private DTOs and never authentication material', async () => {
    const env = testEnv(),
      user = await seedUser(env);
    await reading(env, user);
    const exported = (await (
      await app.request('/v1/me/export', { headers: user.headers }, env)
    ).json()) as {
      messages: { content: unknown }[];
      conversations: { passage: unknown; readingBoundary: unknown }[];
    };
    expect(typeof exported.messages[0].content).toBe('object');
    expect(exported.conversations[0].passage).toEqual(passage);
    expect(exported.conversations[0].readingBoundary).toEqual(passage);
    expect(JSON.stringify(exported)).not.toContain(user.token);
    expect(JSON.stringify(exported)).not.toContain('token_hash');
    expect(JSON.stringify(exported)).not.toContain('public_key');
  });
  it('requires exact confirmation and a recently authenticated session', async () => {
    const env = testEnv(),
      user = await seedUser(env);
    expect(
      (await app.request('/v1/me', { method: 'DELETE', headers: user.headers, body: '{}' }, env))
        .status,
    ).toBe(400);
    await env.DB.prepare('UPDATE sessions SET created_at=? WHERE user_id=?')
      .bind(Math.floor(Date.now() / 1000) - 301, user.id)
      .run();
    expect(
      (
        await app.request(
          '/v1/me',
          { method: 'DELETE', headers: user.headers, body: '{"confirmation":"DELETE_MY_ACCOUNT"}' },
          env,
        )
      ).status,
    ).toBe(403);
    expect(
      (
        await app.request(
          '/v1/me/reading-data',
          {
            method: 'DELETE',
            headers: user.headers,
            body: '{"confirmation":"DELETE_MY_READING_DATA"}',
          },
          env,
        )
      ).status,
    ).toBe(403);
    expect((await app.request('/v1/me', { headers: user.headers }, env)).status).toBe(200);
  });
  it('deletes own reading data and generation payloads while retaining both accounts', async () => {
    const env = testEnv(),
      a = await seedUser(env),
      b = await seedUser(env);
    await reading(env, a);
    const other = await reading(env, b);
    const deleted = await app.request(
      '/v1/me/reading-data',
      { method: 'DELETE', headers: a.headers, body: '{"confirmation":"DELETE_MY_READING_DATA"}' },
      env,
    );
    expect(deleted.status).toBe(200);
    for (const table of ['imports', 'conversations', 'messages', 'generation_requests'])
      expect(
        await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE user_id=?`)
          .bind(a.id)
          .first(),
      ).toEqual({ n: 0 });
    expect(
      (await app.request(`/v1/conversations/${other.conversation.id}`, { headers: b.headers }, env))
        .status,
    ).toBe(200);
    expect((await app.request('/v1/me', { headers: a.headers }, env)).status).toBe(200);
  });
  it('account deletion revokes sessions and reconciles unknown held allowance without affecting another account', async () => {
    const env = testEnv(),
      a = await seedUser(env),
      b = await seedUser(env);
    await reading(env, a);
    await reading(env, b);
    await reserveBudget(env, a.id, 'held-at-delete', 500);
    const response = await app.request(
      '/v1/me',
      { method: 'DELETE', headers: a.headers, body: '{"confirmation":"DELETE_MY_ACCOUNT"}' },
      env,
    );
    expect(response.status).toBe(200);
    expect((await app.request('/v1/me', { headers: a.headers }, env)).status).toBe(401);
    expect((await app.request('/v1/me', { headers: b.headers }, env)).status).toBe(200);
    expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({
      reserved: 0,
      consumed: 500,
    });
    for (const table of [
      'imports',
      'conversations',
      'messages',
      'generation_requests',
      'sessions',
      'budget_reservations',
    ])
      expect(
        await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE user_id=?`)
          .bind(a.id)
          .first(),
      ).toEqual({ n: 0 });
  });
  it('private message pagination returns latest page then earlier same-second messages', async () => {
    const env = testEnv(),
      user = await seedUser(env);
    const { conversation } = await reading(env, user);
    const t = Math.floor(Date.now() / 1000);
    for (let i = 0; i < 205; i++)
      await env.DB.prepare(
        'INSERT INTO messages(id,conversation_id,user_id,role,content_json,created_at) VALUES(?,?,?,?,?,?)',
      )
        .bind(
          crypto.randomUUID(),
          conversation.id,
          user.id,
          'user',
          JSON.stringify({ text: 'message ' + i }),
          t,
        )
        .run();
    const page = (await (
      await app.request(`/v1/conversations/${conversation.id}`, { headers: user.headers }, env)
    ).json()) as { messages: { content: { text: string } }[]; nextMessageCursor: string };
    expect(page.messages).toHaveLength(50);
    expect(page.messages.at(-1)?.content.text).toBe('message 204');
    const earlier = (await (
      await app.request(
        `/v1/conversations/${conversation.id}?beforeMessageId=${page.nextMessageCursor}`,
        { headers: user.headers },
        env,
      )
    ).json()) as { messages: unknown[]; nextMessageCursor: null };
    expect(earlier.messages).toHaveLength(50);
    expect(earlier.nextMessageCursor).not.toBeNull();
  });
});
