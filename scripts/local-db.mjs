#!/usr/bin/env node
/** Private, local-only D1 recovery rehearsals. No SQL export or remote operations. */
import { backup, DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  closeSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  readdirSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LOCAL_WRANGLER_ENV, validateScaffoldConfig } from './config.mjs';

export const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const config = 'apps/api/wrangler.jsonc';
const stateLayout = 'v3/d1/miniflare-D1DatabaseObject';
const defaultState = 'apps/api/.wrangler/state';
const storage = '.cache/local-db';
const labelPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
const quote = (value) => '"' + value.replaceAll('"', '""') + '"';
const digest = (value) => createHash('sha256').update(value).digest('hex');

function fileDigest(path) {
  const hash = createHash('sha256');
  const buffer = Buffer.alloc(1024 * 1024);
  const fd = openSync(path, 'r');
  try {
    let length;
    while ((length = readSync(fd, buffer)) > 0) hash.update(buffer.subarray(0, length));
    return hash.digest('hex');
  } finally {
    closeSync(fd);
  }
}

class LocalDatabaseError extends Error {}
function check(condition, message) {
  if (!condition) throw new LocalDatabaseError(message);
}

export function parseArguments(args) {
  const [command = 'help', ...rest] = args;
  const allowed = {
    help: [],
    inspect: ['--state'],
    backup: ['--state', '--name'],
    verify: ['--name'],
    restore: ['--name', '--target'],
  };
  check(Object.hasOwn(allowed, command), 'Unknown local database command. Use help.');
  const options = {};
  for (let i = 0; i < rest.length; i += 2) {
    const key = rest[i];
    check(
      allowed[command].includes(key) && !Object.hasOwn(options, key.slice(2)),
      'Unsupported or duplicate option. Remote, overwrite and config overrides are not supported.',
    );
    const value = rest[i + 1];
    check(typeof value === 'string' && !value.startsWith('-'), 'An option value is required.');
    options[key.slice(2)] = value;
  }
  if (['backup', 'verify', 'restore'].includes(command))
    check(
      labelPattern.test(options.name ?? ''),
      'Require --name with a simple 1–64 character label.',
    );
  if (command === 'restore')
    check(labelPattern.test(options.target ?? ''), 'Require --target with a new simple label.');
  if (options.state !== undefined) validateState(options.state);
  return { command, ...options };
}

function validateState(state) {
  check(
    state === defaultState || /^\.cache\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*$/.test(state),
    'State must be the default local state or a simple path beneath .cache.',
  );
}

/** Reject links in every existing component, including the final artifact. */
function safePath(root, path) {
  const full = resolve(root, path);
  check(full.startsWith(root + '/'), 'Path must remain inside this repository.');
  let current = root;
  for (const part of relative(root, full).split('/')) {
    current = join(current, part);
    let info;
    try {
      info = lstatSync(current);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    if (info) {
      check(!info.isSymbolicLink(), 'Symlinked local database paths are not supported.');
      check(
        info.isDirectory() || (info.isFile() && info.nlink === 1),
        'Require ordinary, unlinked local files.',
      );
    }
  }
  return full;
}

function privateDirectory(root, path, exclusive = false) {
  const full = safePath(root, path);
  if (exclusive) {
    check(
      !existsSync(full),
      'Destination already exists; choose a new label. Nothing was overwritten.',
    );
    mkdirSync(full, { mode: 0o700 });
  } else if (!existsSync(full)) mkdirSync(full, { mode: 0o700 });
  const info = lstatSync(full);
  check(
    info.isDirectory() && (info.mode & 0o077) === 0,
    'Private artifact directories must have mode 0700.',
  );
  return full;
}

function safeDatabasePath(root, path) {
  const full = safePath(root, path);
  for (const suffix of ['-wal', '-shm', '-journal']) safePath(root, path + suffix);
  return full;
}

function prepareStorage(root) {
  const cache = safePath(root, '.cache');
  if (!existsSync(cache)) mkdirSync(cache, { mode: 0o700 });
  privateDirectory(root, storage);
  privateDirectory(root, storage + '/backups');
  privateDirectory(root, storage + '/restores');
}

function configuration(root) {
  const value = validateScaffoldConfig(JSON.parse(readFileSync(safePath(root, config), 'utf8')));
  check(
    value.vars.ENVIRONMENT === 'development',
    'Only the checked-in development profile is supported.',
  );
  return {
    binding: digest(JSON.stringify(value.d1_databases[0])),
    wrangler: JSON.parse(readFileSync(join(root, 'node_modules/wrangler/package.json'), 'utf8'))
      .version,
  };
}

export function findDatabase(root, state = defaultState) {
  validateState(state);
  const directory = safePath(root, state + '/' + stateLayout);
  check(
    existsSync(directory),
    'No initialized local D1 database found. Apply local migrations first.',
  );
  const names = readdirSync(directory).filter((name) => /^[0-9a-f]{64}\.sqlite$/.test(name));
  check(
    names.length === 1,
    'Expected exactly one local D1 database; ambiguous or absent state is refused.',
  );
  return safeDatabasePath(root, state + '/' + stateLayout + '/' + names[0]);
}

function openReadonly(path) {
  const db = new DatabaseSync(path, { readOnly: true, allowExtension: false });
  db.exec('PRAGMA query_only=ON; PRAGMA trusted_schema=OFF; PRAGMA busy_timeout=5000;');
  return db;
}

function encodeCell(value) {
  if (value === null) return ['null'];
  if (value instanceof Uint8Array) return ['blob', Buffer.from(value).toString('hex')];
  return [typeof value, String(value)];
}

function applicationSchema(schema) {
  return schema.filter(
    (row) =>
      !row.name.startsWith('_cf_') &&
      row.name !== 'sqlite_sequence' &&
      row.tbl_name !== 'd1_migrations',
  );
}

function expectedApplicationSchema(root, migrations) {
  const fresh = new DatabaseSync(':memory:');
  try {
    fresh.exec('PRAGMA foreign_keys=ON;');
    for (const name of migrations)
      fresh.exec(readFileSync(join(root, 'apps/api/migrations', name), 'utf8'));
    return applicationSchema(
      fresh.prepare('SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name').all(),
    );
  } finally {
    fresh.close();
  }
}

/** Fingerprints are private metadata; no row values, SQL or identifiers go to the terminal. */
export function inspectDatabase(path, root = repositoryRoot) {
  safeDatabasePath(root, relative(root, path));
  const db = openReadonly(path);
  try {
    db.exec('BEGIN');
    const integrity = db.prepare('PRAGMA integrity_check').all();
    check(
      integrity.length === 1 && Object.values(integrity[0])[0] === 'ok',
      'SQLite integrity check failed.',
    );
    check(
      db.prepare('PRAGMA foreign_key_check').all().length === 0,
      'Foreign-key violations found.',
    );
    const schema = db
      .prepare('SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name')
      .all();
    const tables = schema.filter((row) => row.type === 'table' && !row.name.startsWith('_cf_'));
    for (const required of [
      'users',
      'imports',
      'conversations',
      'budget_reservations',
      'public_sources',
      'd1_migrations',
    ])
      check(
        tables.some((table) => table.name === required),
        'Required application or D1 migration table is missing.',
      );
    const available = readdirSync(join(root, 'apps/api/migrations'))
      .filter((file) => /^\d+_.+\.sql$/.test(file))
      .sort();
    const applied = db
      .prepare('SELECT name FROM d1_migrations ORDER BY id')
      .all()
      .map((row) => row.name);
    check(
      applied.length > 0 && applied.length <= available.length,
      'Unsupported migration history.',
    );
    check(
      applied.every((name, index) => name === available[index]),
      'Migration history must be a known ordered prefix.',
    );
    const migrations = applied.map((name) => ({
      name,
      sha256: digest(readFileSync(join(root, 'apps/api/migrations', name))),
    }));
    const expectedSchemaSha256 = digest(JSON.stringify(expectedApplicationSchema(root, applied)));
    const schemaMatchesMigrations =
      digest(JSON.stringify(applicationSchema(schema))) === expectedSchemaSha256;
    const contents = {};
    for (const { name } of tables) {
      const columns = db.prepare(`SELECT * FROM ${quote(name)} LIMIT 0`).columns().length;
      const query = db.prepare(
        `SELECT * FROM ${quote(name)} ORDER BY ${Array.from({ length: columns }, (_, i) => i + 1).join(',')}`,
      );
      query.setReadBigInts(true);
      query.setReturnArrays(true);
      const hash = createHash('sha256');
      let rows = 0;
      for (const row of query.iterate()) {
        hash.update(JSON.stringify(row.map(encodeCell)) + '\n');
        rows++;
      }
      contents[name] = { rows, sha256: hash.digest('hex') };
    }
    db.exec('COMMIT');
    return {
      schemaSha256: digest(JSON.stringify(schema)),
      expectedSchemaSha256,
      schemaMatchesMigrations,
      migrations,
      contents,
    };
  } finally {
    db.close();
  }
}

function publicSummary(fingerprint) {
  const categories = [
    'users',
    'imports',
    'conversations',
    'messages',
    'request_cancellations',
    'budget_reservations',
    'public_sources',
    'public_materials',
    'scripture_corpora',
    'scripture_verses',
    'comparison_jobs',
    'comparison_trials',
  ];
  return {
    integrity: 'ok',
    foreignKeys: 'ok',
    schemaMatchesMigrations: fingerprint.schemaMatchesMigrations,
    migrations: fingerprint.migrations.length,
    rows: Object.fromEntries(
      categories
        .filter((table) => fingerprint.contents[table])
        .map((table) => [table, fingerprint.contents[table].rows]),
    ),
  };
}

function fingerprintEquals(actual, expected) {
  check(
    JSON.stringify(actual) === JSON.stringify(expected),
    'Schema, migration or data verification failed.',
  );
}

async function snapshot(source, destination) {
  check(!existsSync(destination), 'Snapshot destination already exists.');
  // Reserve a private empty file; its parent is also private and uniquely reserved.
  writeFileSync(destination, '', { mode: 0o600, flag: 'wx' });
  const db = openReadonly(source);
  try {
    await backup(db, destination);
  } finally {
    db.close();
  }
  useStandaloneJournal(destination);
  chmodSync(destination, 0o600);
}

/** Only called for newly created private copies/targets, never a source database. */
function useStandaloneJournal(path) {
  const db = new DatabaseSync(path, { allowExtension: false });
  try {
    db.exec('PRAGMA busy_timeout=5000;');
    const result = db.prepare('PRAGMA wal_checkpoint(TRUNCATE)').get();
    check(result.busy === 0, 'New target is busy; stop local Workers and choose a new target.');
    check(
      db.prepare('PRAGMA journal_mode=DELETE').get().journal_mode === 'delete',
      'Could not create a standalone private SQLite copy.',
    );
  } finally {
    db.close();
  }
}

export async function createBackup({ root = repositoryRoot, name, state = defaultState }) {
  check(labelPattern.test(name ?? ''), 'Invalid backup label.');
  const identity = configuration(root);
  const source = findDatabase(root, state);
  prepareStorage(root);
  const directory = privateDirectory(root, `${storage}/backups/${name}`, true);
  const path = join(directory, 'database.sqlite');
  await snapshot(source, path);
  const fingerprint = inspectDatabase(path, root);
  const manifest = {
    format: 'bible-companion-private-local-d1-v1',
    createdAt: new Date().toISOString(),
    ...identity,
    databaseFile: source.split('/').at(-1),
    fileSha256: fileDigest(path),
    fingerprint,
  };
  // Written last: a failed backup has no valid manifest and is never restorable.
  writeFileSync(join(directory, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n', {
    flag: 'wx',
    mode: 0o600,
  });
  return { backup: name, privateLocalOnly: true, ...publicSummary(fingerprint) };
}

export function verifyBackup({ root = repositoryRoot, name }) {
  check(labelPattern.test(name ?? ''), 'Invalid backup label.');
  const identity = configuration(root);
  const directory = safePath(root, `${storage}/backups/${name}`);
  check(
    existsSync(directory) && (lstatSync(directory).mode & 0o077) === 0,
    'Backup directory must exist and be private.',
  );
  const path = safeDatabasePath(root, `${storage}/backups/${name}/database.sqlite`);
  const manifestPath = safePath(root, `${storage}/backups/${name}/manifest.json`);
  for (const file of [path, manifestPath])
    check(
      existsSync(file) && (lstatSync(file).mode & 0o077) === 0,
      'Backup files must exist and be private.',
    );
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  check(manifest.format === 'bible-companion-private-local-d1-v1', 'Unsupported backup format.');
  check(
    manifest.binding === identity.binding && manifest.wrangler === identity.wrangler,
    'Backup requires the same D1 binding and installed Wrangler version.',
  );
  check(/^[0-9a-f]{64}\.sqlite$/.test(manifest.databaseFile), 'Invalid backup database identity.');
  check(fileDigest(path) === manifest.fileSha256, 'Backup file checksum mismatch.');
  const fingerprint = inspectDatabase(path, root);
  fingerprintEquals(fingerprint, manifest.fingerprint);
  return {
    path,
    manifest,
    summary: { backup: name, privateLocalOnly: true, ...publicSummary(fingerprint) },
  };
}

/** This is the only subprocess path: fixed local SELECT through the repository guard. */
function localD1(root, state, sql) {
  const result = spawnSync(
    process.execPath,
    [
      'scripts/wrangler.mjs',
      'd1',
      'execute',
      'bible-companion',
      '--local',
      '--config',
      config,
      '--persist-to',
      state,
      '--command',
      sql,
    ],
    {
      cwd: root,
      encoding: 'utf8',
      timeout: 120_000,
      maxBuffer: 1024 * 1024,
      env: {
        ...process.env,
        CI: 'true',
        ...LOCAL_WRANGLER_ENV,
      },
    },
  );
  // Never forward child stderr, SQL or logs: they may contain private data on failure.
  check(
    !result.error && result.status === 0,
    'Local D1 verification failed. The isolated target is incomplete; use a new target label after diagnosis.',
  );
  const start = result.stdout.search(/\[\s*\{\s*"results"\s*:/);
  check(start >= 0, 'Local D1 returned an unrecognized result format.');
  let output;
  try {
    output = JSON.parse(result.stdout.slice(start));
  } catch {
    throw new LocalDatabaseError('Local D1 returned an unrecognized result format.');
  }
  check(
    output.length === 1 && output[0].success === true && output[0].results?.length === 1,
    'Local D1 read verification did not succeed.',
  );
  return output[0].results[0];
}

export async function restoreBackup({ root = repositoryRoot, name, target }) {
  check(labelPattern.test(target ?? ''), 'Invalid restore target label.');
  const { path, manifest, summary } = verifyBackup({ root, name });
  check(
    manifest.fingerprint.schemaMatchesMigrations === true,
    'Backup preserved, but its schema differs from the checked-in applied migrations. Restore requires reviewed matching migration history.',
  );
  prepareStorage(root);
  const state = `${storage}/restores/${target}`;
  const directory = privateDirectory(root, state, true);
  // The inherited restrictive umask also protects newly created Wrangler state files.
  const mask = process.umask(0o077);
  try {
    const initialized = localD1(root, state, 'SELECT 1 AS local_restore_probe;');
    check(
      initialized.local_restore_probe === 1,
      'Could not initialize the isolated local D1 target.',
    );
    const destination = findDatabase(root, state);
    check(
      destination.split('/').at(-1) === manifest.databaseFile,
      'D1 local database identity differs from the snapshot.',
    );
    useStandaloneJournal(destination);
    for (const suffix of ['-wal', '-shm', '-journal'])
      check(
        !existsSync(destination + suffix),
        'Initialized target still has SQLite sidecars; refuse replacement.',
      );
    // This file was created solely by the SELECT above in a brand-new private directory.
    // SQLite backup writes the reserved empty D1 target; it never touches existing state.
    const db = openReadonly(path);
    try {
      await backup(db, destination);
    } finally {
      db.close();
    }
    chmodSync(destination, 0o600);
    fingerprintEquals(inspectDatabase(destination, root), manifest.fingerprint);
    const tables = Object.keys(manifest.fingerprint.contents).filter(
      (table) => !table.startsWith('sqlite_'),
    );
    const counts = localD1(
      root,
      state,
      'SELECT ' +
        tables
          .map((table, index) => `(SELECT COUNT(*) FROM ${quote(table)}) AS ${quote('t' + index)}`)
          .join(',') +
        ';',
    );
    for (let i = 0; i < tables.length; i++)
      check(
        counts['t' + i] === manifest.fingerprint.contents[tables[i]].rows,
        'Restored local D1 row counts differ from the snapshot.',
      );
    fingerprintEquals(inspectDatabase(destination, root), manifest.fingerprint);
    writeFileSync(
      join(directory, 'restore-verified.json'),
      JSON.stringify({
        format: manifest.format,
        backup: name,
        verifiedAt: new Date().toISOString(),
        fileSha256: manifest.fileSha256,
      }) + '\n',
      { flag: 'wx', mode: 0o600 },
    );
    return { ...summary, state, d1Read: 'ok', exactSchemaAndData: 'ok' };
  } finally {
    process.umask(mask);
  }
}

const help = `Private local D1 backup and recovery rehearsal (Node 24+).
  node scripts/local-db.mjs inspect [--state .cache/STATE]
  node scripts/local-db.mjs backup --name LABEL [--state .cache/STATE]
  node scripts/local-db.mjs verify --name LABEL
  node scripts/local-db.mjs restore --name LABEL --target NEW_LABEL

Default source: apps/api/.wrangler/state. Backups: .cache/local-db/backups.
Restores always use a NEW .cache/local-db/restores/NEW_LABEL directory.
Stop local Workers before restore. No remote, overwrite or deletion mode exists.
Backups contain private account data and auth verifiers. Never publish or export them.
See docs/local-backup-restore.md for limitations and recovery steps.`;

export async function main(args, root = repositoryRoot) {
  const options = { ...parseArguments(args), root };
  if (options.command === 'help') return help;
  if (options.command === 'backup') return createBackup(options);
  if (options.command === 'restore') return restoreBackup(options);
  if (options.command === 'verify') return verifyBackup(options).summary;
  configuration(root);
  return {
    privateLocalOnly: true,
    ...publicSummary(inspectDatabase(findDatabase(root, options.state), root)),
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = await main(process.argv.slice(2));
    console.log(typeof result === 'string' ? result : JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(
      error instanceof LocalDatabaseError
        ? error.message
        : 'Local database operation failed. No private SQL or row data was printed.',
    );
    process.exitCode = 1;
  }
}
