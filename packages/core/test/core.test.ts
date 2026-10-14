import {describe,it,expect} from 'vitest';
import {parseImport,normalizeBook,passageSchema,withinBoundary,cacheKey} from '../src/index';
describe('canonical imports',()=>{
 it.each(['使徒18:18','使徒の働き 18章18節','Acts 18:18','ACT.18:18','使徒言行録１８：１８'])('parses %s',input=>{expect(parseImport(input).ranges).toEqual([{book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}}]);});
 it('accepts ranges and does not collapse gaps',()=>{expect(parseImport('使徒18:12–16,18').ranges.map(x=>[x.start.verse,x.end.verse])).toEqual([[12,16],[18,18]]);});
 it('accepts cross chapter range',()=>{expect(parseImport('使徒18:28–19:3').ranges[0].end).toEqual({chapter:19,verse:3});});
 it('parses YouVersion but does not assume numeric version IDs',()=>{expect(parseImport('https://www.bible.com/bible/83/ACT.18.18.JCB')).toMatchObject({translation:'JCB',ranges:[{book:'ACT'}]});expect(parseImport('https://www.bible.com/bible/83/ACT.18.18').translation).toBeNull();});
 it('keeps ambiguity explicit',()=>{expect(parseImport('髪を切った理由は？').needsConfirmation).toBe(true);expect(normalizeBook('偽書')).toBeUndefined();});
 it.each(['使徒18:29','使徒29:1','使徒18:18-17','使徒0:1'])('rejects %s',text=>{expect(()=>parseImport(text)).toThrow();});
 it('rejects unknown books',()=>{expect(passageSchema.safeParse({book:'fake',start:{chapter:1,verse:1},end:{chapter:1,verse:1}}).success).toBe(false);});
});
describe('privacy cache/boundary',()=>{
 const passage={book:'ACT',start:{chapter:18,verse:18},end:{chapter:18,verse:18}};
 it('rejects future and cross-book data',()=>{expect(withinBoundary({...passage,end:{chapter:19,verse:1}},passage)).toBe(false);expect(withinBoundary({...passage,book:'GEN'},passage)).toBe(false);});
 it('separates owners and model versions',async()=>{const base={passage,translation:'JCB',language:'ja',spoilerAllowed:false,provider:'cloudflare-workers-ai',modelId:'a',modelVersion:'1',promptVersion:'1',settings:{temperature:0.2},sourceVersion:'1'};const keys=await Promise.all([base,{...base,ownerId:'a'},{...base,ownerId:'b'},{...base,modelVersion:'2'},{...base,spoilerAllowed:true}].map(cacheKey));expect(new Set(keys).size).toBe(5);});
});
