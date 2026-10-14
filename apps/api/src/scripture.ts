import { assetScriptureRows, type AssetCorpus } from './scripture-assets';
import { Hono } from 'hono';
import { z } from 'zod';
import { passageSchema, type Passage } from '@bible/core';
import {
  validateSource,
  isTrustedPrimaryTextSource,
  isTrustedPrimaryCorpus,
  type GroundingSource,
} from '@bible/ai-harness';
import type { AppEnv, Env } from './types';
import { fail } from './http';

export const scripture = new Hono<AppEnv>();
export const SCRIPTURE_NOTICE =
  'World English Bible の英語本文です。出典ファイルの節番号を保持しています。日本語訳や JCB との対応は未検証です。本文の出典確認は、日本語解説の編集・解釈の確認を意味しません。';
export type ScriptureRow = {
  corpus_id: string;
  corpus_version: string;
  edition: string;
  manifest_sha256: string;
  book: string;
  chapter: number;
  verse: number;
  text: string;
};
export function primarySource(row: ScriptureRow): GroundingSource | null {
  const position = { chapter: row.chapter, verse: row.verse };
  const source = {
    id: `${row.corpus_id}:${row.book}:${row.chapter}:${row.verse}`,
    version: row.corpus_version,
    book: row.book,
    start: position,
    end: position,
    kind: 'scripture' as const,
    title: `World English Bible · ${row.book} ${row.chapter}:${row.verse} (English)`,
    text: row.text,
    url: `https://ebible.org/engwebp/${row.book}${String(row.chapter).padStart(row.book === 'PSA' ? 3 : 2, '0')}.htm#V${row.verse}`,
    license: 'public-domain' as const,
    generationAllowed: true,
    visibility: 'public' as const,
    reviewed: false,
    spoilerEnd: position,
    claims: [],
    verification: {
      kind: 'trusted-primary-text' as const,
      corpusId: row.corpus_id,
      edition: row.edition,
      language: 'en' as const,
      manifestSha256: row.manifest_sha256,
      referenceSystem: 'web-protestant' as const,
      referenceAlignment: 'canonical-compatible' as const,
    },
  };
  try {
    validateSource(source);
    return isTrustedPrimaryTextSource(source) ? source : null;
  } catch {
    return null;
  }
}
export const scriptureColumns =
  'v.corpus_id,v.corpus_version,c.edition,c.manifest_sha256,v.book,v.chapter,v.verse,v.text';
export const scriptureJoin = `FROM scripture_verses v JOIN scripture_corpora c ON c.id=v.corpus_id AND c.version=v.corpus_version WHERE c.id='webp' AND c.storage_type='d1' AND c.active=1 AND c.state='ready' AND c.rights_status='approved' AND c.license='public-domain' AND v.alignment='canonical-compatible' AND v.text_status='present'`;
export async function getScriptureSources(env: Env, passage: Passage, snapshotPolicy?: number): Promise<GroundingSource[]> {
  const rows = await env.DB.prepare(
    `WITH verses AS (SELECT ${scriptureColumns} ${scriptureJoin} AND v.book=? AND (v.chapter>? OR(v.chapter=? AND v.verse>=?)) AND(v.chapter<? OR(v.chapter=? AND v.verse<=?)) ORDER BY v.chapter,v.verse LIMIT 48)
 SELECT *,NULL AS asset_index_sha256,NULL AS policy_version FROM verses
 UNION ALL SELECT c.id,c.version,c.edition,c.manifest_sha256,'',0,0,'',c.asset_index_sha256,s.version FROM scripture_corpora c JOIN source_policy_state s ON s.id=1
 WHERE c.id='webp' AND c.storage_type='assets' AND c.active=1 AND c.state='ready' AND c.rights_status='approved' AND c.license='public-domain'`,
  )
    .bind(
      passage.book,
      passage.start.chapter,
      passage.start.chapter,
      passage.start.verse,
      passage.end.chapter,
      passage.end.chapter,
      passage.end.verse,
    )
    .all<ScriptureRow & { asset_index_sha256: string | null; policy_version: number | null }>();
  const asset = rows.results.find((row) => row.chapter === 0);
  let selected: ScriptureRow[] = rows.results;
  if (asset) {
    if(snapshotPolicy !== undefined && asset.policy_version !== snapshotPolicy) fail(409,'source_policy_changed','Scripture policy changed');
    selected = (
      await assetScriptureRows(
        env,
        {
          id: asset.corpus_id,
          version: asset.corpus_version,
          edition: asset.edition,
          manifest_sha256: asset.manifest_sha256,
          asset_index_sha256: asset.asset_index_sha256,
        },
        passage,
        { chapter: passage.start.chapter, verse: passage.start.verse - 1 },
        48,
      )
    ).rows;
    const current = snapshotPolicy === undefined ? await env.DB.prepare(
      'SELECT version FROM source_policy_state WHERE id=1',
    ).first<{ version: number }>() : {version:snapshotPolicy};
    if (current?.version !== asset.policy_version)
      fail(409, 'source_policy_changed', 'Scripture changed while preparing sources. Retry.');
  }
  return selected.flatMap((row) => {
    const source = primarySource(row);
    return source ? [source] : [];
  });
}
const cursorSchema = z
  .object({
    importId: z.string().uuid(),
    rangeIndex: z.number().int().nonnegative(),
    version: z.string().max(100),
    policy: z.number().int().nonnegative(),
    chapter: z.number().int(),
    verse: z.number().int(),
  })
  .strict();
scripture.get('/imports/:id/scripture', async (c) => {
  const params = z
    .object({
      rangeIndex: z.coerce.number().int().min(0).max(19).default(0),
      after: z.string().max(1000).optional(),
    })
    .strict()
    .safeParse(c.req.query());
  if (!params.success) fail(400, 'invalid_query', 'Invalid scripture page query.');
  const { rangeIndex, after } = params.data;
  const imported = await c.env.DB.prepare(
    'SELECT ranges_json FROM imports WHERE id=? AND user_id=?',
  )
    .bind(c.req.param('id'), c.get('user').id)
    .first<{ ranges_json: string }>();
  if (!imported) fail(404, 'not_found', 'Import not found.');
  const selected = passageSchema.safeParse(JSON.parse(imported.ranges_json)[rangeIndex]);
  if (!selected.success) fail(400, 'invalid_range', 'Selected range does not exist.');
  const passage = selected.data;
  const state = await c.env.DB.prepare('SELECT version FROM source_policy_state WHERE id=1').first<{
    version: number;
  }>();
  if (!state) fail(503, 'source_policy_unavailable', 'Source policy is unavailable.');
  const corpus = await c.env.DB.prepare(
    "SELECT id,version,edition,manifest_sha256,manifest_json,storage_type,asset_index_sha256 FROM scripture_corpora WHERE id='webp' AND active=1 AND state='ready' AND rights_status='approved'",
  ).first<{
    id: string;
    version: string;
    edition: string;
    manifest_sha256: string;
    manifest_json: string;
    storage_type: 'd1' | 'assets';
    asset_index_sha256: string | null;
  }>();
  const empty = {
    available: false,
    passage,
    corpus: null,
    items: [],
    nextCursor: null,
    sourcePolicyVersion: state.version,
    noticeJa: SCRIPTURE_NOTICE,
    coverage: 'unavailable',
    omissions: [],
    unversifiedTextIncluded: false,
  };
  if (
    !corpus ||
    !isTrustedPrimaryCorpus({
      corpusId: corpus.id,
      edition: corpus.edition,
      manifestSha256: corpus.manifest_sha256,
      sourceVersion: corpus.version,
    })
  ) {
    if (after) fail(409, 'source_policy_changed', 'Scripture availability changed.');
    return c.json(empty);
  }
  let start = { chapter: passage.start.chapter, verse: passage.start.verse - 1 };
  if (after) {
    let cursor;
    try {
      cursor = cursorSchema.parse(JSON.parse(atob(after)));
    } catch {
      fail(400, 'invalid_cursor', 'Invalid scripture page cursor.');
    }
    if (cursor.importId !== c.req.param('id') || cursor.rangeIndex !== rangeIndex)
      fail(400, 'invalid_cursor', 'Cursor belongs to another reading range.');
    if (cursor.version !== corpus.version || cursor.policy !== state.version)
      fail(409, 'source_policy_changed', 'Scripture changed; reload from the first page.');
    if (
      !passageSchema.safeParse({
        book: passage.book,
        start: { chapter: cursor.chapter, verse: cursor.verse },
        end: { chapter: cursor.chapter, verse: cursor.verse },
      }).success ||
      cursor.chapter * 1000 + cursor.verse < passage.start.chapter * 1000 + passage.start.verse ||
      cursor.chapter * 1000 + cursor.verse > passage.end.chapter * 1000 + passage.end.verse
    )
      fail(400, 'invalid_cursor', 'Cursor is outside this reading range.');
    start = cursor;
  }
  const assetPage =
    corpus.storage_type === 'assets'
      ? await assetScriptureRows(c.env, corpus, passage, start, 101)
      : null;
  const rows = assetPage
    ? { results: assetPage.rows }
    : await c.env.DB.prepare(
        `SELECT ${scriptureColumns} ${scriptureJoin} AND v.book=? AND(v.chapter>? OR(v.chapter=? AND v.verse>?)) AND(v.chapter<? OR(v.chapter=? AND v.verse<=?)) ORDER BY v.chapter,v.verse LIMIT 101`,
      )
        .bind(
          passage.book,
          start.chapter,
          start.chapter,
          start.verse,
          passage.end.chapter,
          passage.end.chapter,
          passage.end.verse,
        )
        .all<ScriptureRow>();
  const items: { id: string; chapter: number; verse: number; text: string }[] = [];
  let bytes = 0;
  for (const row of rows.results.slice(0, 100)) {
    const source = primarySource(row);
    if (!source) return c.json(empty);
    const item = { id: source.id, chapter: row.chapter, verse: row.verse, text: row.text };
    const size = new TextEncoder().encode(JSON.stringify(item)).byteLength;
    if (bytes + size > 120000) break;
    bytes += size;
    items.push(item);
  }
  const manifest = JSON.parse(corpus.manifest_json) as {
    emptyVerses?: { sourceBook: string; sourceChapter: number; sourceVerse: string }[];
    missingCanonicalVerses?: { book: string; chapter: number; verse: number }[];
  };
  const inRange = (book: string, chapter: number, verse: number) =>
    book === passage.book &&
    chapter * 1000 + verse >= passage.start.chapter * 1000 + passage.start.verse &&
    chapter * 1000 + verse <= passage.end.chapter * 1000 + passage.end.verse;
  const omissions = [
    ...(manifest.emptyVerses ?? [])
      .filter((v) => inRange(v.sourceBook, v.sourceChapter, Number(v.sourceVerse)))
      .map((v) => ({
        chapter: v.sourceChapter,
        verse: Number(v.sourceVerse),
        reason: 'source_text_empty',
      })),
    ...(manifest.missingCanonicalVerses ?? [])
      .filter((v) => inRange(v.book, v.chapter, v.verse))
      .map((v) => ({ chapter: v.chapter, verse: v.verse, reason: 'source_reference_missing' })),
  ];
  const current = await c.env.DB.prepare(
    'SELECT version FROM source_policy_state WHERE id=1',
  ).first<{ version: number }>();
  if (current?.version !== state.version)
    fail(409, 'source_policy_changed', 'Scripture changed while loading the page.');
  const last = items.at(-1);
  const nextCursor =
    last && (rows.results.length > items.length || assetPage?.hasMore)
      ? btoa(
          JSON.stringify({
            importId: c.req.param('id'),
            rangeIndex,
            version: corpus.version,
            policy: state.version,
            chapter: last.chapter,
            verse: last.verse,
          }),
        )
      : null;
  return c.json({
    available: true,
    passage,
    corpus: {
      id: corpus.id,
      version: corpus.version,
      edition: corpus.edition,
      language: 'en',
      license: 'public-domain',
      manifestSha256: corpus.manifest_sha256,
      referenceAlignment: 'canonical-compatible',
      editorialReview: 'unreviewed',
    },
    items,
    nextCursor,
    sourcePolicyVersion: state.version,
    noticeJa: SCRIPTURE_NOTICE,
    coverage: 'source-coordinate-subset',
    omissions,
    unversifiedTextIncluded: false,
  });
});
