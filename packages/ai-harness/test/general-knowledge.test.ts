import {it,expect} from 'vitest';
import {createCompanionAnswer,validateGeneralAnswer,DEFAULT_MODEL_ID} from '../src/index';
import{offlineFixtureAuthorization}from'../fixtures/authorization';
const passage={book:'ACT',start:{chapter:23,verse:1},end:{chapter:23,verse:1}};
it('explicit server opt-in permits clearly labeled general explanations without invented citations',async()=>{
 let calls=0;const result=await createCompanionAnswer({passage,question:'良心とは何ですか？',spoilerAllowed:false,sources:[],modelId:DEFAULT_MODEL_ID},{authorization:offlineFixtureAuthorization('alice',DEFAULT_MODEL_ID),answerMode:'grounded-generation',allowGeneralKnowledge:true,ai:{async run(){calls++;return{response:JSON.stringify({status:'answer',claims:[],generalText:'一般的に、良心は自分の行動を善悪の観点から振り返る働きを指します。'})};}}});
 expect(calls).toBe(1);expect(result.answer).not.toContain('一般的な説明（出典未確認）');expect(result.citations).toEqual([]);expect(result.status).toBe('answered');expect(result.validation.semanticGrounding).toBe('unverified');
});
it('strict mode still stops without sources',async()=>{
 let calls=0;const result=await createCompanionAnswer({passage,question:'良心とは？',spoilerAllowed:false,sources:[],modelId:DEFAULT_MODEL_ID},{authorization:offlineFixtureAuthorization('alice',DEFAULT_MODEL_ID),answerMode:'grounded-generation',ai:{async run(){calls++;throw Error('must not run');}}});expect(calls).toBe(0);expect(result.status).toBe('insufficient-evidence');
});
it('general text cannot smuggle URLs, unrecognized citation objects or explicit future references',()=>{
 for(const object of [{status:'answer',claims:[],generalText:'https://invented.test'}, {status:'answer',claims:[],generalText:'使徒24:1で起きることです。'}, {status:'answer',claims:[],generalText:'背景です。',citations:[{sourceId:'invented'}]}])expect(()=>validateGeneralAnswer(JSON.stringify(object),[],passage,false)).toThrow('INVALID_RESPONSE');
 expect(()=>validateGeneralAnswer(JSON.stringify({status:'answer',claims:[{text:'未検証の主張',kind:'fact',sourceId:'invented',evidenceQuote:'fake'}],generalText:'背景です。'}),[],passage,false)).toThrow('INVALID_RESPONSE');
});
