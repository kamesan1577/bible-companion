import {
  getModel as getOperatorModel,
  MODEL_TERMS_POLICY_VERSION as OPERATOR_TERMS_POLICY_VERSION,
} from '../packages/ai-harness/src/registry.ts';
import { z } from 'zod';
import { validateAuthConfig } from '../packages/core/src/auth-config.ts';
const integer = z
  .string()
  .regex(/^[1-9][0-9]{0,8}$/)
  .transform(Number)
  .refine(Number.isSafeInteger);
const schema = z
  .object({
    name: z.literal('bible-companion'),
    main: z.literal('src/index.ts'),
    compatibility_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    compatibility_flags: z.array(z.literal('nodejs_compat')).length(1),
    workers_dev: z.literal(false),
    observability: z.object({ enabled: z.literal(false) }).strict(),
    vars: z
      .object({
        ENVIRONMENT: z.enum(['development', 'production']),
        RP_ID: z.string().min(1),
        AUTH_ORIGIN: z.string().url(),
        NATIVE_CALLBACK: z.literal('biblecompanion://auth/callback'),
        AI_ENABLED: z.literal('false'),
        CONNECTED_MODELS: z.literal('[]'),
        TERMS_REVIEWED_MODELS: z.literal('[]'),
        TERMS_REVIEW_VERSION: z.literal(''),
        DEFAULT_MODEL_ID: z.string().startsWith('@cf/'),
        DAILY_APP_BUDGET: integer,
        DAILY_USER_BUDGET: integer,
        AI_RESERVATION_UNITS: integer,
      })
      .strict(),
    d1_databases: z
      .array(
        z
          .object({
            binding: z.literal('DB'),
            database_name: z.literal('bible-companion'),
            database_id: z
              .string()
              .regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/),
            migrations_dir: z.literal('migrations'),
          })
          .strict(),
      )
      .length(1),
    assets: z
      .object({
        directory: z.literal('../../.cache/scripture/assets'),
        binding: z.literal('SCRIPTURE_ASSETS'),
        run_worker_first: z.literal(true),
        html_handling: z.literal('none'),
        not_found_handling: z.literal('none'),
      })
      .strict()
      .optional(),
    $schema: z.string().optional(),
  })
  .strict();
/** This scaffold validates only the approved, disconnected no-inference deployment profile. */
export function validateScaffoldConfig(value) {
  const parsed = schema.parse(value);
  validateAuthConfig(parsed.vars);
  if (parsed.vars.DAILY_USER_BUDGET > parsed.vars.DAILY_APP_BUDGET)
    throw Error('User allowance exceeds application allowance');
  if (
    parsed.vars.ENVIRONMENT === 'production' &&
    parsed.d1_databases[0].database_id === '00000000-0000-0000-0000-000000000000'
  )
    throw Error('Production D1 ID must be configured');
  return value;
}

export function validateLocalWranglerInvocation(args) {
  let offset;
  let command;
  if (args[0] === 'dev') {
    command = 'dev';
    offset = 1;
  } else if (args[0] === 'deploy') {
    command = 'deploy';
    offset = 1;
  } else if (
    args[0] === 'd1' &&
    args[1] === 'migrations' &&
    args[2] === 'apply' &&
    args[3] === 'bible-companion'
  ) {
    command = 'migrate';
    offset = 4;
  } else if (args[0] === 'd1' && args[1] === 'execute' && args[2] === 'bible-companion') {
    command = 'execute';
    offset = 3;
  } else
    throw Error(
      'Only the reviewed local development, local database and dry-run commands are supported.',
    );
  const booleans = new Set(
    command === 'deploy'
      ? ['--dry-run']
      : command === 'execute'
        ? ['--local', '--json']
        : ['--local'],
  );
  const values = new Set([
    '--config',
    ...(command === 'dev' ? ['--port'] : []),
    ...(command === 'deploy' ? ['--outdir'] : []),
    ...(command === 'execute' ? ['--command', '--file'] : []),
    ...(command !== 'deploy' ? ['--persist-to'] : []),
  ]);
  const seen = new Map();
  for (let i = offset; i < args.length; i++) {
    const flag = args[i];
    if (seen.has(flag)) throw Error('Duplicate CLI options are not allowed.');
    if (booleans.has(flag)) {
      seen.set(flag, true);
      continue;
    }
    if (!values.has(flag) || typeof args[i + 1] !== 'string' || args[i + 1].startsWith('--'))
      throw Error('Unsupported CLI option: ' + flag);
    seen.set(flag, args[++i]);
  }
  if (command === 'deploy' && !seen.has('--dry-run')) throw Error('Deployment must be a dry-run.');
  if (['migrate', 'execute'].includes(command) && !seen.has('--local'))
    throw Error('Database operations must be local.');
  const config = seen.get('--config');
  if (
    typeof config !== 'string' ||
    !/^apps\/api\/(?:wrangler\.jsonc|wrangler\.production\.json|wrangler\.assets\.json|wrangler\.operator\.json)$/.test(
      config,
    )
  )
    throw Error('An explicit reviewed in-repository config is required.');
  if (command === 'dev' && config === 'apps/api/wrangler.operator.json')
    throw Error('Operator profiles cannot run a development server or live inference.');
  for (const flag of ['--persist-to', '--outdir']) {
    const path = seen.get(flag);
    if (
      path !== undefined &&
      (!/^\.cache\/[A-Za-z0-9_./-]+$/.test(path) || path.split('/').some((p) => p === '..'))
    )
      throw Error('Local output paths must stay under .cache.');
  }
  if (
    seen.has('--port') &&
    (!/^[0-9]{4,5}$/.test(seen.get('--port')) || Number(seen.get('--port')) > 65535)
  )
    throw Error('Invalid local port.');
  if (seen.has('--file')) {
    const path = seen.get('--file');
    if (
      !/^(?:apps\/api\/migrations|\.cache)\/[A-Za-z0-9_./-]+\.sql$/.test(path) ||
      path.split('/').some((p) => p === '..')
    )
      throw Error('SQL files must be reviewed local files.');
  }
  return config;
}

/** Supported by installed Wrangler; local diagnostics must not perform update/telemetry calls. */
export const LOCAL_WRANGLER_ENV = Object.freeze({
  WRANGLER_HIDE_BANNER: 'true',
  WRANGLER_SEND_METRICS: 'false',
  WRANGLER_SEND_ERROR_REPORTS: 'false',
  CLOUDFLARE_CF_FETCH_ENABLED: 'false',
});

/** Prepared operator profile. Validation does not authorize applying it or attest account evidence. */
export function validateOperatorConfig(value) {
  const candidate = structuredClone(value);
  const accountId = z
    .string()
    .regex(/^[a-f0-9]{32}$/)
    .parse(candidate.account_id);
  const vars = candidate.vars;
  if (!vars || vars.ENVIRONMENT !== 'production')
    throw Error('Operator profile must use production auth configuration');
  const enabled = z.enum(['true', 'false']).parse(vars.AI_ENABLED) === 'true';
  for (const key of ['DAILY_APP_BUDGET', 'DAILY_USER_BUDGET'])
    if (
      typeof vars[key] !== 'string' ||
      !/^[1-9][0-9]*$/.test(vars[key]) ||
      Number(vars[key]) > 10000
    )
      throw Error('Operator allowances must stay within the Workers Free daily limit');
  const parseIds = (raw) =>
    z
      .array(z.string())
      .max(22)
      .refine((a) => new Set(a).size === a.length)
      .parse(JSON.parse(raw));
  const connected = parseIds(vars.CONNECTED_MODELS),
    reviewed = parseIds(vars.TERMS_REVIEWED_MODELS);
  const allowed = z
    .array(z.enum(['reviewed-claim-selection', 'grounded-generation']))
    .min(1)
    .max(2)
    .refine((a) => new Set(a).size === a.length)
    .parse(JSON.parse(vars.ALLOWED_ANSWER_MODES ?? '["reviewed-claim-selection"]'));
  if (!allowed.includes(vars.DEFAULT_ANSWER_MODE ?? 'reviewed-claim-selection'))
    throw Error('Default mode is not allowed');
  const route = z
    .array(z.object({ pattern: z.string(), custom_domain: z.literal(true) }).strict())
    .length(1)
    .parse(candidate.routes);
  const origin = new URL(vars.AUTH_ORIGIN);
  if (origin.port || route[0].pattern !== origin.hostname)
    throw Error('Custom domain must exactly match the authentication origin');
  if (candidate.ai !== undefined)
    z.object({ binding: z.literal('AI') })
      .strict()
      .parse(candidate.ai);
  if (candidate.limits !== undefined)
    z.object({ cpu_ms: z.literal(10) })
      .strict()
      .parse(candidate.limits);
  if (candidate.triggers !== undefined)
    z.object({ crons: z.array(z.literal('17 3 * * *')).length(1) })
      .strict()
      .parse(candidate.triggers);
  if (candidate.preview_urls !== undefined && candidate.preview_urls !== false)
    throw Error('Preview URLs must be disabled');
  if (enabled) {
    if (
      !candidate.ai ||
      vars.AI_BUDGET_MODE !== 'free-provider-hard-stop' ||
      vars.WORKERS_AI_ACCOUNT_ID !== accountId ||
      !(
        ((vars.AI_FREE_RECEIPT_MODE ?? 'pinned') === 'pinned' &&
          /^[A-Za-z0-9_-]{1,100}$/.test(vars.AI_FREE_RECEIPT_ID ?? '') &&
          vars.AI_FREE_RECEIPT_SLOT === undefined) ||
        (vars.AI_FREE_RECEIPT_MODE === 'slot' &&
          /^[A-Za-z0-9_-]{1,100}$/.test(vars.AI_FREE_RECEIPT_SLOT ?? '') &&
          vars.AI_FREE_RECEIPT_ID === undefined)
      )
    )
      throw Error(
        'Active operator profile requires exact account-bound free-only receipt configuration',
      );
    if (
      !connected.length ||
      reviewed.length !== connected.length ||
      connected.some((id) => !reviewed.includes(id)) ||
      !connected.includes(vars.DEFAULT_MODEL_ID)
    )
      throw Error('Every selected model needs a current explicit terms review');
    for (const id of connected)
      if (getOperatorModel(id).billingTier !== 'free-allocation-candidate')
        throw Error('Only free-allocation candidates may be activated');
    if (vars.TERMS_REVIEW_VERSION !== OPERATOR_TERMS_POLICY_VERSION)
      throw Error('Model terms review version is stale');
  } else if (
    candidate.ai ||
    connected.length ||
    reviewed.length ||
    vars.TERMS_REVIEW_VERSION !== '' ||
    (vars.AI_BUDGET_MODE !== undefined && vars.AI_BUDGET_MODE !== 'strict-proof') ||
    vars.WORKERS_AI_ACCOUNT_ID ||
    vars.AI_FREE_RECEIPT_ID ||
    vars.AI_FREE_RECEIPT_MODE !== undefined ||
    vars.AI_FREE_RECEIPT_SLOT !== undefined
  )
    throw Error('Disconnected profile cannot retain active provider configuration');
  delete candidate.account_id;
  delete candidate.routes;
  delete candidate.ai;
  delete candidate.limits;
  delete candidate.preview_urls;
  delete candidate.triggers;
  for (const field of [
    'AI_BUDGET_MODE',
    'WORKERS_AI_ACCOUNT_ID',
    'AI_FREE_RECEIPT_ID',
    'AI_FREE_RECEIPT_MODE',
    'AI_FREE_RECEIPT_SLOT',
    'ALLOWED_ANSWER_MODES',
    'DEFAULT_ANSWER_MODE',
  ])
    delete candidate.vars[field];
  candidate.vars.AI_ENABLED = 'false';
  candidate.vars.CONNECTED_MODELS = '[]';
  candidate.vars.TERMS_REVIEWED_MODELS = '[]';
  candidate.vars.TERMS_REVIEW_VERSION = '';
  validateScaffoldConfig(candidate);
  return value;
}
