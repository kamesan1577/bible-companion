"""Local candidate only. Does not touch the public checkout or grant publication approval."""
from pathlib import Path
import json,hashlib,copy,datetime
N=Path(__file__).resolve().parent;C=N/'candidate';R=C/'apps/ios/Sources/Core/Resources'
report={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'published':False,'independentApproval':False,'resources':[],'policies':{},'errors':[]}
for book in ['NUM','JOS']:
 f=N/f'integrated-staging/entity-profiles-{book}.json';d=json.loads(f.read_text());profiles={p['id']:p for p in d['profiles']};items=[];seen=set()
 for i in [1,2,3]:
  for row in json.loads((N/f'reviews/map-policy-places_{i}.json').read_text())['items']:
   if row['book']!=book:continue
   eid=row['id'];p=profiles.get(eid)
   if not p:continue
   if eid in seen:report['errors'].append({'type':'duplicate-map-policy','book':book,'id':eid});continue
   seen.add(eid);gate=row.get('allowFrom')
   if isinstance(gate,list):gate=min(gate,key=lambda x:(x['chapter'],x['verse'])) if gate else None
   gate=gate or p['knownBy'];gate=max([gate,p['knownBy']],key=lambda x:(x['chapter'],x['verse']))
   items.append({'id':eid,'allowCandidateMap':bool(row.get('allowCandidateMap')),'allowFrom':gate,'displayNoteJa':'従来の参考位置候補です。古代地点との一致や正確な位置は独立検証できていません。'+(p.get('modernLocationJa') or p.get('locationNoteJa') or '')})
 out=R/f'{book.lower()}-map-policy.json';out.write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n');report['policies'][book]={'records':len(items),'allowed':sum(x['allowCandidateMap'] for x in items),'newIndependentlyVerifiedCoordinates':0}
 out=R/f.name;out.write_bytes(f.read_bytes());report['resources'].append({'file':str(out.relative_to(C)),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
f=C/'apps/ios/Sources/Core/BundledEntityIndex.swift';s=f.read_text().replace('["ROM", "LEV"]','["ROM", "LEV", "NUM", "JOS"]').replace('["ACT", "ROM", "LEV"]','["ACT", "ROM", "LEV", "NUM", "JOS"]');f.write_text(s)
f=C/'apps/ios/Sources/DesignSystem/OfflineEntityPane.swift';s=f.read_text().replace('["ACT", "ROM", "LEV"]','["ACT", "ROM", "LEV", "NUM", "JOS"]');f.write_text(s)
(N/'candidate-activation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
if report['errors']:raise SystemExit(1)
