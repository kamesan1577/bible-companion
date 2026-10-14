import {describe,it,expect} from 'vitest';
import {prepareCompanionRequest,createCompanionAnswer,createPrivateCacheKey,DEFAULT_MODEL_ID,MODEL_TERMS_POLICY_VERSION,validateSettings,type AnswerInput,type HistoryTurn} from '../src/index';
import {ACTS_SOURCES} from '../fixtures/acts-sources';
const auth={ownerId:'alice',connectedModelIds:[DEFAULT_MODEL_ID],termsReviewedModelIds:[DEFAULT_MODEL_ID],termsReviewVersion:MODEL_TERMS_POLICY_VERSION};
function input():AnswerInput{return {passage:{book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}},question:'誓願について何が分かりますか？',spoilerAllowed:false,sources:structuredClone(ACTS_SOURCES),modelId:DEFAULT_MODEL_ID};}
function turn(source:AnswerInput['sources'][number]):HistoryTurn{return {role:'assistant',content:'PREVIOUS_PRIVATE_ANSWER',ownerId:'alice',scope:{passage:{book:source.book,start:source.start,end:source.end},spoilerAllowed:false,sourceIds:[source.id],sourceVersions:{[source.id]:source.version}}};}

describe('independent security review: private grounded AI boundary',()=>{
 it('drops old assistant text when the referenced source keeps its ID but changes version',()=>{
  const request=input(),source=request.sources[0];request.history=[turn(source)];source.version+='-corrected';
  expect(JSON.stringify(prepareCompanionRequest(request,{authorization:auth}).messages)).not.toContain('PREVIOUS_PRIVATE_ANSWER');
 });
 it('keeps correctly versioned history but never another owner’s turn',()=>{
  const request=input();request.history=[turn(request.sources[0])];
  expect(JSON.stringify(prepareCompanionRequest(request,{authorization:auth}).messages)).toContain('PREVIOUS_PRIVATE_ANSWER');
  request.history[0].ownerId='bob';
  expect(JSON.stringify(prepareCompanionRequest(request,{authorization:auth}).messages)).not.toContain('PREVIOUS_PRIVATE_ANSWER');
 });
 it('does not let model output inject generated prose into strict claim selection',async()=>{
  const request=input();
  await expect(createCompanionAnswer(request,{authorization:auth,ai:{async run(){return {response:JSON.stringify({status:'answer',claimKeys:['s0c0'],answer:'UNREVIEWED_INJECTED_TEXT'})};}}})).rejects.toThrow();
 });
 it('snapshots trusted claims before the asynchronous provider call',async()=>{
  const request=input();let release!:()=>void,entered!:()=>void;
  const gate=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{entered=resolve;});
  const answer=createCompanionAnswer(request,{authorization:auth,ai:{async run(){entered();await gate;return {response:'{"status":"answer","claimKeys":["s0c0"]}'};}}});
  await started;request.sources[0].claims[0].text='MUTATED_AFTER_PROVIDER_STARTED';release();
  expect((await answer).answer).not.toContain('MUTATED_AFTER_PROVIDER_STARTED');
 });
 it('partitions cache identity by owner, spoiler policy, exact source content, settings and question',async()=>{
  const request=input(),key=await createPrivateCacheKey(request,{authorization:auth});expect(key).toMatch(/^private:/);
  expect(await createPrivateCacheKey(request,{authorization:{...auth,ownerId:'bob'}})).not.toBe(key);
  for(const changed of [{...request,spoilerAllowed:true},{...request,question:'別の質問です'},{...request,settings:{temperature:0.3}}])expect(await createPrivateCacheKey(changed,{authorization:auth})).not.toBe(key);
  request.sources[0].text+=' A corrected note.';
  expect(await createPrivateCacheKey(request,{authorization:auth})).not.toBe(key);
 });
 it.each([NaN,Infinity,-Infinity,-1,3])('rejects invalid temperature %s',temperature=>{expect(()=>validateSettings(DEFAULT_MODEL_ID,{temperature})).toThrow();});
 it('never sends private/future source text to a provider',async()=>{
  const request=input();request.sources[0].visibility='private';request.sources[0].ownerId='bob';request.sources[0].text+=' SECRET_FROM_BOB';
  request.sources[1].spoilerEnd={chapter:28,verse:31};request.sources[1].text+=' FUTURE_SECRET';
  let payload='';await createCompanionAnswer(request,{authorization:auth,ai:{async run(_id,body){payload=JSON.stringify(body);return {response:'{"status":"insufficient","claimKeys":[]}'};}}});
  expect(payload).not.toContain('SECRET_FROM_BOB');expect(payload).not.toContain('FUTURE_SECRET');
 });
});
