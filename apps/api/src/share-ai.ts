import { Hono } from 'hono';
import { z } from 'zod';
import { parseImport, sha256, stableJSON } from '@bible/core';
import type { AppEnv } from './types';
import { body, fail, now } from './http';
import {
  ensureConsent,
  answerQuestion,
  questionStatus,
  standardExplanation,
  cancelQuestion,
} from './ai';
import { rateLimit } from './budget';
import { GROUNDED_POLICY_VERSION } from './answer-mode';
import { shareAccessUser, shareTokenScope, assertShareAccess } from './share-auth';
export const shareAccess = new Hono<AppEnv>();
function randomToken(prefix: string) {
  return (
    prefix +
    Array.from(crypto.getRandomValues(new Uint8Array(32)))
      .map((x) => x.toString(16).padStart(2, '0'))
      .join('')
  );
}
// Refresh accepts only a share-scoped credential, never a general API session.
export const shareRenewal = new Hono<AppEnv>();
shareRenewal.post('/renew', async (c) => {
  if (c.env.SHARE_AI_ENABLED !== 'true')
    fail(503, 'share_ai_disabled', '共有AIは現在利用できません。');
  const header = c.req.header('Authorization');
  if (!header?.match(/^Bearer bcr1_[a-f0-9]{64}$/))
    fail(401, 'share_refresh_required', 'アプリで共有設定を確認してください。');
  const refreshHash = await sha256(header.slice(7));
  const row = await c.env.DB.prepare(
    'SELECT token_hash,user_id,refresh_expires_at FROM share_ai_access WHERE refresh_hash=? AND refresh_expires_at>?',
  )
    .bind(refreshHash, now())
    .first<{ token_hash: string; user_id: string; refresh_expires_at: number }>();
  if (!row) fail(401, 'share_refresh_expired', 'アプリでログイン状態を確認してください。');
  // Check live parent session, all consents and data epoch even after access expiry.
  const user = await c.env.DB.prepare(
    `SELECT u.id FROM share_ai_access a JOIN users u ON u.id=a.user_id JOIN sessions s ON s.token_hash=a.source_session_hash AND s.user_id=a.user_id WHERE a.token_hash=? AND s.expires_at>? AND a.data_epoch=u.data_epoch AND json_extract(u.settings_json,'$.shareAiConsent')=1 AND json_extract(u.settings_json,'$.workersAiConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationPolicyVersion')=?`,
  )
    .bind(row.token_hash, now(), GROUNDED_POLICY_VERSION)
    .first();
  if (!user)
    fail(
      401,
      'share_refresh_revoked',
      'ログインまたは同意状態が変わりました。アプリで確認してください。',
    );
  await rateLimit(c.env, 'share-renew:' + row.token_hash, 10, 3600);
  const token = randomToken('bcs1_'),
    hash = await sha256(token),
    expiry = Math.min(now() + 86400, row.refresh_expires_at);
  await c.env.DB.batch([
    c.env.DB.prepare(
      'UPDATE share_ai_access SET expires_at=? WHERE token_hash=? AND refresh_hash=? AND refresh_expires_at>?',
    ).bind(expiry, row.token_hash, refreshHash, now()),
    c.env.DB.prepare(
      'INSERT INTO share_ai_tokens(token_hash,access_hash,expires_at) SELECT ?,token_hash,? FROM share_ai_access WHERE token_hash=? AND refresh_hash=? AND refresh_expires_at>?',
    ).bind(hash, expiry, row.token_hash, refreshHash, now()),
  ]);
  if (!(await shareAccessUser(c, row.token_hash)))
    fail(401, 'share_refresh_revoked', 'ログイン状態を確認してください。');
  c.header('Cache-Control', 'private, no-store');
  return c.json({
    token,
    ownerId: row.user_id,
    expiresAt: expiry,
    scopeId: row.token_hash,
    refreshToken: header.slice(7),
    refreshExpiresAt: row.refresh_expires_at,
  });
});
shareAccess.post('/me/share-access', async (c) => {
  if (c.env.SHARE_AI_ENABLED !== 'true')
    fail(503, 'share_ai_disabled', '共有画面のAIは準備中です。アプリで解説を読めます。');
  const v = await body(c, z.object({ enabled: z.boolean() }).strict());
  const owner = c.get('user').id;
  if (!v.enabled) {
    await c.env.DB.batch([
      c.env.DB.prepare(
        "UPDATE users SET settings_json=json_set(settings_json,'$.shareAiConsent',0) WHERE id=?",
      ).bind(owner),
      c.env.DB.prepare('DELETE FROM share_ai_access WHERE user_id=?').bind(owner),
    ]);
    return c.json({ enabled: false });
  }
  await ensureConsent(c.env, owner, 'grounded-generation');
  await rateLimit(c.env, 'share-issue:' + owner, 10, 3600);
  const token =
    'bcs1_' +
    Array.from(crypto.getRandomValues(new Uint8Array(32)))
      .map((x) => x.toString(16).padStart(2, '0'))
      .join('');
  const parent = await c.env.DB.prepare(
    'SELECT expires_at FROM sessions WHERE token_hash=? AND user_id=?',
  )
    .bind(c.get('tokenHash'), owner)
    .first<{ expires_at: number }>();
  if (!parent) fail(401, 'session_expired', 'ログインを再確認してください。');
  const refreshToken = randomToken('bcr1_');
  const hash = await sha256(token),
    expiry = Math.min(now() + 86400, parent.expires_at);
  await c.env.DB.batch([
    c.env.DB.prepare(
      "UPDATE users SET settings_json=json_set(settings_json,'$.shareAiConsent',1) WHERE id=? AND data_epoch=?",
    ).bind(owner, c.get('dataEpoch')),
    c.env.DB.prepare(
      'INSERT INTO share_ai_access(token_hash,user_id,source_session_hash,data_epoch,expires_at,created_at,refresh_hash,refresh_expires_at) SELECT ?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM sessions WHERE token_hash=? AND user_id=? AND expires_at>?) AND EXISTS(SELECT 1 FROM users WHERE id=? AND data_epoch=?)',
    ).bind(
      hash,
      owner,
      c.get('tokenHash'),
      c.get('dataEpoch'),
      expiry,
      now(),
      await sha256(refreshToken),
      parent.expires_at,
      c.get('tokenHash'),
      owner,
      now(),
      owner,
      c.get('dataEpoch'),
    ),
  ]);
  await c.env.DB.prepare(
    'INSERT INTO share_ai_tokens(token_hash,access_hash,expires_at) VALUES(?,?,?)',
  )
    .bind(hash, hash, expiry)
    .run();
  if (!(await shareAccessUser(c, hash)))
    fail(409, 'share_access_changed', 'ログイン状態を再確認してください。');
  c.header('Cache-Control', 'private, no-store');
  return c.json({
    token,
    ownerId: owner,
    expiresAt: expiry,
    scopeId: hash,
    refreshToken,
    refreshExpiresAt: parent.expires_at,
  });
});
export const shareAi = new Hono<AppEnv>();
shareAi.use('*', async (c, next) => {
  if (c.env.SHARE_AI_ENABLED !== 'true')
    fail(503, 'share_ai_disabled', '共有画面のAIは準備中です。');
  const header = c.req.header('Authorization');
  if (!header?.startsWith('Bearer bcs1_') || header.length !== 76)
    fail(401, 'share_access_required', '初回だけ聖書コンパニオンでAIを有効にしてください。');
  const hash = await sha256(header.slice(7));
  const scope = await shareTokenScope(c, hash);
  const user = scope ? await shareAccessUser(c, scope) : null;
  if (!user)
    fail(
      401,
      'share_access_expired',
      '聖書コンパニオンを開いて、共有画面のAIを有効にしてください。',
    );
  const { data_epoch, ...account } = user;
  c.set('user', account);
  c.set('dataEpoch', data_epoch);
  c.set('tokenHash', scope!);
  c.set('shareCapability', scope!);
  await rateLimit(c.env, 'share-user:' + user.id, 30);
  await next();
});
shareAi.post('/start', async (c) => {
  const v = await body(
    c,
    z.object({ requestId: z.string().uuid(), sharedText: z.string().min(1).max(20000) }).strict(),
  );
  let parsed;
  try {
    parsed = parseImport(v.sharedText);
    if (!parsed.ranges.length) {
      const parts = v.sharedText
        .split('\n')
        .filter((x) => x.trim())
        .map((x) => parseImport(x));
      parsed = {
        ...parsed,
        ranges: [
          ...new Map(parts.flatMap((x) => x.ranges).map((x) => [stableJSON(x), x])).values(),
        ],
      };
    }
  } catch {
    fail(400, 'invalid_passage', '章節を読み取れませんでした。');
  }
  if (!parsed.ranges.length || parsed.ranges.length > 20)
    fail(400, 'invalid_passage', '章節を確認してください。');
  const hash = await sha256(stableJSON(v)),
    access = c.get('shareCapability')!,
    owner = c.get('user').id;
  let reading = await c.env.DB.prepare(
    'SELECT id,request_hash,import_id FROM share_ai_readings WHERE access_hash=? AND request_id=?',
  )
    .bind(access, v.requestId)
    .first<{ id: string; request_hash: string; import_id: string }>();
  if (reading && reading.request_hash !== hash)
    fail(409, 'idempotency_conflict', '共有内容が変わりました。');
  if (!reading) {
    const id = crypto.randomUUID(),
      importId = crypto.randomUUID();
    // Canonical references only; never persist the original shared scripture text.
    const statements = [
      c.env.DB.prepare(
        'INSERT INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,translation,source_url,created_at) SELECT ?,?,?,?,?,?,NULL,? WHERE EXISTS(SELECT 1 FROM users WHERE id=? AND data_epoch=?)',
      ).bind(
        importId,
        owner,
        crypto.randomUUID(),
        hash,
        JSON.stringify(parsed.ranges),
        parsed.translation ?? null,
        now(),
        owner,
        c.get('dataEpoch'),
      ),
      c.env.DB.prepare(
        'INSERT INTO share_ai_readings(id,access_hash,request_id,request_hash,import_id) VALUES(?,?,?,?,?)',
      ).bind(id, access, v.requestId, hash, importId),
    ];
    for (const passage of parsed.ranges) {
      const conversation = crypto.randomUUID();
      statements.push(
        c.env.DB.prepare(
          'INSERT INTO conversations(id,user_id,import_id,passage_json,reading_boundary_json,spoiler_allowed,created_at) VALUES(?,?,?,?,?,0,?)',
        ).bind(
          conversation,
          owner,
          importId,
          JSON.stringify(passage),
          JSON.stringify(passage),
          now(),
        ),
        c.env.DB.prepare(
          'INSERT INTO share_ai_conversations(conversation_id,reading_id) VALUES(?,?)',
        ).bind(conversation, id),
      );
    }
    await assertShareAccess(c);
    await c.env.DB.batch(statements);
    reading = { id, request_hash: hash, import_id: importId };
  }
  const results = await c.env.DB.prepare(
    'SELECT c.id,c.passage_json FROM share_ai_conversations sc JOIN conversations c ON c.id=sc.conversation_id AND c.user_id=? WHERE sc.reading_id=? ORDER BY c.created_at,c.rowid',
  )
    .bind(owner, reading.id)
    .all<{ id: string; passage_json: string }>();
  await assertShareAccess(c);
  return c.json({
    ownerId: owner,
    importId: reading.import_id,
    items: results.results.map((r) => ({
      conversationId: r.id,
      passage: JSON.parse(r.passage_json),
    })),
  });
});
shareAi.post('/conversations/:id/explanation', async (c) => {
  const scoped = await c.env.DB.prepare(
    'SELECT sc.conversation_id FROM share_ai_conversations sc JOIN share_ai_readings r ON r.id=sc.reading_id WHERE sc.conversation_id=? AND r.access_hash=?',
  )
    .bind(c.req.param('id'), c.get('shareCapability'))
    .first();
  if (!scoped) fail(404, 'not_found', 'この共有の会話ではありません。');
  const response = await standardExplanation(c);
  await assertShareAccess(c);
  return response;
});
shareAi.post('/conversations/:id/questions', async (c) => {
  const scoped = await c.env.DB.prepare(
    'SELECT sc.conversation_id FROM share_ai_conversations sc JOIN share_ai_readings r ON r.id=sc.reading_id WHERE sc.conversation_id=? AND r.access_hash=?',
  )
    .bind(c.req.param('id'), c.get('shareCapability'))
    .first();
  if (!scoped) fail(404, 'not_found', 'この共有の会話ではありません。');
  const response = await answerQuestion(c);
  await assertShareAccess(c);
  return response;
});

shareAi.get('/requests/:id', async (c) => {
  const scoped = await c.env.DB.prepare(
    'SELECT g.id FROM generation_requests g JOIN share_ai_conversations sc ON sc.conversation_id=g.conversation_id JOIN share_ai_readings r ON r.id=sc.reading_id WHERE g.id=? AND g.user_id=? AND r.access_hash=?',
  )
    .bind(c.req.param('id'), c.get('user').id, c.get('shareCapability'))
    .first();
  if (!scoped) fail(404, 'not_found', 'この共有の質問ではありません。');
  const response = await questionStatus(c);
  await assertShareAccess(c);
  return response;
});

shareAi.delete('/requests/:id', async (c) => {
  const scoped = await c.env.DB.prepare(
    'SELECT g.id FROM generation_requests g JOIN share_ai_conversations sc ON sc.conversation_id=g.conversation_id JOIN share_ai_readings r ON r.id=sc.reading_id WHERE g.id=? AND g.user_id=? AND r.access_hash=?',
  )
    .bind(c.req.param('id'), c.get('user').id, c.get('shareCapability'))
    .first();
  if (!scoped) fail(404, 'not_found', 'この共有の質問ではありません。');
  await assertShareAccess(c);
  return cancelQuestion(c);
});
