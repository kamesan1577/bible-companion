// Existing cf authentication only. Never creates credentials or changes a billing plan.
// Usage: node scripts/renew-workers-free.mjs --execute
import {n as authenticatedClient} from '../node_modules/cf/dist/auth-MNz2D-PD.mjs';
import {mkdir,writeFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import config from '../apps/api/cloudflare.config.ts';
import {checkAndRenew} from './free-check-policy.mjs';
const execute=process.argv.slice(2).length===1&&process.argv[2]==='--execute';
if(!execute)throw Error('Explicit --execute required for the approved receipt refresh');
const account=config.accountId, database=config.worker.env.DB.id, worker=config.worker.name;
const slot='bible-companion-workers-free';
if(!/^[a-f0-9]{32}$/.test(account)||!database||worker!=='bible-companion')throw Error('Exact configured target required');
const client=await authenticatedClient({});
const q={method:'POST',path:()=>`/accounts/${account}/d1/database/${database}/query`,body:'json'};
const query=async(sql,params=[])=>{const r=await client.send(q,{body:{sql,params}});return(r.result??r)[0].results;};
const halt=()=>query('UPDATE ai_free_account_receipts SET revoked_at=? WHERE account_id=? AND revoked_at IS NULL AND id IN (SELECT receipt_id FROM ai_free_receipt_slots WHERE slot_id=? AND account_id=?)',[Math.floor(Date.now()/1000),account,slot,account]);
await checkAndRenew({
readContracts:async()=>{const r=await client.send({method:'GET',path:()=>`/accounts/${account}/subscriptions`},{},{timeoutInSeconds:20});return r.result??r;},
readSettings:async()=>{const r=await client.send({method:'GET',path:()=>`/accounts/${account}/workers/scripts/${worker}/settings`},{},{timeoutInSeconds:20});return r.result??r;},
halt,
renew:async({plans,models,verifiedAt,expiresAt})=>{
const evidence={verifiedAt,accountId:account,subscriptions:plans,completeSinglePageEndpoint:true,worker,route:'direct-workers-binding',models,defaultFreeBasis:'https://developers.cloudflare.com/workers/platform/pricing/',freeStopBasis:'https://developers.cloudflare.com/workers-ai/platform/pricing/',gatewayCredits:false,paidModels:false,fallbacks:false};
const bytes=JSON.stringify(evidence,null,2)+'\n';const id='free-'+randomUUID();
const receipt={schemaVersion:1,policyVersion:'workers-ai-free-hard-stop.v1',accountId:account,verifiedAt,expiresAt,evidenceRef:'sha256:'+createHash('sha256').update(bytes).digest('hex'),accountPlan:'free',providerRoute:'direct-workers-binding',gatewayCredits:false,paidModels:false,fallbacks:false};
await mkdir('.cache/ai-free-checks',{recursive:true,mode:0o700});await writeFile(`.cache/ai-free-checks/${id}.json`,bytes,{mode:0o600,flag:'wx'});
await query('INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,?)',[id,account,JSON.stringify(receipt),Math.floor(Date.parse(verifiedAt)/1000)]);
const current=(await query('SELECT receipt_id,generation FROM ai_free_receipt_slots WHERE slot_id=? AND account_id=?',[slot,account]))[0];
if(current){await query('UPDATE ai_free_receipt_slots SET receipt_id=?,generation=generation+1,updated_at=? WHERE slot_id=? AND account_id=? AND generation=? AND receipt_id=?',[id,Math.floor(Date.now()/1000),slot,account,current.generation,current.receipt_id]);}
else await query('INSERT INTO ai_free_receipt_slots(slot_id,account_id,receipt_id,generation,updated_at) VALUES(?,?,?,1,?)',[slot,account,id,Math.floor(Date.now()/1000)]);
const readback=(await query('SELECT receipt_id,generation FROM ai_free_receipt_slots WHERE slot_id=? AND account_id=?',[slot,account]))[0];
if(readback?.receipt_id!==id||readback.generation!==(current?current.generation+1:1))throw Error('Refresh lease/readback failed; no deployment changed');
console.log(JSON.stringify({status:'free-evidence-renewed',slot,generation:readback.generation,expiresAt:receipt.expiresAt,billingChanged:false,newCredentials:false}));

}});
