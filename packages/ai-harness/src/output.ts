import { BOOK_REFERENCE_ALIASES, normalizeBook } from '../../core/src/index.ts';
import { HarnessError } from './errors.ts';
import { eligibleClaims, isRecord, comparePosition, validatePassage } from './grounding.ts';
import type { AnswerClaim, Citation, GroundingSource, Passage, AnswerResult } from './types.ts';
const fail = (): never => {
  throw new HarnessError('INVALID_RESPONSE', true);
};
export interface ValidatedAnswer {
  status: AnswerResult['status'];
  claims: AnswerClaim[];
  citations: Citation[];
  answer: string;
}
function parseObject(raw: string): Record<string, unknown> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return fail();
  }
  if (!isRecord(parsed)) return fail();
  return parsed;
}
function statusOf(value: unknown): AnswerResult['status'] {
  if (value === 'answer') return 'answered';
  if (value === 'insufficient') return 'insufficient-evidence';
  if (value === 'spoiler') return 'spoiler-boundary';
  return fail();
}
/** Call with an already validated, retrieval-eligible source. */
export function citationForSource(source: GroundingSource): Citation {
  return {
    sourceId: source.id,
    sourceKind: source.kind,
    ...(source.materialProvenance
      ? {
          materialProvenance: {
            ...source.materialProvenance,
            references: source.materialProvenance.references.map((reference) => ({ ...reference })),
          },
        }
      : {}),
    title: source.title,
    ...(source.url ? { url: source.url } : {}),
    passage: { book: source.book, start: { ...source.start }, end: { ...source.end } },
    version: source.version,
    license: source.license,
    ...(source.verification ? { verification: { ...source.verification } } : {}),
  };
}
function render(
  status: AnswerResult['status'],
  claims: AnswerClaim[],
  sources: readonly GroundingSource[],
): ValidatedAnswer {
  const citations = [...new Set(claims.map((c) => c.sourceId))].map((id) =>
    citationForSource(sources.find((s) => s.id === id)!),
  );
  const answer =
    status === 'insufficient-evidence'
      ? 'この範囲の確認済み資料だけでは、答えを確かめられません。'
      : status === 'spoiler-boundary'
        ? '今のネタバレ境界を越える情報が必要です。設定を変えない限り、先の内容は表示しません。'
        : claims
            .map(
              (claim) =>
                `${claim.kind === 'inference' ? '推測: ' : claim.kind === 'faith' ? `信仰上の解釈（${claim.tradition}）: ` : ''}${claim.text}`,
            )
            .join('\n');
  return { status, claims, citations, answer };
}
export function validateSelection(
  raw: string,
  sources: readonly GroundingSource[],
): ValidatedAnswer {
  const object = parseObject(raw);
  if (
    Object.keys(object).some((key) => !['status', 'claimKeys'].includes(key)) ||
    !Array.isArray(object.claimKeys) ||
    object.claimKeys.length > 3 ||
    new Set(object.claimKeys).size !== object.claimKeys.length
  )
    return fail();
  const status = statusOf(object.status);
  if ((status === 'answered') !== object.claimKeys.length > 0) return fail();
  const allowed = new Map(eligibleClaims(sources).map((c) => [c.key, c]));
  const claims = object.claimKeys.map((key): AnswerClaim => {
    if (typeof key !== 'string' || !allowed.has(key)) return fail();
    const { source, claim } = allowed.get(key)!;
    return {
      id: claim.id,
      text: claim.text,
      kind: claim.kind,
      evidenceQuote: claim.evidenceQuote,
      ...(claim.tradition ? { tradition: claim.tradition } : {}),
      sourceId: source.id,
    };
  });
  return render(status, claims, sources);
}
// Use the same aliases as shared Bible imports. Spaces and abbreviation dots are
// normalized by normalizeBook; longest-first matching keeps numbered books intact.
const bookReferencePattern = BOOK_REFERENCE_ALIASES.map((alias) =>
  [...alias].map((character) => character.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('[\\s.]*'),
).join('|');
// Consume whole numeric runs: a digit cap can truncate a verse or detach its book.
const explicitReferencePattern = new RegExp(
  `(?:(?<![a-z0-9])(${bookReferencePattern})[\\s.]*[（(「『【\\[]?\\s*)?` +
    '(\\d+)\\s*[:：章]\\s*(\\d+)(?:節)?' +
    '(?:\\s*[-–—〜～]\\s*(?:(\\d+)\\s*[:：章]\\s*)?(\\d+))?',
  'gi',
);
/** A syntactic reference check, never a claim of semantic spoiler prevention. */
export function assertReferencesWithinBoundary(
  text: string,
  passage: Passage,
  spoilerAllowed: boolean,
): void {
  for (const match of text.normalize('NFKC').matchAll(explicitReferencePattern)) {
    const rawBook = match[1];
    const book = rawBook ? (normalizeBook(rawBook) ?? rawBook.toUpperCase()) : passage.book;
    const start = { chapter: Number(match[2]), verse: Number(match[3]) };
    const end = { chapter: Number(match[4] ?? match[2]), verse: Number(match[5] ?? match[3]) };
    try {
      validatePassage({ book, start, end });
    } catch {
      return fail();
    }
    if (
      !spoilerAllowed &&
      (book !== passage.book ||
        comparePosition(start, passage.end) > 0 ||
        comparePosition(end, passage.end) > 0)
    )
      return fail();
  }
}
/** Validates provenance links and exact quotes; truth/entailment requires an independent reviewer. */
export function validateGeneratedAnswer(
  raw: string,
  sources: readonly GroundingSource[],
  passage: Passage,
  spoilerAllowed: boolean,
): ValidatedAnswer {
  const object = parseObject(raw);
  if (
    Object.keys(object).some((key) => !['status', 'claims'].includes(key)) ||
    !Array.isArray(object.claims) ||
    object.claims.length > 3
  )
    return fail();
  const status = statusOf(object.status);
  if ((status === 'answered') !== object.claims.length > 0) return fail();
  const claims = object.claims.map((claim, index): AnswerClaim => {
    if (
      !isRecord(claim) ||
      Object.keys(claim).some(
        (k) => !['text', 'kind', 'sourceId', 'evidenceQuote', 'tradition'].includes(k),
      ) ||
      typeof claim.text !== 'string' ||
      !claim.text.trim() ||
      claim.text.length > 300 ||
      !['fact', 'inference', 'faith'].includes(claim.kind as string) ||
      typeof claim.sourceId !== 'string' ||
      typeof claim.evidenceQuote !== 'string' ||
      claim.evidenceQuote.trim().length < 4 ||
      claim.evidenceQuote.length > 500 ||
      /(?:https?:\/\/|<\/?(?:think|analysis|script)|```)/i.test(claim.text)
    )
      return fail();
    const source = sources.find((source) => source.id === claim.sourceId);
    if (!source || !source.text.includes(claim.evidenceQuote)) return fail();
    if (
      (claim.kind === 'faith' || claim.tradition !== undefined) &&
      (typeof claim.tradition !== 'string' ||
        !claim.tradition.trim() ||
        claim.tradition.length > 100)
    )
      return fail();
    assertReferencesWithinBoundary(claim.text, passage, spoilerAllowed);
    if (typeof claim.tradition === 'string') {
      if (/(?:https?:\/\/|<\/?(?:think|analysis|script)|```)/i.test(claim.tradition)) return fail();
      assertReferencesWithinBoundary(claim.tradition, passage, spoilerAllowed);
    }
    return {
      id: `generated-${index}`,
      text: claim.text,
      kind: claim.kind as AnswerClaim['kind'],
      sourceId: source.id,
      evidenceQuote: claim.evidenceQuote,
      ...(typeof claim.tradition === 'string' ? { tradition: claim.tradition } : {}),
    };
  });
  return render(status, claims, sources);
}
export function insufficientAnswer(boundaryExcluded = false): ValidatedAnswer {
  return render(boundaryExcluded ? 'spoiler-boundary' : 'insufficient-evidence', [], []);
}

/** General knowledge has no invented provenance; cited claims still use strict validation. */
export function validateGeneralAnswer(raw: string, sources: readonly GroundingSource[], passage: Passage, spoilerAllowed: boolean): ValidatedAnswer {
  const object = parseObject(raw);
  if (Object.keys(object).some(key => !['status','claims','generalText'].includes(key)) || !Array.isArray(object.claims)) return fail();
  const general = object.generalText;
  if (general !== undefined && (typeof general !== 'string' || general.length > 600 || /https?:\/\/|<[^>]*>/.test(general))) return fail();
  const text = typeof general === 'string' ? general.trim() : '';
  if (text && object.status !== 'answer') return fail();
  if (text) assertReferencesWithinBoundary(text, passage, spoilerAllowed);
  const validated = validateGeneratedAnswer(JSON.stringify({status: object.claims.length ? object.status : (text ? 'insufficient' : object.status), claims: object.claims}), sources, passage, spoilerAllowed);
  if (!text) return validated;
  return {...validated, status:'answered', answer:text};
}
