import verseCounts from './verse-counts.json' with { type: 'json' };
import { z } from 'zod';

export type Verse = { chapter: number; verse: number };
export type Passage = { book: string; start: Verse; end: Verse };
const books = [
  ['GEN', 'Genesis', '創世記', 50],
  ['EXO', 'Exodus', '出エジプト記', 40],
  ['LEV', 'Leviticus', 'レビ記', 27],
  ['NUM', 'Numbers', '民数記', 36],
  ['DEU', 'Deuteronomy', '申命記', 34],
  ['JOS', 'Joshua', 'ヨシュア記', 24],
  ['JDG', 'Judges', '士師記', 21],
  ['RUT', 'Ruth', 'ルツ記', 4],
  ['1SA', '1 Samuel', 'サムエル記上', 31],
  ['2SA', '2 Samuel', 'サムエル記下', 24],
  ['1KI', '1 Kings', '列王記上', 22],
  ['2KI', '2 Kings', '列王記下', 25],
  ['1CH', '1 Chronicles', '歴代誌上', 29],
  ['2CH', '2 Chronicles', '歴代誌下', 36],
  ['EZR', 'Ezra', 'エズラ記', 10],
  ['NEH', 'Nehemiah', 'ネヘミヤ記', 13],
  ['EST', 'Esther', 'エステル記', 10],
  ['JOB', 'Job', 'ヨブ記', 42],
  ['PSA', 'Psalms', '詩篇', 150],
  ['PRO', 'Proverbs', '箴言', 31],
  ['ECC', 'Ecclesiastes', '伝道者の書', 12],
  ['SNG', 'Song of Solomon', '雅歌', 8],
  ['ISA', 'Isaiah', 'イザヤ書', 66],
  ['JER', 'Jeremiah', 'エレミヤ書', 52],
  ['LAM', 'Lamentations', '哀歌', 5],
  ['EZK', 'Ezekiel', 'エゼキエル書', 48],
  ['DAN', 'Daniel', 'ダニエル書', 12],
  ['HOS', 'Hosea', 'ホセア書', 14],
  ['JOL', 'Joel', 'ヨエル書', 3],
  ['AMO', 'Amos', 'アモス書', 9],
  ['OBA', 'Obadiah', 'オバデヤ書', 1],
  ['JON', 'Jonah', 'ヨナ書', 4],
  ['MIC', 'Micah', 'ミカ書', 7],
  ['NAM', 'Nahum', 'ナホム書', 3],
  ['HAB', 'Habakkuk', 'ハバクク書', 3],
  ['ZEP', 'Zephaniah', 'ゼパニヤ書', 3],
  ['HAG', 'Haggai', 'ハガイ書', 2],
  ['ZEC', 'Zechariah', 'ゼカリヤ書', 14],
  ['MAL', 'Malachi', 'マラキ書', 4],
  ['MAT', 'Matthew', 'マタイの福音書', 28],
  ['MRK', 'Mark', 'マルコの福音書', 16],
  ['LUK', 'Luke', 'ルカの福音書', 24],
  ['JHN', 'John', 'ヨハネの福音書', 21],
  ['ACT', 'Acts', '使徒の働き', 28],
  ['ROM', 'Romans', 'ローマ人への手紙', 16],
  ['1CO', '1 Corinthians', 'コリント人への手紙第一', 16],
  ['2CO', '2 Corinthians', 'コリント人への手紙第二', 13],
  ['GAL', 'Galatians', 'ガラテヤ人への手紙', 6],
  ['EPH', 'Ephesians', 'エペソ人への手紙', 6],
  ['PHP', 'Philippians', 'ピリピ人への手紙', 4],
  ['COL', 'Colossians', 'コロサイ人への手紙', 4],
  ['1TH', '1 Thessalonians', 'テサロニケ人への手紙第一', 5],
  ['2TH', '2 Thessalonians', 'テサロニケ人への手紙第二', 3],
  ['1TI', '1 Timothy', 'テモテへの手紙第一', 6],
  ['2TI', '2 Timothy', 'テモテへの手紙第二', 4],
  ['TIT', 'Titus', 'テトスへの手紙', 3],
  ['PHM', 'Philemon', 'ピレモンへの手紙', 1],
  ['HEB', 'Hebrews', 'ヘブル人への手紙', 13],
  ['JAS', 'James', 'ヤコブの手紙', 5],
  ['1PE', '1 Peter', 'ペテロの手紙第一', 5],
  ['2PE', '2 Peter', 'ペテロの手紙第二', 3],
  ['1JN', '1 John', 'ヨハネの手紙第一', 5],
  ['2JN', '2 John', 'ヨハネの手紙第二', 1],
  ['3JN', '3 John', 'ヨハネの手紙第三', 1],
  ['JUD', 'Jude', 'ユダの手紙', 1],
  ['REV', 'Revelation', 'ヨハネの黙示録', 22],
] as const;
export const BOOKS = Object.freeze(
  books.map(([id, en, ja, chapters]) => Object.freeze({ id, en, ja, chapters })),
);
const booksById = new Map<string, (typeof BOOKS)[number]>(BOOKS.map((book) => [book.id, book]));
const aliases = new Map<string, string>();
const clean = (s: string) => s.normalize('NFKC').toLowerCase().replace(/[\s.]/g, '');
for (const [id, en, ja] of books)
  for (const a of [
    id,
    en,
    ja,
    ja.replace('の福音書', ''),
    ja.replace('人への手紙', ''),
    ja.replace('の手紙', ''),
  ])
    aliases.set(clean(a), id);
for (const [name, id] of Object.entries({
  使徒: 'ACT',
  使徒行伝: 'ACT',
  使徒言行録: 'ACT',
  詩編: 'PSA',
  黙示録: 'REV',
  伝道の書: 'ECC',
  コヘレトの言葉: 'ECC',
  Matt: 'MAT',
  Mark: 'MRK',
  Luke: 'LUK',
  John: 'JHN',
  Ps: 'PSA',
  Psalm: 'PSA',
  '1Cor': '1CO',
  '2Cor': '2CO',
}))
  aliases.set(clean(name), id);
// Common Japanese ordinal variants used by sharing apps and Bible translations.
for (const [id, , ja] of books) {
  const n = Number(id[0]);
  if (![1, 2, 3].includes(n)) continue;
  const ordinal = ['', '第一', '第二', '第三'][n];
  const roman = ['', 'Ⅰ', 'Ⅱ', 'Ⅲ'][n];
  const stem = ja.replace(/(第一|第二|第三|上|下)$/, '');
  for (const name of [
    stem + roman,
    stem + n,
    stem + ordinal,
    ordinal + stem,
    roman + stem,
    String(n) + stem,
    stem.replace('人への手紙', '') + ordinal,
    ordinal + stem.replace('人への手紙', ''),
  ])
    aliases.set(clean(name), id);
}
/** Normalized, longest-first aliases shared by import parsing and output reference checks. */
export const BOOK_REFERENCE_ALIASES = Object.freeze(
  [...aliases.keys()].sort((a, b) => b.length - a.length),
);
const aliasCandidates = BOOK_REFERENCE_ALIASES;
export function normalizeBook(input: string): string | undefined {
  return aliases.get(clean(input));
}
export function compareVerse(a: Verse, b: Verse): number {
  return a.chapter - b.chapter || a.verse - b.verse;
}

export const verseSchema = z
  .object({
    chapter: z.number().int().positive().max(150),
    verse: z.number().int().positive().max(176),
  })
  .strict();
export const passageSchema = z
  .object({ book: z.string(), start: verseSchema, end: verseSchema })
  .strict()
  .superRefine((p, ctx) => {
    const b = booksById.get(p.book);
    if (
      !b ||
      p.start.chapter > b.chapters ||
      p.end.chapter > b.chapters ||
      compareVerse(p.start, p.end) > 0
    )
      ctx.addIssue({ code: 'custom', message: 'Invalid canonical passage' });
    const counts = (verseCounts as Record<string, number[]>)[p.book];
    if (
      !counts ||
      p.start.verse > (counts[p.start.chapter - 1] ?? 0) ||
      p.end.verse > (counts[p.end.chapter - 1] ?? 0)
    )
      ctx.addIssue({
        code: 'custom',
        message: 'Verse does not exist in the standard 66-book versification',
      });
  });
export type ParsedImport = {
  ranges: Passage[];
  translation: string | null;
  sourceUrl: string | null;
  needsConfirmation: boolean;
  warnings: string[];
};
function segment(book: string, text: string, chapter?: number): Passage {
  const normalized = text
    .replace(/章/g, ':')
    .replace(/節/g, '')
    .replace(/[‐‑‒–—〜～]/g, '-')
    .trim();
  const m = normalized.match(/^(?:(\d+)[:.])?(\d+)(?:\s*-\s*(?:(\d+)[:.])?(\d+))?$/);
  if (!m || (!m[1] && !chapter)) throw new Error('Expected chapter and verse');
  const start = { chapter: Number(m[1] ?? chapter), verse: Number(m[2]) };
  const end = { chapter: Number(m[3] ?? start.chapter), verse: Number(m[4] ?? start.verse) };
  return passageSchema.parse({ book, start, end });
}
/** Never fetches arbitrary shared URLs or guesses a translation from a numeric version ID. */
export function parseImport(raw: string): ParsedImport {
  if (raw.length > 20000) throw new Error('Shared input too long');
  const text = raw.normalize('NFKC');
  const groups: { ranges: Passage[]; translation: string | null }[] = [];
  const warnings: string[] = [];
  const urls = [
    ...text.matchAll(/https:\/\/(?:www\.)?(?:bible\.com|youversion\.com)\/[^\s<>]+/gi),
  ].map((match) => match[0]);
  let sourceUrl: string | null = null;
  for (const urlText of urls) {
    const url = new URL(urlText.replace(/[)）。，]+$/g, ''));
    sourceUrl ??= url.origin + url.pathname;
    const match = url.pathname.match(
      /^\/(?:[a-z]{2}\/)?bible\/\d+\/([1-3]?[A-Z]{2,3})\.(\d+)\.(\d+(?:-\d+(?:\.\d+)?)?)(?:\.([A-Z0-9]+))?\/?$/i,
    );
    if (match) {
      const book = normalizeBook(match[1]);
      if (book) {
        const tail = match[3].replace(/-(\d+)\.(\d+)/, '-$1:$2');
        groups.push({
          ranges: [segment(book, `${match[2]}:${tail}`)],
          translation: match[4]?.toUpperCase() ?? null,
        });
      } else warnings.push('URLの書名を確認してください');
    } else warnings.push('URLの章節を確認してください');
  }
  let ambiguousSuffix = false;
  for (const line of text.split(/\n/)) {
    const collapsed = line.normalize('NFKC').toLowerCase().replace(/\s/g, '');
    if (!collapsed) continue;
    const alias = aliasCandidates.find(
      (a) => collapsed.startsWith(a) && /^\.?\d/.test(collapsed.slice(a.length)),
    );
    if (!alias) continue;
    const rest = collapsed.slice(alias.length).replace(/^\./, '');
    const match = rest.match(/^([0-9:.,、章節\-‐‑‒–—〜～]+)(.*)$/);
    if (!match) continue;
    const parts = match[1].split(/[,、]/);
    if (parts.length > 20) throw new Error('Too many ranges');
    const ranges: Passage[] = [];
    let chapter: number | undefined;
    for (const part of parts) {
      const range = segment(aliases.get(alias)!, part, chapter);
      ranges.push(range);
      chapter = range.end.chapter;
    }
    const suffix = match[2].replace(/^[（(]/, '').replace(/[）)]$/, '');
    const translation = ['jcb', 'niv', 'kjv', 'esv', 'nlt', 'web'].includes(suffix)
      ? suffix.toUpperCase()
      : null;
    if (!translation && /[0-9;；]/.test(suffix)) ambiguousSuffix = true;
    groups.push({ ranges, translation });
  }
  const distinct = new Map(groups.map((group) => [stableJSON(group.ranges), group.ranges]));
  const translations = [
    ...new Set(groups.flatMap((group) => (group.translation ? [group.translation] : []))),
  ];
  if (distinct.size > 1 || translations.length > 1 || ambiguousSuffix) {
    return {
      ranges: [],
      translation: null,
      sourceUrl: null,
      needsConfirmation: true,
      warnings: ['複数または矛盾する参照があります。取り込む範囲と訳を確認してください。'],
    };
  }
  const ranges = [...distinct.values()][0] ?? [];
  const translation = translations[0] ?? null;
  if (!ranges.length) warnings.push('章節を読み取れません。手動で指定してください');
  if (!translation) warnings.push('訳は未確認です');
  return {
    ranges,
    translation,
    sourceUrl,
    needsConfirmation: !ranges.length || !translation || warnings.length > 0,
    warnings: [...new Set(warnings)],
  };
}
export function withinBoundary(p: Passage, boundary: Passage, spoilerAllowed = false): boolean {
  return spoilerAllowed || (p.book === boundary.book && compareVerse(p.end, boundary.end) <= 0);
}
export function stableJSON(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(stableJSON).join(',') + ']';
  return (
    '{' +
    Object.entries(value as Record<string, unknown>)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([k, v]) => JSON.stringify(k) + ':' + stableJSON(v))
      .join(',') +
    '}'
  );
}
export async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return base64url(new Uint8Array(bytes));
}
export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}
export function decode64(value: string): Uint8Array {
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), (x) => x.charCodeAt(0));
}
export function randomToken(): string {
  return base64url(crypto.getRandomValues(new Uint8Array(32)));
}
export type CacheIdentity = {
  passage: Passage;
  translation: string | null;
  language: string;
  spoilerAllowed: boolean;
  provider: string;
  modelId: string;
  modelVersion: string;
  promptVersion: string;
  settings: unknown;
  sourceVersion: string;
  ownerId?: string;
};
export async function cacheKey(identity: CacheIdentity): Promise<string> {
  return (identity.ownerId ? 'private:' : 'public:') + (await sha256(stableJSON(identity)));
}

export function containsPassage(outer: Passage, inner: Passage): boolean {
  return (
    outer.book === inner.book &&
    compareVerse(outer.start, inner.start) <= 0 &&
    compareVerse(inner.end, outer.end) <= 0
  );
}

/** Small literal context around a narrower question target, always inside the confirmed range. */
export function questionContextWindow(
  boundary: Passage,
  target: Passage,
  earlierBackground = false,
): Passage {
  passageSchema.parse(boundary);
  passageSchema.parse(target);
  if (!containsPassage(boundary, target))
    throw new Error('Question target is outside reading boundary');
  const counts = (verseCounts as Record<string, number[]>)[target.book];
  const advance = (value: Verse, direction: 1 | -1): Verse => {
    if (direction === 1)
      return value.verse < counts[value.chapter - 1]
        ? { chapter: value.chapter, verse: value.verse + 1 }
        : value.chapter < counts.length
          ? { chapter: value.chapter + 1, verse: 1 }
          : value;
    return value.verse > 1
      ? { chapter: value.chapter, verse: value.verse - 1 }
      : value.chapter > 1
        ? { chapter: value.chapter - 1, verse: counts[value.chapter - 2] }
        : value;
  };
  let probe = { ...target.start },
    size = 1;
  while (compareVerse(probe, target.end) < 0 && size <= 32) {
    probe = advance(probe, 1);
    size++;
  }
  // A large target already uses the retrieval allowance; never push its beginning out with context.
  if (size > 32) return { book: target.book, start: { ...target.start }, end: { ...target.end } };
  let start = { ...target.start },
    end = { ...target.end };
  if (earlierBackground) {
    // Earlier text is background, never a claim that the selected translation was verified.
    // The upper spoiler boundary remains fixed. Keep the selected passage first in retrieval.
    for (let i = 0; i < 24 && size < 32; i++) {
      const before = advance(start, -1);
      if (compareVerse(before, start) === 0) break;
      start = before;
      size++;
    }
    for (let i = 0; i < 8 && size < 32; i++) {
      const after = advance(end, 1);
      if (compareVerse(after, boundary.end) > 0 || compareVerse(after, end) === 0) break;
      end = after;
      size++;
    }
  } else {
    for (let i = 0; i < 8; i++) {
      const before = advance(start, -1),
        after = advance(end, 1);
      if (compareVerse(before, boundary.start) >= 0) start = before;
      if (compareVerse(after, boundary.end) <= 0) end = after;
    }
  }
  return { book: target.book, start, end };
}
