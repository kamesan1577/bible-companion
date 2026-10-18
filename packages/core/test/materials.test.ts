import { describe, it, expect } from 'vitest';
import { materialSchema, materialVisible } from '../src/materials';
import cards from '../fixtures/source-cards.json';
const passage = { book: 'ACT', start: { chapter: 18, verse: 18 }, end: { chapter: 18, verse: 18 } };
const base = {
  id: 'place-kenchreai',
  kind: 'place',
  title: 'ケンクレア',
  summary: 'コリントの東側の港です。',
  passages: [passage],
  spoilerEnd: { book: 'ACT', chapter: 18, verse: 18 },
  version: 'test-1',
  reviewed: true,
  rightsStatus: 'approved',
  relationship: 'direct',
  provenance: [
    {
      id: 'primary',
      title: 'Primary archaeology record',
      url: 'https://www.ascsa.edu.gr/',
      publisher: 'ASCSA',
      checkedAt: '2026-10-13',
      license: 'citation-only',
    },
  ],
  details: { coordinates: null, identificationCertainty: 'confirmed' },
};
describe('source-verified material cards', () => {
  it('restricts artwork images to reviewed museum hosts without credentials, redirects or local addresses', () => {
    const artwork = cards.find((card) => card.kind === 'artwork')!;
    const valid = (url: string) =>
      materialSchema.safeParse({
        ...artwork,
        details: { ...artwork.details, media: { ...artwork.details.media, url } },
      }).success;
    for (const host of ['api.nga.gov', 'images.metmuseum.org', 'openaccess-cdn.clevelandart.org'])
      expect(valid(`https://${host}/image.jpg`)).toBe(true);
    const source = `https://piction.clevelandart.org/cma/ump.di?e=${'A'.repeat(64)}&s=24247294&se=116628280&v=3&f=1937.577_o2.jpg`;
    const proxy = (raw: string) =>
      'https://www.clevelandart.org/_next/image?' +
      new URLSearchParams({ url: raw, w: '1920', q: '75' });
    expect(valid(proxy(source))).toBe(true);
    for (const raw of [
      source.replace('piction.clevelandart.org', '127.0.0.1'),
      source + '&redirect=https://evil.com',
      source + '&v=4',
      source.replace('1937.577_o2.jpg', 'https://evil.com/a.jpg'),
      source.replace('/cma/ump.di', '/redirect'),
      'https://piction.clevelandart.org/cma/ump.di',
    ])
      expect(valid(proxy(raw)), raw).toBe(false);
    expect(valid(proxy(source) + '&q=75')).toBe(false);
    expect(valid(proxy(source).replace('w=1920', 'w=99999'))).toBe(false);
    for (const url of [
      'http://images.metmuseum.org/a.jpg',
      'https://images.metmuseum.org.evil.com/a.jpg',
      'https://evil.images.metmuseum.org/a.jpg',
      'https://images.metmuseum.org@127.0.0.1/a.jpg',
      'https://user:password@images.metmuseum.org/a.jpg',
      'https://127.0.0.1/a.jpg',
      'https://[::1]/a.jpg',
      'https://images.metmuseum.org:8443/a.jpg',
      'https://images.metmuseum.org/a.jpg?redirect=http://127.0.0.1',
      'https://images.metmuseum.org/a.jpg#fragment',
      'file:///tmp/image.jpg',
      'https://images.metmuseum.org./a.jpg',
    ])
      expect(valid(url), url).toBe(false);
  });
  it('keeps unknown coordinates explicit and distinguishes no map position from zero coordinates', () => {
    const card = materialSchema.parse(base);
    expect(card.kind === 'place' && card.details.coordinates).toBeNull();
    expect(materialVisible(card, passage, false)).toBe(true);
  });
  it('rejects coordinates without provenance and unsafe source URLs', () => {
    expect(
      materialSchema.safeParse({
        ...base,
        details: {
          ...base.details,
          coordinates: {
            latitude: 37.9,
            longitude: 22.9,
            certainty: 'approximate',
            sourceId: 'invented',
            explanation: 'Approximate',
          },
        },
      }).success,
    ).toBe(false);
    expect(
      materialSchema.safeParse({
        ...base,
        provenance: [{ ...base.provenance[0], url: 'javascript:alert(1)' }],
      }).success,
    ).toBe(false);
  });
  it('does not display future, unrelated, revoked or unreviewed cards', () => {
    const card = materialSchema.parse(base);
    expect(
      materialVisible(
        card,
        { ...passage, end: { chapter: 18, verse: 17 }, start: { chapter: 18, verse: 17 } },
        false,
      ),
    ).toBe(false);
    expect(materialVisible({ ...card, rightsStatus: 'revoked' }, passage, true)).toBe(false);
    expect(materialVisible({ ...card, reviewed: false }, passage, true)).toBe(false);
    expect(
      materialVisible(
        card,
        { book: 'ACT', start: { chapter: 9, verse: 3 }, end: { chapter: 9, verse: 7 } },
        true,
      ),
    ).toBe(false);
  });
  it('rejects whole-card bounds earlier than any associated passage', () =>
    expect(
      materialSchema.safeParse({ ...base, spoilerEnd: { book: 'ACT', chapter: 18, verse: 17 } })
        .success,
    ).toBe(false));
});
