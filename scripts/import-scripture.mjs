#!/usr/bin/env node
/** Pinned local corpus ingestion. No network, auth, remote or overwrite mode. */
import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { z } from 'zod';
import counts from '../packages/core/src/verse-counts.json' with { type: 'json' };
import { WEBP_SOURCE, SCRIPTURE_PARSING_POLICY } from '../packages/core/src/scripture-corpus.ts';
import { TRUSTED_PRIMARY_TEXT_MANIFESTS } from '../packages/ai-harness/src/primary-text-manifests.ts';
import { LOCAL_WRANGLER_ENV, validateScaffoldConfig } from './config.mjs';
import { findDatabase, inspectDatabase } from './local-db.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const preparedDirectory = '.cache/scripture/prepared';
const defaultState = 'apps/api/.wrangler/state';
const books = Object.keys(counts);
const validatedCorpora = new WeakSet();
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const hashSchema = z.string().regex(/^[a-f0-9]{64}$/);
const labelSchema = z
  .string()
  .regex(/^[1-9][0-9]{0,2}(?:[a-z]|-[1-9][0-9]{0,2}[a-z]?)?$/)
  .max(12);
const coordinateSchema = z
  .object({
    book: z.enum(books),
    chapter: z.number().int().min(1).max(150),
    verse: z.number().int().min(1).max(176),
  })
  .strict();
const sourceCoordinateSchema = z
  .object({
    sourceBook: z.enum(books),
    sourceChapter: z.number().int().min(1).max(150),
    sourceVerse: labelSchema,
  })
  .strict();
const textSchema = z
  .string()
  .refine(
    (text) =>
      Buffer.byteLength(text) <= 16384 &&
      !/[\u0000-\u001f\u007f]/.test(text) &&
      text === text.replace(/ +/g, ' ').replace(/^ +| +$/g, '') &&
      text.isWellFormed(),
  );
const verseSchema = sourceCoordinateSchema
  .extend({
    sourceId: z.literal('webp'),
    version: z.string().min(1).max(100),
    text: textSchema,
    canonical: coordinateSchema.nullable(),
    alignment: z.enum(['canonical-compatible', 'unsupported']),
    textStatus: z.enum(['present', 'empty']),
    verification: z.literal('literal-source'),
    editorialReview: z.literal('unreviewed'),
  })
  .strict();
const unversifiedSchema = z
  .object({
    sourceId: z.literal('webp'),
    version: z.string().min(1).max(100),
    sourceBook: z.enum(books),
    sourceChapter: z.number().int().min(1).max(150),
    marker: z.literal('d'),
    afterSourceVerse: labelSchema.nullable(),
    text: textSchema,
    verification: z.literal('literal-source'),
    editorialReview: z.literal('unreviewed'),
  })
  .strict();
const nonnegative = z.number().int().min(0).max(40000);
const bookSchema = z
  .object({
    book: z.enum(books),
    chapterCount: z.number().int().min(1).max(150),
    verseCount: nonnegative,
    nonemptyVerseCount: nonnegative,
    canonicalCompatibleVerseCount: nonnegative,
    unsupportedVerseCount: nonnegative,
  })
  .strict();
const manifestSchema = z
  .object({
    schemaVersion: z.literal(1),
    corpusId: z.literal('webp'),
    edition: z.literal('engwebp'),
    referenceSystem: z.literal('web-protestant'),
    sourceId: z.literal('webp'),
    title: z.literal(WEBP_SOURCE.title),
    sourceURL: z.literal(WEBP_SOURCE.sourceURL),
    licenseURL: z.literal(WEBP_SOURCE.licenseURL),
    license: z.literal('public-domain'),
    language: z.literal('en'),
    version: z.string().regex(/^[a-z0-9][a-z0-9._-]{1,99}$/),
    fetchedAt: z.iso.datetime(),
    hash: z
      .object({
        algorithm: z.literal('sha256'),
        archive: hashSchema,
        xml: hashSchema,
        verses: hashSchema,
        unversified: hashSchema,
      })
      .strict(),
    archiveMember: z.literal(WEBP_SOURCE.archiveMember),
    parserVersion: z.literal('webp-usfx/1'),
    bookCount: z.literal(66),
    verseCount: z.number().int().min(66).max(40000),
    nonemptyVerseCount: nonnegative,
    canonicalCompatibleVerseCount: nonnegative,
    unsupportedVerseCount: nonnegative,
    unversifiedSectionCount: nonnegative,
    books: z.array(bookSchema).length(66),
    excludedBooks: z
      .array(
        z
          .object({ book: z.string().regex(/^[A-Z0-9]{3}$/), verseMarkerCount: nonnegative })
          .strict(),
      )
      .max(100),
    unsupportedVerses: z.array(sourceCoordinateSchema).max(40000),
    emptyVerses: z.array(sourceCoordinateSchema).max(40000),
    missingCanonicalVerses: z.array(coordinateSchema).max(40000),
    excludedElementCounts: z.record(z.string(), nonnegative),
    parsingPolicy: z
      .object(
        Object.fromEntries(
          Object.entries(SCRIPTURE_PARSING_POLICY).map(([key, value]) => [key, z.literal(value)]),
        ),
      )
      .strict(),
    verification: z
      .object({
        sourceText: z.literal('xml-sha256-verified'),
        editorialReview: z.literal('unreviewed'),
        humanTextReview: z.literal(false),
      })
      .strict(),
  })
  .strict();

class ImportError extends Error {}
function check(condition, message) {
  if (!condition) throw new ImportError(message);
}
function same(actual, expected, message) {
  check(JSON.stringify(actual) === JSON.stringify(expected), message);
}
function parse(schema, value, message) {
  const result = schema.safeParse(value);
  check(result.success, message);
  return result.data;
}
function json(bytes) {
  try {
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    throw new ImportError('Invalid UTF-8 JSON input.');
  }
}
const key = (row) => `${row.sourceBook}:${row.sourceChapter}:${row.sourceVerse}`;
const sourceCoordinate = ({ sourceBook, sourceChapter, sourceVerse }) => ({
  sourceBook,
  sourceChapter,
  sourceVerse,
});
const canonical = (row) => {
  const number = /^[1-9][0-9]*$/.test(row.sourceVerse) ? Number(row.sourceVerse) : NaN;
  return Number.isSafeInteger(number) &&
    number <= (counts[row.sourceBook]?.[row.sourceChapter - 1] ?? 0)
    ? { book: row.sourceBook, chapter: row.sourceChapter, verse: number }
    : null;
};

function parseNdjson(bytes, schema, limit) {
  check(bytes.length <= 64 * 1024 * 1024, 'Prepared artifact exceeds its size limit.');
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new ImportError('Invalid UTF-8 artifact.');
  }
  if (!text) return [];
  check(
    text.endsWith('\n') && !text.includes('\r'),
    'Require canonical newline-terminated NDJSON.',
  );
  const lines = text.slice(0, -1).split('\n');
  check(lines.length <= limit, 'Too many prepared rows.');
  return lines.map((line) => {
    check(Buffer.byteLength(line) <= 128 * 1024 && line.length > 0, 'Invalid prepared row length.');
    return parse(schema, json(Buffer.from(line)), 'Invalid prepared row schema or text bounds.');
  });
}

/** The injected identity list is a module-only test seam; CLI has no override. */
export function validateArtifacts(artifacts, trustedIdentities = TRUSTED_PRIMARY_TEXT_MANIFESTS) {
  check(artifacts.manifest.length <= 262144, 'Manifest exceeds the storage bound.');
  const manifestSha256 = sha256(artifacts.manifest);
  check(
    trustedIdentities.some((identity) => identity.manifestSha256 === manifestSha256),
    'Manifest is not an independently pinned trusted identity.',
  );
  const manifest = parse(
    manifestSchema,
    json(artifacts.manifest),
    'Invalid corpus manifest schema.',
  );
  check(
    trustedIdentities.some(
      (identity) =>
        identity.manifestSha256 === manifestSha256 &&
        identity.corpusId === manifest.corpusId &&
        identity.edition === manifest.edition &&
        identity.sourceVersion === manifest.version &&
        identity.language === manifest.language &&
        identity.referenceSystem === manifest.referenceSystem,
    ),
    'Pinned manifest identity does not match the prepared corpus.',
  );
  check(sha256(artifacts.verses) === manifest.hash.verses, 'Verse artifact checksum mismatch.');
  check(
    sha256(artifacts.unversified) === manifest.hash.unversified,
    'Unversified artifact checksum mismatch.',
  );
  const verses = parseNdjson(artifacts.verses, verseSchema, 40000);
  const unversified = parseNdjson(artifacts.unversified, unversifiedSchema, 40000);
  same(
    manifest.books.map((book) => book.book),
    books,
    'Require exactly all 66 books in canonical order.',
  );
  const seen = new Set();
  let previousBook = -1;
  let previousChapter = 0;
  for (const row of verses) {
    check(row.version === manifest.version, 'Verse version differs from manifest.');
    check(!seen.has(key(row)), 'Duplicate source coordinate.');
    seen.add(key(row));
    const bookIndex = books.indexOf(row.sourceBook);
    check(
      bookIndex >= previousBook &&
        (bookIndex !== previousBook || row.sourceChapter >= previousChapter),
      'Prepared verses are not in deterministic book/chapter order.',
    );
    previousBook = bookIndex;
    previousChapter = row.sourceChapter;
    same(
      row.canonical,
      canonical(row),
      'Canonical coordinate must preserve the exact supported source coordinate.',
    );
    check(
      row.alignment === (row.canonical ? 'canonical-compatible' : 'unsupported'),
      'Alignment does not match the source coordinate.',
    );
    check(
      row.textStatus === (row.text ? 'present' : 'empty'),
      'Text status does not match the source text.',
    );
  }
  const computedBooks = books.map((book) => {
    const rows = verses.filter((row) => row.sourceBook === book);
    return {
      book,
      chapterCount: new Set(rows.map((row) => row.sourceChapter)).size,
      verseCount: rows.length,
      nonemptyVerseCount: rows.filter((row) => row.textStatus === 'present').length,
      canonicalCompatibleVerseCount: rows.filter((row) => row.alignment === 'canonical-compatible')
        .length,
      unsupportedVerseCount: rows.filter((row) => row.alignment === 'unsupported').length,
    };
  });
  same(computedBooks, manifest.books, 'Book coverage or counts differ from manifest.');
  check(
    verses.length === manifest.verseCount &&
      unversified.length === manifest.unversifiedSectionCount,
    'Prepared row counts differ from manifest.',
  );
  check(
    verses.filter((row) => row.textStatus === 'present').length === manifest.nonemptyVerseCount &&
      verses.filter((row) => row.canonical).length === manifest.canonicalCompatibleVerseCount &&
      verses.filter((row) => !row.canonical).length === manifest.unsupportedVerseCount,
    'Prepared coverage totals differ from manifest.',
  );
  same(
    verses.filter((row) => !row.canonical).map(sourceCoordinate),
    manifest.unsupportedVerses,
    'Unsupported coordinate report differs from artifact.',
  );
  same(
    verses.filter((row) => !row.text).map(sourceCoordinate),
    manifest.emptyVerses,
    'Empty coordinate report differs from artifact.',
  );
  const missing = [];
  for (const book of books)
    for (let c = 1; c <= counts[book].length; c++)
      for (let v = 1; v <= counts[book][c - 1]; v++)
        if (!seen.has(`${book}:${c}:${v}`)) missing.push({ book, chapter: c, verse: v });
  same(
    missing,
    manifest.missingCanonicalVerses,
    'Missing-coordinate report differs from artifact.',
  );
  for (const row of unversified) {
    check(row.version === manifest.version, 'Unversified version differs from manifest.');
    check(
      verses.some(
        (verse) => verse.sourceBook === row.sourceBook && verse.sourceChapter === row.sourceChapter,
      ),
      'Unversified section has no source chapter.',
    );
    if (row.afterSourceVerse !== null)
      check(
        seen.has(`${row.sourceBook}:${row.sourceChapter}:${row.afterSourceVerse}`),
        'Unversified anchor has no source verse.',
      );
  }
  const result = {
    manifest,
    manifestSha256,
    manifestText: new TextDecoder().decode(artifacts.manifest),
    verses,
    unversified,
  };
  const freeze = (value) => {
    if (value && typeof value === 'object') {
      for (const child of Object.values(value)) freeze(child);
      Object.freeze(value);
    }
    return value;
  };
  validatedCorpora.add(result);
  return freeze(result);
}

export function parseImportArguments(args) {
  const options = { execute: false, state: defaultState };
  const seen = new Set();
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    check(!seen.has(flag), 'Duplicate import option.');
    seen.add(flag);
    if (flag === '--execute') options.execute = true;
    else if (flag === '--persist-to') {
      const value = args[++i];
      check(
        typeof value === 'string' && /^\.cache\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*$/.test(value),
        'Persisted state must be a simple in-repository .cache path.',
      );
      options.state = value;
    } else
      throw new ImportError(
        'Only --execute and optional --persist-to are accepted. No remote or identity override exists.',
      );
  }
  return options;
}

function safePath(path) {
  const absolute = resolve(root, path);
  check(absolute.startsWith(root + '/'), 'Import paths must stay within this repository.');
  let current = root;
  for (const component of relative(root, absolute).split('/')) {
    current = join(current, component);
    let info;
    try {
      info = lstatSync(current);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    if (info)
      check(
        !info.isSymbolicLink() && (info.isDirectory() || (info.isFile() && info.nlink === 1)),
        'Require ordinary, non-linked import paths.',
      );
  }
  return absolute;
}

function artifactsFromDisk() {
  return Object.fromEntries(
    [
      ['manifest', 'manifest.json', 262144],
      ['verses', 'verses.ndjson', 64 * 1024 * 1024],
      ['unversified', 'unversified.ndjson', 64 * 1024 * 1024],
    ].map(([key, name, max]) => {
      const path = safePath(`${preparedDirectory}/${name}`);
      check(
        lstatSync(path).isFile() && lstatSync(path).size <= max,
        'Missing or oversized prepared artifact.',
      );
      return [key, readFileSync(path)];
    }),
  );
}

const sqlValue = (value) =>
  value === null
    ? 'NULL'
    : typeof value === 'number'
      ? String(value)
      : "'" + value.replaceAll("'", "''") + "'";
const verseColumns = [
  'corpus_id',
  'corpus_version',
  'source_id',
  'source_book',
  'source_chapter',
  'source_verse',
  'book',
  'chapter',
  'verse',
  'text',
  'alignment',
  'text_status',
];
function storedVerse(row) {
  return {
    corpus_id: row.sourceId,
    corpus_version: row.version,
    source_id: row.sourceId + ':' + key(row),
    source_book: row.sourceBook,
    source_chapter: row.sourceChapter,
    source_verse: row.sourceVerse,
    book: row.canonical?.book ?? null,
    chapter: row.canonical?.chapter ?? null,
    verse: row.canonical?.verse ?? null,
    text: row.text,
    alignment: row.alignment,
    text_status: row.textStatus,
  };
}

function inspectStored(path, corpus, requireComplete = false) {
  const db = new DatabaseSync(path, { readOnly: true, allowExtension: false });
  try {
    db.exec('PRAGMA query_only=ON; BEGIN;');
    const record = db
      .prepare('SELECT * FROM scripture_corpora WHERE id=? AND version=?')
      .get(corpus.manifest.corpusId, corpus.manifest.version);
    const active = db
      .prepare('SELECT version FROM scripture_corpora WHERE id=? AND active=1 AND version<>?')
      .get(corpus.manifest.corpusId, corpus.manifest.version);
    check(!active, 'Another corpus revision is active; no revision was deactivated.');
    const rows = db
      .prepare(
        `SELECT ${verseColumns.join(',')} FROM scripture_verses WHERE corpus_id=? AND corpus_version=?`,
      )
      .all(corpus.manifest.corpusId, corpus.manifest.version);
    if (record) {
      const expected = {
        id: corpus.manifest.corpusId,
        version: corpus.manifest.version,
        edition: corpus.manifest.edition,
        language: corpus.manifest.language,
        license: corpus.manifest.license,
        manifest_sha256: corpus.manifestSha256,
        manifest_json: corpus.manifestText,
        expected_verses: corpus.verses.length,
      };
      same(
        Object.fromEntries(Object.keys(expected).map((key) => [key, record[key]])),
        expected,
        'Existing corpus identity conflicts with the prepared input.',
      );
      check(
        record.rights_status !== 'revoked',
        'Existing revision is revoked; import cannot reapprove it.',
      );
      if (record.state === 'ready')
        check(
          record.rights_status === 'approved' && record.active === 1,
          'Existing ready revision is inactive or unapproved; policy is preserved.',
        );
      else
        check(
          record.rights_status === 'pending' && record.active === 0,
          'Unexpected staging policy; import stopped.',
        );
    } else check(rows.length === 0, 'Orphaned corpus rows found.');
    const expectedRows = new Map(
      corpus.verses.map((row) => [storedVerse(row).source_id, storedVerse(row)]),
    );
    for (const row of rows) {
      same(
        { ...row },
        expectedRows.get(row.source_id),
        'Stored verse conflicts with immutable prepared input.',
      );
      expectedRows.delete(row.source_id);
    }
    if (requireComplete || record?.state === 'ready')
      check(expectedRows.size === 0, 'Corpus rows are incomplete; revision remains unsealed.');
    db.exec('COMMIT');
    return { record, missing: [...expectedRows.values()] };
  } finally {
    db.close();
  }
}

export function buildStagingStatements(corpus, existing) {
  const statements = [];
  const m = corpus.manifest;
  if (!existing.record)
    statements.push(
      `INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at) VALUES(${[m.corpusId, m.version, m.edition, m.language, m.license, corpus.manifestSha256, corpus.manifestText, corpus.verses.length, Math.floor(Date.now() / 1000)].map(sqlValue).join(',')});`,
    );
  const prefix = `INSERT INTO scripture_verses(${verseColumns.join(',')}) VALUES`;
  let statement = prefix;
  for (const row of existing.missing) {
    const tuple = '(' + verseColumns.map((name) => sqlValue(row[name])).join(',') + ')';
    if (Buffer.byteLength(statement + ',' + tuple + ';') >= 80000 && statement !== prefix) {
      statements.push(statement + ';');
      statement = prefix;
    }
    statement += (statement === prefix ? '' : ',') + tuple;
  }
  if (statement !== prefix) statements.push(statement + ';');
  for (const sql of statements)
    check(Buffer.byteLength(sql) < 100000, 'Prepared SQL statement exceeds the 100 KB D1 bound.');
  return statements;
}

function runSqlFile(state, path) {
  const result = spawnSync(
    process.execPath,
    [
      'scripts/wrangler.mjs',
      'd1',
      'execute',
      'bible-companion',
      '--local',
      '--config',
      'apps/api/wrangler.jsonc',
      ...(state === defaultState ? [] : ['--persist-to', state]),
      '--file',
      path,
    ],
    {
      cwd: root,
      encoding: 'utf8',
      timeout: 120000,
      maxBuffer: 1024 * 1024,
      env: { ...process.env, CI: 'true', ...LOCAL_WRANGLER_ENV },
    },
  );
  check(
    !result.error && result.status === 0,
    'Local D1 import did not complete. Staging stays unapproved; inspect locally before retrying.',
  );
}

/** Module injection is only for synthetic isolated tests; production CLI always loads pinned files. */
export function importValidatedCorpus(corpus, options = {}) {
  check(
    validatedCorpora.has(corpus),
    'Only fully validated immutable corpus input can be imported.',
  );
  const state = options.state ?? defaultState;
  check(
    state === defaultState || /^\.cache\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*$/.test(state),
    'Invalid local state path.',
  );
  if (!options.execute) {
    const statements = buildStagingStatements(corpus, { missing: corpus.verses.map(storedVerse) });
    return {
      status: 'plan',
      localOnly: true,
      state,
      corpus: corpus.manifest.corpusId,
      version: corpus.manifest.version,
      manifestSha256: corpus.manifestSha256,
      books: corpus.manifest.bookCount,
      verses: corpus.verses.length,
      unversifiedSectionsValidated: corpus.unversified.length,
      maximumStagingStatements: statements.length,
      writes: 0,
      requiredMigration: '0017_scripture_corpus.sql',
    };
  }
  const config = validateScaffoldConfig(json(readFileSync(safePath('apps/api/wrangler.jsonc'))));
  check(
    config.vars.ENVIRONMENT === 'development',
    'Only the reviewed local development configuration is supported.',
  );
  const path = findDatabase(root, state);
  const diagnostic = inspectDatabase(path);
  check(
    diagnostic.schemaMatchesMigrations &&
      diagnostic.migrations.some((migration) => migration.name === '0017_scripture_corpus.sql'),
    'Require the current, schema-verified local scripture migration before import.',
  );
  const existing = inspectStored(path, corpus);
  if (existing.record?.state === 'ready')
    return {
      status: 'already-ready',
      corpus: corpus.manifest.corpusId,
      version: corpus.manifest.version,
      verses: corpus.verses.length,
      writes: 0,
    };
  const statements = buildStagingStatements(corpus, existing);
  const summary = {
    status: options.execute ? 'ready' : 'plan',
    corpus: corpus.manifest.corpusId,
    version: corpus.manifest.version,
    books: corpus.manifest.bookCount,
    verses: corpus.verses.length,
    missingRows: existing.missing.length,
    unversifiedSectionsValidated: corpus.unversified.length,
    statements: statements.length + 1,
    localOnly: true,
  };
  if (!options.execute) return summary;
  const parent = safePath('.cache/scripture/imports');
  mkdirSync(parent, { recursive: true, mode: 0o700 });
  const directory = join(parent, randomUUID());
  mkdirSync(directory, { mode: 0o700 });
  // Bounded files also bound Wrangler result/log buffers; each batch may commit only staging rows.
  for (let i = 0; i < statements.length; i += 25) {
    const file = join(directory, `stage-${String(i / 25).padStart(4, '0')}.sql`);
    writeFileSync(file, statements.slice(i, i + 25).join('\n') + '\n', { mode: 0o600, flag: 'wx' });
    runSqlFile(state, relative(root, file));
  }
  inspectStored(path, corpus, true);
  const seal = `UPDATE scripture_corpora SET state='ready',rights_status='approved',active=1 WHERE id=${sqlValue(corpus.manifest.corpusId)} AND version=${sqlValue(corpus.manifest.version)} AND manifest_sha256=${sqlValue(corpus.manifestSha256)} AND state='staging' AND rights_status='pending' AND active=0;`;
  const file = join(directory, 'seal.sql');
  writeFileSync(file, seal + '\n', { mode: 0o600, flag: 'wx' });
  runSqlFile(state, relative(root, file));
  const final = inspectStored(path, corpus, true);
  check(
    final.record?.state === 'ready' &&
      final.record.active === 1 &&
      final.record.rights_status === 'approved',
    'Corpus did not become ready; no successful activation is claimed.',
  );
  return summary;
}

export function main(args) {
  const options = parseImportArguments(args);
  const corpus = validateArtifacts(artifactsFromDisk());
  return importValidatedCorpus(corpus, options);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    console.log(JSON.stringify(main(process.argv.slice(2)), null, 2));
  } catch (error) {
    console.error(
      error instanceof ImportError
        ? error.message
        : 'Local scripture import failed. No private database contents or raw SQL were printed.',
    );
    process.exitCode = 1;
  }
}
