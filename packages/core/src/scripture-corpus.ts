import { SaxesParser } from 'saxes';
import verseCounts from './verse-counts.json' with { type: 'json' };

export const WEBP_SOURCE = {
  id: 'webp',
  edition: 'engwebp',
  referenceSystem: 'web-protestant',
  title: 'World English Bible, Protestant selection (engwebp)',
  sourceURL: 'https://ebible.org/Scriptures/engwebp_usfx.zip',
  licenseURL: 'https://ebible.org/details.php?id=engwebp',
  license: 'public-domain',
  language: 'en',
  archiveMember: 'engwebp_usfx.xml',
} as const;

/** An observed snapshot, not a claim that eBible's mutable download never changes. */
export const WEBP_PINNED_SNAPSHOT = {
  version: 'webp-usfx-2026-10-13-35a6adf626e5',
  fetchedAt: '2026-10-13T18:55:08.167Z',
  archiveSha256: '35a6adf626e563573fdbfb7c89ac8b1d7c5a11df30b54d2566aca7b1f23ec6dc',
  xmlSha256: '61e697d234b92af31edca8804d2041a7f5e68136779573fb3bcfeff7e9cbce58',
  manifestSha256: 'd2f923bc56cb6e2e77f0f5a3e9cbd6a29f7a3028a3db011e0be8cad4f591449e',
} as const;

export type ScriptureCoordinate = { book: string; chapter: number; verse: number };
export type SourceCoordinate = { sourceBook: string; sourceChapter: number; sourceVerse: string };
export type ScriptureVerse = SourceCoordinate & {
  sourceId: 'webp';
  version: string;
  text: string;
  canonical: ScriptureCoordinate | null;
  alignment: 'canonical-compatible' | 'unsupported';
  textStatus: 'present' | 'empty';
  verification: 'literal-source';
  editorialReview: 'unreviewed';
};
export type UnversifiedScripture = {
  sourceId: 'webp';
  version: string;
  sourceBook: string;
  sourceChapter: number;
  marker: 'd';
  afterSourceVerse: string | null;
  text: string;
  verification: 'literal-source';
  editorialReview: 'unreviewed';
};
export type ScriptureBookCounts = {
  book: string;
  chapterCount: number;
  verseCount: number;
  nonemptyVerseCount: number;
  canonicalCompatibleVerseCount: number;
  unsupportedVerseCount: number;
};
export type ScriptureParseResult = {
  verses: ScriptureVerse[];
  unversified: UnversifiedScripture[];
  books: ScriptureBookCounts[];
  excludedBooks: { book: string; verseMarkerCount: number }[];
  unsupportedVerses: SourceCoordinate[];
  emptyVerses: SourceCoordinate[];
  missingCanonicalVerses: ScriptureCoordinate[];
  excludedElementCounts: Record<string, number>;
};
export type ScriptureProvenance = {
  version: string;
  fetchedAt: string;
  archiveSha256: string;
  /** Independently expected digest of the uncompressed original UTF-8 XML bytes. */
  xmlSha256: string;
};
export type ScriptureManifest = {
  schemaVersion: 1;
  corpusId: 'webp';
  edition: 'engwebp';
  referenceSystem: 'web-protestant';
  sourceId: 'webp';
  title: string;
  sourceURL: string;
  licenseURL: string;
  license: 'public-domain';
  language: 'en';
  version: string;
  fetchedAt: string;
  hash: { algorithm: 'sha256'; archive: string; xml: string; verses: string; unversified: string };
  archiveMember: string;
  parserVersion: 'webp-usfx/1';
  bookCount: number;
  verseCount: number;
  nonemptyVerseCount: number;
  canonicalCompatibleVerseCount: number;
  unsupportedVerseCount: number;
  unversifiedSectionCount: number;
  books: ScriptureBookCounts[];
  excludedBooks: ScriptureParseResult['excludedBooks'];
  unsupportedVerses: SourceCoordinate[];
  emptyVerses: SourceCoordinate[];
  missingCanonicalVerses: ScriptureCoordinate[];
  excludedElementCounts: Record<string, number>;
  parsingPolicy: typeof SCRIPTURE_PARSING_POLICY;
  verification: {
    sourceText: 'xml-sha256-verified';
    editorialReview: 'unreviewed';
    humanTextReview: false;
  };
};

export const SCRIPTURE_PARSING_POLICY = {
  canon: 'Select only the 66 book IDs in verse-counts.json; report every excluded source book.',
  text: 'Retain decoded primary-text characters and punctuation verbatim. Remove XML formatting, notes, references, introductions, editorial headings and speaker labels.',
  whitespace:
    'Collapse ASCII space, tab, CR and LF runs to one space; trim those characters at ends. Paragraph/poetry/blank-line boundaries contribute one space. No Unicode normalization or punctuation changes.',
  coordinates:
    'Preserve source book/chapter/verse labels. canonical-compatible means numeric coordinates exist in standardKJV metadata only; it does not establish textual or semantic alignment. Never remap, split, merge, renumber or synthesize verses.',
  empty:
    'Preserve empty-primary verse markers as empty text and report them; never replace with footnotes or another translation.',
  superscriptions:
    'Preserve d-marked Psalm superscriptions and acrostic labels separately as unversified source sections, anchored after the preceding source verse label or at chapter start. Never append them to verse 1 or invent verse 0.',
  security:
    'Reject DTDs, processing instructions, unknown selected-book markup, malformed XML, duplicate/ambiguous markers, excessive size/depth and unassigned primary text. Never load schemas or resolve external entities.',
  review:
    'Literal-source extraction and byte-hash verification are not editorial, theological, translation or Japanese commentary review.',
} as const;

const canonicalCounts: Record<string, number[]> = verseCounts;
const canonicalBookOrder = Object.keys(canonicalCounts);
const MAX_XML_BYTES = 64 * 1024 * 1024;
const MAX_DEPTH = 64;
const MAX_TEXT_CHARS = 100_000;
const MAX_VERSES = 50_000;
const excludedTags = new Set([
  'id',
  'ide',
  'h',
  'toc',
  'cl',
  'cp',
  's',
  'f',
  'x',
  'ref',
  'fig',
  'rem',
  'va',
  'vp',
  'ca',
]);
const inlineTags = new Set([
  'w',
  'wj',
  'qs',
  'k',
  'bk',
  'add',
  'nd',
  'it',
  'bd',
  'bdit',
  'em',
  'sc',
  'sup',
  'qt',
  'tl',
  'pn',
  'ord',
  'sig',
  'sls',
]);
const annotationTags = new Set([
  'fr',
  'ft',
  'fk',
  'fq',
  'fqa',
  'fl',
  'fp',
  'fv',
  'fdc',
  'xo',
  'xt',
  'xk',
  'xq',
  'xot',
  'xnt',
  'xdc',
  'wh',
]);
const paragraphStyles = /^(?:p|m|po|pr|cls|pmo|pm|pmc|pmr|pi[0-9]*|mi|nb|pc|ph[0-9]*|li[0-9]*)$/;
const excludedStyles =
  /^(?:imt[0-9]*|is[0-9]*|ip|ipi|im|imi|ipq|imq|ipr|iq[0-9]*|ib|ili[0-9]*|iot|io[0-9]*|iex|imte[0-9]*|ie|mt[0-9]*|mte[0-9]*|ms[0-9]*|mr|s[0-9]*|sr|r|sp|sd[0-9]*)$/;
const normalizeWhitespace = (text: string) =>
  text.replace(/[ \t\r\n]+/g, ' ').replace(/^ +| +$/g, '');
const sourceCoordinate = (v: SourceCoordinate): SourceCoordinate => ({
  sourceBook: v.sourceBook,
  sourceChapter: v.sourceChapter,
  sourceVerse: v.sourceVerse,
});

/** A strict, bounded reader for the publisher's USFX profile, not a generic XML/USFM importer. */
export function parseWebpUsfx(
  xml: string,
  options: { requireAll66Books?: boolean; version?: string } = {},
): ScriptureParseResult {
  if (new TextEncoder().encode(xml).byteLength > MAX_XML_BYTES)
    throw new Error('USFX exceeds the 64 MiB limit');
  if (/<!DOCTYPE|<!ENTITY/i.test(xml)) throw new Error('DTD/entity declarations are forbidden');
  const version = options.version ?? WEBP_PINNED_SNAPSHOT.version;
  const result: ScriptureParseResult = {
    verses: [],
    unversified: [],
    books: [],
    excludedBooks: [],
    unsupportedVerses: [],
    emptyVerses: [],
    missingCanonicalVerses: [],
    excludedElementCounts: {},
  };
  const seenBooks = new Set<string>();
  const seenVerses = new Set<string>();
  const chapterSets = new Map<string, Set<number>>();
  const stack: { name: string; suppressed: boolean; block: boolean }[] = [];
  let book = '';
  let chapter = 0;
  let lastVerseLabel: string | null = null;
  let selected = false;
  let active: { label: string; text: string } | null = null;
  let superscription: { text: string; depth: number; afterSourceVerse: string | null } | null =
    null;
  let excludedBook: { book: string; verseMarkerCount: number } | null = null;
  let markerCount = 0;
  const append = (text: string) => {
    if (superscription) {
      superscription.text += text;
      if (superscription.text.length > MAX_TEXT_CHARS) throw new Error('Superscription too long');
    } else if (active) {
      active.text += text;
      if (active.text.length > MAX_TEXT_CHARS) throw new Error('Verse text too long');
    } else if (selected && normalizeWhitespace(text)) {
      throw new Error(`Unassigned primary text at ${book}.${chapter}`);
    }
  };
  const finishVerse = () => {
    if (!active) throw new Error(`Verse-end marker without verse at ${book}.${chapter}`);
    const text = normalizeWhitespace(active.text);
    const number = /^[1-9][0-9]*$/.test(active.label) ? Number(active.label) : null;
    const compatible = number !== null && number <= (canonicalCounts[book]?.[chapter - 1] ?? 0);
    const verse: ScriptureVerse = {
      sourceId: 'webp',
      version,
      sourceBook: book,
      sourceChapter: chapter,
      sourceVerse: active.label,
      text,
      canonical: compatible ? { book, chapter, verse: number! } : null,
      alignment: compatible ? 'canonical-compatible' : 'unsupported',
      textStatus: text ? 'present' : 'empty',
      verification: 'literal-source',
      editorialReview: 'unreviewed',
    };
    result.verses.push(verse);
    if (!compatible) result.unsupportedVerses.push(sourceCoordinate(verse));
    if (!text) result.emptyVerses.push(sourceCoordinate(verse));
    active = null;
  };
  const parser = new SaxesParser({ xmlns: false });
  parser.on('error', (error) => {
    throw error;
  });
  parser.on('doctype', () => {
    throw new Error('DTD declarations are forbidden');
  });
  parser.on('processinginstruction', () => {
    throw new Error('Processing instructions are forbidden');
  });
  parser.on('opentag', (tag) => {
    if (stack.length >= MAX_DEPTH) throw new Error('USFX nesting exceeds 64 levels');
    const name = tag.name;
    const attrs = tag.attributes as Record<string, string>;
    const parent = stack.at(-1);
    let suppressed = parent?.suppressed ?? false;
    let block = false;
    if (!parent && name !== 'usfx') throw new Error('Expected usfx root');
    if (name === 'usfx' && parent) throw new Error('Nested usfx root');
    if (name === 'book') {
      if (parent?.name !== 'usfx' || book) throw new Error('Invalid book placement');
      book = attrs.id ?? '';
      if (!/^[A-Z0-9]{3}$/.test(book) || seenBooks.has(book))
        throw new Error(`Invalid/duplicate book: ${book}`);
      seenBooks.add(book);
      selected = Object.hasOwn(canonicalCounts, book);
      chapter = 0;
      chapterSets.set(book, new Set());
      excludedBook = selected ? null : { book, verseMarkerCount: 0 };
      if (excludedBook) result.excludedBooks.push(excludedBook);
    } else if (name === 'languageCode') {
      if (parent?.name !== 'usfx') throw new Error('Invalid languageCode placement');
      suppressed = true;
    } else if (name !== 'usfx' && !book)
      throw new Error(`Unexpected element outside book: ${name}`);
    if (book && selected) {
      if (['c', 'v', 've'].includes(name) && suppressed)
        throw new Error('Scripture milestone inside excluded content');
      if (name === 'c') {
        if (parent?.name !== 'book' || !tag.isSelfClosing || active || superscription)
          throw new Error('Ambiguous chapter marker');
        if (!/^[1-9][0-9]{0,2}$/.test(attrs.id ?? '')) throw new Error('Invalid chapter label');
        const nextChapter = Number(attrs.id);
        if (nextChapter <= chapter) throw new Error('Duplicate/out-of-order chapter');
        chapter = nextChapter;
        lastVerseLabel = null;
        chapterSets.get(book)!.add(chapter);
      } else if (name === 'v') {
        if (
          !tag.isSelfClosing ||
          active ||
          superscription ||
          !chapter ||
          !['p', 'q'].includes(parent?.name ?? '')
        )
          throw new Error('Ambiguous verse marker');
        const label = attrs.id ?? '';
        if (!/^[1-9][0-9]{0,2}(?:[a-z]|-[1-9][0-9]{0,2}[a-z]?)?$/.test(label))
          throw new Error('Invalid verse label');
        if (attrs.bcv && attrs.bcv !== `${book}.${chapter}.${label.split('-')[0]}`)
          throw new Error('Conflicting bcv coordinate');
        const key = `${book}.${chapter}.${label}`;
        if (seenVerses.has(key)) throw new Error(`Duplicate verse: ${key}`);
        seenVerses.add(key);
        active = { label, text: '' };
        lastVerseLabel = label;
      } else if (name === 've') {
        if (!tag.isSelfClosing) throw new Error('Ambiguous verse-end marker');
        finishVerse();
      } else if (name === 'd') {
        if (parent?.name !== 'book' || superscription || !chapter)
          throw new Error('Ambiguous superscription');
        superscription = { text: '', depth: stack.length + 1, afterSourceVerse: lastVerseLabel };
      } else if (name === 'p' || name === 'q') {
        const style = attrs.style ?? attrs.sfm ?? name;
        if (excludedStyles.test(style)) suppressed = true;
        else if (name === 'p' ? !paragraphStyles.test(style) : !/^q[0-9]*$/.test(style))
          throw new Error(`Unsupported paragraph style: ${style}`);
        // A declared marker must agree with the style (q2 -> q, mt1 -> mt).
        if (attrs.sfm && style.replace(/[0-9]+$/, '') !== attrs.sfm)
          throw new Error('Conflicting paragraph markers');
        block = true;
      } else if (name === 'b') {
        block = true;
      } else if (excludedTags.has(name)) suppressed = true;
      else if (annotationTags.has(name)) {
        if (!suppressed) throw new Error(`Annotation outside excluded content: ${name}`);
      } else if (!['book'].includes(name) && !inlineTags.has(name))
        throw new Error(`Unsupported USFX element: ${name}`);
      if (suppressed && !parent?.suppressed)
        result.excludedElementCounts[name === 'p' ? `p:${attrs.style ?? attrs.sfm}` : name] =
          (result.excludedElementCounts[name === 'p' ? `p:${attrs.style ?? attrs.sfm}` : name] ??
            0) + 1;
      if (block && !suppressed && (active || superscription)) append(' ');
    }
    if (name === 'v') {
      markerCount++;
      if (markerCount > MAX_VERSES) throw new Error('Too many verse markers');
      if (excludedBook) excludedBook.verseMarkerCount++;
    }
    stack.push({ name, suppressed, block });
  });
  parser.on('text', (text) => {
    if (stack.at(-1)?.suppressed) return;
    if (selected) append(text);
    else if (!book && normalizeWhitespace(text))
      throw new Error('Unexpected text outside source book');
  });
  parser.on('cdata', () => {
    throw new Error('CDATA is outside the accepted publisher profile');
  });
  parser.on('closetag', (tag) => {
    const frame = stack.at(-1)!;
    if (selected && tag.name === 'd' && superscription?.depth === stack.length) {
      result.unversified.push({
        sourceId: 'webp',
        version,
        sourceBook: book,
        sourceChapter: chapter,
        marker: 'd',
        afterSourceVerse: superscription.afterSourceVerse,
        text: normalizeWhitespace(superscription.text),
        verification: 'literal-source',
        editorialReview: 'unreviewed',
      });
      superscription = null;
    }
    if (selected && frame.block && !frame.suppressed && (active || superscription)) append(' ');
    if (tag.name === 'book') {
      if (active || superscription) throw new Error('Unclosed verse/superscription at book end');
      book = '';
      chapter = 0;
      selected = false;
      excludedBook = null;
    }
    stack.pop();
  });
  parser.write(xml).close();
  if (options.requireAll66Books !== false) {
    const missingBooks = canonicalBookOrder.filter((id) => !seenBooks.has(id));
    if (missingBooks.length) throw new Error(`Missing canonical books: ${missingBooks.join(', ')}`);
    for (const id of canonicalBookOrder) {
      for (let n = 1; n <= canonicalCounts[id].length; n++) {
        if (!chapterSets.get(id)?.has(n)) throw new Error(`Missing source chapter: ${id}.${n}`);
      }
    }
  }
  for (const id of canonicalBookOrder) {
    const verses = result.verses.filter((v) => v.sourceBook === id);
    if (seenBooks.has(id))
      result.books.push({
        book: id,
        chapterCount: chapterSets.get(id)!.size,
        verseCount: verses.length,
        nonemptyVerseCount: verses.filter((v) => v.textStatus === 'present').length,
        canonicalCompatibleVerseCount: verses.filter((v) => v.alignment === 'canonical-compatible')
          .length,
        unsupportedVerseCount: verses.filter((v) => v.alignment === 'unsupported').length,
      });
    for (let c = 1; c <= canonicalCounts[id].length; c++) {
      for (let v = 1; v <= canonicalCounts[id][c - 1]; v++) {
        if (!seenVerses.has(`${id}.${c}.${v}`))
          result.missingCanonicalVerses.push({ book: id, chapter: c, verse: v });
      }
    }
  }
  // Keep source order within each book; enforce the app's canonical book order.
  const order = new Map(canonicalBookOrder.map((id, i) => [id, i]));
  result.verses.sort((a, b) => order.get(a.sourceBook)! - order.get(b.sourceBook)!);
  result.unversified.sort((a, b) => order.get(a.sourceBook)! - order.get(b.sourceBook)!);
  result.excludedElementCounts = Object.fromEntries(
    Object.entries(result.excludedElementCounts).sort(([a], [b]) => a.localeCompare(b, 'en')),
  );
  return result;
}

export function serializeScriptureVerses(
  rows: readonly (ScriptureVerse | UnversifiedScripture)[],
): string {
  return rows.map((row) => JSON.stringify(row)).join('\n') + (rows.length ? '\n' : '');
}
export async function scriptureSha256(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest('SHA-256', Uint8Array.from(bytes));
  return [...new Uint8Array(hash)].map((n) => n.toString(16).padStart(2, '0')).join('');
}

export async function prepareScriptureCorpus(
  xmlBytes: Uint8Array,
  provenance: ScriptureProvenance,
  options: { requireAll66Books?: boolean } = {},
): Promise<
  ScriptureParseResult & {
    manifest: ScriptureManifest;
    versesNdjson: string;
    unversifiedNdjson: string;
  }
> {
  if (xmlBytes.byteLength > MAX_XML_BYTES) throw new Error('USFX exceeds the 64 MiB limit');
  if (!/^[a-z0-9][a-z0-9._-]{1,99}$/.test(provenance.version))
    throw new Error('Invalid corpus version');
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(provenance.fetchedAt) ||
    !Number.isFinite(Date.parse(provenance.fetchedAt))
  )
    throw new Error('fetchedAt must be an ISO UTC timestamp');
  if (![provenance.archiveSha256, provenance.xmlSha256].every((v) => /^[a-f0-9]{64}$/.test(v)))
    throw new Error('Expected lowercase SHA-256 digests');
  const xmlHash = await scriptureSha256(xmlBytes);
  if (xmlHash !== provenance.xmlSha256)
    throw new Error('XML SHA-256 does not match expected source bytes');
  const result = parseWebpUsfx(new TextDecoder('utf-8', { fatal: true }).decode(xmlBytes), {
    ...options,
    version: provenance.version,
  });
  const versesNdjson = serializeScriptureVerses(result.verses);
  const unversifiedNdjson = serializeScriptureVerses(result.unversified);
  const encode = (text: string) => new TextEncoder().encode(text);
  const manifest: ScriptureManifest = {
    schemaVersion: 1,
    corpusId: 'webp',
    edition: 'engwebp',
    referenceSystem: 'web-protestant',
    sourceId: 'webp',
    title: WEBP_SOURCE.title,
    sourceURL: WEBP_SOURCE.sourceURL,
    licenseURL: WEBP_SOURCE.licenseURL,
    license: 'public-domain',
    language: 'en',
    version: provenance.version,
    fetchedAt: provenance.fetchedAt,
    hash: {
      algorithm: 'sha256',
      archive: provenance.archiveSha256,
      xml: xmlHash,
      verses: await scriptureSha256(encode(versesNdjson)),
      unversified: await scriptureSha256(encode(unversifiedNdjson)),
    },
    archiveMember: WEBP_SOURCE.archiveMember,
    parserVersion: 'webp-usfx/1',
    bookCount: result.books.length,
    verseCount: result.verses.length,
    nonemptyVerseCount: result.verses.filter((v) => v.textStatus === 'present').length,
    canonicalCompatibleVerseCount: result.verses.filter(
      (v) => v.alignment === 'canonical-compatible',
    ).length,
    unsupportedVerseCount: result.unsupportedVerses.length,
    unversifiedSectionCount: result.unversified.length,
    books: result.books,
    excludedBooks: result.excludedBooks,
    unsupportedVerses: result.unsupportedVerses,
    emptyVerses: result.emptyVerses,
    missingCanonicalVerses: result.missingCanonicalVerses,
    excludedElementCounts: result.excludedElementCounts,
    parsingPolicy: SCRIPTURE_PARSING_POLICY,
    verification: {
      sourceText: 'xml-sha256-verified',
      editorialReview: 'unreviewed',
      humanTextReview: false,
    },
  };
  return { ...result, manifest, versesNdjson, unversifiedNdjson };
}
