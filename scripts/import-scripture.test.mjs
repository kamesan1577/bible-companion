import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import counts from '../packages/core/src/verse-counts.json' with { type: 'json' };
import { WEBP_SOURCE, SCRIPTURE_PARSING_POLICY } from '../packages/core/src/scripture-corpus.ts';
import {
  buildStagingStatements,
  importValidatedCorpus,
  parseImportArguments,
  validateArtifacts,
} from './import-scripture.mjs';
import { findDatabase, repositoryRoot as root } from './local-db.mjs';
import { LOCAL_WRANGLER_ENV } from './config.mjs';

const hash = (value) => createHash('sha256').update(value).digest('hex');
const encode = (value) => Buffer.from(JSON.stringify(value));
const ndjson = (rows) =>
  Buffer.from(rows.map((row) => JSON.stringify(row)).join('\n') + (rows.length ? '\n' : ''));
const version = 'synthetic-local-import-test-v1';
const syntheticText = "SYNTHETIC TEST ONLY: O'Brien; this is not a Bible translation.";

// Full synthetic coordinate coverage keeps the production 66-book validator unchanged.
// No publisher text, downloads, external keys or test-only production CLI switches.
function syntheticFixture() {
  const verses = [];
  for (const [book, chapters] of Object.entries(counts))
    for (let c = 1; c <= chapters.length; c++)
      for (let v = 1; v <= chapters[c - 1]; v++)
        verses.push({
          sourceId: 'webp',
          version,
          sourceBook: book,
          sourceChapter: c,
          sourceVerse: String(v),
          text: book === 'GEN' && c === 1 && v === 2 ? '' : syntheticText,
          canonical: { book, chapter: c, verse: v },
          alignment: 'canonical-compatible',
          textStatus: book === 'GEN' && c === 1 && v === 2 ? 'empty' : 'present',
          verification: 'literal-source',
          editorialReview: 'unreviewed',
        });
  const unversified = [
    {
      sourceId: 'webp',
      version,
      sourceBook: 'PSA',
      sourceChapter: 1,
      marker: 'd',
      afterSourceVerse: null,
      text: 'SYNTHETIC UNVERSIFIED TEST ONLY',
      verification: 'literal-source',
      editorialReview: 'unreviewed',
    },
  ];
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
      archive: '0'.repeat(64),
      xml: '0'.repeat(64),
      verses: '',
      unversified: '',
    },
    archiveMember: WEBP_SOURCE.archiveMember,
    parserVersion: 'webp-usfx/1',
    bookCount: 66,
    verseCount: verses.length,
    nonemptyVerseCount: verses.length - 1,
    canonicalCompatibleVerseCount: verses.length,
    unsupportedVerseCount: 0,
    unversifiedSectionCount: unversified.length,
    books: Object.entries(counts).map(([book, chapters]) => {
      const n = chapters.reduce((sum, value) => sum + value, 0);
      return {
        book,
        chapterCount: chapters.length,
        verseCount: n,
        nonemptyVerseCount: n - (book === 'GEN' ? 1 : 0),
        canonicalCompatibleVerseCount: n,
        unsupportedVerseCount: 0,
      };
    }),
    excludedBooks: [],
    unsupportedVerses: [],
    emptyVerses: [{ sourceBook: 'GEN', sourceChapter: 1, sourceVerse: '2' }],
    missingCanonicalVerses: [],
    excludedElementCounts: {},
    parsingPolicy: SCRIPTURE_PARSING_POLICY,
    verification: {
      sourceText: 'xml-sha256-verified',
      editorialReview: 'unreviewed',
      humanTextReview: false,
    },
  };
  return { manifest, verses, unversified };
}
const fixture = syntheticFixture();
function prepare(f = fixture) {
  const verses = ndjson(f.verses),
    unversified = ndjson(f.unversified);
  const manifest = encode({
    ...f.manifest,
    hash: { ...f.manifest.hash, verses: hash(verses), unversified: hash(unversified) },
  });
  const trusted = [
    {
      corpusId: 'webp',
      edition: 'engwebp',
      manifestSha256: hash(manifest),
      sourceVersion: f.manifest.version,
      language: 'en',
      referenceSystem: 'web-protestant',
    },
  ];
  return { artifacts: { manifest, verses, unversified }, trusted };
}
const prepared = prepare();
const valid = () => validateArtifacts(prepared.artifacts, prepared.trusted);

test('default plan requires no database and exposes no production identity override', () => {
  assert.deepEqual(parseImportArguments([]), { execute: false, state: 'apps/api/.wrangler/state' });
  assert.deepEqual(parseImportArguments(['--execute', '--persist-to', '.cache/test-scripture']), {
    execute: true,
    state: '.cache/test-scripture',
  });
  for (const args of [
    ['--remote'],
    ['--execute=false'],
    ['--execute', '--execute'],
    ['--manifest', 'x'],
    ['--allowlist', 'x'],
    ['--config', 'remote.json'],
    ['--persist-to'],
    ['--persist-to', '/tmp/state'],
    ['--persist-to', '.cache/../state'],
  ])
    assert.throws(() => parseImportArguments(args));
  const corpus = valid();
  const plan = importValidatedCorpus(corpus);
  assert.equal(plan.status, 'plan');
  assert.equal(plan.writes, 0);
  assert.equal(plan.books, 66);
  assert.equal(plan.verses, fixture.verses.length);
  assert.equal(plan.unversifiedSectionsValidated, 1);
  assert.throws(() => importValidatedCorpus({ ...corpus }, { execute: true }), /fully validated/);
  assert.throws(() => {
    corpus.verses[0].text = 'changed';
  }, TypeError);
});

test('untrusted manifest, mutated manifest bytes and artifact hash mismatch fail before database access', () => {
  assert.throws(() => validateArtifacts(prepared.artifacts), /not an independently pinned/);
  assert.throws(
    () =>
      validateArtifacts(
        {
          ...prepared.artifacts,
          manifest: Buffer.concat([prepared.artifacts.manifest, Buffer.from(' ')]),
        },
        prepared.trusted,
      ),
    /not an independently pinned/,
  );
  for (const name of ['verses', 'unversified'])
    assert.throws(
      () =>
        validateArtifacts(
          { ...prepared.artifacts, [name]: Buffer.from('corrupt') },
          prepared.trusted,
        ),
      /checksum mismatch/,
    );
  const wrong = [{ ...prepared.trusted[0], sourceVersion: 'other' }];
  assert.throws(() => validateArtifacts(prepared.artifacts, wrong), /identity does not match/);
});

test('every row is validated independently of a supplied test identity', () => {
  for (const [patch, pattern] of [
    [{ canonical: { book: 'GEN', chapter: 1, verse: 2 } }, /Canonical coordinate/],
    [{ text: 'x'.repeat(16385) }, /row schema/],
    [{ textStatus: 'empty' }, /Text status/],
    [{ sourceChapter: 151 }, /row schema/],
    [{ unrequested: true }, /row schema/],
    [{ version: 'other' }, /Verse version/],
  ]) {
    const f = {
      ...fixture,
      verses: [{ ...fixture.verses[0], ...patch }, ...fixture.verses.slice(1)],
    };
    const p = prepare(f);
    assert.throws(() => validateArtifacts(p.artifacts, p.trusted), pattern);
  }
  const p = prepare({ ...fixture, verses: [fixture.verses[0], ...fixture.verses] });
  assert.throws(() => validateArtifacts(p.artifacts, p.trusted), /Duplicate/);
});

test('manifest coverage and unversified anchors cannot silently become invented verses', () => {
  for (const patch of [
    { bookCount: 65 },
    { books: fixture.manifest.books.slice(1) },
    { verseCount: fixture.verses.length - 1 },
    { emptyVerses: [] },
  ]) {
    const p = prepare({ ...fixture, manifest: { ...fixture.manifest, ...patch } });
    assert.throws(() => validateArtifacts(p.artifacts, p.trusted));
  }
  const p = prepare({
    ...fixture,
    unversified: [{ ...fixture.unversified[0], afterSourceVerse: '999' }],
  });
  assert.throws(() => validateArtifacts(p.artifacts, p.trusted), /anchor/);
});

function createLocalSqliteState(t) {
  const state = '.cache/scripture-conflict-test-' + randomUUID();
  const directory = join(root, state, 'v3/d1/miniflare-D1DatabaseObject');
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  t.after(() => rmSync(join(root, state), { recursive: true, force: true }));
  const path = join(directory, 'a'.repeat(64) + '.sqlite');
  const db = new DatabaseSync(path);
  db.exec(
    'PRAGMA foreign_keys=ON; CREATE TABLE d1_migrations(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL UNIQUE,applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);',
  );
  for (const name of readdirSync(join(root, 'apps/api/migrations'))
    .filter((name) => name.endsWith('.sql'))
    .sort()) {
    db.exec(readFileSync(join(root, 'apps/api/migrations', name), 'utf8'));
    db.prepare('INSERT INTO d1_migrations(name) VALUES(?)').run(name);
  }
  return { state, db };
}
function initializeRecord(db, corpus) {
  db.prepare(
    'INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at) VALUES(?,?,?,?,?,?,?,?,?)',
  ).run(
    'webp',
    corpus.manifest.version,
    'engwebp',
    'en',
    'public-domain',
    corpus.manifestSha256,
    corpus.manifestText,
    corpus.verses.length,
    1,
  );
}

test('conflicting immutable staging data fails closed before a D1 write', (t) => {
  const { state, db } = createLocalSqliteState(t);
  const corpus = valid();
  initializeRecord(db, corpus);
  db.prepare(
    "INSERT INTO scripture_verses VALUES('webp',?,'webp:GEN:1:1','GEN',1,'1','GEN',1,1,'wrong immutable text','canonical-compatible','present')",
  ).run(version);
  db.close();
  assert.throws(
    () => importValidatedCorpus(corpus, { state, execute: true }),
    /Stored verse conflicts/,
  );
  const check = new DatabaseSync(findDatabase(root, state), { readOnly: true });
  assert.equal(check.prepare('SELECT state FROM scripture_corpora').get().state, 'staging');
  assert.equal(check.prepare('SELECT COUNT(*) AS n FROM scripture_verses').get().n, 1);
  check.close();
});

test(
  'actual isolated local D1 resumes staged synthetic rows, seals atomically and reruns without writes',
  { timeout: 180000 },
  (t) => {
    const state = '.cache/scripture-import-test-' + randomUUID();
    const directory = join(root, state);
    mkdirSync(directory, { mode: 0o700 });
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const denied = join(directory, 'external-attempt');
    const guard = join(directory, 'network-guard.cjs');
    writeFileSync(
      guard,
      `
    const fs=require('node:fs'),net=require('node:net'),dns=require('node:dns'),tls=require('node:tls');
    function check(host){if(host===undefined||['localhost','127.0.0.1','::1'].includes(host))return;fs.writeFileSync(${JSON.stringify(denied)},'blocked-before-connect');throw Error('External calls forbidden in importer test');}
    function checkArgs(args){if(Array.isArray(args[0]))return checkArgs(args[0]);if(typeof args[0]==='object')check(args[0].host||args[0].hostname||args[0].servername);else if(typeof args[1]==='string')check(args[1]);}
    const connect=net.Socket.prototype.connect;net.Socket.prototype.connect=function(...args){checkArgs(args);return connect.apply(this,args)};
    const lookup=dns.lookup;dns.lookup=function(host,...args){check(host);return lookup.call(this,host,...args)};
    const secure=tls.connect;tls.connect=function(...args){checkArgs(args);return secure.apply(this,args)};
  `,
      { mode: 0o600 },
    );
    const previous = process.env.NODE_OPTIONS;
    process.env.NODE_OPTIONS = '--require=' + guard;
    t.after(() => {
      if (previous === undefined) delete process.env.NODE_OPTIONS;
      else process.env.NODE_OPTIONS = previous;
    });
    const migrated = spawnSync(
      process.execPath,
      [
        'scripts/wrangler.mjs',
        'd1',
        'migrations',
        'apply',
        'bible-companion',
        '--local',
        '--config',
        'apps/api/wrangler.jsonc',
        '--persist-to',
        state,
      ],
      {
        cwd: root,
        encoding: 'utf8',
        timeout: 60000,
        maxBuffer: 1024 * 1024,
        env: { ...process.env, CI: 'true', ...LOCAL_WRANGLER_ENV },
      },
    );
    assert.equal(migrated.status, 0, 'Local D1 migration must succeed');
    const path = findDatabase(root, state);
    const db = new DatabaseSync(path);
    const corpus = valid();
    initializeRecord(db, corpus);
    db.exec(
      "INSERT INTO users(id,display_name,role,created_at) VALUES('private-sentinel','PRIVATE READING SENTINEL','member',1)",
    );
    const first = corpus.verses[0];
    db.prepare('INSERT INTO scripture_verses VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').run(
      'webp',
      version,
      'webp:GEN:1:1',
      'GEN',
      1,
      '1',
      'GEN',
      1,
      1,
      first.text,
      first.alignment,
      first.textStatus,
    );
    db.close();
    const result = importValidatedCorpus(corpus, { state, execute: true });
    assert.equal(result.status, 'ready');
    assert.equal(result.missingRows, corpus.verses.length - 1);
    assert.ok(!JSON.stringify(result).includes('PRIVATE READING SENTINEL'));
    const before = new DatabaseSync(path, { readOnly: true });
    const epoch = before.prepare('SELECT version FROM source_policy_state').get().version;
    assert.equal(
      before.prepare('SELECT COUNT(*) AS n FROM scripture_verses').get().n,
      corpus.verses.length,
    );
    assert.equal(
      before
        .prepare(
          "SELECT COUNT(*) AS n FROM scripture_corpora WHERE state='ready' AND active=1 AND rights_status='approved'",
        )
        .get().n,
      1,
    );
    assert.equal(
      before.prepare("SELECT text FROM scripture_verses WHERE source_id='webp:GEN:1:1'").get().text,
      syntheticText,
    );
    assert.equal(before.prepare('SELECT COUNT(*) AS n FROM users').get().n, 1);
    before.close();
    assert.equal(importValidatedCorpus(corpus, { state, execute: true }).writes, 0);
    const changed = new DatabaseSync(path);
    assert.equal(changed.prepare('SELECT version FROM source_policy_state').get().version, epoch);
    assert.throws(
      () =>
        changed.exec("UPDATE scripture_verses SET text='altered' WHERE source_id='webp:GEN:1:1'"),
      /scripture_revision_immutable/,
    );
    changed.exec("UPDATE scripture_corpora SET active=0,rights_status='revoked'");
    changed.close();
    assert.throws(() => importValidatedCorpus(corpus, { state, execute: true }), /revoked/);
    const check = new DatabaseSync(path, { readOnly: true });
    assert.equal(
      check.prepare('SELECT rights_status FROM scripture_corpora').get().rights_status,
      'revoked',
    );
    assert.equal(check.prepare('PRAGMA foreign_key_check').all().length, 0);
    check.close();
    assert.ok(!existsSync(denied), 'No external DNS/TCP/TLS request or update check is permitted');
  },
);
