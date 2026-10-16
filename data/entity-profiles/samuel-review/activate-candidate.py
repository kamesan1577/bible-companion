"""Local candidate only. Does not touch the public checkout or grant publication approval."""
from pathlib import Path
import json,hashlib,copy,datetime,re
N=Path(__file__).resolve().parent;C=N/'candidate';R=C/'apps/ios/Sources/Core/Resources'
assert not json.loads((N/'integrated-staging/report.json').read_text())['errors']
report={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'published':False,'independentApproval':False,'resources':[],'policies':{},'errors':[]}
for book in ['1SA','2SA']:
 f=N/f'integrated-staging/entity-profiles-{book}.json';d=json.loads(f.read_text());profiles={p['id']:p for p in d['profiles']};items=[];seen=set()
 for i in [1,2,3]:
  for row in json.loads((N/f'reviews/map-policy-places_{i}.json').read_text())['items']:
   if row['book']!=book:continue
   eid=row['id'];p=profiles.get(eid)
   if not p:continue
   if eid in seen:report['errors'].append({'type':'duplicate-map-policy','book':book,'id':eid});continue
   seen.add(eid);gate=row.get('allowFrom')
   if gate=='legacy-candidate-coordinate':
    report.setdefault('nativePolicyNormalizations',[]).append({'book':book,'id':eid,'originalAllowFrom':gate,'normalizedGate':p['knownBy'],'reason':'Author provenance tag is not a verse; candidate visibility starts no earlier than the reviewed profile introduction. No coordinate verification is promoted.'})
    gate=p['knownBy']
   if isinstance(gate,list):
    normalized=[]
    for value in gate:
     if isinstance(value,dict):normalized.append(value)
     elif isinstance(value,str):
      match=re.fullmatch(r'(1SA|2SA) (\d+):(\d+)',value)
      assert match and match[1]==book,('invalid-map-gate',eid,value)
      normalized.append({'chapter':int(match[2]),'verse':int(match[3])})
     else:raise ValueError(('invalid-map-gate',eid,value))
    gate=min(normalized,key=lambda x:(x['chapter'],x['verse'])) if normalized else None
   gate=gate or p['knownBy'];gate=max([gate,p['knownBy']],key=lambda x:(x['chapter'],x['verse']))
   items.append({'id':eid,'allowCandidateMap':bool(row.get('allowCandidateMap')),'allowFrom':gate,'displayNoteJa':'従来の参考位置候補です。古代地点との一致や正確な位置は独立検証できていません。'+(p.get('modernLocationJa') or p.get('locationNoteJa') or '')})
 out=R/f'{book.lower()}-map-policy.json';out.write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n');report['policies'][book]={'records':len(items),'allowed':sum(x['allowCandidateMap'] for x in items),'newIndependentlyVerifiedCoordinates':0}
 out=R/f.name;out.write_bytes(f.read_bytes());report['resources'].append({'file':str(out.relative_to(C)),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
(N/'candidate-activation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
if report['errors']:raise SystemExit(1)
