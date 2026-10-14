import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync, mkdirSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { main, parseAssetArguments, assetConfig } from './scripture-assets-config.mjs';
import { findDatabase } from './local-db.mjs';
import { LOCAL_WRANGLER_ENV } from './config.mjs';
const root = resolve(new URL('..', import.meta.url).pathname);
test('assets operator plans stay local and routing cannot silently bypass rights checks', () => {
  assert.deepEqual(parseAssetArguments([]), {
    command: 'plan',
    execute: false,
    state: '.cache/scripture-assets-state',
  });
  for (const args of [
    ['--remote'],
    ['register-local', '--remote'],
    ['register-local', '--config', 'other'],
    ['register-local', '--persist-to', '../unsafe'],
    ['register-local', '--persist-to', '.cache/a/../b'],
    ['generate', '--execute'],
    ['register-local', '--execute', '--execute'],
  ])
    assert.throws(() => parseAssetArguments(args));
  const config = assetConfig();
  assert.equal(config.assets.run_worker_first, true);
  assert.equal(config.assets.not_found_handling, 'none');
  assert.equal(config.vars.AI_ENABLED, 'false');
  assert.equal(config.ai, undefined);
  const plan = main([]);
  assert.equal(plan.writes, 0);
  assert.equal(plan.remoteEnabled, false);
  assert.equal(plan.verseCount, 31095);
});
test(
  'actual isolated metadata-only activation is idempotent and never reapproves a revoked corpus',
  { timeout: 120000 },
  (t) => {
    main(['generate']);
    const state = '.cache/assets-config-test-' + randomUUID(),
      directory = join(root, state);
    mkdirSync(directory, { mode: 0o700 });
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const denied = join(directory, 'unexpected-network'),
      guard = join(directory, 'guard.cjs');
    writeFileSync(
      guard,
      `const fs=require('node:fs'),net=require('node:net'),dns=require('node:dns'),tls=require('node:tls');function check(h){if(h===undefined||['localhost','127.0.0.1','::1'].includes(h))return;fs.writeFileSync(${JSON.stringify(denied)},'blocked-before-connect');throw Error('External network forbidden');}function args(a){if(Array.isArray(a[0]))return args(a[0]);if(typeof a[0]==='object')check(a[0].host||a[0].hostname||a[0].servername);else if(typeof a[1]==='string')check(a[1]);}const c=net.Socket.prototype.connect;net.Socket.prototype.connect=function(...a){args(a);return c.apply(this,a)};const d=dns.lookup;dns.lookup=function(h,...a){check(h);return d.call(this,h,...a)};const s=tls.connect;tls.connect=function(...a){args(a);return s.apply(this,a)};`,
      { mode: 0o600 },
    );
    const previous = process.env.NODE_OPTIONS;
    process.env.NODE_OPTIONS = '--require=' + guard;
    t.after(() => {
      if (previous === undefined) delete process.env.NODE_OPTIONS;
      else process.env.NODE_OPTIONS = previous;
    });
    const initial = spawnSync(
      process.execPath,
      [
        'scripts/wrangler.mjs',
        'd1',
        'execute',
        'bible-companion',
        '--local',
        '--config',
        'apps/api/wrangler.assets.json',
        '--persist-to',
        state,
        '--command',
        'SELECT 1',
      ],
      {
        cwd: root,
        encoding: 'utf8',
        env: { ...process.env, ...LOCAL_WRANGLER_ENV },
        timeout: 60000,
      },
    );
    assert.equal(initial.status, 0);
    const path = findDatabase(root, state),
      db = new DatabaseSync(path);
    db.exec(
      'PRAGMA foreign_keys=ON;CREATE TABLE d1_migrations(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL UNIQUE,applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);',
    );
    for (const name of readdirSync(join(root, 'apps/api/migrations'))
      .filter((n) => n.endsWith('.sql'))
      .sort()) {
      db.exec(readFileSync(join(root, 'apps/api/migrations', name), 'utf8'));
      db.prepare('INSERT INTO d1_migrations(name) VALUES(?)').run(name);
    }
    db.close();
    const first = main(['register-local', '--persist-to', state, '--execute']);
    assert.equal(first.status, 'ready');
    assert.equal(first.verseRowsWritten, 0);
    const repeat = main(['register-local', '--persist-to', state, '--execute']);
    assert.equal(repeat.status, 'already-ready');
    assert.equal(repeat.writes, 0);
    const read = new DatabaseSync(path);
    assert.equal(read.prepare('SELECT count(*) AS n FROM scripture_verses').get().n, 0);
    assert.equal(read.prepare('SELECT count(*) AS n FROM scripture_corpora').get().n, 1);
    read.exec("UPDATE scripture_corpora SET active=0,rights_status='revoked'");
    read.close();
    assert.throws(
      () => main(['register-local', '--persist-to', state, '--execute']),
      /inactive or revoked/,
    );
    assert.equal(existsSync(denied), false);
  },
);
