import { materialGroundingSource } from './material-grounding';
import { getScriptureSources } from './scripture';
import {
  historicalSources,
  historicalWithin,
  comparisonAnswers,
  type HistoricalSource,
} from './history';
import { Hono } from 'hono';
import { z } from 'zod';
import {
  parseImport,
  passageSchema,
  sha256,
  stableJSON,
  withinBoundary,
  containsPassage,
  questionContextWindow,
  type Passage,
} from '@bible/core';
import type { AppEnv, Env } from './types';
import { validateSource, withinSpoilerBoundary, type GroundingSource } from '@bible/ai-harness';
import { body, fail, now } from './http';
export const data = new Hono<AppEnv>();
const uuid = z.string().uuid();
const importSchema = z
  .object({
    idempotencyKey: uuid,
    sharedText: z.string().max(20000).optional(),
    ranges: z.array(passageSchema).min(1).max(20).optional(),
    translation: z
      .string()
      .regex(/^[A-Z0-9-]{1,30}$/)
      .nullable()
      .optional(),
  })
  .strict()
  .refine((v) => v.sharedText !== undefined || v.ranges !== undefined);
data.post('/imports/parse', async (c) => {
  const v = await body(c, z.object({ sharedText: z.string().max(20000) }).strict());
  try {
    return c.json(parseImport(v.sharedText));
  } catch {
    fail(400, 'invalid_passage', 'Check the chapter and verse range');
  }
});
data.post('/imports', async (c) => {
  const v = await body(c, importSchema);
  const user = c.get('user');
  const hash = await sha256(stableJSON(v));
  const existing = await c.env.DB.prepare(
    'SELECT * FROM imports WHERE user_id=? AND idempotency_key=?',
  )
    .bind(user.id, v.idempotencyKey)
    .first<ImportRow>();
  if (existing) {
    if (existing.request_hash !== hash)
      fail(409, 'idempotency_conflict', 'This import ID already belongs to different content');
    return c.json(importOutput(existing));
  }
  let parsed;
  try {
    parsed = v.sharedText ? parseImport(v.sharedText) : null;
  } catch {
    fail(400, 'invalid_passage', 'Check the chapter and verse range');
  }
  const ranges = v.ranges ?? parsed?.ranges ?? [];
  if (!ranges.length)
    fail(
      400,
      'passage_required',
      'Confirm the passage before syncing. Keep the original text on the device.',
    );
  const id = crypto.randomUUID();
  // Raw copyrighted shared text is deliberately not persisted; rights policy is unresolved.
  await c.env.DB.prepare(
    'INSERT OR IGNORE INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,translation,source_url,created_at) SELECT ?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM users WHERE id=? AND data_epoch=?)',
  )
    .bind(
      id,
      user.id,
      v.idempotencyKey,
      hash,
      JSON.stringify(ranges),
      v.translation !== undefined ? v.translation : (parsed?.translation ?? null),
      parsed?.sourceUrl ?? null,
      now(),
      user.id,
      c.get('dataEpoch'),
    )
    .run();
  const row = await c.env.DB.prepare('SELECT * FROM imports WHERE user_id=? AND idempotency_key=?')
    .bind(user.id, v.idempotencyKey)
    .first<ImportRow>();
  if (!row || row.request_hash !== hash)
    fail(409, 'idempotency_conflict', 'This import ID already belongs to different content');
  return c.json(importOutput(row), row.id === id ? 201 : 200);
});
type ImportRow = {
  id: string;
  idempotency_key: string;
  request_hash: string;
  ranges_json: string;
  translation: string | null;
  source_url: string | null;
  created_at: number;
};
export function importOutput(r: ImportRow) {
  return {
    id: r.id,
    idempotencyKey: r.idempotency_key,
    ranges: JSON.parse(r.ranges_json),
    translation: r.translation,
    sourceUrl: r.source_url,
    createdAt: r.created_at,
  };
}
data.get('/imports', async (c) => {
  let cursor = { createdAt: Number.MAX_SAFE_INTEGER, id: '~' };
  if (c.req.query('before')) {
    try {
      const parsed = z
        .object({ createdAt: z.number().int().nonnegative(), id: uuid })
        .strict()
        .parse(JSON.parse(atob(c.req.query('before')!)));
      cursor = parsed;
    } catch {
      fail(400, 'invalid_cursor', 'Invalid page cursor');
    }
  }
  const result = await c.env.DB.prepare(
    'SELECT * FROM imports WHERE user_id=? AND (created_at<? OR (created_at=? AND id<?)) ORDER BY created_at DESC,id DESC LIMIT 51',
  )
    .bind(c.get('user').id, cursor.createdAt, cursor.createdAt, cursor.id)
    .all<ImportRow>();
  const rows = result.results.slice(0, 50);
  const last = rows.at(-1);
  return c.json({
    items: rows.map(importOutput),
    nextCursor:
      result.results.length > 50 && last
        ? btoa(JSON.stringify({ createdAt: last.created_at, id: last.id }))
        : null,
  });
});
data.get('/imports/:id', async (c) => {
  const r = await c.env.DB.prepare('SELECT * FROM imports WHERE id=? AND user_id=?')
    .bind(c.req.param('id'), c.get('user').id)
    .first<ImportRow>();
  if (!r) fail(404, 'not_found', 'Import not found');
  return c.json(importOutput(r));
});
data.delete('/imports/:id', async (c) => {
  const r = await c.env.DB.prepare('DELETE FROM imports WHERE id=? AND user_id=? RETURNING id')
    .bind(c.req.param('id'), c.get('user').id)
    .first();
  if (!r) fail(404, 'not_found', 'Import not found');
  return c.body(null, 204);
});
data.post('/conversations', async (c) => {
  const v = await body(
    c,
    z
      .object({
        importId: uuid,
        rangeIndex: z.number().int().min(0).max(19).default(0),
        passage: passageSchema.optional(),
        spoilerAllowed: z.boolean().default(false),
      })
      .strict(),
  );
  const r = await c.env.DB.prepare('SELECT ranges_json FROM imports WHERE id=? AND user_id=?')
    .bind(v.importId, c.get('user').id)
    .first<{ ranges_json: string }>();
  if (!r) fail(404, 'not_found', 'Import not found');
  const readingBoundary = (JSON.parse(r.ranges_json) as Passage[])[v.rangeIndex];
  if (!readingBoundary) fail(400, 'invalid_range', 'Selected range does not exist');
  const passage = v.passage ?? readingBoundary;
  if (!containsPassage(readingBoundary, passage))
    fail(
      400,
      'target_outside_reading_range',
      'Question target must be inside the selected reading range',
    );
  const id = crypto.randomUUID();
  const inserted = await c.env.DB.prepare(
    'INSERT INTO conversations(id,user_id,import_id,passage_json,reading_boundary_json,spoiler_allowed,created_at) SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM users WHERE id=? AND data_epoch=?) AND EXISTS(SELECT 1 FROM imports WHERE id=? AND user_id=?) RETURNING id',
  )
    .bind(
      id,
      c.get('user').id,
      v.importId,
      JSON.stringify(passage),
      JSON.stringify(readingBoundary),
      v.spoilerAllowed ? 1 : 0,
      now(),
      c.get('user').id,
      c.get('dataEpoch'),
      v.importId,
      c.get('user').id,
    )
    .first();
  if (!inserted)
    fail(409, 'reading_data_changed', 'Reading data changed while creating the conversation.');
  return c.json(
    {
      id,
      importId: v.importId,
      passage,
      readingBoundary,
      spoilerAllowed: v.spoilerAllowed,
      createdAt: now(),
    },
    201,
  );
});
export type ConversationRow = {
  id: string;
  user_id: string;
  import_id: string;
  passage_json: string;
  reading_boundary_json: string | null;
  translation?: string | null;
  spoiler_allowed: number;
  created_at: number;
};
export async function getConversation(
  env: Env,
  userId: string,
  id: string,
): Promise<ConversationRow> {
  const row = await env.DB.prepare(
    'SELECT c.*,i.translation FROM conversations c JOIN imports i ON i.id=c.import_id AND i.user_id=c.user_id WHERE c.id=? AND c.user_id=?',
  )
    .bind(id, userId)
    .first<ConversationRow>();
  if (!row) fail(404, 'not_found', 'Conversation not found');
  return row;
}
data.get('/conversations', async (c) => {
  const query = z
    .object({ importId: z.string().uuid().optional(), before: z.string().max(2000).optional() })
    .strict()
    .safeParse(c.req.query());
  if (!query.success) fail(400, 'invalid_query', 'Invalid conversation page parameters');
  const importId = query.data.importId ?? null;
  if (
    importId &&
    !(await c.env.DB.prepare('SELECT id FROM imports WHERE id=? AND user_id=?')
      .bind(importId, c.get('user').id)
      .first())
  )
    fail(404, 'not_found', 'Import not found');
  let cursor = { createdAt: Number.MAX_SAFE_INTEGER, id: '~' };
  if (query.data.before) {
    try {
      cursor = z
        .object({
          createdAt: z.number().int().nonnegative().safe(),
          id: uuid,
          importId: z.literal(importId),
        })
        .strict()
        .parse(JSON.parse(atob(query.data.before)));
    } catch {
      fail(400, 'invalid_cursor', 'Cursor does not match this conversation list');
    }
  }
  const result = await c.env.DB.prepare(
    `SELECT c.*,
    (SELECT COUNT(*) FROM messages m WHERE m.conversation_id=c.id AND m.user_id=c.user_id) AS message_count,
    (SELECT MAX(created_at) FROM messages m WHERE m.conversation_id=c.id AND m.user_id=c.user_id) AS last_message_at
    FROM conversations c WHERE c.user_id=? AND (? IS NULL OR c.import_id=?) AND (c.created_at<? OR (c.created_at=? AND c.id<?)) ORDER BY c.created_at DESC,c.id DESC LIMIT 51`,
  )
    .bind(c.get('user').id, importId, importId, cursor.createdAt, cursor.createdAt, cursor.id)
    .all<ConversationRow & { message_count: number; last_message_at: number | null }>();
  const rows = result.results.slice(0, 50),
    last = rows.at(-1);
  return c.json({
    items: rows.map((r) => ({
      id: r.id,
      importId: r.import_id,
      passage: JSON.parse(r.passage_json),
      readingBoundary: readingBoundaryOf(r),
      spoilerAllowed: !!r.spoiler_allowed,
      createdAt: r.created_at,
      messageCount: r.message_count,
      lastMessageAt: r.last_message_at,
    })),
    nextCursor:
      result.results.length > 50 && last
        ? btoa(JSON.stringify({ createdAt: last.created_at, id: last.id, importId }))
        : null,
  });
});
data.get('/conversations/:id', async (c) => {
  const r = await getConversation(c.env, c.get('user').id, c.req.param('id'));
  let before = { created_at: Number.MAX_SAFE_INTEGER, rowid: Number.MAX_SAFE_INTEGER };
  if (c.req.query('beforeMessageId')) {
    const cursor = await c.env.DB.prepare(
      'SELECT created_at,rowid FROM messages WHERE id=? AND conversation_id=? AND user_id=?',
    )
      .bind(c.req.query('beforeMessageId')!, r.id, c.get('user').id)
      .first<{ created_at: number; rowid: number }>();
    if (!cursor) fail(400, 'invalid_cursor', 'Message cursor does not belong to this conversation');
    before = cursor;
  }
  const policyVersion = await sourcePolicyVersion(c.env);
  const candidates = await c.env.DB.prepare(
    'SELECT rowid,id,length(CAST(content_json AS BLOB))+512 AS raw_bytes FROM messages WHERE conversation_id=? AND user_id=? AND (created_at<? OR (created_at=? AND rowid<?)) ORDER BY created_at DESC,rowid DESC LIMIT 51',
  )
    .bind(r.id, c.get('user').id, before.created_at, before.created_at, before.rowid)
    .all<{ rowid: number; id: string; raw_bytes: number }>();
  const selected: number[] = [];
  let selectedBytes = 0;
  for (const candidate of candidates.results.slice(0, 50)) {
    if (candidate.raw_bytes > 950000) {
      if (!selected.length)
        fail(
          413,
          'message_too_large',
          'A saved message exceeds the supported page bound. No text was truncated.',
        );
      break;
    }
    if (selectedBytes + candidate.raw_bytes > 950000) break;
    selected.push(candidate.rowid);
    selectedBytes += candidate.raw_bytes;
  }
  const messages = selected.length
    ? await c.env.DB.prepare(
        'SELECT id,role,content_json,created_at FROM messages WHERE conversation_id=? AND user_id=? AND rowid IN(SELECT value FROM json_each(?)) ORDER BY created_at,rowid',
      )
        .bind(r.id, c.get('user').id, JSON.stringify(selected))
        .all<{ id: string; role: string; content_json: string; created_at: number }>()
    : { results: [] };
  const page = messages.results;
  const sources = historicalWithin(
    await historicalSources(
      c.env,
      page.filter((m) => m.role === 'assistant').map((m) => JSON.parse(m.content_json)),
    ),
    readingBoundaryOf(r),
    !!r.spoiler_allowed,
  );
  if (policyVersion !== (await sourcePolicyVersion(c.env)))
    fail(409, 'source_policy_changed', 'Sources changed while loading history. Retry.');
  const current = await getConversation(c.env, c.get('user').id, r.id);
  if (current.spoiler_allowed !== r.spoiler_allowed)
    fail(
      409,
      'conversation_policy_changed',
      'Conversation spoiler setting changed. Reload history.',
    );
  return c.json({
    sourcePolicyVersion: policyVersion,
    id: r.id,
    importId: r.import_id,
    passage: JSON.parse(r.passage_json),
    readingBoundary: readingBoundaryOf(r),
    spoilerAllowed: !!r.spoiler_allowed,
    createdAt: r.created_at,
    nextMessageCursor: candidates.results.length > selected.length ? (page[0]?.id ?? null) : null,
    messages: page.map((m) => {
      const content = JSON.parse(m.content_json);
      return {
        id: m.id,
        role: m.role,
        content:
          m.role === 'assistant' && !canDisplayAnswer(content, sources, !!r.spoiler_allowed)
            ? { hidden: true, reason: 'source_or_spoiler_policy_changed' }
            : content,
        createdAt: m.created_at,
      };
    }),
  });
});
data.patch('/conversations/:id', async (c) => {
  const v = await body(c, z.object({ spoilerAllowed: z.boolean() }).strict());
  await getConversation(c.env, c.get('user').id, c.req.param('id'));
  await c.env.DB.prepare('UPDATE conversations SET spoiler_allowed=? WHERE id=? AND user_id=?')
    .bind(v.spoilerAllowed ? 1 : 0, c.req.param('id'), c.get('user').id)
    .run();
  return c.json({ spoilerAllowed: v.spoilerAllowed });
});
data.delete('/conversations/:id', async (c) => {
  const r = await c.env.DB.prepare(
    'DELETE FROM conversations WHERE id=? AND user_id=? RETURNING id',
  )
    .bind(c.req.param('id'), c.get('user').id)
    .first();
  if (!r) fail(404, 'not_found', 'Conversation not found');
  return c.body(null, 204);
});
data.get('/me/export', async (c) => {
  const id = c.get('user').id;
  const before = await c.env.DB.prepare(
    'SELECT export_epoch,display_name,role FROM users WHERE id=?',
  )
    .bind(id)
    .first<{ export_epoch: number; display_name: string; role: string }>();
  const size = await c.env.DB.prepare(
    `SELECT
    (SELECT COUNT(*) FROM imports WHERE user_id=?)+(SELECT COUNT(*) FROM conversations WHERE user_id=?)+(SELECT COUNT(*) FROM messages WHERE user_id=?)+(SELECT COUNT(*) FROM comparison_jobs WHERE user_id=?) AS rows,
    COALESCE((SELECT SUM(length(CAST(ranges_json AS BLOB))) FROM imports WHERE user_id=?),0)+COALESCE((SELECT SUM(length(CAST(content_json AS BLOB))) FROM messages WHERE user_id=?),0)+COALESCE((SELECT SUM(length(CAST(metrics_json AS BLOB))) FROM comparison_jobs WHERE user_id=?),0) AS bytes`,
  )
    .bind(id, id, id, id, id, id, id)
    .first<{ rows: number; bytes: number }>();
  if (!size || size.rows > 1000 || size.bytes > 1048576)
    fail(
      413,
      'export_requires_pagination',
      'Use the bounded export snapshot and page endpoints for this account.',
    );
  const policyBefore = await sourcePolicyVersion(c.env);
  const [imports, conversations, messages, comparisons, preferences, settings] = await Promise.all([
    c.env.DB.prepare('SELECT * FROM imports WHERE user_id=? ORDER BY created_at,id')
      .bind(id)
      .all<ImportRow>(),
    c.env.DB.prepare(
      'SELECT id,import_id,passage_json,reading_boundary_json,spoiler_allowed,created_at FROM conversations WHERE user_id=? ORDER BY created_at,id',
    )
      .bind(id)
      .all<ConversationRow>(),
    c.env.DB.prepare(
      'SELECT id,conversation_id,role,content_json,created_at FROM messages WHERE user_id=? ORDER BY created_at,rowid',
    )
      .bind(id)
      .all<{
        id: string;
        conversation_id: string;
        role: string;
        content_json: string;
        created_at: number;
      }>(),
    c.env.DB.prepare(
      'SELECT id,status,saved,metrics_json,created_at FROM comparison_jobs WHERE user_id=? ORDER BY created_at,id',
    )
      .bind(id)
      .all<{
        id: string;
        status: string;
        saved: number;
        metrics_json: string | null;
        created_at: number;
      }>(),
    c.env.DB.prepare('SELECT model_id,settings_json,version FROM model_preferences WHERE user_id=?')
      .bind(id)
      .first<{ model_id: string; settings_json: string; version: number }>(),
    c.env.DB.prepare('SELECT settings_json FROM users WHERE id=?')
      .bind(id)
      .first<{ settings_json: string }>(),
  ]);
  const historical = await historicalSources(c.env, [
    ...messages.results
      .filter((row) => row.role === 'assistant')
      .map((row) => JSON.parse(row.content_json)),
    ...comparisons.results.flatMap((row) =>
      row.saved && row.metrics_json ? comparisonAnswers(JSON.parse(row.metrics_json)) : [],
    ),
  ]);
  const conversationById = new Map(conversations.results.map((row) => [row.id, row]));
  const projectedMessages = await Promise.all(
    messages.results.map(async (row) => {
      const content = JSON.parse(row.content_json);
      const conversation = conversationById.get(row.conversation_id);
      const allowed =
        row.role !== 'assistant' ||
        (conversation &&
          canDisplayAnswer(
            content,
            historicalWithin(
              historical,
              readingBoundaryOf(conversation),
              !!conversation.spoiler_allowed,
            ),
            !!conversation.spoiler_allowed,
          ));
      return {
        id: row.id,
        conversationId: row.conversation_id,
        role: row.role,
        content: allowed ? content : { hidden: true, reason: 'source_or_spoiler_policy_changed' },
        createdAt: row.created_at,
      };
    }),
  );
  const projectedComparisons = await Promise.all(
    comparisons.results.map(async (row) => ({
      id: row.id,
      status: row.status,
      saved: !!row.saved,
      data: row.metrics_json
        ? row.saved
          ? await projectSavedComparison(c.env, JSON.parse(row.metrics_json), historical)
          : JSON.parse(row.metrics_json)
        : null,
      createdAt: row.created_at,
    })),
  );
  const after = await c.env.DB.prepare('SELECT export_epoch FROM users WHERE id=?')
    .bind(id)
    .first<{ export_epoch: number }>();
  if (
    !before ||
    !after ||
    before.export_epoch !== after.export_epoch ||
    policyBefore !== (await sourcePolicyVersion(c.env))
  )
    fail(409, 'export_changed', 'Reading data changed during export. Restart the export.');
  c.header('Content-Disposition', 'attachment; filename="bible-companion-export.json"');
  return c.json({
    version: 1,
    exportedAt: new Date().toISOString(),
    user: { id, display_name: before.display_name, role: before.role },
    settings: JSON.parse(settings?.settings_json ?? '{}'),
    imports: imports.results.map(importOutput),
    conversations: conversations.results.map((row) => ({
      id: row.id,
      importId: row.import_id,
      passage: JSON.parse(row.passage_json),
      readingBoundary: readingBoundaryOf(row),
      spoilerAllowed: !!row.spoiler_allowed,
      createdAt: row.created_at,
    })),
    messages: projectedMessages,
    comparisons: projectedComparisons,
    modelPreference: preferences
      ? {
          modelId: preferences.model_id,
          settings: JSON.parse(preferences.settings_json),
          version: preferences.version,
        }
      : null,
  });
});
data.get('/sources', async (c) => {
  let p: Passage;
  try {
    p = passageSchema.parse(JSON.parse(c.req.query('passage') ?? 'null'));
  } catch {
    fail(400, 'invalid_passage', 'Provide a canonical passage');
  }
  return c.json({
    version: 'initial-1',
    items: await getSources(c.env, p, c.req.query('spoilers') === 'true'),
  });
});
export async function getSources(
  env: Env,
  passage: Passage,
  spoilers = false,
  target: Passage = passage,
  snapshotPolicy?: number,
  includeMaterials = false,
  earlierBackground = false,
): Promise<GroundingSource[]> {
  const rows = await env.DB.prepare(
    `WITH candidates AS (
      SELECT *,CASE WHEN start_chapter*1000+start_verse<=? AND end_chapter*1000+end_verse>=? THEN 0 ELSE 1 END AS priority
      FROM public_sources WHERE id NOT LIKE 'webp:%' AND id NOT LIKE 'material:%' AND book=? AND active=1 AND rights_status='approved' AND length(CAST(content_json AS BLOB))<=65536 AND start_chapter<=?
      ORDER BY priority,start_chapter DESC,start_verse DESC,id LIMIT 64
    ), bounded AS (
      SELECT *,SUM(length(CAST(content_json AS BLOB))) OVER(ORDER BY priority,start_chapter DESC,start_verse DESC,id) AS body_bytes FROM candidates
    ), source_rows AS (
      SELECT id,book,start_chapter,start_verse,end_chapter,end_verse,content_json,version,NULL AS material_json FROM bounded WHERE body_bytes<=1048576 ORDER BY priority,start_chapter DESC,start_verse DESC,id
    ), material_candidates AS (
      SELECT id,book,version,data_json,CASE WHEN EXISTS(SELECT 1 FROM json_each(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.passages') p WHERE json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.start.chapter')*1000+json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.start.verse')<=? AND json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.end.chapter')*1000+json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.end.verse')>=?) THEN 0 ELSE 1 END AS priority
      FROM public_materials WHERE ?=1 AND book=? AND active=1 AND rights_status='approved' AND length(CAST(data_json AS BLOB))<=65536 AND json_valid(data_json)
      AND json_type(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.reviewed')='true' AND json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.rightsStatus')='approved'
      AND (?=1 OR json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.spoilerEnd.chapter')*1000+json_extract(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.spoilerEnd.verse')<=?)
      AND EXISTS(SELECT 1 FROM json_each(CASE WHEN json_valid(data_json) THEN data_json ELSE '{}' END,'$.passages') p WHERE json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.start.chapter')*1000+json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.start.verse')<=? AND json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.end.chapter')*1000+json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.end.verse')>=?)
      ORDER BY priority,id LIMIT 8
    ) SELECT * FROM source_rows UNION ALL SELECT id,book,0,0,0,0,'',version,data_json FROM material_candidates`,
  )
    .bind(
      target.end.chapter * 1000 + target.end.verse,
      target.start.chapter * 1000 + target.start.verse,
      passage.book,
      spoilers ? 150 : passage.end.chapter,
      target.end.chapter * 1000 + target.end.verse,
      target.start.chapter * 1000 + target.start.verse,
      includeMaterials ? 1 : 0,
      passage.book,
      spoilers ? 1 : 0,
      passage.end.chapter * 1000 + passage.end.verse,
      passage.end.chapter * 1000 + passage.end.verse,
      passage.start.chapter * 1000 + passage.start.verse,
    )
    .all<{
      id: string;
      book: string;
      start_chapter: number;
      start_verse: number;
      end_chapter: number;
      end_verse: number;
      content_json: string;
      version: string;
      material_json: string | null;
    }>();
  const sources: GroundingSource[] = [];
  const materialSources: GroundingSource[] = [];
  let returnedBytes = 0;
  for (const row of rows.results) {
    if (row.material_json) {
      const source = materialGroundingSource(
        { ...row, material_json: row.material_json },
        passage,
        spoilers,
      );
      if (source) materialSources.push(source);
      continue;
    }
    try {
      const source: unknown = JSON.parse(row.content_json);
      validateSource(source);
      if (
        source.id !== row.id ||
        source.book !== row.book ||
        source.version !== row.version ||
        source.visibility !== 'public' ||
        source.reviewed !== true ||
        source.generationAllowed !== true
      )
        continue;
      if (!withinSpoilerBoundary(source, passage, spoilers)) continue;
      if (
        source.start.chapter !== row.start_chapter ||
        source.start.verse !== row.start_verse ||
        source.end.chapter !== row.end_chapter ||
        source.end.verse !== row.end_verse
      )
        continue;
      const bytes = new TextEncoder().encode(JSON.stringify(source)).length;
      if (returnedBytes + bytes > 1048576) break;
      returnedBytes += bytes;
      sources.push(source);
    } catch {
      /* Invalid ingestion metadata fails closed and cannot leak through the direct source API. */
    }
  }
  const window = questionContextWindow(passage, target, earlierBackground);
  // Fetch the selected verses independently: the older-window storage page is capped at 48.
  // Preserve selection first, then add earlier evidence for why/intent questions.
  const [selected, background] = earlierBackground ? await Promise.all([
    getScriptureSources(env, target, snapshotPolicy),
    getScriptureSources(env, window, snapshotPolicy),
  ]) : [[], await getScriptureSources(env, window, snapshotPolicy)];
  const primary = [...new Map([...selected, ...background].map(source => [source.id, source])).values()];
  return primary.length
    ? [...sources.slice(0, 16 - materialSources.length), ...materialSources, ...primary].slice(
        0,
        64,
      )
    : [...sources.slice(0, 64 - materialSources.length), ...materialSources];
}

/** Historical answers must not bypass a later rights revocation, correction, or spoiler toggle. */
export function canDisplayAnswer(
  answer: unknown,
  sources: readonly { id: string; version: string }[],
  spoilerAllowed: boolean,
  policyVersion?: number,
): boolean {
  if (!answer || typeof answer !== 'object') return false;
  const a = answer as {
    spoilerAllowed?: boolean;
    sourcePolicyVersion?: number;
    citations?: { sourceId: string; version: string }[];
  };
  if (!spoilerAllowed && a.spoilerAllowed) return false;
  // Global epochs guard publication atomically. Historical visibility follows cited versions,
  // so an unrelated catalog edit does not erase still-valid answers.
  if (
    !Array.isArray(a.citations) ||
    a.citations.length > 64 ||
    a.citations.some(
      (c) =>
        !c ||
        typeof c.sourceId !== 'string' ||
        typeof c.version !== 'string' ||
        c.sourceId.length > 100 ||
        c.version.length > 100,
    )
  )
    return false;
  const versions = new Map(sources.map((s) => [s.id, s.version]));
  return a.citations.every((c) => versions.get(c.sourceId) === c.version);
}

export function readingBoundaryOf(row: {
  reading_boundary_json?: string | null;
  passage_json: string;
}): Passage {
  return JSON.parse(row.reading_boundary_json ?? row.passage_json);
}

export async function sourcePolicyVersion(env: Env): Promise<number> {
  const row = await env.DB.prepare('SELECT version FROM source_policy_state WHERE id=1').first<{
    version: number;
  }>();
  if (!row) fail(503, 'source_policy_unavailable', 'Source policy state is unavailable');
  return row.version;
}
export async function sourceSnapshot(
  env: Env,
  passage: Passage,
  spoilers = false,
  target: Passage = passage,
  earlierBackground = false,
) {
  const version = await sourcePolicyVersion(env);
  const sources = await getSources(
    env,
    passage,
    spoilers,
    target,
    version,
    true,
    earlierBackground,
  );
  if (version !== (await sourcePolicyVersion(env)))
    fail(409, 'source_policy_changed', 'Source policy changed while preparing the request. Retry.');
  return { version, sources };
}

export async function projectSavedComparison(
  env: Env,
  value: unknown,
  available?: HistoricalSource[],
): Promise<unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return { hidden: true, reason: 'source_provenance_unavailable' };
  const saved = value as {
    questions?: unknown[];
    results?: unknown[];
    sourcePolicyVersion?: number;
  };
  if (!Array.isArray(saved.questions) || !Array.isArray(saved.results))
    return { hidden: true, reason: 'source_provenance_unavailable' };
  const historical = available ?? (await historicalSources(env, comparisonAnswers(saved)));
  const results = await Promise.all(
    saved.results.map(async (item) => {
      if (!item || typeof item !== 'object')
        return { hidden: true, reason: 'source_provenance_unavailable' };
      const row = item as { questionIndex: number; modelIndex: number; result: unknown };
      const question = saved.questions![row.questionIndex] as
        { passage?: unknown; spoilerAllowed?: boolean } | undefined;
      const passage = passageSchema.safeParse(question?.passage);
      const sources = passage.success
        ? historicalWithin(historical, passage.data, question?.spoilerAllowed === true)
        : [];
      return {
        ...row,
        result:
          passage.success &&
          canDisplayAnswer(row.result, sources, question?.spoilerAllowed === true)
            ? row.result
            : { hidden: true, reason: 'source_or_spoiler_policy_changed' },
      };
    }),
  );
  return { ...saved, results };
}
