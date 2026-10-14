import {MODEL_TERMS_POLICY_VERSION} from '@bible/ai-harness';
import {describe,it,expect} from 'vitest';
import {Hono} from 'hono';
import {HTTPException} from 'hono/http-exception';
import {auth,validateAuthConfig} from '../src/auth';
import {reserveBudget,settleBudget} from '../src/budget';
import {body} from '../src/http';
import type {AppEnv} from '../src/types';
import {TestDatabase,testEnv,seedUser} from './helpers/db';
import {sha256,randomToken} from '@bible/core';
import {z} from 'zod';

function authApp(){const app=new Hono<AppEnv>();app.route('/auth',auth);app.onError((error,c)=>error instanceof HTTPException?error.getResponse():c.json({error:'internal'},500));return app;}
const state='s'.repeat(32),verifier='v'.repeat(43);

describe('independent security review: authentication boundaries',()=>{
 it('rejects hostile and missing origins on browser authentication mutations',async()=>{
  const app=authApp(),env=testEnv();
  for(const origin of [undefined,'null','https://evil.test','http://localhost:8787.evil.test']){
   const headers:Record<string,string>={'Content-Type':'application/json'};if(origin)headers.Origin=origin;
   const response=await app.request('/auth/options',{method:'POST',headers,body:'{"mode":"login"}'},env);
   expect(response.status).toBe(403);
  }
 });
 it('requires S256 initiation and rejects short state',async()=>{
  const app=authApp(),env=testEnv();
  for(const query of [`state=x&code_challenge=${await sha256(verifier)}&code_challenge_method=S256`,`state=${state}&code_challenge=${await sha256(verifier)}&code_challenge_method=plain`]){
   expect((await app.request('/auth/authorize?'+query,{},env)).status).toBe(400);
  }
 });
 it('sets an HttpOnly strict secure flow cookie on HTTPS even in development',async()=>{
  const env={...testEnv(),AUTH_ORIGIN:'https://auth.example.test',RP_ID:'auth.example.test'};
  const response=await authApp().request(`/auth/authorize?state=${state}&code_challenge=${await sha256(verifier)}&code_challenge_method=S256`,{},env);
  expect(response.status).toBe(200);const cookie=response.headers.get('set-cookie')??'';
  expect(cookie).toContain('HttpOnly');expect(cookie).toContain('SameSite=Strict');expect(cookie).toContain('Secure');
  expect(response.headers.get('cache-control')).toBe('no-store');
 });
 it('rejects callback userinfo and insecure production origins',()=>{
  expect(()=>validateAuthConfig({...testEnv(),NATIVE_CALLBACK:'biblecompanion://user:pass@auth/callback'})).toThrow();
  expect(()=>validateAuthConfig({...testEnv(),ENVIRONMENT:'production'})).toThrow();
 });
 it('rejects incorrect verifier without burning code; valid code is single-use under parallel requests',async()=>{
  const env=testEnv(),user=await seedUser(env),code=randomToken(),app=authApp();
  await env.DB.prepare('INSERT INTO auth_codes(code_hash,user_id,pkce_challenge,expires_at) VALUES(?,?,?,?)').bind(await sha256(code),user.id,await sha256(verifier),Math.floor(Date.now()/1000)+60).run();
  const exchange=(v:string)=>app.request('/auth/token',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,codeVerifier:v})},env);
  expect((await exchange('w'.repeat(43))).status).toBe(401);
  const results=await Promise.all([exchange(verifier),exchange(verifier)]);
  expect(results.map(r=>r.status).sort()).toEqual([200,401]);
  const success=await results.find(r=>r.status===200)!.json() as {accessToken:string};
  expect(success.accessToken).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect(await env.DB.prepare('SELECT token_hash FROM sessions WHERE token_hash=?').bind(success.accessToken).first()).toBeNull();
  expect(await env.DB.prepare('SELECT token_hash FROM sessions WHERE token_hash=?').bind(await sha256(success.accessToken)).first()).not.toBeNull();
 });
 it('rejects expired exchange codes',async()=>{
  const env=testEnv(),user=await seedUser(env),code=randomToken();
  await env.DB.prepare('INSERT INTO auth_codes(code_hash,user_id,pkce_challenge,expires_at) VALUES(?,?,?,?)').bind(await sha256(code),user.id,await sha256(verifier),Math.floor(Date.now()/1000)-1).run();
  expect((await authApp().request('/auth/token',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,codeVerifier:verifier})},env)).status).toBe(401);
 });
 it('rejects a streamed oversized body without reading its full content',async()=>{
  const app=new Hono<AppEnv>();app.post('/body',async c=>c.json(await body(c,z.object({text:z.string()}))));app.onError((e,c)=>e instanceof HTTPException?e.getResponse():c.json({},500));
  let pulls=0;const stream=new ReadableStream<Uint8Array>({pull(controller){pulls++;controller.enqueue(new Uint8Array(16384));if(pulls===100)controller.close();}});
  const request=new Request('http://localhost/body',{method:'POST',body:stream,duplex:'half'} as RequestInit);
  expect((await app.fetch(request,testEnv())).status).toBe(413);expect(pulls).toBeLessThan(10);
 });
});

describe('independent security review: actual SQLite budget triggers',()=>{
 it('rolls back a reservation exceeding the user cap without changing global totals',async()=>{
  const db=new TestDatabase(),env={...testEnv(db),DAILY_USER_BUDGET:'600'},user=await seedUser(env);
  await reserveBudget(env,user.id,'first',500);await expect(reserveBudget(env,user.id,'second',500)).rejects.toThrow();
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:500,consumed:0});
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations').first()).toEqual({n:1});
 });
 it('enforces the global budget across distinct owners',async()=>{
  const env={...testEnv(),DAILY_APP_BUDGET:'700'},a=await seedUser(env),b=await seedUser(env);
  await reserveBudget(env,a.id,'first',500);await expect(reserveBudget(env,b.id,'second',500)).rejects.toThrow();
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:500,consumed:0});
 });
 it('charges unknown usage conservatively and settlement is idempotent',async()=>{
  const env=testEnv(),user=await seedUser(env);await reserveBudget(env,user.id,'first',500);
  await settleBudget(env,'first',null);await settleBudget(env,'first',0);
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:500});
 });
 it('records actual usage even above the reservation and rejects invalid usage',async()=>{
  const env=testEnv(),user=await seedUser(env);await reserveBudget(env,user.id,'first',500);await settleBudget(env,'first',700);
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:700});
  for(const invalid of [-1,NaN,Infinity,1.5])await expect(settleBudget(env,'first',invalid)).rejects.toThrow();
 });
});

describe('independent security review: tenant and data boundaries',()=>{
 const passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
 it('isolates import read/delete, conversation create/read/edit/delete, and exports',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),a=await seedUser(env),b=await seedUser(env);
  const imported=await app.request('/v1/imports',{method:'POST',headers:a.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env);
  expect(imported.status).toBe(201);const row=await imported.json() as {id:string};
  for(const method of ['GET','DELETE'])expect((await app.request('/v1/imports/'+row.id,{method,headers:b.headers},env)).status).toBe(404);
  expect((await app.request('/v1/conversations',{method:'POST',headers:b.headers,body:JSON.stringify({importId:row.id})},env)).status).toBe(404);
  const created=await app.request('/v1/conversations',{method:'POST',headers:a.headers,body:JSON.stringify({importId:row.id})},env);expect(created.status).toBe(201);
  const convo=await created.json() as {id:string};
  for(const method of ['GET','DELETE','PATCH'])expect((await app.request('/v1/conversations/'+convo.id,{method,headers:b.headers,...(method==='PATCH'?{body:'{"spoilerAllowed":true}'}:{})},env)).status).toBe(404);
  const exported=await (await app.request('/v1/me/export',{headers:b.headers},env)).json() as {imports:unknown[];conversations:unknown[]};
  expect(exported.imports).toEqual([]);expect(exported.conversations).toEqual([]);
  expect((await app.request('/v1/imports/'+row.id,{headers:a.headers},env)).status).toBe(200);
 });
 it('scopes idempotency to owner and rejects key reuse with different payload',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),a=await seedUser(env),b=await seedUser(env),key=crypto.randomUUID();
  const payload={idempotencyKey:key,ranges:[passage]};
  const create=(headers:Record<string,string>,value:unknown)=>app.request('/v1/imports',{method:'POST',headers,body:JSON.stringify(value)},env);
  const results=await Promise.all([create(a.headers,payload),create(a.headers,payload)]);
  expect(results.map(r=>r.status).sort()).toEqual([200,201]);
  const rows=await Promise.all(results.map(r=>r.json())) as {id:string}[];expect(rows[0].id).toBe(rows[1].id);
  expect((await create(a.headers,{...payload,translation:'JCB'})).status).toBe(409);
  const other=await create(b.headers,payload);expect(other.status).toBe(201);expect((await other.json() as {id:string}).id).not.toBe(rows[0].id);
  expect((await create(a.headers,{...payload,userId:b.id})).status).toBe(400);
 });
 it('invalidates a native bearer session after logout',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),a=await seedUser(env);
  expect((await app.request('/v1/me',{headers:a.headers},env)).status).toBe(200);
  expect((await app.request('/v1/logout',{method:'POST',headers:a.headers},env)).status).toBe(204);
  expect((await app.request('/v1/me',{headers:a.headers},env)).status).toBe(401);
 });
 it('does not skip imports sharing the same timestamp across pages',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),a=await seedUser(env),time=Math.floor(Date.now()/1000);
  for(let i=0;i<53;i++)await env.DB.prepare('INSERT INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,created_at) VALUES(?,?,?,?,?,?)').bind(crypto.randomUUID(),a.id,crypto.randomUUID(),'hash',JSON.stringify([passage]),time).run();
  const first=await (await app.request('/v1/imports',{headers:a.headers},env)).json() as {items:{id:string}[];nextCursor:string|number|null};
  expect(first.items).toHaveLength(50);expect(first.nextCursor).not.toBeNull();
  const second=await (await app.request('/v1/imports?before='+encodeURIComponent(String(first.nextCursor)),{headers:a.headers},env)).json() as {items:{id:string}[]};
  expect(second.items).toHaveLength(3);expect(new Set([...first.items,...second.items].map(x=>x.id)).size).toBe(53);
 });
});

describe('independent security review: AI authorization and cancellation',()=>{
 const model='@cf/google/gemma-4-26b-a4b-it';
 it('blocks ordinary users from every developer endpoint',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),user=await seedUser(env);
  for(const [method,path] of [['GET','/developer/models'],['PUT','/developer/model-preference'],['DELETE','/developer/model-preference'],['POST','/developer/comparisons/plan'],['POST','/developer/comparisons'],['GET','/developer/comparisons/anything'],['DELETE','/developer/comparisons/anything']]){
   expect((await app.request('/v1'+path,{method,headers:user.headers,...(['POST','PUT'].includes(method)?{body:'{}'}:{})},env)).status).toBe(403);
  }
 });
 it('rejects unknown and paid model destinations even when marked connected',async()=>{
  const {app}=await import('../src/index');const paid='@cf/moonshotai/kimi-k2.6';const env={...testEnv(),AI_ENABLED:'true',TERMS_REVIEWED_MODELS:JSON.stringify([model]),TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,CONNECTED_MODELS:JSON.stringify([model,paid,'https://evil.test'])},user=await seedUser(env,crypto.randomUUID(),'owner');
  for(const id of ['https://evil.test',paid,'@cf/unknown/model']){
   const response=await app.request('/v1/developer/model-preference',{method:'PUT',headers:user.headers,body:JSON.stringify({modelId:id})},env);expect([400,503]).toContain(response.status);
  }
  expect(await env.DB.prepare('SELECT * FROM model_preferences').first()).toBeNull();
 });
 it('does not resurrect a question cancelled during budget reservation',async()=>{
  const {app}=await import('../src/index');const db=new TestDatabase();let calls=0;
  const env={...testEnv(db),AI_ENABLED:'true',TERMS_REVIEWED_MODELS:JSON.stringify([model]),TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,CONNECTED_MODELS:JSON.stringify([model]),AI:{async run(){calls++;return {response:'{}'};}}};const user=await seedUser(env);
  const {PRICING_VERSION}=await import('@bible/ai-harness');
  const proof={modelId:model,pricingVersion:PRICING_VERSION,inputTokenUpperBound:30000,outputTokenUpperBound:2048,includesHiddenReasoning:true,evidenceRef:'synthetic-test-fixture-not-real-proof',expiresAt:new Date(Date.now()+3600000).toISOString()};
  await env.DB.prepare('INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)').bind(model,PRICING_VERSION,JSON.stringify(proof),1).run();
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',user.id).run();
  const passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
  const imported=await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env)).json() as {id:string};
  const conversation=await (await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id})},env)).json() as {id:string};
  const requestId=crypto.randomUUID();let release!:()=>void,entered!:()=>void;
  const gate=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{entered=resolve;});
  const original=db.batch.bind(db);db.batch=async statements=>{if(statements.some(s=>s.sql.includes('INSERT INTO budget_reservations'))){entered();await gate;}return original(statements);};
  const question=app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId,question:'この節の背景は？'})},env);
  await started;
  try{expect((await app.request('/v1/requests/'+requestId,{method:'DELETE',headers:user.headers},env)).status).toBe(200);}finally{release();}
  expect((await question).status).toBe(409);
  expect(await env.DB.prepare('SELECT status FROM generation_requests WHERE id=?').bind(requestId).first()).toEqual({status:'cancelled'});
  expect(calls).toBe(0);expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM messages').first()).toEqual({n:0});
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:0});
 });
});

describe('independent security review: real signed WebAuthn assertions',()=>{
 async function ceremony(overrides:{origin?:string;rp?:string;flags?:number;expired?:boolean;wrongSignature?:boolean}={}){
  const {generateKeyPairSync,createHash,sign}=await import('node:crypto');
  const env=testEnv(),user=await seedUser(env),flowToken=randomToken(),challenge=randomToken(),credentialId=randomToken();
  const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),jwk=pair.publicKey.export({format:'jwk'});
  // Minimal ES256 COSE_Key: {1:2,3:-7,-1:1,-2:x,-3:y}. No mocked verifier.
  const publicKey=Buffer.concat([Buffer.from([0xa5,0x01,0x02,0x03,0x26,0x20,0x01,0x21,0x58,0x20]),Buffer.from(jwk.x!,'base64url'),Buffer.from([0x22,0x58,0x20]),Buffer.from(jwk.y!,'base64url')]);
  await env.DB.prepare('INSERT INTO credentials(id,user_id,public_key,counter,transports_json,device_type,backed_up,created_at) VALUES(?,?,?,?,?,?,?,?)').bind(credentialId,user.id,publicKey.toString('base64url'),0,'[]','singleDevice',0,1).run();
  await env.DB.prepare('INSERT INTO auth_flows(id_hash,state,pkce_challenge,challenge,mode,expires_at) VALUES(?,?,?,?,?,?)').bind(await sha256(flowToken),state,await sha256(verifier),challenge,'login',Math.floor(Date.now()/1000)+(overrides.expired?-1:60)).run();
  const clientDataJSON=Buffer.from(JSON.stringify({type:'webauthn.get',challenge,origin:overrides.origin??env.AUTH_ORIGIN,crossOrigin:false}));
  const count=Buffer.alloc(4);count.writeUInt32BE(1);
  const authenticatorData=Buffer.concat([createHash('sha256').update(overrides.rp??env.RP_ID).digest(),Buffer.from([overrides.flags??0x05]),count]);
  const signature=sign('sha256',Buffer.concat([authenticatorData,createHash('sha256').update(clientDataJSON).digest()]),pair.privateKey);
  if(overrides.wrongSignature)signature[signature.length-1]^=1;
  const response={id:credentialId,rawId:credentialId,type:'public-key',clientExtensionResults:{},response:{clientDataJSON:clientDataJSON.toString('base64url'),authenticatorData:authenticatorData.toString('base64url'),signature:signature.toString('base64url'),userHandle:null}};
  const submit=()=>authApp().request('/auth/verify',{method:'POST',headers:{Origin:env.AUTH_ORIGIN,'Content-Type':'application/json',Cookie:`bible_auth_flow=${flowToken}`},body:JSON.stringify({response})},env);
  return {env,submit,credentialId};
 }
 it('accepts a valid ES256 assertion and consumes the ceremony',async()=>{
  const {env,submit,credentialId}=await ceremony();const response=await submit();expect(response.status).toBe(200);
  const output=await response.json() as {callback:string};const callback=new URL(output.callback);
  expect(callback.protocol).toBe('biblecompanion:');expect(callback.searchParams.get('state')).toBe(state);expect(callback.searchParams.get('code')).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect(await env.DB.prepare('SELECT counter FROM credentials WHERE id=?').bind(credentialId).first()).toEqual({counter:1});
  expect((await submit()).status).toBe(401);
 });
 it.each([
  {origin:'https://evil.test'}, {rp:'evil.test'}, {flags:0x01}, {wrongSignature:true}, {expired:true},
 ])('rejects signed assertion violating origin/RP/UV/signature/expiry: %j',async bad=>{
  const {env,submit}=await ceremony(bad);expect((await submit()).status).toBe(401);
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM auth_codes').first()).toEqual({n:0});
 });
 it('permits only one successful concurrent verification of a valid assertion',async()=>{
  const {submit}=await ceremony();const responses=await Promise.all([submit(),submit()]);
  expect(responses.filter(x=>x.status===200)).toHaveLength(1);expect(responses.filter(x=>[401,409].includes(x.status))).toHaveLength(1);
 });
});

describe('independent security review: concurrent accounting invariants',()=>{
 it('allows only capacity-fitting parallel reservations across users',async()=>{
  const env={...testEnv(),DAILY_APP_BUDGET:'1000'},a=await seedUser(env),b=await seedUser(env);
  const outcomes=await Promise.allSettled(Array.from({length:12},(_,i)=>reserveBudget(env,i%2?a.id:b.id,'parallel-'+i,250)));
  expect(outcomes.filter(x=>x.status==='fulfilled')).toHaveLength(4);
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:1000,consumed:0});
  expect(await env.DB.prepare('SELECT SUM(amount) AS n FROM budget_reservations').first()).toEqual({n:1000});
 });
 it('does not double reserve on an identical reservation ID',async()=>{
  const env=testEnv(),a=await seedUser(env);
  const outcomes=await Promise.allSettled([reserveBudget(env,a.id,'duplicate',500),reserveBudget(env,a.id,'duplicate',500)]);
  expect(outcomes.filter(x=>x.status==='fulfilled')).toHaveLength(1);
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:500,consumed:0});
 });
 it('settles the original UTC bucket after a day boundary',async()=>{
  const env=testEnv(),user=await seedUser(env),day='2020-01-01';
  await env.DB.prepare('INSERT INTO budget_days(day) VALUES(?)').bind(day).run();
  await env.DB.prepare('INSERT INTO user_budget_days(user_id,day) VALUES(?,?)').bind(user.id,day).run();
  await env.DB.prepare('INSERT INTO budget_reservations(id,user_id,day,amount,created_at,app_limit,user_limit) VALUES(?,?,?,?,?,?,?)').bind('old-day',user.id,day,500,1,9000,2000).run();
  await settleBudget(env,'old-day',350);
  expect(await env.DB.prepare('SELECT day,reserved,consumed FROM budget_days').first()).toEqual({day,reserved:0,consumed:350});
 });
 it('enforces one active comparison per owner while allowing distinct owners',async()=>{
  const env=testEnv(),a=await seedUser(env),b=await seedUser(env);
  const insert=(id:string,user:string)=>env.DB.prepare("INSERT INTO comparison_jobs(id,user_id,request_hash,status,created_at,updated_at) VALUES(?,?,?,'running',1,1)").bind(id,user,'hash').run();
  const outcomes=await Promise.allSettled([insert('a-one',a.id),insert('a-two',a.id),insert('b-one',b.id)]);
  expect(outcomes.filter(x=>x.status==='fulfilled')).toHaveLength(2);
 });
});

describe('independent security review: registration transaction rollback',()=>{
 it('preserves a valid invitation when a verified registration duplicates a credential',async()=>{
  const {generateKeyPairSync,createHash}=await import('node:crypto');const env=testEnv(),existing=await seedUser(env),credentialId=randomToken(),invite=randomToken();
  const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'}),jwk=pair.publicKey.export({format:'jwk'});
  const cose=Buffer.concat([Buffer.from([0xa5,0x01,0x02,0x03,0x26,0x20,0x01,0x21,0x58,0x20]),Buffer.from(jwk.x!,'base64url'),Buffer.from([0x22,0x58,0x20]),Buffer.from(jwk.y!,'base64url')]);
  await env.DB.prepare('INSERT INTO credentials(id,user_id,public_key,counter,transports_json,device_type,backed_up,created_at) VALUES(?,?,?,?,?,?,?,?)').bind(credentialId,existing.id,cose.toString('base64url'),0,'[]','singleDevice',0,1).run();
  await env.DB.prepare('INSERT INTO invitations(token_hash,role,expires_at) VALUES(?,?,?)').bind(await sha256(invite),'member',Math.floor(Date.now()/1000)+300).run();
  const flowToken=randomToken(),challenge=randomToken(),newUser=crypto.randomUUID();
  await env.DB.prepare('INSERT INTO auth_flows(id_hash,state,pkce_challenge,challenge,mode,pending_user_id,expires_at) VALUES(?,?,?,?,?,?,?)').bind(await sha256(flowToken),state,await sha256(verifier),challenge,'register',newUser,Math.floor(Date.now()/1000)+60).run();
  const id=Buffer.from(credentialId,'base64url'),length=Buffer.alloc(2);length.writeUInt16BE(id.length);
  const authData=Buffer.concat([createHash('sha256').update(env.RP_ID).digest(),Buffer.from([0x45]),Buffer.alloc(4),Buffer.alloc(16),length,id,cose]);
  function bytes(b:Buffer){return Buffer.concat([b.length<24?Buffer.from([0x40+b.length]):Buffer.from([0x58,b.length]),b]);}
  function text(s:string){return Buffer.concat([Buffer.from([0x60+s.length]),Buffer.from(s)]);}
  const attestation=Buffer.concat([Buffer.from([0xa3]),text('fmt'),text('none'),text('attStmt'),Buffer.from([0xa0]),text('authData'),bytes(authData)]);
  const clientDataJSON=Buffer.from(JSON.stringify({type:'webauthn.create',challenge,origin:env.AUTH_ORIGIN,crossOrigin:false}));
  const response={id:credentialId,rawId:credentialId,type:'public-key',clientExtensionResults:{},response:{clientDataJSON:clientDataJSON.toString('base64url'),attestationObject:attestation.toString('base64url'),transports:['internal']}};
  const {verifyRegistrationResponse}=await import('@simplewebauthn/server');
  const verified=await verifyRegistrationResponse({response:response as Parameters<typeof verifyRegistrationResponse>[0]['response'],expectedChallenge:challenge,expectedOrigin:env.AUTH_ORIGIN,expectedRPID:env.RP_ID,requireUserVerification:true});
  expect(verified.verified).toBe(true);
  const result=await authApp().request('/auth/verify',{method:'POST',headers:{Origin:env.AUTH_ORIGIN,'Content-Type':'application/json',Cookie:`bible_auth_flow=${flowToken}`},body:JSON.stringify({response,invitation:invite})},env);
  expect(result.status).toBe(401);
  expect(await env.DB.prepare('SELECT role FROM invitations WHERE token_hash=?').bind(await sha256(invite)).first()).toEqual({role:'member'});
  expect(await env.DB.prepare('SELECT id FROM users WHERE id=?').bind(newUser).first()).toBeNull();
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM auth_codes').first()).toEqual({n:0});
 });
});

describe('independent security review: inference budget proof gate',()=>{
 it.each(['missing','expired','wrong-model','wrong-pricing','excludes-reasoning'])('rejects %s proof before reservation, request claim or provider call',async kind=>{
  const {app}=await import('../src/index');const {PRICING_VERSION}=await import('@bible/ai-harness');const model='@cf/google/gemma-4-26b-a4b-it';let calls=0;
  const env={...testEnv(),AI_ENABLED:'true',TERMS_REVIEWED_MODELS:JSON.stringify([model]),TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,CONNECTED_MODELS:JSON.stringify([model]),AI:{async run(){calls++;return {response:'{}'};}}},user=await seedUser(env);
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',user.id).run();
  if(kind!=='missing'){
   const proof={modelId:kind==='wrong-model'?'@cf/unknown/model':model,pricingVersion:kind==='wrong-pricing'?'old-price':PRICING_VERSION,inputTokenUpperBound:30000,outputTokenUpperBound:2048,includesHiddenReasoning:kind!=='excludes-reasoning',evidenceRef:'synthetic-invalid-proof-regression',expiresAt:new Date(Date.now()+(kind==='expired'?-60000:3600000)).toISOString()};
   await env.DB.prepare('INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)').bind(model,PRICING_VERSION,JSON.stringify(proof),1).run();
  }
  const passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
  const imported=await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env)).json() as {id:string};
  const conversation=await (await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id})},env)).json() as {id:string};
  const result=await app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId:crypto.randomUUID(),question:'誓願について何が分かりますか？'})},env);
  expect(result.status).toBe(503);expect(calls).toBe(0);
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations').first()).toEqual({n:0});
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM generation_requests').first()).toEqual({n:0});
 });
});

describe('independent security review: comparison partial cancellation',()=>{
 it('retains only the started trial reservation and releases never-dispatched trials',async()=>{
  const {app}=await import('../src/index');const {PRICING_VERSION}=await import('@bible/ai-harness');const model='@cf/google/gemma-4-26b-a4b-it';let calls=0,release!:()=>void,entered!:()=>void;
  const gate=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{entered=resolve;});
  const env={...testEnv(),AI_ENABLED:'true',TERMS_REVIEWED_MODELS:JSON.stringify([model]),TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,CONNECTED_MODELS:JSON.stringify([model]),AI:{async run(){calls++;entered();await gate;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};}}},user=await seedUser(env,crypto.randomUUID(),'owner');
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',user.id).run();
  const proof={modelId:model,pricingVersion:PRICING_VERSION,inputTokenUpperBound:30000,outputTokenUpperBound:2048,includesHiddenReasoning:true,evidenceRef:'synthetic-test-fixture-not-real-proof',expiresAt:new Date(Date.now()+3600000).toISOString()};
  await env.DB.prepare('INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)').bind(model,PRICING_VERSION,JSON.stringify(proof),1).run();
  const requestId=crypto.randomUUID(),passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
  const plan={requestId,models:[{modelId:model}],questions:[{passage,question:'誓願について何が分かりますか？'},{passage,question:'場所について何が分かりますか？'}]};
  const preview=await app.request('/v1/developer/comparisons/plan',{method:'POST',headers:user.headers,body:JSON.stringify(plan)},env);expect(preview.status).toBe(200);
  const prepared=await preview.json() as {confirmationHash:string;reservedBudgetUnits:number};
  expect((await app.request('/v1/developer/comparisons',{method:'POST',headers:user.headers,body:JSON.stringify({plan,confirmationHash:prepared.confirmationHash})},env)).status).toBe(202);
  const comparison=app.request(`/v1/developer/comparisons/${requestId}/steps`,{method:'POST',headers:user.headers,body:JSON.stringify({plan,confirmationHash:prepared.confirmationHash,trialIndex:0})},env);
  await started;
  try{expect((await app.request('/v1/developer/comparisons/'+requestId,{method:'DELETE',headers:user.headers},env)).status).toBe(200);}finally{release();}
  expect((await comparison).status).toBe(409);expect(calls).toBe(1);
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:prepared.reservedBudgetUnits/2});
  expect(await env.DB.prepare('SELECT status,metrics_json FROM comparison_jobs WHERE id=?').bind(requestId).first()).toEqual({status:'cancelled',metrics_json:'[]'});
 });
});

describe('independent security review: target versus reading boundary',()=>{
 it('keeps the full confirmed reading range while narrowing the question target',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),user=await seedUser(env),reading={book:'ACT',start:{chapter:18,verse:1},end:{chapter:18,verse:18}},target={book:'ACT',start:{chapter:18,verse:3},end:{chapter:18,verse:3}};
  const imported=await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[reading]})},env)).json() as {id:string};
  const response=await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id,passage:target})},env);expect(response.status).toBe(201);
  const conversation=await response.json() as {id:string;passage:unknown;readingBoundary:unknown};expect(conversation.passage).toEqual(target);expect(conversation.readingBoundary).toEqual(reading);
  const fetched=await (await app.request('/v1/conversations/'+conversation.id,{headers:user.headers},env)).json() as {readingBoundary:unknown};expect(fetched.readingBoundary).toEqual(reading);
  const sourceOnly=await app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId:crypto.randomUUID(),question:'この節について',sourceOnly:true})},env);expect(sourceOnly.status).toBe(200);
  const answer=await sourceOnly.json() as {result:{citations:{passage:{start:{verse:number};end:{verse:number}}}[]}};
  expect(answer.result.citations.length).toBeGreaterThan(0);for(const citation of answer.result.citations){expect(citation.passage.start.verse).toBeLessThanOrEqual(3);expect(citation.passage.end.verse).toBeGreaterThanOrEqual(3);}
 });
 it('rejects a target before, after, cross-book, or spanning a gap between selected ranges',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),user=await seedUser(env),reading={book:'ACT',start:{chapter:18,verse:3},end:{chapter:18,verse:8}};
  const imported=await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[reading,{book:'ACT',start:{chapter:18,verse:12},end:{chapter:18,verse:18}}]})},env)).json() as {id:string};
  for(const target of [{...reading,start:{chapter:18,verse:2}},{...reading,end:{chapter:18,verse:9}},{...reading,book:'MAT'},{...reading,end:{chapter:18,verse:18}}]){
   expect((await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id,passage:target})},env)).status).toBe(400);
  }
  expect((await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id,readingBoundary:{...reading,end:{chapter:28,verse:31}}})},env)).status).toBe(400);
 });
});

describe('independent security review: in-flight source policy changes',()=>{
 it('withholds an answer whose cited source was revoked while inference was pending',async()=>{
  const {app}=await import('../src/index');const {PRICING_VERSION}=await import('@bible/ai-harness');const model='@cf/google/gemma-4-26b-a4b-it';let sourceId='',release!:()=>void,entered!:()=>void;
  const gate=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{entered=resolve;});
  const env={...testEnv(),AI_ENABLED:'true',TERMS_REVIEWED_MODELS:JSON.stringify([model]),TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,CONNECTED_MODELS:JSON.stringify([model]),AI:{async run(_model:string,inputs:Record<string,unknown>){const messages=inputs.messages as {content:string}[];sourceId=JSON.parse(messages[1].content).claims[0].sourceId;entered();await gate;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};}}},user=await seedUser(env);
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',user.id).run();
  const proof={modelId:model,pricingVersion:PRICING_VERSION,inputTokenUpperBound:30000,outputTokenUpperBound:2048,includesHiddenReasoning:true,evidenceRef:'synthetic-test-fixture-not-real-proof',expiresAt:new Date(Date.now()+3600000).toISOString()};
  await env.DB.prepare('INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)').bind(model,PRICING_VERSION,JSON.stringify(proof),1).run();
  const passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
  const imported=await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env)).json() as {id:string};
  const conversation=await (await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id})},env)).json() as {id:string};
  const requestId=crypto.randomUUID();const question=app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId,question:'誓願について何が分かりますか？'})},env);
  await started;
  try{expect(sourceId).not.toBe('');await env.DB.prepare("UPDATE public_sources SET rights_status='revoked' WHERE id=?").bind(sourceId).run();}finally{release();}
  expect((await question).status).toBe(409);
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM messages').first()).toEqual({n:0});
  expect(await env.DB.prepare('SELECT result_json FROM generation_requests WHERE id=?').bind(requestId).first()).toEqual({result_json:null});
  const usage=await env.DB.prepare('SELECT consumed FROM budget_days').first<{consumed:number}>();expect(usage!.consumed).toBeGreaterThan(0);
 });
});

describe('independent security review: bulk deletion race',()=>{
 it('does not recreate an import from a request authenticated before reading-data deletion',async()=>{
  const {app}=await import('../src/index');const db=new TestDatabase(),env=testEnv(db),user=await seedUser(env);let release!:()=>void,entered!:()=>void,paused=false;
  const gate=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{entered=resolve;});
  const original=db.prepare.bind(db);
  db.prepare=(sql:string)=>{
   const statement=original(sql);
   if(sql==='SELECT * FROM imports WHERE user_id=? AND idempotency_key=?'){
    const bind=statement.bind.bind(statement);statement.bind=(...params:unknown[])=>{const bound=bind(...params),first=bound.first.bind(bound);bound.first=async <T=Record<string,unknown>>(column?:string):Promise<T|null>=>{if(!paused){paused=true;entered();await gate;}return first<T>(column);};return bound;};
   }
   return statement;
  };
  const passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
  const pending=app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env);
  await started;
  try{expect((await app.request('/v1/me/reading-data',{method:'DELETE',headers:user.headers,body:'{"confirmation":"DELETE_MY_READING_DATA"}'},env)).status).toBe(200);}finally{release();}
  expect((await pending).status).toBe(409);
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM imports WHERE user_id=?').bind(user.id).first()).toEqual({n:0});
  expect((await app.request('/v1/me',{headers:user.headers},env)).status).toBe(200);
 });
});

describe('independent security review: public artwork and reading cache',()=>{
 it('rejects private-network, arbitrary-host and credential-bearing automatic image URLs',async()=>{
  const {materialSchema}=await import('../../../packages/core/src/materials');const {readFileSync}=await import('node:fs');
  const cards=JSON.parse(readFileSync(new URL('../../../packages/core/fixtures/source-cards.json',import.meta.url),'utf8')) as Record<string,any>[];
  const art=cards.find(card=>card.kind==='artwork'&&card.details.media)!;expect(art).toBeTruthy();expect(materialSchema.safeParse(art).success).toBe(true);
  for(const url of ['https://127.0.0.1/a.jpg','https://localhost/a.jpg','https://169.254.169.254/a.jpg','https://[::1]/a.jpg','https://evil.test/a.jpg','https://api.nga.gov.evil.test/a.jpg','https://user:pass@api.nga.gov/a.jpg','https://api.nga.gov:444/a.jpg','http://api.nga.gov/a.jpg']){
   const candidate=structuredClone(art);candidate.details.media.url=url;expect(materialSchema.safeParse(candidate).success,url).toBe(false);
  }
 });
 it('shares only public reading content while requiring authenticated access and isolating private import IDs',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),a=await seedUser(env),b=await seedUser(env),passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
  const make=async(user:typeof a)=>(await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage],translation:'JCB'})},env)).json()) as {id:string};
  const first=await make(a),second=await make(b);
  expect((await app.request(`/v1/imports/${first.id}/reading`,{},env)).status).toBe(401);
  expect((await app.request(`/v1/imports/${first.id}/reading`,{headers:b.headers},env)).status).toBe(404);
  const readA=await (await app.request(`/v1/imports/${first.id}/reading`,{headers:a.headers},env)).json() as {cache:string};
  const readB=await (await app.request(`/v1/imports/${second.id}/reading`,{headers:b.headers},env)).json() as {cache:string};
  expect(readA.cache).toBe('public-miss');expect(readB.cache).toBe('public-hit');
  const cache=await env.DB.prepare('SELECT body_json FROM public_cache').all<{body_json:string}>();const serialized=JSON.stringify(cache.results);
  for(const privateValue of [a.id,b.id,a.token,b.token,first.id,second.id])expect(serialized).not.toContain(privateValue);
 });
});

describe('independent security review: saved comparison policy',()=>{
 it('withholds saved comparison answer text after its cited source is revoked',async()=>{
  const {app}=await import('../src/index');const {PRICING_VERSION}=await import('@bible/ai-harness');const model='@cf/google/gemma-4-26b-a4b-it';let sourceId='',answerText='';
  const env={...testEnv(),AI_ENABLED:'true',TERMS_REVIEWED_MODELS:JSON.stringify([model]),TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,CONNECTED_MODELS:JSON.stringify([model]),AI:{async run(_model:string,inputs:Record<string,unknown>){const messages=inputs.messages as {content:string}[],claim=JSON.parse(messages[1].content).claims[0];sourceId=claim.sourceId;answerText=claim.text;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};}}},user=await seedUser(env,crypto.randomUUID(),'owner');
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',user.id).run();
  const proof={modelId:model,pricingVersion:PRICING_VERSION,inputTokenUpperBound:30000,outputTokenUpperBound:2048,includesHiddenReasoning:true,evidenceRef:'synthetic-test-fixture-not-real-proof',expiresAt:new Date(Date.now()+3600000).toISOString()};
  await env.DB.prepare('INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)').bind(model,PRICING_VERSION,JSON.stringify(proof),1).run();
  const requestId=crypto.randomUUID(),passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}},plan={requestId,models:[{modelId:model}],questions:[{passage,question:'この節の内容は？'}],saveResults:true};
  const preview=await (await app.request('/v1/developer/comparisons/plan',{method:'POST',headers:user.headers,body:JSON.stringify(plan)},env)).json() as {confirmationHash:string};
  expect((await app.request('/v1/developer/comparisons',{method:'POST',headers:user.headers,body:JSON.stringify({plan,confirmationHash:preview.confirmationHash})},env)).status).toBe(202);
  const completed=await app.request(`/v1/developer/comparisons/${requestId}/steps`,{method:'POST',headers:user.headers,body:JSON.stringify({plan,confirmationHash:preview.confirmationHash,trialIndex:0})},env);expect(completed.status).toBe(200);expect(answerText).not.toBe('');
  const before=await (await app.request('/v1/developer/comparisons/'+requestId,{headers:user.headers},env)).text();expect(before).toContain(answerText);
  await env.DB.prepare("UPDATE public_sources SET rights_status='revoked' WHERE id=?").bind(sourceId).run();
  const after=await (await app.request('/v1/developer/comparisons/'+requestId,{headers:user.headers},env)).text();expect(after).not.toContain(answerText);
  const replay=await app.request('/v1/developer/comparisons',{method:'POST',headers:user.headers,body:JSON.stringify({plan,confirmationHash:preview.confirmationHash})},env);expect(await replay.text()).not.toContain(answerText);
  const exported=await (await app.request('/v1/me/export',{headers:user.headers},env)).text();expect(exported).not.toContain(answerText);expect(exported).toContain('この節の内容は？');
 });
});

describe('independent security review: durable pre-claim cancellation',()=>{
 it('keeps a cancelled question UUID dead for its owner without cancelling another user’s identical UUID',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),a=await seedUser(env),b=await seedUser(env),requestId=crypto.randomUUID();
  const passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
  const setup=async(user:typeof a)=>{const imported=await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env)).json() as {id:string};return (await (await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id})},env)).json()) as {id:string};};
  const ca=await setup(a),cb=await setup(b);
  expect((await app.request('/v1/requests/'+requestId,{method:'DELETE',headers:a.headers},env)).status).toBe(200);
  const ask=(user:typeof a,id:string)=>app.request(`/v1/conversations/${id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId,question:'本文を確認したい',sourceOnly:true})},env);
  expect((await ask(a,ca.id)).status).toBe(409);
  expect((await ask(b,cb.id)).status).toBe(200);
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE user_id=?').bind(a.id).first()).toEqual({n:0});
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE user_id=?').bind(b.id).first()).toEqual({n:2});
 });
});

describe('independent security review: bounded export snapshot isolation',()=>{
 it('paginates exactly once and rejects foreign-owner and cross-section cursors',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),a=await seedUser(env),b=await seedUser(env);const range=JSON.stringify([{book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}}]);
  for(let i=0;i<27;i++)await env.DB.prepare('INSERT INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,created_at) VALUES(?,?,?,?,?,?)').bind(crypto.randomUUID(),a.id,crypto.randomUUID(),'hash',range,1).run();
  const snapshot=await (await app.request('/v1/me/export/snapshots',{method:'POST',headers:a.headers,body:'{}'},env)).json() as {snapshotId:string};
  const query=`/v1/me/export/pages?snapshotId=${snapshot.snapshotId}&section=imports`;
  expect((await app.request(query,{headers:b.headers},env)).status).toBe(404);
  const firstResponse=await app.request(query,{headers:a.headers},env);const firstText=await firstResponse.text();expect(new TextEncoder().encode(firstText).length).toBeLessThan(1048576);const first=JSON.parse(firstText) as {items:{id:string}[];nextCursor:string};expect(first.items).toHaveLength(25);
  const second=await (await app.request(query+'&cursor='+encodeURIComponent(first.nextCursor),{headers:a.headers},env)).json() as {items:{id:string}[];nextCursor:null};expect(second.items).toHaveLength(2);expect(second.nextCursor).toBeNull();expect(new Set([...first.items,...second.items].map(x=>x.id)).size).toBe(27);
  expect((await app.request(query.replace('section=imports','section=messages')+'&cursor='+encodeURIComponent(first.nextCursor),{headers:a.headers},env)).status).toBe(400);
  expect(firstText).not.toContain(a.token);expect(firstText).not.toContain('request_hash');
 });
 it.each(['private-write','source-policy','expired'])('requires restart after %s invalidates a snapshot',async change=>{
  const {app}=await import('../src/index');const env=testEnv(),user=await seedUser(env);
  const snapshot=await (await app.request('/v1/me/export/snapshots',{method:'POST',headers:user.headers,body:'{}'},env)).json() as {snapshotId:string};
  if(change==='private-write')await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',user.id).run();
  else if(change==='source-policy')await env.DB.prepare("UPDATE public_sources SET active=0 WHERE id='act-18-18'").run();
  else await env.DB.prepare('UPDATE export_snapshots SET expires_at=0 WHERE id=?').bind(snapshot.snapshotId).run();
  expect((await app.request(`/v1/me/export/pages?snapshotId=${snapshot.snapshotId}&section=imports`,{headers:user.headers},env)).status).toBe(409);
 });
 it('does not invalidate Alice’s snapshot for Bob’s private settings change',async()=>{
  const {app}=await import('../src/index');const env=testEnv(),a=await seedUser(env),b=await seedUser(env);
  const snapshot=await (await app.request('/v1/me/export/snapshots',{method:'POST',headers:a.headers,body:'{}'},env)).json() as {snapshotId:string};
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',b.id).run();
  expect((await app.request(`/v1/me/export/pages?snapshotId=${snapshot.snapshotId}&section=imports`,{headers:a.headers},env)).status).toBe(200);
 });
});

describe('independent security review: historical citation scale',()=>{
 it('keeps a valid saved answer beyond generation’s64-source window, but still hides actual revocation',async()=>{
  const {app}=await import('../src/index');const {getSources}=await import('../src/data');const env=testEnv(),user=await seedUser(env),passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
  const imported=await (await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env)).json() as {id:string};
  const conversation=await (await app.request('/v1/conversations',{method:'POST',headers:user.headers,body:JSON.stringify({importId:imported.id})},env)).json() as {id:string};
  const requestId=crypto.randomUUID();const original=await (await app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:user.headers,body:JSON.stringify({requestId,question:'本文を確認したい',sourceOnly:true})},env)).json() as {result:{answer:string;citations:{sourceId:string}[]}};
  const sourceId=original.result.citations[0].sourceId,source=await env.DB.prepare('SELECT * FROM public_sources WHERE id=?').bind(sourceId).first<Record<string,unknown>>();expect(source).not.toBeNull();
  for(let i=0;i<70;i++){
   const id='a'+String(i).padStart(4,'0'),content=JSON.parse(String(source!.content_json));content.id=id;
   await env.DB.prepare('INSERT INTO public_sources(id,book,start_chapter,start_verse,end_chapter,end_verse,kind,title,content_json,version,rights_status,active) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').bind(id,source!.book,source!.start_chapter,source!.start_verse,source!.end_chapter,source!.end_verse,source!.kind,source!.title,JSON.stringify(content),source!.version,'approved',1).run();
  }
  expect((await getSources(env,passage)).some(s=>s.id===sourceId)).toBe(false);
  const history=await (await app.request('/v1/conversations/'+conversation.id,{headers:user.headers},env)).json() as {messages:{role:string;content:{answer?:string;hidden?:boolean}}[]};
  expect(history.messages.find(m=>m.role==='assistant')!.content.answer).toBe(original.result.answer);
  const status=await (await app.request('/v1/requests/'+requestId,{headers:user.headers},env)).json() as {result:{answer:string}};expect(status.result.answer).toBe(original.result.answer);
  expect(await (await app.request('/v1/me/export',{headers:user.headers},env)).text()).toContain(original.result.citations[0].sourceId);
  await env.DB.prepare("UPDATE public_sources SET rights_status='revoked' WHERE id=?").bind(sourceId).run();
  const revoked=await (await app.request('/v1/conversations/'+conversation.id,{headers:user.headers},env)).json() as {messages:{role:string;content:{hidden?:boolean}}[]};expect(revoked.messages.find(m=>m.role==='assistant')!.content.hidden).toBe(true);
 });
});

async function reviewComparisonFixture(run:(_model:string,inputs:Record<string,unknown>)=>Promise<unknown>){
 const {app}=await import('../src/index'),{PRICING_VERSION}=await import('@bible/ai-harness');const db=new TestDatabase(),model='@cf/google/gemma-4-26b-a4b-it';
 const env={...testEnv(db),AI_ENABLED:'true',CONNECTED_MODELS:JSON.stringify([model]),TERMS_REVIEWED_MODELS:JSON.stringify([model]),TERMS_REVIEW_VERSION:MODEL_TERMS_POLICY_VERSION,AI:{run}},user=await seedUser(env,crypto.randomUUID(),'owner');
 await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?').bind('{"workersAiConsent":true}',user.id).run();
 const proof={modelId:model,pricingVersion:PRICING_VERSION,inputTokenUpperBound:30000,outputTokenUpperBound:2048,includesHiddenReasoning:true,evidenceRef:'synthetic-ledger-fixture-not-real-proof',expiresAt:new Date(Date.now()+3600000).toISOString()};
 await env.DB.prepare('INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)').bind(model,PRICING_VERSION,JSON.stringify(proof),1).run();
 const id=crypto.randomUUID(),passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}},plan={requestId:id,models:[{modelId:model}],questions:[{passage,question:'PRIVATE_COMPARISON_QUESTION_ONE'},{passage,question:'PRIVATE_COMPARISON_QUESTION_TWO'}]};
 const preview=await (await app.request('/v1/developer/comparisons/plan',{method:'POST',headers:user.headers,body:JSON.stringify(plan)},env)).json() as {confirmationHash:string;reservedBudgetUnits:number};
 const start=()=>app.request('/v1/developer/comparisons',{method:'POST',headers:user.headers,body:JSON.stringify({plan,confirmationHash:preview.confirmationHash})},env);
 const step=(trialIndex:number)=>app.request(`/v1/developer/comparisons/${id}/steps`,{method:'POST',headers:user.headers,body:JSON.stringify({plan,confirmationHash:preview.confirmationHash,trialIndex})},env);
 return {app,db,env,user,id,plan,preview,start,step};
}
describe('independent security review: durable comparison ledger',()=>{
 it('does not orphan budget when reading data is deleted before reservation insertion',async()=>{
  const f=await reviewComparisonFixture(async()=>({response:'{"status":"answer","claimKeys":["s0c0"]}'}));let entered!:()=>void,release!:()=>void;
  const gate=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{entered=resolve;});
  const original=f.db.batch.bind(f.db);f.db.batch=async statements=>{if(statements.some(s=>s.sql.includes('INSERT INTO budget_reservations'))){entered();await gate;}return original(statements);};
  const start=f.start();await started;
  try{expect((await f.app.request('/v1/me/reading-data',{method:'DELETE',headers:f.user.headers,body:'{"confirmation":"DELETE_MY_READING_DATA"}'},f.env)).status).toBe(200);}finally{release();}
  expect((await start).status).toBeGreaterThanOrEqual(400);
  expect(await f.env.DB.prepare("SELECT COUNT(*) AS n FROM budget_reservations WHERE state='reserved'").first()).toEqual({n:0});
  const usage=await f.env.DB.prepare('SELECT COALESCE(SUM(reserved),0) AS n FROM budget_days').first();expect(usage).toEqual({n:0});
 });
 it('claims one step once, blocks out-of-order work and replays without another provider dispatch',async()=>{
  let calls=0,entered!:()=>void,release!:()=>void;const gate=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{entered=resolve;});
  const f=await reviewComparisonFixture(async()=>{calls++;entered();await gate;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};});expect((await f.start()).status).toBe(202);expect(calls).toBe(0);
  const first=f.step(0);await started;
  try{expect((await f.step(0)).status).toBe(409);expect((await f.step(1)).status).toBe(409);}finally{release();}
  expect((await first).status).toBe(200);const replay=await f.step(0);expect(replay.status).toBe(200);expect((await replay.json() as {replayed:boolean}).replayed).toBe(true);expect(calls).toBe(1);
  expect((await f.step(1)).status).toBe(200);expect(calls).toBe(2);
  const rows=await f.env.DB.prepare('SELECT metrics_json FROM comparison_jobs').all();expect(JSON.stringify(rows)).not.toContain('PRIVATE_COMPARISON_QUESTION');
  expect(await f.env.DB.prepare('SELECT reserved FROM budget_days').first()).toEqual({reserved:0});
 });
 it('fails an expired dispatched lease conservatively and never retries uncertain inference',async()=>{
  let calls=0,entered!:()=>void,release!:()=>void;const gate=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{entered=resolve;});
  const f=await reviewComparisonFixture(async()=>{calls++;entered();await gate;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};});expect((await f.start()).status).toBe(202);
  const first=f.step(0);await started;await f.env.DB.prepare('UPDATE comparison_trials SET lease_expires_at=0 WHERE job_id=? AND trial_index=0').bind(f.id).run();
  const reconciled=await (await f.app.request('/v1/developer/comparisons/'+f.id,{headers:f.user.headers},f.env)).json() as {status:string;trials:{usageUnknown:boolean}[]};expect(reconciled.status).toBe('failed');expect(reconciled.trials[0].usageUnknown).toBe(true);release();
  expect((await first).status).toBe(409);expect((await f.step(0)).status).toBe(409);expect(calls).toBe(1);
  expect(await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:f.preview.reservedBudgetUnits/2});
 });
});

function pauseStatementClaim(db:TestDatabase,match:(sql:string)=>boolean){
 let entered!:()=>void,release!:()=>void,paused=false;const reached=new Promise<void>(resolve=>{entered=resolve;}),gate=new Promise<void>(resolve=>{release=resolve;});const original=db.prepare.bind(db);
 db.prepare=(sql:string)=>{const statement=original(sql);if(match(sql)){const bind=statement.bind.bind(statement);statement.bind=(...params:unknown[])=>{const bound=bind(...params),first=bound.first.bind(bound);bound.first=async <T=Record<string,unknown>>(column?:string):Promise<T|null>=>{if(!paused){paused=true;entered();await gate;}return first<T>(column);};return bound;};}return statement;};
 return {reached,release};
}
describe('independent security review: dispatch proof compare-and-swap',()=>{
 it.each(['deleted','replaced','expired'])('does not dispatch with a %s proof changed after validation',async mutation=>{
  let calls=0;const f=await reviewComparisonFixture(async()=>{calls++;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};});expect((await f.start()).status).toBe(202);
  const pause=pauseStatementClaim(f.db,sql=>sql.startsWith('UPDATE comparison_trials SET dispatched=1'));const step=f.step(0);await pause.reached;
  try{
   if(mutation==='deleted')await f.env.DB.prepare('DELETE FROM model_budget_proofs').run();
   else{const stored=await f.env.DB.prepare('SELECT model_id,bounds_json FROM model_budget_proofs').first<{model_id:string;bounds_json:string}>();const proof=JSON.parse(stored!.bounds_json);if(mutation==='expired')proof.expiresAt=new Date(0).toISOString();else proof.evidenceRef='synthetic-replaced-calibration-record';await f.env.DB.prepare('UPDATE model_budget_proofs SET bounds_json=? WHERE model_id=?').bind(JSON.stringify(proof),stored!.model_id).run();}
  }finally{pause.release();}
  expect((await step).status).toBeGreaterThanOrEqual(400);expect(calls).toBe(0);
  expect(await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:0});
 });
});

describe('independent security review: question dispatch proof gate',()=>{
 it.each(['deleted','replaced','expired'])('refunds and never invokes when a question proof is %s immediately before dispatch',async mutation=>{
  let calls=0;const f=await reviewComparisonFixture(async()=>{calls++;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};});const passage=f.plan.questions[0].passage;
  const imported=await (await f.app.request('/v1/imports',{method:'POST',headers:f.user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},f.env)).json() as {id:string};
  const conversation=await (await f.app.request('/v1/conversations',{method:'POST',headers:f.user.headers,body:JSON.stringify({importId:imported.id})},f.env)).json() as {id:string};
  const pause=pauseStatementClaim(f.db,sql=>sql.startsWith('UPDATE generation_requests SET updated_at=')&&sql.includes('model_budget_proofs'));
  const question=f.app.request(`/v1/conversations/${conversation.id}/questions`,{method:'POST',headers:f.user.headers,body:JSON.stringify({requestId:crypto.randomUUID(),question:'この節の背景は？'})},f.env);await pause.reached;
  try{if(mutation==='deleted')await f.env.DB.prepare('DELETE FROM model_budget_proofs').run();else{const stored=await f.env.DB.prepare('SELECT model_id,bounds_json FROM model_budget_proofs').first<{model_id:string;bounds_json:string}>();const proof=JSON.parse(stored!.bounds_json);if(mutation==='expired')proof.expiresAt=new Date(0).toISOString();else proof.evidenceRef='synthetic-question-replacement';await f.env.DB.prepare('UPDATE model_budget_proofs SET bounds_json=? WHERE model_id=?').bind(JSON.stringify(proof),stored!.model_id).run();}}finally{pause.release();}
  expect((await question).status).toBeGreaterThanOrEqual(400);expect(calls).toBe(0);
  expect(await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:0});
 });
});

describe('independent security review: observed abort before comparison invocation',()=>{
 it.each([false,true])('refunds a proven non-invocation after dispatch CAS (concurrent cancellation: %s)',async concurrentCancel=>{
  let calls=0;const f=await reviewComparisonFixture(async()=>{calls++;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};});expect((await f.start()).status).toBe(202);
  const controller=new AbortController();const original=f.db.prepare.bind(f.db);
  f.db.prepare=(sql:string)=>{const statement=original(sql);if(sql.startsWith('UPDATE comparison_trials SET dispatched=1')){const bind=statement.bind.bind(statement);statement.bind=(...params:unknown[])=>{const bound=bind(...params),first=bound.first.bind(bound);bound.first=async <T=Record<string,unknown>>(column?:string):Promise<T|null>=>{const result=await first<T>(column);if(concurrentCancel)await f.app.request(`/v1/developer/comparisons/${f.id}`,{method:'DELETE',headers:f.user.headers},f.env);controller.abort();return result;};return bound;};}return statement;};
  const response=await f.app.request(`/v1/developer/comparisons/${f.id}/steps`,{method:'POST',headers:f.user.headers,signal:controller.signal,body:JSON.stringify({plan:f.plan,confirmationHash:f.preview.confirmationHash,trialIndex:0})},f.env);
  expect(response.status).toBeGreaterThanOrEqual(400);expect(calls).toBe(0);
  expect(await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:0,consumed:0});
 });
});
