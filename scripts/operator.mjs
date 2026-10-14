#!/usr/bin/env node
/** Local preparation by default. Remote execution is a separate, exact-target opt-in. */
import { z } from 'zod';
import {
  readFileSync,
  readdirSync,
  readSync,
  fstatSync,
  writeFileSync,
  mkdirSync,
  lstatSync,
  constants,
  openSync,
  closeSync,
} from 'node:fs';
import { resolve, dirname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { CATALOG_DATA } from '../packages/ai-harness/src/catalog.ts';
import {
  MODEL_TERMS_POLICY_VERSION,
  PUBLISHED_MODEL_TERMS,
} from '../packages/ai-harness/src/model-terms.ts';
import { validateAuthConfig } from '../packages/core/src/auth-config.ts';
import * as configValidation from './config.mjs';
import {
  pinnedAssetRegistration,
  validatePinnedAssetRegistration,
} from './scripture-assets-config.mjs';
import {
  readBundledScriptureAssetInputs,
  planScriptureAssets,
  writeScriptureAssetPlan,
} from './build-scripture-assets.mjs';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const CONFIG_PATH = 'apps/api/wrangler.operator.json';
const POLICY = 'workers-ai-free-hard-stop.v1';
const evidence = z.string().regex(/^sha256:[a-f0-9]{64}$/);
const stamp = z.iso.datetime();
const account = z.string().regex(/^[a-f0-9]{32}$/);
const uuid = z
  .string()
  .regex(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
  .refine((v) => v !== '00000000-0000-0000-0000-000000000000');
const mode = z.enum(['reviewed-claim-selection', 'grounded-generation']);
const receiptSchema = z
  .object({
    schemaVersion: z.literal(1),
    policyVersion: z.literal(POLICY),
    accountId: account,
    verifiedAt: stamp,
    expiresAt: stamp,
    evidenceRef: evidence,
    accountPlan: z.literal('free'),
    providerRoute: z.literal('direct-workers-binding'),
    gatewayCredits: z.literal(false),
    paidModels: z.literal(false),
    fallbacks: z.literal(false),
  })
  .strict();
const termsUrl = z
  .string()
  .url()
  .refine((v) => {
    const u = new URL(v);
    return (
      u.protocol === 'https:' &&
      !u.username &&
      !u.password &&
      !u.search &&
      !u.hash &&
      [
        'developers.cloudflare.com',
        'www.cloudflare.com',
        'ai.google.dev',
        'github.com',
        'huggingface.co',
      ].includes(u.hostname)
    );
  });
const profileSchema = z
  .object({
    schemaVersion: z.literal(1),
    accountId: account,
    databaseId: uuid,
    origin: z.string().url(),
    rpId: z.string().min(3).max(253),
    corpus: z.enum(['none', 'webp-pinned-assets']).default('none'),
    cleanup: z.enum(['none', 'daily-utc']).default('none'),
    dailyAppBudget: z.number().int().min(1).max(10000).default(9000),
    dailyUserBudget: z.number().int().min(1).max(10000).default(2000),
    modelIds: z.array(z.string()).max(22),
    defaultModelId: z.string(),
    answerModes: z.array(mode).min(1).max(2),
    defaultAnswerMode: mode,
    experimentalGroundedReviewed: z.boolean(),
    freeReceiptSlot: z
      .object({
        id: z.string().regex(/^[A-Za-z0-9_-]{1,100}$/),
        expectedGeneration: z
          .number()
          .int()
          .min(0)
          .max(Number.MAX_SAFE_INTEGER - 1),
        expectedReceiptId: z
          .string()
          .regex(/^[A-Za-z0-9_-]{1,100}$/)
          .nullable(),
      })
      .strict()
      .optional(),
    freeReceipt: z
      .object({ id: z.string().regex(/^[a-zA-Z0-9_-]{1,100}$/), receipt: receiptSchema })
      .strict()
      .nullable(),
    termsReviews: z
      .array(
        z
          .object({
            modelId: z.string(),
            status: z.enum(['pending', 'reviewed', 'rejected']),
            policyVersion: z.literal(MODEL_TERMS_POLICY_VERSION),
            evidenceRef: evidence.nullable(),
            reviewedAt: stamp.nullable(),
            termsUrls: z.array(termsUrl).max(8),
          })
          .strict(),
      )
      .length(22),
  })
  .strict();
export function validateOperatorProfile(
  value,
  nowMs = Date.now(),
  { allowExpiredReceipt = false } = {},
) {
  const p = profileSchema.parse(value);
  if (p.dailyUserBudget > p.dailyAppBudget)
    throw Error('User allowance must not exceed application allowance');
  validateAuthConfig({
    ENVIRONMENT: 'production',
    AUTH_ORIGIN: p.origin,
    RP_ID: p.rpId,
    NATIVE_CALLBACK: 'biblecompanion://auth/callback',
  });
  if (new URL(p.origin).port || !/^[a-z0-9.-]+$/.test(p.rpId))
    throw Error('Stable HTTPS origin without port required');
  const ids = CATALOG_DATA.map((m) => m.id);
  if (
    new Set(p.termsReviews.map((r) => r.modelId)).size !== 22 ||
    p.termsReviews.some((r) => !ids.includes(r.modelId))
  )
    throw Error('One distinct terms review entry for each catalog model is required');
  if (new Set(p.modelIds).size !== p.modelIds.length || p.modelIds.some((id) => !ids.includes(id)))
    throw Error('Unknown or duplicate model');
  if (
    new Set(p.answerModes).size !== p.answerModes.length ||
    !p.answerModes.includes(p.defaultAnswerMode)
  )
    throw Error('Invalid answer modes');
  if (p.answerModes.includes('grounded-generation') && !p.experimentalGroundedReviewed)
    throw Error('Experimental grounded mode requires explicit review');
  if (
    !ids.includes(p.defaultModelId) ||
    (p.modelIds.length && !p.modelIds.includes(p.defaultModelId))
  )
    throw Error('Default model must be in connected set');
  for (const r of p.termsReviews) {
    if (
      r.status === 'reviewed' &&
      (!r.evidenceRef || !r.reviewedAt || Date.parse(r.reviewedAt) > nowMs || !r.termsUrls.length)
    )
      throw Error('Reviewed terms require real dated evidence and terms URLs');
    if (r.status !== 'reviewed' && (r.evidenceRef !== null || r.reviewedAt !== null))
      throw Error('Pending/rejected terms cannot claim review evidence');
  }
  if (
    !p.modelIds.length &&
    (p.freeReceipt || p.freeReceiptSlot || p.answerModes.includes('grounded-generation'))
  )
    throw Error('Disconnected profile must not carry activation receipt or experimental mode');
  if (p.modelIds.length) {
    if (!p.freeReceipt) throw Error('Free account evidence receipt required');
    if (
      p.freeReceiptSlot &&
      ((p.freeReceiptSlot.expectedGeneration === 0) !==
        (p.freeReceiptSlot.expectedReceiptId === null) ||
        p.freeReceiptSlot.expectedReceiptId === p.freeReceipt.id)
    )
      throw Error(
        'Slot rotation requires exact previous generation and different previous receipt; initialization uses 0/null',
      );
    const r = p.freeReceipt.receipt;
    const checked = Date.parse(r.verifiedAt),
      expires = Date.parse(r.expiresAt);
    if (
      !Number.isFinite(nowMs) ||
      r.accountId !== p.accountId ||
      checked > nowMs ||
      expires <= checked ||
      expires - checked > 86400000
    )
      throw Error('Account mismatch, future or overlong receipt');
    if (!allowExpiredReceipt && expires <= nowMs)
      throw Error(
        p.freeReceiptSlot
          ? 'Free-account receipt expired. Review fresh genuine evidence, install a new receipt ID, then separately authorize rotate-receipt-slot with the exact previous generation and receipt ID. An existing same-slot deployment needs no redeploy. Daily budget reset does not renew evidence.'
          : 'Free-account receipt expired. Review fresh genuine account evidence, use a new receipt ID, prepare a new config, then explicitly authorize install-receipt and deploy. See docs/operator-activation.md#daily-use-and-receipt-renewal; waiting for the daily budget reset does not renew evidence.',
      );
    for (const id of p.modelIds) {
      const m = CATALOG_DATA.find((m) => m.id === id);
      if (m.provider !== 'cloudflare-workers-ai' || m.billingTier !== 'free-allocation-candidate')
        throw Error('Paid or unknown provider is forbidden');
      if (p.termsReviews.find((r) => r.modelId === id).status !== 'reviewed')
        throw Error('Selected model terms are not reviewed');
    }
  }
  return p;
}
export function profileTemplate() {
  return {
    schemaVersion: 1,
    accountId: 'REPLACE_WITH_VERIFIED_ACCOUNT_ID',
    databaseId: 'REPLACE_WITH_EXISTING_D1_ID',
    origin: 'https://REPLACE_WITH_STABLE_DOMAIN',
    rpId: 'REPLACE_WITH_STABLE_DOMAIN',
    corpus: 'none',
    cleanup: 'none',
    dailyAppBudget: 9000,
    dailyUserBudget: 2000,
    modelIds: [],
    defaultModelId: CATALOG_DATA[0].id,
    answerModes: ['reviewed-claim-selection'],
    defaultAnswerMode: 'reviewed-claim-selection',
    experimentalGroundedReviewed: false,
    freeReceipt: null,
    termsReviews: CATALOG_DATA.map((m) => ({
      modelId: m.id,
      status: 'pending',
      policyVersion: MODEL_TERMS_POLICY_VERSION,
      evidenceRef: null,
      reviewedAt: null,
      termsUrls: PUBLISHED_MODEL_TERMS[m.id] ? [PUBLISHED_MODEL_TERMS[m.id]] : [],
    })),
  };
}
export function profileToConfig(value, nowMs = Date.now(), root = ROOT, options = {}) {
  const p = validateOperatorProfile(value, nowMs, options);
  const c = JSON.parse(readFileSync(resolve(root, 'apps/api/wrangler.jsonc'), 'utf8'));
  c.account_id = p.accountId;
  c.preview_urls = false;
  c.limits = { cpu_ms: 10 };
  c.routes = [{ pattern: new URL(p.origin).hostname, custom_domain: true }];
  c.d1_databases[0].database_id = p.databaseId;
  c.vars = {
    ...c.vars,
    DAILY_APP_BUDGET: String(p.dailyAppBudget),
    DAILY_USER_BUDGET: String(p.dailyUserBudget),
    ENVIRONMENT: 'production',
    AUTH_ORIGIN: p.origin,
    RP_ID: p.rpId,
    AI_ENABLED: p.modelIds.length ? 'true' : 'false',
    CONNECTED_MODELS: JSON.stringify(p.modelIds),
    TERMS_REVIEWED_MODELS: JSON.stringify(p.modelIds),
    TERMS_REVIEW_VERSION: p.modelIds.length ? MODEL_TERMS_POLICY_VERSION : '',
    DEFAULT_MODEL_ID: p.defaultModelId,
    ALLOWED_ANSWER_MODES: JSON.stringify(p.answerModes),
    DEFAULT_ANSWER_MODE: p.defaultAnswerMode,
  };
  if (p.cleanup === 'daily-utc') c.triggers = { crons: ['17 3 * * *'] };
  if (p.corpus === 'webp-pinned-assets')
    c.assets = {
      directory: '../../.cache/scripture/assets',
      binding: 'SCRIPTURE_ASSETS',
      run_worker_first: true,
      html_handling: 'none',
      not_found_handling: 'none',
    };
  if (p.modelIds.length) {
    c.ai = { binding: 'AI' };
    Object.assign(c.vars, {
      AI_BUDGET_MODE: 'free-provider-hard-stop',
      WORKERS_AI_ACCOUNT_ID: p.accountId,
      ...(p.freeReceiptSlot
        ? { AI_FREE_RECEIPT_MODE: 'slot', AI_FREE_RECEIPT_SLOT: p.freeReceiptSlot.id }
        : { AI_FREE_RECEIPT_ID: p.freeReceipt.id }),
    });
  }
  if (!configValidation.validateOperatorConfig)
    throw Error('Operator config validator is not installed');
  configValidation.validateOperatorConfig(c);
  return c;
}
/** Only exact generated public files may reach the Assets uploader. Extra files fail closed. */
export function preparePinnedAssets(repositoryRoot = ROOT) {
  if (resolve(repositoryRoot) !== ROOT)
    throw Error('Asset build must use the checked-out repository');
  const plan = planScriptureAssets(readBundledScriptureAssetInputs());
  const summary = writeScriptureAssetPlan(plan, '.cache/scripture/assets');
  const directory = resolve(ROOT, '.cache/scripture/assets');
  const expected = new Set(plan.files.map((file) => file.path.slice(1)));
  function inspect(path, prefix = '') {
    for (const name of readdirSync(path)) {
      const full = resolve(path, name),
        relative = prefix + name,
        stat = lstatSync(full);
      if (stat.isSymbolicLink()) throw Error('Linked asset entry refused');
      if (stat.isDirectory()) inspect(full, relative + '/');
      else if (!stat.isFile() || stat.nlink !== 1 || !expected.delete(relative))
        throw Error('Unexpected or linked asset upload file refused');
    }
  }
  inspect(directory);
  if (expected.size) throw Error('Incomplete pinned asset build');
  return summary;
}
export function digest(value) {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}
/** Reject lexical escapes and symlinks in EVERY existing path component, including the root. */
export function safePath(root, path, { config = false, createParents = false } = {}) {
  if (
    typeof path !== 'string' ||
    (!(config && path === CONFIG_PATH) &&
      !/^\.cache\/operator\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_.-]+)*\.(?:json|sql)$/.test(path))
  )
    throw Error('Path must be a bounded operator JSON/SQL file');
  if (path.split('/').some((p) => p === '..' || p === '.')) throw Error('Path traversal forbidden');
  const absolute = resolve(root, path);
  if (!absolute.startsWith(resolve(root) + sep)) throw Error('Path escape forbidden');
  const parts = absolute.split(sep).filter(Boolean);
  let current = sep;
  for (let i = 0; i < parts.length; i++) {
    current = resolve(current, parts[i]);
    try {
      const stat = lstatSync(current);
      if (stat.isSymbolicLink() || (i < parts.length - 1 && !stat.isDirectory()))
        throw Error('Symlink or non-directory path forbidden');
      if (i === parts.length - 1 && !stat.isFile()) throw Error('Regular file required');
    } catch (e) {
      if (e.code !== 'ENOENT') throw e;
      if (i < parts.length - 1 && createParents) mkdirSync(current, { mode: 0o700 });
      else if (i < parts.length - 1) throw Error('Parent directory missing');
    }
  }
  return absolute;
}
export function readJson(root, path, options = {}) {
  const full = safePath(root, path, options);
  const fd = openSync(full, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const limit = 128 * 1024;
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size > limit)
      throw Error('Operator input must be a bounded regular file');
    const bytes = Buffer.alloc(limit + 1);
    let length = 0;
    while (length < bytes.length) {
      const count = readSync(fd, bytes, length, bytes.length - length, null);
      if (!count) break;
      length += count;
    }
    if (length > limit) throw Error('Operator input too large');
    return JSON.parse(bytes.subarray(0, length).toString('utf8'));
  } finally {
    closeSync(fd);
  }
}
export function writeExclusive(root, path, content, options = {}) {
  const full = safePath(root, path, { ...options, createParents: true });
  const fd = openSync(
    full,
    constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,
    0o600,
  );
  try {
    writeFileSync(fd, content);
  } finally {
    closeSync(fd);
  }
  return path;
}
function quote(value) {
  return "'" + value.replaceAll("'", "''") + "'";
}
export function receiptSql(p) {
  const { id, receipt } = p.freeReceipt;
  // Conflict is a no-write; caller verifies exact stored bytes/account/revocation before success.
  return `INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) SELECT ${quote(id)},${quote(p.accountId)},${quote(JSON.stringify(receipt))},${Math.floor(Date.parse(receipt.verifiedAt) / 1000)} WHERE NOT EXISTS(SELECT 1 FROM ai_free_account_receipts WHERE id=${quote(id)});\n`;
}
/** Explicit CAS only; installation of immutable evidence is a separate action. */
export function receiptSlotSql(p, nowMs = Date.now()) {
  p = validateOperatorProfile(p, nowMs);
  if (!p.freeReceiptSlot || !p.freeReceipt) throw Error('Slot profile required');
  const slot = p.freeReceiptSlot;
  const evidence = `EXISTS(SELECT 1 FROM ai_free_account_receipts r WHERE r.id=${quote(p.freeReceipt.id)} AND r.account_id=${quote(p.accountId)} AND r.receipt_json=${quote(JSON.stringify(p.freeReceipt.receipt))} AND r.revoked_at IS NULL AND julianday(json_extract(r.receipt_json,'$.verifiedAt'))<=julianday('now') AND julianday(json_extract(r.receipt_json,'$.expiresAt'))>julianday('now'))`;
  const timestamp = Math.floor(nowMs / 1000);
  const where = `slot_id=${quote(slot.id)} AND account_id=${quote(p.accountId)}`;
  const sql =
    slot.expectedGeneration === 0
      ? `INSERT INTO ai_free_receipt_slots(slot_id,account_id,receipt_id,generation,updated_at) SELECT ${quote(slot.id)},${quote(p.accountId)},${quote(p.freeReceipt.id)},1,${timestamp} WHERE ${evidence} AND NOT EXISTS(SELECT 1 FROM ai_free_receipt_slots WHERE ${where}) RETURNING slot_id,account_id,receipt_id,generation;`
      : `UPDATE ai_free_receipt_slots SET receipt_id=${quote(p.freeReceipt.id)},generation=generation+1,updated_at=${timestamp} WHERE ${where} AND generation=${slot.expectedGeneration} AND receipt_id=${quote(slot.expectedReceiptId)} AND ${evidence} RETURNING slot_id,account_id,receipt_id,generation;`;
  return {
    sql,
    readbackSql: `SELECT slot_id,account_id,receipt_id,generation FROM ai_free_receipt_slots WHERE ${where} AND receipt_id=${quote(p.freeReceipt.id)} AND ${evidence};`,
    identity: {
      slot_id: slot.id,
      account_id: p.accountId,
      receipt_id: p.freeReceipt.id,
      generation: slot.expectedGeneration + 1,
    },
  };
}
export function verifyReceiptSlotResult(rows, identity) {
  if (
    !Array.isArray(rows) ||
    rows.length !== 1 ||
    rows[0]?.success !== true ||
    rows[0]?.results?.length !== 1
  )
    return false;
  const row = rows[0].results[0];
  return Object.entries(identity).every(([key, value]) => row[key] === value);
}
export function inviteSql(role, tokenHash, expires, nowSeconds) {
  if (
    !['owner', 'member'].includes(role) ||
    !/^[A-Za-z0-9_-]{43}$/.test(tokenHash) ||
    !Number.isSafeInteger(expires) ||
    expires <= nowSeconds ||
    expires > nowSeconds + 3600
  )
    throw Error('Invalid invitation');
  return `INSERT INTO invitations(token_hash,role,expires_at) SELECT '${tokenHash}','${role}',${expires}${role === 'owner' ? ` WHERE NOT EXISTS(SELECT 1 FROM users WHERE role='owner') AND NOT EXISTS(SELECT 1 FROM invitations WHERE role='owner' AND expires_at>${nowSeconds})` : ''} RETURNING token_hash;`;
}
export function operatorPlan(p, nowMs = Date.now()) {
  p = validateOperatorProfile(p, nowMs, { allowExpiredReceipt: true });
  return {
    schemaVersion: 1,
    profileFingerprint: digest(p),
    accountId: p.accountId,
    databaseId: p.databaseId,
    origin: p.origin,
    receiptCurrent: p.freeReceipt ? Date.parse(p.freeReceipt.receipt.expiresAt) > nowMs : null,
    receiptMaintenance: p.freeReceipt
      ? {
          expiresAt: p.freeReceipt.receipt.expiresAt,
          automaticRenewal: false,
          deploymentRequiredForNewId: !p.freeReceiptSlot,
          ...(p.freeReceiptSlot
            ? { slot: p.freeReceiptSlot, nextGeneration: p.freeReceiptSlot.expectedGeneration + 1 }
            : {}),
          guidance: p.freeReceiptSlot
            ? 'Within at most 24 hours AI stops without fresh reviewed evidence. Install a new immutable receipt, then separately authorize rotate-receipt-slot with the exact previous generation and receipt ID. Rotation invalidates old plans and undispatched reservations. A deployment already configured for this same slot needs no redeploy. Daily budget reset does not renew evidence.'
            : 'Within at most 24 hours AI stops without fresh reviewed evidence. Use a new receipt ID, preserve the old private profile/config, prepare again, then separately authorize install-receipt and deploy. Installation alone does not change the deployed receipt ID. Daily budget reset does not renew evidence. See docs/operator-activation.md#daily-use-and-receipt-renewal.',
        }
      : null,
    defaultExecution: 'local-only',
    provider: 'cloudflare-workers-ai',
    paidFallback: false,
    budgets: {
      dailyApp: p.dailyAppBudget,
      dailyUser: p.dailyUserBudget,
      unit: 'estimated-neurons',
      providerAccountFreeDailyAllowance: 10000,
      otherAccountUsage: 'unknown',
      automaticIncrease: false,
    },
    cleanup:
      p.cleanup === 'daily-utc'
        ? {
            cron: '17 3 * * *',
            timezone: 'UTC',
            effect: 'Daily bounded lifecycle cleanup after explicitly authorized deployment',
          }
        : {
            cron: null,
            warning:
              'Scheduled cleanup is not configured. Expiry checks remain enforced; maintenance is a launch decision.',
          },
    corpus:
      p.corpus === 'webp-pinned-assets'
        ? {
            mode: p.corpus,
            identity: pinnedAssetRegistration().identity,
            verseRowsWritten: 0,
            publication:
              'Pinned public-domain English WEB assets; authenticated application routing; metadata registration required',
          }
        : { mode: 'none', coverage: 'Curated starter excerpts only' },
    comparisonGuidance:
      'Plan uses prepared question/context input estimates and current remaining allowance. If it does not fit, explicitly reduce trial count/output or review a new bounded operator allowance; no automatic increase or paid upgrade.',
    secretReferences: [
      'Existing Wrangler login or CLOUDFLARE_API_TOKEN environment reference only; never copy values into artifacts',
    ],
    activation: p.modelIds.length ? 'free-provider-hard-stop' : 'disconnected',
    models: p.modelIds.map((id) => {
      const m = CATALOG_DATA.find((m) => m.id === id);
      return {
        id,
        tokenParameter: m.tokenParameter,
        temperatureMax: m.temperatureMax,
        streamSupported: m.streamSupported,
        reasoningControl: m.reasoningControl,
        billingTier: m.billingTier,
      };
    }),
    answerModes: p.answerModes,
    estimateDisclosure:
      'Application reservations are estimates, not hard token bounds. Provider Free quota is the final stop; account evidence is an expiring snapshot. Hidden reasoning and other account usage are uncertain.',
    experimentalDisclosure: p.answerModes.includes('grounded-generation')
      ? 'Experimental generated prose: structural citations do not establish semantic truth, spoiler safety or Japanese quality. Per-user quality consent still required.'
      : null,
    steps: [
      'Review existing account, D1 ownership and stable domain; no login or resource creation by prepare',
      p.corpus === 'webp-pinned-assets'
        ? 'prepare builds and verifies pinned public-domain assets and writes config locally'
        : 'prepare writes config only',
      'apply migrate explicitly targets existing D1',
      ...(p.corpus === 'webp-pinned-assets'
        ? ['apply register-corpus writes one exact pinned corpus metadata record; no verse import']
        : []),
      ...(p.freeReceipt ? ['apply install-receipt with current genuine evidence'] : []),
      ...(p.freeReceiptSlot
        ? ['apply rotate-receipt-slot explicitly installs or CAS-rotates the exact slot pointer']
        : []),
      'apply deploy creates/updates Worker and custom domain route',
      'apply invite-owner; register via passkey before inviting members',
    ],
    legalNotice:
      'Terms review entries record operator evidence, never accept agreements. Obtain any required acceptance separately before execution.',
  };
}
function parseArgs(argv) {
  const [command, ...rest] = argv;
  const flags = {};
  const allowed = new Set(['--profile', '--out', '--action', '--confirm', '--owner']);
  for (let i = 0; i < rest.length; i++) {
    const key = rest[i];
    if (Object.hasOwn(flags, key)) throw Error('Duplicate option');
    if (['--execute', '--allow-remote'].includes(key)) flags[key] = true;
    else if (allowed.has(key) && rest[i + 1] && !rest[i + 1].startsWith('--'))
      flags[key] = rest[++i];
    else throw Error('Unsupported or incomplete option');
  }
  const perCommand = {
    template: ['--out'],
    plan: ['--profile'],
    validate: ['--profile'],
    prepare: ['--profile'],
    apply: ['--profile', '--action', '--confirm', '--execute', '--allow-remote'],
    'github-plan': ['--owner'],
    'github-apply': ['--owner', '--action', '--confirm', '--execute', '--allow-remote'],
  };
  if (!perCommand[command] || Object.keys(flags).some((k) => !perCommand[command].includes(k)))
    throw Error('Unsupported command/options');
  return { command, flags };
}
export function defaultRunner(exe, args, options) {
  const r = spawnSync(exe, args, {
    cwd: options.root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 1024 * 1024,
    timeout: 180000,
    env: {
      ...process.env,
      ...options.env,
      CI: 'true',
      WRANGLER_SEND_METRICS: 'false',
      WRANGLER_SEND_ERROR_REPORTS: 'false',
      CLOUDFLARE_CF_FETCH_ENABLED: 'false',
      WRANGLER_LOG: 'error',
      WRANGLER_WRITE_LOGS: 'false',
      WRANGLER_LOG_SANITIZE: 'true',
      WRANGLER_HIDE_BANNER: 'true',
      GH_DEBUG: '',
      GH_PROMPT_DISABLED: '1',
      GH_NO_UPDATE_NOTIFIER: '1',
      GIT_TRACE: '0',
      GIT_TRACE_CURL: '0',
      GIT_CURL_VERBOSE: '0',
    },
  });
  if (r.error || r.status !== 0)
    throw Error(
      'External command failed; sensitive output suppressed. Check provider state before retrying.',
    );
  return r.stdout;
}
export function runOperator(
  argv,
  {
    root = ROOT,
    clock = Date.now,
    nowMs = clock(),
    run = defaultRunner,
    output = console.log,
    random = randomBytes,
    prepareAssets = preparePinnedAssets,
  } = {},
) {
  const { command, flags: f } = parseArgs(argv);
  if (command === 'template') {
    writeExclusive(root, f['--out'], JSON.stringify(profileTemplate(), null, 2) + '\n');
    output('Pending template written; no account or model is approved.');
    return;
  }
  const remoteAllowed = () => {
    if (!f['--execute'] || !f['--allow-remote'])
      throw Error(
        'Remote action requires --execute and --allow-remote after explicit authorization',
      );
  };
  if (command.startsWith('github-')) {
    const owner = f['--owner'];
    if (!/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/.test(owner ?? ''))
      throw Error('Exact GitHub personal owner required');
    const repo = owner + '/bible-companion';
    if (command === 'github-plan') {
      output(
        JSON.stringify(
          {
            repository: repo,
            visibility: 'PRIVATE',
            actions: ['create', 'push'],
            execution: 'pending authorization',
            credentials: 'existing gh authentication only',
          },
          null,
          2,
        ),
      );
      return;
    }
    remoteAllowed();
    const action = f['--action'];
    if (!['create', 'push'].includes(action) || f['--confirm'] !== `${action}:${repo}:private`)
      throw Error('Exact private repository action confirmation required');
    const gh = (args) => run('gh', args, { root });
    gh(['auth', 'status']);
    const user = JSON.parse(gh(['api', 'user']));
    if (user.login?.toLowerCase() !== owner.toLowerCase() || user.type !== 'User')
      throw Error('Authenticated personal GitHub owner mismatch');
    if (action === 'create')
      gh(['repo', 'create', repo, '--private', '--source=.', '--remote=origin']);
    const meta = JSON.parse(gh(['repo', 'view', repo, '--json', 'visibility,nameWithOwner,url']));
    if (
      meta.visibility !== 'PRIVATE' ||
      meta.nameWithOwner?.toLowerCase() !== repo.toLowerCase() ||
      meta.url !== `https://github.com/${meta.nameWithOwner}`
    )
      throw Error('Exact private repository verification failed; no push');
    if (action === 'push') {
      const remote = run('git', ['remote', 'get-url', '--push', '--all', 'origin'], {
        root,
      }).trim();
      if (
        ![
          `https://github.com/${meta.nameWithOwner}.git`,
          `git@github.com:${meta.nameWithOwner}.git`,
        ].includes(remote)
      )
        throw Error('Git push remote mismatch');
      const configKeys = run('git', ['config', '--name-only', '--list'], { root }).split(/\r?\n/);
      if (configKeys.some((key) => /^url\..*\.(?:insteadof|pushinsteadof)$/i.test(key)))
        throw Error('Git URL rewriting must be reviewed and removed before this guarded push');
      run('git', ['push', remote, 'HEAD:refs/heads/main'], { root });
    }
    output(
      action === 'create'
        ? 'Private repository created and visibility verified; no push performed.'
        : 'Push completed after exact private repository and remote verification.',
    );
    return;
  }
  const evidenceOptions = {
    allowExpiredReceipt:
      command === 'plan' || (command === 'apply' && f['--action'] === 'revoke-receipt'),
  };
  const p = validateOperatorProfile(readJson(root, f['--profile']), nowMs, evidenceOptions);
  if (command === 'plan') {
    output(JSON.stringify(operatorPlan(p, nowMs), null, 2));
    return;
  }
  const c = profileToConfig(p, nowMs, root, evidenceOptions);
  if (command === 'validate') {
    output(
      'Profile and generated configuration valid; evidence is operator-attested, not independently provider-verified. No remote calls.',
    );
    return;
  }
  if (command === 'prepare') {
    if (p.corpus === 'webp-pinned-assets') prepareAssets(root);
    writeExclusive(root, CONFIG_PATH, JSON.stringify(c, null, 2) + '\n', { config: true });
    output(
      'Private local operator config prepared; no deployment, agreement acceptance or provider connection.',
    );
    return;
  }
  remoteAllowed();
  const action = f['--action'];
  if (
    ![
      'migrate',
      'install-receipt',
      'rotate-receipt-slot',
      'revoke-receipt',
      'register-corpus',
      'deploy',
      'invite-owner',
      'invite-member',
    ].includes(action) ||
    f['--confirm'] !== `${action}:${p.accountId}:${p.databaseId}:${digest(p)}`
  )
    throw Error(
      'Exact action/account/database/profile confirmation required; get fingerprint from plan',
    );
  const existing = readJson(root, CONFIG_PATH, { config: true });
  if (JSON.stringify(existing) !== JSON.stringify(c))
    throw Error('Prepared config differs from current approved profile');
  const wrangler = (args) =>
    run(process.execPath, [resolve(root, 'node_modules/wrangler/bin/wrangler.js'), ...args], {
      root,
      env: { CLOUDFLARE_ACCOUNT_ID: p.accountId },
    });
  const auth = JSON.parse(wrangler(['whoami', '--json']));
  if (
    auth.loggedIn !== true ||
    !Array.isArray(auth.accounts) ||
    !auth.accounts.some((a) => a.id === p.accountId)
  )
    throw Error('Existing Cloudflare authentication account mismatch');
  const info = JSON.parse(
    wrangler(['d1', 'info', 'bible-companion', '--json', '--config', CONFIG_PATH]),
  );
  if (info.uuid !== p.databaseId) throw Error('Provider D1 identity mismatch');
  validateOperatorProfile(p, clock(), evidenceOptions);
  if (action === 'migrate')
    wrangler(['d1', 'migrations', 'apply', 'bible-companion', '--remote', '--config', CONFIG_PATH]);
  if (action === 'deploy') {
    if (p.freeReceiptSlot) {
      const rotation = receiptSlotSql(p, clock());
      const rows = JSON.parse(
        wrangler([
          'd1',
          'execute',
          'bible-companion',
          '--remote',
          '--config',
          CONFIG_PATH,
          '--command',
          rotation.readbackSql,
          '--json',
        ]),
      );
      if (!verifyReceiptSlotResult(rows, rotation.identity))
        throw Error(
          'Install and explicitly rotate the exact approved slot before deployment; pointer/evidence readback did not match',
        );
    }
    if (p.corpus === 'webp-pinned-assets') {
      prepareAssets(root);
      const registration = pinnedAssetRegistration(Math.floor(clock() / 1000));
      const rows = JSON.parse(
        wrangler([
          'd1',
          'execute',
          'bible-companion',
          '--remote',
          '--config',
          CONFIG_PATH,
          '--command',
          registration.readbackSql,
          '--json',
        ]),
      );
      const row =
        Array.isArray(rows) &&
        rows.length === 1 &&
        rows[0]?.success === true &&
        rows[0]?.results?.length === 1 &&
        rows[0].results[0];
      if (!validatePinnedAssetRegistration(row, registration.identity))
        throw Error('Register the exact approved corpus before asset deployment');
    }
    wrangler(['deploy', '--config', CONFIG_PATH]);
  }
  if (action === 'register-corpus') {
    if (p.corpus !== 'webp-pinned-assets') throw Error('Pinned corpus was not selected');
    const registration = pinnedAssetRegistration(Math.floor(clock() / 1000));
    const execute = (sql) =>
      JSON.parse(
        wrangler([
          'd1',
          'execute',
          'bible-companion',
          '--remote',
          '--config',
          CONFIG_PATH,
          '--command',
          sql,
          '--json',
        ]),
      );
    const changed = execute(registration.sql);
    if (!Array.isArray(changed) || !changed.length || changed.some((r) => r.success !== true))
      throw Error('Corpus registration response was not successful');
    const rows = execute(registration.readbackSql);
    const row =
      Array.isArray(rows) &&
      rows.length === 1 &&
      rows[0]?.success === true &&
      rows[0]?.results?.length === 1 &&
      rows[0].results[0];
    if (!validatePinnedAssetRegistration(row, registration.identity))
      throw Error('Corpus identity, storage mode or rights did not verify; no reapproval');
  }
  if (action === 'install-receipt') {
    if (!p.freeReceipt) throw Error('No free-account receipt to install');
    const sql = receiptSql(p);
    wrangler([
      'd1',
      'execute',
      'bible-companion',
      '--remote',
      '--config',
      CONFIG_PATH,
      '--command',
      sql,
      '--json',
    ]);
    const rows = JSON.parse(
      wrangler([
        'd1',
        'execute',
        'bible-companion',
        '--remote',
        '--config',
        CONFIG_PATH,
        '--command',
        `SELECT account_id,receipt_json,revoked_at FROM ai_free_account_receipts WHERE id=${quote(p.freeReceipt.id)};`,
        '--json',
      ]),
    );
    const row =
      Array.isArray(rows) &&
      rows[0]?.success === true &&
      rows[0]?.results?.length === 1 &&
      rows[0].results[0];
    if (
      !row ||
      row.account_id !== p.accountId ||
      row.receipt_json !== JSON.stringify(p.freeReceipt.receipt) ||
      row.revoked_at !== null
    )
      throw Error('Receipt conflict, revoked evidence or unverified install; no reapproval');
  }
  if (action === 'rotate-receipt-slot') {
    const rotation = receiptSlotSql(p, clock());
    const execute = (sql) =>
      JSON.parse(
        wrangler([
          'd1',
          'execute',
          'bible-companion',
          '--remote',
          '--config',
          CONFIG_PATH,
          '--command',
          sql,
          '--json',
        ]),
      );
    if (!verifyReceiptSlotResult(execute(rotation.sql), rotation.identity))
      throw Error(
        'Slot CAS did not change exactly the expected pointer; inspect current generation and receipt before new approval',
      );
    if (!verifyReceiptSlotResult(execute(rotation.readbackSql), rotation.identity))
      throw Error(
        'Slot readback differs; do not retry an uncertain rotation without inspection and new approval',
      );
  }
  if (action === 'revoke-receipt') {
    if (!p.freeReceipt) throw Error('Exact receipt ID required');
    const rows = JSON.parse(
      wrangler([
        'd1',
        'execute',
        'bible-companion',
        '--remote',
        '--config',
        CONFIG_PATH,
        '--command',
        `UPDATE ai_free_account_receipts SET revoked_at=COALESCE(revoked_at,${Math.floor(clock() / 1000)}) WHERE id=${quote(p.freeReceipt.id)} AND account_id=${quote(p.accountId)} RETURNING id;`,
        '--json',
      ]),
    );
    if (
      !Array.isArray(rows) ||
      !rows.some((r) => r.success === true && r.results?.some((row) => row.id === p.freeReceipt.id))
    )
      throw Error('Receipt revocation target missing or not verified');
  }
  if (action.startsWith('invite-')) {
    const role = action.slice(7),
      token = random(32).toString('base64url'),
      hash = createHash('sha256').update(token).digest('base64url');
    const seconds = Math.floor(nowMs / 1000);
    const result = JSON.parse(
      wrangler([
        'd1',
        'execute',
        'bible-companion',
        '--remote',
        '--config',
        CONFIG_PATH,
        '--command',
        inviteSql(role, hash, seconds + 3600, seconds),
        '--json',
      ]),
    );
    if (
      !Array.isArray(result) ||
      !result.some((r) => r.success === true && r.results?.some((row) => row.token_hash === hash))
    )
      throw Error('Invitation was not created; existing owner/pending owner or database failure');
    output(
      `Private ${role} invitation, expires in one hour. Displayed once; do not log/share publicly: ${token}`,
    );
  } else output(`Authorized ${action} completed. No AI inference was run by this CLI.`);
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    runOperator(process.argv.slice(2));
  } catch {
    console.error(
      'Operator command refused or failed. Check profile, evidence, exact authorization and provider state; input/provider output suppressed.',
    );
    process.exitCode = 1;
  }
}
