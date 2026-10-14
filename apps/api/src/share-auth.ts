import type { Context } from 'hono';
import type {AppEnv,User} from './types';
import {fail,now} from './http';
import {GROUNDED_POLICY_VERSION} from './answer-mode';
export async function shareAccessUser(c:Context<AppEnv>,hash:string) {
 return c.env.DB.prepare(`SELECT u.id,u.display_name,u.role,u.data_epoch FROM share_ai_access a JOIN users u ON u.id=a.user_id JOIN sessions s ON s.token_hash=a.source_session_hash AND s.user_id=a.user_id WHERE a.token_hash=? AND a.expires_at>? AND s.expires_at>? AND a.data_epoch=u.data_epoch AND json_extract(u.settings_json,'$.shareAiConsent')=1 AND json_extract(u.settings_json,'$.workersAiConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationPolicyVersion')=?`).bind(hash,now(),now(),GROUNDED_POLICY_VERSION).first<User&{data_epoch:number}>();
}
export async function assertShareAccess(c:Context<AppEnv>) {
 const hash=c.get('shareCapability');if(hash&&!await shareAccessUser(c,hash))fail(401,'share_access_expired','アプリで共有画面のAIを有効にしてください。');
}
