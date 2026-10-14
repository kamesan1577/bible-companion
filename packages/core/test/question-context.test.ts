import {describe,it,expect} from 'vitest';
import {questionContextWindow,type Passage} from '../src/index';
const range=(book:string,a:number,b:number,c:number,d:number):Passage=>({book,start:{chapter:a,verse:b},end:{chapter:c,verse:d}});
describe('bounded question context',()=>{
 it('keeps a late target visible and stops at the confirmed end',()=>{
  expect(questionContextWindow(range('PSA',119,1,119,176),range('PSA',119,176,119,176))).toEqual(range('PSA',119,168,119,176));
 });
 it('walks canonical chapter boundaries without inventing verse zero',()=>{
  expect(questionContextWindow(range('GEN',1,1,2,10),range('GEN',2,1,2,1))).toEqual(range('GEN',1,24,2,9));
 });
 it('never displaces a long selected target with preceding context',()=>{
  const target=range('PSA',119,100,119,150);
  expect(questionContextWindow(range('PSA',119,1,119,176),target)).toEqual(target);
 });
 it('rejects invalid, cross-book and out-of-bound targets',()=>{
  for(const target of [range('GEN',1,0,1,1),range('EXO',1,1,1,1),range('GEN',2,1,2,2)]) expect(()=>questionContextWindow(range('GEN',1,1,1,31),target)).toThrow();
 });
});
