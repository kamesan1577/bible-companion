import {describe,it,expect} from 'vitest';
import {app} from '../src/index';import{testEnv,seedUser}from'./helpers/db';
import{MODEL_TERMS_POLICY_VERSION}from'@bible/ai-harness';import{GROUNDED_POLICY_VERSION}from'../src/answer-mode';
async function setup(){
 const env=testEnv();let calls=0;Object.assign(env,{SHARE_AI_ENABLED:'true',AI_ENABLED:'true',CONNECTED_MODELS:'["@cf/google/gemma-4-26b-a4b-it"]',TERMS_REVIEWED_MODELS:'["@cf/google/gemma-4-26b-a4b-it"]',TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,ALLOWED_ANSWER_MODES:'["grounded-generation"]',AI_BUDGET_MODE:'free-provider-hard-stop',WORKERS_AI_ACCOUNT_ID:'a'.repeat(32),AI_FREE_RECEIPT_ID:'share-fixture',AI:{async run(){calls++;return{response:JSON.stringify({status:'answer',claims:[{text:'プリスキラとアキラは神の道をより正確に説明しました。',kind:'fact',sourceId:'act-18-24-26',evidenceQuote:'explained to him the way of God more accurately'}]})};}}});
 const user=await seedUser(env);const request=(path:string,body:unknown,headers=user.headers)=>app.request(path,{method:'POST',headers,body:JSON.stringify(body)},env);
 const consent=()=>request('/v1/me/consents',{workersAi:true,groundedGeneration:{accepted:true,policyVersion:GROUNDED_POLICY_VERSION}});
 const issue=async()=>{await consent();const r=await request('/v1/me/share-access',{enabled:true});expect(r.status).toBe(200);const v=await r.json() as {token:string;ownerId:string;expiresAt:number};return{...v,headers:{Authorization:'Bearer '+v.token,'Content-Type':'application/json'}};};
 const start=async(headers:{Authorization:string;'Content-Type':string})=>{const r=await request('/share/start',{requestId:crypto.randomUUID(),sharedText:'使徒18:24-26'},headers);expect(r.status).toBe(200);return await r.json() as {items:{conversationId:string}[]};};
 return {env,user,request,consent,issue,start,calls:()=>calls};
}
describe('bounded share AI capabilities',()=>{
 it('requires current AI consent and never lets a share token log in to general API',async()=>{
  const x=await setup();expect((await x.request('/v1/me/share-access',{enabled:true})).status).toBe(403);const cap=await x.issue();expect(cap.ownerId).toBe(x.user.id);expect(cap.expiresAt).toBeLessThanOrEqual(Date.now()/1000+86400);
  expect((await app.request('/v1/me',{headers:cap.headers},x.env)).status).toBe(401);
  expect((await x.request('/share/start',{requestId:crypto.randomUUID(),sharedText:'使徒18:24-26'},x.user.headers)).status).toBe(401);
 });
 it('permits only conversations created by that capability and preserves the existing inference guards',async()=>{
  const x=await setup(),a=await x.issue(),b=await x.issue(),reading=await x.start(a.headers),id=reading.items[0].conversationId;
  const question={requestId:crypto.randomUUID(),question:'何をしましたか？',answerMode:'grounded-generation'};
  expect((await x.request('/share/conversations/'+id+'/questions',question,b.headers)).status).toBe(404);expect(x.calls()).toBe(0);
  const response=await x.request('/share/conversations/'+id+'/questions',question,a.headers);expect(response.status).toBe(200);expect(x.calls()).toBe(1);
  expect((await app.request('/share/requests/'+question.requestId,{headers:b.headers},x.env)).status).toBe(404);
  expect((await app.request('/share/requests/'+question.requestId,{headers:a.headers},x.env)).status).toBe(200);
 });
 it('expires on logout, consent withdrawal, account epoch change and capability expiry',async()=>{
  for(const change of ['logout','consent','epoch','expiry']){
   const x=await setup(),cap=await x.issue();
   if(change==='logout')await x.env.DB.prepare('DELETE FROM sessions WHERE user_id=?').bind(x.user.id).run();
   if(change==='consent')await x.env.DB.prepare("UPDATE users SET settings_json=json_set(settings_json,'$.workersAiConsent',0) WHERE id=?").bind(x.user.id).run();
   if(change==='epoch')await x.env.DB.prepare('UPDATE users SET data_epoch=data_epoch+1 WHERE id=?').bind(x.user.id).run();
   if(change==='expiry')await x.env.DB.prepare('UPDATE share_ai_access SET expires_at=1 WHERE user_id=?').bind(x.user.id).run();
   expect((await x.request('/share/start',{requestId:crypto.randomUUID(),sharedText:'使徒18:24-26'},cap.headers)).status).toBe(401);expect(x.calls()).toBe(0);
  }
 });
 it('fails closed without deployment approval before any capability mutation or inference',async()=>{
  const x=await setup();x.env.SHARE_AI_ENABLED='false';
  expect((await x.request('/v1/me/share-access',{enabled:true})).status).toBe(503);
  expect((await x.request('/share/start',{requestId:crypto.randomUUID(),sharedText:'使徒23:1'})).status).toBe(503);
  const count=await x.env.DB.prepare('SELECT COUNT(*) AS n FROM share_ai_access').first<{n:number}>();expect(count?.n).toBe(0);expect(x.calls()).toBe(0);
 });
 it('does not persist shared scripture text and cannot reach developer or account routes',async()=>{
  const x=await setup(),cap=await x.issue();await x.start(cap.headers);
  const imports=await x.env.DB.prepare('SELECT ranges_json,source_url FROM imports WHERE user_id=?').bind(x.user.id).all();expect(JSON.stringify(imports.results)).not.toContain('sharedText');
  expect((await x.request('/share/developer/model-preferences',{modelId:'anything'},cap.headers)).status).toBe(404);
  await x.request('/v1/me/share-access',{enabled:false});expect((await x.request('/share/start',{requestId:crypto.randomUUID(),sharedText:'使徒18:24-26'},cap.headers)).status).toBe(401);
 });
});
