import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { materialSchema, materialVisible } from '../src/materials';
const cards = JSON.parse(
  readFileSync(new URL('../fixtures/source-cards.json', import.meta.url), 'utf8'),
);
const evidence = JSON.parse(
  readFileSync(new URL('../../../data/geography/pleiades-evidence.json', import.meta.url), 'utf8'),
);
const ids: Record<string, string> = {
  'place-corinth': '570182',
  'place-cenchreae': '570347',
  'place-ephesus': '599612',
};
describe('reviewed geography subset', () => {
  it('maps only the three reviewed ancient places to exact published representative points', () => {
    const places = cards.filter((card: any) => card.kind === 'place');
    expect(places.map((card: any) => card.id).sort()).toEqual(Object.keys(ids).sort());
    for (const raw of places) {
      const card = materialSchema.parse(raw);
      if (card.kind !== 'place') throw new Error('Expected place');
      const entry = evidence.entries.find((item: any) => item.placeId === ids[card.id]);
      expect(card.details.coordinates).toMatchObject({
        ...entry.representativePoint,
        certainty: 'approximate',
      });
      expect(card.details.coordinates?.explanation).toContain('代表点');
      expect(entry.datasetCommit).toMatch(/^[a-f0-9]{40}$/);
      expect(entry.sourceSha256).toMatch(/^[a-f0-9]{64}$/);
      const source = card.provenance.find((item) => item.id === card.details.coordinates?.sourceId);
      expect(source).toMatchObject({
        license: 'cc-by-3.0',
        licenseUrl: 'https://creativecommons.org/licenses/by/3.0/',
      });
      expect(source?.attribution).toContain('Pleiades');
    }
  });
  it('retains the OpenStreetMap upstream attribution for derived Corinth and Ephesus points', () => {
    for (const id of ['place-corinth', 'place-ephesus']) {
      const card = materialSchema.parse(cards.find((item: any) => item.id === id));
      const osm = card.provenance.find((item) => item.license === 'odbl-1.0');
      expect(osm?.attribution).toContain('© OpenStreetMap contributors');
      expect(osm?.licenseUrl).toBe('https://opendatacommons.org/licenses/odbl/1-0/');
      expect(osm?.url).toMatch(/^https:\/\/www\.openstreetmap\.org\/way\/\d+$/);
    }
  });
  it('keeps geographic points behind the same passage/spoiler boundary as their cards', () => {
    const ephesus = materialSchema.parse(cards.find((item: any) => item.id === 'place-ephesus'));
    expect(
      materialVisible(
        ephesus,
        { book: 'ACT', start: { chapter: 18, verse: 18 }, end: { chapter: 18, verse: 18 } },
        false,
      ),
    ).toBe(false);
    expect(
      materialVisible(
        ephesus,
        { book: 'ACT', start: { chapter: 18, verse: 19 }, end: { chapter: 18, verse: 19 } },
        false,
      ),
    ).toBe(true);
  });
});
