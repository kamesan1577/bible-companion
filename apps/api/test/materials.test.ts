import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser } from './helpers/db';
import { materialSchema } from '../../../packages/core/src/materials';
import fixtures from '../../../packages/core/fixtures/source-cards.json';
async function setup(chapter: number, start: number, end = start) {
  const env = testEnv(),
    user = await seedUser(env);
  const response = await app.request(
    '/v1/imports',
    {
      method: 'POST',
      headers: user.headers,
      body: JSON.stringify({
        idempotencyKey: crypto.randomUUID(),
        ranges: [{ book: 'ACT', start: { chapter, verse: start }, end: { chapter, verse: end } }],
      }),
    },
    env,
  );
  const row = (await response.json()) as { id: string };
  const read = async () =>
    (await (
      await app.request(`/v1/imports/${row.id}/reading`, { headers: user.headers }, env)
    ).json()) as {
      places: any[];
      people: any[];
      artworks: any[];
      sourceVersion: string;
      cache: string;
    };
  return { env, user, read };
}
describe('reviewed primary-source cards', () => {
  it('validates all curated cards and rejects unapproved automatic image destinations', () => {
    for (const card of fixtures) expect(materialSchema.safeParse(card).success, card.id).toBe(true);
    const art = fixtures.find((c) => c.kind === 'artwork')!;
    for (const url of [
      'https://127.0.0.1/x',
      'https://localhost/x',
      'https://api.nga.gov:8443/x',
      'https://unreviewed.example.org/x',
      'https://user@api.nga.gov/x',
    ]) {
      expect(
        materialSchema.safeParse({
          ...art,
          details: { ...art.details, media: { ...art.details.media, url } },
        }).success,
      ).toBe(false);
    }
  });
  it('shows applicable places with attributed approximate coordinates and does not reuse Acts 9 art in Acts 18', async () => {
    const { read } = await setup(18, 18);
    const value = await read();
    expect(value.places.map((x) => x.title).join(' ')).toContain('ケンクレア');
    expect(value.places.every((x) => x.details.coordinates?.certainty === 'approximate')).toBe(
      true,
    );
    for (const card of value.places)
      expect(
        card.provenance.some(
          (p: { id: string; license: string; attribution?: string; licenseUrl?: string }) =>
            p.id === card.details.coordinates?.sourceId &&
            p.license === 'cc-by-3.0' &&
            p.attribution &&
            p.licenseUrl,
        ),
      ).toBe(true);
    expect(value.artworks).toEqual([]);
    for (const card of [...value.people, ...value.places])
      for (const p of card.passages)
        expect(p.end.chapter * 1000 + p.end.verse).toBeLessThanOrEqual(18018);
  });
  it('shows the explicitly licensed exact-passage artwork only after its complete scene boundary', async () => {
    const before = await setup(9, 3, 6);
    expect((await before.read()).artworks).toEqual([]);
    const exact = await setup(9, 3, 7);
    const cards = (await exact.read()).artworks;
    expect(cards).toHaveLength(1);
    expect(cards[0].details.media.rights).toBe('public-domain');
    expect(new URL(cards[0].details.media.url).hostname).toBe('api.nga.gov');
  });
  it('revocation invalidates public caches and the offline manifest even without a version string change', async () => {
    const { env, user, read } = await setup(18, 18);
    const manifest = async () =>
      (await (
        await app.request('/v1/content-manifest', { headers: user.headers }, env)
      ).json()) as { version: string };
    const initial = await read();
    expect((await read()).cache).toBe('public-hit');
    const oldManifest = await manifest();
    const id = initial.places[0].id;
    await env.DB.prepare("UPDATE public_materials SET rights_status='revoked' WHERE id=?")
      .bind(id)
      .run();
    const changed = await read();
    expect(changed.places.some((x) => x.id === id)).toBe(false);
    expect(changed.sourceVersion).not.toBe(initial.sourceVersion);
    expect((await manifest()).version).not.toBe(oldManifest.version);
    const previous = await manifest();
    await env.DB.prepare(
      'UPDATE public_sources SET content_json=content_json WHERE id=(SELECT id FROM public_sources LIMIT 1)',
    ).run();
    expect((await manifest()).version).not.toBe(previous.version);
  });
});

it('corrupt material JSON or primitive range entries cannot break the reading endpoint', async () => {
  const { env, read } = await setup(18, 18);
  for (const [id, body] of [
    ['broken-json', 'not json'],
    ['primitive-range', '{"passages":["malformed",null,42]}'],
  ])
    await env.DB.prepare(
      "INSERT INTO public_materials(id,kind,book,data_json,version,rights_status) VALUES(?,'place','ACT',?,'bad-fixture','approved')",
    )
      .bind(id, body)
      .run();
  const result = await read();
  expect(result.places.length).toBeGreaterThan(0);
  expect(result.places.every((card) => !['broken-json', 'primitive-range'].includes(card.id))).toBe(
    true,
  );
});

it('offline grants follow actual reviewed public-domain citations and explicit manifest metadata', async () => {
  const { env, user, read } = await setup(18, 18);
  const before = (await read()) as any;
  expect(before.offlineCache.eligible).toBe(true);
  expect(before.offlineCache.allowedFields).toEqual(['overview']);
  expect(before.offlineCache.maxAgeSeconds).toBe(86400);
  const original = await env.DB.prepare(
    "SELECT content_json FROM public_sources WHERE id='act-18-18'",
  ).first<{ content_json: string }>();
  const changed = {
    ...JSON.parse(original!.content_json),
    version: 'licensed-unreviewed-test-v2',
    license: 'licensed',
    reviewed: false,
  };
  await env.DB.prepare("UPDATE public_sources SET version=?,content_json=? WHERE id='act-18-18'")
    .bind(changed.version, JSON.stringify(changed))
    .run();
  const manifest = (await (
    await app.request('/v1/content-manifest', { headers: user.headers }, env)
  ).json()) as { items: any[] };
  expect(manifest.items.find((x) => x.id === 'act-18-18')).toMatchObject({
    license: 'licensed',
    reviewed: false,
    visibility: 'public',
    version: changed.version,
  });
  const after = (await read()) as any;
  expect(after.offlineCache.eligible).toBe(false);
  expect(after.offlineCache.maxAgeSeconds).toBe(0);
});
