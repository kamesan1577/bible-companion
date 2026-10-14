import { budgetDispatchGuard } from './budget-dispatch';
import { answerModeSchema, assertAnswerMode, GROUNDED_POLICY_VERSION } from './answer-mode';
import { Hono } from 'hono';
import { z } from 'zod';
import { sha256, stableJSON, passageSchema } from '@bible/core';
import {
  assertModelAuthorized,
  validateSettings,
  createCompanionAnswer,
  prepareCompanionRequest,
  validatePreparedInputCapacity,
  MODEL_TERMS_POLICY_VERSION,
  REGISTRY_VERSION,
  PROMPT_VERSION,
  type AnswerResult,
} from '@bible/ai-harness';
import type { AppEnv, Env } from './types';
import { body, fail, now, requireDebugger, configuredBudget } from './http';
import { authorization, settingsSchema, ensureConsent, aiError } from './ai';
import { getSources, sourcePolicyVersion, projectSavedComparison } from './data';
import {
  loadBudgetAuthority,
  estimateModelReservation,
  estimateReservation,
  reserveBudget,
} from './budget';
export const comparisons = new Hono<AppEnv>();
const executionVersion = [
  REGISTRY_VERSION,
  PROMPT_VERSION,
  MODEL_TERMS_POLICY_VERSION,
  GROUNDED_POLICY_VERSION,
].join('|');
const proofExecutionIdentity = (fingerprint: string) => fingerprint + '|' + executionVersion;
const planSchema = z
  .object({
    requestId: z.string().uuid(),
    models: z
      .array(
        z
          .object({
            modelId: z.string().max(150),
            settings: settingsSchema.default({}),
            answerMode: answerModeSchema.optional(),
          })
          .strict(),
      )
      .min(1)
      .max(2),
    questions: z
      .array(
        z
          .object({
            passage: passageSchema,
            question: z.string().trim().min(1).max(2000),
            spoilerAllowed: z.boolean().default(false),
            translation: z
              .string()
              .regex(/^[A-Z0-9_-]{1,30}$/)
              .optional(),
          })
          .strict(),
      )
      .min(1)
      .max(10),
    saveResults: z.boolean().default(false),
  })
  .strict()
  .refine(
    (x) =>
      new Set(x.models.map((m) => m.modelId + ':' + (m.answerMode ?? 'reviewed-claim-selection')))
        .size === x.models.length,
  );
const startSchema = z
  .object({ plan: planSchema, confirmationHash: z.string().regex(/^[A-Za-z0-9_-]{43}$/) })
  .strict();
const stepSchema = startSchema.extend({ trialIndex: z.number().int().min(0).max(19) }).strict();
type Plan = z.infer<typeof planSchema>;
type Job = {
  id: string;
  user_id: string;
  request_hash: string;
  plan_fingerprint: string | null;
  status: string;
  saved: number;
  metrics_json: string | null;
  policy_version: number;
  expires_at: number | null;
  trial_count: number;
  error_code: string | null;
};
type Trial = {
  trial_index: number;
  question_index: number;
  model_index: number;
  model_id: string;
  state: string;
  amount: number;
  proof_fingerprint: string;
  dispatched: number;
  model_invoked: number | null;
  lease_token: string | null;
  lease_expires_at: number | null;
  metrics_json: string | null;
};
const terminal = (status: string) => !['reserved', 'running'].includes(status);
export async function expireComparisons(env: Env, userId?: string) {
  await env.DB.prepare(
    "UPDATE comparison_jobs SET status=CASE WHEN expires_at<=? THEN 'expired' ELSE 'failed' END,error_code=CASE WHEN expires_at<=? THEN 'comparison_expired' ELSE 'trial_acknowledgment_unknown' END,updated_at=? WHERE status IN ('reserved','running') AND trial_count>0 AND (? IS NULL OR user_id=?) AND (expires_at<=? OR EXISTS(SELECT 1 FROM comparison_trials t WHERE t.job_id=comparison_jobs.id AND t.state='running' AND t.lease_expires_at<=?))",
  )
    .bind(now(), now(), now(), userId ?? null, userId ?? null, now(), now())
    .run();
}
async function finish(env: Env, id: string, userId: string, status: string, error: string) {
  await env.DB.prepare(
    "UPDATE comparison_jobs SET status=?,error_code=?,updated_at=? WHERE id=? AND user_id=? AND status IN ('reserved','running')",
  )
    .bind(status, error, now(), id, userId)
    .run();
}
async function job(env: Env, id: string, userId: string) {
  return env.DB.prepare('SELECT * FROM comparison_jobs WHERE id=? AND user_id=?')
    .bind(id, userId)
    .first<Job>();
}
async function trialRows(env: Env, id: string, userId: string) {
  return (
    await env.DB.prepare(
      'SELECT * FROM comparison_trials WHERE job_id=? AND user_id=? ORDER BY trial_index',
    )
      .bind(id, userId)
      .all<Trial>()
  ).results;
}
async function state(env: Env, row: Job) {
  const trials = await trialRows(env, row.id, row.user_id);
  const active = trials.find((t) => t.state === 'running');
  return {
    requestId: row.id,
    status: row.status,
    phase: terminal(row.status)
      ? 'terminal'
      : row.status === 'reserved'
        ? 'preparing'
        : active
          ? 'executing'
          : 'ready',
    saved: !!row.saved,
    trialCount: row.trial_count,
    completedCount: trials.filter((t) => t.state === 'complete').length,
    nextTrialIndex:
      !terminal(row.status) && !active && row.status === 'running'
        ? (trials.find((t) => t.state === 'queued')?.trial_index ?? null)
        : null,
    activeTrialIndex: active?.trial_index ?? null,
    expiresAt: row.expires_at,
    trials: trials.map((t) => ({
      index: t.trial_index,
      questionIndex: t.question_index,
      modelIndex: t.model_index,
      modelId: t.model_id,
      status: t.state,
      reservedBudgetUnits: t.amount,
      modelInvoked: t.model_invoked === null ? null : !!t.model_invoked,
      usageUnknown: !!t.dispatched && t.model_invoked === null,
      leaseExpiresAt: t.lease_expires_at,
    })),
    results:
      row.saved && row.metrics_json
        ? await projectSavedComparison(env, JSON.parse(row.metrics_json))
        : null,
    errorCode: row.error_code,
  };
}
async function budget(env: Env, userId: string, plan: Plan) {
  const auth = authorization(env, userId);
  const authority = await loadBudgetAuthority(
    env,
    plan.models.map((m) => m.modelId),
  );
  const settings = plan.models.map((m) => {
    assertModelAuthorized(m.modelId, auth);
    assertAnswerMode(env, m.answerMode ?? 'reviewed-claim-selection');
    return validateSettings(m.modelId, m.settings);
  });
  const policyVersion = await sourcePolicyVersion(env);
  const snapshots = new Map<string, Awaited<ReturnType<typeof getSources>>>();
  const trials = [];
  const inputEstimates = new Map<string, number>();
  for (let q = 0; q < plan.questions.length; q++) {
    const question = plan.questions[q];
    let sources: Awaited<ReturnType<typeof getSources>> = [];
    if (authority.mode === 'free-provider-hard-stop') {
      const key = stableJSON([question.passage, question.spoilerAllowed]);
      const cached = snapshots.get(key);
      sources =
        cached ??
        (await getSources(
          env,
          question.passage,
          question.spoilerAllowed,
          question.passage,
          policyVersion,
          true,
        ));
      snapshots.set(key, sources);
    }
    for (let i = 0; i < plan.models.length; i++) {
      const model = plan.models[i];
      let inputTokens = 0;
      if (authority.mode === 'free-provider-hard-stop') {
        const key = stableJSON([question, model.answerMode ?? 'reviewed-claim-selection']);
        inputTokens =
          inputEstimates.get(key) ??
          prepareCompanionRequest(
            {
              ...question,
              modelId: model.modelId,
              settings: {
                ...model.settings,
                stream: false,
                timeoutMs: Math.min(model.settings.timeoutMs ?? 30000, 30000),
              },
              sources,
            },
            { authorization: auth, answerMode: model.answerMode ?? 'reviewed-claim-selection' },
          ).usage.estimated.inputTokens;
        inputEstimates.set(key, inputTokens);
        validatePreparedInputCapacity(model.modelId, inputTokens, settings[i].maxOutputTokens);
      }
      const reservation = estimateModelReservation(
        env,
        model.modelId,
        settings[i].maxOutputTokens,
        authority,
        inputTokens,
      );
      trials.push({
        index: q * plan.models.length + i,
        questionIndex: q,
        modelIndex: i,
        modelId: model.modelId,
        ...reservation,
        proofFingerprint: proofExecutionIdentity(reservation.proofFingerprint),
      });
    }
  }
  if (
    authority.mode === 'free-provider-hard-stop' &&
    policyVersion !== (await sourcePolicyVersion(env))
  )
    fail(409, 'source_policy_changed', 'Sources changed while preparing comparison');
  const summary = {
    amount: trials.reduce((a, t) => a + t.amount, 0),
    policyVersion,
    trials,
    termsPolicyVersion: MODEL_TERMS_POLICY_VERSION,
    executionVersion,
  };
  if (
    summary.amount > configuredBudget(env.DAILY_APP_BUDGET) ||
    summary.amount > configuredBudget(env.DAILY_USER_BUDGET)
  )
    fail(
      429,
      'comparison_budget_exceeded',
      'This complete plan exceeds the configured daily allowance. Select fewer trials or use an explicitly reviewed allowance.',
    );
  const day = new Date().toISOString().slice(0, 10);
  const allowance = await env.DB.prepare(
    'SELECT COALESCE((SELECT reserved+consumed FROM budget_days WHERE day=?),0) AS app_used,COALESCE((SELECT reserved+consumed FROM user_budget_days WHERE user_id=? AND day=?),0) AS user_used',
  )
    .bind(day, userId, day)
    .first<{ app_used: number; user_used: number }>();
  if (
    !allowance ||
    summary.amount > configuredBudget(env.DAILY_APP_BUDGET) - allowance.app_used ||
    summary.amount > configuredBudget(env.DAILY_USER_BUDGET) - allowance.user_used
  )
    fail(429, 'comparison_budget_exceeded', 'This plan exceeds the remaining daily allowance.');
  return { ...summary, hash: await sha256(stableJSON({ plan, budget: summary })) };
}
comparisons.post('/developer/comparisons/plan', async (c) => {
  requireDebugger(c);
  const plan = await body(c, planSchema);
  try {
    const b = await budget(c.env, c.get('user').id, plan);
    return c.json({
      requestId: plan.requestId,
      trialCount: b.trials.length,
      models: plan.models.map((m) => m.modelId),
      answerModes: plan.models.map((m) => m.answerMode ?? 'reviewed-claim-selection'),
      budgetMode: b.trials[0]?.budgetMode,
      budgetBoundVerified: b.trials.every((t) => t.budgetBoundVerified),
      reservationWarnings: [...new Set(b.trials.flatMap((t) => t.warnings))],
      questionCount: plan.questions.length,
      reservedBudgetUnits: b.amount,
      estimateOnly: true,
      actualNeurons: null,
      sequential: true,
      automaticRetries: 0,
      saveResults: plan.saveResults,
      pricingVersions: [...new Set(b.trials.map((t) => t.estimate.pricingVersion))],
      confirmationHash: b.hash,
      executionVersion,
      inputBoundsValidation: 'per-step-before-dispatch',
      execution: 'client-driven-single-trial',
    });
  } catch (e) {
    aiError(e);
  }
});
comparisons.post('/developer/comparisons', async (c) => {
  requireDebugger(c);
  const { plan, confirmationHash } = await body(c, startSchema);
  const uid = c.get('user').id;
  await expireComparisons(c.env, uid);
  const fingerprint = await sha256(stableJSON(plan));
  const existing = await job(c.env, plan.requestId, uid);
  if (existing) {
    if (existing.plan_fingerprint !== fingerprint || existing.request_hash !== confirmationHash)
      fail(409, 'idempotency_conflict', 'Comparison ID already used');
    return c.json(await state(c.env, existing), 200);
  }
  let b;
  try {
    b = await budget(c.env, uid, plan);
  } catch (e) {
    aiError(e);
  }
  if (b.hash !== confirmationHash) fail(409, 'plan_changed', 'Confirm the current comparison plan');
  if (c.env.AI_ENABLED !== 'true' || !c.env.AI)
    fail(503, 'ai_not_connected', 'AI is not connected');
  await ensureConsent(
    c.env,
    uid,
    plan.models.some((m) => m.answerMode === 'grounded-generation')
      ? 'grounded-generation'
      : 'reviewed-claim-selection',
  );
  const expiresAt = Math.min(now() + 900, (Math.floor(now() / 86400) + 1) * 86400);
  try {
    const rows = await c.env.DB.batch([
      c.env.DB.prepare(
        "INSERT INTO comparison_jobs(id,user_id,request_hash,status,saved,created_at,updated_at,plan_fingerprint,policy_version,expires_at,trial_count,metrics_json) SELECT ?,?,?,'reserved',?,?,?,?,?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM request_cancellations WHERE user_id=? AND id=? AND kind='comparison') AND EXISTS(SELECT 1 FROM users WHERE id=? AND data_epoch=?) RETURNING id",
      ).bind(
        plan.requestId,
        uid,
        b.hash,
        plan.saveResults ? 1 : 0,
        now(),
        now(),
        fingerprint,
        b.policyVersion,
        expiresAt,
        b.trials.length,
        JSON.stringify(
          plan.saveResults
            ? { questions: plan.questions, results: [], sourcePolicyVersion: b.policyVersion }
            : [],
        ),
        uid,
        plan.requestId,
        uid,
        c.get('dataEpoch'),
      ),
      c.env.DB.prepare(
        "INSERT INTO comparison_trials(job_id,user_id,trial_index,question_index,model_index,model_id,amount,proof_fingerprint) SELECT ?,?,json_extract(value,'$.index'),json_extract(value,'$.questionIndex'),json_extract(value,'$.modelIndex'),json_extract(value,'$.modelId'),json_extract(value,'$.amount'),json_extract(value,'$.proofFingerprint') FROM json_each(?) WHERE EXISTS(SELECT 1 FROM comparison_jobs WHERE id=? AND user_id=? AND plan_fingerprint=?)",
      ).bind(plan.requestId, uid, JSON.stringify(b.trials), plan.requestId, uid, fingerprint),
    ]);
    if (!rows[0].results.length)
      fail(409, 'comparison_cancelled', 'Comparison was cancelled before start');
  } catch (e) {
    if ((e as { status?: number }).status) throw e;
    fail(409, 'comparison_active', 'Only one comparison may be active');
  }
  try {
    await reserveBudget(c.env, uid, 'comparison:' + plan.requestId, b.amount);
    const ready = await c.env.DB.prepare(
      "UPDATE comparison_jobs SET status='running',updated_at=? WHERE id=? AND user_id=? AND status='reserved' AND expires_at>? RETURNING id",
    )
      .bind(now(), plan.requestId, uid, now())
      .first();
    if (!ready) fail(409, 'comparison_cancelled', 'Comparison is no longer active');
  } catch (e) {
    await finish(c.env, plan.requestId, uid, 'failed', 'reservation_failed');
    throw e;
  }
  return c.json(await state(c.env, (await job(c.env, plan.requestId, uid))!), 202);
});
comparisons.get('/developer/comparisons', async (c) => {
  requireDebugger(c);
  const query = z
    .object({
      saved: z.enum(['true', 'false']).default('true'),
      before: z.string().max(2000).optional(),
    })
    .strict()
    .safeParse(c.req.query());
  if (!query.success) fail(400, 'invalid_query', 'Invalid comparison page parameters');
  const saved = query.data.saved === 'true';
  let cursor = { createdAt: Number.MAX_SAFE_INTEGER, id: '~' };
  if (query.data.before) {
    try {
      cursor = z
        .object({
          createdAt: z.number().int().nonnegative().safe(),
          id: z.string().uuid(),
          saved: z.literal(saved),
        })
        .strict()
        .parse(JSON.parse(atob(query.data.before)));
    } catch {
      fail(400, 'invalid_cursor', 'Cursor does not match this comparison list');
    }
  }
  await expireComparisons(c.env, c.get('user').id);
  const result = await c.env.DB.prepare(
    'SELECT id,status,saved,created_at,updated_at,trial_count,error_code FROM comparison_jobs WHERE user_id=? AND saved=? AND (created_at<? OR (created_at=? AND id<?)) ORDER BY created_at DESC,id DESC LIMIT 51',
  )
    .bind(c.get('user').id, saved ? 1 : 0, cursor.createdAt, cursor.createdAt, cursor.id)
    .all<{
      id: string;
      status: string;
      saved: number;
      created_at: number;
      updated_at: number;
      trial_count: number;
      error_code: string | null;
    }>();
  const rows = result.results.slice(0, 50),
    last = rows.at(-1);
  return c.json({
    items: rows.map((r) => ({
      requestId: r.id,
      status: r.status,
      saved: !!r.saved,
      createdAt: r.created_at,
      updatedAt: r.updated_at,
      trialCount: r.trial_count,
      errorCode: r.error_code,
    })),
    nextCursor:
      result.results.length > 50 && last
        ? btoa(JSON.stringify({ createdAt: last.created_at, id: last.id, saved }))
        : null,
  });
});
comparisons.get('/developer/comparisons/active', async (c) => {
  requireDebugger(c);
  const uid = c.get('user').id;
  await expireComparisons(c.env, uid);
  const row = await c.env.DB.prepare(
    "SELECT * FROM comparison_jobs WHERE user_id=? AND status IN ('reserved','running') LIMIT 1",
  )
    .bind(uid)
    .first<Job>();
  return c.json({ comparison: row ? await state(c.env, row) : null });
});
comparisons.get('/developer/comparisons/:id', async (c) => {
  requireDebugger(c);
  const uid = c.get('user').id;
  await expireComparisons(c.env, uid);
  const row = await job(c.env, c.req.param('id'), uid);
  if (row) return c.json(await state(c.env, row));
  const cancelled = await c.env.DB.prepare(
    "SELECT id FROM request_cancellations WHERE user_id=? AND id=? AND kind='comparison'",
  )
    .bind(uid, c.req.param('id'))
    .first();
  if (cancelled)
    return c.json({
      requestId: c.req.param('id'),
      status: 'cancelled',
      phase: 'terminal',
      saved: false,
      trialCount: 0,
      completedCount: 0,
      nextTrialIndex: null,
      activeTrialIndex: null,
      expiresAt: null,
      trials: [],
      results: null,
      errorCode: 'cancelled_before_start',
    });
  fail(404, 'not_found', 'Comparison state is not yet known');
});
comparisons.delete('/developer/comparisons/:id', async (c) => {
  requireDebugger(c);
  const id = c.req.param('id'),
    uid = c.get('user').id;
  if (!z.string().uuid().safeParse(id).success)
    fail(400, 'invalid_request_id', 'Expected a request UUID');
  await c.env.DB.batch([
    c.env.DB.prepare(
      "INSERT OR IGNORE INTO request_cancellations(user_id,id,kind,created_at) VALUES(?,?,'comparison',?)",
    ).bind(uid, id, now()),
    c.env.DB.prepare(
      "UPDATE comparison_jobs SET status='cancelled',updated_at=? WHERE id=? AND user_id=? AND status IN ('reserved','running')",
    ).bind(now(), id, uid),
  ]);
  if ((await job(c.env, id, uid))?.status === 'complete')
    fail(409, 'comparison_complete', 'Comparison completed before cancellation');
  return c.json({ status: 'cancelled', usageMayHaveOccurred: true });
});
comparisons.post('/developer/comparisons/:id/steps', async (c) => {
  requireDebugger(c);
  const input = await body(c, stepSchema),
    { plan, trialIndex } = input,
    uid = c.get('user').id,
    id = c.req.param('id');
  if (id !== plan.requestId) fail(400, 'request_id_mismatch', 'Plan request ID differs');
  await expireComparisons(c.env, uid);
  const row = await job(c.env, id, uid);
  if (!row) fail(404, 'not_found', 'Comparison is not started');
  if (
    row.plan_fingerprint !== (await sha256(stableJSON(plan))) ||
    row.request_hash !== input.confirmationHash
  )
    fail(409, 'idempotency_conflict', 'Use the original frozen plan');
  const trials = await trialRows(c.env, id, uid),
    trial = trials.find((t) => t.trial_index === trialIndex);
  if (!trial) fail(400, 'invalid_trial', 'Trial does not exist');
  if (trial.state === 'complete') {
    const projected = await state(c.env, row);
    const saved =
      (
        projected.results as {
          results?: { questionIndex: number; modelIndex: number; result: AnswerResult }[];
        } | null
      )?.results?.find(
        (x) => x.questionIndex === trial.question_index && x.modelIndex === trial.model_index,
      )?.result ?? null;
    return c.json({
      state: projected,
      trialIndex,
      result: saved,
      replayed: true,
      resultAvailability: row.saved ? 'saved' : 'not_saved',
    });
  }
  if (terminal(row.status)) fail(409, 'comparison_terminal', 'Comparison cannot resume');
  if (
    trial.state !== 'queued' ||
    trials.some((t) => t.trial_index < trialIndex && t.state !== 'complete')
  )
    fail(409, 'trial_in_progress', 'Reconcile the current trial before continuing');
  const lease = crypto.randomUUID();
  const claimed = await c.env.DB.prepare(
    "UPDATE comparison_trials SET state='running',lease_token=?,lease_expires_at=? WHERE job_id=? AND user_id=? AND trial_index=? AND state='queued' AND NOT EXISTS(SELECT 1 FROM comparison_trials t WHERE t.job_id=? AND (t.state='running' OR (t.trial_index<? AND t.state<>'complete'))) AND EXISTS(SELECT 1 FROM comparison_jobs j WHERE j.id=? AND j.user_id=? AND j.status='running' AND j.expires_at>?) RETURNING trial_index",
  )
    .bind(lease, now() + 90, id, uid, trialIndex, id, trialIndex, id, uid, now())
    .first();
  if (!claimed) fail(409, 'trial_in_progress', 'Trial is already claimed or comparison stopped');
  try {
    if (c.env.AI_ENABLED !== 'true' || !c.env.AI)
      fail(503, 'ai_not_connected', 'AI is not connected');
    await ensureConsent(
      c.env,
      uid,
      plan.models[trial.model_index].answerMode ?? 'reviewed-claim-selection',
    );
    if ((await sourcePolicyVersion(c.env)) !== row.policy_version)
      fail(409, 'source_policy_changed', 'Sources changed; confirm a new comparison');
    const question = plan.questions[trial.question_index],
      model = plan.models[trial.model_index];
    const answerInput = {
      ...question,
      modelId: model.modelId,
      settings: {
        ...model.settings,
        stream: false as const,
        timeoutMs: Math.min(model.settings.timeoutMs ?? 30000, 30000),
      },
      sources: await getSources(
        c.env,
        question.passage,
        question.spoilerAllowed,
        question.passage,
        undefined,
        true,
      ),
    };
    const proof = await estimateReservation(
      c.env,
      answerInput,
      authorization(c.env, uid),
      model.answerMode ?? 'reviewed-claim-selection',
    );
    if (
      proofExecutionIdentity(proof.proofFingerprint) !== trial.proof_fingerprint ||
      proof.amount !== trial.amount
    )
      fail(
        409,
        'execution_policy_changed',
        'Confirm a new plan after model proof or prompt/catalog policy changes',
      );
    const result = await createCompanionAnswer(answerInput, {
      answerMode: model.answerMode ?? 'reviewed-claim-selection',
      authorization: authorization(c.env, uid),
      signal: c.req.raw.signal,
      ai: {
        run: async (modelId, inputs) => {
          assertModelAuthorized(modelId, authorization(c.env, uid));
          assertAnswerMode(c.env, model.answerMode ?? 'reviewed-claim-selection');
          const guard = budgetDispatchGuard(c.env, proof.dispatchIdentity);
          const dispatched = await c.env.DB.prepare(
            `UPDATE comparison_trials SET dispatched=1 WHERE job_id=? AND user_id=? AND trial_index=? AND state='running' AND lease_token=? AND lease_expires_at>? AND EXISTS(SELECT 1 FROM comparison_jobs j JOIN users u ON u.id=j.user_id WHERE j.id=? AND j.status='running' AND j.expires_at>? AND json_extract(u.settings_json,'$.workersAiConsent')=1 AND (?='reviewed-claim-selection' OR (json_extract(u.settings_json,'$.groundedGenerationConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationPolicyVersion')=?)) AND (SELECT version FROM source_policy_state WHERE id=1)=?) AND ${guard.sql} RETURNING trial_index`,
          )
            .bind(
              id,
              uid,
              trialIndex,
              lease,
              now(),
              id,
              now(),
              model.answerMode ?? 'reviewed-claim-selection',
              GROUNDED_POLICY_VERSION,
              row.policy_version,
              ...guard.params,
            )
            .first();
          if (!dispatched) fail(409, 'comparison_cancelled', 'Comparison stopped before dispatch');
          if (c.req.raw.signal.aborted) {
            await c.env.DB.prepare(
              'UPDATE comparison_trials SET dispatched=0,model_invoked=0 WHERE job_id=? AND user_id=? AND trial_index=? AND lease_token=? AND dispatched=1 AND model_invoked IS NULL',
            )
              .bind(id, uid, trialIndex, lease)
              .run();
            fail(409, 'request_aborted', 'Request disconnected before provider invocation');
          }
          return c.env.AI!.run(modelId, inputs);
        },
      },
    });
    const budgetPolicy = {
      mode: proof.budgetMode,
      reservationBasis: proof.reservationBasis,
      budgetBoundVerified: proof.budgetBoundVerified,
      reservedBudgetUnits: proof.amount,
      actualNeurons: null,
      warnings: proof.warnings,
    };
    const item = {
      budgetPolicy,
      questionIndex: trial.question_index,
      modelIndex: trial.model_index,
      result,
    };
    const encoded = JSON.stringify(item);
    if (new TextEncoder().encode(encoded).byteLength > 40000)
      fail(413, 'comparison_result_too_large', 'Trial result exceeds the saved-result bound');
    const metric = JSON.stringify({
      questionIndex: trial.question_index,
      modelIndex: trial.model_index,
      modelId: result.modelId,
      usage: result.usage,
      timing: result.timing,
      status: result.status,
    });
    const published = await c.env.DB.batch([
      c.env.DB.prepare(
        "UPDATE comparison_trials SET state='complete',model_invoked=?,metrics_json=? WHERE job_id=? AND user_id=? AND trial_index=? AND state='running' AND lease_token=? AND lease_expires_at>? AND EXISTS(SELECT 1 FROM comparison_jobs j JOIN users u ON u.id=j.user_id WHERE j.id=? AND j.status='running' AND j.expires_at>? AND json_extract(u.settings_json,'$.workersAiConsent')=1 AND (?='reviewed-claim-selection' OR (json_extract(u.settings_json,'$.groundedGenerationConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationPolicyVersion')=?)) AND (SELECT version FROM source_policy_state WHERE id=1)=?) RETURNING trial_index",
      ).bind(
        result.modelInvoked ? 1 : 0,
        metric,
        id,
        uid,
        trialIndex,
        lease,
        now(),
        id,
        now(),
        model.answerMode ?? 'reviewed-claim-selection',
        GROUNDED_POLICY_VERSION,
        row.policy_version,
      ),
      c.env.DB.prepare(
        "UPDATE comparison_jobs SET metrics_json=json_insert(metrics_json,?,json(?)),updated_at=?,status=CASE WHEN NOT EXISTS(SELECT 1 FROM comparison_trials WHERE job_id=? AND state<>'complete') THEN 'complete' ELSE 'running' END WHERE id=? AND user_id=? AND status='running' AND EXISTS(SELECT 1 FROM comparison_trials WHERE job_id=? AND trial_index=? AND state='complete' AND lease_token=?)",
      ).bind(
        row.saved ? '$.results[#]' : '$[#]',
        row.saved ? encoded : metric,
        now(),
        id,
        id,
        uid,
        id,
        trialIndex,
        lease,
      ),
    ]);
    if (!published[0].results.length)
      fail(409, 'comparison_cancelled', 'Comparison stopped before publication');
    return c.json({
      state: await state(c.env, (await job(c.env, id, uid))!),
      trialIndex,
      result,
      budgetPolicy,
      replayed: false,
      resultAvailability: 'returned',
    });
  } catch (e) {
    await finish(c.env, id, uid, 'failed', 'trial_failed');
    aiError(e);
  }
});
