"""Rebuild the isolated extension candidate and preserve replaced intermediate bytes."""
from pathlib import Path
import subprocess,hashlib,json,datetime
n=Path(__file__).resolve().parent;stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');saved=[]
paths=[n/'reviews/root-current-independent-review-bindings.json',n/'reviews/root-reviewed-occurrence-edge-preview.json',n/'reviews/root-native-final-runtime-probe.json']
for folder in ['normalized-staging','conservative-runtime-preview','qualified-primary-runtime-preview','reviewed-context-runtime-preview','reviewed-alias-runtime-preview']:
 paths.extend((n/folder).glob('*.json'))
for b in ['1CH','2CH']:paths.append(n/f'candidate/apps/ios/Sources/Core/Resources/entity-profiles-{b}.json')
for p in paths:
 if not p.exists():continue
 raw=p.read_bytes();h=hashlib.sha256(raw).hexdigest();o=n/'preservation/objects'/h
 if o.exists():assert o.read_bytes()==raw
 else:o.write_bytes(raw)
 saved.append({'path':str(p.relative_to(n)),'sha256':h})
(n/'preservation'/f'extension-derived-before-{stamp}.json').write_text(json.dumps({'scope':'Exact intermediate before bytes; not semantic approval','files':saved},indent=2)+'\n')
steps=[('reconcile-current-reviews.py',[]),('normalize-staging.py',['--reviewed-only']),('audit-reader-future-references.py',[]),('preview-reviewed-occurrence-edges.py',[]),('build-conservative-runtime-preview.py',[]),('build-qualified-primary-preview.py',[]),('build-reviewed-context-preview.py',['qualified-primary-runtime-preview']),('build-reviewed-alias-preview.py',[]),('stage-reviewed-candidate.py',['reviewed-alias-runtime-preview'])]
for script,args in steps:
 log=n/'reviews'/('extension-'+script.removesuffix('.py')+'-run.log')
 with log.open('w')as out:subprocess.run(['python3',str(n/script),*args],cwd=n,stdout=out,check=True)
print(json.dumps({'steps':len(steps),'preservedBeforeFiles':len(saved),'candidateOnly':True,'publicationApproved':False}))
