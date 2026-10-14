import { offlineFixtureAuthorization } from '../fixtures/authorization.ts';
import { describe, it, expect, vi } from 'vitest';
import {
  createCompanionAnswer,
  prepareCompanionRequest,
  eligibleClaims,
  validateGeneratedAnswer,
  DEFAULT_MODEL_ID,
} from '../src/index.ts';
import { BIBLE_QUESTIONS, inputForCase } from '../fixtures/questions.ts';
const authorization = offlineFixtureAuthorization('alice', DEFAULT_MODEL_ID);
describe('Japanese Bible question contracts using explicitly scripted offline providers', () => {
  it.each(BIBLE_QUESTIONS)('$id: $question', async (test) => {
    const input = inputForCase(test);
    const prepared = prepareCompanionRequest(input, { authorization });
    const keys = eligibleClaims(prepared.retrieval.sources)
      .filter((c) => test.expectedClaimIds.includes(c.claim.id))
      .map((c) => c.key);
    const result = await createCompanionAnswer(input, {
      authorization,
      ai: {
        run: async () => ({
          response: JSON.stringify({ status: test.expectedStatus, claimKeys: keys }),
        }),
      },
    });
    expect(result.claims.map((c) => c.id)).toEqual(test.expectedClaimIds);
    expect(result.usage.actual).toBeNull();
    expect(result.usage.neurons).toBeNull();
    expect(result.usage.reasoningTokens).toBeNull();
    expect(result.providerPromptCache.status).toBe(
      result.modelInvoked ? 'unknown' : 'not-applicable',
    );
    expect(result.providerPromptCache.cachedInputTokens).toBeNull();
    expect(result.modelVersion).toBe('provider-managed-unpinned');
    expect(result.providerReportedModelVersion).toBeNull();
    expect(result.cacheScope).toBe('private');
    expect(result.mode).toBe('reviewed-claim-selection');
    expect(result.validation.semanticGrounding).toBe('reviewed-source');
    if (test.expectedStatus === 'answer') expect(result.citations.length).toBeGreaterThan(0);
    if (test.id === 'aquila-priscilla' || test.id === 'future-activity')
      expect(result.answer).not.toContain('アポロ');
    if (test.id === 'spirit-prevents') expect(result.answer).toContain('信仰上の解釈');
    if (test.id === 'jason-bond') expect(result.answer).toContain('推測:');
  });
  it('snapshots source claims before awaiting the provider', async () => {
    const input = inputForCase(BIBLE_QUESTIONS[0]);
    const prepared = prepareCompanionRequest(input, { authorization });
    const key = eligibleClaims(prepared.retrieval.sources).find(
      (c) => c.claim.id === 'sosthenes',
    )!.key;
    let finish!: (value: unknown) => void;
    const run = vi.fn(
      () =>
        new Promise((r) => {
          finish = r;
        }),
    );
    const pending = createCompanionAnswer(input, { authorization, ai: { run } });
    await Promise.resolve();
    input.sources.find((s) => s.id === 'act-18-17')!.claims[0].text = 'MUTATED SECRET';
    finish({ response: JSON.stringify({ status: 'answer', claimKeys: [key] }) });
    expect((await pending).answer).not.toContain('MUTATED');
  });
});
describe('broader grounded generation: syntactic provenance checks, not semantic proof', () => {
  const input = inputForCase(BIBLE_QUESTIONS[0]);
  const prepared = prepareCompanionRequest(input, {
    authorization,
    answerMode: 'grounded-generation',
  });
  const claim = {
    text: 'ソステネは会堂の指導者として登場します。',
    kind: 'fact',
    sourceId: 'act-18-17',
    evidenceQuote: 'Sosthenes, the ruler of the synagogue',
  };
  const validate = (value: unknown) =>
    validateGeneratedAnswer(
      JSON.stringify(value),
      prepared.retrieval.sources,
      input.passage,
      false,
    );
  it('returns validated original Japanese prose with citations', () => {
    expect(validate({ status: 'answer', claims: [claim] }).answer).toBe(claim.text);
  });
  it('rejects invented citations, quotes, links, or raw answer fields', () => {
    for (const changed of [
      { sourceId: 'invented-source' },
      { evidenceQuote: 'invented-quote' },
      { text: 'https://evil.example' },
      { kind: 'faith' },
    ]) {
      expect(() => validate({ status: 'answer', claims: [{ ...claim, ...changed }] })).toThrow(
        'INVALID_RESPONSE',
      );
    }
    expect(() =>
      validate({ status: 'answer', claims: [claim], answer: 'free-form escape' }),
    ).toThrow('INVALID_RESPONSE');
  });
  it('rejects explicit future and cross-book references', () => {
    for (const text of ['使徒18:26では…', 'ACT 18:17-26では…', '1CO 1:1では…', '18章26節では…'])
      expect(() => validate({ status: 'answer', claims: [{ ...claim, text }] })).toThrow(
        'INVALID_RESPONSE',
      );
  });
  it('labels inference and faith instead of presenting them as fact', () => {
    const result = validate({
      status: 'answer',
      claims: [{ ...claim, kind: 'faith', tradition: '特定の信仰的読解' }],
    });
    expect(result.answer).toContain('信仰上の解釈');
  });
  it('explicitly exposes the limitation that quote validation does not prove entailment', async () => {
    const contradictory = { ...claim, text: 'ソステネはローマ皇帝です。' };
    const result = await createCompanionAnswer(input, {
      authorization,
      answerMode: 'grounded-generation',
      ai: {
        run: async () => ({
          response: JSON.stringify({ status: 'answer', claims: [contradictory] }),
        }),
      },
    });
    // Intentional limitation test: a real semantic reviewer is required before enabling this mode in production.
    expect(result.validation.semanticGrounding).toBe('unverified');
    expect(result.warnings).toContain('GENERATED_PROSE_ENTAILMENT_NOT_PROVEN');
    expect(result.warnings).toContain('PRETRAINED_SPOILERS_NOT_FULLY_DETECTABLE');
  });
});

describe('generated verse references cannot invent verses even with spoilers enabled', () => {
  const input = inputForCase(BIBLE_QUESTIONS[0]);
  const sources = prepareCompanionRequest(input, { authorization }).retrieval.sources;
  const claim = {
    kind: 'fact',
    sourceId: 'act-18-17',
    evidenceQuote: 'Sosthenes, the ruler of the synagogue',
  };
  it.each(['ACT 1:99', 'ACT 18:17-16', 'ACT 29:1', 'acts 18:99'])(
    'rejects invalid reference %s',
    (text) => {
      expect(() =>
        validateGeneratedAnswer(
          JSON.stringify({ status: 'answer', claims: [{ ...claim, text }] }),
          sources,
          input.passage,
          true,
        ),
      ).toThrow('INVALID_RESPONSE');
    },
  );
});

it('source-only reference metadata exposes translation uncertainty without requiring model approval', async () => {
  const { createSourceOnlyAnswer } = await import('../src/index.ts');
  const result = createSourceOnlyAnswer(
    { ...inputForCase(BIBLE_QUESTIONS[0]), translation: 'JCB' },
    'alice',
  );
  expect(result.modelInvoked).toBe(false);
  expect(result.answer).toContain('AIによる回答ではありません');
  expect(result.answer).not.toContain('未接続');
  expect(result.providerPromptCache).toEqual({
    status: 'not-applicable',
    basis: 'model-not-invoked',
    cachedInputTokens: null,
  });
  expect(result.usage.reasoningTokens).toBeNull();
  expect(result.referenceSystem).toMatchObject({
    canon: 'protestant-66',
    versification: 'standard-kjv',
    requestedTranslation: 'JCB',
    translationAlignment: 'unverified',
  });
  expect(result.referenceSystem.noticeJa).toContain('未検証');
});
