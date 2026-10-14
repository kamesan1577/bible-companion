#!/usr/bin/env node
/** Explicit, inspectable CLI. No remote infrastructure is provisioned implicitly. */
import { spawnSync } from 'node:child_process';
import { validateScaffoldConfig } from './config.mjs';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash, randomBytes } from 'node:crypto';
import { inviteSql } from './operator.mjs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const config = 'apps/api/wrangler.jsonc';
const [command, ...args] = process.argv.slice(2);
function run(exe, argv) {
  const result = spawnSync(exe, argv, {
    cwd: root,
    stdio: 'inherit',
    env: {
      ...process.env,
      npm_config_cache: resolve(root, '.cache/npm'),
      WRANGLER_SEND_METRICS: 'false',
    },
  });
  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }
  if (result.status !== 0) process.exit(result.status ?? 1);
}
function flags(name) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}
function configData() {
  return JSON.parse(readFileSync(resolve(root, config), 'utf8'));
}
switch (command) {
  case 'plan':
    console.log(
      `Local-first plan (no network writes):\n1. npm ci\n2. npm run validate\n3. npm run migrate\n4. npm run infra -- invite-local --role owner\n5. npm run dev\n6. npm run deploy:dry-run\n\nPending decisions: permanent RP domain, D1 account/resource ID, retention/recovery policy, verified Workers AI free-account limits and connectivity.\nRemote provisioning and deployment are NOT executed by this command. AI is disabled and no binding is configured by default.\nR2 and Queues are not needed for the initial text-only service and are not provisioned.\nPrivate repository setup requires an already-authorized gh CLI; see private-repo --execute.`,
    );
    break;
  case 'validate-config': {
    const c = validateScaffoldConfig(configData());
    console.log('Configuration valid for ' + c.vars.ENVIRONMENT + '; inference disconnected.');
    break;
  }
  case 'migrate-local':
    run(process.execPath, [
      'scripts/wrangler.mjs',
      'd1',
      'migrations',
      'apply',
      'bible-companion',
      '--local',
      '--config',
      config,
    ]);
    break;
  case 'deploy-dry-run':
    validateScaffoldConfig(configData());
    run(process.execPath, ['scripts/wrangler.mjs', 'deploy', '--dry-run', '--config', config]);
    break;
  case 'invite-local': {
    const role = flags('--role') ?? 'member';
    if (!['owner', 'member'].includes(role)) throw Error('Role must be owner or member');
    const token = randomBytes(32).toString('base64url');
    const hash = createHash('sha256').update(token).digest('base64url');
    const seconds = Math.floor(Date.now() / 1000);
    const expires = seconds + 3600;
    // Token goes only to the invoking terminal, never to process args or a tracked file.
    if (args.length && (args.length !== 2 || args[0] !== '--role'))
      throw Error('Only --role owner|member is supported');
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
        '--command',
        inviteSql(role, hash, expires, seconds),
        '--json',
      ],
      { cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: 1024 * 1024 },
    );
    if (result.status !== 0)
      throw Error('Local invitation failed; inspect local database before retrying');
    let rows;
    try {
      rows = JSON.parse(result.stdout);
    } catch {
      throw Error('Local invitation result was not verified');
    }
    if (
      !Array.isArray(rows) ||
      !rows.some((r) => r.success === true && r.results?.some((row) => row.token_hash === hash))
    )
      throw Error(
        'Invitation not created: owner/pending owner already exists or database rejected it',
      );
    console.log('Local ' + role + ' invitation (expires in one hour; keep private): ' + token);
    break;
  }
  case 'private-repo': {
    const repo = flags('--name') ?? 'bible-companion';
    if (!/^[A-Za-z0-9_.-]+$/.test(repo)) throw Error('Invalid repository name');
    if (!args.includes('--execute')) {
      console.log(
        'Requires existing authorized GitHub CLI. Would run: gh repo create ' +
          repo +
          ' --private --source=. --remote=origin; then verify visibility. No push or public deployment. Pass --execute only after authorization.',
      );
      break;
    }
    run('gh', ['auth', 'status']);
    run('gh', ['repo', 'create', repo, '--private', '--source=.', '--remote=origin']);
    const result = spawnSync('gh', ['repo', 'view', '--json', 'visibility,url'], {
      cwd: root,
      encoding: 'utf8',
    });
    if (result.status !== 0)
      throw Error('Repository created but verification failed; inspect before retrying');
    const meta = JSON.parse(result.stdout);
    if (meta.visibility !== 'PRIVATE')
      throw Error('Repository is not private; stop before pushing');
    console.log('Verified private repository: ' + meta.url);
    break;
  }
  case 'init-production-config': {
    const origin = flags('--origin');
    const rp = flags('--rp-id');
    const databaseId = flags('--database-id');
    if (!origin || !rp || !databaseId)
      throw Error('Require --origin, --rp-id, --database-id. Use the final stable HTTPS domain.');
    const u = new URL(origin);
    if (
      u.protocol !== 'https:' ||
      u.origin !== origin ||
      (u.hostname !== rp && !u.hostname.endsWith('.' + rp))
    )
      throw Error('Invalid stable RP origin');
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(databaseId))
      throw Error('Invalid D1 ID');
    const c = configData();
    c.vars = { ...c.vars, ENVIRONMENT: 'production', AUTH_ORIGIN: origin, RP_ID: rp };
    c.d1_databases[0].database_id = databaseId;
    validateScaffoldConfig(c);
    const path = resolve(root, 'apps/api/wrangler.production.json');
    writeFileSync(path, JSON.stringify(c, null, 2) + '\n', { flag: 'wx' });
    console.log('Wrote local production config. It has not been deployed.');
    break;
  }
  default:
    console.log(
      'Commands: plan, validate-config, migrate-local, invite-local, deploy-dry-run, private-repo, init-production-config',
    );
    if (command) process.exitCode = 1;
}
