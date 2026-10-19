"""Project already-written independent exact rows by the existing reviewed group."""
from pathlib import Path
import json,hashlib,sys,re
n=Path(__file__).resolve().parent;src=n/sys.argv[1];d=json.loads(src.read_text());rows=d.get('rows',d.get('records',[]));assert rows
if len(sys.argv)>2:rows=[r for r in rows if r['entityID']in sys.argv[2:]]
assert rows;bindings=json.loads((n/'reviews/root-current-independent-review-bindings.json').read_text());groups={};sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for r in rows:
 dp=r['draftPath'];ep=r['evidencePath'];gs=[k for k,g in bindings['groups'].items()if any(x['draftPath']==dp for x in g['currentRecords'])];assert len(gs)==1,(dp,gs)
 ds=r.get('currentDraftSHA256',r.get('draftSHA256'));es=r.get('currentEvidenceSHA256',r.get('evidenceSHA256'));ps=r.get('currentProfileSHA256',r.get('currentProfileCanonicalSHA256'));decision=r['decision'];assert decision in ['pass','qualified','fail','pending','excluded'];assert all(re.fullmatch('[a-f0-9]{64}',x or '')for x in [ds,es,ps])
 out={'book':r['book'],'entityID':r['entityID'],'draftPath':dp,'evidencePath':ep,'currentDraftSHA256':ds,'currentEvidenceSHA256':es,'currentProfileSHA256':ps,'decision':decision,'sourceIndependentReportPath':str(src.relative_to(n)),'sourceIndependentReportSHA256':sha(src),'formatOnlyProjection':True}
 for key in ['runtimeDisposition','primaryOnlyDisposition']:
  if key in r:out[key]=r[key]
 groups.setdefault(gs[0],[]).append(out)
regp=n/'reviews/extension-review-delta-registry.json';reg=json.loads(regp.read_text())if regp.exists()else{'scope':'Explicit independent exact local delta rows only; no filesystem rebind or semantic promotion','groups':{}}
if regp.exists():(n/'preservation/objects'/sha(regp)).write_bytes(regp.read_bytes())
for group,rs in groups.items():
 name='projected-extension-'+src.stem+'-'+group+'.json';p=n/'reviews'/name;raw=(json.dumps({'scope':'Group-filtered exact independent local delta; original scope and expected hashes retained','sourceReportPath':str(src.relative_to(n)),'sourceReportSHA256':sha(src),'rows':rs},ensure_ascii=False,indent=2)+'\n').encode()
 if p.exists():assert p.read_bytes()==raw,('Do not overwrite immutable projection',name)
 else:p.write_bytes(raw)
 names=reg['groups'].setdefault(group,[])
 if name not in names:names.append(name)
 print(group,name,len(rs))
regp.write_text(json.dumps(reg,ensure_ascii=False,indent=2)+'\n')
