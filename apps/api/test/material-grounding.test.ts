import { fixture } from './helpers/fixtures';
import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser, TestDatabase } from './helpers/db';
import { getSources } from '../src/data';
import { MODEL_TERMS_POLICY_VERSION, PRICING_VERSION } from '@bible/ai-harness';
import { GROUNDED_POLICY_VERSION } from '../src/answer-mode';
const passage = { book: 'ACT', start: { chapter: 18, verse: 18 }, end: { chapter: 18, verse: 18 } };
async function setup() {
  const db = new TestDatabase(),
    env = testEnv(db),
    user = await seedUser(env),
    model = env.DEFAULT_MODEL_ID;
  Object.assign(env, {
    AI_ENABLED: 'true',
    CONNECTED_MODELS: JSON.stringify([model]),
    TERMS_REVIEWED_MODELS: JSON.stringify([model]),
    TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
    ALLOWED_ANSWER_MODES: '["reviewed-claim-selection","grounded-generation"]',
  });
  const proof = {
    modelId: model,
    pricingVersion: PRICING_VERSION,
    inputTokenUpperBound: 30000,
    outputTokenUpperBound: 2048,
    includesHiddenReasoning: true,
    evidenceRef: 'synthetic-material-test-not-real-proof',
    expiresAt: new Date(Date.now() + 3600000).toISOString(),
  };
  await env.DB.prepare(
    'INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)',
  )
    .bind(model, PRICING_VERSION, JSON.stringify(proof), 1)
    .run();
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?')
    .bind(
      JSON.stringify({
        workersAiConsent: true,
        groundedGenerationConsent: true,
        groundedGenerationPolicyVersion: GROUNDED_POLICY_VERSION,
      }),
      user.id,
    )
    .run();
  const post = (path: string, value: unknown) =>
    app.request(
      '/v1' + path,
      { method: 'POST', headers: user.headers, body: JSON.stringify(value) },
      env,
    );
  const imported = (await (
    await post('/imports', { idempotencyKey: crypto.randomUUID(), ranges: [passage] })
  ).json()) as { id: string };
  const chat = (await (await post('/conversations', { importId: imported.id })).json()) as {
    id: string;
  };
  return { db, env, user, post, chat };
}
describe('approved material summary grounding', () => {
  it('answers the Cenchreae geography question with distinct commentary and complete primary references', async () => {
    const x = await setup();
    let received = '';
    x.env.AI = {
      async run(_model, input) {
        received = JSON.stringify(input);
        return {
          response: JSON.stringify({
            status: 'answer',
            claims: [
              {
                text: 'ケンクレアはコリントの東側の港です。',
                kind: 'fact',
                sourceId: 'material:place-cenchreae',
                evidenceQuote: 'コリントの東側の港として発掘研究が行われている場所です。',
              },
            ],
          }),
        };
      },
    };
    const response = await x.post('/conversations/' + x.chat.id + '/questions', {
      requestId: crypto.randomUUID(),
      question: 'ケンクレアはどのあたりですか',
      answerMode: 'grounded-generation',
    });
    expect(response.status).toBe(200);
    const value = (await response.json()) as {
      result: { answer: string; citations: any[]; validation: { semanticGrounding: string } };
    };
    fixture('material-answer', value);
    expect(value.result.answer).toContain('東側の港');
    expect(received).toContain('reviewed-material-summary');
    const citation = value.result.citations[0];
    expect(citation.sourceKind).toBe('commentary');
    expect(
      citation.materialProvenance.references.some((r: any) => r.url.includes('ascsa.edu.gr')),
    ).toBe(true);
    expect(
      citation.materialProvenance.references.some((r: any) => r.url.includes('ebible.org')),
    ).toBe(true);
    expect(value.result.validation.semanticGrounding).toBe('unverified');
    await x.env.DB.prepare(
      "UPDATE public_materials SET rights_status='revoked' WHERE id='place-cenchreae'",
    ).run();
    const history = (await (
      await app.request('/v1/conversations/' + x.chat.id, { headers: x.user.headers }, x.env)
    ).json()) as { messages: { role: string; content: any }[] };
    expect(history.messages.find((m) => m.role === 'assistant')!.content.hidden).toBe(true);
    expect(history.messages.find((m) => m.role === 'user')!.content.text).toBe(
      'ケンクレアはどのあたりですか',
    );
  });
  it('excludes denied, unreviewed, future and forged material identities before prompts', async () => {
    const x = await setup();
    const original = x.db.sqlite
      .prepare("SELECT * FROM public_materials WHERE id='place-cenchreae'")
      .get() as any;
    const data = JSON.parse(original.data_json);
    data.id = 'unreviewed-card';
    data.version = 'test.1';
    data.reviewed = false;
    data.summary = 'UNREVIEWED_SECRET';
    x.db.sqlite
      .prepare(
        'INSERT INTO public_materials(id,kind,book,data_json,version,rights_status,active) VALUES(?,?,?,?,?,?,?)',
      )
      .run(data.id, data.kind, 'ACT', JSON.stringify(data), data.version, 'approved', 1);
    x.db.sqlite
      .prepare("UPDATE public_materials SET rights_status='revoked' WHERE id='place-cenchreae'")
      .run();
    const sources = await getSources(x.env, passage, false, passage, undefined, true);
    expect(JSON.stringify(sources)).not.toContain('UNREVIEWED_SECRET');
    expect(sources.some((s) => s.id === 'material:place-cenchreae')).toBe(false);
    expect(sources.some((s) => s.id.includes('apollos'))).toBe(false);
    expect(() =>
      x.db.sqlite
        .prepare(
          "INSERT INTO public_sources SELECT 'material:place-cenchreae',book,start_chapter,start_verse,end_chapter,end_verse,kind,title,content_json,version,rights_status,active FROM public_sources LIMIT 1",
        )
        .run(),
    ).toThrow();
  });
  it('requires a new version for semantic changes, even after delete and reinsert', async () => {
    const x = await setup(),
      row = x.db.sqlite
        .prepare("SELECT * FROM public_materials WHERE id='place-cenchreae'")
        .get() as any;
    expect(() =>
      x.db.sqlite
        .prepare(
          "UPDATE public_materials SET data_json=json_set(data_json,'$.summary','changed') WHERE id=?",
        )
        .run(row.id),
    ).toThrow(/material_version_content_conflict/);
    x.db.sqlite.prepare('DELETE FROM public_materials WHERE id=?').run(row.id);
    expect(() =>
      x.db.sqlite
        .prepare(
          'INSERT INTO public_materials(id,kind,book,data_json,version,rights_status,active) VALUES(?,?,?,?,?,?,?)',
        )
        .run(
          row.id,
          row.kind,
          row.book,
          JSON.stringify({ ...JSON.parse(row.data_json), summary: 'changed' }),
          row.version,
          'approved',
          1,
        ),
    ).toThrow(/material_version_content_conflict/);
  });
});
