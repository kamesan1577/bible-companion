import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser, TestDatabase } from './helpers/db';
import { MODEL_TERMS_POLICY_VERSION, PRICING_VERSION } from '@bible/ai-harness';
import { GROUNDED_POLICY_VERSION } from '../src/answer-mode';
const model = '@cf/google/gemma-4-26b-a4b-it';
async function setup() {
  const env = {
    ...testEnv(),
    AI_ENABLED: 'true',
    CONNECTED_MODELS: JSON.stringify([model]),
    TERMS_REVIEWED_MODELS: JSON.stringify([model]),
    TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
    ALLOWED_ANSWER_MODES: JSON.stringify(['reviewed-claim-selection', 'grounded-generation']),
    AI: {
      async run() {
        return {
          response: JSON.stringify({
            status: 'answer',
            claims: [
              {
                text: 'ソステネは会堂の指導者として登場します。',
                kind: 'fact',
                sourceId: 'act-18-17',
                evidenceQuote: 'Sosthenes, the ruler of the synagogue',
              },
            ],
          }),
        };
      },
    },
  };
  const user = await seedUser(env, crypto.randomUUID(), 'owner');
  const proof = {
    modelId: model,
    pricingVersion: PRICING_VERSION,
    inputTokenUpperBound: 30000,
    outputTokenUpperBound: 2048,
    includesHiddenReasoning: true,
    evidenceRef: 'synthetic-mode-test-not-real-proof',
    expiresAt: new Date(Date.now() + 3600000).toISOString(),
  };
  await env.DB.prepare(
    'INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)',
  )
    .bind(model, PRICING_VERSION, JSON.stringify(proof), 1)
    .run();
  const post = (path: string, value: unknown) =>
    app.request(
      '/v1' + path,
      { method: 'POST', headers: user.headers, body: JSON.stringify(value) },
      env,
    );
  const imported = (await (
    await post('/imports', { idempotencyKey: crypto.randomUUID(), sharedText: '使徒18:17' })
  ).json()) as { id: string };
  const chat = (await (await post('/conversations', { importId: imported.id })).json()) as {
    id: string;
  };
  const consent = () =>
    post('/me/consents', {
      workersAi: true,
      groundedGeneration: { accepted: true, policyVersion: GROUNDED_POLICY_VERSION },
    });
  const ask = (requestId = crypto.randomUUID(), answerMode = 'grounded-generation') =>
    post('/conversations/' + chat.id + '/questions', {
      requestId,
      question: 'ソステネは誰ですか',
      answerMode,
    });
  return { env, user, post, chat, consent, ask };
}
describe('explicit experimental answer-mode integration', () => {
  it('requires server allowance and exact current consent before any reservation', async () => {
    const x = await setup();
    await x.post('/me/consents', { workersAi: true });
    expect((await x.ask()).status).toBe(403);
    expect(
      (
        await x.post('/me/consents', {
          workersAi: true,
          groundedGeneration: { accepted: true, policyVersion: 'old' },
        })
      ).status,
    ).toBe(400);
    await x.consent();
    x.env.ALLOWED_ANSWER_MODES = '["reviewed-claim-selection"]';
    expect((await x.ask()).status).toBe(503);
    expect(await x.env.DB.prepare('SELECT count(*) n FROM budget_reservations').first()).toEqual({
      n: 0,
    });
  });
  it('reaches grounded generation, freezes mode in replay identity, and reports policy', async () => {
    const x = await setup();
    await x.consent();
    const id = crypto.randomUUID();
    const response = await x.ask(id);
    expect(response.status).toBe(200);
    const value = (await response.json()) as {
      result: { mode: string; modelInvoked: boolean; answer: string };
    };
    expect(value.result.mode).toBe('grounded-generation');
    expect(value.result.modelInvoked).toBe(true);
    expect(value.result.answer).toContain('ソステネ');
    expect((await x.ask(id, 'reviewed-claim-selection')).status).toBe(409);
    const policy = (await (
      await app.request('/v1/me/ai-policy', { headers: x.user.headers }, x.env)
    ).json()) as { groundedConsent: { accepted: boolean } };
    expect(policy.groundedConsent.accepted).toBe(true);
  });
  it('revocation during inference prevents publication while preserving dispatched reservation', async () => {
    const x = await setup();
    await x.consent();
    let release!: (value: any) => void;
    let started!: () => void;
    const entered = new Promise<void>((r) => (started = r));
    const original = x.env.AI.run;
    x.env.AI.run = async () => {
      started();
      return new Promise((r) => (release = r));
    };
    const pending = x.ask();
    await entered;
    await x.post('/me/consents', {
      workersAi: true,
      groundedGeneration: { accepted: false, policyVersion: GROUNDED_POLICY_VERSION },
    });
    release(await original());
    expect((await pending).status).toBe(409);
    expect(await x.env.DB.prepare('SELECT count(*) n FROM messages').first()).toEqual({ n: 0 });
    expect(
      (await x.env.DB.prepare('SELECT consumed FROM budget_days').first<{ consumed: number }>())!
        .consumed,
    ).toBeGreaterThan(0);
  });
  it('reaches generated contextual answers from pinned primary text outside the curated Acts corpus', async () => {
    const x = await setup();
    await x.consent();
    const { seedAssetCorpus, realAssetBinding } = await import('./helpers/scripture-assets');
    await seedAssetCorpus(x.env.DB as unknown as TestDatabase);
    Object.assign(x.env, { SCRIPTURE_ASSETS: realAssetBinding() });
    const passage = { book: 'GEN', start: { chapter: 1, verse: 1 }, end: { chapter: 1, verse: 1 } };
    const { getSources } = await import('../src/data');
    const sources = await getSources(x.env, passage, false);
    const source = sources.find((s) => s.id === 'webp:GEN:1:1')!;
    expect(source.reviewed).toBe(false);
    expect(source.claims).toEqual([]);
    let calls = 0;
    x.env.AI.run = async () => {
      calls++;
      return {
        response: JSON.stringify({
          status: 'answer',
          claims: [
            {
              text: 'この節は神による天地の創造を述べています。',
              kind: 'fact',
              sourceId: source.id,
              evidenceQuote: source.text,
            },
          ],
        }),
      };
    };
    const imported = (await (
      await x.post('/imports', { idempotencyKey: crypto.randomUUID(), ranges: [passage] })
    ).json()) as { id: string };
    const chat = (await (await x.post('/conversations', { importId: imported.id })).json()) as {
      id: string;
    };
    const response = await x.post('/conversations/' + chat.id + '/questions', {
      requestId: crypto.randomUUID(),
      question: 'この節は何を述べていますか',
      answerMode: 'grounded-generation',
    });
    expect(response.status).toBe(200);
    const value = (await response.json()) as {
      result: { mode: string; modelInvoked: boolean; citations: { sourceId: string }[] };
    };
    expect(calls).toBe(1);
    expect(value.result.modelInvoked).toBe(true);
    expect(value.result.mode).toBe('grounded-generation');
    expect(value.result.citations[0].sourceId).toBe(source.id);
  });
  it('permits comparing the same model in two distinct modes but not duplicate same-mode trials', async () => {
    const x = await setup();
    await x.consent();
    const plan = {
      requestId: crypto.randomUUID(),
      models: [
        { modelId: model, answerMode: 'reviewed-claim-selection' },
        { modelId: model, answerMode: 'grounded-generation' },
      ],
      questions: [
        {
          passage: {
            book: 'ACT',
            start: { chapter: 18, verse: 17 },
            end: { chapter: 18, verse: 17 },
          },
          question: '誰ですか',
        },
      ],
    };
    expect((await x.post('/developer/comparisons/plan', plan)).status).toBe(200);
    plan.models[1].answerMode = 'reviewed-claim-selection';
    expect((await x.post('/developer/comparisons/plan', plan)).status).toBe(400);
  });
  it('grounded revocation never re-enables provider consent and preserves unrelated settings', async () => {
    const x = await setup();
    await x.consent();
    await x.env.DB.prepare(
      "UPDATE users SET settings_json=json_set(settings_json,'$.unrelated','retained') WHERE id=?",
    )
      .bind(x.user.id)
      .run();
    await x.post('/me/consents', { workersAi: false });
    expect(
      (
        await x.post('/me/consents', {
          workersAi: true,
          groundedGeneration: { accepted: false, policyVersion: GROUNDED_POLICY_VERSION },
        })
      ).status,
    ).toBe(200);
    const row = await x.env.DB.prepare('SELECT settings_json FROM users WHERE id=?')
      .bind(x.user.id)
      .first<{ settings_json: string }>();
    expect(JSON.parse(row!.settings_json)).toMatchObject({
      workersAiConsent: false,
      groundedGenerationConsent: false,
      unrelated: 'retained',
    });
    expect(
      (
        await x.post('/me/consents', {
          groundedGeneration: { accepted: false, policyVersion: GROUNDED_POLICY_VERSION },
        })
      ).status,
    ).toBe(200);
    expect((await x.post('/me/consents', {})).status).toBe(400);
  });
  it('keeps a late narrowed target in bounded primary retrieval instead of returning the first48 imported verses', async () => {
    const x = await setup();
    const { seedAssetCorpus, realAssetBinding } = await import('./helpers/scripture-assets');
    await seedAssetCorpus(x.env.DB as unknown as TestDatabase);
    Object.assign(x.env, { SCRIPTURE_ASSETS: realAssetBinding() });
    const boundary = {
        book: 'PSA',
        start: { chapter: 119, verse: 1 },
        end: { chapter: 119, verse: 176 },
      },
      target = { ...boundary, start: { chapter: 119, verse: 176 } };
    const imported = (await (
      await x.post('/imports', { idempotencyKey: crypto.randomUUID(), ranges: [boundary] })
    ).json()) as { id: string };
    const chat = (await (
      await x.post('/conversations', { importId: imported.id, passage: target })
    ).json()) as { id: string };
    const response = await x.post('/conversations/' + chat.id + '/questions', {
      requestId: crypto.randomUUID(),
      question: 'この節の資料',
      sourceOnly: true,
    });
    expect(response.status).toBe(200);
    const value = (await response.json()) as { result: { citations: { sourceId: string }[] } };
    expect(value.result.citations.map((c) => c.sourceId)).toEqual(['webp:PSA:119:176']);
  });
});
