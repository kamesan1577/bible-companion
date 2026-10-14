import { describe, expect, it } from 'vitest';
import {
  createSourceOnlyAnswer,
  prepareCompanionRequest,
  validateSource,
  validateSelection,
  eligibleClaims,
  DEFAULT_MODEL_ID,
  validatePreparedInputCapacity,
  listModels,
} from '../src/index.ts';
import type { AnswerInput, GroundingSource } from '../src/index.ts';
import { offlineFixtureAuthorization } from '../fixtures/authorization.ts';
const source = (): GroundingSource => ({
  id: 'material:cenchreae',
  kind: 'commentary',
  title: 'ケンクレア',
  text: 'ケンクレアはコリント東側の港です。',
  book: 'ACT',
  start: { chapter: 18, verse: 18 },
  end: { chapter: 18, verse: 18 },
  spoilerEnd: { chapter: 18, verse: 18 },
  version: 'v1',
  license: 'original-commentary',
  generationAllowed: true,
  visibility: 'public',
  reviewed: true,
  url: 'https://ebible.org/engwebp/ACT18.htm',
  claims: [
    {
      id: 'summary',
      kind: 'fact',
      text: 'ケンクレアはコリント東側の港です。',
      evidenceQuote: 'ケンクレアはコリント東側の港です。',
    },
  ],
  materialProvenance: {
    kind: 'reviewed-material-summary',
    materialId: 'cenchreae',
    materialVersion: 'v1',
    materialKind: 'place',
    references: [
      {
        id: 'acts',
        title: 'Acts 18',
        url: 'https://ebible.org/engwebp/ACT18.htm',
        publisher: 'eBible',
        license: 'public-domain',
      },
      {
        id: 'geography',
        title: 'Geography',
        url: 'https://www.ascsa.edu.gr/',
        publisher: 'ASCSA',
        license: 'citation-only',
        checkedAt: '2026-10-13',
      },
    ],
  },
});
const input = (s = source()): AnswerInput => ({
  passage: { book: s.book, start: s.start, end: s.end },
  question: 'ケンクレアはどこ？',
  spoilerAllowed: false,
  sources: [s],
});
const auth = offlineFixtureAuthorization('alice', DEFAULT_MODEL_ID);
describe('reviewed original material summaries retain complete attribution', () => {
  it('preserves both references and commentary label in source-only and selected answers', () => {
    const s = source();
    validateSource(s);
    const result = createSourceOnlyAnswer(input(s), 'alice');
    expect(result.citations[0]).toMatchObject({
      sourceKind: 'commentary',
      license: 'original-commentary',
      materialProvenance: s.materialProvenance,
    });
    const prepared = prepareCompanionRequest(input(s), { authorization: auth });
    const key = eligibleClaims(prepared.retrieval.sources)[0].key;
    const selected = validateSelection(
      JSON.stringify({ status: 'answer', claimKeys: [key] }),
      prepared.retrieval.sources,
    );
    expect(selected.citations[0].materialProvenance?.references).toHaveLength(2);
    s.materialProvenance!.references[1].title = 'changed';
    expect(result.citations[0].materialProvenance?.references[1].title).toBe('Geography');
  });
  it('preserves explicit curatorial inference labeling', () => {
    const s = source();
    s.materialProvenance!.materialKind = 'artwork';
    s.claims[0].kind = 'inference';
    validateSource(s);
    expect(createSourceOnlyAnswer(input(s), 'alice').answer).toContain('推測:');
  });
  it('keeps full attribution out of prompt while retaining compact provenance', () => {
    const s = source();
    (s.claims[0] as any).privateAnnotation = 'PRIVATE_SENTINEL';
    const p = prepareCompanionRequest(input(s), { authorization: auth });
    const payload = JSON.stringify(p.messages);
    expect(payload).toContain('reviewed-material-summary');
    expect(payload).not.toContain('ASCSA');
    expect(payload).not.toContain('PRIVATE_SENTINEL');
    const r = validateSelection(
      JSON.stringify({ status: 'answer', claimKeys: [eligibleClaims(p.retrieval.sources)[0].key] }),
      p.retrieval.sources,
    );
    expect(JSON.stringify(r)).not.toContain('PRIVATE_SENTINEL');
  });
  it('excludes future summaries and their attribution before provider payload', () => {
    const q = input();
    q.passage = { book: 'ACT', start: { chapter: 18, verse: 17 }, end: { chapter: 18, verse: 17 } };
    const p = prepareCompanionRequest(q, { authorization: auth });
    expect(p.retrieval.sources).toHaveLength(0);
    expect(JSON.stringify(p.messages)).not.toContain('cenchreae');
  });
  it('rejects malformed provenance, missing licenses, version mismatches and literal mislabeling', () => {
    const changes: ((s: any) => void)[] = [
      (s) => (s.materialProvenance.materialVersion = 'v2'),
      (s) => (s.kind = 'scripture'),
      (s) => (s.reviewed = false),
      (s) => (s.license = 'public-domain'),
      (s) => (s.visibility = 'private'),
      (s) => (s.materialProvenance.extra = true),
      (s) => (s.materialProvenance.references = []),
      (s) => (s.materialProvenance.references = Array(11).fill(s.materialProvenance.references[0])),
      (s) => (s.materialProvenance.references[1].url = 'http://localhost/'),
      (s) => (s.materialProvenance.references[1].license = 'unknown'),
      (s) => (s.materialProvenance.references[1].license = 'cc-by-3.0'),
      (s) => (s.materialProvenance.references[1].extra = true),
      (s) => (s.url = 'https://www.ascsa.edu.gr/'),
      (s) => (s.claims[0].text = 'Other'),
      (s) => (s.claims[0].kind = 'faith'),
    ];
    for (const change of changes) {
      const s = source();
      change(s);
      expect(() => validateSource(s)).toThrow('INVALID_SOURCE');
    }
  });
});
describe('shared prepared input capacity', () => {
  it('checks exact context headroom for every registered model', () => {
    for (const m of listModels()) {
      const ceiling = m.contextWindowTokens - 512 - 1024;
      expect(validatePreparedInputCapacity(m.id, ceiling, 512)).toBe(ceiling);
      expect(() => validatePreparedInputCapacity(m.id, ceiling + 1, 512)).toThrow(
        'CONTEXT_TOO_LARGE',
      );
    }
  });
  it('rejects nonfinite, fractional, negative and invalid settings', () => {
    for (const n of [NaN, Infinity, -1, 1.5])
      expect(() => validatePreparedInputCapacity(DEFAULT_MODEL_ID, n, 512)).toThrow();
    expect(() => validatePreparedInputCapacity(DEFAULT_MODEL_ID, 1, 0)).toThrow();
  });
});
