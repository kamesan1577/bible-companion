import {
  STANDARD_QUESTION,
  standardKey,
  readStandard,
  claimStandard,
  completeStandard,
  failStandard,
  cachedStandard,
} from './standard-cache';
import { budgetDispatchGuard } from './budget-dispatch';
import type { Context } from 'hono';
import { assertShareAccess } from './share-auth';
import {
  answerModeSchema,
  answerModes,
  assertAnswerMode,
  hasGroundedConsent,
  GROUNDED_POLICY_VERSION,
  GROUNDED_NOTICE_JA,
  type AnswerMode,
} from './answer-mode';
import { historicalSources, historicalWithin } from './history';
import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import { sha256, stableJSON, passageSchema, type Passage } from '@bible/core';
import {
  createCompanionAnswer,
  createSourceOnlyAnswer,
  prepareCompanionRequest,
  listModels,
  assertModelAuthorized,
  validateSettings,
  HarnessError,
  type AnswerInput,
  type GroundingSource,
  type ModelSettings,
} from '@bible/ai-harness';
import type { AppEnv, Env } from './types';
import { body, fail, now, requireDebugger, canDebug, configuredBudget } from './http';
import {
  getConversation,
  getSources,
  canDisplayAnswer,
  readingBoundaryOf,
  sourceSnapshot,
  sourcePolicyVersion,
  projectSavedComparison,
} from './data';
import {
  reserveBudget,
  reportedBudgetConsumption,
  settleBudget,
  rateLimit,
  estimateReservation,
  modelBudgetReadiness,
  loadBudgetAuthority,
  budgetMode,
} from './budget';
export const aiRoutes = new Hono<AppEnv>();
export const settingsSchema = z
  .object({
    maxOutputTokens: z.number().int().min(64).max(2048).optional(),
    temperature: z.number().min(0).max(2).optional(),
    timeoutMs: z.number().int().min(1000).max(30000).optional(),
    stream: z.literal(false).optional(),
    reasoning: z.enum(['off', 'low', 'medium', 'high']).optional(),
  })
  .strict();
export function authorization(env: Env, userId: string) {
  let connected: string[] = [];
  let termsReviewed: string[] = [];
  try {
    const parsed = JSON.parse(env.CONNECTED_MODELS);
    if (Array.isArray(parsed) && parsed.every((x) => typeof x === 'string')) connected = parsed;
  } catch {
    /* Fail closed. */
  }
  try {
    const value: unknown = JSON.parse(env.TERMS_REVIEWED_MODELS);
    if (Array.isArray(value) && value.every((x) => typeof x === 'string')) termsReviewed = value;
  } catch {}
  return {
    termsReviewedModelIds: termsReviewed,
    termsReviewVersion: env.TERMS_REVIEW_VERSION,
    ownerId: userId,
    connectedModelIds: env.AI_ENABLED === 'true' ? connected : [],
    paidModelIds: [],
  };
}
export async function ensureConsent(
  env: Env,
  userId: string,
  mode: AnswerMode = 'reviewed-claim-selection',
) {
  assertAnswerMode(env, mode);
  const row = await env.DB.prepare('SELECT settings_json FROM users WHERE id=?')
    .bind(userId)
    .first<{ settings_json: string }>();
  const settings = JSON.parse(row?.settings_json ?? '{}');
  if (!row || settings.workersAiConsent !== true)
    fail(
      403,
      'ai_consent_required',
      'Confirm sending the question and relevant reading context to Cloudflare Workers AI first.',
    );
  if (mode === 'grounded-generation' && !hasGroundedConsent(settings))
    fail(
      403,
      'grounded_consent_required',
      'Confirm the current experimental grounded-generation limitations first.',
    );
}
export function aiError(error: unknown): never {
  if (error instanceof HarnessError) {
    const status =
      error.code === 'BUDGET_EXCEEDED'
        ? 429
        : [
              'MODEL_UNCONNECTED',
              'MODEL_DISABLED',
              'MODEL_TERMS_UNREVIEWED',
              'PROVIDER_ERROR',
              'TIMEOUT',
              'BUDGET_UNVERIFIED',
            ].includes(error.code)
          ? 503
          : 400;
    fail(
      status,
      error.code.toLowerCase(),
      'AI could not answer this request. Your question is preserved.',
    );
  }
  throw error;
}
aiRoutes.post('/me/consents', async (c) => {
  const v = await body(
    c,
    z
      .object({
        workersAi: z.boolean().optional(),
        groundedGeneration: z
          .object({ accepted: z.boolean(), policyVersion: z.string().max(100) })
          .strict()
          .optional(),
      })
      .strict()
      .refine((value) => value.workersAi !== undefined || value.groundedGeneration !== undefined),
  );
  if (
    v.groundedGeneration?.accepted &&
    (v.workersAi !== true || v.groundedGeneration.policyVersion !== GROUNDED_POLICY_VERSION)
  )
    fail(
      400,
      'invalid_consent_policy',
      'Current policy and explicit provider consent are required.',
    );
  const changes: [string, unknown][] = [];
  // Grounded revocation cannot accidentally grant provider consent from a stale client snapshot.
  if (v.workersAi === false || (v.workersAi === true && v.groundedGeneration?.accepted !== false)) {
    changes.push(['workersAiConsent', v.workersAi], ['workersAiConsentAt', now()]);
  }
  if (v.groundedGeneration || v.workersAi === false) {
    changes.push(
      [
        'groundedGenerationConsent',
        v.workersAi !== false && v.groundedGeneration?.accepted === true,
      ],
      ['groundedGenerationPolicyVersion', v.groundedGeneration?.policyVersion ?? null],
    );
  }
  const result = await c.env.DB.prepare(
    'UPDATE users SET settings_json=json_set(settings_json,' +
      changes.map(([key]) => "'$." + key + "',json(?)").join(',') +
      ') WHERE id=? RETURNING settings_json',
  )
    .bind(...changes.map(([, value]) => JSON.stringify(value)), c.get('user').id)
    .first<{ settings_json: string }>();
  if (!result) fail(404, 'not_found', 'Account not found');
  const settings = JSON.parse(result.settings_json);
  return c.json({ workersAi: settings.workersAiConsent === true });
});
aiRoutes.get('/me/ai-policy', async (c) => {
  const row = await c.env.DB.prepare('SELECT settings_json FROM users WHERE id=?')
    .bind(c.get('user').id)
    .first<{ settings_json: string }>();
  const settings = JSON.parse(row?.settings_json ?? '{}');
  const allowed = answerModes(c.env);
  const proposed = answerModeSchema.safeParse(
    c.env.DEFAULT_ANSWER_MODE ?? 'reviewed-claim-selection',
  );
  return c.json({
    allowedAnswerModes: allowed,
    defaultAnswerMode: proposed.success && allowed.includes(proposed.data) ? proposed.data : null,
    groundedPolicyVersion: GROUNDED_POLICY_VERSION,
    groundedNoticeJa: GROUNDED_NOTICE_JA,
    workersAiConsent: settings.workersAiConsent === true,
    shareAiEnabled: c.env.SHARE_AI_ENABLED === 'true',
    shareAiConsent: c.env.SHARE_AI_ENABLED === 'true' && settings.shareAiConsent === true,
    groundedConsent: {
      accepted: hasGroundedConsent(settings),
      policyVersion: settings.groundedGenerationPolicyVersion ?? null,
    },
  });
});
aiRoutes.get('/usage', async (c) => {
  const day = new Date().toISOString().slice(0, 10);
  const row = await c.env.DB.prepare(
    'SELECT reserved,consumed FROM user_budget_days WHERE user_id=? AND day=?',
  )
    .bind(c.get('user').id, day)
    .first();
  return c.json({
    day,
    resetAt: Date.parse(day + 'T00:00:00Z') / 1000 + 86400,
    budgetUnits: row ?? { reserved: 0, consumed: 0 },
    limit: configuredBudget(c.env.DAILY_USER_BUDGET),
    unitKind:
      budgetMode(c.env) === 'free-provider-hard-stop'
        ? 'estimated-neurons-provider-free-hard-stop'
        : 'estimated-neurons-reserved-from-verified-bounds',
    budgetMode: budgetMode(c.env),
    usageAccounting: 'reservation-estimates-not-billed-neurons',
    actualNeurons: null,
  });
});
aiRoutes.get('/developer/models', async (c) => {
  requireDebugger(c);
  const catalog = listModels(authorization(c.env, c.get('user').id));
  const authority = await loadBudgetAuthority(
    c.env,
    catalog.map((model) => model.id),
  );
  const models = await Promise.all(
    catalog.map(async (model) => {
      const budgetReadiness = await modelBudgetReadiness(
        c.env,
        model.id,
        512,
        undefined,
        authority,
      );
      return {
        ...model,
        enabled: model.enabled && budgetReadiness.ready,
        disabledReason: model.disabledReason ?? budgetReadiness.reason,
        budgetReadiness,
        settingsSchema: {
          ...model.settingsSchema,
          timeoutMs: { ...model.settingsSchema.timeoutMs, maximum: 30000 },
        },
      };
    }),
  );
  return c.json({ models, defaultModelId: c.env.DEFAULT_MODEL_ID });
});
aiRoutes.put('/developer/model-preference', async (c) => {
  requireDebugger(c);
  const v = await body(
    c,
    z.object({ modelId: z.string().max(150), settings: settingsSchema.default({}) }).strict(),
  );
  try {
    assertModelAuthorized(v.modelId, authorization(c.env, c.get('user').id));
    validateSettings(v.modelId, v.settings);
    if (!(await modelBudgetReadiness(c.env, v.modelId, v.settings.maxOutputTokens ?? 512)).ready)
      fail(
        503,
        'budget_unverified',
        'This model needs current budget authority before selection; every prepared request is checked separately',
      );
  } catch (e) {
    aiError(e);
  }
  await c.env.DB.prepare(
    'INSERT INTO model_preferences(user_id,model_id,settings_json) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET model_id=excluded.model_id,settings_json=excluded.settings_json,version=version+1',
  )
    .bind(c.get('user').id, v.modelId, JSON.stringify(v.settings))
    .run();
  return c.json(v);
});
aiRoutes.delete('/developer/model-preference', async (c) => {
  requireDebugger(c);
  await c.env.DB.prepare('DELETE FROM model_preferences WHERE user_id=?')
    .bind(c.get('user').id)
    .run();
  return c.body(null, 204);
});
type Progress = (stage: string, text?: string) => Promise<void>;
export async function answerQuestion(c: Context<AppEnv>) {
  return answerTransport(c, false);
}
export async function standardExplanation(c: Context<AppEnv>) {
  return answerTransport(c, true);
}
async function answerTransport(c: Context<AppEnv>, standard: boolean) {
  if (!c.req.header('Accept')?.includes('text/event-stream')) return answerCore(c, standard);
  c.header('Cache-Control', 'private, no-store');
  c.header('X-Accel-Buffering', 'no');
  const response = streamSSE(c, async (stream) => {
    const controller = new AbortController();
    stream.onAbort(() => controller.abort());
    const progress: Progress = async (stage, text) => {
      await assertShareAccess(c);
      await stream.writeSSE({
        event: text === undefined ? 'progress' : 'preview',
        data: JSON.stringify({ stage, ...(text === undefined ? {} : { text }) }),
      });
    };
    try {
      await progress('preparing');
      const response = await answerCore(
        c,
        standard,
        progress,
        AbortSignal.any([c.req.raw.signal, controller.signal]),
      );
      await assertShareAccess(c);
      await stream.writeSSE({ event: 'complete', data: await response.text() });
    } catch (error) {
      const response = error instanceof HTTPException ? error.getResponse() : null;
      const envelope = response
        ? await response.json<{ error?: { code?: string } }>().catch(() => null)
        : null;
      await stream.writeSSE({
        event: 'failure',
        data: JSON.stringify({
          status: response?.status ?? 500,
          code: envelope?.error?.code ?? 'server_error',
        }),
      });
    }
  });
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}
async function answerCore(
  c: Context<AppEnv>,
  standard: boolean,
  progress?: Progress,
  signal: AbortSignal = c.req.raw.signal,
) {
  const v = standard
    ? {
        ...(await body(c, z.object({ requestId: z.string().uuid() }).strict())),
        question: STANDARD_QUESTION,
        sourceOnly: false,
        answerMode: 'grounded-generation' as const,
      }
    : await body(
        c,
        z
          .object({
            requestId: z.string().uuid(),
            question: z.string().trim().min(1).max(2000),
            sourceOnly: z.boolean().default(false),
            answerMode: answerModeSchema.default('reviewed-claim-selection'),
          })
          .strict(),
      );
  const user = c.get('user');
  const conversationID = c.req.param('id');
  if (!conversationID) fail(400, 'conversation_required', 'Conversation ID required');
  const conversation = await getConversation(c.env, user.id, conversationID);
  if (
    await c.env.DB.prepare(
      "SELECT id FROM request_cancellations WHERE user_id=? AND id=? AND kind='question'",
    )
      .bind(user.id, v.requestId)
      .first()
  )
    fail(409, 'request_cancelled', 'This request ID was cancelled');
  const hash = await sha256(
    stableJSON({
      v:
        v.answerMode === 'reviewed-claim-selection'
          ? { requestId: v.requestId, question: v.question, sourceOnly: v.sourceOnly }
          : v,
      ...(standard ? { standardExplanation: true } : {}),
      conversationId: conversation.id,
      passage: conversation.passage_json,
      readingBoundary: readingBoundaryOf(conversation),
      spoilers: conversation.spoiler_allowed,
      ...(c.env.GENERAL_KNOWLEDGE_ENABLED === 'true' ? { generalKnowledge: true } : {}),
    }),
  );
  const existing = await c.env.DB.prepare(
    'SELECT request_hash,status,result_json FROM generation_requests WHERE id=? AND user_id=?',
  )
    .bind(v.requestId, user.id)
    .first<{ request_hash: string; status: string; result_json: string | null }>();
  if (existing) {
    if (existing.request_hash !== hash)
      fail(
        409,
        'idempotency_conflict',
        'Request ID belongs to a different question or reading setting',
      );
    if (existing.status === 'complete') {
      const result = JSON.parse(existing.result_json!);
      const currentSources = historicalWithin(
        await historicalSources(c.env, [result]),
        readingBoundaryOf(conversation),
        !!conversation.spoiler_allowed,
      );
      if (!canDisplayAnswer(result, currentSources, !!conversation.spoiler_allowed))
        fail(409, 'source_policy_changed', 'Saved answer sources changed. Start a new request.');
      return c.json({ requestId: v.requestId, status: 'complete', result });
    }
    fail(
      409,
      'request_already_processed',
      'This request is running, cancelled or failed. Retry with a new request ID only after checking its status.',
    );
  }
  if (!v.sourceOnly) {
    if (!standard && (c.env.AI_ENABLED !== 'true' || !c.env.AI))
      fail(
        503,
        'ai_not_connected',
        'AI is not connected. Reviewed reading sources remain available.',
      );
    await ensureConsent(c.env, user.id, v.answerMode);
  }
  await rateLimit(c.env, 'question:' + user.id, 10);
  const preference =
    canDebug(c.env, user) && !c.get('shareCapability') && !standard
      ? await c.env.DB.prepare(
          'SELECT model_id,settings_json FROM model_preferences WHERE user_id=?',
        )
          .bind(user.id)
          .first<{ model_id: string; settings_json: string }>()
      : null;
  const passage = JSON.parse(conversation.passage_json) as Passage;
  const sourceState = await sourceSnapshot(
    c.env,
    readingBoundaryOf(conversation),
    !!conversation.spoiler_allowed,
    passage,
    !standard,
  );
  const sources = sourceState.sources;
  const previous = await c.env.DB.prepare(
    'SELECT role,content_json FROM messages WHERE conversation_id=? AND user_id=? ORDER BY created_at DESC,rowid DESC LIMIT 12',
  )
    .bind(conversation.id, user.id)
    .all<{ role: 'user' | 'assistant'; content_json: string }>();
  const history = previous.results
    .reverse()
    .map((row) => {
      const content = JSON.parse(row.content_json);
      return {
        role: row.role,
        content: row.role === 'user' ? content.text : content.answer,
        ownerId: user.id,
        scope: content.scope,
      };
    })
    .filter((row) => typeof row.content === 'string' && row.content.length <= 4000 && row.scope);
  const input: AnswerInput = {
    passage,
    readingBoundary: readingBoundaryOf(conversation),
    history: standard ? [] : history,
    question: v.question,
    translation: conversation.translation ?? undefined,
    spoilerAllowed: !!conversation.spoiler_allowed,
    sources,
    modelId: preference?.model_id ?? c.env.DEFAULT_MODEL_ID,
    settings: preference
      ? { ...JSON.parse(preference.settings_json), ...(progress ? { stream: true } : {}) }
      : { maxOutputTokens: 2048, temperature: 0.2, timeoutMs: 30000, stream: !!progress },
  };
  const publicKey = standard
    ? await standardKey(input, sourceState.version, c.env.GENERAL_KNOWLEDGE_ENABLED === 'true')
    : null;
  let sharedResult = publicKey ? await readStandard(c.env, publicKey.key) : null;
  let cacheToken: string | null = null;
  try {
    if (!sharedResult)
      prepareCompanionRequest(input, {
        authorization: authorization(c.env, user.id),
        answerMode: v.answerMode,
        allowGeneralKnowledge: c.env.GENERAL_KNOWLEDGE_ENABLED === 'true',
      });
    if (!v.sourceOnly && !sharedResult) {
      assertModelAuthorized(input.modelId!, authorization(c.env, user.id));
    }
  } catch (e) {
    aiError(e);
  }
  let reservationAmount = 0;
  let verifiedReservation: Awaited<ReturnType<typeof estimateReservation>> | undefined;
  try {
    if (!v.sourceOnly && !sharedResult) {
      if (c.env.AI_ENABLED !== 'true' || !c.env.AI)
        fail(503, 'ai_not_connected', 'AI is not connected');
      verifiedReservation = await estimateReservation(
        c.env,
        input,
        authorization(c.env, user.id),
        v.answerMode,
      );
      reservationAmount = verifiedReservation.amount;
    }
  } catch (e) {
    aiError(e);
  }
  if (publicKey && !sharedResult) {
    const ticket = await claimStandard(c.env, publicKey.key, publicKey.json);
    cacheToken = ticket.token;
    sharedResult = ticket.result;
  }
  if (sharedResult) verifiedReservation = undefined;
  const claimed = await c.env.DB.prepare(
    "INSERT OR IGNORE INTO generation_requests(id,user_id,conversation_id,request_hash,status,created_at,updated_at) SELECT ?,?,?,?,'reserved',?,? WHERE NOT EXISTS(SELECT 1 FROM request_cancellations WHERE user_id=? AND id=? AND kind='question') RETURNING id",
  )
    .bind(v.requestId, user.id, conversation.id, hash, now(), now(), user.id, v.requestId)
    .first();
  if (!claimed) {
    if (publicKey && cacheToken) await failStandard(c.env, publicKey.key, cacheToken);
    fail(409, 'request_already_processed', 'Request ID is already in use');
  }
  let budgetReserved = false;
  let dispatched = false;
  let settledUsage: number | null = null;
  try {
    if (!v.sourceOnly && !sharedResult) {
      await reserveBudget(c.env, user.id, v.requestId, reservationAmount);
      budgetReserved = true;
    }
    const started = await c.env.DB.prepare(
      "UPDATE generation_requests SET status='running',updated_at=? WHERE id=? AND user_id=? AND status='reserved' AND NOT EXISTS(SELECT 1 FROM request_cancellations WHERE user_id=? AND id=? AND kind='question') RETURNING id",
    )
      .bind(now(), v.requestId, user.id, user.id, v.requestId)
      .first();
    if (!started) fail(409, 'request_cancelled', 'Request was cancelled before generation');
    await progress?.(sharedResult ? 'cached' : 'generating');
    const result = sharedResult
      ? cachedStandard(sharedResult)
      : v.sourceOnly
        ? createSourceOnlyAnswer(input, user.id)
        : await createCompanionAnswer(input, {
            answerMode: v.answerMode,
            allowGeneralKnowledge: c.env.GENERAL_KNOWLEDGE_ENABLED === 'true',
            ai: {
              run: async (model, inputs) => {
                assertModelAuthorized(model, authorization(c.env, user.id));
                assertAnswerMode(c.env, v.answerMode);
                const guard = budgetDispatchGuard(c.env, verifiedReservation!.dispatchIdentity);
                const dispatchClaim = await c.env.DB.prepare(
                  `UPDATE generation_requests SET updated_at=? WHERE id=? AND user_id=? AND status='running' AND EXISTS(SELECT 1 FROM conversations c JOIN users u ON u.id=c.user_id WHERE c.id=? AND c.user_id=? AND c.spoiler_allowed=? AND json_extract(u.settings_json,'$.workersAiConsent')=1 AND (?='reviewed-claim-selection' OR (json_extract(u.settings_json,'$.groundedGenerationConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationPolicyVersion')=?))) AND (SELECT version FROM source_policy_state WHERE id=1)=? AND ${guard.sql} RETURNING id`,
                )
                  .bind(
                    now(),
                    v.requestId,
                    user.id,
                    conversation.id,
                    user.id,
                    conversation.spoiler_allowed,
                    v.answerMode,
                    GROUNDED_POLICY_VERSION,
                    sourceState.version,
                    ...guard.params,
                  )
                  .first();
                if (!dispatchClaim)
                  fail(409, 'dispatch_policy_changed', 'Request stopped before provider dispatch');
                if (signal.aborted)
                  fail(409, 'request_aborted', 'Request disconnected before provider invocation');
                dispatched = true;
                await assertShareAccess(c);
                return c.env.AI!.run(model, inputs);
              },
            },
            authorization: authorization(c.env, user.id),
            signal,
            onProgress: progress,
            onPreview: progress
              ? async (text) => {
                  if (sourceState.version !== (await sourcePolicyVersion(c.env)))
                    fail(409, 'source_policy_changed', 'Sources changed while generating');
                  const active = await c.env.DB.prepare(
                    'SELECT status FROM generation_requests WHERE id=? AND user_id=?',
                  )
                    .bind(v.requestId, user.id)
                    .first<{ status: string }>();
                  if (active?.status !== 'running')
                    fail(409, 'request_cancelled', 'Request stopped');
                  await progress('receiving', text);
                }
              : undefined,
          });
    await progress?.('saving');
    if (verifiedReservation?.budgetMode === 'free-provider-hard-stop')
      settledUsage = reportedBudgetConsumption(input.modelId!, result.usage.actual);
    const current = await getConversation(c.env, user.id, conversation.id);
    const request = await c.env.DB.prepare(
      'SELECT status FROM generation_requests WHERE id=? AND user_id=?',
    )
      .bind(v.requestId, user.id)
      .first<{ status: string }>();
    if (current.spoiler_allowed !== conversation.spoiler_allowed || request?.status === 'cancelled')
      fail(
        409,
        'request_cancelled',
        'Reading settings changed or the request was cancelled; the answer was not saved',
      );
    const scope = {
      passage,
      readingBoundary: readingBoundaryOf(conversation),
      spoilerAllowed: !!conversation.spoiler_allowed,
      sourceIds: result.citations.map((x) => x.sourceId),
      sourceVersions: Object.fromEntries(result.citations.map((x) => [x.sourceId, x.version])),
    };
    const annotated = {
      ...result,
      standardExplanation: standard,
      cache: standard ? (sharedResult ? 'public-standard-hit' : 'public-standard-miss') : 'private',
      budgetPolicy: sharedResult
        ? {
            mode: 'public-standard-cache',
            actualNeurons: 0,
            reservedBudgetUnits: 0,
            usageAccounting: 'cache-hit-no-provider',
            warnings: [],
          }
        : verifiedReservation
          ? {
              mode: verifiedReservation.budgetMode,
              reservationBasis: verifiedReservation.reservationBasis,
              budgetBoundVerified: verifiedReservation.budgetBoundVerified,
              reservedBudgetUnits: verifiedReservation.amount,
              actualNeurons: settledUsage !== null ? result.usage.neurons : null,
              usageAccounting:
                settledUsage !== null
                  ? 'provider-reported-usage-rounded-up'
                  : 'conservative-reservation',
              warnings: verifiedReservation.warnings,
            }
          : null,
      sourcePolicyVersion: sourceState.version,
      spoilerAllowed: !!conversation.spoiler_allowed,
      scope,
    };
    if (sourceState.version !== (await sourcePolicyVersion(c.env)))
      fail(
        409,
        'source_policy_changed',
        'Sources changed during generation; the answer was not saved',
      );
    await c.env.DB.batch([
      c.env.DB.prepare(
        "UPDATE generation_requests SET status='complete',result_json=?,updated_at=? WHERE id=? AND user_id=? AND status='running' AND EXISTS(SELECT 1 FROM conversations WHERE id=? AND user_id=? AND spoiler_allowed=?) AND (SELECT version FROM source_policy_state WHERE id=1)=? AND (?=1 OR EXISTS(SELECT 1 FROM users u WHERE u.id=? AND json_extract(u.settings_json,'$.workersAiConsent')=1 AND (?='reviewed-claim-selection' OR (json_extract(u.settings_json,'$.groundedGenerationConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationPolicyVersion')=?))))",
      ).bind(
        JSON.stringify(annotated),
        now(),
        v.requestId,
        user.id,
        conversation.id,
        user.id,
        conversation.spoiler_allowed,
        sourceState.version,
        v.sourceOnly ? 1 : 0,
        user.id,
        v.answerMode,
        GROUNDED_POLICY_VERSION,
      ),
      c.env.DB.prepare(
        "INSERT INTO messages(id,conversation_id,user_id,role,content_json,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM generation_requests WHERE id=? AND user_id=? AND status='complete')",
      ).bind(
        crypto.randomUUID(),
        conversation.id,
        user.id,
        'user',
        JSON.stringify({
          text: v.question,
          standardExplanation: standard,
          scope: {
            passage,
            readingBoundary: readingBoundaryOf(conversation),
            spoilerAllowed: !!conversation.spoiler_allowed,
            sourceIds: [],
            sourceVersions: {},
          },
        }),
        now(),
        v.requestId,
        user.id,
      ),
      c.env.DB.prepare(
        "INSERT INTO messages(id,conversation_id,user_id,role,content_json,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM generation_requests WHERE id=? AND user_id=? AND status='complete')",
      ).bind(
        crypto.randomUUID(),
        conversation.id,
        user.id,
        'assistant',
        JSON.stringify(annotated),
        now(),
        v.requestId,
        user.id,
      ),
    ]);
    const saved = await c.env.DB.prepare(
      'SELECT status FROM generation_requests WHERE id=? AND user_id=?',
    )
      .bind(v.requestId, user.id)
      .first<{ status: string }>();
    if (saved?.status !== 'complete')
      fail(409, 'request_cancelled', 'The request was cancelled before completion');
    await assertShareAccess(c);
    if (publicKey && cacheToken) await completeStandard(c.env, publicKey.key, cacheToken, result);
    return c.json({ requestId: v.requestId, status: 'complete', result: annotated });
  } catch (error) {
    if (publicKey && cacheToken) await failStandard(c.env, publicKey.key, cacheToken);
    await c.env.DB.prepare(
      "UPDATE generation_requests SET status='failed',updated_at=? WHERE id=? AND user_id=? AND status!='cancelled'",
    )
      .bind(now(), v.requestId, user.id)
      .run();
    aiError(error);
  } finally {
    if (budgetReserved) await settleBudget(c.env, v.requestId, dispatched ? settledUsage : 0);
  }
}
aiRoutes.post('/conversations/:id/questions', answerQuestion);
aiRoutes.post('/conversations/:id/explanation', standardExplanation);
export async function questionStatus(c: Context<AppEnv>) {
  const row = await c.env.DB.prepare(
    'SELECT g.id,g.status,g.result_json,c.spoiler_allowed,c.passage_json,c.reading_boundary_json FROM generation_requests g JOIN conversations c ON c.id=g.conversation_id AND c.user_id=g.user_id WHERE g.id=? AND g.user_id=?',
  )
    .bind(c.req.param('id'), c.get('user').id)
    .first<{
      id: string;
      status: string;
      result_json: string | null;
      spoiler_allowed: number;
      passage_json: string;
      reading_boundary_json: string | null;
    }>();
  if (!row) {
    if (
      await c.env.DB.prepare(
        "SELECT id FROM request_cancellations WHERE user_id=? AND id=? AND kind='question'",
      )
        .bind(c.get('user').id, c.req.param('id'))
        .first()
    )
      return c.json({ requestId: c.req.param('id'), status: 'cancelled', result: null });
    fail(
      404,
      'not_found',
      'Request state is not yet known; retry only with the same frozen request ID',
    );
  }
  const result = row.result_json ? JSON.parse(row.result_json) : null;
  const currentSources = historicalWithin(
    await historicalSources(c.env, [result]),
    readingBoundaryOf(row),
    !!row.spoiler_allowed,
  );
  return c.json({
    requestId: row.id,
    status: row.status,
    result: canDisplayAnswer(result, currentSources, !!row.spoiler_allowed) ? result : null,
  });
}
aiRoutes.get('/requests/:id', questionStatus);
export async function cancelQuestion(c: Context<AppEnv>) {
  const id = c.req.param('id');
  if (!z.string().uuid().safeParse(id).success)
    fail(400, 'invalid_request_id', 'Expected a request UUID');
  await c.env.DB.batch([
    c.env.DB.prepare(
      "INSERT OR IGNORE INTO request_cancellations(user_id,id,kind,created_at) VALUES(?,?,'question',?)",
    ).bind(c.get('user').id, id, now()),
    c.env.DB.prepare(
      "UPDATE generation_requests SET status='cancelled',updated_at=? WHERE id=? AND user_id=? AND status IN ('reserved','running')",
    ).bind(now(), id, c.get('user').id),
  ]);
  const row = await c.env.DB.prepare(
    'SELECT status FROM generation_requests WHERE id=? AND user_id=?',
  )
    .bind(id, c.get('user').id)
    .first<{ status: string }>();
  if (row?.status === 'complete')
    fail(
      409,
      'request_complete',
      'The request completed before cancellation; retrieve its existing result',
    );
  return c.json({ status: 'cancelled', usageMayHaveOccurred: true });
}
aiRoutes.delete('/requests/:id', cancelQuestion);
