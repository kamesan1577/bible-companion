/** Offline planning/review queue. This module cannot call providers or deploy resources. */
import {readFileSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
export const counts=JSON.parse(readFileSync(new URL('../packages/core/src/verse-counts.json',import.meta.url)));
export const VERSION='chapter-and-verse-ja-v1';
export const SAMPLES=['GEN:1','GEN:5','EXO:20','LEV:16','JOB:3','PSA:23','PSA:119','PRO:26','ECC:3','SNG:2','ISA:53','DAN:7','MAT:5','LUK:3','JHN:1','ACT:18','ROM:9','PHM:1','REV:13'];
export function inventory(){return Object.entries(counts).flatMap(([book,chapters])=>chapters.map((n,i)=>({key:`${book}:${i+1}`,book,chapter:i+1,verses:n})));}
export function estimate({inputTokens=3000,verseOutputTokens=180,chapterOutputTokens=600,versesPerCall=8,dailyBatchNeurons=500,rework=0.25}={}){
 const chapters=inventory(),verses=chapters.reduce((n,c)=>n+c.verses,0);
 const calls=chapters.reduce((n,c)=>n+Math.ceil(c.verses/versesPerCall)+1,0);
 const input=calls*inputTokens,output=verses*verseOutputTokens+chapters.length*chapterOutputTokens;
 const neurons=(input*9091+output*27273)/1e6*(1+rework);
 return {books:Object.keys(counts).length,chapters:chapters.length,verses,estimatedCalls:calls,versesPerCall,inputTokens:input,outputTokens:output,rework,estimatedNeurons:Math.ceil(neurons),dailyBatchNeurons,minimumDays:Math.ceil(neurons/dailyBatchNeurons),paidEquivalentUSD:neurons/1000*0.011,assumption:'Planning only; excludes independent editorial labor. Actual tokens, reasoning, retries and source size can increase consumption.'};
}
export function init(db,variant){
 if(!variant.translation||!variant.sourceVersion||!variant.model||!variant.boundaryPolicy)throw Error('Explicit translation/source/model/boundary required');
 db.exec(`CREATE TABLE IF NOT EXISTS corpus_jobs(key TEXT PRIMARY KEY, chapter_key TEXT NOT NULL, variant TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'missing',lease TEXT,lease_until INTEGER NOT NULL DEFAULT 0,result TEXT,review TEXT,updated INTEGER NOT NULL DEFAULT 0); CREATE TABLE IF NOT EXISTS corpus_budget(day TEXT PRIMARY KEY,reserved REAL NOT NULL DEFAULT 0);`);
 const json=JSON.stringify({...variant,version:VERSION});
 const insert=db.prepare('INSERT OR IGNORE INTO corpus_jobs(key,chapter_key,variant)VALUES(?,?,?)');
 db.exec('BEGIN IMMEDIATE');try{for(const c of inventory()){const key=createHash('sha256').update(c.key+json).digest('hex');insert.run(key,c.key,json);}db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}
}
/** Reserve conservatively: unknown consumption never refunds. Batch defaults disabled. */
export function claim(db,{now=Date.now(),estimatedNeurons,enabled=false,freeVerified=false,foregroundNeurons=Infinity,dailyCap=500,appCap=9000,foregroundReserve=2000}={}){
 if(!enabled||!freeVerified||!Number.isFinite(estimatedNeurons)||estimatedNeurons<=0||dailyCap>500||dailyCap<=0||!Number.isFinite(foregroundNeurons))return null;
 const day=new Date(now).toISOString().slice(0,10),token=randomUUID();
 db.exec('BEGIN IMMEDIATE');try{
 db.prepare('INSERT OR IGNORE INTO corpus_budget(day)VALUES(?)').run(day);
 const used=db.prepare('SELECT reserved FROM corpus_budget WHERE day=?').get(day).reserved;
 if(used+estimatedNeurons>dailyCap||foregroundNeurons+used+estimatedNeurons+foregroundReserve>appCap){db.exec('COMMIT');return null;}
 const row=db.prepare("SELECT key,chapter_key,variant FROM corpus_jobs WHERE state IN ('missing','failed','generating') AND lease_until<=? ORDER BY chapter_key LIMIT 1").get(now);
 if(!row){db.exec('COMMIT');return null;}
 db.prepare("UPDATE corpus_jobs SET state='generating',lease=?,lease_until=?,updated=? WHERE key=?").run(token,now+300000,now,row.key);
 db.prepare('UPDATE corpus_budget SET reserved=reserved+? WHERE day=?').run(estimatedNeurons,day);
 db.exec('COMMIT');return {...row,token};
 }catch(e){db.exec('ROLLBACK');throw e;}
}
/** Structural gate is necessary, never a claim of factual or editorial correctness. */
export function inspect(result,chapter){
 const errors=[],expected=counts[chapter.book]?.[chapter.chapter-1];
 if(result?.version!==VERSION||result?.chapterKey!==chapter.key)errors.push('identity/version');
 if(typeof result?.backgroundJa!=='string'||result.backgroundJa.trim().length<40)errors.push('chapter background');
 if(!Array.isArray(result?.verses)||result.verses.length!==expected)errors.push('verse coverage');
 const seen=new Set();
 for(const v of result?.verses??[]){
 if(!Number.isInteger(v.verse)||v.verse<1||v.verse>expected||seen.has(v.verse))errors.push('verse identity');seen.add(v.verse);
 if(typeof v.meaningJa!=='string'||v.meaningJa.trim().length<30)errors.push('verse meaning');
 if(!Array.isArray(v.evidence)||!v.evidence.length||v.evidence.some(e=>e.book!==chapter.book||e.chapter!==chapter.chapter||e.verse>v.verse||e.verse<1||!e.sourceVersion||!e.translation))errors.push('bounded evidence');
 if(!Array.isArray(v.entities)||v.entities.some(e=>!e.id||!['person','place'].includes(e.kind)||!e.roleJa||!['identified','uncertain'].includes(e.identity)))errors.push('entity identity/role');
 if(!Array.isArray(v.uncertainties)||typeof v.translationNoteJa!=='string')errors.push('uncertainty/translation');
 }
 return [...new Set(errors)];
}
export function saveGenerated(db,job,result){
 const [book,ch]=job.chapter_key.split(':'),errors=inspect(result,{key:job.chapter_key,book,chapter:Number(ch)});
 if(errors.length)throw Error(errors.join(', '));
 return db.prepare("UPDATE corpus_jobs SET state='generated',result=?,lease_until=0,updated=? WHERE key=? AND lease=? AND state='generating'").run(JSON.stringify(result),Date.now(),job.key,job.token).changes===1;
}
export function review(db,key,{reviewer,evidenceChecked,translationChecked,identityChecked,spoilerChecked,interpretationChecked,notes}={}){
 if(!reviewer||!notes||![evidenceChecked,translationChecked,identityChecked,spoilerChecked,interpretationChecked].every(x=>x===true))throw Error('Recorded review of all quality dimensions required');
 return db.prepare("UPDATE corpus_jobs SET state='verified',review=?,updated=? WHERE key=? AND state='generated'").run(JSON.stringify({reviewer,evidenceChecked,translationChecked,identityChecked,spoilerChecked,interpretationChecked,notes,at:new Date().toISOString()}),Date.now(),key).changes===1;
}
export function coverage(db){return db.prepare('SELECT state,count(*) chapters FROM corpus_jobs GROUP BY state').all();}
