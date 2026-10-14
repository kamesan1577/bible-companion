import { describe, it, expect } from 'vitest';
import { testEnv, seedUser } from './helpers/db';
import { getSources } from '../src/data';
import { app } from '../src/index';
const passage = { book: 'ACT', start: { chapter: 18, verse: 1 }, end: { chapter: 18, verse: 1 } };
describe('bounded retrieval and private parent invariants', () => {
  it('keeps selected-range evidence ahead of dozens of later context sources', async () => {
    const env = testEnv();
    const original = await env.DB.prepare(
      "SELECT content_json FROM public_sources WHERE id='act-18-24-26'",
    ).first<{ content_json: string }>();
    expect(original).not.toBeNull();
    for (let i = 0; i < 80; i++) {
      const source = { ...JSON.parse(original!.content_json), id: `scale-${i}` };
      await env.DB.prepare(
        'INSERT INTO public_sources(id,book,start_chapter,start_verse,end_chapter,end_verse,kind,title,content_json,version,rights_status) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      )
        .bind(
          source.id,
          source.book,
          source.start.chapter,
          source.start.verse,
          source.end.chapter,
          source.end.verse,
          source.kind,
          source.title,
          JSON.stringify(source),
          source.version,
          'approved',
        )
        .run();
    }
    const sources = await getSources(env, passage, true);
    expect(sources.length).toBeLessThanOrEqual(64);
    expect(sources.some((source) => source.id === 'act-18-1')).toBe(true);
    expect(sources[0].id).toBe('act-18-1');
  });
  it('direct SQL cannot connect a conversation to another owner’s import', async () => {
    const env = testEnv(),
      a = await seedUser(env),
      b = await seedUser(env);
    const imported = (await (
      await app.request(
        '/v1/imports',
        {
          method: 'POST',
          headers: a.headers,
          body: JSON.stringify({ idempotencyKey: crypto.randomUUID(), ranges: [passage] }),
        },
        env,
      )
    ).json()) as { id: string };
    await expect(
      env.DB.prepare(
        'INSERT INTO conversations(id,user_id,import_id,passage_json,created_at) VALUES(?,?,?,?,?)',
      )
        .bind(crypto.randomUUID(), b.id, imported.id, JSON.stringify(passage), 1)
        .run(),
    ).rejects.toThrow('conversation_import_owner_mismatch');
  });
});
