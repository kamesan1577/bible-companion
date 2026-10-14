import {
  historicalSources,
  historicalWithin,
  comparisonAnswers,
  type HistoricalSource,
} from './history';
import { Hono } from 'hono';
import { z } from 'zod';
import { body, fail, now } from './http';
import type { AppEnv, Env } from './types';
import {
  canDisplayAnswer,
  readingBoundaryOf,
  projectSavedComparison,
  sourcePolicyVersion,
} from './data';
export const exportsApi = new Hono<AppEnv>();
const sections = ['imports', 'conversations', 'messages', 'comparisons'] as const;
const tables = {
  imports: 'imports',
  conversations: 'conversations',
  messages: 'messages',
  comparisons: 'comparison_jobs',
} as const;
type Section = (typeof sections)[number];
type Snapshot = {
  id: string;
  user_id: string;
  export_epoch: number;
  data_epoch: number;
  source_policy_version: number;
  upper_rows_json: string;
  created_at: number;
  expires_at: number;
};
async function assertCurrent(env: Env, snapshot: Snapshot) {
  const user = await env.DB.prepare('SELECT export_epoch,data_epoch FROM users WHERE id=?')
    .bind(snapshot.user_id)
    .first<{ export_epoch: number; data_epoch: number }>();
  if (
    !user ||
    user.export_epoch !== snapshot.export_epoch ||
    user.data_epoch !== snapshot.data_epoch ||
    snapshot.source_policy_version !== (await sourcePolicyVersion(env))
  )
    fail(
      409,
      'export_changed',
      'Data or source policy changed. Discard the incomplete export and start a new snapshot.',
    );
  if (snapshot.expires_at <= now())
    fail(409, 'export_expired', 'Export snapshot expired. Start a new snapshot.');
}
exportsApi.post('/me/export/snapshots', async (c) => {
  await body(c, z.object({}).strict());
  const userId = c.get('user').id;
  const state = await c.env.DB.prepare(
    `SELECT export_epoch,data_epoch,settings_json,display_name,role,
 (SELECT COALESCE(MAX(rowid),0) FROM imports WHERE user_id=users.id) AS imports,
 (SELECT COALESCE(MAX(rowid),0) FROM conversations WHERE user_id=users.id) AS conversations,
 (SELECT COALESCE(MAX(rowid),0) FROM messages WHERE user_id=users.id) AS messages,
 (SELECT COALESCE(MAX(rowid),0) FROM comparison_jobs WHERE user_id=users.id) AS comparisons,
 (SELECT version FROM source_policy_state WHERE id=1) AS policy FROM users WHERE id=?`,
  )
    .bind(userId)
    .first<Record<string, number | string>>();
  if (!state) fail(401, 'unauthenticated', 'Authentication is required');
  const upper = Object.fromEntries(sections.map((section) => [section, state[section]]));
  const snapshot: Snapshot = {
    id: crypto.randomUUID(),
    user_id: userId,
    export_epoch: Number(state.export_epoch),
    data_epoch: Number(state.data_epoch),
    source_policy_version: Number(state.policy),
    upper_rows_json: JSON.stringify(upper),
    created_at: now(),
    expires_at: now() + 900,
  };
  const preference = await c.env.DB.prepare(
    'SELECT model_id,settings_json,version FROM model_preferences WHERE user_id=?',
  )
    .bind(userId)
    .first<{ model_id: string; settings_json: string; version: number }>();
  await assertCurrent(c.env, snapshot);
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM export_snapshots WHERE user_id=?').bind(userId),
    c.env.DB.prepare(
      'INSERT INTO export_snapshots(id,user_id,export_epoch,data_epoch,source_policy_version,upper_rows_json,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)',
    ).bind(
      snapshot.id,
      userId,
      snapshot.export_epoch,
      snapshot.data_epoch,
      snapshot.source_policy_version,
      snapshot.upper_rows_json,
      snapshot.created_at,
      snapshot.expires_at,
    ),
  ]);
  return c.json(
    {
      version: 1,
      snapshotId: snapshot.id,
      createdAt: snapshot.created_at,
      expiresAt: snapshot.expires_at,
      sections,
      maxPageBytes: 1048576,
      maxPageItems: 25,
      user: { id: userId, display_name: String(state.display_name), role: String(state.role) },
      settings: JSON.parse(String(state.settings_json)),
      modelPreference: preference
        ? {
            modelId: preference.model_id,
            settings: JSON.parse(preference.settings_json),
            version: preference.version,
          }
        : null,
      consistency: 'restart-on-any-private-write-or-source-policy-change',
    },
    201,
  );
});
exportsApi.get('/me/export/pages', async (c) => {
  const parsed = z
    .object({
      snapshotId: z.string().uuid(),
      section: z.enum(sections),
      cursor: z.string().max(2000).optional(),
    })
    .safeParse(c.req.query());
  if (!parsed.success) fail(400, 'invalid_export_page', 'A snapshot ID and section are required');
  const { snapshotId, section } = parsed.data;
  const snapshot = await c.env.DB.prepare('SELECT * FROM export_snapshots WHERE id=? AND user_id=?')
    .bind(snapshotId, c.get('user').id)
    .first<Snapshot>();
  if (!snapshot) fail(404, 'not_found', 'Export snapshot not found');
  let after = 0;
  if (parsed.data.cursor) {
    try {
      const cursor = z
        .object({
          snapshotId: z.literal(snapshotId),
          section: z.literal(section),
          after: z.number().int().nonnegative().safe(),
        })
        .strict()
        .parse(JSON.parse(atob(parsed.data.cursor)));
      after = cursor.after;
    } catch {
      fail(400, 'invalid_cursor', 'Export cursor does not match this snapshot and section');
    }
  }
  await assertCurrent(c.env, snapshot);
  const upper = JSON.parse(snapshot.upper_rows_json)[section] as number;
  // Read only lengths/identities before loading private bodies;26 near-2MB rows must not enter one isolate.
  const sizeExpression = {
    imports: 'length(CAST(ranges_json AS BLOB))+COALESCE(length(CAST(source_url AS BLOB)),0)+512',
    conversations:
      'length(CAST(passage_json AS BLOB))+COALESCE(length(CAST(reading_boundary_json AS BLOB)),0)+512',
    messages: 'length(CAST(content_json AS BLOB))+512',
    comparisons: 'COALESCE(length(CAST(metrics_json AS BLOB)),0)+512',
  }[section];
  const candidates = await c.env.DB.prepare(
    `SELECT rowid AS export_rowid,${sizeExpression} AS raw_bytes FROM ${tables[section]} WHERE user_id=? AND rowid>? AND rowid<=? ORDER BY rowid LIMIT 26`,
  )
    .bind(snapshot.user_id, after, upper)
    .all<{ export_rowid: number; raw_bytes: number }>();
  const selected: number[] = [];
  let loadedBytes = 0;
  for (const candidate of candidates.results.slice(0, 25)) {
    if (candidate.raw_bytes > 1000000) {
      if (!selected.length)
        fail(
          413,
          'export_entity_too_large',
          'An export entity exceeds the supported per-item size. No data was truncated.',
        );
      break;
    }
    if (loadedBytes + candidate.raw_bytes > 1000000) break;
    selected.push(candidate.export_rowid);
    loadedBytes += candidate.raw_bytes;
  }
  const rows = selected.length
    ? await c.env.DB.prepare(
        `SELECT rowid AS export_rowid,* FROM ${tables[section]} WHERE user_id=? AND rowid IN(SELECT value FROM json_each(?)) ORDER BY rowid`,
      )
        .bind(snapshot.user_id, JSON.stringify(selected))
        .all<Record<string, unknown>>()
    : { results: [] };
  const historical = await historicalSources(
    c.env,
    rows.results.flatMap((row) =>
      section === 'messages' && row.role === 'assistant'
        ? [JSON.parse(String(row.content_json))]
        : section === 'comparisons' && row.saved && row.metrics_json
          ? comparisonAnswers(JSON.parse(String(row.metrics_json)))
          : [],
    ),
  );
  const items: unknown[] = [];
  let bytes = 0,
    last = after;
  for (const row of rows.results.slice(0, 25)) {
    const item = await projectExportRow(c.env, section, row, snapshot.user_id, historical);
    const length = new TextEncoder().encode(JSON.stringify(item)).length;
    if (length > 1000000)
      fail(
        413,
        'export_entity_too_large',
        'An export entity exceeds the supported per-item size. No data was truncated.',
      );
    if (bytes + length > 1000000) break;
    items.push(item);
    bytes += length;
    last = Number(row.export_rowid);
  }
  await assertCurrent(c.env, snapshot);
  const hasMore = candidates.results.some((row) => Number(row.export_rowid) > last);
  return c.json({
    version: 1,
    snapshotId,
    section,
    items,
    nextCursor: hasMore ? btoa(JSON.stringify({ snapshotId, section, after: last })) : null,
  });
});
async function projectExportRow(
  env: Env,
  section: Section,
  row: Record<string, unknown>,
  userId: string,
  historical: HistoricalSource[],
): Promise<unknown> {
  const common = { id: row.id, createdAt: row.created_at };
  if (section === 'imports')
    return {
      ...common,
      idempotencyKey: row.idempotency_key,
      ranges: JSON.parse(String(row.ranges_json)),
      translation: row.translation,
      sourceUrl: row.source_url,
    };
  if (section === 'conversations')
    return {
      ...common,
      importId: row.import_id,
      passage: JSON.parse(String(row.passage_json)),
      readingBoundary: JSON.parse(String(row.reading_boundary_json ?? row.passage_json)),
      spoilerAllowed: !!row.spoiler_allowed,
    };
  if (section === 'comparisons')
    return {
      ...common,
      status: row.status,
      saved: !!row.saved,
      data: row.metrics_json
        ? row.saved
          ? await projectSavedComparison(env, JSON.parse(String(row.metrics_json)), historical)
          : JSON.parse(String(row.metrics_json))
        : null,
    };
  const content = JSON.parse(String(row.content_json));
  let visible = row.role !== 'assistant';
  if (!visible) {
    const conversation = await env.DB.prepare(
      'SELECT passage_json,reading_boundary_json,spoiler_allowed FROM conversations WHERE id=? AND user_id=?',
    )
      .bind(row.conversation_id, userId)
      .first<{
        passage_json: string;
        reading_boundary_json: string | null;
        spoiler_allowed: number;
      }>();
    visible =
      !!conversation &&
      canDisplayAnswer(
        content,
        historicalWithin(
          historical,
          readingBoundaryOf(conversation),
          !!conversation.spoiler_allowed,
        ),
        !!conversation.spoiler_allowed,
      );
  }
  return {
    ...common,
    conversationId: row.conversation_id,
    role: row.role,
    content: visible ? content : { hidden: true, reason: 'source_or_spoiler_policy_changed' },
  };
}
