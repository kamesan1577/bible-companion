import { TRUSTED_PRIMARY_TEXT_MANIFESTS } from './primary-text-manifests.ts';
import { HarnessError } from './errors.ts';
import type {
  AnswerInput,
  GroundingSource,
  Passage,
  VersePosition,
  GroundedClaim,
  HistoryTurn,
} from './types.ts';
import verseCounts from '../../core/src/verse-counts.json' with { type: 'json' };
const VERSE_COUNTS: Readonly<Record<string, readonly number[]>> = verseCounts;
export const comparePosition = (a: VersePosition, b: VersePosition) =>
  a.chapter - b.chapter || a.verse - b.verse;
export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function boundedString(value: unknown, max: number): value is string {
  return (
    typeof value === 'string' &&
    value.trim().length > 0 &&
    value.length <= max &&
    !/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value)
  );
}
function isPosition(value: unknown): value is VersePosition {
  return (
    isRecord(value) &&
    Number.isInteger(value.chapter) &&
    Number.isInteger(value.verse) &&
    (value.chapter as number) > 0 &&
    (value.chapter as number) <= 150 &&
    (value.verse as number) > 0 &&
    (value.verse as number) <= 176
  );
}
export function validatePassage(value: unknown): asserts value is Passage {
  if (
    !isRecord(value) ||
    typeof value.book !== 'string' ||
    !Object.hasOwn(VERSE_COUNTS, value.book) ||
    !isPosition(value.start) ||
    !isPosition(value.end) ||
    comparePosition(value.start, value.end) > 0 ||
    value.end.chapter > VERSE_COUNTS[value.book].length
  )
    throw new HarnessError('INVALID_INPUT');
  if (
    [value.start, value.end].some(
      (v) => v.verse > (VERSE_COUNTS[value.book as string][v.chapter - 1] ?? 0),
    )
  )
    throw new HarnessError('INVALID_INPUT');
}
/** Selection may be narrower than the reader's known range, never outside it. */
export function validateReadingBoundary(passage: Passage, boundary?: Passage): Passage {
  validatePassage(passage);
  if (boundary === undefined) return passage;
  validatePassage(boundary);
  if (
    boundary.book !== passage.book ||
    comparePosition(boundary.start, passage.start) > 0 ||
    comparePosition(boundary.end, passage.end) < 0
  ) {
    throw new HarnessError('INVALID_INPUT');
  }
  return boundary;
}
/** Conservative: no cross-book canonical-order assumption; the entire item must be bounded. */
export function withinSpoilerBoundary(
  item: { book: string; spoilerEnd: VersePosition },
  passage: Passage,
  spoilerAllowed: boolean,
): boolean {
  return (
    spoilerAllowed ||
    (item.book === passage.book && comparePosition(item.spoilerEnd, passage.end) <= 0)
  );
}
export function filterBySpoilerBoundary<
  T extends { book: string; spoilerEnd: VersePosition; reviewed: boolean },
>(items: readonly T[], passage: Passage, spoilerAllowed: boolean): T[] {
  validatePassage(passage);
  if (typeof spoilerAllowed !== 'boolean') throw new HarnessError('INVALID_INPUT');
  return items.filter((item) => {
    if (item.reviewed !== true || !isPosition(item.spoilerEnd)) return false;
    try {
      validatePassage({ book: item.book, start: item.spoilerEnd, end: item.spoilerEnd });
    } catch {
      return false;
    }
    return withinSpoilerBoundary(item, passage, spoilerAllowed);
  });
}
export function validateAnswerInput(input: AnswerInput): void {
  if (
    !isRecord(input) ||
    Object.keys(input).some(
      (k) =>
        ![
          'passage',
          'readingBoundary',
          'question',
          'spoilerAllowed',
          'sources',
          'history',
          'modelId',
          'settings',
          'translation',
          'language',
        ].includes(k),
    )
  )
    throw new HarnessError('INVALID_INPUT');
  validateReadingBoundary(input.passage, input.readingBoundary);
  if (
    !boundedString(input.question, 2000) ||
    typeof input.spoilerAllowed !== 'boolean' ||
    !Array.isArray(input.sources) ||
    input.sources.length > 64 ||
    (input.translation !== undefined && !boundedString(input.translation, 64)) ||
    (input.language !== undefined && input.language !== 'ja')
  )
    throw new HarnessError('INVALID_INPUT');
  if (
    input.history !== undefined &&
    (!Array.isArray(input.history) ||
      input.history.length > 20 ||
      input.history.some(
        (h) =>
          !isRecord(h) ||
          !['user', 'assistant'].includes(h.role as string) ||
          !boundedString(h.content, 4000),
      ))
  )
    throw new HarnessError('INVALID_INPUT');
}
/** Server provenance plus a pinned manifest identity, not editorial review or translation equivalence.
 * This does not replace ingestion's immutable-row/content-integrity checks. */
export function isTrustedPrimaryTextSource(source: unknown): source is GroundingSource {
  try {
    validateSource(source);
  } catch {
    return false;
  }
  const v = source.verification;
  return (
    source.reviewed === false &&
    v?.referenceAlignment === 'canonical-compatible' &&
    TRUSTED_PRIMARY_TEXT_MANIFESTS.some(
      (m) =>
        m.corpusId === v.corpusId &&
        m.edition === v.edition &&
        m.manifestSha256 === v.manifestSha256 &&
        m.sourceVersion === source.version &&
        m.language === v.language &&
        m.referenceSystem === v.referenceSystem,
    )
  );
}
function publicReferenceUrl(value: unknown): boolean {
  if (!boundedString(value, 2000)) return false;
  try {
    const url = new URL(value);
    return (
      url.protocol === 'https:' &&
      !url.username &&
      !url.password &&
      !url.port &&
      /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$/i.test(url.hostname) &&
      !/\.(?:localhost|local|internal|test|invalid|example)$/i.test(url.hostname)
    );
  } catch {
    return false;
  }
}
function validMaterialReference(value: unknown): boolean {
  if (!isRecord(value)) return false;
  return (
    !Object.keys(value).some(
      (key) =>
        ![
          'id',
          'title',
          'url',
          'publisher',
          'license',
          'licenseUrl',
          'attribution',
          'checkedAt',
        ].includes(key),
    ) &&
    boundedString(value.id, 100) &&
    boundedString(value.title, 1000) &&
    boundedString(value.publisher, 1000) &&
    publicReferenceUrl(value.url) &&
    ['public-domain', 'original-commentary', 'citation-only', 'cc-by-3.0', 'odbl-1.0'].includes(
      value.license as string,
    ) &&
    (value.licenseUrl === undefined || publicReferenceUrl(value.licenseUrl)) &&
    (value.attribution === undefined || boundedString(value.attribution, 1000)) &&
    (value.checkedAt === undefined ||
      (typeof value.checkedAt === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value.checkedAt))) &&
    (!['cc-by-3.0', 'odbl-1.0'].includes(value.license as string) ||
      (value.licenseUrl !== undefined && value.attribution !== undefined))
  );
}
export function validateSource(value: unknown): asserts value is GroundingSource {
  if (!isRecord(value)) throw new HarnessError('INVALID_SOURCE');
  try {
    validatePassage(value);
  } catch {
    throw new HarnessError('INVALID_SOURCE');
  }
  if (
    !boundedString(value.id, 100) ||
    !/^[a-zA-Z0-9][a-zA-Z0-9_.:-]*$/.test(value.id) ||
    !boundedString(value.title, 200) ||
    !boundedString(value.text, 16000) ||
    !boundedString(value.version, 100) ||
    !['scripture', 'commentary'].includes(value.kind as string) ||
    !['public-domain', 'licensed', 'user-provided', 'original-commentary'].includes(
      value.license as string,
    ) ||
    !['public', 'private'].includes(value.visibility as string) ||
    typeof value.reviewed !== 'boolean' ||
    typeof value.generationAllowed !== 'boolean' ||
    !isPosition(value.spoilerEnd) ||
    comparePosition(value.spoilerEnd, value.end as VersePosition) < 0 ||
    !Array.isArray(value.claims) ||
    value.claims.length > 16
  )
    throw new HarnessError('INVALID_SOURCE');
  try {
    validatePassage({ book: value.book, start: value.start, end: value.spoilerEnd });
  } catch {
    throw new HarnessError('INVALID_SOURCE');
  }
  if (value.visibility === 'private' && !boundedString(value.ownerId, 200))
    throw new HarnessError('INVALID_SOURCE');
  if (value.license === 'user-provided' && value.visibility !== 'private')
    throw new HarnessError('INVALID_SOURCE');
  if (value.url !== undefined) {
    if (!boundedString(value.url, 2000)) throw new HarnessError('INVALID_SOURCE');
    let url: URL;
    try {
      url = new URL(value.url);
    } catch {
      throw new HarnessError('INVALID_SOURCE');
    }
    if (
      url.protocol !== 'https:' ||
      url.username ||
      url.password ||
      url.port ||
      !url.hostname.includes('.') ||
      /^\d+\./.test(url.hostname) ||
      /[\[\]]/.test(url.hostname) ||
      /\.(localhost|local|internal)$/.test(url.hostname)
    )
      throw new HarnessError('INVALID_SOURCE');
  }
  if (value.verification !== undefined) {
    const v = value.verification;
    if (
      !isRecord(v) ||
      Object.keys(v).some(
        (key) =>
          ![
            'kind',
            'corpusId',
            'edition',
            'language',
            'manifestSha256',
            'referenceSystem',
            'referenceAlignment',
          ].includes(key),
      ) ||
      v.kind !== 'trusted-primary-text' ||
      !boundedString(v.corpusId, 100) ||
      !/^[a-zA-Z0-9][a-zA-Z0-9_.:-]*$/.test(v.corpusId) ||
      !boundedString(v.edition, 100) ||
      v.language !== 'en' ||
      typeof v.manifestSha256 !== 'string' ||
      !/^[a-f0-9]{64}$/.test(v.manifestSha256) ||
      v.referenceSystem !== 'web-protestant' ||
      !['canonical-compatible', 'unverified', 'unsupported'].includes(
        v.referenceAlignment as string,
      ) ||
      value.reviewed !== false ||
      value.kind !== 'scripture' ||
      value.license !== 'public-domain' ||
      value.visibility !== 'public' ||
      value.claims.length !== 0 ||
      comparePosition(value.start as VersePosition, value.end as VersePosition) !== 0 ||
      comparePosition(value.end as VersePosition, value.spoilerEnd as VersePosition) !== 0
    )
      throw new HarnessError('INVALID_SOURCE');
  }
  if (value.materialProvenance !== undefined) {
    const p = value.materialProvenance,
      claim = value.claims[0];
    if (
      !isRecord(p) ||
      Object.keys(p).some(
        (key) =>
          !['kind', 'materialId', 'materialVersion', 'materialKind', 'references'].includes(key),
      ) ||
      p.kind !== 'reviewed-material-summary' ||
      !boundedString(p.materialId, 100) ||
      !/^[a-zA-Z0-9][a-zA-Z0-9_.:-]*$/.test(p.materialId) ||
      !boundedString(p.materialVersion, 100) ||
      p.materialVersion !== value.version ||
      !Array.isArray(p.references) ||
      p.references.length < 1 ||
      p.references.length > 10 ||
      !p.references.every(validMaterialReference) ||
      new Set(p.references.map((r: any) => r.id)).size !== p.references.length ||
      value.url !== p.references[0]?.url ||
      !['person', 'place', 'artwork'].includes(p.materialKind as string) ||
      value.kind !== 'commentary' ||
      value.reviewed !== true ||
      value.license !== 'original-commentary' ||
      value.visibility !== 'public' ||
      value.verification !== undefined ||
      value.url === undefined ||
      value.claims.length !== 1 ||
      !isRecord(claim) ||
      !['fact', 'inference'].includes(claim.kind as string) ||
      claim.text !== value.text ||
      claim.evidenceQuote !== value.text ||
      claim.tradition !== undefined
    )
      throw new HarnessError('INVALID_SOURCE');
  }
  const ids = new Set<string>();
  for (const claim of value.claims) {
    if (
      !isRecord(claim) ||
      !boundedString(claim.id, 100) ||
      !/^[a-zA-Z0-9][a-zA-Z0-9_.:-]*$/.test(claim.id) ||
      ids.has(claim.id) ||
      !boundedString(claim.text, 500) ||
      !['fact', 'inference', 'faith'].includes(claim.kind as string) ||
      !boundedString(claim.evidenceQuote, 500) ||
      !(value.text as string).includes(claim.evidenceQuote) ||
      (claim.kind === 'faith' && !boundedString(claim.tradition, 100)) ||
      (claim.tradition !== undefined && !boundedString(claim.tradition, 100))
    )
      throw new HarnessError('INVALID_SOURCE');
    ids.add(claim.id);
  }
}
export interface RetrievalResult {
  sources: GroundingSource[];
  excluded: {
    unreviewed: number;
    rights: number;
    privacy: number;
    boundary: number;
    contextLimit: number;
  };
}
/** Call before prompt construction. No excluded content or private metadata enters the provider request. */
export function retrieveGrounding(input: AnswerInput, ownerId: string): RetrievalResult {
  validateAnswerInput(input);
  if (!boundedString(ownerId, 200)) throw new HarnessError('INVALID_INPUT');
  const excluded = { unreviewed: 0, rights: 0, privacy: 0, boundary: 0, contextLimit: 0 };
  const sources: GroundingSource[] = [];
  const candidates: GroundingSource[] = [];
  const ids = new Set<string>();
  let totalBytes = 0;
  const boundary = validateReadingBoundary(input.passage, input.readingBoundary);
  for (const source of input.sources) {
    validateSource(source);
    if (ids.has(source.id)) throw new HarnessError('INVALID_SOURCE');
    ids.add(source.id);
    if (source.visibility === 'private' && source.ownerId !== ownerId) {
      excluded.privacy++;
      continue;
    }
    if (!source.reviewed && !isTrustedPrimaryTextSource(source)) {
      excluded.unreviewed++;
      continue;
    }
    if (!source.generationAllowed) {
      excluded.rights++;
      continue;
    }
    if (!withinSpoilerBoundary(source, boundary, input.spoilerAllowed)) {
      excluded.boundary++;
      continue;
    }
    candidates.push(source);
  }
  // Prefer selected-range material before older background chunks consume the bounded context.
  const overlaps = (source: GroundingSource) =>
    source.book === input.passage.book &&
    comparePosition(source.end, input.passage.start) >= 0 &&
    comparePosition(source.start, input.passage.end) <= 0
      ? 1
      : 0;
  candidates.sort(
    (a, b) =>
      overlaps(b) - overlaps(a) ||
      Number(b.reviewed && b.claims.length > 0) - Number(a.reviewed && a.claims.length > 0) ||
      (a.book === input.passage.book ? 0 : 1) - (b.book === input.passage.book ? 0 : 1) ||
      Math.abs(a.end.chapter - input.passage.end.chapter) -
        Math.abs(b.end.chapter - input.passage.end.chapter) ||
      Math.abs(a.end.verse - input.passage.end.verse) -
        Math.abs(b.end.verse - input.passage.end.verse) ||
      (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
  );
  for (const source of candidates) {
    const bytes = new TextEncoder().encode(JSON.stringify(source)).byteLength;
    if (sources.length >= 16 || totalBytes + bytes > 20000) {
      excluded.contextLimit++;
      continue;
    }
    totalBytes += bytes;
    // Snapshot trusted inputs so mutation during asynchronous inference cannot expand the allowlist.
    sources.push(structuredClone(source));
  }
  return { sources, excluded };
}
export interface EligibleClaim {
  key: string;
  source: GroundingSource;
  claim: GroundedClaim;
}
export function eligibleClaims(sources: readonly GroundingSource[]): EligibleClaim[] {
  return sources.flatMap((source, index) =>
    source.claims.map((claim, claimIndex) => ({ key: `s${index}c${claimIndex}`, source, claim })),
  );
}

/** Replay only server-tagged turns safe under the current source set and boundary. */
export function scopedHistory(
  input: AnswerInput,
  sources: readonly GroundingSource[],
  ownerId: string,
): HistoryTurn[] {
  const sourceIds = new Set(sources.map((s) => s.id));
  const versions = new Map(sources.map((s) => [s.id, s.version]));
  const eligible = (input.history ?? [])
    .filter((turn) => {
      if (
        turn.ownerId !== ownerId ||
        !turn.scope ||
        !isRecord(turn.scope) ||
        typeof turn.scope.spoilerAllowed !== 'boolean' ||
        !Array.isArray(turn.scope.sourceIds) ||
        turn.scope.sourceIds.length > 16 ||
        turn.scope.sourceIds.some((id) => typeof id !== 'string' || !sourceIds.has(id)) ||
        (turn.role === 'assistant' && turn.scope.sourceIds.length === 0) ||
        (turn.scope.sourceIds.length > 0 &&
          (!isRecord(turn.scope.sourceVersions) ||
            turn.scope.sourceIds.some(
              (id) => turn.scope!.sourceVersions![id] !== versions.get(id),
            )))
      )
        return false;
      let historyBoundary: Passage;
      try {
        historyBoundary = validateReadingBoundary(turn.scope.passage, turn.scope.readingBoundary);
      } catch {
        return false;
      }
      if (turn.scope.passage.book !== input.passage.book) return false;
      return (
        input.spoilerAllowed ||
        (!turn.scope.spoilerAllowed &&
          comparePosition(historyBoundary.end, (input.readingBoundary ?? input.passage).end) <= 0)
      );
    })
    .slice(-6);
  const result: HistoryTurn[] = [];
  let characters = 0;
  for (const turn of eligible.reverse()) {
    if (turn.content.length > 1500 || characters + turn.content.length > 4000) continue;
    const scope = turn.scope!;
    // Copy only allowed provenance fields. Do not forward extra DB metadata or unrelated version-map entries.
    result.unshift({
      role: turn.role,
      content: turn.content,
      ownerId: turn.ownerId,
      scope: {
        passage: structuredClone(scope.passage),
        ...(scope.readingBoundary
          ? { readingBoundary: structuredClone(scope.readingBoundary) }
          : {}),
        spoilerAllowed: scope.spoilerAllowed,
        sourceIds: [...scope.sourceIds],
        sourceVersions: Object.fromEntries(scope.sourceIds.map((id) => [id, versions.get(id)!])),
      },
    });
    characters += turn.content.length;
  }
  return result;
}
