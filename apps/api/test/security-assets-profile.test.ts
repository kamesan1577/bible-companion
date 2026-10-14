import {it,expect} from 'vitest';
import {writeFileSync} from 'node:fs';
import {app} from '../src/index';
import {TestDatabase,testEnv,seedUser} from './helpers/db';
import {seedAssetCorpus,realAssetBinding,realAssetFiles} from './helpers/scripture-assets';
class MeasuredDatabase extends TestDatabase{statements=0;enabled=false;override prepare(sql:string){if(this.enabled)this.statements++;return super.prepare(sql);}}
const summarize=(xs:number[])=>{const s=[...xs].sort((a,b)=>a-b);return {median:s[Math.floor(s.length/2)],p95:s[Math.ceil(s.length*.95)-1],max:s.at(-1)};};
it('profiles pinned real internal assets using local Node CPU and bounded resources',async()=>{
 const db=new MeasuredDatabase(),env=testEnv(db),user=await seedUser(env);seedAssetCorpus(db);const files=realAssetFiles();
 const cases=[{name:'genesis-three-verses',passage:{book:'GEN',start:{chapter:1,verse:1},end:{chapter:1,verse:3}}},{name:'psalm119-first100',passage:{book:'PSA',start:{chapter:119,verse:1},end:{chapter:119,verse:176}}},{name:'genesis-fullbook-first100',passage:{book:'GEN',start:{chapter:1,verse:1},end:{chapter:50,verse:26}}}];
 const expanded=cases.map(fixture=>({...fixture,route:'scripture'})).concat([cases[0],cases[1]].map(fixture=>({...fixture,name:fixture.name+'-reading',route:'reading'})));
 const results=[];
 for(const fixture of expanded){
  const imported=await(await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[fixture.passage]})},env)).json() as {id:string};
  for(const warm of [false,true]){
   const calls:string[]=[];env.SCRIPTURE_ASSETS=realAssetBinding(calls);
   const request=()=>app.request(`/v1/imports/${imported.id}/${fixture.route}`,{headers:user.headers},env);
   if(warm)expect((await request()).status).toBe(200);
   const samples=[];
   for(let n=0;n<10;n++){
    if(!warm){env.SCRIPTURE_ASSETS=realAssetBinding(calls);if(fixture.route==='reading')db.sqlite.exec('DELETE FROM public_cache');}
    calls.length=0;db.statements=0;db.enabled=true;const cpu=process.cpuUsage(),start=performance.now();const response=await request(),text=await response.text(),used=process.cpuUsage(cpu);db.enabled=false;
    expect(response.status,fixture.name+' '+text+' '+calls.join(',')).toBe(200);const page=JSON.parse(text);if(fixture.route==='scripture'){expect(page.items.length).toBeGreaterThan(0);expect(page.items.length).toBeLessThanOrEqual(100);}else{expect(page.cache).toBe(warm?'public-hit':'public-miss');expect(page.overview.modelInvoked).toBe(false);}
    const sample={cpuMs:(used.user+used.system)/1000,wallMs:performance.now()-start,statements:db.statements,assetFetches:calls.length,assetBytes:calls.reduce((sum,path)=>sum+(files.get(path)?.length??0),0),responseBytes:new TextEncoder().encode(text).length};
    expect(sample.statements).toBeLessThanOrEqual(50);expect(sample.assetFetches).toBeLessThanOrEqual(9);expect(sample.assetBytes).toBeLessThan(600000);expect(sample.responseBytes).toBeLessThan(125000);samples.push(sample);
   }
   results.push({name:fixture.name,cache:fixture.route==='reading'?(warm?'public-hit':'public-miss-fresh-binding'):(warm?'warm-binding':'fresh-binding'),samples:10,cpuMs:summarize(samples.map(x=>x.cpuMs)),wallMs:summarize(samples.map(x=>x.wallMs)),statementsMax:Math.max(...samples.map(x=>x.statements)),assetFetchesMax:Math.max(...samples.map(x=>x.assetFetches)),assetBytesMax:Math.max(...samples.map(x=>x.assetBytes)),responseBytesMax:Math.max(...samples.map(x=>x.responseBytes))});
  }
 }
 const report={measuredAt:new Date().toISOString(),scope:'Real pinned checked-in corpus; local Hono/Node/in-memory SQLite and in-memory synthetic asset binding. Fresh binding clears application asset caches but is not a fresh process or cold Worker isolate. Fixture preparation excluded; request CPU includes SQLite and JSON/hash work. No remote latency or Cloudflare billed CPU measured.',results};
 if(process.env.BIBLE_WRITE_PROFILE==='1')writeFileSync(new URL('../../../../bible-security-review/real-assets-profile.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
},30000);
