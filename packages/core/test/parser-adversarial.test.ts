import {describe,it,expect} from 'vitest';
import counts from '../src/verse-counts.json';
import {BOOKS,parseImport,passageSchema} from '../src/index';
describe('all canonical endpoints',()=>{
 it('validates all 1189 chapter endpoints and refuses the next verse',()=>{let chapters=0,verses=0;for(const book of BOOKS){const list=(counts as Record<string,number[]>)[book.id];expect(list.length).toBe(book.chapters);for(let index=0;index<list.length;index++){chapters++;verses+=list[index];const p={book:book.id,start:{chapter:index+1,verse:1},end:{chapter:index+1,verse:list[index]}};expect(passageSchema.safeParse(p).success).toBe(true);expect(passageSchema.safeParse({...p,end:{...p.end,verse:list[index]+1}}).success).toBe(false);}}expect(chapters).toBe(1189);expect(verses).toBe(31102);});
 it.each(BOOKS.map(b=>[b.ja,b.id]))('parses Japanese %s',(name,id)=>{expect(parseImport(`${name}1:1`).ranges[0].book).toBe(id);});
 it.each(BOOKS.map(b=>[b.en,b.id]))('parses English %s',(name,id)=>{expect(parseImport(`${name} 1:1`).ranges[0].book).toBe(id);});
});
describe('range and URL edge cases',()=>{
 it.each(['使徒18:1,3,8','Acts 18.1,3,8','ACT.18:1,3,8','使徒18章1節、3節、8節'])('keeps discontinuous selection %s',s=>expect(parseImport(s).ranges.map(p=>p.start.verse)).toEqual([1,3,8]));
 it('retains confirmed translation for parenthesized full-width input',()=>expect(parseImport('使徒１８章１８節（ＪＣＢ）').translation).toBe('JCB'));
 it.each(['使徒18:18-19:','使徒18:18-19:abc','使徒18:18,,20','使徒18:18-','使徒18:18-999','使徒18:18,0','創世記1:32','ヨハネの黙示録22:22'])('does not truncate invalid selection %s',s=>expect(()=>parseImport(s)).toThrow());
 it('canonicalizes a shared URL and strips tracking/private query and fragment',()=>{const out=parseImport('(https://www.bible.com/ja/bible/83/ACT.18.18.JCB?utm_source=private#token)');expect(out.sourceUrl).toBe('https://www.bible.com/ja/bible/83/ACT.18.18.JCB');expect(out.translation).toBe('JCB');});
 it('accepts URL cross-chapter ranges',()=>expect(parseImport('https://bible.com/bible/83/ACT.18.28-19.3.JCB').ranges[0].end).toEqual({chapter:19,verse:3}));
 it.each(['https://bible.com.evil.test/bible/83/ACT.18.18.JCB','https://evil.test/?u=https%3A%2F%2Fbible.com%2Fbible%2F83%2FACT.18.18.JCB','https://bible.com/bible/83/FAKE.18.18.JCB','https://bible.com/bible/83/ACT.18.18.JCB/extra'])('leaves unrecognized URL for confirmation %s',s=>expect(parseImport(s).ranges).toEqual([]));
 it('unknown translation stays explicit',()=>expect(parseImport('使徒18:18 XYZ').translation).toBeNull());
 it('ignores bounded blank lines without changing parsed references',()=>{expect(parseImport('\n'.repeat(20000))).toEqual(parseImport(''));expect(parseImport(' \t\n'.repeat(4997)+'Acts 18:17')).toEqual(parseImport('Acts 18:17'));});
 it('bounded input',()=>expect(()=>parseImport('x'.repeat(20001))).toThrow());
});
describe('Japanese numbered-book aliases',()=>{
 it.each([['コリント人への手紙Ⅰ 1:1','1CO'],['コリント第一1:1','1CO'],['第二コリント1:1','2CO'],['サムエル記Ⅱ1:1','2SA'],['ヨハネの手紙Ⅲ1:1','3JN']])('normalizes %s',(name,id)=>expect(parseImport(name).ranges[0].book).toBe(id));
});
describe('ambiguous shared selections never truncate silently',()=>{
 it.each(['Acts18:18 JCB\nActs19:1 JCB','https://bible.com/bible/83/ACT.18.18.JCB\nhttps://bible.com/bible/83/ACT.19.1.JCB','Acts18:18 JCB\nJohn3:16 JCB','Acts18:18 JCB\nActs18:18 NIV','Acts18:18;19:1'])('requests confirmation for %s',text=>{const parsed=parseImport(text);expect(parsed.ranges).toEqual([]);expect(parsed.needsConfirmation).toBe(true);});
 it('accepts matching URL plus explicit text without duplicate import ranges',()=>{const parsed=parseImport('使徒18:18 JCB\nhttps://bible.com/bible/83/ACT.18.18.JCB');expect(parsed.ranges).toHaveLength(1);expect(parsed.translation).toBe('JCB');expect(parsed.needsConfirmation).toBe(false);});
});
