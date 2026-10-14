import {describe,it,expect} from 'vitest';
import worker from '../src/index';
import {testEnv,seedUser} from './helpers/db';
import {reserveBudget} from '../src/budget';
describe('explicit scheduled maintenance',()=>{
 it('prunes only expired transient state and settles unknown stale reservations once',async()=>{
  const env=testEnv(),user=await seedUser(env),t=Math.floor(Date.now()/1000);
  for(const [id,expiry] of [['expired',t-1],['current',t+3600]] as const){
   await env.DB.prepare('INSERT INTO auth_flows(id_hash,state,pkce_challenge,expires_at) VALUES(?,?,?,?)').bind(id,'test','test',expiry).run();
   await env.DB.prepare('INSERT INTO auth_codes(code_hash,user_id,pkce_challenge,expires_at) VALUES(?,?,?,?)').bind(id,user.id,'test',expiry).run();
   await env.DB.prepare('INSERT INTO invitations(token_hash,role,expires_at) VALUES(?,?,?)').bind(id,'member',expiry).run();
   await env.DB.prepare('INSERT INTO public_cache(cache_key,source_version,body_json,expires_at) VALUES(?,?,?,?)').bind(id,'test','{}',expiry).run();
  }
  await env.DB.prepare('INSERT INTO rate_windows(scope,window,count) VALUES(?,?,?)').bind('expired',Math.floor(t/60)-1441,1).run();
  await env.DB.prepare('INSERT INTO rate_windows(scope,window,count) VALUES(?,?,?)').bind('current',Math.floor(t/60),1).run();
  await reserveBudget(env,user.id,'stale-unknown',100);await reserveBudget(env,user.id,'current-budget',100);
  await env.DB.prepare('UPDATE budget_reservations SET created_at=? WHERE id=?').bind(t-1000,'stale-unknown').run();
  const policy=await env.DB.prepare('SELECT version FROM source_policy_state WHERE id=1').first();
  await worker.scheduled({} as ScheduledEvent,env);await worker.scheduled({} as ScheduledEvent,env);
  for(const [table,key] of [['auth_flows','id_hash'],['auth_codes','code_hash'],['invitations','token_hash'],['public_cache','cache_key'],['rate_windows','scope']]){
   expect(await env.DB.prepare(`SELECT ${key} AS id FROM ${table} ORDER BY ${key}`).all()).toMatchObject({results:[{id:'current'}]});
  }
  expect(await env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({reserved:100,consumed:100});
  expect(await env.DB.prepare('SELECT version FROM source_policy_state WHERE id=1').first()).toEqual(policy);
  expect(await env.DB.prepare('SELECT id FROM users WHERE id=?').bind(user.id).first()).not.toBeNull();
 });
});
