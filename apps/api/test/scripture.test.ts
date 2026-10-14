import { it, expect } from 'vitest';
import { app } from '../src/index';
import { getSources } from '../src/data';
import { historicalSources } from '../src/history';
import { seedScripture } from './helpers/scripture';
import { TestDatabase, testEnv, seedUser } from './helpers/db';
const genesis = { book: 'GEN', start: { chapter: 1, verse: 1 }, end: { chapter: 1, verse: 3 } };
async function imported(
  env: ReturnType<typeof testEnv>,
  headers: Record<string, string>,
  passage = genesis,
) {
  const response = await app.request(
    '/v1/imports',
    {
      method: 'POST',
      headers,
      body: JSON.stringify({
        idempotencyKey: crypto.randomUUID(),
        ranges: [passage],
        translation: 'JCB',
      }),
    },
    env,
  );
  expect(response.status).toBe(201);
  return (await response.json()) as { id: string };
}
it('serves literal primary text for non-Acts passages without pretending editorial or JCB review', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    user = await seedUser(env);
  const pin = seedScripture(db, [
    {
      book: 'GEN',
      chapter: 1,
      verse: 1,
      text: 'In the beginning, God created the heavens and the earth.',
    },
    {
      book: 'GEN',
      chapter: 1,
      verse: 3,
      text: 'God said, “Let there be light,” and there was light.',
    },
  ]);
  const row = await imported(env, user.headers);
  const response = await app.request(
    `/v1/imports/${row.id}/reading`,
    { headers: user.headers },
    env,
  );
  expect(response.status).toBe(200);
  const reading = (await response.json()) as any;
  expect(reading.overview.contentKind).toBe('literal-primary-text');
  expect(reading.overview.text).toContain('In the beginning');
  expect(reading.overview.claims).toEqual([]);
  expect(reading.overview.modelInvoked).toBe(false);
  expect(reading.overview.noticeJa).toContain('JCB');
  expect(reading.offlineCache.eligible).toBe(false);
  expect(
    reading.sources.every(
      (s: any) => s.reviewed === false && s.verification.manifestSha256 === pin.manifestSha256,
    ),
  ).toBe(true);
  const sources = await historicalSources(env, [{ citations: reading.overview.citations }]);
  expect(sources).toHaveLength(2);
  db.sqlite.prepare("UPDATE scripture_corpora SET active=0,rights_status='revoked'").run();
  expect(await historicalSources(env, [{ citations: reading.overview.citations }])).toEqual([]);
  expect(await getSources(env, genesis)).toEqual([]);
  const revoked = await app.request(
    `/v1/imports/${row.id}/scripture`,
    { headers: user.headers },
    env,
  );
  expect(((await revoked.json()) as any).available).toBe(false);
});
it('pages source text with stable exact range and policy-bound cursors without future verses', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    user = await seedUser(env),
    other = await seedUser(env);
  seedScripture(
    db,
    Array.from({ length: 111 }, (_, i) => ({
      book: 'PSA',
      chapter: 119,
      verse: i + 1,
      text: `Synthetic primary fixture ${i + 1}`,
    })),
  );
  const passage = {
    book: 'PSA',
    start: { chapter: 119, verse: 1 },
    end: { chapter: 119, verse: 110 },
  };
  const row = await imported(env, user.headers, passage);
  const get = (suffix = '') =>
    app.request(`/v1/imports/${row.id}/scripture${suffix}`, { headers: user.headers }, env);
  const first = (await (await get()).json()) as any;
  expect(first.items).toHaveLength(100);
  expect(first.items[0].verse).toBe(1);
  const second = (await (
    await get('?after=' + encodeURIComponent(first.nextCursor))
  ).json()) as any;
  expect(second.items).toHaveLength(10);
  expect(second.items.at(-1).verse).toBe(110);
  expect(second.nextCursor).toBeNull();
  expect(
    (await app.request(`/v1/imports/${row.id}/scripture`, { headers: other.headers }, env)).status,
  ).toBe(404);
  expect((await get('?rangeIndex=19')).status).toBe(400);
  expect((await get('?unexpected=true')).status).toBe(400);
  db.sqlite.prepare('UPDATE source_policy_state SET version=version+1 WHERE id=1').run();
  expect((await get('?after=' + encodeURIComponent(first.nextCursor))).status).toBe(409);
});
it('reports scoped source omissions without exposing unrelated future references', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    user = await seedUser(env);
  seedScripture(db, [{ book: 'ROM', chapter: 16, verse: 25, text: '' }], {
    emptyVerses: [
      { sourceBook: 'ROM', sourceChapter: 16, sourceVerse: '25' },
      { sourceBook: 'ACT', sourceChapter: 24, sourceVerse: '7' },
    ],
    missingCanonicalVerses: [
      { book: 'ROM', chapter: 16, verse: 26 },
      { book: 'ROM', chapter: 16, verse: 27 },
    ],
  });
  const row = await imported(env, user.headers, {
    book: 'ROM',
    start: { chapter: 16, verse: 25 },
    end: { chapter: 16, verse: 26 },
  });
  const page = (await (
    await app.request(`/v1/imports/${row.id}/scripture`, { headers: user.headers }, env)
  ).json()) as any;
  expect(page.available).toBe(true);
  expect(page.items).toEqual([]);
  expect(page.omissions).toEqual([
    { chapter: 16, verse: 25, reason: 'source_text_empty' },
    { chapter: 16, verse: 26, reason: 'source_reference_missing' },
  ]);
  expect(page.unversifiedTextIncluded).toBe(false);
});
it('enforces corpus staging and immutable verse identity in actual SQLite', () => {
  const db = new TestDatabase();
  const pin = seedScripture(db, [{ book: 'GEN', chapter: 1, verse: 1, text: 'Fixture' }]);
  expect(() => db.sqlite.prepare("UPDATE scripture_verses SET text='Changed'").run()).toThrow(
    'scripture_revision_immutable',
  );
  expect(() => db.sqlite.prepare('DELETE FROM scripture_verses').run()).toThrow(
    'scripture_revision_immutable',
  );
  expect(() =>
    db.sqlite.prepare('UPDATE scripture_corpora SET manifest_sha256=?').run('b'.repeat(64)),
  ).toThrow('scripture_revision_immutable');
  expect(() => db.sqlite.prepare("UPDATE scripture_corpora SET state='staging'").run()).toThrow(
    'scripture_revision_immutable',
  );
  expect(() => db.sqlite.prepare('DELETE FROM scripture_corpora').run()).toThrow(
    'scripture_revision_immutable',
  );
  expect(() =>
    db.sqlite.prepare("UPDATE public_sources SET id='webp:GEN:1:1' WHERE id='act-18-18'").run(),
  ).toThrow('reserved_scripture_namespace');
  expect(pin.sourceVersion).toBeTruthy();
});
