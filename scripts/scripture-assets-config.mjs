#!/usr/bin/env node
/** Local-only immutable Assets profile. Never logs private data or enables provider/account access. */
import { readFileSync, writeFileSync, mkdirSync, lstatSync, existsSync } from 'node:fs';
import { dirname, resolve, relative, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { validateScaffoldConfig, LOCAL_WRANGLER_ENV } from './config.mjs';
import { findDatabase, inspectDatabase } from './local-db.mjs';
import {
  readBundledScriptureAssetInputs,
  planScriptureAssets,
  writeScriptureAssetPlan,
} from './build-scripture-assets.mjs';
import {
  SCRIPTURE_ASSET_INDEX_SHA256,
  SCRIPTURE_ASSET_SOURCE_VERSION,
  SCRIPTURE_ASSET_MANIFEST_SHA256,
} from '../apps/api/src/scripture-assets-pin.ts';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const configPath = 'apps/api/wrangler.assets.json';
const defaultState = '.cache/scripture-assets-state';
function check(ok, message) {
  if (!ok) throw Error(message);
}
function noLinks(path) {
  for (let p = resolve(root, path); p !== root; p = dirname(p)) {
    check(p.startsWith(root + '/'), 'Path outside repository.');
    if (existsSync(p)) {
      const stat = lstatSync(p);
      check(!stat.isSymbolicLink(), 'Symlink paths are refused.');
      if (stat.isFile()) check(stat.nlink === 1, 'Hardlinked files are refused.');
    }
  }
}
function trustedPlan() {
  const artifacts = readBundledScriptureAssetInputs();
  const plan = planScriptureAssets(artifacts);
  check(
    plan.summary.indexSha256 === SCRIPTURE_ASSET_INDEX_SHA256 &&
      plan.summary.sourceVersion === SCRIPTURE_ASSET_SOURCE_VERSION &&
      plan.summary.manifestSha256 === SCRIPTURE_ASSET_MANIFEST_SHA256,
    'Runtime asset pin differs from the offline build.',
  );
  return {
    plan,
    manifest: JSON.parse(artifacts.manifest.toString('utf8')),
    manifestText: artifacts.manifest.toString('utf8'),
  };
}
export function assetConfig() {
  const config = JSON.parse(readFileSync(join(root, 'apps/api/wrangler.jsonc'), 'utf8'));
  config.assets = {
    directory: '../../.cache/scripture/assets',
    binding: 'SCRIPTURE_ASSETS',
    run_worker_first: true,
    html_handling: 'none',
    not_found_handling: 'none',
  };
  return validateScaffoldConfig(config);
}
function generate(plan) {
  writeScriptureAssetPlan(plan, '.cache/scripture/assets');
  noLinks(configPath);
  const contents = JSON.stringify(assetConfig(), null, 2) + '\n';
  const path = join(root, configPath);
  if (existsSync(path))
    check(
      readFileSync(path, 'utf8') === contents,
      'Refusing to overwrite a different Assets configuration.',
    );
  else writeFileSync(path, contents, { flag: 'wx', mode: 0o600 });
}
export function parseAssetArguments(args) {
  const [command = 'plan', ...rest] = args;
  check(
    ['plan', 'generate', 'register-local'].includes(command),
    'Use plan, generate or register-local.',
  );
  let execute = false,
    state = defaultState;
  const seen = new Set();
  for (let i = 0; i < rest.length; i++) {
    const flag = rest[i];
    check(!seen.has(flag), 'Duplicate option.');
    seen.add(flag);
    if (flag === '--execute' && command === 'register-local') execute = true;
    else if (flag === '--persist-to' && command === 'register-local') {
      state = rest[++i];
      check(
        typeof state === 'string' && /^\.cache\/[A-Za-z0-9_-]+$/.test(state),
        'State must be a direct .cache child.',
      );
    } else throw Error('Unsupported option. No remote or configuration override is allowed.');
  }
  return { command, execute, state };
}
const quote = (v) =>
  typeof v === 'number' ? String(v) : "'" + String(v).replaceAll("'", "''") + "'";
export function main(args) {
  const options = parseAssetArguments(args);
  const { plan, manifest, manifestText } = trustedPlan();
  const summary = {
    storage: 'worker-assets',
    localOnly: true,
    remoteEnabled: false,
    config: configPath,
    state: options.state,
    chapterFiles: plan.summary.chapterCount,
    verseCount: plan.summary.verseCount,
    totalAssetBytes: plan.summary.totalBytes,
    indexSha256: plan.summary.indexSha256,
    corpusManifestSha256: plan.summary.manifestSha256,
  };
  if (options.command === 'plan') return { ...summary, status: 'plan', writes: 0 };
  if (options.command === 'generate') {
    generate(plan);
    return { ...summary, status: 'generated', modelConnections: 0 };
  }
  if (!options.execute) return { ...summary, status: 'registration-plan', writes: 0 };
  noLinks(options.state);
  noLinks(configPath);
  check(existsSync(join(root, configPath)), 'Generate the reviewed Assets configuration first.');
  check(
    JSON.stringify(
      validateScaffoldConfig(JSON.parse(readFileSync(join(root, configPath), 'utf8'))),
    ) === JSON.stringify(assetConfig()),
    'Assets configuration changed.',
  );
  const path = findDatabase(root, options.state),
    diagnostic = inspectDatabase(path);
  check(
    diagnostic.schemaMatchesMigrations &&
      diagnostic.migrations.some((m) => m.name === '0018_scripture_asset_storage.sql'),
    'Apply current local migrations to the isolated Assets state first.',
  );
  generate(plan);
  const db = new DatabaseSync(path, { readOnly: true });
  let current, active;
  try {
    current = db
      .prepare('SELECT * FROM scripture_corpora WHERE id=? AND version=?')
      .get(manifest.corpusId, manifest.version);
    active = db
      .prepare('SELECT version FROM scripture_corpora WHERE id=? AND active=1 AND version<>?')
      .get(manifest.corpusId, manifest.version);
  } finally {
    db.close();
  }
  check(!active, 'Another corpus revision is active; it will not be replaced.');
  if (current) {
    check(
      current.storage_type === 'assets' &&
        current.asset_index_sha256 === plan.summary.indexSha256 &&
        current.manifest_sha256 === plan.summary.manifestSha256 &&
        current.manifest_json === manifestText &&
        current.expected_verses === manifest.verseCount &&
        current.edition === manifest.edition &&
        current.language === manifest.language &&
        current.license === manifest.license,
      'Existing corpus storage/identity conflicts.',
    );
    if (current.state === 'ready') {
      check(
        current.active === 1 && current.rights_status === 'approved',
        'Existing revision is inactive or revoked; no reapproval is performed.',
      );
      return { ...summary, status: 'already-ready', writes: 0 };
    }
    check(
      current.state === 'staging' && current.active === 0 && current.rights_status === 'pending',
      'Staging policy changed; no reapproval is performed.',
    );
  }
  const statements = [];
  if (!current)
    statements.push(
      `INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at,storage_type,asset_index_sha256) VALUES(${[manifest.corpusId, manifest.version, manifest.edition, manifest.language, manifest.license, plan.summary.manifestSha256, manifestText, manifest.verseCount, Math.floor(Date.now() / 1000), 'assets', plan.summary.indexSha256].map(quote).join(',')});`,
    );
  statements.push(
    `UPDATE scripture_corpora SET state='ready',rights_status='approved',active=1 WHERE id=${quote(manifest.corpusId)} AND version=${quote(manifest.version)} AND manifest_sha256=${quote(plan.summary.manifestSha256)} AND asset_index_sha256=${quote(plan.summary.indexSha256)} AND storage_type='assets' AND state='staging' AND rights_status='pending' AND active=0;`,
  );
  const out = '.cache/scripture/assets-register-' + crypto.randomUUID() + '.sql';
  noLinks(out);
  mkdirSync(dirname(join(root, out)), { recursive: true });
  writeFileSync(join(root, out), statements.join('\n'), { flag: 'wx', mode: 0o600 });
  const result = spawnSync(
    process.execPath,
    [
      'scripts/wrangler.mjs',
      'd1',
      'execute',
      'bible-companion',
      '--local',
      '--config',
      configPath,
      '--persist-to',
      options.state,
      '--file',
      out,
    ],
    {
      cwd: root,
      env: { ...process.env, ...LOCAL_WRANGLER_ENV },
      encoding: 'utf8',
      timeout: 120000,
      maxBuffer: 1048576,
    },
  );
  check(
    result.status === 0,
    'Local Assets registration did not complete; no successful activation is claimed.',
  );
  const verify = new DatabaseSync(path, { readOnly: true });
  try {
    const row = verify
      .prepare(
        'SELECT state,rights_status,active,storage_type FROM scripture_corpora WHERE id=? AND version=?',
      )
      .get(manifest.corpusId, manifest.version);
    check(
      row?.state === 'ready' &&
        row.rights_status === 'approved' &&
        row.active === 1 &&
        row.storage_type === 'assets',
      'Assets activation was not confirmed.',
    );
    check(
      verify
        .prepare(
          'SELECT count(*) AS n FROM scripture_verses WHERE corpus_id=? AND corpus_version=?',
        )
        .get(manifest.corpusId, manifest.version).n === 0,
      'Assets mode must not require verse rows.',
    );
  } finally {
    verify.close();
  }
  return { ...summary, status: 'ready', corpusRecords: 1, verseRowsWritten: 0 };
}
/** Public, pinned metadata only; no provider/account action. Used by the separately guarded operator. */
export function pinnedAssetRegistration(nowSeconds = Math.floor(Date.now() / 1000)) {
  check(Number.isSafeInteger(nowSeconds) && nowSeconds >= 0, 'Invalid registration time');
  const { plan, manifest, manifestText } = trustedPlan();
  const identity = {
    id: manifest.corpusId,
    version: manifest.version,
    edition: manifest.edition,
    language: manifest.language,
    license: manifest.license,
    manifestSha256: plan.summary.manifestSha256,
    manifestText,
    expectedVerses: manifest.verseCount,
    indexSha256: plan.summary.indexSha256,
  };
  const values = [
    identity.id,
    identity.version,
    identity.edition,
    identity.language,
    identity.license,
    identity.manifestSha256,
    identity.manifestText,
    identity.expectedVerses,
    nowSeconds,
    'assets',
    identity.indexSha256,
  ]
    .map(quote)
    .join(',');
  const where = `id=${quote(identity.id)} AND version=${quote(identity.version)}`;
  const exact = `${where} AND edition=${quote(identity.edition)} AND language=${quote(identity.language)} AND license=${quote(identity.license)} AND manifest_sha256=${quote(identity.manifestSha256)} AND manifest_json=${quote(identity.manifestText)} AND expected_verses=${identity.expectedVerses} AND storage_type='assets' AND asset_index_sha256=${quote(identity.indexSha256)}`;
  const sql = `INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at,storage_type,asset_index_sha256) VALUES(${values}) ON CONFLICT(id,version) DO NOTHING;
UPDATE scripture_corpora SET state='ready',rights_status='approved',active=1 WHERE ${exact} AND state='staging' AND rights_status='pending' AND active=0 AND NOT EXISTS(SELECT 1 FROM scripture_corpora other WHERE other.id=${quote(identity.id)} AND other.version<>${quote(identity.version)} AND other.active=1);`;
  const readbackSql = `SELECT c.*,(SELECT count(*) FROM scripture_verses v WHERE v.corpus_id=c.id AND v.corpus_version=c.version) AS verse_count FROM scripture_corpora c WHERE c.${where};`;
  return { identity, sql, readbackSql };
}
export function validatePinnedAssetRegistration(row, identity) {
  return (
    !!row &&
    row.id === identity.id &&
    row.version === identity.version &&
    row.edition === identity.edition &&
    row.language === identity.language &&
    row.license === identity.license &&
    row.manifest_sha256 === identity.manifestSha256 &&
    row.manifest_json === identity.manifestText &&
    row.expected_verses === identity.expectedVerses &&
    row.asset_index_sha256 === identity.indexSha256 &&
    row.storage_type === 'assets' &&
    row.state === 'ready' &&
    row.rights_status === 'approved' &&
    row.active === 1 &&
    row.verse_count === 0
  );
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    console.log(JSON.stringify(main(process.argv.slice(2)), null, 2));
  } catch {
    console.error(
      'Local Assets setup failed closed. Check pinned artifacts, exact configuration and isolated migration state.',
    );
    process.exitCode = 1;
  }
}
