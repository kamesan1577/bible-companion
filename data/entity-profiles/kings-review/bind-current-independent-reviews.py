"""Bind current drafts to saved substantive independent profile reviews; never creates approval."""
from pathlib import Path
import json,hashlib,datetime,re
N=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
drafts={str(p.relative_to(N)):p for p in sorted((N/'drafts').glob('*/*.json')) if p.name!='progress.json'}
byhash={sha(p):r for r,p in drafts.items()}
evidenceByHash={sha(p):str(p.relative_to(N)) for p in (N/'evidence').glob('*/*.json')}
refs={};errors=[];used=[];currentAdverse=[]
for f in sorted((N/'reviews').glob('*.json')):
 name=f.name
 if not re.match(r'(?:independent-(?:pharaoh-|validator-|persons_|places_|extra-|reclosure-|2KI-)|reclosure-(?:persons_|persons3-|places_|independent-extra-|2KI-)|closure-(?:independent-extra-|persons_|places_|current-places_|extra-|reader-|wikipedia-article-|2KI-|philistia-|gibeah)|final-?closure-persons_)',name):continue
 if any(x in name for x in ['format-fix','source-map']):continue
 d=json.loads(f.read_text());rows=[]
 for k in ['rows','items','entries','records','profiles','checks','reviewItems','results']:
  if isinstance(d.get(k),list):rows.extend(x for x in d[k]if isinstance(x,dict))
 for k in ['item','entry']:
  if isinstance(d.get(k),dict):rows.append(d[k])
 if any(k in d for k in ['currentDraftSHA256','draftSHA256','currentHashes']):rows.append(d)
 for row in rows:
  if isinstance(row.get('independentReclosure'),dict):row={**row,**row['independentReclosure']}
  hashes=row.get('currentSHA256')or row.get('currentHashes')or{}
  expected=row.get('currentDraftSHA256')or row.get('draftSHA256')or((hashes.get('draft')or hashes.get('draftSHA256'))if isinstance(hashes,dict)else None)
  rel=row.get('draftPath')or row.get('draft')or row.get('file')or byhash.get(expected)
  if not rel:continue
  if str(rel).startswith(str(N)):rel=str(Path(rel).relative_to(N))
  if '/'not in rel:
   ms=[r for r in drafts if Path(r).name==rel]
   if len(ms)!=1:errors.append({'ambiguousPath':rel,'review':name});continue
   rel=ms[0]
  if rel not in drafts or expected!=sha(drafts[rel]):continue
  verdict=next((row[k]for k in ['currentDecision','independentStatus','decision','verdict','overallStatus','result','status','reclosureStatus']if isinstance(row.get(k),str)),None)
  if not verdict:verdict=d.get('overallDecision')or d.get('decision')
  if not isinstance(verdict,str):continue
  good=verdict.startswith(('pass','qualified','closed-qualified','closed-pass')) or verdict in ['excluded','null-excluded','not-applicable-excluded']
  # A qualified-open or explicitly unresolved row cannot close a publication record.
  if any(word in verdict.lower() for word in ['open','pending','fail']):good=False
  if row.get('publicationBlocking') or row.get('blockingFindings') or row.get('unresolvedSearchEvidence'):good=False
  evidenceHash=row.get('currentEvidenceSHA256')or row.get('evidenceSHA256')or((hashes.get('evidence')or hashes.get('evidenceSHA256'))if isinstance(hashes,dict)else None)
  if not evidenceHash or evidenceHash not in evidenceByHash:good=False
  if not good:currentAdverse.append({'draftPath':rel,'draftSHA256':expected,'reviewPath':'reviews/'+name,'verdict':verdict})
  if good:refs.setdefault(rel,[]).append({'reviewPath':'reviews/'+name,'reviewSHA256':sha(f),'verdict':verdict,'draftSHA256':expected,'evidenceSHA256':row.get('currentEvidenceSHA256')or row.get('evidenceSHA256')or((hashes.get('evidence')or hashes.get('evidenceSHA256'))if isinstance(hashes,dict)else None)})
  used.append(name)
records=[]
for rel,p in drafts.items():
 d=json.loads(p.read_text());pr=d.get('profile');rv=d.get('review',{});good=refs.get(rel,[])
 if not good:errors.append({'unclosedCurrentDraft':rel})
 records.append({'draftPath':rel,'currentDraftSHA256':sha(p),'book':rv.get('book')or d.get('book'),'entityID':rv.get('entityID')or(pr or{}).get('id'),'profilePresent':bool(pr and pr.get('passages')),'independentCurrentReferences':good})
out={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'method':'Current raw draft SHA is matched to substantive saved independent profile-review rows. Hash matching does not replace semantic review. Stale and historical failed reports remain preserved.','currentAdverseReviewRows':currentAdverse,'records':records,'counts':{'drafts':len(records),'bound':sum(bool(r['independentCurrentReferences'])for r in records)},'errors':errors,'publicationApproved':False}
(N/'reviews/root-final-main-review-bindings.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'counts':out['counts'],'errors':errors},ensure_ascii=False))
