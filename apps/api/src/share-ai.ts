import {Hono} from 'hono';import {z} from 'zod';
import {parseImport,sha256,stableJSON} from '@bible/core';
import type {AppEnv} from './types';import {body,fail,now} from './http';
import {ensureConsent,answerQuestion,questionStatus} from './ai';import {rateLimit} from './budget';
import {shareAccessUser,assertShareAccess} from './share-auth';
export const shareAccess=new Hono<AppEnv>();
shareAccess.post('/me/share-access',async c=>{
 if(c.env.SHARE_AI_ENABLED !== 'true') fail(503,'share_ai_disabled','共有画面のAIは準備中です。アプリで解説を読めます。');
 const v=await body(c,z.object({enabled:z.boolean()}).strict());const owner=c.get('user').id;
 if(!v.enabled){await c.env.DB.batch([c.env.DB.prepare("UPDATE users SET settings_json=json_set(settings_json,'$.shareAiConsent',0) WHERE id=?").bind(owner),c.env.DB.prepare('DELETE FROM share_ai_access WHERE user_id=?').bind(owner)]);return c.json({enabled:false});}
 await ensureConsent(c.env,owner,'grounded-generation');
 await rateLimit(c.env,'share-issue:'+owner,10,3600);
 const token='bcs1_'+Array.from(crypto.getRandomValues(new Uint8Array(32))).map(x=>x.toString(16).padStart(2,'0')).join('');
 const parent=await c.env.DB.prepare('SELECT expires_at FROM sessions WHERE token_hash=? AND user_id=?').bind(c.get('tokenHash'),owner).first<{expires_at:number}>();
 if(!parent)fail(401,'session_expired','ログインを再確認してください。');
 const hash=await sha256(token),expiry=Math.min(now()+86400,parent.expires_at);
 await c.env.DB.batch([
 c.env.DB.prepare("UPDATE users SET settings_json=json_set(settings_json,'$.shareAiConsent',1) WHERE id=? AND data_epoch=?").bind(owner,c.get('dataEpoch')),
 c.env.DB.prepare('INSERT INTO share_ai_access(token_hash,user_id,source_session_hash,data_epoch,expires_at,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM sessions WHERE token_hash=? AND user_id=? AND expires_at>?) AND EXISTS(SELECT 1 FROM users WHERE id=? AND data_epoch=?)').bind(hash,owner,c.get('tokenHash'),c.get('dataEpoch'),expiry,now(),c.get('tokenHash'),owner,now(),owner,c.get('dataEpoch'))]);
 if(!await shareAccessUser(c,hash))fail(409,'share_access_changed','ログイン状態を再確認してください。');
 return c.json({token,ownerId:owner,expiresAt:expiry});
});
export const shareAi=new Hono<AppEnv>();
shareAi.use('*',async(c,next)=>{
 if(c.env.SHARE_AI_ENABLED !== 'true') fail(503,'share_ai_disabled','共有画面のAIは準備中です。');
 const header=c.req.header('Authorization');if(!header?.startsWith('Bearer bcs1_')||header.length!==76)fail(401,'share_access_required','初回だけ聖書コンパニオンでAIを有効にしてください。');
 const hash=await sha256(header.slice(7));const user=await shareAccessUser(c,hash);if(!user)fail(401,'share_access_expired','聖書コンパニオンを開いて、共有画面のAIを有効にしてください。');
 const {data_epoch,...account}=user;c.set('user',account);c.set('dataEpoch',data_epoch);c.set('tokenHash',hash);c.set('shareCapability',hash);
 await rateLimit(c.env,'share-user:'+user.id,30);await next();
});
shareAi.post('/start',async c=>{
 const v=await body(c,z.object({requestId:z.string().uuid(),sharedText:z.string().min(1).max(20000)}).strict());
 let parsed;try{parsed=parseImport(v.sharedText);if(!parsed.ranges.length){const parts=v.sharedText.split('\n').filter(x=>x.trim()).map(x=>parseImport(x));parsed={...parsed,ranges:[...new Map(parts.flatMap(x=>x.ranges).map(x=>[stableJSON(x),x])).values()]};}}catch{fail(400,'invalid_passage','章節を読み取れませんでした。');}
 if(!parsed.ranges.length||parsed.ranges.length>20)fail(400,'invalid_passage','章節を確認してください。');
 const hash=await sha256(stableJSON(v)),access=c.get('shareCapability')!,owner=c.get('user').id;
 let reading=await c.env.DB.prepare('SELECT id,request_hash,import_id FROM share_ai_readings WHERE access_hash=? AND request_id=?').bind(access,v.requestId).first<{id:string;request_hash:string;import_id:string}>();
 if(reading&&reading.request_hash!==hash)fail(409,'idempotency_conflict','共有内容が変わりました。');
 if(!reading){
 const id=crypto.randomUUID(),importId=crypto.randomUUID();
 // Canonical references only; never persist the original shared scripture text.
 const statements=[c.env.DB.prepare('INSERT INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,translation,source_url,created_at) SELECT ?,?,?,?,?,?,NULL,? WHERE EXISTS(SELECT 1 FROM users WHERE id=? AND data_epoch=?)').bind(importId,owner,crypto.randomUUID(),hash,JSON.stringify(parsed.ranges),parsed.translation??null,now(),owner,c.get('dataEpoch')),c.env.DB.prepare('INSERT INTO share_ai_readings(id,access_hash,request_id,request_hash,import_id) VALUES(?,?,?,?,?)').bind(id,access,v.requestId,hash,importId)];
 for(const passage of parsed.ranges){const conversation=crypto.randomUUID();statements.push(c.env.DB.prepare('INSERT INTO conversations(id,user_id,import_id,passage_json,reading_boundary_json,spoiler_allowed,created_at) VALUES(?,?,?,?,?,0,?)').bind(conversation,owner,importId,JSON.stringify(passage),JSON.stringify(passage),now()),c.env.DB.prepare('INSERT INTO share_ai_conversations(conversation_id,reading_id) VALUES(?,?)').bind(conversation,id));}
 await assertShareAccess(c);await c.env.DB.batch(statements);reading={id,request_hash:hash,import_id:importId};
 }
 const results=await c.env.DB.prepare('SELECT c.id,c.passage_json FROM share_ai_conversations sc JOIN conversations c ON c.id=sc.conversation_id AND c.user_id=? WHERE sc.reading_id=? ORDER BY c.created_at,c.rowid').bind(owner,reading.id).all<{id:string;passage_json:string}>();
 await assertShareAccess(c);return c.json({ownerId:owner,importId:reading.import_id,items:results.results.map(r=>({conversationId:r.id,passage:JSON.parse(r.passage_json)}))});
});
shareAi.post('/conversations/:id/questions',async c=>{
 const scoped=await c.env.DB.prepare('SELECT sc.conversation_id FROM share_ai_conversations sc JOIN share_ai_readings r ON r.id=sc.reading_id WHERE sc.conversation_id=? AND r.access_hash=?').bind(c.req.param('id'),c.get('shareCapability')).first();
 if(!scoped)fail(404,'not_found','この共有の会話ではありません。');
 const response=await answerQuestion(c);await assertShareAccess(c);return response;
});

shareAi.get('/requests/:id',async c=>{
 const scoped=await c.env.DB.prepare('SELECT g.id FROM generation_requests g JOIN share_ai_conversations sc ON sc.conversation_id=g.conversation_id JOIN share_ai_readings r ON r.id=sc.reading_id WHERE g.id=? AND g.user_id=? AND r.access_hash=?').bind(c.req.param('id'),c.get('user').id,c.get('shareCapability')).first();
 if(!scoped)fail(404,'not_found','この共有の質問ではありません。');
 const response=await questionStatus(c);await assertShareAccess(c);return response;
});
