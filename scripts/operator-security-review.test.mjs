import test from 'node:test';
import assert from 'node:assert/strict';
import {runOperator} from './operator.mjs';
const args=['github-apply','--owner','owner','--action','push','--execute','--allow-remote','--confirm','push:owner/bible-companion:private'];
function mockRunner(multiple){const calls=[];return {calls,run(exe,argv){calls.push({exe,argv});if(exe==='gh'&&argv[0]==='api')return JSON.stringify({login:'owner',type:'User'});if(exe==='gh'&&argv[1]==='view')return JSON.stringify({visibility:'PRIVATE',nameWithOwner:'owner/bible-companion',url:'https://github.com/owner/bible-companion'});if(exe==='git'&&argv[0]==='remote'){const approved='git@github.com:owner/bible-companion.git';return argv.includes('--all')&&multiple?approved+'\nhttps://github.com/other/public.git\n':approved+'\n';}return '';}};}
test('independent review: a hidden second push URL cannot receive the private repository',()=>{
 const fixture=mockRunner(true);assert.throws(()=>runOperator(args,{run:fixture.run,output(){}}));assert(!fixture.calls.some(c=>c.exe==='git'&&c.argv[0]==='push'));
});
test('independent review: one exact private push target remains usable with mocked execution',()=>{
 const fixture=mockRunner(false);runOperator(args,{run:fixture.run,output(){}});const pushes=fixture.calls.filter(c=>c.exe==='git'&&c.argv[0]==='push');assert.equal(pushes.length,1);
 const remoteCheck=fixture.calls.find(c=>c.exe==='git'&&c.argv[0]==='remote');assert(remoteCheck.argv.includes('--all'),'Every configured push URL must be inspected');
});

import {DatabaseSync} from 'node:sqlite';
import {readdirSync,readFileSync} from 'node:fs';
import {pinnedAssetRegistration,validatePinnedAssetRegistration} from './scripture-assets-config.mjs';
import {profileTemplate,validateOperatorProfile,profileToConfig,operatorPlan} from './operator.mjs';
test('independent review: real pinned metadata registration is zero-write replay and cannot reapprove revocation',()=>{
 const db=new DatabaseSync(':memory:');try{
  db.exec('PRAGMA foreign_keys=ON');for(const name of readdirSync(new URL('../apps/api/migrations/',import.meta.url)).filter(x=>x.endsWith('.sql')).sort())db.exec(readFileSync(new URL('../apps/api/migrations/'+name,import.meta.url),'utf8'));
  const r=pinnedAssetRegistration(1);db.exec(r.sql);assert.equal(validatePinnedAssetRegistration(db.prepare(r.readbackSql).get(),r.identity),true);
  const changes=Number(db.prepare('SELECT total_changes() AS n').get().n);db.exec(r.sql);assert.equal(Number(db.prepare('SELECT total_changes() AS n').get().n),changes);
  db.exec("UPDATE scripture_corpora SET active=0,rights_status='revoked' WHERE id='webp'");const revokedChanges=Number(db.prepare('SELECT total_changes() AS n').get().n);db.exec(r.sql);assert.equal(Number(db.prepare('SELECT total_changes() AS n').get().n),revokedChanges);assert.equal(validatePinnedAssetRegistration(db.prepare(r.readbackSql).get(),r.identity),false);
  assert.equal(db.prepare('SELECT count(*) AS n FROM scripture_verses').get().n,0);
 }finally{db.close();}
});
function disconnectedProfile(){return {...profileTemplate(),accountId:'a'.repeat(32),databaseId:'11111111-1111-4111-8111-111111111111',origin:'https://bible.example.org',rpId:'bible.example.org'};}
test('independent review: corpus cron and allowances stay explicit fingerprinted selections',()=>{
 const plain=validateOperatorProfile(disconnectedProfile());const selected=validateOperatorProfile({...plain,corpus:'webp-pinned-assets',cleanup:'daily-utc',dailyAppBudget:10000,dailyUserBudget:9999});
 assert.notEqual(operatorPlan(plain).profileFingerprint,operatorPlan(selected).profileFingerprint);
 const config=profileToConfig(selected);assert.deepEqual(config.triggers,{crons:['17 3 * * *']});assert.equal(config.assets.run_worker_first,true);assert.equal(config.vars.AI_ENABLED,'false');assert.equal(config.vars.DAILY_APP_BUDGET,'10000');
 const baseline=profileToConfig(plain);assert.equal(baseline.assets,undefined);assert.equal(baseline.triggers,undefined);
 for(const patch of [{dailyAppBudget:10001},{dailyUserBudget:10001},{dailyUserBudget:9001,dailyAppBudget:9000},{cleanup:'hourly'},{corpus:'unverified'}])assert.throws(()=>validateOperatorProfile({...plain,...patch}));
});
