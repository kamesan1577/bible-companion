import { it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser } from './helpers/db';
import { MODEL_TERMS_POLICY_VERSION } from '@bible/ai-harness';
import { GROUNDED_POLICY_VERSION } from '../src/answer-mode';
async function fixture() {
  const env = testEnv(),
    user = await seedUser(env);
  let calls = 0;
  Object.assign(env, {
    AI_BUDGET_MODE: 'free-provider-hard-stop',
    AI_ENABLED: 'true',
    SHARE_AI_ENABLED: 'true',
    CONNECTED_MODELS: '["@cf/google/gemma-4-26b-a4b-it"]',
    TERMS_REVIEWED_MODELS: '["@cf/google/gemma-4-26b-a4b-it"]',
    TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
    ALLOWED_ANSWER_MODES: '["grounded-generation"]',
    AI: {
      async run() {
        calls++;
        return {
          response: JSON.stringify({
            status: 'answer',
            claims: [
              {
                text: 'プリスキラとアキラは神の道をより正確に説明しました。',
                kind: 'fact',
                sourceId: 'act-18-24-26',
                evidenceQuote: 'explained to him the way of God more accurately',
              },
            ],
          }),
        };
      },
    },
  });
  const post = (path: string, value: unknown, headers = user.headers) =>
    app.request(path, { method: 'POST', headers, body: JSON.stringify(value) }, env);
  await post('/v1/me/consents', {
    workersAi: true,
    groundedGeneration: { accepted: true, policyVersion: GROUNDED_POLICY_VERSION },
  });
  const cap = (await (await post('/v1/me/share-access', { enabled: true })).json()) as {
    token: string;
  };
  const headers = { Authorization: 'Bearer ' + cap.token, 'Content-Type': 'application/json' };
  const start = (await (
    await post(
      '/share/start',
      { requestId: crypto.randomUUID(), sharedText: '使徒18:24-26' },
      headers,
    )
  ).json()) as { items: { conversationId: string }[] };
  const ask = () =>
    post(
      '/share/conversations/' + start.items[0].conversationId + '/questions',
      {
        requestId: crypto.randomUUID(),
        question: '何をした人物ですか？',
        answerMode: 'grounded-generation',
      },
      headers,
    );
  return { env, user, post, headers, ask, calls: () => calls };
}
it('normal generation works after a historical contract certificate has expired, with no renewal bindings', async () => {
  const f = await fixture();
  await f.env.DB.prepare(
    'INSERT INTO ai_free_account_receipts VALUES(\'historical\',?,\'{"expiresAt":"2000-01-01T00:00:00Z"}\',1,NULL)',
  )
    .bind('a'.repeat(32))
    .run();
  expect((await f.ask()).status).toBe(200);
  expect(f.calls()).toBe(1);
  expect(
    await f.env.DB.prepare(
      "SELECT receipt_json FROM ai_free_account_receipts WHERE id='historical'",
    ).first(),
  ).toEqual({ receipt_json: '{"expiresAt":"2000-01-01T00:00:00Z"}' });
});
for (const budget of ['app', 'user'])
  it('still stops before inference on ' + budget + ' daily budget exhaustion', async () => {
    const f = await fixture();
    if (budget === 'app')
      await f.env.DB.prepare('INSERT INTO budget_days(day,consumed)VALUES(?,9000)')
        .bind(new Date().toISOString().slice(0, 10))
        .run();
    else
      await f.env.DB.prepare('INSERT INTO user_budget_days(user_id,day,consumed)VALUES(?,?,2000)')
        .bind(f.user.id, new Date().toISOString().slice(0, 10))
        .run();
    const r = await f.ask();
    expect(r.status).toBe(429);
    expect(f.calls()).toBe(0);
  });
for (const scope of ['session', 'share'])
  it('still refuses expired ' + scope + ' authentication before inference', async () => {
    const f = await fixture();
    await f.env.DB.prepare(
      scope === 'session'
        ? 'UPDATE sessions SET expires_at=1 WHERE user_id=?'
        : 'UPDATE share_ai_access SET expires_at=1 WHERE user_id=?',
    )
      .bind(f.user.id)
      .run();
    expect((await f.ask()).status).toBe(401);
    expect(f.calls()).toBe(0);
  });
