import { Hono, type Context } from 'hono';
import { cacheKey, sha256, stableJSON, type Passage } from '@bible/core';
import { createSourceOnlyAnswer, PROMPT_VERSION, REGISTRY_VERSION } from '@bible/ai-harness';
import { getSources, sourcePolicyVersion } from './data';
import { getMaterials } from './materials';
import { SCRIPTURE_NOTICE } from './scripture';
import { readingSourceVersion } from './reading-cache';
import { fail, now } from './http';
import type { AppEnv } from './types';
export const reading = new Hono<AppEnv>();
reading.get('/content-manifest', async (c) => {
  const policyVersion = await sourcePolicyVersion(c.env);
  const rows = await c.env.DB.prepare(
    `SELECT id,version,rights_status,active,
    CASE WHEN json_valid(content_json) THEN json_extract(content_json,'$.id') END AS source_id,
    CASE WHEN json_valid(content_json) THEN json_extract(content_json,'$.version') END AS source_version,
    CASE WHEN json_valid(content_json) THEN json_extract(content_json,'$.license') END AS license,
    CASE WHEN json_valid(content_json) THEN json_extract(content_json,'$.visibility') END AS visibility,
    CASE WHEN json_valid(content_json) THEN json_type(content_json,'$.reviewed')='true' ELSE 0 END AS reviewed,
    CASE WHEN json_valid(content_json) THEN json_type(content_json,'$.generationAllowed')='true' ELSE 0 END AS generation_allowed
    FROM public_sources ORDER BY id LIMIT 4097`,
  ).all();
  if (rows.results.length > 4096)
    fail(
      503,
      'manifest_capacity',
      'The catalog requires a newer paginated manifest protocol. Offline grants cannot be renewed.',
    );
  const items = rows.results.map((row) => {
    const consistent = row.source_id === row.id && row.source_version === row.version;
    return {
      id: row.id,
      version: row.version,
      rights_status: row.rights_status,
      active: row.active,
      license:
        consistent &&
        ['public-domain', 'licensed', 'user-provided', 'original-commentary'].includes(
          String(row.license),
        )
          ? row.license
          : 'unknown',
      visibility:
        consistent && ['public', 'private'].includes(String(row.visibility))
          ? row.visibility
          : 'unknown',
      reviewed: consistent && row.reviewed === 1,
      generationAllowed: consistent && row.generation_allowed === 1,
    };
  });
  const materials = await c.env.DB.prepare(
    'SELECT id,version,rights_status,active FROM public_materials ORDER BY id LIMIT 4097',
  ).all();
  if (materials.results.length > 4096)
    fail(503, 'manifest_capacity', 'The material catalog requires a newer manifest protocol.');
  const corpora = await c.env.DB.prepare(
    'SELECT id,version,edition,language,license,manifest_sha256 AS manifestSha256,state,rights_status,active FROM scripture_corpora ORDER BY id,version LIMIT 101',
  ).all();
  if (corpora.results.length > 100)
    fail(
      503,
      'manifest_capacity',
      'The scripture corpus catalog requires a newer manifest protocol.',
    );
  if (policyVersion !== (await sourcePolicyVersion(c.env)))
    fail(409, 'source_policy_changed', 'Content changed while loading the manifest. Retry.');
  const version = await sha256(
    stableJSON({
      policyVersion,
      sources: items,
      materials: materials.results,
      corpora: corpora.results,
    }),
  );
  return c.json({
    version,
    items,
    materials: materials.results,
    corpora: corpora.results,
    checkedAt: now(),
  });
});
reading.get('/imports/:id/reading', async (c) => {
  const row = await c.env.DB.prepare(
    'SELECT ranges_json,translation FROM imports WHERE id=? AND user_id=?',
  )
    .bind(c.req.param('id'), c.get('user').id)
    .first<{ ranges_json: string; translation: string | null }>();
  if (!row) fail(404, 'not_found', 'Import not found');
  const rangeIndex = Number(c.req.query('rangeIndex') ?? 0);
  if (!Number.isSafeInteger(rangeIndex) || rangeIndex < 0)
    fail(400, 'invalid_range', 'Invalid range index');
  const passage = (JSON.parse(row.ranges_json) as Passage[])[rangeIndex];
  if (!passage) fail(400, 'invalid_range', 'Selected range does not exist');
  const spoilers = c.req.query('spoilers') === 'true';
  return publicReading(c, passage, row.translation, spoilers);
});

// Only existing public sources/materials; no imports, account fields, user text or inference.
// Main app and extension share this exact builder and immutable-policy cache.
export async function publicReading(c: Context<AppEnv>, passage: Passage, translation: string | null, spoilers = false): Promise<Response> {
  const policyVersion = await sourcePolicyVersion(c.env);
  // Check the shared immutable-policy cache before loading/validating large public bodies.
  // The owned import lookup above and the epoch recheck below remain mandatory on every hit.
  const sourceVersion = await readingSourceVersion(policyVersion);
  // A fixed public-data summary, no user text/history, no user model preference and no provider call.
  const key = await cacheKey({
    passage,
    translation: translation,
    language: 'ja',
    spoilerAllowed: spoilers,
    provider: 'source-only',
    modelId: c.env.DEFAULT_MODEL_ID,
    modelVersion: REGISTRY_VERSION,
    promptVersion: PROMPT_VERSION,
    settings: { offlinePolicyVersion: 1, referenceNoticeVersion: 1 },
    sourceVersion,
  });
  const cached = await c.env.DB.prepare(
    'SELECT body_json FROM public_cache WHERE cache_key=? AND source_version=? AND expires_at>?',
  )
    .bind(key, sourceVersion, now())
    .first<{ body_json: string }>();
  if (cached) {
    if (policyVersion !== (await sourcePolicyVersion(c.env)))
      fail(409, 'source_policy_changed', 'Content changed. Retry.');
    return c.json({ ...JSON.parse(cached.body_json), checkedAt: now(), cache: 'public-hit' });
  }
  const sources = await getSources(c.env, passage, spoilers, passage, policyVersion);
  const materials = await getMaterials(c.env, passage, spoilers);
  if (policyVersion !== (await sourcePolicyVersion(c.env)))
    fail(409, 'source_policy_changed', 'Content changed while loading reading materials. Retry.');
  const overview = createSourceOnlyAnswer(
    {
      passage,
      translation: translation ?? undefined,
      question: '選択箇所の確認済み資料を示してください。',
      spoilerAllowed: spoilers,
      sources,
      modelId: c.env.DEFAULT_MODEL_ID,
    },
    'public-data-only',
  );
  const offlineEligible =
    overview.citations.length > 0 &&
    overview.citations.every((citation) =>
      sources.some(
        (source) =>
          source.id === citation.sourceId &&
          source.version === citation.version &&
          source.reviewed === true &&
          source.license === 'public-domain',
      ),
    );
  const result = {
    offlineCache: {
      eligible: offlineEligible,
      maxAgeSeconds: offlineEligible ? 86400 : 0,
      reason: offlineEligible
        ? 'reviewed_public_domain_overview'
        : 'no_eligible_public_domain_overview',
      allowedFields: ['overview'],
      dependencies: overview.citations.map((citation) => ({
        id: citation.sourceId,
        version: citation.version,
      })),
      policyVersion: 1,
    },
    passage,
    translation: translation,
    spoilerAllowed: spoilers,
    sourceVersion,
    overview: {
      contentKind: overview.citations.some((citation) =>
        sources.some((source) => source.id === citation.sourceId && source.reviewed === false),
      )
        ? 'literal-primary-text'
        : 'curated-reference',
      noticeJa: overview.citations.some((citation) =>
        sources.some((source) => source.id === citation.sourceId && source.reviewed === false),
      )
        ? SCRIPTURE_NOTICE
        : '確認済みの引用・解説資料です。AIによる回答ではありません。',
      referenceSystem: overview.referenceSystem,
      text: overview.answer,
      claims: overview.claims,
      citations: overview.citations,
      mode: 'source-only',
      modelInvoked: false,
    },
    sources,
    people: materials.filter((card) => card.kind === 'person'),
    places: materials.filter((card) => card.kind === 'place'),
    artworks: materials.filter((card) => card.kind === 'artwork'),
    materialNotice: materials.length
      ? '確認済みの関連資料です。収録内容は一部で、すべての人物・場所・作品を網羅していません。未確認の座標や画像は表示しません。'
      : 'この範囲に対応する確認済みの人物・場所・絵画資料はありません。',
  };
  const serialized = JSON.stringify(result);
  // D1 rows are limited to2MB. Oversized public responses bypass cache persistence.
  if (new TextEncoder().encode(serialized).byteLength <= 1800000)
    await c.env.DB.prepare(
      'INSERT OR REPLACE INTO public_cache(cache_key,source_version,body_json,expires_at) VALUES(?,?,?,?)',
    )
      .bind(key, sourceVersion, serialized, now() + 86400)
      .run();
  if (policyVersion !== (await sourcePolicyVersion(c.env)))
    fail(409, 'source_policy_changed', 'Content changed. Retry.');
  return c.json({ ...result, checkedAt: now(), cache: 'public-miss' });
}
