import { it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser, TestDatabase } from './helpers/db';
it('lists same-second private conversations exactly once and binds import-filter cursors', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    alice = await seedUser(env),
    bob = await seedUser(env);
  const passage = {
    book: 'ACT',
    start: { chapter: 18, verse: 18 },
    end: { chapter: 18, verse: 18 },
  };
  const imported = async (user: typeof alice) =>
    (
      (await (
        await app.request(
          '/v1/imports',
          {
            method: 'POST',
            headers: user.headers,
            body: JSON.stringify({ idempotencyKey: crypto.randomUUID(), ranges: [passage] }),
          },
          env,
        )
      ).json()) as { id: string }
    ).id;
  const aid = await imported(alice),
    bid = await imported(bob);
  for (let i = 0; i < 52; i++)
    db.sqlite
      .prepare(
        'INSERT INTO conversations(id,user_id,import_id,passage_json,reading_boundary_json,created_at) VALUES(?,?,?,?,?,1)',
      )
      .run(crypto.randomUUID(), alice.id, aid, JSON.stringify(passage), JSON.stringify(passage));
  db.sqlite
    .prepare(
      'INSERT INTO conversations(id,user_id,import_id,passage_json,created_at) VALUES(?,?,?,?,1)',
    )
    .run(crypto.randomUUID(), bob.id, bid, JSON.stringify(passage));
  const get = (path: string) => app.request(path, { headers: alice.headers }, env);
  const first = (await (await get('/v1/conversations?importId=' + aid)).json()) as {
    items: { id: string; importId: string }[];
    nextCursor: string;
  };
  expect(first.items).toHaveLength(50);
  expect(first.items.every((x) => x.importId === aid)).toBe(true);
  const second = (await (
    await get(
      '/v1/conversations?importId=' + aid + '&before=' + encodeURIComponent(first.nextCursor),
    )
  ).json()) as { items: { id: string }[]; nextCursor: null };
  expect(second.items).toHaveLength(2);
  expect(second.nextCursor).toBeNull();
  expect(new Set([...first.items, ...second.items].map((x) => x.id)).size).toBe(52);
  expect(
    (await get('/v1/conversations?before=' + encodeURIComponent(first.nextCursor))).status,
  ).toBe(400);
  expect((await get('/v1/conversations?importId=' + bid)).status).toBe(404);
});
it('lists only own selected comparison metadata and enforces owner access', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    owner = await seedUser(env, crypto.randomUUID(), 'owner'),
    other = await seedUser(env, crypto.randomUUID(), 'owner'),
    member = await seedUser(env);
  for (const user of [owner, other])
    for (let i = 0; i < 52; i++)
      db.sqlite
        .prepare(
          "INSERT INTO comparison_jobs(id,user_id,request_hash,status,saved,metrics_json,created_at,updated_at) VALUES(?,?,?,'complete',1,?,1,1)",
        )
        .run(crypto.randomUUID(), user.id, 'private-hash', '{"private":"must not appear"}');
  const first = (await (
    await app.request('/v1/developer/comparisons', { headers: owner.headers }, env)
  ).json()) as { items: { requestId: string }[]; nextCursor: string };
  expect(first.items).toHaveLength(50);
  expect(JSON.stringify(first)).not.toContain('private');
  const second = (await (
    await app.request(
      '/v1/developer/comparisons?before=' + encodeURIComponent(first.nextCursor),
      { headers: owner.headers },
      env,
    )
  ).json()) as { items: { requestId: string }[]; nextCursor: null };
  expect(second.items).toHaveLength(2);
  expect(new Set([...first.items, ...second.items].map((x) => x.requestId)).size).toBe(52);
  expect(
    (
      await app.request(
        '/v1/developer/comparisons?saved=false&before=' + encodeURIComponent(first.nextCursor),
        { headers: owner.headers },
        env,
      )
    ).status,
  ).toBe(400);
  expect(
    (await app.request('/v1/developer/comparisons', { headers: member.headers }, env)).status,
  ).toBe(403);
});
it('preflights message body bytes and paginates without truncation or mixed-policy ambiguity', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    user = await seedUser(env),
    passage = JSON.stringify({
      book: 'ACT',
      start: { chapter: 18, verse: 18 },
      end: { chapter: 18, verse: 18 },
    }),
    importId = crypto.randomUUID(),
    conversationId = crypto.randomUUID();
  db.sqlite
    .prepare(
      'INSERT INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,created_at) VALUES(?,?,?,?,?,1)',
    )
    .run(importId, user.id, crypto.randomUUID(), 'fixture', '[' + passage + ']');
  db.sqlite
    .prepare(
      'INSERT INTO conversations(id,user_id,import_id,passage_json,created_at) VALUES(?,?,?,?,1)',
    )
    .run(conversationId, user.id, importId, passage);
  const content = { text: 'あ'.repeat(20000) };
  for (let i = 0; i < 35; i++)
    db.sqlite
      .prepare(
        "INSERT INTO messages(id,conversation_id,user_id,role,content_json,created_at) VALUES(?,?,?,'user',?,1)",
      )
      .run(crypto.randomUUID(), conversationId, user.id, JSON.stringify(content));
  let cursor: string | null = null;
  const ids = new Set<string>();
  let pages = 0;
  do {
    const response = await app.request(
      '/v1/conversations/' + conversationId + (cursor ? '?beforeMessageId=' + cursor : ''),
      { headers: user.headers },
      env,
    );
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(new TextEncoder().encode(text).length).toBeLessThan(1048576);
    const page = JSON.parse(text) as {
      sourcePolicyVersion: number;
      messages: { id: string; content: { text: string } }[];
      nextMessageCursor: string | null;
    };
    expect(page.sourcePolicyVersion).toBeTypeOf('number');
    for (const message of page.messages) {
      expect(ids.has(message.id)).toBe(false);
      expect(message.content.text).toBe(content.text);
      ids.add(message.id);
    }
    cursor = page.nextMessageCursor;
    pages++;
  } while (cursor && pages < 10);
  expect(ids.size).toBe(35);
  expect(pages).toBeGreaterThan(1);
  db.sqlite
    .prepare(
      "INSERT INTO messages(id,conversation_id,user_id,role,content_json,created_at) VALUES(?,?,?,'user',?,2)",
    )
    .run(
      crypto.randomUUID(),
      conversationId,
      user.id,
      JSON.stringify({ text: 'x'.repeat(1000000) }),
    );
  expect(
    (await app.request('/v1/conversations/' + conversationId, { headers: user.headers }, env))
      .status,
  ).toBe(413);
});
