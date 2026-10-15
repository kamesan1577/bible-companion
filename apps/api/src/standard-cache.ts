import {sha256,stableJSON} from '@bible/core';
import {PROMPT_VERSION,REGISTRY_VERSION,type AnswerInput,type AnswerResult} from '@bible/ai-harness';
import type {Env} from './types';
import {fail,now} from './http';
export const STANDARD_QUESTION='この箇所の出来事と意味を短い日本語で説明し、登場人物が誰で何をしたか、分かる背景を示してください。同名の人物を根拠なく同一視せず、特定できなければそう記してください。人物のない箇所に人物を作らず、章の背景ならその旨を明記してください。';
export async function standardKey(input:AnswerInput,policyVersion:number,generalKnowledge:boolean){
 const descriptor={kind:'public-scripture-standard.v1',passage:input.passage,translation:input.translation?.toUpperCase()??null,language:'ja',standardQuestion:STANDARD_QUESTION,readingBoundary:input.readingBoundary,spoilerAllowed:input.spoilerAllowed,settings:input.settings,model:input.modelId,generalKnowledge,promptVersion:PROMPT_VERSION,registryVersion:REGISTRY_VERSION,policyVersion,publicSourcesHash:await sha256(stableJSON(input.sources))};
 const json=stableJSON(descriptor);return{key:await sha256(json),json};
}
type Row={result_json:string|null;state:string;lease_until:number};
export async function readStandard(env:Env,key:string):Promise<AnswerResult|null>{
 const row=await env.DB.prepare("SELECT result_json FROM standard_explanations WHERE cache_key=? AND state='complete'").bind(key).first<{result_json:string}>();
 return row?JSON.parse(row.result_json):null;
}
export async function claimStandard(env:Env,key:string,descriptor:string):Promise<{token:string|null;result:AnswerResult|null}>{
 const token=crypto.randomUUID(),t=now();
 const claimed=await env.DB.prepare("INSERT INTO standard_explanations(cache_key,descriptor_json,result_json,lease_token,lease_until,state,created_at,updated_at) VALUES(?,?,NULL,?,?,'generating',?,?) ON CONFLICT(cache_key) DO UPDATE SET lease_token=excluded.lease_token,lease_until=excluded.lease_until,state='generating',updated_at=excluded.updated_at WHERE standard_explanations.result_json IS NULL AND standard_explanations.lease_until<=? RETURNING lease_token").bind(key,descriptor,token,t+90,t,t,t).first<{lease_token:string}>();
 if(claimed?.lease_token===token)return{token,result:null};
 const end=Date.now()+35000;
 while(Date.now()<end){
  const row=await env.DB.prepare('SELECT result_json,state,lease_until FROM standard_explanations WHERE cache_key=?').bind(key).first<Row>();
  if(row?.result_json&&row.state==='complete')return{token:null,result:JSON.parse(row.result_json)};
  if(!row||row.state==='failed')fail(503,'standard_explanation_unavailable','標準解説を準備できませんでした。少ししてから開いてください。');
  await new Promise(resolve=>setTimeout(resolve,500));
 }
 fail(409,'standard_explanation_pending','同じ箇所の標準解説を準備中です。少ししてから開いてください。');
}
export function cachedStandard(result:AnswerResult):AnswerResult{
 return {...result,cacheScope:'public-standard',modelInvoked:false,usage:{...result.usage,actual:{inputTokens:0,outputTokens:0,totalTokens:0},neurons:0},providerPromptCache:{status:'not-applicable',basis:'model-not-invoked',cachedInputTokens:null},timing:{...result.timing,durationMs:0,providerFirstTextMs:null,visibleAnswerMs:0,validatedReadyMs:0}};
}
export async function completeStandard(env:Env,key:string,token:string,result:AnswerResult){
 if(result.status!=='answered'){await failStandard(env,key,token);return;}
 // Store only the public harness result; caller budget, IDs, conversation scope are never stored.
 await env.DB.prepare("UPDATE standard_explanations SET result_json=?,state='complete',lease_until=0,updated_at=? WHERE cache_key=? AND lease_token=? AND state='generating'").bind(JSON.stringify(cachedStandard(result)),now(),key,token).run();
}
export async function failStandard(env:Env,key:string,token:string){
 await env.DB.prepare("UPDATE standard_explanations SET state='failed',lease_until=?,updated_at=? WHERE cache_key=? AND lease_token=? AND state='generating'").bind(now()+30,now(),key,token).run();
}
