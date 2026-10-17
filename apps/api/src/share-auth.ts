import type { Context } from 'hono';
import type { AppEnv, User } from './types';
import { fail, now } from './http';
import { GROUNDED_POLICY_VERSION } from './answer-mode';
export async function shareTokenScope(c: Context<AppEnv>, hash: string): Promise<string | null> {
  const token = await c.env.DB.prepare(
    'SELECT access_hash FROM share_ai_tokens WHERE token_hash=? AND expires_at>?',
  )
    .bind(hash, now())
    .first<{ access_hash: string }>();
  if (token) return token.access_hash;
  // Old installations keep their original limited token until its original expiry.
  const legacy = await c.env.DB.prepare(
    'SELECT token_hash FROM share_ai_access WHERE token_hash=? AND refresh_hash IS NULL AND expires_at>?',
  )
    .bind(hash, now())
    .first<{ token_hash: string }>();
  return legacy?.token_hash ?? null;
}
export async function shareAccessUser(c: Context<AppEnv>, hash: string) {
  return c.env.DB.prepare(
    `SELECT u.id,u.display_name,u.role,u.data_epoch FROM share_ai_access a JOIN users u ON u.id=a.user_id JOIN sessions s ON s.token_hash=a.source_session_hash AND s.user_id=a.user_id WHERE a.token_hash=? AND a.expires_at>? AND s.expires_at>? AND a.data_epoch=u.data_epoch AND json_extract(u.settings_json,'$.shareAiConsent')=1 AND json_extract(u.settings_json,'$.workersAiConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationPolicyVersion')=?`,
  )
    .bind(hash, now(), now(), GROUNDED_POLICY_VERSION)
    .first<User & { data_epoch: number }>();
}
export async function assertShareAccess(c: Context<AppEnv>) {
  const hash = c.get('shareCapability');
  if (hash && !(await shareAccessUser(c, hash)))
    fail(401, 'share_access_expired', 'アプリで共有画面のAIを有効にしてください。');
}
