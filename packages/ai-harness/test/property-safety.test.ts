import { offlineFixtureAuthorization } from '../fixtures/authorization.ts';
import { describe, it, expect } from 'vitest';
import {
  retrieveGrounding,
  eligibleClaims,
  validateSelection,
  prepareCompanionRequest,
  DEFAULT_MODEL_ID,
  getModelPricing,
} from '../src/index.ts';
import { ACTS_SOURCES } from '../fixtures/acts-sources.ts';
import type { AnswerInput } from '../src/types.ts';
// Deterministic data variation, not a random model-quality benchmark.
function generator(seed: number) {
  return () => {
    seed = (1664525 * seed + 1013904223) >>> 0;
    return seed / 4294967296;
  };
}
describe('deterministic guardrail properties over varied metadata', () => {
  it('every rendered strict claim/citation came from an eligible source in 300 varied requests', () => {
    const random = generator(20261013);
    for (let iteration = 0; iteration < 300; iteration++) {
      const end = 1 + Math.floor(random() * 28),
        start = 1 + Math.floor(random() * end);
      const request: AnswerInput = {
        passage: {
          book: 'ACT',
          start: { chapter: 18, verse: start },
          end: { chapter: 18, verse: end },
        },
        question: 'この箇所の説明',
        spoilerAllowed: false,
        sources: structuredClone(ACTS_SOURCES),
      };
      for (const source of request.sources) {
        if (random() < 0.2) {
          source.visibility = 'private';
          source.ownerId = random() < 0.5 ? 'alice' : 'bob';
        }
        if (random() < 0.15) source.reviewed = false;
        if (random() < 0.15) source.generationAllowed = false;
      }
      const retrieved = retrieveGrounding(request, 'alice');
      const candidates = eligibleClaims(retrieved.sources);
      const chosen = candidates.filter(() => random() < 0.5).slice(0, 3);
      const result = validateSelection(
        JSON.stringify({
          status: chosen.length ? 'answer' : 'insufficient',
          claimKeys: chosen.map((c) => c.key),
        }),
        retrieved.sources,
      );
      for (const claim of result.claims) {
        const source = retrieved.sources.find((s) => s.id === claim.sourceId)!;
        expect(source.reviewed && source.generationAllowed).toBe(true);
        expect(source.visibility === 'public' || source.ownerId === 'alice').toBe(true);
        expect(source.book).toBe('ACT');
        expect(source.spoilerEnd.chapter < 18 || source.spoilerEnd.verse <= end).toBe(true);
        expect(
          source.claims.some(
            (c) => c.text === claim.text && c.evidenceQuote === claim.evidenceQuote,
          ),
        ).toBe(true);
        expect(
          result.citations.some((c) => c.sourceId === source.id && c.version === source.version),
        ).toBe(true);
      }
      const payload = JSON.stringify(
        prepareCompanionRequest(request, {
          authorization: offlineFixtureAuthorization('alice', DEFAULT_MODEL_ID),
        }).messages,
      );
      expect(payload).not.toContain('"ownerId"');
    }
  });
  it('candidate rate objects cannot be mutated to reduce reservations', () => {
    const rates = getModelPricing(DEFAULT_MODEL_ID);
    expect(Object.isFrozen(rates)).toBe(true);
    expect(() => Object.assign(rates, { outputNeuronsPerMillionTokens: 0 })).toThrow();
  });
});
