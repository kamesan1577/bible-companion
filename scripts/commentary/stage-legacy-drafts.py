#!/usr/bin/env python3
"""Preserve legacy drafts, choose current variants and audit; never certify or merge them."""
import argparse,collections,gzip,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def parse_reference(text):
 m=re.search(r'(\d+):(\d+)(?:[–−-](\d+))?',text);assert m,'Unrecognized reference: '+text;c,s,e=m.groups();return int(c),int(s),int(e or s)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--input',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();assert not a.output.exists();a.output.mkdir(parents=True)
 selected=sorted((a.input/'bible-luna-batches/acts01-08').glob('acts*.json'))+sorted((a.input/'bible-luna-batches/acts09-12').glob('acts*.json'))+[a.input/'bible-luna-batches/acts13-17/acts13-14_ja.json',a.input/'bible-luna-batches/acts13-17/acts15-17_ja.json',a.input/'acts24-26-notes/acts26.json',a.input/'acts27-28-notes/acts27-28_ja.json']
 counts=json.loads((ROOT/'packages/core/src/verse-counts.json').read_text())['ACT'];primary={}
 with gzip.open(ROOT/'data/scripture/webp-2026-10-13/verses.ndjson.gz','rt')as f:
  for line in f:
   r=json.loads(line);c=r.get('canonical')
   if c and c['book']=='ACT' and r.get('text'):primary[f"ACT:{c['chapter']}:{c['verse']}"]=r['text']
 res=ROOT/'apps/ios/Sources/Core/Resources';catalog=json.loads((res/'commentary-catalog.json').read_text());rec=catalog['files']['JFB:ACT'];assert digest(res/rec['file'])==rec['sha256'];sources=json.loads((res/rec['file']).read_text());records=[];files=[]
 def add(c,s,e,row,sourcefile):
  errors=[]
  if not 1<=c<=len(counts)or not 1<=s<=e<=counts[c-1]:errors.append('invalid canonical range')
  refs=[f'ACT:{c}:{v}'for v in range(s,e+1)];summary=row.get('study_explanation_ja',row.get('explanation_ja',''));sentence_count=summary.count('。');missing=[r for r in refs if r not in primary]
  if e-s+1>8:errors.append('range over 8 verses; density rewrite needed')
  if not 2<=sentence_count<=4:errors.append('summary not 2-4 sentences')
  if missing:errors.append('KJV-to-local-WEB primary alignment gap')
  linked=[u for u in sources if any(r['start']['chapter']==c and r['start']['verse']<=e and s<=r['end']['verse']for r in u['ranges'])]
  if not linked:errors.append('no local JFB unit for range')
  entry={'id':f'ja-v1:ACT:{c}:{s}-{e}','passage':{'book':'ACT','start':{'chapter':c,'verse':s},'end':{'chapter':c,'verse':e}},'titleJa':row.get('title_ja',f'使徒{c}:{s}–{e}'),'summaryJa':summary,'authorInterpretationJa':row.get('jfb_commentary_summary_ja','原稿内のJFBによる説明を本文観察から分離する作業が必要です。'),'editorialNoteJa':'受領したLuna下書きです。原典との別段階の点検・人物ID照合・先読み検査は未完です。','sourceUnitIds':[],'evidence':[],'people':[],'editingMethod':'Codex gpt-6-luna source-based Japanese editorial summary; not a literal translation','reviewStatus':'draft-awaiting-independent-source-review; no expert review','spoilerEnd':{'chapter':c,'verse':e}}
  records.append({'entry':entry,'legacyInput':{'file':str(sourcefile.relative_to(a.input)),'fileSha256':digest(sourcefile),'record':row},'suggestedSourceUnits':[{'id':u['id'],'ranges':u['ranges'],'plainTextSha256':hashlib.sha256(u['originalText'].encode()).hexdigest()}for u in linked],'primaryText':{r:primary[r]for r in refs if r in primary},'missingPrimaryCoordinates':missing,'sourceBibleVersion':'KJV as declared by incoming author','localComparisonVersion':'WEB; not automatically equivalent to KJV/JCB','density':{'verses':e-s+1,'sentences':sentence_count},'mechanicalIssues':errors,'sourceComparison':'pending','identityComparison':'pending; never match by name only','spoilerComparison':'pending','readyForApp':False})
 for p in selected:
  assert p.is_file(),str(p);d=json.loads(p.read_text());rows=d.get('pericopes',d.get('notes',d.get('entries')));assert isinstance(rows,list),str(p);files.append({'file':str(p.relative_to(a.input)),'sha256':digest(p),'records':len(rows)})
  for row in rows:
   ref=row.get('reference',row.get('verse_range',row.get('refs','')));c,s,e=parse_reference(ref);add(c,s,e,row,p)
 for chapter in [24,25]:
  p=a.input/f'acts24-26-notes/acts{chapter}.md';text=p.read_text();matches=list(re.finditer(r'^###\s+(\d+):(\d+)(?:[–-](\d+))?[^\n]*\n',text,re.M));assert matches;files.append({'file':str(p.relative_to(a.input)),'sha256':digest(p),'records':len(matches)})
  for i,m in enumerate(matches):
   c,s,e=int(m[1]),int(m[2]),int(m[3]or m[2]);body=text[m.end():matches[i+1].start()if i+1<len(matches)else len(text)].strip();body=body.split('\n- ')[0].split('\n## ')[0].strip();add(c,s,e,{'reference':m[0].strip(),'title_ja':m[0].strip('# \n'),'explanation_ja':body,'originalMarkdownBody':text[m.end():matches[i+1].start()if i+1<len(matches)else len(text)]},p)
 seen=collections.Counter();bychapter=collections.defaultdict(list)
 for r in records:
  p=r['entry']['passage'];c=p['start']['chapter'];bychapter[c].append(r)
  for v in range(p['start']['verse'],p['end']['verse']+1):seen[(c,v)]+=1
 duplicates=[f'ACT:{c}:{v}'for(c,v),n in seen.items()if n>1];missing={str(c):[v for v in range(1,counts[c-1]+1)if(c,v)not in seen]for c in sorted(bychapter)}
 report={'schemaVersion':1,'selectionPolicy':'use combined acts27-28_ja.json; exclude older individual JSON and all duplicate Markdown renderings. Use chapter JSON for1-12, merged JSON13-17, JSON26, smallest Markdown subheadings24-25. Original inputs preserved untouched.','files':files,'selectedChapters':sorted(bychapter),'selectedRecords':len(records),'uniqueCoordinates':len(seen),'duplicateCoordinates':duplicates,'missingWithinSelectedChapters':missing,'rangeOver8Verses':[r['entry']['id']for r in records if r['density']['verses']>8],'sentenceDensityFailures':[r['entry']['id']for r in records if not 2<=r['density']['sentences']<=4],'primaryAlignmentGaps':sorted({x for r in records for x in r['missingPrimaryCoordinates']}),'allAreDrafts':True,'sourceReviewedCount':0,'appChanged':False,'records':records}
 (a.output/'staging.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items()if k not in ['records','files']},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
