import {describe,it,expect} from 'vitest';
import {app} from '../src/index';
import {testEnv,TestDatabase,seedUser} from './helpers/db';
const passage={book:'ACT',start:{chapter:18,verse:24},end:{chapter:18,verse:28}};
const read=(env:ReturnType<typeof testEnv>,body:unknown)=>app.request('/public/reading',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)},env);
describe('one public reader for app and share',()=>{
 it('returns the exact authenticated reading projection without creating a user/import/conversation or invoking AI',async()=>{
  const db=new TestDatabase(),env=testEnv(db);let calls=0;env.AI_ENABLED='true';env.AI={run:async()=>{calls++;throw Error('no inference');}};
  const first=await read(env,{passage,translation:'JCB'});expect(first.status).toBe(200);expect(first.headers.get('Cache-Control')).toBe('no-store');
  const publicBody=await first.json() as any;
  for(const table of ['users','imports','conversations','messages'])expect(db.sqlite.prepare(`SELECT count(*) AS n FROM ${table}`).get()?.n).toBe(0);
  const user=await seedUser(env);
  const item=await(await app.request('/v1/imports',{method:'POST',headers:user.headers,body:JSON.stringify({idempotencyKey:crypto.randomUUID(),ranges:[passage],translation:'JCB'})},env)).json() as any;
  const mainBody=await(await app.request(`/v1/imports/${item.id}/reading`,{headers:user.headers},env)).json() as any;
  expect({...mainBody,cache:undefined,checkedAt:undefined}).toEqual({...publicBody,cache:undefined,checkedAt:undefined});expect(calls).toBe(0);expect(publicBody.overview.modelInvoked).toBe(false);
  const cached=JSON.stringify(db.sqlite.prepare('SELECT body_json FROM public_cache').all());for(const secret of [user.id,user.token,item.id])expect(cached).not.toContain(secret);
 });
 it('accepts passage metadata only, rejects private text and invalid ranges, rechecks revoked public cards',async()=>{
  const db=new TestDatabase(),env=testEnv(db);
  for(const extra of [{question:'private'},{sharedText:'private'},{messages:[]},{userId:'private'},{spoilers:true}])expect((await read(env,{passage,...extra})).status).toBe(400);
  expect((await read(env,{passage:{...passage,end:{chapter:18,verse:99}}})).status).toBe(400);
  expect((await read(env,{passage,translation:'x'.repeat(31)})).status).toBe(400);
  const before=await(await read(env,{passage})).json() as any;expect(before.people.length).toBeGreaterThan(0);
  db.sqlite.exec("UPDATE public_materials SET rights_status='revoked'");
  const after=await(await read(env,{passage})).json() as any;expect(after.people).toEqual([]);expect(after.places).toEqual([]);expect(after.artworks).toEqual([]);expect(after.sourceVersion).not.toBe(before.sourceVersion);
 });
});
