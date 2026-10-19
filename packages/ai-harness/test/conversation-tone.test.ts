import {it, expect} from 'vitest';
import {ACTS_SOURCES} from '../fixtures/acts-sources';
import {offlineFixtureAuthorization} from '../fixtures/authorization';
import {prepareCompanionRequest, validateGeneralAnswer, DEFAULT_MODEL_ID} from '../src/index';
import {questionContextWindow} from '../../core/src/index';
const passage={book:'ACT',start:{chapter:26,verse:32},end:{chapter:26,verse:32}};
const scope={passage,spoilerAllowed:false,sourceIds:[],sourceVersions:{}};
const questions=['じゃあパウロは上訴しなければよかったの？','パウロってバカだったってこと？','結局なんで上訴したの？','上訴って？','そのときの本当の内心は？'];
it('keeps the three screenshot followups and asks for a reasoned direct answer, without weakening citations',()=>{
 const history: {role:'user'|'assistant';content:string;ownerId:string;scope:typeof scope}[]=[];
 for(const question of questions){
  const request=prepareCompanionRequest({passage,question,spoilerAllowed:false,sources:[],history},{authorization:offlineFixtureAuthorization('alice',DEFAULT_MODEL_ID),answerMode:'grounded-generation',allowGeneralKnowledge:true});
  const data=JSON.parse(request.messages[1].content);
  expect(data.question).toBe(question);expect(data.history).toHaveLength(Math.min(history.length,6));
  expect(request.messages[0].content).toContain('字義通りの拒否をしません');
  expect(request.messages[0].content).toContain('その見立ての理由');
  expect(request.messages[0].content).toContain('実際に不明な内心を区別');
  history.push({role:'user',content:question,ownerId:'alice',scope},{role:'assistant',content:'前の質問への見立てと理由',ownerId:'alice',scope});
 }
});
it('renders narrative first, keeps supporting citations, rejects invented evidence, and allows a genuine unknown',()=>{
 const source=ACTS_SOURCES[0];
 const text='そう単純には言えません。その場の判断と後から見た結果は分けて考える必要があります。';
 const claims=[{text:'本文にある出来事',kind:'fact',sourceId:source.id,evidenceQuote:source.text.slice(0,30)}];
 const result=validateGeneralAnswer(JSON.stringify({status:'answer',generalText:text,claims}),[source],passage,true);
 expect(result.answer).toBe(text);expect(result.citations).toHaveLength(1);expect(result.claims).toHaveLength(1);
 expect(()=>validateGeneralAnswer(JSON.stringify({status:'answer',generalText:text,claims:[{...claims[0],evidenceQuote:'invented quotation'}]}),[source],passage,true)).toThrow();
 expect(validateGeneralAnswer(JSON.stringify({status:'answer',claims:[],generalText:'本人がその瞬間に何を感じたかまでは分かりません。行動と状況からの見立てはできます。'}),[],passage,false).answer).toContain('その瞬間');
});
it('can retrieve the earlier appeal scene for Acts26:32 while preserving selection and spoiler end',()=>{
 const window=questionContextWindow(passage,passage,true);
 expect(window.start.chapter).toBeLessThanOrEqual(25);expect(window.end).toEqual(passage.end);
});
// These assertions test transport, prompt and validation contracts. They are not live Gemma quality scores.
