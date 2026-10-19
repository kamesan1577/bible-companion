import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { testEnv, TestDatabase } from './helpers/db';
import { getMaterials } from '../src/materials';
import { materialSchema, materialVisible } from '../../../packages/core/src/materials';
import raw from '../../../packages/core/fixtures/artwork-catalog.json';
import legacy from '../../../packages/core/fixtures/source-cards.json';
const cards = raw.map((card) => materialSchema.parse(card));
const migration = readFileSync(
  new URL('../migrations/0026_reviewed_artwork_catalog.sql', import.meta.url),
  'utf8',
);

describe('reviewed artwork catalog adoption', () => {
  it('contains unique illustrated physical works with retained rights, attribution and scene evidence', () => {
    expect(cards.length).toBeGreaterThanOrEqual(40);
    expect(new Set(cards.map((card) => card.id)).size).toBe(cards.length);
    expect(new Set(raw.map((card) => card.details.objectUrl)).size).toBe(cards.length);
    for (const card of raw) {
      expect(card.reviewed).toBe(true);
      expect(card.rightsStatus).toBe('approved');
      expect(card.details.media.rights).toBe('public-domain');
      expect(card.details.media.attribution.length).toBeGreaterThan(10);
      expect(card.provenance.some((source) => source.url === card.details.objectUrl)).toBe(true);
      expect(card.provenance.some((source) => source.url === card.details.media.rightsUrl)).toBe(
        true,
      );
    }
  });
  it('actually projects every registered scene only after its full ending, with no cross-book or rights leak', async () => {
    const env = testEnv();
    for (const card of cards) {
      const end = { chapter: card.spoilerEnd.chapter, verse: card.spoilerEnd.verse };
      const passage = { book: card.spoilerEnd.book, start: end, end };
      // The selected endpoint belongs to the scene, not merely to the same book.
      expect(
        (await getMaterials(env, passage)).some((value) => value.id === card.id),
        card.id,
      ).toBe(true);
      const first = card.passages[0];
      if (end.verse > 1) {
        const before = {
          ...passage,
          start: { chapter: end.chapter, verse: end.verse - 1 },
          end: { chapter: end.chapter, verse: end.verse - 1 },
        };
        expect(
          (await getMaterials(env, before)).some((value) => value.id === card.id),
          card.id,
        ).toBe(false);
      }
      expect(
        materialVisible(
          card,
          { book: 'LEV', start: { chapter: 19, verse: 1 }, end: { chapter: 19, verse: 2 } },
          true,
        ),
      ).toBe(false);
      expect(materialVisible({ ...card, rightsStatus: 'revoked' }, first, true)).toBe(false);
      expect(materialVisible({ ...card, reviewed: false }, first, true)).toBe(false);
      const nonoverlap = {
        book: first.book,
        start: { chapter: 1, verse: 1 },
        end: { chapter: 1, verse: 1 },
      };
      expect(materialVisible(card, nonoverlap, true)).toBe(false);
    }
  });
  it('adds only catalog-owned rows and preserves prior data through repeated upserts', () => {
    const database = new TestDatabase();
    const priorRows = () =>
      database.sqlite
        .prepare(
          'SELECT * FROM public_materials WHERE id IN (' +
            legacy.map(() => '?').join(',') +
            ') ORDER BY id',
        )
        .all(...legacy.map((card) => card.id));
    const prior = priorRows();
    database.sqlite.exec(migration);
    expect(priorRows()).toEqual(prior);
    for (const card of cards)
      expect(
        database.sqlite
          .prepare('SELECT version,rights_status FROM public_materials WHERE id=?')
          .get(card.id),
      ).toEqual({ version: card.version, rights_status: 'approved' });
    expect(database.sqlite.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
    expect(
      database.sqlite
        .prepare("SELECT count(*) AS n FROM public_materials WHERE kind='artwork'")
        .get()?.n,
    ).toBe(cards.length + 1);
  });
  it('includes the ram in the Isaac boundary and keeps thematic resurrection distinct from literal narrative', () => {
    const isaac = raw.find((card) => card.details.objectUrl.endsWith('/1937.577'))!;
    expect(isaac.spoilerEnd).toEqual({ book: 'GEN', chapter: 22, verse: 13 });
    const resurrection = raw.find((card) => card.details.objectUrl.includes('/41670-'))!;
    expect(resurrection.relationship).toBe('thematic');
    expect(resurrection.summary).toContain('福音書');
    expect(
      raw.some(
        (card) => card.details.objectUrl.includes('/436504') || card.spoilerEnd.book === 'DAN',
      ),
    ).toBe(false);
  });
});
