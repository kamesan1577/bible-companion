import { offlineFixtureAuthorization } from '../fixtures/authorization.ts';
import { describe, it, expect } from 'vitest';
import {
  prepareCompanionRequest,
  retrieveGrounding,
  createSourceOnlyAnswer,
  createPrivateCacheKey,
  validateGeneratedAnswer,
  DEFAULT_MODEL_ID,
} from '../src/index.ts';
import type { AnswerInput, HistoryTurn } from '../src/types.ts';
import { ACTS_SOURCES } from '../fixtures/acts-sources.ts';
const authorization = offlineFixtureAuthorization('alice', DEFAULT_MODEL_ID);
const target = { book: 'ACT', start: { chapter: 18, verse: 3 }, end: { chapter: 18, verse: 3 } };
const readingBoundary = {
  book: 'ACT',
  start: { chapter: 18, verse: 1 },
  end: { chapter: 18, verse: 18 },
};
const input = (): AnswerInput => ({
  passage: structuredClone(target),
  readingBoundary: structuredClone(readingBoundary),
  question: 'この部分を教えて',
  spoilerAllowed: false,
  sources: structuredClone(ACTS_SOURCES),
});
describe('independent target and available reading boundary', () => {
  it('retains later-in-reading sources but excludes events beyond the reader boundary', () => {
    const prepared = prepareCompanionRequest(input(), { authorization });
    expect(prepared.retrieval.sources.some((s) => s.id === 'act-18-17')).toBe(true);
    expect(prepared.retrieval.sources.some((s) => s.id === 'act-18-24-26')).toBe(false);
    expect(JSON.parse(prepared.messages[1].content).boundary).toEqual({
      book: 'ACT',
      chapter: 18,
      verse: 18,
    });
    expect(JSON.parse(prepared.messages[1].content).passage).toEqual(target);
  });
  it.each([
    { ...readingBoundary, book: 'GEN' },
    { ...readingBoundary, start: { chapter: 18, verse: 4 } },
    { ...readingBoundary, end: { chapter: 18, verse: 2 } },
    { ...readingBoundary, end: { chapter: 18, verse: 99 } },
    null,
  ])('rejects a boundary that does not validly contain target %j', (boundary) => {
    expect(() =>
      prepareCompanionRequest(
        { ...input(), readingBoundary: boundary as never },
        { authorization },
      ),
    ).toThrow('INVALID_INPUT');
  });
  it('defaults omitted reading boundary to target end', () => {
    const request = input();
    delete request.readingBoundary;
    expect(retrieveGrounding(request, 'alice').sources.some((s) => s.id === 'act-18-17')).toBe(
      false,
    );
  });
  it('source-only fallback stays focused on selection, not all available later material', () => {
    const result = createSourceOnlyAnswer(input(), 'alice');
    expect(result.citations.map((c) => c.sourceId)).toEqual(['act-18-2-3']);
    expect(result.answer).not.toContain('ソステネ');
  });
  it('cache identity includes reading boundary independently of selection', async () => {
    const request = input();
    const key = await createPrivateCacheKey(request, { authorization });
    expect(
      await createPrivateCacheKey(
        { ...request, readingBoundary: { ...readingBoundary, end: { chapter: 18, verse: 17 } } },
        { authorization },
      ),
    ).not.toBe(key);
    const noBoundary = { ...request };
    delete noBoundary.readingBoundary;
    expect(
      await createPrivateCacheKey({ ...noBoundary, readingBoundary: target }, { authorization }),
    ).toBe(await createPrivateCacheKey(noBoundary, { authorization }));
  });
  it('rejects history created with a broader reading boundary after narrowing', () => {
    const request = input();
    request.readingBoundary = { ...readingBoundary, end: { chapter: 18, verse: 3 } };
    request.history = [
      {
        role: 'assistant',
        content: 'CONTEXT_FROM_LATER_READING',
        ownerId: 'alice',
        scope: {
          passage: target,
          readingBoundary,
          spoilerAllowed: false,
          sourceIds: ['act-18-2-3'],
          sourceVersions: {
            'act-18-2-3': ACTS_SOURCES.find((s) => s.id === 'act-18-2-3')!.version,
          },
        },
      },
    ];
    expect(prepareCompanionRequest(request, { authorization }).history).toEqual([]);
  });
  it('whitelists replayed history metadata and only referenced versions', () => {
    const request = input();
    const source = request.sources.find((s) => s.id === 'act-18-2-3')!;
    request.history = [
      {
        role: 'assistant',
        content: 'SAFE_CONTEXT',
        ownerId: 'alice',
        scope: {
          passage: target,
          spoilerAllowed: false,
          sourceIds: [source.id],
          sourceVersions: {
            [source.id]: source.version,
            otherUsersSource: 'PRIVATE_VERSION_SECRET',
          },
          privateDatabaseNote: 'SECRET_METADATA',
        } as unknown as HistoryTurn['scope'],
      },
    ];
    const messages = JSON.stringify(prepareCompanionRequest(request, { authorization }).messages);
    expect(messages).toContain('SAFE_CONTEXT');
    expect(messages).not.toContain('PRIVATE_VERSION_SECRET');
    expect(messages).not.toContain('SECRET_METADATA');
  });
  it('prioritizes target material before context truncation', () => {
    const request = input();
    request.sources = [
      ...Array.from({ length: 25 }, (_, i) => ({
        ...structuredClone(ACTS_SOURCES[0]),
        id: `old-${i}`,
      })),
      structuredClone(ACTS_SOURCES.find((s) => s.id === 'act-18-2-3')!),
    ];
    const retrieved = retrieveGrounding(request, 'alice');
    expect(retrieved.sources[0].id).toBe('act-18-2-3');
    expect(retrieved.excluded.contextLimit).toBeGreaterThan(0);
  });
  it('generated faith labels receive the same explicit-reference/link checks as prose', () => {
    const request = input();
    const sources = retrieveGrounding(request, 'alice').sources;
    const claim = {
      text: '信仰的な読み方です。',
      kind: 'faith',
      sourceId: 'act-18-2-3',
      evidenceQuote: 'for by trade they were tent makers.',
    };
    for (const tradition of [
      '使徒18:26に基づく解釈',
      '使徒１８：２６の解釈',
      'https://evil.example',
    ])
      expect(() =>
        validateGeneratedAnswer(
          JSON.stringify({ status: 'answer', claims: [{ ...claim, tradition }] }),
          sources,
          readingBoundary,
          false,
        ),
      ).toThrow('INVALID_RESPONSE');
  });
});

describe('history provenance must not be silently rewritten', () => {
  it('omits a source-referencing user turn with an old version too', () => {
    const request = input();
    request.history = [
      {
        role: 'user',
        content: 'OLD_QUOTED_CONTENT',
        ownerId: 'alice',
        scope: {
          passage: target,
          readingBoundary,
          spoilerAllowed: false,
          sourceIds: ['act-18-2-3'],
          sourceVersions: { 'act-18-2-3': 'obsolete' },
        },
      },
    ];
    expect(prepareCompanionRequest(request, { authorization }).history).toEqual([]);
  });
});
