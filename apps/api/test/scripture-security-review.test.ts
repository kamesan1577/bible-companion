import {describe,it,expect,vi} from 'vitest';
import {assetScriptureRows,knownPrimaryReference} from '../src/scripture-assets';
import {SCRIPTURE_ASSET_INDEX_SHA256,SCRIPTURE_ABSENT_CANONICAL} from '../src/scripture-assets-pin';
import {app} from '../src/index';
import {getScriptureSources} from '../src/scripture';
import {historicalSources} from '../src/history';
import {TestDatabase,testEnv,seedUser} from './helpers/db';

// Synthetic content using the pinned identity ONLY to test server boundary behavior.
// This is not an authentic corpus fixture or ingestion-integrity/translation-quality proof.
const version='webp-usfx-2026-10-13-35a6adf626e5';
const digest='d2f923bc56cb6e2e77f0f5a3e9cbd6a29f7a3028a3db011e0be8cad4f591449e';
function corpus(db:TestDatabase,count:number,hash=digest){
 db.sqlite.prepare("INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at) VALUES('webp',?,'engwebp','en','public-domain',?,'{}',?,1)").run(version,hash,count);
}
function verse(db:TestDatabase,chapter:number,n:number,text='SYNTHETIC PRIMARY TEXT FOR SECURITY TEST ONLY'){
 db.sqlite.prepare("INSERT INTO scripture_verses(corpus_id,corpus_version,source_id,source_book,source_chapter,source_verse,book,chapter,verse,text,alignment,text_status) VALUES('webp',?,?,'ACT',?,?,'ACT',?,?,?,'canonical-compatible','present')").run(version,`webp:ACT:${chapter}:${n}`,chapter,String(n),chapter,n,text);
}
function activate(db:TestDatabase){db.sqlite.exec("UPDATE scripture_corpora SET state='ready',rights_status='approved',active=1");}
const passage={book:'ACT' as const,start:{chapter:1,verse:1},end:{chapter:4,verse:6}};
async function fixture(){const db=new TestDatabase(),env=testEnv(db),user=await seedUser(env),other=await seedUser(env);const imported=await(await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage]})},env)).json() as {id:string};return {db,env,user,other,id:imported.id};}

describe('independent security review: primary scripture boundaries',()=>{
 it('requires complete staged revision and rejects semantic mutation after activation',()=>{
  const db=new TestDatabase();corpus(db,2);verse(db,1,1);
  expect(()=>activate(db)).toThrow();verse(db,1,2);activate(db);
  expect(()=>verse(db,1,3)).toThrow();
  expect(()=>db.sqlite.exec("UPDATE scripture_verses SET text='altered'")).toThrow();
  expect(()=>db.sqlite.exec('DELETE FROM scripture_verses')).toThrow();
  expect(()=>db.sqlite.exec("UPDATE scripture_corpora SET manifest_sha256=printf('%064d',1)")).toThrow();
  expect(()=>db.sqlite.exec('DELETE FROM scripture_corpora')).toThrow();
 });
 it('rejects nullable and remapped canonical coordinates at the SQL boundary',()=>{
  const db=new TestDatabase();corpus(db,1);
  const sql="INSERT INTO scripture_verses(corpus_id,corpus_version,source_id,source_book,source_chapter,source_verse,book,chapter,verse,text,alignment,text_status) VALUES('webp',?,'webp:ACT:1:1','ACT',1,'1','ACT',?,?,'synthetic','canonical-compatible','present')";
  for(const [chapter,n] of [[null,1],[1,null],[2,1],[1,2]])expect(()=>db.sqlite.prepare(sql).run(version,chapter,n)).toThrow();
 });
 it('reserves scripture citation IDs against curated-source collisions',()=>{
  const db=new TestDatabase();
  expect(()=>db.sqlite.exec("UPDATE public_sources SET id='webp:ACT:1:1' WHERE id='act-18-18'")).toThrow();
 });
 it.each(['untrusted','pending','staging','revoked'])('excludes %s primary text from retrieval and history',async mode=>{
  const db=new TestDatabase(),env=testEnv(db);corpus(db,1,mode==='untrusted'?'0'.repeat(64):digest);verse(db,1,1);
  if(mode==='untrusted')activate(db);
  if(mode==='pending')db.sqlite.exec("UPDATE scripture_corpora SET state='ready'");
  if(mode==='revoked'){activate(db);db.sqlite.exec("UPDATE scripture_corpora SET active=0,rights_status='revoked'");}
  expect(await getScriptureSources(env,passage)).toEqual([]);
  expect(await historicalSources(env,[{citations:[{sourceId:'webp:ACT:1:1'}]}])).toEqual([]);
 });
 it('pages exactly through the owned selected range, then invalidates after corpus revocation',async()=>{
  const f=await fixture();corpus(f.db,106);
  for(const [chapter,count] of [[1,26],[2,47],[3,26],[4,7]])for(let n=1;n<=count;n++)verse(f.db,chapter,n);
  activate(f.db);const path=`/v1/imports/${f.id}/scripture`;
  expect((await app.request(path,{headers:f.other.headers},f.env)).status).toBe(404);
  const first=await(await app.request(path,{headers:f.user.headers},f.env)).json() as {items:{id:string}[];nextCursor:string;corpus:{editorialReview:string}};
  expect(first.items).toHaveLength(100);expect(first.corpus.editorialReview).toBe('unreviewed');
  const second=await(await app.request(path+'?after='+encodeURIComponent(first.nextCursor),{headers:f.user.headers},f.env)).json() as {items:{id:string}[];nextCursor:null};
  expect(second.items).toHaveLength(5);expect(second.nextCursor).toBeNull();expect(new Set([...first.items,...second.items].map(x=>x.id)).size).toBe(105);expect(JSON.stringify(second)).not.toContain('webp:ACT:4:7');
  expect((await getScriptureSources(f.env,passage)).length).toBe(48);
  expect(await historicalSources(f.env,[{citations:[{sourceId:'webp:ACT:4:6'}]}])).toHaveLength(1);
  f.db.sqlite.exec("UPDATE scripture_corpora SET active=0,rights_status='revoked'");
  expect((await app.request(path+'?after='+encodeURIComponent(first.nextCursor),{headers:f.user.headers},f.env)).status).toBe(409);
  expect(await historicalSources(f.env,[{citations:[{sourceId:'webp:ACT:4:6'}]}])).toEqual([]);
 });
});

const assetCorpus={id:'webp',version,edition:'engwebp',manifest_sha256:digest,asset_index_sha256:SCRIPTURE_ASSET_INDEX_SHA256};
describe('independent security review: internal scripture asset bounds',()=>{
 it('excludes every pinned absent coordinate from metadata-only historical membership',()=>{
  for(const coordinate of SCRIPTURE_ABSENT_CANONICAL){const [book,chapter,verse]=coordinate.split(':');expect(knownPrimaryReference(book,Number(chapter),Number(verse))).toBe(false);}
  expect(knownPrimaryReference('GEN',1,1)).toBe(true);expect(knownPrimaryReference('REV',22,21)).toBe(true);expect(knownPrimaryReference('REV',22,22)).toBe(false);
 });
 it.each(['mime','size','redirect'])('cancels the response body rejected for %s before reading',async failure=>{
  let cancelled=false,reads=0;const stream=new ReadableStream<Uint8Array>({pull(){reads++;},cancel(){cancelled=true;}},{highWaterMark:0});
  const env={...testEnv(),SCRIPTURE_ASSETS:{async fetch(){return new Response(stream,{status:failure==='redirect'?302:200,headers:{'content-type':failure==='mime'?'text/html':'application/json',...(failure==='size'?{'content-length':'262145'}:{})}});}}};
  await expect(assetScriptureRows(env,assetCorpus,passage,{chapter:1,verse:0},48)).rejects.toThrow();
  expect(reads).toBe(0);expect(cancelled).toBe(true);
 });
 it('cancels a delayed binding response that arrives after timeout instead of consuming its body',async()=>{
  vi.useFakeTimers();try{
   let resolve!: (response:Response)=>void,cancelled=false,reads=0;const delayed=new Promise<Response>(r=>{resolve=r;});
   const env={...testEnv(),SCRIPTURE_ASSETS:{fetch:()=>delayed}};
   const rejected=expect(assetScriptureRows(env,assetCorpus,passage,{chapter:1,verse:0},48)).rejects.toThrow();
   await vi.advanceTimersByTimeAsync(5001);await rejected;
   resolve(new Response(new ReadableStream<Uint8Array>({pull(){reads++;},cancel(){cancelled=true;}},{highWaterMark:0}),{headers:{'content-type':'application/json'}}));
   for(let i=0;i<10;i++)await Promise.resolve();
   expect(reads).toBe(0);expect(cancelled).toBe(true);
  }finally{vi.useRealTimers();}
 });
 it('does not expose internal asset paths through the unauthenticated Worker router',async()=>{
  let calls=0;const env={...testEnv(),SCRIPTURE_ASSETS:{async fetch(){calls++;return new Response('synthetic');}}};
  for(const path of [`/__scripture/${version}/index.json`,`/__scripture/${version}/ACT/1.json`])expect((await app.request(path,{},env)).status).toBe(404);
  expect(calls).toBe(0);
 });
});
