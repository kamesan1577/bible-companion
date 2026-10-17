from pathlib import Path
import json,hashlib
n=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(fn,src,row):
 p=n/'reviews'/src
 out={'scope':'Explicit format-only projection of an independent local delta; earlier unchanged review scope retained, no new semantic approval.', 'sourceIndependentReportPath':'reviews/'+src,'sourceIndependentReportSHA256':sha(p),'rows':[row]}
 (n/'reviews'/fn).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
f='reclosure-terah-occurrence-evidence-final.json';d=json.loads((n/'reviews'/f).read_text());assert d['decision']=='pass' and all(d['currentBindingChecks'].values())
save('projected-terah-occurrence-final-delta.json',f,{'book':'1CH','entityID':'person:terah_2841','draftPath':d['inputs']['draft']['path'],'evidencePath':d['inputs']['evidence']['path'],'currentDraftSHA256':d['inputs']['draft']['sha256'],'currentEvidenceSHA256':d['inputs']['evidence']['sha256'],'currentProfileSHA256':d['profileSHA256'],'decision':'pass','localCorrectionScopeRetained':d['scope']})
f='reclosure-ishi626-evidence-only-delta.json';d=json.loads((n/'reviews'/f).read_text());b=d['currentBindings'];a=d['assessment'];assert a['decision']=='qualified' and a['runtimeDisposition']=='primary-only-display-supported' and b['draftUnchanged'] and a['runtimeDispositionRebind']['draftSHA256Matches'] and a['runtimeDispositionRebind']['profileSHA256Matches']
r={'book':'1CH','entityID':'person:ishi_626','draftPath':b['draftPath'],'evidencePath':b['evidencePath'],'currentDraftSHA256':b['draftSHA256'],'currentEvidenceSHA256':b['evidenceSHA256'],'currentProfileSHA256':b['profileSHA256'],'decision':'qualified','runtimeDisposition':a['runtimeDisposition'],'evidenceOnlyRebind':True}
save('projected-ishi626-evidence-only-delta.json',f,r)
print('2 exact independent deltas projected; no raw changes')
f='reclosure-batch08-persons_2-conaniah-current-delta.json';d=json.loads((n/'reviews'/f).read_text());b=d['currentHashes'];assert d['verdict']=='qualified' and all(d['consistencyChecks'].values())
r=dict(d['scope'],currentDraftSHA256=b['draftSHA256'],currentEvidenceSHA256=b['evidenceSHA256'],currentProfileSHA256=b['profileSHA256'],decision=d['verdict'],runtimeDisposition=d['qualifiedRuntimeDisposition']['disposition'])
save('projected-conaniah-current-delta.json',f,r)
f='runtime-disposition-primary-only-persons1-god1324-current.json';d=json.loads((n/'reviews'/f).read_text());b=d['currentInputSHAs'];a=d['disposition'];assert all(d['bindingChecks'].values()) and a['profileWideStatus']=='qualified' and a['runtimeDisposition']=='primary-only-display-supported' and not a['runtimeApproval']
save('projected-god1324-primary-only-current.json',f,{'book':'2CH','entityID':'person:god_1324','draftPath':b['draft']['path'],'evidencePath':b['evidence']['path'],'currentDraftSHA256':b['draft']['sha256'],'currentEvidenceSHA256':b['evidence']['sha256'],'currentProfileSHA256':d['currentProfileSHA256'],'decision':'qualified','runtimeDisposition':a['runtimeDisposition'],'scopePreserved':d['scope'],'mapRelationshipHoldPreserved':d['mapRelationshipHold']})
