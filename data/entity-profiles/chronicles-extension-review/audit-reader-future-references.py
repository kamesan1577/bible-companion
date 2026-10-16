"""Flag future chapter:verse references in always-visible prose; a source review still decides semantics."""
from pathlib import Path
import json,re,hashlib,datetime
N=Path(__file__).resolve().parent;findings=[];exceptions=[]
exceptionFile=N/'reviews/root-earlier-book-reader-reference-exceptions.json'
reviewed=json.loads(exceptionFile.read_text())['items'] if exceptionFile.exists() else []
for f in sorted((N/'drafts').glob('*/*.json')):
 d=json.loads(f.read_text());p=d.get('profile')
 if not p or not p.get('passages'):continue
 if not p.get('knownBy'):raise ValueError(('active-profile-without-knownBy',str(f)))
 gate=p['knownBy']['chapter'],p['knownBy']['verse']
 fields={k:(p.get(k)or'',gate) for k in ['nameJa','subtitleJa','summaryJa','historicalRoleJa','identityNoteJa','modernLocationJa','locationNoteJa']}
 w=p.get('wikipedia')or{};wg=w.get('knownBy')or p['knownBy'];fields['wikipedia.noteJa']=(w.get('noteJa')or w.get('note')or'',(wg['chapter'],wg['verse']))
 for k,(fieldText,fieldGate) in fields.items():
  for m in re.finditer(r'(?<!\d)(\d{1,2}):(\d{1,2})(?!\d)',fieldText):
   cv=tuple(map(int,m.groups()))
   if cv<=fieldGate:continue
   row={'draftPath':str(f.relative_to(N)),'draftSHA256':hashlib.sha256(f.read_bytes()).hexdigest(),'field':k,'knownBy':list(fieldGate),'reference':list(cv),'text':fieldText}
   accepted=next((x for x in reviewed if all(x.get(k)==row.get(k) for k in ['draftPath','draftSHA256','field','reference'])),None)
   if accepted:exceptions.append({**row,'reasonJa':accepted['reasonJa']})
   else:findings.append(row)
out={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'semanticApproval':False,'method':'Detect explicit future coordinate references in always-visible fields, not all possible implicit spoilers. Wikipedia notes are checked against their own gate; gated facts/names also have a separate source-gate audit.','findings':findings,'reviewedExceptions':exceptions}
(N/'reviews/root-future-reference-reader-field-audit.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'openFindings':len(findings),'reviewedExceptions':len(exceptions),'findings':findings},ensure_ascii=False))
