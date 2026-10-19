from pathlib import Path
import json,hashlib,datetime,collections
n=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
specs={
 'batch06-persons_1':['reclosure-batch06-persons_1-current.json'],
 'batch05-persons_3':['reclosure-batch05-persons_3-current.json'],
 'batch05-persons_2':['reclosure-batch05-persons_2-final-current.json','root-reader-five-reclosure-batch05-persons_2.json'],
 'batch05-persons_1':['reclosure-batch05-persons_1-current-v3.json'],
 'batch04-persons_3':['reclosure-batch04-persons_3-current.json','root-jehiel770-first-use-reclosure.json'],
 'batch04-persons_2':['reclosure-independent-batch04-persons_2-after-author-fixes.json'],
 'batch03-persons_2':['reclosure-batch03-persons_2-current-final.json','root-hanun1404-reader-wording-delta.json','root-reader-five-reclosure-batch03-persons_2.json'],
 'batch04-persons_1':['reclosure-batch04-persons_1-after-repairs.json'],
 'batch01-persons_1':['independent-reclosure-batch01-persons_1-current-amminadab.json','independent-reclosure-amminadab229-source-dedupe.json','root-independent-ashbel-source-sync-delta.json','root-amminadab229-date-metadata-rebind.json'],
 'batch01-persons_2':['reclosure-batch01-persons_2-final-two.json','root-independent-ahlai-reader-gate-delta.json'],
 'batch02-persons_2':['reclosure-batch02-persons_2-after-author-fixes-v2.json','root-reclosure-persons2-caleb-eliezer-fact-current.json'],
 'batch03-persons_3':['reclosure-batch03-persons_3-current.json'],
 'batch03-places_1':['root-reclosure-batch03-places1-three-repairs.json'],
 'batch03-persons_1':['reclosure-batch03-persons_1-after-repairs.json'],
 'batch02-persons_1':['reclosure-batch02-persons_1-after-repairs-v2.json'],
 'batch02-persons_3':['reclosure-batch02-persons_3-after-repairs.json','reclosure-persons3-dodanim-subtitle-current.json','root-independent-caleb538-reader-gate-delta.json'],
 'batch01-persons_3':['independent-batch01-persons_3-v3.json','independent-batch01-persons_3-v3-delta.json'],
 'batch02-places_2':['reclosure-batch02-places_2-after-author-fixes.json'],
 'batch02-places_3':['reclosure-batch02-places_3-reader-language-current.json'],
 'batch02-places_1':['reclosure-batch02-places_1-three-repairs.json'],
 'batch03-places_2':['reclosure-batch03-places_2-current.json'],
 'batch03-places_3':['root-reclosure-batch03-places3-final-three-current.json'],
 'batch01-places_1':['reclosure-batch01-places_1-current.json'],
 'batch01-places_2':['reclosure-batch01-places_2-current.json'],
 'batch01-places_3':['reclosure-batch01-places_3-v3.json']}
specs.update({'batch06-persons_2':['reclosure-batch06-persons_2-current.json'], 'batch06-persons_3':['reclosure-batch06-persons_3-current.json']})
specs['batch07-persons_1']=['reclosure-batch07-persons_1-current.json','root-sibbechai-rationale-reclosure-delta.json','root-projected-tahan-current-delta.json','root-projected-shelomith-reader-note-delta.json']
specs['batch07-persons_3']=['reclosure-batch07-persons_3-current.json','reclosure-shobal-persons3-identity-note-current.json']
for group in ['batch02-persons_3','batch04-persons_3','batch02-persons_1']:
 specs[group].append('root-projected-reader-concrete-reclosure-'+group+'.json')
for group in ['batch05-persons_1','batch01-places_1']:
 specs[group].append('root-rights-reader-three-reclosure-'+group+'.json')
for group in ['batch01-persons_1','batch04-persons_1','batch03-persons_1','batch06-persons_1']:
 specs[group].append('root-projected-primary-context-reclosure-'+group+'.json')
# Extension reports retain exact independent row bindings and explicit local deltas.
specs['batch04-persons_1'].append('projected-ishi626-evidence-only-delta.json')
specs['batch07-persons_2']=['projected-reclosure-batch07-persons_2.json','projected-terah-occurrence-final-delta.json']
specs['batch08-persons_1']=['projected-reclosure-batch08-persons_1.json','projected-god1324-primary-only-current.json']
specs['batch08-persons_2']=['projected-reclosure-batch08-persons_2.json','projected-conaniah-current-delta.json']
specs['batch08-persons_3']=['projected-reclosure-batch08-persons_3.json','projected-batch08-book-metadata-delta.json','projected-hiram1533-root-repair-delta.json']
specs['batch09-persons_1']=['projected-independent-batch09-persons_1.json']
specs['batch09-persons_2']=['projected-reclosure-batch09-persons_2-after-independent-repairs.json']
specs['batch09-persons_3']=['projected-reclosure-batch09-persons_3.json','reclosure-shamariah-persons3-reader-repair-current.json']
delta_registry=n/'reviews/extension-review-delta-registry.json'
if delta_registry.exists():
 for group,reports in json.loads(delta_registry.read_text())['groups'].items():
  assert group in specs
  specs[group].extend(reports)
out={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Exact byte binding of independent semantic reports; this script does not independently approve content. Later exact delta supersedes only its named records.','groups':{}}
for group,fs in specs.items():
 rows={}; proofs=[]
 for fn in fs:
  p=n/'reviews'/fn; d=json.loads(p.read_text()); proofs.append({'path':str(p.relative_to(n)),'sha256':sha(p)})
  for sourceRow in d.get('records',d.get('rows',d.get('entries',[]))):
   r=dict(sourceRow)
   # Explicit excluded/no-profile records have no draft bytes to activate.
   # Their full decision remains in the immutable report, never as runtime data.
   if r.get('draftPath') is None and 'draftPath' in r:
    assert r.get('currentDraftSHA256') is None
    continue
   if 'draftPath' not in r:
    prior=[v for v in rows.values() if v['entityID']==r['entityID'] and (not r.get('book') or r.get('book')==v.get('book'))]
    assert len(prior)==1,('Ambiguous pathless delta',fn,r['entityID'])
    r.update({k:prior[0][k] for k in ['draftPath','evidencePath']});r['pathResolvedFromUniquePriorScope']=True
   if 'evidencePath' not in r:
    dp=Path(r['draftPath']);es=[n/'evidence'/dp.parts[1]/(dp.stem+x) for x in ['.json','-sources.json'] if (n/'evidence'/dp.parts[1]/(dp.stem+x)).exists()]
    assert len(es)==1,('Ambiguous primary sidecar',fn,r['draftPath'])
    r['evidencePath']=str(es[0].relative_to(n));r['evidencePathResolvedFromUniquePrimarySidecar']=True
   rows[r['draftPath']]=r
 errors=[]; counts=collections.Counter(); bindings=[]
 for path,r in rows.items():
  dp=n/path; ep=n/r['evidencePath']; ds=sha(dp); es=sha(ep)
  expectedDS=r.get('currentDraftSHA256',r.get('draftSHA256'));expectedES=r.get('currentEvidenceSHA256',r.get('evidenceSHA256'))
  if ds!=expectedDS: errors.append({'path':path,'field':'draftSHA'})
  if es!=expectedES: errors.append({'path':str(ep.relative_to(n)),'field':'evidenceSHA'})
  decision=r.get('decision',r.get('verdict',r.get('status',r.get('currentVerdict'))))
  assert decision in ['pass','qualified','pending','excluded','fail'],('Unknown independent verdict',group,path,decision)
  counts[decision]+=1
  bindings.append({'draftPath':path,'draftSHA256':expectedDS,'evidencePath':r['evidencePath'],'evidenceSHA256':expectedES,'decision':decision,'bytesMatchIndependentReview':ds==expectedDS and es==expectedES,'currentFilesystemDraftSHA256':ds,'currentFilesystemEvidenceSHA256':es})
 out['groups'][group]={'records':len(rows),'lastReportedCountsNotCurrentApproval':dict(counts),'allRowsBoundToCurrentBytes':not errors,'bindingErrors':errors,'reports':proofs,'currentRecords':bindings}
p=n/'reviews/root-current-independent-review-bindings.json';p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:{x:v[x]for x in ['records','lastReportedCountsNotCurrentApproval','allRowsBoundToCurrentBytes','bindingErrors']}for k,v in out['groups'].items()},ensure_ascii=False))
