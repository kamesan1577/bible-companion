#!/usr/bin/env python3
"""Validate candidates without changing app/editorial data. No model or network access."""
import argparse,gzip,importlib.util,json
from pathlib import Path
spec=importlib.util.spec_from_file_location('jobs',Path(__file__).with_name('codex-jobs.py'));jobs=importlib.util.module_from_spec(spec);spec.loader.exec_module(jobs)
def inspect(path):
 candidate=jobs.read(path);entries=candidate.get('entries',[]);reviews={r['draftSha256']:r for r in candidate.get('reviews',[])};resource=jobs.ROOT/'apps/ios/Sources/Core/Resources';catalog=jobs.read(resource/'commentary-catalog.json');units={};primary={};index=jobs.read(resource/'entity-index.json');seen=set();occupied=set();results=[]
 with gzip.open(jobs.ROOT/'data/scripture/webp-2026-10-13/verses.ndjson.gz','rt')as f:
  for line in f:
   r=json.loads(line);c=r.get('canonical')
   if c and r.get('text'):primary[f"{c['book']}:{c['chapter']}:{c['verse']}"]=r['text']
 for entry in entries:
  errors=[];p=entry.get('passage',{});book=p.get('book');start=p.get('start',{});end=p.get('end',{});counts=jobs.read(jobs.ROOT/'packages/core/src/verse-counts.json').get(book,[])
  if not isinstance(start.get('chapter'),int)or not 1<=start['chapter']<=len(counts)or start.get('chapter')!=end.get('chapter')or not isinstance(start.get('verse'),int)or not isinstance(end.get('verse'),int)or not 1<=start['verse']<=end['verse']<=counts[start['chapter']-1]:results.append({'id':entry.get('id'),'errors':['invalid range']});continue
  refs={f"{book}:{start['chapter']}:{v}"for v in range(start['verse'],end['verse']+1)}
  if entry.get('id')in seen or occupied.intersection(refs):errors.append('duplicate entry/range')
  seen.add(entry.get('id'));occupied|=refs
  if not refs<=primary.keys():errors.append('missing primary text; do not invent/assume KJV-WEB alignment')
  if book not in units:
   units[book]={}
   for edition in ['MHC','JFB']:
    rec=catalog['files'][edition+':'+book];raw=(resource/rec['file']).read_bytes();assert jobs.sha(raw)==rec['sha256'];units[book].update({u['id']:u for u in json.loads(raw)})
  known=units[book];sources=[known[k]for k in entry.get('sourceUnitIds',[])if isinstance(k,str)and k in known];bn=index['books'].index(book)+1;entities=[e for e in index['entities']if any(bn*1000000+start['chapter']*1000+v in e['appearances']for v in range(1,end['verse']+1))]
  packet={'passage':p,'sources':sources,'primaryText':{r:primary[r]for r in refs if r in primary},'entityCandidates':entities};errors+=jobs.inspect_entry(entry,packet);review=reviews.get(jobs.sha(entry))
  if not review or review.get('verdict')!='pass'or not all(review.get(k)is True for k in ['sourceCompared','primaryCompared','identityCompared','spoilerCompared','interpretationSeparated']):errors.append('separate source review not bound to exact draft')
  results.append({'id':entry.get('id'),'errors':sorted(set(errors)),'sourceReviewRecorded':bool(review),'expertReview':False})
 return {'candidate':str(path),'entries':len(entries),'detailedCoordinates':len(occupied),'mechanicalPass':bool(entries)and all(not r['errors']for r in results),'semanticAccuracyProvenByThisProgram':False,'appChanged':False,'results':results}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('candidate',type=Path);p.add_argument('--report',type=Path);args=p.parse_args();result=inspect(args.candidate)
 if args.report:jobs.write(args.report,result)
 print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(0 if result['mechanicalPass']else 1)
