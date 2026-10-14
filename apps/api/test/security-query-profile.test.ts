import {it,expect} from 'vitest';
import {writeFileSync} from 'node:fs';
import {app} from '../src/index';
import {PRICING_VERSION,MODEL_TERMS_POLICY_VERSION} from '@bible/ai-harness';
import {TestDatabase,testEnv,seedUser} from './helpers/db';

class ProfileDatabase extends TestDatabase {
 enabled=false; statements:string[]=[]; maxParams=0;
 override prepare(sql:string){
  if(this.enabled)this.statements.push(sql);
  const statement=super.prepare(sql),bind=statement.bind.bind(statement);
  statement.bind=(...params:unknown[])=>{if(this.enabled)this.maxParams=Math.max(this.maxParams,params.length);return bind(...params);};
  return statement;
 }
 reset(){this.statements=[];this.maxParams=0;}
}
const percentile=(xs:number[],p:number)=>[...xs].sort((a,b)=>a-b)[Math.min(xs.length-1,Math.ceil(xs.length*p)-1)];

it('profiles local route cost with conservative D1 prepared-statement and payload bounds',async()=>{
 const db=new ProfileDatabase(),env=testEnv(db),user=await seedUser(env,crypto.randomUUID(),'owner');
 const passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
 const imported=await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env)).json() as {id:string};
 const conversation=await (await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id})},env)).json() as {id:string};
 const results:Record<string,unknown>[]=[];
 async function profile(name:string,count:number,request:()=>Promise<Response>|Response,beforeEach?:()=>void){
  db.enabled=false;db.sqlite.exec('DELETE FROM rate_windows');const durations:number[]=[],queries:number[]=[],payloads:number[]=[],statuses:number[]=[];let maxParams=0,maxHeapDelta=0;let worst:string[]=[];
  for(let i=0;i<count;i++){
   db.enabled=false;beforeEach?.();db.reset();db.enabled=true;const heap=process.memoryUsage().heapUsed,start=performance.now();const response=await request(),text=await response.text();durations.push(performance.now()-start);maxHeapDelta=Math.max(maxHeapDelta,process.memoryUsage().heapUsed-heap);
   queries.push(db.statements.length);payloads.push(new TextEncoder().encode(text).length);statuses.push(response.status);maxParams=Math.max(maxParams,db.maxParams);if(db.statements.length>=worst.length)worst=[...db.statements];db.enabled=false;
  }
  results.push({name,samples:count,statuses:[...new Set(statuses)],preparedStatementsMax:Math.max(...queries),maxBoundParameters:maxParams,responseBytesMax:Math.max(...payloads),nodeSqliteWallMs:{median:percentile(durations,.5),p95:percentile(durations,.95)},largestObservedHeapDeltaBytes:Math.max(0,maxHeapDelta),statementShapes:worst.map(sql=>sql.replace(/\s+/g,' ').slice(0,180))});
 }
 await profile('parse-short',20,()=>app.request('/v1/imports/parse',{method:'POST',headers:user.headers,body:JSON.stringify({sharedText:'使徒18:18 JCB'})},env));
 await profile('parse-near-input-limit',20,()=>app.request('/v1/imports/parse',{method:'POST',headers:user.headers,body:JSON.stringify({sharedText:'使徒18:18 JCB\n'+'補足'.repeat(9900)})},env));
 await profile('reading-public-miss',10,()=>app.request(`/v1/imports/${imported.id}/reading`,{headers:user.headers},env),()=>db.sqlite.exec('DELETE FROM public_cache'));
 await profile('reading-public-hit',20,()=>app.request(`/v1/imports/${imported.id}/reading`,{headers:user.headers},env));
 await profile('source-only-question-save',10,()=>app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId:crypto.randomUUID(),question:'この箇所の資料を確認したい',sourceOnly:true})},env));
 db.enabled=false;
 for(let i=0;i<200;i++)await env.DB.prepare('INSERT INTO messages(id,conversation_id,user_id,role,content_json,created_at) VALUES(?,?,?,?,?,?)').bind(crypto.randomUUID(),conversation.id,user.id,'user',JSON.stringify({text:'代表的な保存済み質問'.repeat(30)}),Math.floor(Date.now()/1000)).run();
 await profile('history-latest-50-of-220',10,()=>app.request(`/v1/conversations/${conversation.id}`,{headers:user.headers},env));
 const history=await (await app.request(`/v1/conversations/${conversation.id}`,{headers:user.headers},env)).json() as {messages:unknown[];nextMessageCursor:string|null};expect(history.messages).toHaveLength(50);expect(history.nextMessageCursor).not.toBeNull();
 await profile('whole-export-220-messages',5,()=>app.request('/v1/me/export',{headers:user.headers},env));
 db.sqlite.exec('DELETE FROM rate_windows');const snapshot=await (await app.request('/v1/me/export/snapshots',{method:'POST',headers:user.headers,body:'{}'},env)).json() as {snapshotId:string};
 await profile('export-page-25',10,()=>app.request(`/v1/me/export/pages?snapshotId=${snapshot.snapshotId}&section=messages`,{headers:user.headers},env));
 await profile('source-policy-conflict',5,()=>app.request(`/v1/me/export/pages?snapshotId=${snapshot.snapshotId}&section=messages`,{headers:user.headers},env),()=>db.sqlite.exec("UPDATE public_sources SET active=1-active WHERE id='act-18-18'"));
 db.enabled=false;db.sqlite.exec("UPDATE public_sources SET active=1 WHERE id='act-18-18';DELETE FROM rate_windows");
 const assistant=db.sqlite.prepare("SELECT content_json FROM messages WHERE role='assistant' LIMIT 1").get() as {content_json:string};
 const previous=Number(db.sqlite.prepare('SELECT MAX(rowid) AS n FROM messages').get()!.n);
 for(let i=0;i<25;i++)await env.DB.prepare('INSERT INTO messages(id,conversation_id,user_id,role,content_json,created_at) VALUES(?,?,?,?,?,?)').bind(crypto.randomUUID(),conversation.id,user.id,'assistant',assistant.content_json,1).run();
 const snapshotWorst=await (await app.request('/v1/me/export/snapshots',{method:'POST',headers:user.headers,body:'{}'},env)).json() as {snapshotId:string};
 const cursor=btoa(JSON.stringify({snapshotId:snapshotWorst.snapshotId,section:'messages',after:previous}));
 await profile('export-page-25-assistants',5,()=>app.request(`/v1/me/export/pages?snapshotId=${snapshotWorst.snapshotId}&section=messages&cursor=${encodeURIComponent(cursor)}`,{headers:user.headers},env));
 const saved={questions:Array.from({length:10},()=>({passage,question:'代表的な比較質問',spoilerAllowed:false})),results:Array.from({length:20},(_,i)=>({questionIndex:Math.floor(i/2),modelIndex:i%2,result:JSON.parse(assistant.content_json)}))};
 for(let i=0;i<25;i++)await env.DB.prepare("INSERT INTO comparison_jobs(id,user_id,request_hash,status,saved,metrics_json,created_at,updated_at) VALUES(?,?,?,'complete',1,?,1,1)").bind(crypto.randomUUID(),user.id,'fixture',JSON.stringify(saved)).run();
 const snapshotComparisons=await (await app.request('/v1/me/export/snapshots',{method:'POST',headers:user.headers,body:'{}'},env)).json() as {snapshotId:string};
 await profile('export-page-25-saved-comparisons',3,()=>app.request(`/v1/me/export/pages?snapshotId=${snapshotComparisons.snapshotId}&section=comparisons`,{headers:user.headers},env));
 await profile('invalid-parse-input',10,()=>app.request('/v1/imports/parse',{method:'POST',headers:user.headers,body:JSON.stringify({sharedText:'使徒99:99'})},env));
 db.enabled=false;
 const model=env.DEFAULT_MODEL_ID,secondModel='@cf/meta/llama-3.2-1b-instruct';
 env.AI_ENABLED='true';env.CONNECTED_MODELS=JSON.stringify([model,secondModel]);env.TERMS_REVIEWED_MODELS=JSON.stringify([model,secondModel]);env.TERMS_REVIEW_VERSION=MODEL_TERMS_POLICY_VERSION;env.DAILY_USER_BUDGET='9000';
 await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',user.id).run();
 for(const modelId of [model,secondModel])await env.DB.prepare('INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)').bind(modelId,PRICING_VERSION,JSON.stringify({modelId,pricingVersion:PRICING_VERSION,inputTokenUpperBound:30000,outputTokenUpperBound:2048,includesHiddenReasoning:true,evidenceRef:'synthetic-profile-fixture-not-real-proof',expiresAt:new Date(Date.now()+3600000).toISOString()}),1).run();
 let behavior='ok';env.AI={async run(_model,inputs){if(behavior==='fail')throw new Error('synthetic-provider-failure');const messages=inputs.messages as {content:string}[],claim=JSON.parse(messages[1].content).claims[0];if(behavior==='revoke')await env.DB.prepare("UPDATE public_sources SET active=0 WHERE id=?").bind(claim.sourceId).run();return {response:JSON.stringify({status:'answer',claimKeys:[claim.key]})};}};
 const ask=()=>app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId:crypto.randomUUID(),question:'この箇所の資料を確認したい'})},env);
 await profile('provider-fixture-success',3,ask);behavior='fail';await profile('provider-fixture-failure-retain',3,ask);behavior='revoke';await profile('provider-fixture-revocation-retain',3,ask,()=>db.sqlite.exec('UPDATE public_sources SET active=1'));behavior='ok';
 db.sqlite.exec('UPDATE public_sources SET active=1');
 const consumedBefore=Number(db.sqlite.prepare('SELECT SUM(consumed) AS n FROM budget_days').get()!.n);
 await profile('client-aborted-before-dispatch-refund',3,()=>{const controller=new AbortController();controller.abort();return app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:user.headers,signal:controller.signal,body:JSON.stringify({requestId:crypto.randomUUID(),question:'キャンセル済みの質問'})},env);});
 const consumedAfter=Number(db.sqlite.prepare('SELECT SUM(consumed) AS n FROM budget_days').get()!.n);expect(consumedAfter).toBe(consumedBefore);
 await profile('comparison-plan-max20',1,()=>app.request('/v1/developer/comparisons/plan',{method:'POST',headers:user.headers,body:JSON.stringify({requestId:crypto.randomUUID(),models:[{modelId:model},{modelId:secondModel}],questions:Array.from({length:10},()=>({passage,question:'この箇所の背景は？'}))})},env));
 db.enabled=false;
 const maxPlan={requestId:crypto.randomUUID(),models:[{modelId:model},{modelId:secondModel}],questions:Array.from({length:10},()=>({passage,question:'最大比較の代表的な質問'})),saveResults:true};
 const maxPreview=await (await app.request('/v1/developer/comparisons/plan',{method:'POST',headers:user.headers,body:JSON.stringify(maxPlan)},env)).json() as {confirmationHash:string};
 await profile('comparison-start-max20',1,()=>app.request('/v1/developer/comparisons',{method:'POST',headers:user.headers,body:JSON.stringify({plan:maxPlan,confirmationHash:maxPreview.confirmationHash})},env));
 let trialIndex=0;await profile('comparison-single-step-max20-ledger',20,()=>app.request(`/v1/developer/comparisons/${maxPlan.requestId}/steps`,{method:'POST',headers:user.headers,body:JSON.stringify({plan:maxPlan,confirmationHash:maxPreview.confirmationHash,trialIndex:trialIndex++})},env));
 await profile('comparison-completed-step-replay',3,()=>app.request(`/v1/developer/comparisons/${maxPlan.requestId}/steps`,{method:'POST',headers:user.headers,body:JSON.stringify({plan:maxPlan,confirmationHash:maxPreview.confirmationHash,trialIndex:19})},env));
 await profile('model-catalog22',5,()=>app.request('/v1/developer/models',{headers:user.headers},env));
 db.enabled=false;
 const unsavedPlan={requestId:crypto.randomUUID(),models:[{modelId:model}],questions:[{passage,question:'未保存の比較質問'},{passage,question:'中止する比較質問'}],saveResults:false};
 const unsavedPreview=await (await app.request('/v1/developer/comparisons/plan',{method:'POST',headers:user.headers,body:JSON.stringify(unsavedPlan)},env)).json() as {confirmationHash:string};
 await profile('comparison-start-unsaved',1,()=>app.request('/v1/developer/comparisons',{method:'POST',headers:user.headers,body:JSON.stringify({plan:unsavedPlan,confirmationHash:unsavedPreview.confirmationHash})},env));
 await profile('comparison-single-step-unsaved',1,()=>app.request(`/v1/developer/comparisons/${unsavedPlan.requestId}/steps`,{method:'POST',headers:user.headers,body:JSON.stringify({plan:unsavedPlan,confirmationHash:unsavedPreview.confirmationHash,trialIndex:0})},env));
 await profile('comparison-cancel-partial',1,()=>app.request(`/v1/developer/comparisons/${unsavedPlan.requestId}`,{method:'DELETE',headers:user.headers},env));
 db.enabled=false;
 const expiryPlan={requestId:crypto.randomUUID(),models:[{modelId:model}],questions:[{passage,question:'期限切れになる比較質問'}],saveResults:false};
 const expiryPreview=await (await app.request('/v1/developer/comparisons/plan',{method:'POST',headers:user.headers,body:JSON.stringify(expiryPlan)},env)).json() as {confirmationHash:string};
 expect((await app.request('/v1/developer/comparisons',{method:'POST',headers:user.headers,body:JSON.stringify({plan:expiryPlan,confirmationHash:expiryPreview.confirmationHash})},env)).status).toBe(202);
 await env.DB.prepare('UPDATE comparison_jobs SET expires_at=0 WHERE id=?').bind(expiryPlan.requestId).run();
 await profile('comparison-expiry-reconcile',1,()=>app.request(`/v1/developer/comparisons/${expiryPlan.requestId}`,{headers:user.headers},env));
 db.enabled=false;
 // Synthetic populated primary-text volume; this tests bounds, not authentic corpus integrity.
 const corpusVersion='webp-usfx-2026-10-13-35a6adf626e5';
 db.sqlite.prepare("INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at) VALUES('webp',?,'engwebp','en','public-domain',?,'{}',176,1)").run(corpusVersion,'d2f923bc56cb6e2e77f0f5a3e9cbd6a29f7a3028a3db011e0be8cad4f591449e');
 const verseInsert=db.sqlite.prepare("INSERT INTO scripture_verses(corpus_id,corpus_version,source_id,source_book,source_chapter,source_verse,book,chapter,verse,text,alignment,text_status) VALUES('webp',?,?,'PSA',119,?,'PSA',119,?,?,'canonical-compatible','present')");
 for(let n=1;n<=176;n++)verseInsert.run(corpusVersion,`webp:PSA:119:${n}`,String(n),n,'Synthetic public-domain text fixture only. '.repeat(30));
 db.sqlite.exec("UPDATE scripture_corpora SET state='ready',rights_status='approved',active=1;DELETE FROM rate_windows");
 const scripturePassage={book:'PSA',start:{chapter:119,verse:1},end:{chapter:119,verse:176}};
 const scriptureImport=await(await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[scripturePassage]})},env)).json() as {id:string};
 const scriptureConversation=await(await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:scriptureImport.id})},env)).json() as {id:string};
 await profile('scripture-populated-bounded-page',5,()=>app.request(`/v1/imports/${scriptureImport.id}/scripture`,{headers:user.headers},env));
 await profile('scripture-populated-reading',5,()=>app.request(`/v1/imports/${scriptureImport.id}/reading`,{headers:user.headers},env),()=>db.sqlite.exec('DELETE FROM public_cache'));
 await profile('scripture-populated-source-only',5,()=>app.request(`/v1/conversations/${scriptureConversation.id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId:crypto.randomUUID(),question:'本文を表示したい',sourceOnly:true})},env));
 db.enabled=false;let maxRowBytes=0,maxRowTable='';
 const tables=db.sqlite.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all() as {name:string}[];
 for(const {name} of tables){for(const row of db.sqlite.prepare(`SELECT * FROM ${name}`).all()){const size=new TextEncoder().encode(JSON.stringify(row)).length;if(size>maxRowBytes){maxRowBytes=size;maxRowTable=name;}}}
 const report={generatedAt:new Date().toISOString(),scope:'Node Hono + in-memory SQLite + synthetic local data. No real provider, browser, Worker runtime, network latency or production performance measured.',countMethod:'Conservative number of prepared statements, including individual batch statements. Trigger internal operations and provider runtime are not modeled.',limitsSource:'https://developers.cloudflare.com/d1/platform/limits/',limits:{freeQueriesPerInvocation:50,rowBytes:2000000,boundParameters:100,concurrentConnections:6},memoryCaveat:'Heap deltas are observed process deltas affected by GC, not peak Worker memory. Row JSON byte count is a conservative fixture serialization proxy, not database storage measurement.',fixtureLargestRow:{table:maxRowTable,jsonBytes:maxRowBytes},results};
 if(process.env.BIBLE_WRITE_PROFILE==='1')writeFileSync(new URL('../../../../bible-security-review/local-route-profile.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
 for(const result of results){expect(result.statuses,result.name as string).toEqual([['source-policy-conflict','provider-fixture-revocation-retain'].includes(result.name as string)?409:result.name==='provider-fixture-failure-retain'?503:['invalid-parse-input','client-aborted-before-dispatch-refund'].includes(result.name as string)?400:String(result.name).startsWith('comparison-start')?202:200]);expect(result.preparedStatementsMax,result.name as string).toBeLessThanOrEqual(50);expect(result.maxBoundParameters,result.name as string).toBeLessThanOrEqual(100);expect(result.responseBytesMax,result.name as string).toBeLessThan(2000000);}
 expect(maxRowBytes).toBeLessThan(1900000);
},30000);
