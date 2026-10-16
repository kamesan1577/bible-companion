from pathlib import Path
import hashlib,json,datetime
n=Path(__file__).resolve().parent;sha=lambda b:hashlib.sha256(b).hexdigest();base=sorted((n/'preservation').glob('checkpoint-*.json'))[-1];d=json.loads(base.read_text());assert not d['unreadable'];rows={r['path']:r for r in d['files']}
paths=[]
for folder in ['inventory/targets','verse-review-inputs','normalized-staging','conservative-runtime-preview','qualified-primary-runtime-preview','reviewed-context-runtime-preview','reviewed-alias-runtime-preview']:
 paths.extend(sorted((n/folder).glob('*.json')))
paths.extend(sorted((n/'scripts').rglob('*.py')))
paths.extend(p for pattern in ['*.py','*.swift']for p in sorted(n.glob(pattern))if p.name not in ['project-public-evidence.py','project-extension-public-evidence.py'])
for p in paths:
 raw=p.read_bytes();h=sha(raw);o=n/'preservation/objects'/h
 if o.exists():assert o.read_bytes()==raw
 else:o.write_bytes(raw)
 rel=str(p.relative_to(n));rows[rel]={'path':rel,'sha256':h,'bytes':len(raw),'kind':'fixed-primary-source-derived-preview-or-archival-helper'}
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');d={'atUTC':stamp,'scope':'Immutable publication input projection freeze; held authoring drafts retained with their status, no semantic promotion. No live-derived bytes used during projection.','authoringSnapshot':str(base.relative_to(n)),'authoringSnapshotSHA256':sha(base.read_bytes()),'files':[rows[k]for k in sorted(rows)],'unreadable':[],'publicationApproved':False};p=n/'preservation'/('release-inputs-'+stamp+'.json');p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'manifest':str(p.relative_to(n)),'files':len(rows),'sha256':sha(p.read_bytes())}))
