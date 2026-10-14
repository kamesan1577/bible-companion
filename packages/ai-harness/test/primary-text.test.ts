import { describe, it, expect, vi } from 'vitest';
import {
  TRUSTED_PRIMARY_TEXT_MANIFESTS,
  isTrustedPrimaryCorpus,
  isTrustedPrimaryTextSource,
  validateSource,
  retrieveGrounding,
  createSourceOnlyAnswer,
  createCompanionAnswer,
  prepareCompanionRequest,
  DEFAULT_MODEL_ID,
  type GroundingSource,
  type AnswerInput,
} from '../src/index.ts';
import { ACTS_SOURCES } from '../fixtures/acts-sources.ts';
import { offlineFixtureAuthorization } from '../fixtures/authorization.ts';
// Synthetic source objects test the harness contract. Artifact/content integrity is tested by ingestion.
function source(): GroundingSource {
  const manifest = TRUSTED_PRIMARY_TEXT_MANIFESTS[0];
  if (!manifest)
    throw new Error('Real pinned official corpus manifest required for these contract tests');
  return {
    ...structuredClone(ACTS_SOURCES.find((s) => s.id === 'act-18-17')!),
    id: 'webp:ACT:18:17',
    version: manifest.sourceVersion,
    reviewed: false,
    claims: [],
    verification: {
      kind: 'trusted-primary-text',
      corpusId: manifest.corpusId,
      edition: manifest.edition,
      language: manifest.language,
      manifestSha256: manifest.manifestSha256,
      referenceSystem: manifest.referenceSystem,
      referenceAlignment: 'canonical-compatible',
    },
  };
}
function input(s = source()): AnswerInput {
  return {
    passage: { book: s.book, start: s.start, end: s.end },
    question: 'この箇所を説明して',
    spoilerAllowed: false,
    sources: [s],
  };
}
describe('trusted literal primary text is distinct from editorial interpretation', () => {
  it('renders literal English source text with provenance, no invented claims and no model call', () => {
    const s = source();
    expect(isTrustedPrimaryCorpus({ ...s.verification!, sourceVersion: s.version })).toBe(true);
    expect(isTrustedPrimaryTextSource(s)).toBe(true);
    const answer = createSourceOnlyAnswer(input(s), 'owner');
    expect(answer.answer).toContain(s.text);
    expect(answer.answer).toContain('英語・WEB');
    expect(answer.answer).toContain('JCB本文ではありません');
    expect(answer.claims).toEqual([]);
    expect(answer.modelInvoked).toBe(false);
    expect(answer.validation.semanticGrounding).toBe('literal-source-excerpt');
    expect(answer.citations[0].verification).toEqual(s.verification);
    expect(s.reviewed).toBe(false);
  });
  it('does not promote primary text into reviewed-claim generation', async () => {
    const run = vi.fn();
    const result = await createCompanionAnswer(input(), {
      authorization: offlineFixtureAuthorization('owner', DEFAULT_MODEL_ID),
      ai: { run },
    });
    expect(result.status).toBe('insufficient-evidence');
    expect(result.modelInvoked).toBe(false);
    expect(run).not.toHaveBeenCalled();
  });
  it('requires exact pinned corpus, edition, manifest and source version', () => {
    for (const patch of [
      { corpusId: 'unknown' },
      { edition: 'JCB' },
      { manifestSha256: '0'.repeat(64) },
      { referenceAlignment: 'unverified' as const },
    ]) {
      const s = source();
      s.verification = { ...s.verification!, ...patch };
      expect(isTrustedPrimaryTextSource(s)).toBe(false);
      expect(retrieveGrounding(input(s), 'owner').sources).toEqual([]);
    }
    const stale = source();
    stale.version += '-changed';
    expect(isTrustedPrimaryTextSource(stale)).toBe(false);
    expect(retrieveGrounding(input(stale), 'owner').sources).toEqual([]);
  });
  it('rejects primary markers attached to interpretations, private content, or multi-verse chunks', () => {
    for (const patch of [
      { reviewed: true },
      { kind: 'commentary' },
      { visibility: 'private', ownerId: 'owner' },
      { end: { chapter: 18, verse: 18 }, spoilerEnd: { chapter: 18, verse: 18 } },
      { claims: [{ id: 'invented', text: '解釈', kind: 'fact', evidenceQuote: 'Sosthenes' }] },
    ]) {
      const malformed = { ...source(), ...patch };
      expect(() => validateSource(malformed)).toThrow('INVALID_SOURCE');
      expect(isTrustedPrimaryTextSource(malformed)).toBe(false);
    }
  });
  it('excludes future primary text before prompt construction and retains provenance for eligible text', () => {
    const s = source(),
      future = {
        ...source(),
        id: 'webp:ACT:18:26',
        start: { chapter: 18, verse: 26 },
        end: { chapter: 18, verse: 26 },
        spoilerEnd: { chapter: 18, verse: 26 },
        text: 'FUTURE_SENTINEL',
      };
    const prepared = prepareCompanionRequest(
      { ...input(s), sources: [s, future] },
      {
        authorization: { ownerId: 'owner', connectedModelIds: [] },
        answerMode: 'grounded-generation',
      },
    );
    expect(JSON.stringify(prepared.messages)).not.toContain('FUTURE_SENTINEL');
    expect(JSON.stringify(prepared.messages)).toContain('canonical-compatible');
    expect(prepared.retrieval.sources).toHaveLength(1);
  });
});
