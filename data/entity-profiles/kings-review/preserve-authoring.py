"""Preserve public-source authoring inputs in candidate; excludes build/cache/private state."""
from pathlib import Path
import json,hashlib,shutil,datetime
N=Path(__file__).resolve().parent
if N.name=='kings-review' and N.parent.name=='entity-profiles':raise SystemExit('Archival reference copy: run from the original authoring workspace, not inside this projection.')
D=N/'candidate/data/entity-profiles/kings-review';D.mkdir(parents=True,exist_ok=True)
manifest=[]
for sub in ['drafts','evidence','reviews','context-edits','assignments','inventory/targets']:
 for f in sorted((N/sub).rglob('*.json')):
  if f.name=='progress.json':continue
  rel=f.relative_to(N);out=D/rel;out.parent.mkdir(parents=True,exist_ok=True)
  original=f.read_bytes();public=original.replace(str(N).encode(),b'authoring-workspace').replace(b'published-source-checkout',b'published-source-checkout').replace(b'local-workspace',b'local-workspace')
  assert bytes([47,85,115,101,114,115,47]) not in public and b'/var/folders/'not in public
  out.write_bytes(public);manifest.append({'path':str(rel),'sha256':hashlib.sha256(public).hexdigest(),'bytes':len(public),'originalLocalEvidenceSHA256':hashlib.sha256(original).hexdigest(),'localWorkspacePathRedacted':public!=original})
for name in ['AUTHOR-CONTRACT.md'] + sorted(p.name for p in N.glob('*.py')):
 original=(N/name).read_bytes();public=original.replace(str(N).encode(),b'authoring-workspace').replace(b'published-source-checkout',b'published-source-checkout').replace(b'local-workspace',b'local-workspace');assert bytes([47,85,115,101,114,115,47]) not in public;(D/name).write_bytes(public);manifest.append({'path':name,'sha256':hashlib.sha256(public).hexdigest(),'bytes':len(public),'originalLocalEvidenceSHA256':hashlib.sha256(original).hexdigest(),'localWorkspacePathRedacted':public!=original,'kind':'authoring-helper-reference'})
(D/'preservation-manifest.json').write_text(json.dumps({'preservedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'AI Japanese authoring drafts and independent-review evidence; runtime release approval is separate','privateStateIncluded':False,'projectionNote':'Local authoring workspace paths replaced by authoring-workspace; both original and public file hashes recorded. Unredacted evidence remains local.','inputs':manifest},ensure_ascii=False,indent=2)+'\n')
print('Public-source authoring files preserved in local candidate:',len(manifest))
