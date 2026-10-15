import {describe,it,expect} from 'vitest';
import {app} from '../src/index';import{testEnv,seedUser}from'./helpers/db';
import{MODEL_TERMS_POLICY_VERSION}from'@bible/ai-harness';import{GROUNDED_POLICY_VERSION}from'../src/answer-mode';
async function setup(){
 const env=testEnv();let calls=0;Object.assign(env,{SHARE_AI_ENABLED:'true',AI_ENABLED:'true',CONNECTED_MODELS:'["@cf/google/gemma-4-26b-a4b-it"]',TERMS_REVIEWED_MODELS:'["@cf/google/gemma-4-26b-a4b-it"]',TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,ALLOWED_ANSWER_MODES:'["grounded-generation"]',AI_BUDGET_MODE:'free-provider-hard-stop',WORKERS_AI_ACCOUNT_ID:'a'.repeat(32),AI_FREE_RECEIPT_ID:'share-fixture',AI:{async run(){calls++;return{response:JSON.stringify({status:'answer',claims:[{text:'プリスキラとアキラは神の道をより正確に説明しました。',kind:'fact',sourceId:'act-18-24-26',evidenceQuote:'explained to him the way of God more accurately'}]})};}}});
 const receipt={schemaVersion:1,policyVersion:'workers-ai-free-hard-stop.v1',accountId:'a'.repeat(32),verifiedAt:new Date(Date.now()-60000).toISOString(),expiresAt:new Date(Date.now()+3600000).toISOString(),evidenceRef:'synthetic-share-unit-test-not-provider-evidence',accountPlan:'free',providerRoute:'direct-workers-binding',gatewayCredits:false,paidModels:false,fallbacks:false};
 await env.DB.prepare('INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,1)').bind(env.AI_FREE_RECEIPT_ID,env.WORKERS_AI_ACCOUNT_ID,JSON.stringify(receipt)).run();
 const user=await seedUser(env);const request=(path:string,body:unknown,headers=user.headers)=>app.request(path,{method:'POST',headers,body:JSON.stringify(body)},env);
 const consent=()=>request('/v1/me/consents',{workersAi:true,groundedGeneration:{accepted:true,policyVersion:GROUNDED_POLICY_VERSION}});
 const issue=async()=>{await consent();const r=await request('/v1/me/share-access',{enabled:true});expect(r.status).toBe(200);const v=await r.json() as {token:string;ownerId:string;expiresAt:number};return{...v,headers:{Authorization:'Bearer '+v.token,'Content-Type':'application/json'}};};
 const start=async(headers:{Authorization:string;'Content-Type':string})=>{const r=await request('/share/start',{requestId:crypto.randomUUID(),sharedText:'使徒18:24-26'},headers);expect(r.status).toBe(200);return await r.json() as {items:{conversationId:string}[]};};
 return {env,user,request,consent,issue,start,calls:()=>calls};
}

import {standardKey} from '../src/standard-cache';
import {BIBLE_QUESTIONS,inputForCase} from '../../../packages/ai-harness/fixtures/questions';
import {TestDatabase} from './helpers/db';
import {DatabaseSync} from 'node:sqlite';
import {mkdtempSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
async function secondUser(x:Awaited<ReturnType<typeof setup>>){
 const user=await seedUser(x.env);await x.request('/v1/me/consents',{workersAi:true,groundedGeneration:{accepted:true,policyVersion:GROUNDED_POLICY_VERSION}},user.headers);
 const r=await x.request('/v1/me/share-access',{enabled:true},user.headers);const cap=await r.json() as {token:string};
 return {user,headers:{Authorization:'Bearer '+cap.token,'Content-Type':'application/json'}};
}
async function explain(x:Awaited<ReturnType<typeof setup>>,id:string,headers:{Authorization:string;'Content-Type':string}){
 return x.request('/share/conversations/'+id+'/explanation',{requestId:crypto.randomUUID()},headers);
}
describe('durable public standard explanations',()=>{
 it('reuses across users with zero provider calls and zero budget reservation on hit',async()=>{
  const x=await setup(),a=await x.issue(),one=await x.start(a.headers);const first=await explain(x,one.items[0].conversationId,a.headers);expect(first.status).toBe(200);expect(x.calls()).toBe(1);
  const b=await secondUser(x),two=await x.start(b.headers);const hit=await explain(x,two.items[0].conversationId,b.headers);expect(hit.status).toBe(200);const body=await hit.json() as any;
  expect(body.result.cache).toBe('public-standard-hit');expect(body.result.modelInvoked).toBe(false);expect(body.result.usage.neurons).toBe(0);expect(x.calls()).toBe(1);
  const count=await x.env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations WHERE user_id=?').bind(b.user.id).first<{n:number}>();expect(count?.n).toBe(0);
 });
 it('cannot accept a free question through the standard endpoint or publish private history',async()=>{
  const x=await setup(),a=await x.issue(),r=await x.start(a.headers),id=r.items[0].conversationId;
  expect((await x.request('/share/conversations/'+id+'/explanation',{requestId:crypto.randomUUID(),question:'PRIVATE_CANARY'},a.headers)).status).toBe(400);
  await x.request('/share/conversations/'+id+'/questions',{requestId:crypto.randomUUID(),question:'PRIVATE_CANARY',answerMode:'grounded-generation'},a.headers);
  expect((await x.env.DB.prepare('SELECT COUNT(*) AS n FROM standard_explanations').first<{n:number}>())?.n).toBe(0);
  const response=await explain(x,id,a.headers);expect(response.status).toBe(200);
  const rows=await x.env.DB.prepare('SELECT descriptor_json,result_json FROM standard_explanations').all();expect(JSON.stringify(rows.results)).not.toContain('PRIVATE_CANARY');expect(JSON.stringify(rows.results)).not.toContain(x.user.id);expect(JSON.stringify(rows.results)).not.toContain('budgetPolicy');
 });
 it('deduplicates simultaneous misses across separate users',async()=>{
  const x=await setup(),a=await x.issue(),one=await x.start(a.headers),b=await secondUser(x),two=await x.start(b.headers);let calls=0;let release!:()=>void;let entered!:()=>void;
  const enteredPromise=new Promise<void>(r=>entered=r);const blocked=new Promise<void>(r=>release=r);const original=x.env.AI!.run;
  x.env.AI={async run(...args){calls++;entered();await blocked;return original(...args);}};
  const first=explain(x,one.items[0].conversationId,a.headers);await enteredPromise;const follower=explain(x,two.items[0].conversationId,b.headers);await new Promise(r=>setTimeout(r,50));release();
  const responses=await Promise.all([first,follower]);expect(responses.map(r=>r.status)).toEqual([200,200]);expect(calls).toBe(1);
 });
 it('persists after closing the SQLite connection and recreating Worker bindings',async()=>{
  const x=await setup(),a=await x.issue(),r=await x.start(a.headers),id=r.items[0].conversationId;expect((await explain(x,id,a.headers)).status).toBe(200);
  const dir=mkdtempSync(join(realpathSync(tmpdir()),'standard-cache-'));let reopened:TestDatabase|undefined;
  try{const file=join(dir,'d1.sqlite');(x.env.DB as unknown as TestDatabase).sqlite.prepare('VACUUM INTO ?').run(file);
   reopened=Object.create(TestDatabase.prototype) as TestDatabase;Object.defineProperty(reopened,'sqlite',{value:new DatabaseSync(file)});
   const env={...x.env,DB:reopened as unknown as D1Database,AI:{async run(){throw Error('must not generate after restart');}}};
   const response=await app.request('/share/conversations/'+id+'/explanation',{method:'POST',headers:a.headers,body:JSON.stringify({requestId:crypto.randomUUID()})},env);expect(response.status).toBe(200);expect((await response.json() as any).result.cache).toBe('public-standard-hit');
  }finally{reopened?.sqlite.close();rmSync(dir,{recursive:true,force:true});}
 });
 it('does not store failed generations or create a miss stampede after failure',async()=>{
  const x=await setup(),a=await x.issue(),r=await x.start(a.headers),id=r.items[0].conversationId;let calls=0;x.env.AI={async run(){calls++;throw Error('provider failure');}};
  expect((await explain(x,id,a.headers)).status).toBe(503);expect((await explain(x,id,a.headers)).status).toBe(503);expect(calls).toBe(1);
  const row=await x.env.DB.prepare('SELECT state,result_json FROM standard_explanations').first<{state:string;result_json:string|null}>();expect(row?.state).toBe('failed');expect(row?.result_json).toBeNull();
 });
 it('keys range, translation, language/prompt version, spoiler boundary and fixed settings separately',async()=>{
  const base=inputForCase(BIBLE_QUESTIONS[0]);base.history=[];const a=await standardKey(base,1,false);
  for(const changed of [{...base,translation:base.translation==='WEB'?'JCB':'WEB'},{...base,spoilerAllowed:!base.spoilerAllowed},{...base,settings:{...base.settings,temperature:0.4}},{...base,passage:{...base.passage,end:{...base.passage.end,verse:base.passage.end.verse+1}}}])expect((await standardKey(changed,1,false)).key).not.toBe(a.key);
  expect((await standardKey(base,2,false)).key).not.toBe(a.key);expect((await standardKey(base,1,true)).key).not.toBe(a.key);
  expect(a.json).toContain('"language":"ja"');expect(a.json).toContain('promptVersion');expect(a.json).not.toContain('history');
 });
});
