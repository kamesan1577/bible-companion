import {describe,it,expect} from 'vitest';
import {app} from '../src/index';
import {TestDatabase,testEnv,seedUser} from './helpers/db';
import {getScriptureSources} from '../src/scripture';
import {READING_RUNTIME_IDENTITY,readingSourceVersion} from '../src/reading-cache';
import {seedAssetCorpus,realAssetBinding} from './helpers/scripture-assets';
const passage={book:'ACT' as const,start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
const epoch=(db:TestDatabase)=>Number(db.sqlite.prepare('SELECT version FROM source_policy_state WHERE id=1').get()!.version);
function advances(db:TestDatabase,action:()=>unknown){const before=epoch(db);action();expect(epoch(db)).toBeGreaterThan(before);}
function cloneRow(db:TestDatabase,table:string,row:Record<string,unknown>){const keys=Object.keys(row);db.sqlite.prepare(`INSERT INTO ${table}(${keys.join(',')}) VALUES(${keys.map(()=>'?').join(',')})`).run(...keys.map(k=>row[k] as any));}
async function readingFixture(){const db=new TestDatabase(),env=testEnv(db),a=await seedUser(env),b=await seedUser(env);const imported=async(user:typeof a)=>(await(await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env)).json()) as {id:string};return {db,env,a,b,ia:await imported(a),ib:await imported(b)};}

describe('independent security review: cache policy epoch completeness',()=>{
 it.each(['public_sources','public_materials'])('advances epoch on every mutable %s publication path',table=>{
  const db=new TestDatabase(),row=db.sqlite.prepare(`SELECT * FROM ${table} LIMIT 1`).get() as Record<string,unknown>,id='security-epoch-fixture';const column=table==='public_sources'?'content_json':'data_json';const content=JSON.parse(row[column] as string);Object.assign(content,{id,version:'security.v1'});Object.assign(row,{id,version:'security.v1',[column]:JSON.stringify(content)});
  advances(db,()=>cloneRow(db,table,row));
  advances(db,()=>db.sqlite.prepare(`UPDATE ${table} SET rights_status='revoked' WHERE id=?`).run(id));
  advances(db,()=>db.sqlite.prepare(`UPDATE ${table} SET rights_status='approved',active=0 WHERE id=?`).run(id));
  advances(db,()=>db.sqlite.prepare(`UPDATE ${table} SET active=1 WHERE id=?`).run(id));
  content.version='security.v2';if(table==='public_sources')content.title+=' changed';else content.summary+=' changed';
  advances(db,()=>db.sqlite.prepare(`UPDATE ${table} SET version=?,${column}=? WHERE id=?`).run(content.version,JSON.stringify(content),id));
  const latest=db.sqlite.prepare(`SELECT * FROM ${table} WHERE id=?`).get(id) as Record<string,unknown>;
  advances(db,()=>db.sqlite.prepare(`DELETE FROM ${table} WHERE id=?`).run(id));advances(db,()=>cloneRow(db,table,latest));
 });
 it('staged verses are invisible until epoch-changing seal; ready corpus mutations either advance epoch or fail',async()=>{
  const db=new TestDatabase(),env=testEnv(db),version='webp-usfx-2026-10-13-35a6adf626e5',digest='d2f923bc56cb6e2e77f0f5a3e9cbd6a29f7a3028a3db011e0be8cad4f591449e';
  advances(db,()=>db.sqlite.prepare("INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at) VALUES('webp',?,'engwebp','en','public-domain',?,'{}',1,1)").run(version,digest));
  const before=epoch(db);db.sqlite.prepare("INSERT INTO scripture_verses(corpus_id,corpus_version,source_id,source_book,source_chapter,source_verse,book,chapter,verse,text,alignment,text_status) VALUES('webp',?,'webp:ACT:18:18','ACT',18,'18','ACT',18,18,'SYNTHETIC SECURITY FIXTURE','canonical-compatible','present')").run(version);
  expect(epoch(db)).toBe(before);expect(await getScriptureSources(env,passage)).toEqual([]);
  advances(db,()=>db.sqlite.exec("UPDATE scripture_corpora SET state='ready',rights_status='approved',active=1"));expect(await getScriptureSources(env,passage)).toHaveLength(1);
  for(const statement of ["UPDATE scripture_corpora SET active=0","UPDATE scripture_corpora SET rights_status='revoked'","UPDATE scripture_corpora SET rights_status='approved'","UPDATE scripture_corpora SET active=1"])advances(db,()=>db.sqlite.exec(statement));
  for(const statement of ['DELETE FROM scripture_corpora',"UPDATE scripture_corpora SET manifest_sha256=printf('%064d',1)","UPDATE scripture_verses SET text='changed'",'DELETE FROM scripture_verses'])expect(()=>db.sqlite.exec(statement)).toThrow();
 });
 it('shares only public payload across owned imports, never bypassing import ownership',async()=>{
  const f=await readingFixture();const first=await(await app.request(`/v1/imports/${f.ia.id}/reading`,{headers:f.a.headers},f.env)).json() as any;expect(first.cache).toBe('public-miss');
  const second=await(await app.request(`/v1/imports/${f.ib.id}/reading`,{headers:f.b.headers},f.env)).json() as any;expect(second.cache).toBe('public-hit');expect(second.sourceVersion).toBe(first.sourceVersion);
  expect((await app.request(`/v1/imports/${f.ia.id}/reading`,{headers:f.b.headers},f.env)).status).toBe(404);
  const cached=JSON.stringify(f.db.sqlite.prepare('SELECT body_json FROM public_cache').all());for(const secret of [f.a.id,f.b.id,f.a.token,f.b.token,f.ia.id,f.ib.id])expect(cached).not.toContain(secret);
  expect(second.overview.modelInvoked).toBe(false);
 });
 it.each(['source','material','corpus'])('rejects a cached body if %s rights change while the cache read is in flight',async kind=>{
  const f=await readingFixture();seedAssetCorpus(f.db);f.env.SCRIPTURE_ASSETS=realAssetBinding();expect((await app.request(`/v1/imports/${f.ia.id}/reading`,{headers:f.a.headers},f.env)).status).toBe(200);
  let entered!:()=>void,resume!:()=>void;const reached=new Promise<void>(r=>entered=r),gate=new Promise<void>(r=>resume=r),original=f.db.prepare.bind(f.db);
  f.db.prepare=(sql:string)=>{const statement=original(sql);if(sql.includes('FROM public_cache')){const bind=statement.bind.bind(statement);statement.bind=(...params:unknown[])=>{const bound=bind(...params),first=bound.first.bind(bound);bound.first=async<T=Record<string,unknown>>(column?:string):Promise<T|null>=>{const value=await first<T>(column);if(value){entered();await gate;}return value;};return bound;};}return statement;};
  const pending=app.request(`/v1/imports/${f.ia.id}/reading`,{headers:f.a.headers},f.env);await reached;
  try{f.db.sqlite.exec(kind==='source'?"UPDATE public_sources SET rights_status='revoked' WHERE id='act-18-18'":kind==='material'?"UPDATE public_materials SET rights_status='revoked' WHERE id='place-cenchreae'":"UPDATE scripture_corpora SET active=0,rights_status='revoked'");}finally{resume();}
  const response=await pending;expect(response.status).toBe(409);expect(await response.text()).not.toContain('sources');
 });
});

describe('independent security review: early public cache lookup',()=>{
 it('serves a validated hit without loading source/material bodies or fetching immutable assets',async()=>{
  const f=await readingFixture(),calls:string[]=[];seedAssetCorpus(f.db);f.env.SCRIPTURE_ASSETS=realAssetBinding(calls);
  const path=`/v1/imports/${f.ia.id}/reading`;expect((await app.request(path,{headers:f.a.headers},f.env)).status).toBe(200);expect(calls.length).toBeGreaterThan(0);calls.length=0;
  const original=f.db.prepare.bind(f.db);let queries=0;
  f.db.prepare=(sql:string)=>{queries++;if(/FROM (?:public_sources|public_materials|scripture_corpora|scripture_verses)/i.test(sql))throw Error('Body-loading path entered on public hit');return original(sql);};
  const response=await app.request(path,{headers:f.a.headers},f.env);expect(response.status).toBe(200);expect((await response.json() as any).cache).toBe('public-hit');expect(calls).toEqual([]);expect(queries).toBe(6);
 });
 it('changes source identity for every response/runtime pin and policy epoch mutation',async()=>{
  const original=await readingSourceVersion(7);
  for(const field of ['sourceVersion','manifestSha256','assetIndexSha256']){const changed=JSON.parse(JSON.stringify(READING_RUNTIME_IDENTITY));changed.primaryRuntime[field]+='-changed';expect(await readingSourceVersion(7,changed)).not.toBe(original);}
  const schema=JSON.parse(JSON.stringify(READING_RUNTIME_IDENTITY));schema.readingSchemaVersion++;expect(await readingSourceVersion(7,schema)).not.toBe(original);expect(await readingSourceVersion(8)).not.toBe(original);
  for(const invalid of [-1,NaN,Infinity,1.5])expect(()=>readingSourceVersion(invalid)).toThrow();
 });
 it('keeps spoiler, translation and model-dependent public projections in distinct cache entries',async()=>{
  const f=await readingFixture(),path=`/v1/imports/${f.ia.id}/reading`;
  const read=async(suffix='')=>(await(await app.request(path+suffix,{headers:f.a.headers},f.env)).json()) as any;
  expect((await read()).cache).toBe('public-miss');expect((await read()).cache).toBe('public-hit');expect((await read('?spoilers=true')).cache).toBe('public-miss');
  f.db.sqlite.prepare('UPDATE imports SET translation=? WHERE id=?').run('JCB',f.ia.id);expect((await read()).cache).toBe('public-miss');
  f.env.DEFAULT_MODEL_ID='@cf/meta/llama-3.2-1b-instruct';expect((await read()).cache).toBe('public-miss');
 });
});
