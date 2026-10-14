import {
  SCRIPTURE_ASSET_INDEX_SHA256,
  SCRIPTURE_ASSET_SOURCE_VERSION,
  SCRIPTURE_ASSET_MANIFEST_SHA256,
  SCRIPTURE_ABSENT_CANONICAL,
} from '../apps/api/src/scripture-assets-pin.ts';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import counts from '../packages/core/src/verse-counts.json' with { type: 'json' };
import { WEBP_SOURCE, SCRIPTURE_PARSING_POLICY } from '../packages/core/src/scripture-corpus.ts';
import {
  readScriptureAssetInputs,
  readBundledScriptureAssetInputs,
  main,
  planScriptureAssets,
  writeScriptureAssetPlan,
} from './build-scripture-assets.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sha = (data) => createHash('sha256').update(data).digest('hex');
const encode = (value) => Buffer.from(JSON.stringify(value) + '\n');
const coord = ({ sourceBook, sourceChapter, sourceVerse }) => ({
  sourceBook,
  sourceChapter,
  sourceVerse,
});
// Module-only synthetic identity: never an accepted production CLI manifest or Bible translation.
function syntheticArtifacts(version = 'synthetic-assets-test-v1', longChapter = false) {
  const verses = [];
  for (const [book, chapters] of Object.entries(counts))
    for (let c = 1; c <= chapters.length; c++) {
      for (let v = 1; v <= chapters[c - 1]; v++) {
        const text =
          (book === 'GEN' && c === 1) || (book === 'ACT' && c === 8 && v === 37)
            ? ''
            : longChapter && book === 'PSA' && c === 119
              ? 'x'.repeat(1000)
              : 'SYNTHETIC TEXT ONLY';
        verses.push({
          sourceId: 'webp',
          version,
          sourceBook: book,
          sourceChapter: c,
          sourceVerse: String(v),
          text,
          canonical: { book, chapter: c, verse: v },
          alignment: 'canonical-compatible',
          textStatus: text ? 'present' : 'empty',
          verification: 'literal-source',
          editorialReview: 'unreviewed',
        });
      }
      if (book === 'ROM' && c === 14)
        verses.push({
          sourceId: 'webp',
          version,
          sourceBook: book,
          sourceChapter: c,
          sourceVerse: '24',
          text: 'UNSUPPORTED SENTINEL',
          canonical: null,
          alignment: 'unsupported',
          textStatus: 'present',
          verification: 'literal-source',
          editorialReview: 'unreviewed',
        });
    }
  const verseBytes = Buffer.from(verses.map((v) => JSON.stringify(v)).join('\n') + '\n'),
    unversified = Buffer.alloc(0);
  const manifest = {
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
    version,
    fetchedAt: '2026-10-13T00:00:00.000Z',
    hash: {
      algorithm: 'sha256',
      archive: 'a'.repeat(64),
      xml: 'b'.repeat(64),
      verses: sha(verseBytes),
      unversified: sha(unversified),
    },
    archiveMember: WEBP_SOURCE.archiveMember,
    parserVersion: 'webp-usfx/1',
    bookCount: 66,
    verseCount: verses.length,
    nonemptyVerseCount: verses.filter((v) => v.text).length,
    canonicalCompatibleVerseCount: verses.filter((v) => v.canonical).length,
    unsupportedVerseCount: 1,
    unversifiedSectionCount: 0,
    books: Object.entries(counts).map(([book, chapters]) => {
      const rows = verses.filter((v) => v.sourceBook === book);
      return {
        book,
        chapterCount: chapters.length,
        verseCount: rows.length,
        nonemptyVerseCount: rows.filter((v) => v.text).length,
        canonicalCompatibleVerseCount: rows.filter((v) => v.canonical).length,
        unsupportedVerseCount: rows.filter((v) => !v.canonical).length,
      };
    }),
    excludedBooks: [],
    unsupportedVerses: verses.filter((v) => !v.canonical).map(coord),
    emptyVerses: verses.filter((v) => !v.text).map(coord),
    missingCanonicalVerses: [],
    excludedElementCounts: {},
    parsingPolicy: SCRIPTURE_PARSING_POLICY,
    verification: {
      sourceText: 'xml-sha256-verified',
      editorialReview: 'unreviewed',
      humanTextReview: false,
    },
  };
  const manifestBytes = encode(manifest);
  return {
    artifacts: { manifest: manifestBytes, verses: verseBytes, unversified },
    identities: [
      {
        corpusId: 'webp',
        edition: 'engwebp',
        sourceVersion: version,
        manifestSha256: sha(manifestBytes),
        language: 'en',
        referenceSystem: 'web-protestant',
      },
    ],
  };
}
const fixture = syntheticArtifacts();
const plan = planScriptureAssets(fixture.artifacts, fixture.identities);

test('assets are deterministic bounded chapter JSON with only literal compatible nonempty text', () => {
  const second = planScriptureAssets(fixture.artifacts, fixture.identities);
  assert.deepEqual(second.summary, plan.summary);
  assert.deepEqual(second.files, plan.files);
  assert.equal(plan.files.length, 1257);
  assert.equal(Object.keys(plan.index.chapters).length, 1189);
  assert.ok(plan.summary.indexBytes <= 262144);
  assert.ok(plan.summary.maxChapterBytes <= 65536);
  assert.equal(plan.summary.indexSha256, sha(plan.files.at(-1).contents));
  assert.equal(plan.summary.networkRequests, 0);
  assert.ok(plan.files.every((f) => !f.contents.includes('UNSUPPORTED SENTINEL')));
  assert.deepEqual(JSON.parse(plan.files.find((f) => f.path.endsWith('/GEN/1.json')).contents), {
    book: 'GEN',
    chapter: 1,
    verses: [],
  });
  assert.deepEqual(
    { ...plan.index.chapters['GEN:1'], path: undefined, sha256: undefined, bytes: undefined },
    {
      path: undefined,
      sha256: undefined,
      bytes: undefined,
      count: 0,
      firstVerse: null,
      lastVerse: null,
    },
  );
  const acts = JSON.parse(plan.files.find((f) => f.path.endsWith('/ACT/8.json')).contents);
  assert.ok(!acts.verses.some(([n]) => n === 37));
  for (const file of plan.files.filter((file) => /\/[A-Z0-9]{3}\/[0-9]+\.json$/.test(file.path))) {
    const chapter = JSON.parse(file.contents),
      entry = plan.index.chapters[`${chapter.book}:${chapter.chapter}`];
    assert.equal(entry.sha256, sha(file.contents));
    assert.equal(entry.bytes, Buffer.byteLength(file.contents));
    assert.equal(entry.count, chapter.verses.length);
  }
});
test('untrusted artifacts, fake plans and CLI override attempts are refused', () => {
  assert.throws(() => planScriptureAssets(fixture.artifacts), /pinned/);
  assert.throws(
    () =>
      planScriptureAssets(
        {
          ...fixture.artifacts,
          verses: Buffer.concat([fixture.artifacts.verses, Buffer.from('\n')]),
        },
        fixture.identities,
      ),
    /checksum/,
  );
  assert.throws(() => writeScriptureAssetPlan({ ...plan }), /validated/);
  assert.throws(() => main(['--output', '/tmp/escape']), /Only --check/);
  assert.throws(() => main(['--remote']), /Only --check/);
  assert.ok(
    Object.isFrozen(plan) && Object.isFrozen(plan.files) && Object.isFrozen(plan.index.chapters),
  );
});
test('writes are repeatable and reject changed files, symlinks and output escapes', () => {
  const directory = join(root, '.cache/scripture', `assets-test-${randomUUID()}`);
  mkdirSync(directory, { recursive: true });
  try {
    const output = join(directory, 'output');
    const preview = writeScriptureAssetPlan(plan, relative(root, output), true);
    assert.equal(preview.filesWritten, 0);
    assert.deepEqual(readdirSync(directory), []);
    const built = writeScriptureAssetPlan(plan, relative(root, output));
    assert.equal(built.filesWritten, 1257);
    assert.equal(writeScriptureAssetPlan(plan, relative(root, output)).filesWritten, 0);
    assert.equal(
      sha(readFileSync(join(output, plan.summary.indexPath.slice(1)))),
      plan.summary.indexSha256,
    );
    writeFileSync(join(output, plan.files[0].path.slice(1)), 'changed');
    assert.throws(
      () => writeScriptureAssetPlan(plan, relative(root, output)),
      /refusing overwrite/,
    );
    assert.throws(() => writeScriptureAssetPlan(plan, '../escape'), /escapes/);
    assert.throws(() => writeScriptureAssetPlan(plan, 'apps/api/assets'), /must stay/);
    const target = join(directory, 'target');
    mkdirSync(target);
    const linked = join(directory, 'linked');
    symlinkSync(target, linked, 'dir');
    assert.throws(() => writeScriptureAssetPlan(plan, relative(root, linked)), /Symbolic/);
    assert.deepEqual(readdirSync(target), []);
    const leafOutput = join(directory, 'leaf'),
      leaf = join(leafOutput, plan.files[0].path.slice(1));
    mkdirSync(dirname(leaf), { recursive: true });
    symlinkSync(join(directory, 'nonexistent'), leaf);
    assert.throws(() => writeScriptureAssetPlan(plan, relative(root, leafOutput)), /Symbolic/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('oversized chapter and index plans fail closed before writing', () => {
  const chapter = syntheticArtifacts('synthetic-assets-test-v1', true);
  assert.throws(
    () => planScriptureAssets(chapter.artifacts, chapter.identities),
    /Chapter exceeds/,
  );
  const index = syntheticArtifacts('x'.repeat(99));
  assert.throws(() => planScriptureAssets(index.artifacts, index.identities), /Index exceeds/);
});
test('input reader rejects symlinks and repository escapes', () => {
  const directory = join(root, '.cache/scripture', `assets-input-test-${randomUUID()}`);
  mkdirSync(directory, { recursive: true });
  try {
    symlinkSync(join(directory, 'not-present'), join(directory, 'manifest.json'));
    assert.throws(() => readScriptureAssetInputs(relative(root, directory)), /Symbolic/);
    assert.throws(() => readScriptureAssetInputs('../escape'), /escapes/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('real bundled corpus exactly matches pinned runtime index and canonical membership complement', () => {
  const real = planScriptureAssets(readBundledScriptureAssetInputs());
  assert.equal(real.summary.indexSha256, SCRIPTURE_ASSET_INDEX_SHA256);
  assert.equal(real.summary.sourceVersion, SCRIPTURE_ASSET_SOURCE_VERSION);
  assert.equal(real.summary.manifestSha256, SCRIPTURE_ASSET_MANIFEST_SHA256);
  assert.equal(real.summary.verseCount, 31095);
  assert.equal(
    real.bookIndexPinsContents,
    readFileSync(join(root, 'packages/core/fixtures/scripture-asset-indexes.json'), 'utf8'),
  );
  assert.equal(Object.keys(real.bookIndexPins).length, 66);
  for (const book of Object.keys(counts)) {
    const file = real.files.find((f) => f.path.endsWith(`/${book}/index.json`));
    const index = JSON.parse(file.contents);
    assert.equal(sha(file.contents), real.bookIndexPins[book].sha256);
    assert.equal(Buffer.byteLength(file.contents), real.bookIndexPins[book].bytes);
    assert.ok(real.bookIndexPins[book].bytes <= 65536);
    assert.deepEqual(
      Object.keys(index.chapters),
      counts[book].map((_, i) => `${book}:${i + 1}`),
    );
    for (const [key, chapter] of Object.entries(index.chapters))
      assert.deepEqual(chapter, real.index.chapters[key]);
  }
  const present = new Set(),
    absent = new Set(SCRIPTURE_ABSENT_CANONICAL);
  let total = 0;
  for (const file of real.files.filter((file) => /\/[A-Z0-9]{3}\/[0-9]+\.json$/.test(file.path))) {
    const chapter = JSON.parse(file.contents);
    for (const [number] of chapter.verses) {
      assert.ok(number >= 1 && number <= counts[chapter.book][chapter.chapter - 1]);
      const key = `${chapter.book}:${chapter.chapter}:${number}`;
      assert.ok(!present.has(key), `Duplicate ${key}`);
      present.add(key);
      total++;
    }
  }
  const actualAbsent = new Set();
  for (const [book, chapters] of Object.entries(counts))
    chapters.forEach((maximum, c) => {
      for (let v = 1; v <= maximum; v++) {
        const key = `${book}:${c + 1}:${v}`;
        assert.equal(present.has(key), !absent.has(key), key);
        if (!present.has(key)) actualAbsent.add(key);
      }
    });
  assert.equal(total, 31095);
  assert.equal(present.size, 31095);
  assert.deepEqual(actualAbsent, absent);
});
