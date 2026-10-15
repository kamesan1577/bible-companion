"""Current-byte binding only. Content judgments come from independent source reviews."""
from pathlib import Path
import json,hashlib,datetime,collections
N=Path(__file__).resolve().parent;sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
reports={'persons_1':'finalclosure-persons_1-final.json','persons_2':'finalclosure-persons_2-final.json','persons_3':'finalclosure-persons_3-final.json','places_1':'final-closure-places_1.json','places_2':'finalclosure-places_2-final.json','places_3':'closure-current-all-places_3.json'}
results=[];errors=[];allrows=[]
for group,name in reports.items():
 f=N/'reviews'/name;d=json.loads(f.read_text());rows=d.get('records')or d.get('entries');expected={str(p.relative_to(N))for p in(N/'drafts'/group).glob('*.json')if p.name!='progress.json'};seen=set();statuses=collections.Counter();issues=[];entries=[]
 for r in rows:
  p=r['draftPath'];current=sha(N/p);seen.add(p);reviewed=r.get('currentDraftSHA256')or r.get('draftSHA256')
  if reviewed!=current:issues.append({'type':'stale-reviewed-draft','path':p,'reviewedSHA256':reviewed,'currentSHA256':current})
  status=r.get('currentRecordStatus')or r.get('currentClosureStatus')or r.get('overallStatus')or r.get('readerClosureStatus')or r.get('status');statuses[status]+=1
  if status and any(w in status.lower()for w in ['fail','open','pending']):issues.append({'type':'unresolved-current-review','path':p,'status':status})
  ep=r.get('currentEvidencePath')or r.get('evidencePath');eh=r.get('currentEvidenceSHA256')
  if ep and eh and sha(N/ep)!=eh:issues.append({'type':'stale-reviewed-evidence','path':ep,'reviewedSHA256':eh,'currentSHA256':sha(N/ep)})
  entry={'draftPath':p,'currentDraftSHA256':current,'reviewReport':str(f.relative_to(N)),'reviewReportSHA256':sha(f),'currentReviewStatus':status,'profileExcluded':json.loads((N/p).read_text()).get('profile')is None};entries.append(entry);allrows.append(entry)
 if seen!=expected or len(rows)!=len(expected):issues.append({'type':'coverage-mismatch','expected':len(expected),'rows':len(rows),'missing':sorted(expected-seen),'extra':sorted(seen-expected)})
 errors.extend(dict(group=group,**i)for i in issues);results.append({'group':group,'report':str(f.relative_to(N)),'reportSHA256':sha(f),'drafts':len(expected),'rows':len(rows),'statusCounts':dict(statuses),'issues':issues})
O=N/'reviews/root-final-main-review-bindings.json';O.write_text(json.dumps({'checkedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'byte binding of existing independent source-review decisions, not independent semantic approval by this script','groups':results,'records':allrows,'errors':errors},ensure_ascii=False,indent=2)+'\n');print(json.dumps({'drafts':len(allrows),'errors':len(errors),'issues':errors[:20]},ensure_ascii=False))
