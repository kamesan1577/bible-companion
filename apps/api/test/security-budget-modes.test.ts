import {it,expect,describe} from 'vitest';
import {writeFileSync} from 'node:fs';
import {app} from '../src/index';
import {TestDatabase,testEnv,seedUser} from './helpers/db';
import {seedAssetCorpus,realAssetBinding} from './helpers/scripture-assets';
import {DEFAULT_MODEL_ID,MODEL_TERMS_POLICY_VERSION} from '@bible/ai-harness';
import {FREE_HARD_STOP_POLICY_VERSION} from '../src/budget';
import {GROUNDED_POLICY_VERSION} from '../src/answer-mode';
async function fixture(promptSpecific=false){
 const db=new TestDatabase(),env=testEnv(db),user=await seedUser(env,crypto.randomUUID(),'owner');let calls=0;
 Object.assign(env,{AI_ENABLED:'true',CONNECTED_MODELS:JSON.stringify([DEFAULT_MODEL_ID]),TERMS_REVIEWED_MODELS:JSON.stringify([DEFAULT_MODEL_ID]),TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,ALLOWED_ANSWER_MODES:JSON.stringify(['reviewed-claim-selection','grounded-generation']),AI_BUDGET_MODE:'free-provider-hard-stop',WORKERS_AI_ACCOUNT_ID:'a'.repeat(32),AI_FREE_RECEIPT_ID:'synthetic-security-receipt',AI:{async run(_model:string,inputs:Record<string,unknown>){calls++;if(promptSpecific){const messages=inputs.messages as {content:string}[],source=JSON.parse(messages[1].content).sources[0];return {response:JSON.stringify(source?{status:'answer',claims:[{text:source.text.slice(0,150),kind:'fact',sourceId:source.id,evidenceQuote:source.text.slice(0,150)}]}:{status:'insufficient',claims:[]})};}return {response:JSON.stringify({status:'answer',claims:[{text:'創世記の冒頭では、神が天と地を創造したと記されています。',kind:'fact',sourceId:'webp:GEN:1:1',evidenceQuote:'In the beginning, God created the heavens and the earth.'}]})};}}});
 const receipt={schemaVersion:1,policyVersion:FREE_HARD_STOP_POLICY_VERSION,accountId:env.WORKERS_AI_ACCOUNT_ID,verifiedAt:new Date(Date.now()-60000).toISOString(),expiresAt:new Date(Date.now()+3600000).toISOString(),evidenceRef:'synthetic-security-test-not-a-real-account-verification',accountPlan:'free',providerRoute:'direct-workers-binding',gatewayCredits:false,paidModels:false,fallbacks:false};
 await env.DB.prepare('INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,1)').bind(env.AI_FREE_RECEIPT_ID,env.WORKERS_AI_ACCOUNT_ID,JSON.stringify(receipt)).run();
 await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind(JSON.stringify({workersAiConsent:true,groundedGenerationConsent:true,groundedGenerationPolicyVersion:GROUNDED_POLICY_VERSION}),user.id).run();
 seedAssetCorpus(db);env.SCRIPTURE_ASSETS=realAssetBinding();
 const passage={book:'GEN',start:{chapter:1,verse:1},end:{chapter:1,verse:3}},post=(path:string,value:unknown)=>app.request('/v1'+path,{method:'POST',headers:user.headers,body:JSON.stringify(value)},env);
 const imported=await(await post('/imports',{idempotencyKey:crypto.randomUUID(),ranges:[passage]})).json() as {id:string};const chat=await(await post('/conversations',{importId:imported.id})).json() as {id:string};
 return {db,env,user,post,passage,chat,calls:()=>calls,ask:()=>post(`/conversations/${chat.id}/questions`,{requestId:crypto.randomUUID(),question:'この箇所を説明してください',answerMode:'grounded-generation'})};
}
function pauseDispatch(db:TestDatabase,comparison:boolean){let entered!:()=>void,resume!:()=>void,paused=false;const reached=new Promise<void>(r=>entered=r),gate=new Promise<void>(r=>resume=r),original=db.prepare.bind(db);db.prepare=(sql:string)=>{const statement=original(sql);if(sql.startsWith(comparison?'UPDATE comparison_trials SET dispatched=1':'UPDATE generation_requests SET updated_at=')&&sql.includes('ai_free_account_receipts')){const bind=statement.bind.bind(statement);statement.bind=(...params:unknown[])=>{const bound=bind(...params),first=bound.first.bind(bound);bound.first=async<T=Record<string,unknown>>(column?:string):Promise<T|null>=>{if(!paused){paused=true;entered();await gate;}return first<T>(column);};return bound;};}return statement;};return {reached,resume};}

describe('independent security review: alternative allowance and grounded consent',()=>{
 for(const comparison of [false,true])it.each(['receipt-revoked','grounded-consent-revoked','all-consent-revoked'])('blocks '+(comparison?'comparison':'question')+' after %s before dispatch',async mutation=>{
  const f=await fixture();let start:()=>Promise<Response>|Response=f.ask;
  if(comparison){const plan={requestId:crypto.randomUUID(),models:[{modelId:DEFAULT_MODEL_ID,answerMode:'grounded-generation'}],questions:[{passage:f.passage,question:'この箇所を説明してください'}]};const preview=await(await f.post('/developer/comparisons/plan',plan)).json() as {confirmationHash:string};expect((await f.post('/developer/comparisons',{plan,confirmationHash:preview.confirmationHash})).status).toBe(202);start=()=>f.post(`/developer/comparisons/${plan.requestId}/steps`,{plan,confirmationHash:preview.confirmationHash,trialIndex:0});}
  const gate=pauseDispatch(f.db,comparison),pending=start();await gate.reached;
  try{if(mutation==='receipt-revoked')await f.env.DB.prepare('UPDATE ai_free_account_receipts SET revoked_at=1').run();else await f.env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind(JSON.stringify({workersAiConsent:mutation!=='all-consent-revoked',groundedGenerationConsent:false,groundedGenerationPolicyVersion:GROUNDED_POLICY_VERSION}),f.user.id).run();}finally{gate.resume();}
  expect((await pending).status).toBeGreaterThanOrEqual(400);expect(f.calls()).toBe(0);expect(await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:0});
 });
 it('can reach experimental grounded output from real primary text with synthetic authority, while retaining unverified semantics',async()=>{
  const f=await fixture();const response=await f.ask();const body=await response.json() as any;expect(response.status,JSON.stringify(body)).toBe(200);expect(f.calls()).toBe(1);
  expect(body.result.mode).toBe('grounded-generation');expect(body.result.validation.semanticGrounding).toBe('unverified');expect(body.result.citations[0].sourceId).toBe('webp:GEN:1:1');expect(body.result.answer).toContain('創世記');
  expect(JSON.stringify(body)).not.toContain('synthetic-security-test-not-a-real-account-verification');expect(JSON.stringify(body)).not.toContain('a'.repeat(32));
 });
 it('receipt evidence cannot be edited, deleted, or unrevoked',async()=>{
  const f=await fixture();expect(()=>f.db.sqlite.exec("UPDATE ai_free_account_receipts SET receipt_json='{}'")).toThrow();expect(()=>f.db.sqlite.exec('DELETE FROM ai_free_account_receipts')).toThrow();f.db.sqlite.exec('UPDATE ai_free_account_receipts SET revoked_at=1');expect(()=>f.db.sqlite.exec('UPDATE ai_free_account_receipts SET revoked_at=NULL')).toThrow();
 });
});

it('profiles a free-mode20-trial plan with10distinct real-asset passages and exact dispatch estimate',async()=>{
 const f=await fixture(true),second='@cf/meta/llama-3.2-1b-instruct';f.env.CONNECTED_MODELS=JSON.stringify([DEFAULT_MODEL_ID,second]);f.env.TERMS_REVIEWED_MODELS=f.env.CONNECTED_MODELS;expect(f.env.DAILY_USER_BUDGET).toBe('2000');
 const plan={requestId:crypto.randomUUID(),models:[DEFAULT_MODEL_ID,second].map(modelId=>({modelId,answerMode:'grounded-generation',settings:{maxOutputTokens:512}})),questions:Array.from({length:10},(_,i)=>({passage:{book:'GEN',start:{chapter:i+1,verse:1},end:{chapter:i+1,verse:3}},question:'この箇所を説明してください'})),saveResults:true};
 const prepare=f.db.prepare.bind(f.db);let enabled=false,statements=0;f.db.prepare=(sql:string)=>{if(enabled)statements++;return prepare(sql);};const measurements:{name:string;status:number;statements:number;cpuMs:number;wallMs:number;responseBytes:number}[]=[];
 async function measured(name:string,run:()=>Promise<Response>|Response){statements=0;enabled=true;const cpu=process.cpuUsage(),start=performance.now();const response=await run(),text=await response.text(),used=process.cpuUsage(cpu);enabled=false;measurements.push({name,status:response.status,statements,cpuMs:(used.user+used.system)/1000,wallMs:performance.now()-start,responseBytes:new TextEncoder().encode(text).length});expect(statements,name).toBeLessThanOrEqual(50);return {response,value:JSON.parse(text)};}
 const preview=await measured('free-plan20-distinct-assets',()=>f.post('/developer/comparisons/plan',plan));expect(preview.response.status,JSON.stringify(preview.value)).toBe(200);expect(preview.value.budgetBoundVerified).toBe(false);
 const start=await measured('free-start20-distinct-assets',()=>f.post('/developer/comparisons',{plan,confirmationHash:preview.value.confirmationHash}));expect(start.response.status,JSON.stringify(start.value)).toBe(202);expect(f.calls()).toBe(0);
 expect(preview.value.reservedBudgetUnits).toBeLessThanOrEqual(2000);
 let terminal:any;
 for(let trialIndex=0;trialIndex<20;trialIndex++){
  const step=await measured('free-step-'+trialIndex,()=>f.post(`/developer/comparisons/${plan.requestId}/steps`,{plan,confirmationHash:preview.value.confirmationHash,trialIndex}));expect(step.response.status,JSON.stringify(step.value)).toBe(200);expect(f.calls()).toBe(trialIndex+1);expect(step.value.result.mode).toBe('grounded-generation');expect(step.value.result.modelInvoked).toBe(true);terminal=step.value.state;
 }
 expect(terminal.status).toBe('complete');expect(terminal.completedCount).toBe(20);expect(terminal.nextTrialIndex).toBeNull();
 const replay=await measured('free-completed-step-replay',()=>f.post(`/developer/comparisons/${plan.requestId}/steps`,{plan,confirmationHash:preview.value.confirmationHash,trialIndex:0}));expect(replay.response.status).toBe(200);expect(replay.value.replayed).toBe(true);expect(f.calls()).toBe(20);
 expect(await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:preview.value.reservedBudgetUnits});
 if(process.env.BIBLE_WRITE_PROFILE==='1')writeFileSync(new URL('../../../../bible-security-review/free-comparison-profile.json',import.meta.url),JSON.stringify({measuredAt:new Date().toISOString(),scope:'Single-sample local Node/SQLite, real pinned assets, synthetic Free-account receipt and mocked provider. CPU diagnostic only, not Worker compliance or live account evidence.',reservedEstimate:preview.value.reservedBudgetUnits,userBudget:2000,completedTrials:20,providerCalls:f.calls(),measurements},null,2)+'\n');
},30000);
