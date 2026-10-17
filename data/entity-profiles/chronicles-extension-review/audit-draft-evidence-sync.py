"""Check current authoring sidecars against actual draft/profile bytes; no semantic approval."""
from pathlib import Path
import hashlib,json
K=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rows=[];errors=[]
for draft in sorted((K/'drafts').glob('*/*.json')):
 d=json.loads(draft.read_text());r=d.get('review',{});p=d.get('profile');book=r.get('book')or d.get('book');eid=(p or{}).get('id')or r.get('entityID')
 if not book or not eid:continue
 primary=[K/'evidence'/draft.parent.name/(draft.stem+suffix) for suffix in ['.json','-sources.json']]
 found=[x for x in primary if x.exists()]
 row={'draftPath':str(draft.relative_to(K)),'book':book,'id':eid,'draftSHA256':sha(draft),'evidencePaths':[str(f.relative_to(K))for f in found],'errors':[]}
 if len(found)!=1:row['errors'].append('missing-or-ambiguous-primary-sidecar')
 else:
  e=json.loads(found[0].read_text());row['evidenceSHA256']=sha(found[0]);row['profileSHA256']=hashlib.sha256((json.dumps(p,ensure_ascii=False,indent=2)+'\n').encode()).hexdigest() if p else None
  if e.get('draftSHA256')!=row['draftSHA256']:row['errors'].append('draft-hash-stale')
  if p and e.get('profileSHA256')!=row['profileSHA256']:row['errors'].append('profile-hash-stale')
 rows.append(row)
 errors.extend({'draftPath':row['draftPath'],'error':error}for error in row['errors'])
report={'records':rows,'counts':{'rawPairs':len(rows),'sidecarIssues':len(errors)},'errors':errors,'semanticApproval':False,'publicationApproved':False}
(K/'reviews/root-draft-evidence-sync.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'counts':report['counts'],'errors':errors},ensure_ascii=False))
raise SystemExit(bool(errors))
