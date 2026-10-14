import { describe, expect, it } from 'vitest';
import counts from '../src/verse-counts.json';
import {
  BOOKS,
  containsPassage,
  parseImport,
  passageSchema,
  questionContextWindow,
  type Passage,
} from '../src/index';

const metadata = counts as Record<string, number[]>;
function ordinal(book: string, point: { chapter: number; verse: number }) {
  return (
    metadata[book].slice(0, point.chapter - 1).reduce((sum, count) => sum + count, 0) + point.verse
  );
}

describe('canonical context invariants across every chapter boundary', () => {
  it('retains each chapter endpoint, stays inside the confirmed book, and adds at most eight verses each side', () => {
    let checked = 0;
    for (const book of BOOKS) {
      const chapters = metadata[book.id];
      const boundary: Passage = {
        book: book.id,
        start: { chapter: 1, verse: 1 },
        end: { chapter: chapters.length, verse: chapters.at(-1)! },
      };
      for (let chapter = 1; chapter <= chapters.length; chapter++) {
        for (const verse of new Set([1, chapters[chapter - 1]])) {
          const target: Passage = {
            book: book.id,
            start: { chapter, verse },
            end: { chapter, verse },
          };
          const before = JSON.stringify([boundary, target]);
          const context = questionContextWindow(boundary, target);
          expect(passageSchema.safeParse(context).success).toBe(true);
          expect(containsPassage(boundary, context)).toBe(true);
          expect(containsPassage(context, target)).toBe(true);
          expect(
            ordinal(book.id, target.start) - ordinal(book.id, context.start),
          ).toBeLessThanOrEqual(8);
          expect(ordinal(book.id, context.end) - ordinal(book.id, target.end)).toBeLessThanOrEqual(
            8,
          );
          expect(JSON.stringify([boundary, target])).toBe(before);
          checked++;
        }
      }
    }
    expect(checked).toBe(2378);
  });
  it('keeps a cross-chapter long target unchanged rather than displacing it with context', () => {
    for (const book of BOOKS.filter((item) => item.chapters > 1)) {
      const chapters = metadata[book.id];
      const boundary: Passage = {
        book: book.id,
        start: { chapter: 1, verse: 1 },
        end: { chapter: chapters.length, verse: chapters.at(-1)! },
      };
      if (ordinal(book.id, boundary.end) <= 32) continue;
      expect(questionContextWindow(boundary, boundary)).toEqual(boundary);
    }
  });
});

describe('mixed-language shared reference consistency', () => {
  it('deduplicates matching Japanese, English, and YouVersion references across all books', () => {
    for (const book of BOOKS) {
      const text = `${book.ja}１：１（ＪＣＢ）\r\n${book.en} 1:1 JCB\nhttps://www.bible.com/ja/bible/83/${book.id}.1.1.JCB?private=discarded#fragment`;
      const result = parseImport(text);
      expect(result.ranges).toEqual([
        { book: book.id, start: { chapter: 1, verse: 1 }, end: { chapter: 1, verse: 1 } },
      ]);
      expect(result.needsConfirmation).toBe(false);
      expect(result.sourceUrl).not.toContain('?');
      expect(result.sourceUrl).not.toContain('#');
      const conflict = parseImport(text + `\n${book.en} 1:2 JCB`);
      expect(conflict.ranges).toEqual([]);
      expect(conflict.needsConfirmation).toBe(true);
    }
  });
  it.each([
    '0',
    '-1',
    '999999999999999999999',
    '1-0',
    '1-999999999999999999',
    '1,,2',
    '1-2:',
    '1-2:0',
  ])('fails closed for malformed range tail %s', (tail) => {
    expect(() => parseImport(`Acts 1:${tail} JCB`)).toThrow();
  });
});
