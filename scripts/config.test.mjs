import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  validateScaffoldConfig,
  validateLocalWranglerInvocation,
  LOCAL_WRANGLER_ENV,
} from './config.mjs';
const fixture = () =>
  JSON.parse(readFileSync(new URL('../apps/api/wrangler.jsonc', import.meta.url), 'utf8'));
test('checked-in profile is disconnected and valid', () =>
  assert.doesNotThrow(() => validateScaffoldConfig(fixture())));
test('unapproved bindings and public routes fail closed', () => {
  for (const patch of [
    { ai: { binding: 'AI' } },
    { r2_buckets: [] },
    { queues: {} },
    { workers_dev: true },
    { routes: ['*/*'] },
    { triggers: { crons: ['* * * * *'] } },
    { observability: { enabled: true } },
    { env: { production: {} } },
  ])
    assert.throws(() => validateScaffoldConfig({ ...fixture(), ...patch }));
});
test('malformed auth, budgets and model connection flags cannot pass scaffolding', () => {
  for (const patch of [
    { ENVIRONMENT: 'staging' },
    { AUTH_ORIGIN: 'ftp://localhost:8787' },
    { NATIVE_CALLBACK: 'other://auth/callback' },
    { DAILY_APP_BUDGET: 'NaN' },
    { DAILY_APP_BUDGET: '0' },
    { DAILY_APP_BUDGET: '200', DAILY_USER_BUDGET: '201' },
    { AI_ENABLED: 'true' },
    { AI_ENABLED: 'false', CONNECTED_MODELS: '["@cf/model"]' },
  ]) {
    const c = fixture();
    Object.assign(c.vars, patch);
    assert.throws(() => validateScaffoldConfig(c));
  }
});
test('production configuration requires real-looking identity without provisioning anything', () => {
  const c = fixture();
  Object.assign(c.vars, {
    ENVIRONMENT: 'production',
    AUTH_ORIGIN: 'https://bible.example.org',
    RP_ID: 'bible.example.org',
  });
  assert.throws(() => validateScaffoldConfig(c));
  c.d1_databases[0].database_id = '11111111-1111-4111-8111-111111111111';
  assert.doesNotThrow(() => validateScaffoldConfig(c));
  Object.assign(c.vars, { AUTH_ORIGIN: 'https://localhost', RP_ID: 'localhost' });
  assert.throws(() => validateScaffoldConfig(c));
});

test('local wrapper cannot silently deploy, provision, log in or select remote D1', () => {
  for (const args of [
    ['deploy'],
    ['login'],
    ['d1', 'create', 'db'],
    [
      'd1',
      'execute',
      'bible-companion',
      '--local',
      '--remote',
      '--config',
      'apps/api/wrangler.jsonc',
    ],
    ['dev', '--remote', '--config', 'apps/api/wrangler.jsonc'],
    ['deploy', '--dry-run'],
  ])
    assert.throws(() => validateLocalWranglerInvocation(args));
  for (const args of [
    ['dev'],
    ['deploy', '--dry-run'],
    ['d1', 'migrations', 'apply', 'bible-companion', '--local'],
    ['d1', 'execute', 'bible-companion', '--local'],
  ])
    assert.equal(
      validateLocalWranglerInvocation([...args, '--config', 'apps/api/wrangler.jsonc']),
      'apps/api/wrangler.jsonc',
    );
});

test('boolean flag aliases, duplicate configs and unreviewed overrides fail closed', () => {
  for (const extra of [
    ['--dry-run=false'],
    ['--remote=true'],
    ['--var', 'AI_ENABLED:true'],
    ['--config', 'apps/api/wrangler.jsonc'],
    ['--env', 'production'],
    ['--experimental-remote-bindings'],
    ['--outdir', '../outside'],
    ['--outdir', '.cache/../outside'],
  ])
    assert.throws(() =>
      validateLocalWranglerInvocation([
        'deploy',
        '--dry-run',
        '--config',
        'apps/api/wrangler.jsonc',
        ...extra,
      ]),
    );
  assert.doesNotThrow(() =>
    validateLocalWranglerInvocation([
      'd1',
      'migrations',
      'apply',
      'bible-companion',
      '--local',
      '--config',
      'apps/api/wrangler.jsonc',
      '--persist-to',
      '.cache/d1-fresh',
    ]),
  );
});

test('generated production config path remains compatible with guarded dry-run', () =>
  assert.equal(
    validateLocalWranglerInvocation([
      'deploy',
      '--dry-run',
      '--config',
      'apps/api/wrangler.production.json',
    ]),
    'apps/api/wrangler.production.json',
  ));

test('local Wrangler environment suppresses supported update and telemetry side effects', () =>
  assert.deepEqual(LOCAL_WRANGLER_ENV, {
    WRANGLER_HIDE_BANNER: 'true',
    WRANGLER_SEND_METRICS: 'false',
    WRANGLER_SEND_ERROR_REPORTS: 'false',
    CLOUDFLARE_CF_FETCH_ENABLED: 'false',
  }));

test('optional scripture Assets profile cannot bypass Worker policy routing', () => {
  const config = JSON.parse(
    readFileSync(new URL('../apps/api/wrangler.jsonc', import.meta.url), 'utf8'),
  );
  config.assets = {
    directory: '../../.cache/scripture/assets',
    binding: 'SCRIPTURE_ASSETS',
    run_worker_first: true,
    html_handling: 'none',
    not_found_handling: 'none',
  };
  assert.doesNotThrow(() => validateScaffoldConfig(config));
  for (const change of [
    { run_worker_first: false },
    { run_worker_first: ['/v1/*'] },
    { not_found_handling: 'single-page-application' },
    { directory: '../../' },
    { binding: 'PUBLIC_ASSETS' },
  ])
    assert.throws(() =>
      validateScaffoldConfig({ ...config, assets: { ...config.assets, ...change } }),
    );
  assert.equal(
    validateLocalWranglerInvocation([
      'deploy',
      '--dry-run',
      '--config',
      'apps/api/wrangler.assets.json',
    ]),
    'apps/api/wrangler.assets.json',
  );
});

test('prepared operator profiles validate free-only activation without opening the local dev wrapper', async () => {
  const { validateOperatorConfig } = await import('./config.mjs');
  const { MODEL_TERMS_POLICY_VERSION } = await import('../packages/ai-harness/src/registry.ts');
  const config = fixture(),
    id = '@cf/google/gemma-4-26b-a4b-it';
  Object.assign(config, {
    account_id: 'a'.repeat(32),
    routes: [{ pattern: 'reader.example.org', custom_domain: true }],
    preview_urls: false,
    limits: { cpu_ms: 10 },
    ai: { binding: 'AI' },
  });
  Object.assign(config.vars, {
    ENVIRONMENT: 'production',
    RP_ID: 'reader.example.org',
    AUTH_ORIGIN: 'https://reader.example.org',
    AI_ENABLED: 'true',
    CONNECTED_MODELS: JSON.stringify([id]),
    TERMS_REVIEWED_MODELS: JSON.stringify([id]),
    TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
    AI_BUDGET_MODE: 'free-provider-hard-stop',
    WORKERS_AI_ACCOUNT_ID: 'a'.repeat(32),
    AI_FREE_RECEIPT_ID: 'explicit-review-1',
    ALLOWED_ANSWER_MODES: '["reviewed-claim-selection","grounded-generation"]',
    DEFAULT_ANSWER_MODE: 'grounded-generation',
  });
  config.d1_databases[0].database_id = '11111111-1111-4111-8111-111111111111';
  assert.doesNotThrow(() => validateOperatorConfig(config));
  const slotConfig = structuredClone(config);
  delete slotConfig.vars.AI_FREE_RECEIPT_ID;
  Object.assign(slotConfig.vars, { AI_FREE_RECEIPT_MODE: 'slot', AI_FREE_RECEIPT_SLOT: 'main' });
  assert.doesNotThrow(() => validateOperatorConfig(slotConfig));
  for (const patch of [
    { AI_FREE_RECEIPT_MODE: 'unknown' },
    { AI_FREE_RECEIPT_MODE: 'pinned' },
    { AI_FREE_RECEIPT_MODE: undefined },
    { AI_FREE_RECEIPT_SLOT: '' },
    { AI_FREE_RECEIPT_SLOT: '../main' },
    { AI_FREE_RECEIPT_ID: 'hidden-fallback' },
  ])
    assert.throws(() =>
      validateOperatorConfig({ ...slotConfig, vars: { ...slotConfig.vars, ...patch } }),
    );
  for (const patch of [
    { AI_BUDGET_MODE: 'paid' },
    { WORKERS_AI_ACCOUNT_ID: 'b'.repeat(32) },
    { AI_FREE_RECEIPT_ID: '' },
    { TERMS_REVIEW_VERSION: 'old' },
    { TERMS_REVIEWED_MODELS: '[]' },
    { DEFAULT_ANSWER_MODE: 'unknown' },
    { ALLOWED_ANSWER_MODES: '[]' },
    { CONNECTED_MODELS: '["@cf/moonshotai/kimi-k2.6"]' },
  ])
    assert.throws(() => validateOperatorConfig({ ...config, vars: { ...config.vars, ...patch } }));
  for (const patch of [
    { routes: [{ pattern: 'other.example.org', custom_domain: true }] },
    { ai: { binding: 'AI', remote: true } },
    { limits: { cpu_ms: 300000 } },
    { preview_urls: true },
    { r2_buckets: [] },
  ])
    assert.throws(() => validateOperatorConfig({ ...config, ...patch }));
  assert.throws(() =>
    validateLocalWranglerInvocation(['dev', '--config', 'apps/api/wrangler.operator.json']),
  );
  assert.throws(() =>
    validateLocalWranglerInvocation(['deploy', '--config', 'apps/api/wrangler.operator.json']),
  );
  assert.equal(
    validateLocalWranglerInvocation([
      'deploy',
      '--dry-run',
      '--config',
      'apps/api/wrangler.operator.json',
    ]),
    'apps/api/wrangler.operator.json',
  );
});
