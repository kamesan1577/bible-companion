from pathlib import Path
import json,hashlib,datetime
n=Path(__file__).resolve().parent;w=n.parent;c=n/'candidate';sha=lambda b:hashlib.sha256(b).hexdigest();paths=[p for p in c.rglob('*')if p.is_file() and not p.is_symlink() and ('node_modules'not in p.parts) and (p.name in ['entity-profiles-1CH.json','entity-profiles-2CH.json','1ch-map-policy.json','2ch-map-policy.json','ChroniclesEntityTests.swift','ChroniclesEntityUITests.swift','validate-chronicles-entities.py','OfflineEntityPane.swift','AppStore.swift','SimulatorQA.swift','BundledEntityIndex.swift','project.yml','package.json','chronicles-release-review.json','chronicles-release-evidence.json','chronicles-public-projection-audit.json','v0.1.16-preview.1.md'])]
paths+=sorted((w/'chronicles-ui-v7-attachments').glob('*.png'));paths +=[n/'project-public-evidence.py',w/'chronicles-core-final-exact.log',w/'chronicles-final-ui-v7.log',n/'whole-validation-chronicles-final-real-tmp.log'];rows=[]
for p in paths:
 raw=p.read_bytes();h=sha(raw);o=n/'preservation/objects'/h
 if o.exists():assert o.read_bytes()==raw
 else:o.write_bytes(raw)
 rows.append({'candidateOrEvidencePath':str(p.relative_to(c))if p.is_relative_to(c)else str(p.relative_to(w)),'sha256':h,'bytes':len(raw),'preservedObject':'preservation/objects/'+h})
p=n/'reviews/root-first-subset-final-files-and-ui-preservation.json';p.write_text(json.dumps({'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Exact final candidate code/resources/quality evidence and seven v7 simulator PNGs; 223 core tests and 6 UI tests passed, all seven screenshots visually checked. Library formal readback follows.','records':rows,'published':False},ensure_ascii=False,indent=2)+'\n');print(json.dumps({'preservedFiles':len(rows),'manifestSHA256':sha(p.read_bytes())}))
