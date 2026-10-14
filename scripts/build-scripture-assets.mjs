#!/usr/bin/env node
/** Deterministic offline static assets from the pinned corpus. No network, account or deployment actions. */
import { createHash } from 'node:crypto';
import {
  constants,
  closeSync,
  existsSync,
  fstatSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';
import counts from '../packages/core/src/verse-counts.json' with { type: 'json' };
import { validateArtifacts } from './import-scripture.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const preparedDirectory = '.cache/scripture/prepared';
const outputDirectory = '.cache/scripture/assets';
const INDEX_LIMIT = 262144;
const CHAPTER_LIMIT = 65536;
const plans = new WeakSet();
const hash = (data) => createHash('sha256').update(data).digest('hex');
const encode = (value) => JSON.stringify(value) + '\n';
class AssetError extends Error {}
function check(condition, message) {
  if (!condition) throw new AssetError(message);
}

/** Both roots remain inside the repository; no existing symlink component is followed. */
function safePath(base, candidate) {
  check(typeof candidate === 'string' && candidate.length > 0, 'Invalid path.');
  const target = resolve(base, candidate);
  const rel = relative(base, target);
  check(
    rel !== '..' && !rel.startsWith('../') && !isAbsolute(rel),
    'Path escapes the allowed root.',
  );
  let current = base;
  for (const part of ['', ...rel.split('/').filter(Boolean)]) {
    if (part) current = join(current, part);
    const info = lstatSync(current, { throwIfNoEntry: false });
    check(!info?.isSymbolicLink(), 'Symbolic links are not allowed.');
  }
  return target;
}
function readBoundedFile(file, maximum) {
  const fd = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = fstatSync(fd);
    check(info.isFile() && info.size <= maximum, 'Input is not a bounded regular file.');
    const bytes = readFileSync(fd);
    check(bytes.length <= maximum, 'Input exceeds the byte limit.');
    return bytes;
  } finally {
    closeSync(fd);
  }
}
export function readScriptureAssetInputs(directory = preparedDirectory) {
  const input = safePath(root, directory);
  return {
    manifest: readBoundedFile(safePath(input, 'manifest.json'), INDEX_LIMIT),
    verses: readBoundedFile(safePath(input, 'verses.ndjson'), 64 * 1024 * 1024),
    unversified: readBoundedFile(safePath(input, 'unversified.ndjson'), 64 * 1024 * 1024),
  };
}

/** Read the checked-in pinned bundle, independent of ignored cache files and network availability.
 * Returned bytes still require planScriptureAssets/validateArtifacts before use. */
export function readBundledScriptureAssetInputs() {
  const directory = safePath(root, 'data/scripture/webp-2026-10-13');
  const inflate = (name) =>
    gunzipSync(readBoundedFile(safePath(directory, name), 8 * 1024 * 1024), {
      maxOutputLength: 64 * 1024 * 1024,
    });
  return {
    manifest: readBoundedFile(safePath(directory, 'manifest.json'), INDEX_LIMIT),
    verses: inflate('verses.ndjson.gz'),
    unversified: inflate('unversified.ndjson.gz'),
  };
}

/** The optional identity list is a module-only synthetic test seam. CLI offers no override. */
export function planScriptureAssets(artifacts, trustedIdentities) {
  const corpus =
    trustedIdentities === undefined
      ? validateArtifacts(artifacts)
      : validateArtifacts(artifacts, trustedIdentities);
  const grouped = new Map();
  for (const [book, chapters] of Object.entries(counts))
    chapters.forEach((_, i) => grouped.set(`${book}:${i + 1}`, []));
  for (const row of corpus.verses) {
    if (
      row.alignment !== 'canonical-compatible' ||
      row.textStatus !== 'present' ||
      !row.text ||
      !row.canonical
    )
      continue;
    const key = `${row.canonical.book}:${row.canonical.chapter}`;
    check(grouped.has(key), 'Source chapter is outside the canonical asset set.');
    grouped.get(key).push([row.canonical.verse, row.text]);
  }
  const chapters = {};
  const files = [];
  let verseCount = 0,
    totalChapterBytes = 0,
    maxChapterBytes = 0;
  for (const [key, verses] of grouped) {
    const [book, chapterText] = key.split(':');
    const chapter = Number(chapterText);
    verses.sort((a, b) => a[0] - b[0]);
    check(new Set(verses.map(([n]) => n)).size === verses.length, 'Duplicate canonical verse.');
    const contents = encode({ book, chapter, verses });
    const bytes = Buffer.byteLength(contents);
    check(bytes <= CHAPTER_LIMIT, 'Chapter exceeds the runtime asset byte bound.');
    const path = `/__scripture/${corpus.manifest.version}/${book}/${chapter}.json`;
    chapters[key] = Object.freeze({
      path,
      sha256: hash(contents),
      bytes,
      count: verses.length,
      firstVerse: verses[0]?.[0] ?? null,
      lastVerse: verses.at(-1)?.[0] ?? null,
    });
    files.push(Object.freeze({ path, contents }));
    verseCount += verses.length;
    totalChapterBytes += bytes;
    maxChapterBytes = Math.max(maxChapterBytes, bytes);
  }
  check(files.length === 1189, 'Require all 1189 canonical chapters.');
  const index = Object.freeze({
    schemaVersion: 1,
    corpusId: corpus.manifest.corpusId,
    sourceVersion: corpus.manifest.version,
    manifestSha256: corpus.manifestSha256,
    chapters: Object.freeze(chapters),
  });
  const indexContents = encode(index),
    indexBytes = Buffer.byteLength(indexContents);
  check(indexBytes <= INDEX_LIMIT, 'Index exceeds the runtime asset byte bound.');
  const bookIndexPins = {};
  let bookIndexesBytes = 0,
    maxBookIndexBytes = 0;
  for (const book of Object.keys(counts)) {
    const bookChapters = Object.fromEntries(
      Object.entries(chapters).filter(([key]) => key.startsWith(`${book}:`)),
    );
    const contents = encode({ ...index, chapters: bookChapters });
    const bytes = Buffer.byteLength(contents);
    check(bytes <= CHAPTER_LIMIT, 'Book index exceeds the runtime byte bound.');
    bookIndexPins[book] = Object.freeze({ sha256: hash(contents), bytes });
    files.push(
      Object.freeze({
        path: `/__scripture/${corpus.manifest.version}/${book}/index.json`,
        contents,
      }),
    );
    bookIndexesBytes += bytes;
    maxBookIndexBytes = Math.max(maxBookIndexBytes, bytes);
  }
  const bookIndexPinsContents = encode(bookIndexPins);
  const bookIndexPinsPath = `/__scripture/${corpus.manifest.version}/book-index-pins.json`;
  files.push(Object.freeze({ path: bookIndexPinsPath, contents: bookIndexPinsContents }));
  const indexPath = `/__scripture/${corpus.manifest.version}/index.json`;
  files.push(Object.freeze({ path: indexPath, contents: indexContents }));
  const plan = Object.freeze({
    index,
    bookIndexPins: Object.freeze(bookIndexPins),
    bookIndexPinsContents,
    files: Object.freeze(files),
    summary: Object.freeze({
      corpusId: corpus.manifest.corpusId,
      sourceVersion: corpus.manifest.version,
      manifestSha256: corpus.manifestSha256,
      chapterCount: 1189,
      verseCount,
      indexPath,
      indexSha256: hash(indexContents),
      indexBytes,
      totalChapterBytes,
      maxChapterBytes,
      bookIndexCount: 66,
      bookIndexesBytes,
      maxBookIndexBytes,
      bookIndexPinsPath,
      bookIndexPinsSha256: hash(bookIndexPinsContents),
      bookIndexPinsBytes: Buffer.byteLength(bookIndexPinsContents),
      totalBytes:
        totalChapterBytes +
        indexBytes +
        bookIndexesBytes +
        Buffer.byteLength(bookIndexPinsContents),
      networkRequests: 0,
    }),
  });
  plans.add(plan);
  return plan;
}

/** Refuse changed existing files; repeated byte-identical builds perform no writes. */
export function writeScriptureAssetPlan(plan, output = outputDirectory, checkOnly = false) {
  check(plans.has(plan), 'Only an artifact-validated asset plan can be written.');
  const directory = safePath(root, output);
  check(
    relative(root, directory).startsWith('.cache/scripture/'),
    'Output must stay within .cache/scripture/.',
  );
  let existingFiles = 0;
  const pending = [];
  for (const file of plan.files) {
    check(file.path.startsWith('/__scripture/'), 'Unexpected asset path.');
    const path = safePath(directory, file.path.slice(1));
    if (existsSync(path)) {
      const expected = Buffer.from(file.contents);
      check(
        readBoundedFile(path, Math.max(INDEX_LIMIT, CHAPTER_LIMIT)).equals(expected),
        'Existing asset differs; refusing overwrite.',
      );
      existingFiles++;
    } else pending.push({ path, contents: file.contents });
  }
  if (!checkOnly)
    for (const file of pending) {
      safePath(root, dirname(file.path));
      mkdirSync(dirname(file.path), { recursive: true, mode: 0o700 });
      safePath(directory, relative(directory, file.path));
      writeFileSync(file.path, file.contents, { encoding: 'utf8', flag: 'wx', mode: 0o600 });
    }
  return {
    ...plan.summary,
    status: checkOnly ? 'validated-plan' : 'built',
    output: relative(root, directory),
    existingFiles,
    filesWritten: checkOnly ? 0 : pending.length,
  };
}
export function main(args) {
  check(
    args.length === 0 || (args.length === 1 && args[0] === '--check'),
    'Only --check is supported; no network, input, pin or output override exists.',
  );
  const plan = planScriptureAssets(readBundledScriptureAssetInputs());
  check(
    readBoundedFile(
      safePath(root, 'packages/core/fixtures/scripture-asset-indexes.json'),
      65536,
    ).equals(Buffer.from(plan.bookIndexPinsContents)),
    'Generated book-index pins differ from the checked-in runtime fixture.',
  );
  return writeScriptureAssetPlan(plan, outputDirectory, args[0] === '--check');
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    console.log(JSON.stringify(main(process.argv.slice(2)), null, 2));
  } catch (error) {
    console.error(
      error instanceof AssetError
        ? error.message
        : 'Offline scripture asset build failed; inputs and output were not trusted.',
    );
    process.exitCode = 1;
  }
}
