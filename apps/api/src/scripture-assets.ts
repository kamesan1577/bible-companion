import bookIndexPins from '../../../packages/core/fixtures/scripture-asset-indexes.json';
import { passageSchema, type Passage } from '@bible/core';
import counts from '../../../packages/core/src/verse-counts.json';
import { isTrustedPrimaryCorpus } from '@bible/ai-harness';
import { fail } from './http';
import type { Env } from './types';
import type { ScriptureRow } from './scripture';
import {
  SCRIPTURE_ASSET_INDEX_SHA256,
  SCRIPTURE_ASSET_SOURCE_VERSION,
  SCRIPTURE_ASSET_MANIFEST_SHA256,
  SCRIPTURE_ABSENT_CANONICAL,
} from './scripture-assets-pin';
export type AssetCorpus = {
  id: string;
  version: string;
  edition: string;
  manifest_sha256: string;
  asset_index_sha256: string | null;
};
type Entry = {
  path: string;
  sha256: string;
  bytes: number;
  count: number;
  firstVerse: number;
  lastVerse: number;
};
type Index = {
  schemaVersion: 1;
  corpusId: string;
  sourceVersion: string;
  manifestSha256: string;
  chapters: Record<string, Entry>;
};
type Chapter = { book: string; chapter: number; verses: [number, string][] };
const absent = new Set<string>(SCRIPTURE_ABSENT_CANONICAL);
const indexCache = new WeakMap<object, Map<string, Promise<Index>>>();
const chapterCache = new WeakMap<object, Map<string, Chapter>>();
export function knownPrimaryReference(book: string, chapter: number, verse: number): boolean {
  return (
    passageSchema.safeParse({ book, start: { chapter, verse }, end: { chapter, verse } }).success &&
    !absent.has(`${book}:${chapter}:${verse}`)
  );
}
export function trustedAssetCorpus(c: AssetCorpus): boolean {
  return (
    c.id === 'webp' &&
    c.version === SCRIPTURE_ASSET_SOURCE_VERSION &&
    c.manifest_sha256 === SCRIPTURE_ASSET_MANIFEST_SHA256 &&
    c.asset_index_sha256 === SCRIPTURE_ASSET_INDEX_SHA256 &&
    isTrustedPrimaryCorpus({
      corpusId: c.id,
      edition: c.edition,
      manifestSha256: c.manifest_sha256,
      sourceVersion: c.version,
    })
  );
}
function invalid(): never {
  return fail(
    503,
    'scripture_assets_unavailable',
    'Verified scripture assets are unavailable. Retry later.',
  );
}
async function assetJSON(
  env: Env,
  path: string,
  maxBytes: number,
  digest: string,
): Promise<unknown> {
  const binding = env.SCRIPTURE_ASSETS;
  if (!binding) invalid();
  const controller = new AbortController();
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let responseBody: ReadableStream<Uint8Array> | null | undefined;
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const pending = (async () => {
    const response = await binding.fetch(
      new Request('https://scripture-assets.invalid' + path, {
        redirect: 'manual',
        signal: controller.signal,
      }),
    );
    responseBody = response.body;
    if (controller.signal.aborted) {
      void response.body?.cancel().catch(() => {});
      invalid();
    }
    if (
      response.status !== 200 ||
      response.redirected ||
      !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') ||
      !response.body
    )
      invalid();
    const declared = response.headers.get('content-length');
    if (declared && (!/^\d+$/.test(declared) || Number(declared) > maxBytes)) invalid();
    reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let bytes = 0,
      totalChunks = 0,
      empty = 0;
    while (true) {
      if (controller.signal.aborted) invalid();
      const part = await reader.read();
      if (part.done) break;
      if (++totalChunks > 4096) invalid();
      if (!part.value.byteLength) {
        if (++empty > 64) invalid();
        continue;
      }
      empty = 0;
      bytes += part.value.byteLength;
      if (bytes > maxBytes) invalid();
      chunks.push(part.value);
    }
    const all = new Uint8Array(bytes);
    let offset = 0;
    for (const chunk of chunks) {
      all.set(chunk, offset);
      offset += chunk.length;
    }
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', all)))
      .map((n) => n.toString(16).padStart(2, '0'))
      .join('');
    if (hash !== digest) invalid();
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(all));
  })();
  try {
    return await Promise.race([
      pending,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => {
          controller.abort();
          reject(Error('asset timeout'));
        }, 5000);
      }),
    ]);
  } catch {
    invalid();
  } finally {
    if (timeout) clearTimeout(timeout);
    controller.abort();
    if (reader) void reader.cancel().catch(() => {});
    else void responseBody?.cancel().catch(() => {});
  }
}
function exactKeys(value: unknown, keys: string[]): value is Record<string, unknown> {
  return (
    !!value &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    Object.keys(value).sort().join('|') === keys.sort().join('|')
  );
}
async function loadIndex(env: Env, corpus: AssetCorpus, selectedBook: string): Promise<Index> {
  if (!trustedAssetCorpus(corpus) || !env.SCRIPTURE_ASSETS) invalid();
  const binding = env.SCRIPTURE_ASSETS;
  const pin = (bookIndexPins as Record<string, { sha256: string; bytes: number }>)[selectedBook];
  if (!pin || pin.bytes > 32768) invalid();
  let cache = indexCache.get(binding);
  if (!cache) {
    cache = new Map();
    indexCache.set(binding, cache);
  }
  let cached = cache.get(selectedBook);
  if (cached) {
    cache.delete(selectedBook);
    cache.set(selectedBook, cached);
    return cached;
  }
  cached = (async () => {
    const raw = await assetJSON(
      env,
      `/__scripture/${corpus.version}/${selectedBook}/index.json`,
      pin.bytes,
      pin.sha256,
    );
    if (
      !exactKeys(raw, [
        'schemaVersion',
        'corpusId',
        'sourceVersion',
        'manifestSha256',
        'chapters',
      ]) ||
      raw.schemaVersion !== 1 ||
      raw.corpusId !== corpus.id ||
      raw.sourceVersion !== corpus.version ||
      raw.manifestSha256 !== corpus.manifest_sha256 ||
      !raw.chapters ||
      typeof raw.chapters !== 'object' ||
      Array.isArray(raw.chapters)
    )
      invalid();
    let total = 0;
    const entries = Object.entries(raw.chapters);
    const chapterCounts = (counts as Record<string, number[]>)[selectedBook];
    if (!chapterCounts || entries.length !== chapterCounts.length) invalid();
    for (const [key, value] of entries) {
      const match = /^([A-Z0-9]{3}):([1-9][0-9]{0,2})$/.exec(key);
      if (
        !match ||
        !exactKeys(value, ['path', 'sha256', 'bytes', 'count', 'firstVerse', 'lastVerse'])
      )
        invalid();
      const book = match[1],
        chapter = Number(match[2]);
      if (
        book !== selectedBook ||
        !passageSchema.safeParse({ book, start: { chapter, verse: 1 }, end: { chapter, verse: 1 } })
          .success ||
        value.path !== `/__scripture/${corpus.version}/${book}/${chapter}.json` ||
        typeof value.sha256 !== 'string' ||
        !/^[a-f0-9]{64}$/.test(value.sha256) ||
        !Number.isInteger(value.bytes) ||
        Number(value.bytes) < 1 ||
        Number(value.bytes) > 65536 ||
        !Number.isInteger(value.count) ||
        Number(value.count) < 1 ||
        Number(value.count) > 176 ||
        !knownPrimaryReference(book, chapter, Number(value.firstVerse)) ||
        !knownPrimaryReference(book, chapter, Number(value.lastVerse)) ||
        Number(value.firstVerse) > Number(value.lastVerse)
      )
        invalid();
      total += Number(value.count);
    }
    if (
      total !==
      chapterCounts.reduce((sum, n) => sum + n, 0) -
        SCRIPTURE_ABSENT_CANONICAL.filter((key) => key.startsWith(selectedBook + ':')).length
    )
      invalid();
    return raw as unknown as Index;
  })();
  cache.set(selectedBook, cached);
  while (cache.size > 3) cache.delete(cache.keys().next().value!);
  try {
    return await cached;
  } catch (e) {
    cache.delete(selectedBook);
    throw e;
  }
}
async function loadChapter(
  env: Env,
  corpus: AssetCorpus,
  index: Index,
  book: string,
  chapter: number,
): Promise<Chapter> {
  const entry = index.chapters[`${book}:${chapter}`];
  if (!entry || !env.SCRIPTURE_ASSETS) invalid();
  let cache = chapterCache.get(env.SCRIPTURE_ASSETS);
  if (!cache) {
    cache = new Map();
    chapterCache.set(env.SCRIPTURE_ASSETS, cache);
  }
  const key = entry.path + ':' + entry.sha256;
  const hit = cache.get(key);
  if (hit) {
    cache.delete(key);
    cache.set(key, hit);
    return hit;
  }
  const raw = await assetJSON(env, entry.path, Math.min(entry.bytes, 65536), entry.sha256);
  if (
    !exactKeys(raw, ['book', 'chapter', 'verses']) ||
    raw.book !== book ||
    raw.chapter !== chapter ||
    !Array.isArray(raw.verses) ||
    raw.verses.length !== entry.count
  )
    invalid();
  let previous = 0;
  for (const item of raw.verses) {
    if (
      !Array.isArray(item) ||
      item.length !== 2 ||
      !Number.isInteger(item[0]) ||
      item[0] <= previous ||
      !knownPrimaryReference(book, chapter, item[0]) ||
      typeof item[1] !== 'string' ||
      !item[1].trim() ||
      new TextEncoder().encode(item[1]).byteLength > 16384
    )
      invalid();
    previous = item[0];
  }
  if (raw.verses[0][0] !== entry.firstVerse || raw.verses.at(-1)[0] !== entry.lastVerse) invalid();
  const value = raw as unknown as Chapter;
  cache.set(key, value);
  while (cache.size > 6) cache.delete(cache.keys().next().value!);
  return value;
}
function knownAfter(p: Passage, position: { chapter: number; verse: number }): boolean {
  const chapters = (counts as Record<string, number[]>)[p.book];
  if (!chapters) return false;
  for (let c = position.chapter; c <= p.end.chapter; c++)
    for (
      let v = c === position.chapter ? position.verse + 1 : 1;
      v <= (c === p.end.chapter ? p.end.verse : chapters[c - 1]);
      v++
    )
      if (knownPrimaryReference(p.book, c, v)) return true;
  return false;
}
export async function assetScriptureRows(
  env: Env,
  corpus: AssetCorpus,
  passage: Passage,
  after: { chapter: number; verse: number },
  limit: number,
): Promise<{ rows: ScriptureRow[]; hasMore: boolean }> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 101) invalid();
  const index = await loadIndex(env, corpus, passage.book);
  const rows: ScriptureRow[] = [];
  let loaded = 0;
  for (
    let chapter = Math.max(after.chapter, passage.start.chapter);
    chapter <= passage.end.chapter && loaded < 8;
    chapter++
  ) {
    const data = await loadChapter(env, corpus, index, passage.book, chapter);
    loaded++;
    for (const [verse, text] of data.verses) {
      const pos = chapter * 1000 + verse;
      if (
        pos <= after.chapter * 1000 + after.verse ||
        pos < passage.start.chapter * 1000 + passage.start.verse ||
        pos > passage.end.chapter * 1000 + passage.end.verse
      )
        continue;
      rows.push({
        corpus_id: corpus.id,
        corpus_version: corpus.version,
        edition: corpus.edition,
        manifest_sha256: corpus.manifest_sha256,
        book: passage.book,
        chapter,
        verse,
        text,
      });
      if (rows.length === limit) return { rows, hasMore: knownAfter(passage, { chapter, verse }) };
    }
  }
  return { rows, hasMore: knownAfter(passage, rows.at(-1) ?? after) };
}
