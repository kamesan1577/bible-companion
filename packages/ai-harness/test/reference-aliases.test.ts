import { describe, expect, it } from 'vitest';
import { BOOKS } from '../../core/src/index.ts';
import { assertReferencesWithinBoundary, validateGeneratedAnswer } from '../src/output.ts';
import { ACTS_SOURCES } from '../fixtures/acts-sources.ts';

const boundary = {
  book: 'ACT',
  start: { chapter: 18, verse: 1 },
  end: { chapter: 18, verse: 18 },
};

describe('generated explicit references share import book aliases', () => {
  it('recognizes all canonical English and Japanese book names instead of assuming the current book', () => {
    for (const book of BOOKS) {
      for (const alias of [book.id, book.en, book.ja]) {
        const check = () => assertReferencesWithinBoundary(`${alias} 1:1`, boundary, false);
        if (book.id === boundary.book) expect(check).not.toThrow();
        else expect(check, alias).toThrow('INVALID_RESPONSE');
        expect(
          () => assertReferencesWithinBoundary(`${alias} 1:1`, boundary, true),
          alias,
        ).not.toThrow();
      }
    }
  });

  it('blocks cross-book Japanese short names, ordinal variants, and dotted abbreviations', () => {
    for (const reference of [
      'ヨハネ３：１６',
      'ヨハネの福音書3章16節',
      'ヨハネ（3:16）',
      'John [3:16]',
      'ヨハネの福音書「３章１６節」',
      '第一コリント1:1',
      'コリント人への手紙Ⅰ 1:1',
      '1 Cor. 1:1',
      'John 3:16',
      'ヨハネの黙示録1:1',
    ]) {
      expect(() => assertReferencesWithinBoundary(reference, boundary, false), reference).toThrow(
        'INVALID_RESPONSE',
      );
      expect(
        () => assertReferencesWithinBoundary(reference, boundary, true),
        reference,
      ).not.toThrow();
    }
  });

  it('preserves valid local references, punctuation, and bare verse numbers', () => {
    for (const text of [
      '使徒の働き１８：１７です。',
      '（Acts 18:17）',
      'ACT.18:17',
      '18章17節',
      '18:17–18',
      '17節で語られます。',
      'This passage (18:17) describes it.',
      'See 18:17 for the text.',
      'In 18:17 the name appears.',
    ])
      expect(() => assertReferencesWithinBoundary(text, boundary, false), text).not.toThrow();
    for (const text of ['使徒言行録18:19', 'Acts 18:17–19', '使徒の働き29:1'])
      expect(() => assertReferencesWithinBoundary(text, boundary, false), text).toThrow(
        'INVALID_RESPONSE',
      );
  });

  it('checks complete numeric runs without truncating verses or detaching the book', () => {
    for (const reference of [
      'John 0003:16',
      'Acts 1018:17',
      'Acts 18:0019',
      'Acts 18:17–0019',
      'Ａｃｔｓ １８：００１９',
      `Acts 18:${'9'.repeat(280)}`,
      `Acts 18:${'⑳'.repeat(290)}`,
    ])
      expect(() => assertReferencesWithinBoundary(reference, boundary, false), reference).toThrow(
        'INVALID_RESPONSE',
      );
    const psalm = {
      book: 'PSA',
      start: { chapter: 119, verse: 1 },
      end: { chapter: 119, verse: 176 },
    };
    expect(() => assertReferencesWithinBoundary('Psalm 119:1760', psalm, true)).toThrow(
      'INVALID_RESPONSE',
    );
    expect(() => assertReferencesWithinBoundary('Acts 0018:0017', boundary, false)).not.toThrow();
  });

  it('checks Japanese cross-book aliases in both generated prose and faith labels', () => {
    const claim = {
      text: 'ソステネは会堂の指導者として登場します。',
      kind: 'fact',
      sourceId: 'act-18-17',
      evidenceQuote: 'Sosthenes, the ruler of the synagogue',
    };
    for (const changed of [
      { text: 'ヨハネ3:16にも書かれています。' },
      { kind: 'faith', tradition: 'ヨハネ3:16の解釈' },
    ])
      expect(() =>
        validateGeneratedAnswer(
          JSON.stringify({ status: 'answer', claims: [{ ...claim, ...changed }] }),
          ACTS_SOURCES,
          boundary,
          false,
        ),
      ).toThrow('INVALID_RESPONSE');
  });
});
