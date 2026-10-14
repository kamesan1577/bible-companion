import { trustedAssetCorpus, knownPrimaryReference } from './scripture-assets';
import { isTrustedPrimaryCorpus } from '@bible/ai-harness';
import { passageSchema, type Passage } from '@bible/core';
import type { Env } from './types';
import { fail } from './http';
export type HistoricalSource = {
  id: string;
  version: string;
  book: string;
  spoilerEnd: { chapter: number; verse: number };
};
/** Authoritative cited-ID lookup, independent of relevance ranking and generation context caps. */
export async function historicalSources(env: Env, answers: unknown[]): Promise<HistoricalSource[]> {
  const ids = new Set<string>();
  for (const answer of answers) {
    if (!answer || typeof answer !== 'object') continue;
    const citations = (answer as { citations?: unknown }).citations;
    if (!Array.isArray(citations) || citations.length > 64) continue;
    for (const citation of citations) {
      if (
        citation &&
        typeof citation === 'object' &&
        typeof citation.sourceId === 'string' &&
        citation.sourceId.length <= 100
      )
        ids.add(citation.sourceId);
    }
  }
  if (ids.size > 4096)
    fail(
      413,
      'historical_scope_too_large',
      'Use smaller history/export pages. No historical data was truncated.',
    );
  if (!ids.size) return [];
  const before = await env.DB.prepare('SELECT version FROM source_policy_state WHERE id=1').first<{
    version: number;
  }>();
  // Semantic (ID,version) immutability means metadata can validate a previously verified citation without loading every source body.
  const json = "CASE WHEN json_valid(content_json) THEN content_json ELSE '{}' END";
  const rows = await env.DB.prepare(
    `SELECT id,version,book,
 json_extract(${json},'$.id') AS source_id,json_extract(${json},'$.version') AS source_version,json_extract(${json},'$.book') AS source_book,
 json_extract(${json},'$.spoilerEnd.chapter') AS chapter,json_extract(${json},'$.spoilerEnd.verse') AS verse,NULL AS corpus_id,NULL AS edition,NULL AS manifest_sha256,NULL AS asset_index_sha256
 FROM public_sources WHERE id NOT LIKE 'webp:%' AND id NOT LIKE 'material:%' AND active=1 AND rights_status='approved' AND id IN(SELECT value FROM json_each(?))
 AND json_type(${json},'$.reviewed')='true' AND json_type(${json},'$.generationAllowed')='true' AND json_extract(${json},'$.visibility')='public'
 UNION ALL SELECT 'material:'||id,version,book,
 'material:'||json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.id'),json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.version'),json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.spoilerEnd.book'),
 json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.spoilerEnd.chapter'),json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.spoilerEnd.verse'),NULL,NULL,NULL,NULL
 FROM public_materials WHERE active=1 AND rights_status='approved' AND length(CAST(data_json AS BLOB))<=65536 AND json_valid(data_json)
 AND json_type(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.reviewed')='true' AND json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.rightsStatus')='approved' AND 'material:'||id IN(SELECT value FROM json_each(?))
 UNION ALL SELECT v.source_id,v.corpus_version,v.book,
 v.source_id,v.corpus_version,v.book,v.chapter,v.verse,c.id,c.edition,c.manifest_sha256,NULL
 FROM scripture_verses v JOIN scripture_corpora c ON c.id=v.corpus_id AND c.version=v.corpus_version
 WHERE c.id='webp' AND c.storage_type='d1' AND c.state='ready' AND c.active=1 AND c.rights_status='approved' AND c.license='public-domain'
 AND v.alignment='canonical-compatible' AND v.text_status='present'
 AND v.source_id IN(SELECT value FROM json_each(?))
 UNION ALL SELECT '',c.version,'','','','',0,0,c.id,c.edition,c.manifest_sha256,c.asset_index_sha256
 FROM scripture_corpora c WHERE c.id='webp' AND c.storage_type='assets' AND c.state='ready' AND c.active=1 AND c.rights_status='approved' AND c.license='public-domain'`,
  )
    .bind(JSON.stringify([...ids]), JSON.stringify([...ids]), JSON.stringify([...ids]))
    .all<{
      id: string;
      version: string;
      book: string;
      source_id: string;
      source_version: string;
      source_book: string;
      chapter: number;
      verse: number;
      corpus_id: string | null;
      edition: string | null;
      manifest_sha256: string | null;
      asset_index_sha256: string | null;
    }>();
  const after = await env.DB.prepare('SELECT version FROM source_policy_state WHERE id=1').first<{
    version: number;
  }>();
  if (!before || !after || before.version !== after.version)
    fail(409, 'source_policy_changed', 'Sources changed while checking history. Retry.');
  return rows.results.flatMap((row) => {
    if (row.asset_index_sha256) {
      if (
        !trustedAssetCorpus({
          id: row.corpus_id!,
          version: row.version,
          edition: row.edition!,
          manifest_sha256: row.manifest_sha256!,
          asset_index_sha256: row.asset_index_sha256,
        })
      )
        return [];
      return [...ids].flatMap((id) => {
        const m = /^webp:([A-Z0-9]{3}):([1-9][0-9]{0,2}):([1-9][0-9]{0,2})$/.exec(id);
        if (!m || !knownPrimaryReference(m[1], Number(m[2]), Number(m[3]))) return [];
        return [
          {
            id,
            version: row.version,
            book: m[1],
            spoilerEnd: { chapter: Number(m[2]), verse: Number(m[3]) },
          },
        ];
      });
    }
    const end = { chapter: row.chapter, verse: row.verse };
    return (!row.corpus_id ||
      isTrustedPrimaryCorpus({
        corpusId: row.corpus_id,
        edition: row.edition!,
        manifestSha256: row.manifest_sha256!,
        sourceVersion: row.version,
      })) &&
      row.id === row.source_id &&
      row.version === row.source_version &&
      row.book === row.source_book &&
      passageSchema.safeParse({ book: row.book, start: end, end }).success
      ? [{ id: row.id, version: row.version, book: row.book, spoilerEnd: end }]
      : [];
  });
}
export function historicalWithin(sources: HistoricalSource[], passage: Passage, spoilers: boolean) {
  return sources.filter(
    (source) =>
      source.book === passage.book &&
      (spoilers ||
        source.spoilerEnd.chapter * 1000 + source.spoilerEnd.verse <=
          passage.end.chapter * 1000 + passage.end.verse),
  );
}
export function comparisonAnswers(value: unknown): unknown[] {
  if (!value || typeof value !== 'object') return [];
  const results = (value as { results?: unknown }).results;
  return Array.isArray(results)
    ? results.map((row) => (row && typeof row === 'object' ? row.result : undefined))
    : [];
}
