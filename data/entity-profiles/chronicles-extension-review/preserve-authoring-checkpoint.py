from pathlib import Path
import json,hashlib,datetime
n=Path(__file__).resolve().parent;o=n/'preservation/objects';o.mkdir(parents=True,exist_ok=True);rows=[];unreadable=[]
paths=[n/'AUTHOR-CONTRACT.md',n/'VERSE-MAP-CONTRACT.md']
for folder in ['drafts','evidence','reviews','assignments','context-edits']:
 paths.extend(sorted((n/folder).rglob('*.json')))
for p in paths:
 try:
  raw=p.read_bytes();h=hashlib.sha256(raw).hexdigest();dest=o/h
  if dest.exists():assert dest.read_bytes()==raw
  else:dest.write_bytes(raw)
  rows.append({'path':str(p.relative_to(n)),'sha256':h,'bytes':len(raw)})
 except OSError as e:unreadable.append({'path':str(p.relative_to(n)),'error':type(e).__name__})
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');out=n/'preservation'/('checkpoint-'+stamp+'.json');out.write_text(json.dumps({'atUTC':stamp,'scope':'Immutable content-addressed bytes of current authoring inputs, drafts, evidence, reviews, and proposals. Files may be under active work; this is preservation, not atomic semantic approval. Earlier content remains in objects and earlier manifests.','files':rows,'unreadable':unreadable,'publicationApproved':False},ensure_ascii=False,indent=2)+'\n');print(json.dumps({'manifest':str(out.relative_to(n)),'files':len(rows),'unreadable':len(unreadable),'manifestSHA256':hashlib.sha256(out.read_bytes()).hexdigest()}))
