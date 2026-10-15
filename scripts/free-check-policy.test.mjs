import {test} from 'node:test';
import assert from 'node:assert/strict';
import {nextDeadline,checkAndRenew} from './free-check-policy.mjs';
const settings={bindings:[{name:'CONNECTED_MODELS',type:'plain_text',text:'["@cf/google/gemma-4-26b-a4b-it"]'},{name:'AI',type:'ai'},{name:'AI_BUDGET_MODE',type:'plain_text',text:'free-provider-hard-stop'}]};
test('deadline uses fixed UTC half-days, never a rolling 23-hour lease',()=>{
 assert.equal(nextDeadline(Date.parse('2026-10-15T01:05:00Z')),'2026-10-15T12:00:00.000Z');
 assert.equal(nextDeadline(Date.parse('2026-10-15T12:00:00Z')),'2026-10-16T00:00:00.000Z');
});
test('verified Free route renews only to the next boundary',async()=>{
 const value=await checkAndRenew({readContracts:async()=>[],readSettings:async()=>settings,renew:async v=>v,halt:async()=>assert.fail(),clock:()=>Date.parse('2026-10-15T01:05:00Z')});
 assert.equal(value.expiresAt,'2026-10-15T12:00:00.000Z');
});
for(const failure of ['contracts','settings','renew','paid','malformed'])test('failure revokes evidence: '+failure,async()=>{
 let revoked=0;
 await assert.rejects(checkAndRenew({readContracts:async()=>{if(failure==='contracts')throw Error('secret must not escape');return failure==='paid'?[{rate_plan:{id:'workers-paid',public_name:'Workers Paid'}}]:[];},readSettings:async()=>{if(failure==='settings')throw Error();return failure==='malformed'?{}:settings;},renew:async()=>{if(failure==='renew')throw Error();},halt:async()=>{revoked++;}}),/evidence revoked/);
 assert.equal(revoked,1);
});
test('control-plane outage reports bounded deadline instead of claiming revocation',async()=>{
 await assert.rejects(checkAndRenew({readContracts:async()=>{throw Error();},readSettings:async()=>settings,renew:async()=>{},halt:async()=>{throw Error();}}),/revocation unreachable/);
});
