"""Flag future chapter:verse references in always-visible prose; a source review still decides semantics."""
from pathlib import Path
import json,re,hashlib,datetime
N=Path(__file__).resolve().parent;findings=[];exceptions=[]
for f in sorted((N/'drafts').glob('*/*.json')):
 d=json.loads(f.read_text());p=d.get('profile')
 if not p or not p.get('passages'):continue
 if not p.get('knownBy'):raise ValueError(('active-profile-without-knownBy',str(f)))
 gate=p['knownBy']['chapter'],p['knownBy']['verse']
 for k in ['nameJa','subtitleJa','summaryJa','historicalRoleJa','identityNoteJa','modernLocationJa','locationNoteJa']:
  for m in re.finditer(r'(?<!\d)(\d{1,2}):(\d{1,2})(?!\d)',p.get(k)or''):
   cv=tuple(map(int,m.groups()))
   if cv<=gate:continue
   row={'draftPath':str(f.relative_to(N)),'draftSHA256':hashlib.sha256(f.read_bytes()).hexdigest(),'field':k,'knownBy':list(gate),'reference':list(cv),'text':p[k]}
   if f.name=='2SA_ahitub_164.json'and k=='identityNoteJa'and '1サムエル記14:3'in p[k]:
    row['reasonJa']='別の先行書1SAの同名父名を区別する照合注意。2SA内の未来参照ではない。';exceptions.append(row)
   else:findings.append(row)
out={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'semanticApproval':False,'method':'Detect explicit future coordinate references in always-visible fields, not all possible implicit spoilers. Separately gated facts/names/Wikipedia use their own source-gate audit.','findings':findings,'reviewedExceptions':exceptions}
(N/'reviews/root-future-reference-reader-field-audit.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'openFindings':len(findings),'reviewedExceptions':len(exceptions),'findings':findings},ensure_ascii=False))
