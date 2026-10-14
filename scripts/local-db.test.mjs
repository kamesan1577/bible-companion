import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  copyFileSync,
  existsSync,
  linkSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { join, relative } from 'node:path';
import {
  createBackup,
  findDatabase,
  inspectDatabase,
  main,
  parseArguments,
  repositoryRoot,
  restoreBackup,
  verifyBackup,
} from './local-db.mjs';
import { LOCAL_WRANGLER_ENV } from './config.mjs';

const migrationDirectory = join(repositoryRoot, 'apps/api/migrations');
const migrationNames = () =>
  readdirSync(migrationDirectory)
    .filter((name) => name.endsWith('.sql'))
    .sort();
const databaseName = 'a'.repeat(64) + '.sqlite';
const privateValue = 'DO-NOT-LOG-private-reading-and-auth-verifier';

function populate(db) {
  db.exec(`
    PRAGMA foreign_keys=ON;
    INSERT INTO users(id,display_name,role,created_at) VALUES('alice','${privateValue}','owner',1),('bob','Second reader','member',2);
    INSERT INTO credentials(id,user_id,public_key,counter,transports_json,device_type,backed_up,created_at) VALUES('credential','alice','${privateValue}',7,'[]','singleDevice',0,1);
    INSERT INTO sessions(token_hash,user_id,expires_at,created_at) VALUES('${privateValue}','alice',9999999999,1);
    INSERT INTO invitations(token_hash,role,expires_at) VALUES('${privateValue}','member',9999999999);
    INSERT INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,created_at) VALUES('ia','alice','ka','ha','[{"book":"GEN","chapter":1}]',1),('ib','bob','kb','hb','[]',2);
    INSERT INTO conversations(id,user_id,import_id,passage_json,reading_boundary_json,created_at) VALUES('ca','alice','ia','{"book":"GEN"}','{"chapter":1}',1),('cb','bob','ib','{}','{}',2);
    INSERT INTO messages(id,conversation_id,user_id,role,content_json,created_at) VALUES('ma','ca','alice','user','{"text":"${privateValue}"}',1),('mb','cb','bob','user','{"text":"Second account"}',2);
    INSERT INTO generation_requests(id,user_id,conversation_id,request_hash,status,created_at,updated_at) VALUES('ga','alice','ca','hash','cancelled',1,1);
    INSERT INTO request_cancellations(user_id,id,kind,created_at) VALUES('alice','ga','question',1),('bob','before-request','comparison',2);
    INSERT INTO budget_days(day) VALUES('2026-10-13');
    INSERT INTO user_budget_days(user_id,day) VALUES('alice','2026-10-13');
    INSERT INTO budget_reservations(id,user_id,day,amount,created_at) VALUES('settled','alice','2026-10-13',100,1);
    UPDATE budget_reservations SET actual=60,state='settled' WHERE id='settled';
    INSERT INTO budget_reservations(id,user_id,day,amount,created_at) VALUES('held','alice','2026-10-13',50,1);
    INSERT INTO comparison_jobs(id,user_id,request_hash,status,saved,metrics_json,created_at,updated_at,trial_count) VALUES('comparison','alice','hash','complete',1,'{"text":"${privateValue}"}',1,1,1);
    INSERT INTO comparison_trials(job_id,user_id,trial_index,question_index,model_index,model_id,state,amount,proof_fingerprint,dispatched,model_invoked,metrics_json) VALUES('comparison','alice',0,0,0,'offline-model','complete',20,'proof',1,1,'{"latency":12}');
    UPDATE public_sources SET rights_status='revoked',active=0 WHERE id=(SELECT id FROM public_sources ORDER BY id LIMIT 1);
    UPDATE public_materials SET rights_status='revoked',active=0 WHERE id=(SELECT id FROM public_materials ORDER BY id LIMIT 1);
  `);
}

function fixture(t, { populateData = true, migrationCount = migrationNames().length } = {}) {
  mkdirSync(join(repositoryRoot, '.cache'), { recursive: true });
  const root = mkdtempSync(join(repositoryRoot, '.cache/local-db-unit-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const dir of [
    'apps/api/migrations',
    'node_modules/wrangler',
    '.cache/source/v3/d1/miniflare-D1DatabaseObject',
  ])
    mkdirSync(join(root, dir), { recursive: true });
  copyFileSync(
    join(repositoryRoot, 'apps/api/wrangler.jsonc'),
    join(root, 'apps/api/wrangler.jsonc'),
  );
  copyFileSync(
    join(repositoryRoot, 'node_modules/wrangler/package.json'),
    join(root, 'node_modules/wrangler/package.json'),
  );
  for (const name of migrationNames())
    copyFileSync(join(migrationDirectory, name), join(root, 'apps/api/migrations', name));
  const path = join(root, '.cache/source/v3/d1/miniflare-D1DatabaseObject', databaseName);
  const db = new DatabaseSync(path);
  db.exec(
    'PRAGMA foreign_keys=ON; CREATE TABLE d1_migrations(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL UNIQUE,applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);',
  );
  for (const name of migrationNames().slice(0, migrationCount)) {
    db.exec(readFileSync(join(migrationDirectory, name), 'utf8'));
    db.prepare('INSERT INTO d1_migrations(name) VALUES(?)').run(name);
  }
  if (populateData) populate(db);
  db.close();
  return { root, path, state: '.cache/source' };
}

test('strict local arguments reject remote, destructive, ambiguous and escaping inputs', () => {
  assert.deepEqual(parseArguments(['backup', '--name', 'before-upgrade']), {
    command: 'backup',
    name: 'before-upgrade',
  });
  for (const args of [
    ['export'],
    ['backup'],
    ['restore', '--name', 'safe'],
    ['backup', '--name', '../secret'],
    ['backup', '--name', 'x', '--remote'],
    ['backup', '--name', 'x', '--name', 'y'],
    ['backup', '--name=x'],
    ['backup', '--name', 'x', '--config', 'remote.json'],
    ['restore', '--name', 'x', '--target', '.'],
    ['restore', '--name', 'x', '--target', 'y', '--overwrite'],
    ...[
      '/tmp/source',
      '.cache/../source',
      '.cache/source/',
      'https://remote',
      '.cache/source//nested',
    ].map((state) => ['inspect', '--state', state]),
  ])
    assert.throws(() => parseArguments(args));
});

test('WAL snapshot preserves all exact schema/data, migration history and private file modes without leaking rows', async (t) => {
  const options = fixture(t);
  const source = new DatabaseSync(options.path);
  t.after(() => source.close());
  source.exec('PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;');
  source.exec(
    "CREATE TABLE binary_probe(id INTEGER PRIMARY KEY,b BLOB,n INTEGER,r REAL); INSERT INTO binary_probe VALUES(1,x'00FF1020',9223372036854775807,1.5);",
  );
  const expected = inspectDatabase(options.path, options.root);
  const originalFile = readFileSync(options.path);
  const result = await createBackup({ ...options, name: 'wal' });
  assert.equal(result.rows.users, 2);
  assert.equal(result.rows.imports, 2);
  assert.equal(result.rows.request_cancellations, 2);
  assert.equal(result.rows.budget_reservations, 2);
  assert.equal(result.migrations, migrationNames().length);
  assert.ok(!JSON.stringify(result).includes(privateValue));
  const verified = verifyBackup({ ...options, name: 'wal' });
  assert.deepEqual(verified.manifest.fingerprint, expected);
  assert.deepEqual(inspectDatabase(options.path, options.root), expected);
  assert.deepEqual(readFileSync(options.path), originalFile);
  for (const name of ['database.sqlite', 'manifest.json']) {
    const file = join(options.root, '.cache/local-db/backups/wal', name);
    assert.equal(lstatSync(file).mode & 0o777, 0o600);
  }
  assert.equal(lstatSync(join(options.root, '.cache/local-db/backups/wal')).mode & 0o777, 0o700);
  assert.ok(!existsSync(verified.path + '-wal'));
  const backupContents = readFileSync(verified.path);
  await assert.rejects(createBackup({ ...options, name: 'wal' }), /already exists/);
  assert.deepEqual(readFileSync(verified.path), backupContents);
});

test('restoration refuses any pre-existing target before invoking Wrangler', async (t) => {
  const options = fixture(t);
  await createBackup({ ...options, name: 'keep' });
  const target = join(options.root, '.cache/local-db/restores/existing');
  mkdirSync(target, { mode: 0o700 });
  writeFileSync(join(target, 'sentinel'), 'existing-state');
  await assert.rejects(
    restoreBackup({ ...options, name: 'keep', target: 'existing' }),
    /already exists/,
  );
  assert.equal(readFileSync(join(target, 'sentinel'), 'utf8'), 'existing-state');
});

test('older snapshots preserve their migration prefix and never apply pending migrations', async (t) => {
  const options = fixture(t, { populateData: false, migrationCount: 1 });
  const result = await createBackup({ ...options, name: 'old' });
  assert.equal(result.migrations, 1);
  assert.equal(verifyBackup({ ...options, name: 'old' }).manifest.fingerprint.migrations.length, 1);
  assert.ok(!inspectDatabase(options.path, options.root).contents.comparison_trials);
});

test('same migration names cannot hide historical schema drift or make a restore application-ready', async (t) => {
  const options = fixture(t);
  const db = new DatabaseSync(options.path);
  db.exec('DROP TRIGGER comparison_proven_no_dispatch;');
  db.close();
  const result = await createBackup({ ...options, name: 'historical' });
  assert.equal(result.schemaMatchesMigrations, false);
  assert.equal(
    verifyBackup({ ...options, name: 'historical' }).summary.schemaMatchesMigrations,
    false,
  );
  await assert.rejects(
    restoreBackup({ ...options, name: 'historical', target: 'refused' }),
    /schema differs/,
  );
  assert.ok(!existsSync(join(options.root, '.cache/local-db/restores/refused')));
});

test('corrupt bytes, edited manifest, migration drift, runtime drift and loose permissions fail closed', async (t) => {
  for (const mode of ['bytes', 'manifest', 'migration', 'runtime', 'permissions']) {
    await t.test(mode, async (t) => {
      const options = fixture(t);
      await createBackup({ ...options, name: 'original' });
      const directory = join(options.root, '.cache/local-db/backups/original');
      if (mode === 'bytes')
        writeFileSync(join(directory, 'database.sqlite'), 'corrupt', { mode: 0o600 });
      if (mode === 'manifest') {
        const path = join(directory, 'manifest.json');
        const manifest = JSON.parse(readFileSync(path, 'utf8'));
        manifest.fingerprint.contents.users.rows = 0;
        writeFileSync(path, JSON.stringify(manifest));
      }
      if (mode === 'migration')
        writeFileSync(
          join(options.root, 'apps/api/migrations', migrationNames()[0]),
          '-- changed migration',
        );
      if (mode === 'runtime')
        writeFileSync(
          join(options.root, 'node_modules/wrangler/package.json'),
          '{"version":"other"}',
        );
      if (mode === 'permissions') chmodSync(join(directory, 'database.sqlite'), 0o644);
      assert.throws(() => verifyBackup({ ...options, name: 'original' }));
    });
  }
});

test('foreign-key damage cannot produce a valid backup manifest', async (t) => {
  const options = fixture(t);
  const db = new DatabaseSync(options.path);
  db.exec("PRAGMA foreign_keys=OFF; INSERT INTO sessions VALUES('orphan','absent',1,1);");
  db.close();
  await assert.rejects(createBackup({ ...options, name: 'broken' }), /Foreign-key/);
  assert.ok(!existsSync(join(options.root, '.cache/local-db/backups/broken/manifest.json')));
});

test('symlinked and hardlinked state, ambiguous database selection and linked backup files are refused', async (t) => {
  const options = fixture(t);
  symlinkSync(join(options.root, '.cache/source'), join(options.root, '.cache/link'));
  assert.throws(() => findDatabase(options.root, '.cache/link'), /Symlink/);
  const extra = join(
    options.root,
    '.cache/source/v3/d1/miniflare-D1DatabaseObject',
    'b'.repeat(64) + '.sqlite',
  );
  writeFileSync(extra, 'other');
  assert.throws(() => findDatabase(options.root, options.state), /exactly one/);
  rmSync(extra);
  linkSync(options.path, join(options.root, '.cache/hardlink'));
  assert.throws(() => findDatabase(options.root, options.state), /unlinked/);
  rmSync(join(options.root, '.cache/hardlink'));
  await createBackup({ ...options, name: 'linked' });
  const path = join(options.root, '.cache/local-db/backups/linked/database.sqlite');
  rmSync(path);
  symlinkSync(options.path, path);
  assert.throws(() => verifyBackup({ ...options, name: 'linked' }), /Symlink/);
});

test('CLI summaries contain no private rows, verifiers or raw database errors', async (t) => {
  const options = fixture(t);
  const result = await main(['inspect', '--state', options.state], options.root);
  assert.ok(!JSON.stringify(result).includes(privateValue));
  const failure = spawnSync(
    process.execPath,
    ['scripts/local-db.mjs', 'inspect', '--state', '.cache/missing-local-db-test-state'],
    { cwd: repositoryRoot, encoding: 'utf8' },
  );
  assert.equal(failure.status, 1);
  assert.ok(!failure.stderr.includes('at file:'));
  assert.ok(!failure.stderr.includes(privateValue));
});

test('linked SQLite sidecars and linked artifact parents are refused before any write', async (t) => {
  const options = fixture(t);
  const before = readFileSync(options.path);
  symlinkSync(options.path, options.path + '-wal');
  assert.throws(() => findDatabase(options.root, options.state), /Symlink/);
  rmSync(options.path + '-wal');
  symlinkSync(join(options.root, '.cache/source'), join(options.root, '.cache/local-db'));
  await assert.rejects(createBackup({ ...options, name: 'escape' }), /Symlink/);
  assert.deepEqual(readFileSync(options.path), before);
});

test(
  'actual local D1 round trip preserves populated accounts, rights, triggers and budgets without external calls',
  { timeout: 660_000 },
  async (t) => {
    const label = 'test-' + randomUUID();
    const state = '.cache/local-db-integration-' + randomUUID();
    const directory = join(repositoryRoot, state);
    mkdirSync(directory, { mode: 0o700 });
    const deniedPath = join(directory, 'unexpected-network');
    // The same fail-before-connect guard protects fresh and warm checkouts.
    const guardPath = join(repositoryRoot, 'scripts/diagnostics/no-external-network.cjs');
    const env = {
      ...process.env,
      NODE_OPTIONS: '--require=' + guardPath,
      BIBLE_NETWORK_DIAGNOSTIC: deniedPath,
      CI: 'true',
      ...LOCAL_WRANGLER_ENV,
    };
    t.after(() => {
      rmSync(directory, { recursive: true, force: true });
      rmSync(join(repositoryRoot, '.cache/local-db/backups', label), {
        recursive: true,
        force: true,
      });
      rmSync(join(repositoryRoot, '.cache/local-db/restores', label), {
        recursive: true,
        force: true,
      });
    });
    const migrate = (target) =>
      spawnSync(
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
          target,
        ],
        { cwd: repositoryRoot, encoding: 'utf8', env, timeout: 300_000, maxBuffer: 1024 * 1024 },
      );
    const migration = migrate(state);
    assert.equal(
      !migration.error && migration.status === 0,
      true,
      `Local migrations must finish without external calls (signal=${migration.signal ?? 'none'}, error=${migration.error?.code ?? 'none'})`,
    );
    assert.ok(!existsSync(deniedPath), 'Wrangler must not attempt an external connection');
    const sourcePath = findDatabase(repositoryRoot, state);
    const db = new DatabaseSync(sourcePath);
    populate(db);
    db.close();
    const expected = inspectDatabase(sourcePath);
    const invoke = (args) =>
      spawnSync(process.execPath, ['scripts/local-db.mjs', ...args], {
        cwd: repositoryRoot,
        encoding: 'utf8',
        env,
        timeout: 60_000,
      });
    const snapshot = invoke(['backup', '--name', label, '--state', state]);
    assert.equal(snapshot.status, 0, snapshot.stderr);
    const restored = invoke(['restore', '--name', label, '--target', label]);
    assert.equal(restored.status, 0, restored.stderr);
    assert.ok(!restored.stdout.includes(privateValue));
    assert.ok(!restored.stderr.includes(privateValue));
    assert.equal(JSON.parse(restored.stdout).d1Read, 'ok');
    const restoredState = '.cache/local-db/restores/' + label;
    const restoredPath = findDatabase(repositoryRoot, restoredState);
    assert.deepEqual(inspectDatabase(restoredPath), expected);
    assert.deepEqual(inspectDatabase(sourcePath), expected);
    // Migration replay is a no-op. No seed reapproval or budget settlement is repeated.
    assert.equal(migrate(restoredState).status, 0);
    assert.deepEqual(inspectDatabase(restoredPath), expected);
    assert.ok(
      !existsSync(deniedPath),
      'No external DNS/TCP/TLS attempt is allowed, including update checks',
    );
    const restoredDB = new DatabaseSync(restoredPath);
    try {
      restoredDB.exec('PRAGMA foreign_keys=ON');
      assert.deepEqual(
        {
          ...restoredDB
            .prepare("SELECT reserved,consumed FROM budget_days WHERE day='2026-10-13'")
            .get(),
        },
        { reserved: 50, consumed: 60 },
      );
      assert.equal(
        restoredDB
          .prepare(
            "SELECT COUNT(*) AS n FROM public_sources WHERE rights_status='revoked' AND active=0",
          )
          .get().n,
        1,
      );
      assert.equal(
        restoredDB
          .prepare(
            "SELECT COUNT(*) AS n FROM public_materials WHERE rights_status='revoked' AND active=0",
          )
          .get().n,
        1,
      );
      assert.equal(
        restoredDB.prepare('SELECT COUNT(*) AS n FROM request_cancellations').get().n,
        2,
      );
      assert.throws(
        () =>
          restoredDB.exec(
            "INSERT INTO conversations(id,user_id,import_id,passage_json,created_at) VALUES('bad','bob','ia','{}',1)",
          ),
        /conversation_import_owner_mismatch/,
      );
      assert.throws(
        () =>
          restoredDB.exec(
            "UPDATE public_sources SET content_json='{}' WHERE id=(SELECT id FROM public_sources LIMIT 1)",
          ),
        /source_version_content_conflict/,
      );
      restoredDB.exec("DELETE FROM imports WHERE id='ia'");
      assert.equal(
        restoredDB.prepare("SELECT COUNT(*) AS n FROM conversations WHERE user_id='alice'").get().n,
        0,
      );
      assert.equal(
        restoredDB.prepare("SELECT COUNT(*) AS n FROM conversations WHERE user_id='bob'").get().n,
        1,
      );
      assert.equal(restoredDB.prepare('PRAGMA foreign_key_check').all().length, 0);
    } finally {
      restoredDB.close();
    }
  },
);
