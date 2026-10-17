import { it, expect } from 'vitest';
import { app } from '../src/index';
import { getSources } from '../src/data';
import { historicalSources } from '../src/history';
import { TestDatabase, testEnv, seedUser } from './helpers/db';
import { seedAssetCorpus, realAssetBinding } from './helpers/scripture-assets';
const genesis = { book: 'GEN', start: { chapter: 1, verse: 1 }, end: { chapter: 1, verse: 3 } };
it('uses verified per-book assets without verse rows and reuses only immutable public bytes', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    calls: string[] = [];
  seedAssetCorpus(db);
  env.SCRIPTURE_ASSETS = realAssetBinding(calls);
  const first = await getSources(env, genesis);
  expect(first).toHaveLength(3);
  expect(first[0].text).toContain('In the beginning');
  expect(first.every((s) => !s.reviewed)).toBe(true);
  expect(calls).toHaveLength(2);
  expect(calls[0]).toMatch(/\/GEN\/index.json$/);
  expect(calls[1]).toMatch(/\/GEN\/1.json$/);
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM scripture_verses').get()?.n).toBe(0);
  expect(await getSources(env, genesis)).toHaveLength(3);
  expect(calls).toHaveLength(2);
  const historical = await historicalSources(env, [
    { citations: first.map((s) => ({ sourceId: s.id, version: s.version })) },
  ]);
  expect(historical).toHaveLength(3);
  db.sqlite.prepare("UPDATE scripture_corpora SET active=0,rights_status='revoked'").run();
  expect(await getSources(env, genesis)).toEqual([]);
  expect(
    await historicalSources(env, [
      { citations: first.map((s) => ({ sourceId: s.id, version: s.version })) },
    ]),
  ).toEqual([]);
  expect(calls).toHaveLength(2);
});
it('pages actual Psalm text and never needs the global index or full book body', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    calls: string[] = [];
  seedAssetCorpus(db);
  env.SCRIPTURE_ASSETS = realAssetBinding(calls);
  const user = await seedUser(env);
  const passage = {
    book: 'PSA',
    start: { chapter: 119, verse: 1 },
    end: { chapter: 119, verse: 176 },
  };
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
  const first = (await (
    await app.request(`/v1/imports/${imported.id}/scripture`, { headers: user.headers }, env)
  ).json()) as any;
  expect(first.items).toHaveLength(100);
  expect(first.items[0].verse).toBe(1);
  expect(first.items[99].verse).toBe(100);
  const second = (await (
    await app.request(
      `/v1/imports/${imported.id}/scripture?after=${encodeURIComponent(first.nextCursor)}`,
      { headers: user.headers },
      env,
    )
  ).json()) as any;
  expect(second.items).toHaveLength(76);
  expect(second.nextCursor).toBeNull();
  expect(second.items.at(-1).verse).toBe(176);
  expect(calls).toHaveLength(2);
  expect(calls.every((path) => path.includes('/PSA/'))).toBe(true);
});
it('rejects in-flight rights changes before returning newly fetched public sources', async () => {
  const db = new TestDatabase(),
    env = testEnv(db);
  seedAssetCorpus(db);
  const backing = realAssetBinding();
  let count = 0;
  env.SCRIPTURE_ASSETS = {
    async fetch(request) {
      const response = await backing.fetch(request);
      if (++count === 2)
        db.sqlite.prepare("UPDATE scripture_corpora SET active=0,rights_status='revoked'").run();
      return response;
    },
  };
  await expect(getSources(env, genesis)).rejects.toThrow();
});
it('rejects corrupted book indexes and chapters without fallback to an older storage mode', async () => {
  for (const target of ['index.json', '1.json']) {
    const db = new TestDatabase(),
      env = testEnv(db);
    seedAssetCorpus(db);
    const backing = realAssetBinding();
    env.SCRIPTURE_ASSETS = {
      async fetch(request) {
        if (new URL(request.url).pathname.endsWith('/' + target))
          return new Response('{"forged":true}', {
            headers: { 'content-type': 'application/json' },
          });
        return backing.fetch(request);
      },
    };
    await expect(getSources(env, genesis)).rejects.toThrow();
  }
});
it('never returns future verses in a narrow reference even though the asset contains the chapter', async () => {
  const db = new TestDatabase(),
    env = testEnv(db);
  seedAssetCorpus(db);
  env.SCRIPTURE_ASSETS = realAssetBinding();
  const sources = await getSources(env, {
    book: 'GEN',
    start: { chapter: 1, verse: 1 },
    end: { chapter: 1, verse: 1 },
  });
  expect(sources).toHaveLength(1);
  expect(sources[0].end.verse).toBe(1);
  expect(sources[0].text).not.toContain('Let there be light');
});

it('keeps Acts28:15/26:32 selection and the earlier appeal evidence under existing limits', async () => {
  const {retrieveGrounding} = await import('../../../packages/ai-harness/src/grounding');
  const db = new TestDatabase(), env = testEnv(db);
  seedAssetCorpus(db); env.SCRIPTURE_ASSETS = realAssetBinding([]);
  const target={book:'ACT',start:{chapter:26,verse:32},end:{chapter:26,verse:32}};
  const sources=await getSources(env,target,false,target,undefined,false,true);
  expect(sources.some(source=>source.start.chapter===26 && source.start.verse===32)).toBe(true);
  expect(sources.some(source=>source.start.chapter===25 && source.start.verse===11)).toBe(true);
  const retrieved=retrieveGrounding({passage:target,question:'結局なんで上訴したの？',spoilerAllowed:false,sources},'alice');
  expect(retrieved.sources.some(source=>source.start.chapter===26 && source.start.verse===32)).toBe(true);
  expect(retrieved.sources.some(source=>source.start.chapter===25 && source.start.verse===11)).toBe(true);
  expect(retrieved.sources.length).toBeLessThanOrEqual(16);
  expect(retrieved.sources.every(source=>source.end.chapter<=26 && (source.end.chapter<26 || source.end.verse<=32))).toBe(true);
});
