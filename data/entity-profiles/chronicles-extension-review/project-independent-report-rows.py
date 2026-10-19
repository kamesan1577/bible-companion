from pathlib import Path
import json,hashlib,sys,datetime,re
n=Path(__file__).resolve().parent;src=n/sys.argv[1];dest=n/sys.argv[2];d=json.loads(src.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();rows=d.get('rows',d.get('records',d.get('entries',[d['row']]if 'row'in d else[])));assert rows,('No independently approved rows contract',src.name);out=[];skipped=[]
for r in rows:
 dp=r.get('draftPath');ep=r.get('evidencePath',r.get('currentEvidencePath'));assert dp and ep,(src.name,'Paths required');assert not Path(dp).is_absolute()and '..'not in Path(dp).parts;assert not Path(ep).is_absolute()and '..'not in Path(ep).parts
 b=r.get('currentBindings',{});ds=r.get('currentDraftSHA256',r.get('draftSHA256',b.get('currentDraftSHA256')));es=r.get('currentEvidenceSHA256',r.get('evidenceSHA256',b.get('currentEvidenceSHA256')));ps=r.get('currentProfileSHA256',r.get('currentProfileCanonicalSHA256',r.get('profileSHA256',b.get('currentProfileSHA256'))));decision=r.get('decision',r.get('verdict',r.get('currentVerdict',r.get('readerFieldsAndGates',{}).get('decision',r.get('originalDecision')))));assert decision in ['pass','qualified','pending','excluded','fail'],(src.name,dp,decision);assert re.fullmatch('[0-9a-f]{64}',ds or '')and re.fullmatch('[0-9a-f]{64}',es or '')
 book=r.get('correctedBook',r.get('book'))or re.match(r'(1CH|2CH)_',Path(dp).name).group(1)
 if book not in ['1CH','2CH']:
  assert '--skip-invalid-book' in sys.argv,('Invalid independent metadata book',src.name,dp,book)
  skipped.append({'draftPath':dp,'invalidBook':book,'decisionNotActivated':decision,'reason':'Requires separately bound independent metadata correction delta'});continue
 if 'correctedBook' in r:assert r['originalDecisionPreserved'] and r['originalReportBook']not in ['1CH','2CH']
 eid=r.get('entityID',r.get('id'));assert eid
 row={'book':book,'entityID':eid,'draftPath':dp,'evidencePath':ep,'currentDraftSHA256':ds,'currentEvidenceSHA256':es,'currentProfileSHA256':ps,'decision':decision,'sourceIndependentReportPath':str(src.relative_to(n)),'sourceIndependentReportSHA256':sha(src),'formatOnlyProjection':True,'fieldAliasResolution':{'evidencePathFrom':'evidencePath'if'evidencePath'in r else'currentEvidencePath','bookFrom':'correctedBook'if'correctedBook'in r else'book-or-explicit-filename'}}
 if 'runtimeDisposition'in r.get('readerFieldsAndGates',{}):row['runtimeDisposition']=r['readerFieldsAndGates']['runtimeDisposition']
 for k in ['runtimeDisposition','primaryOnlyDisposition']: 
  if k in r:row[k]=r[k]
 out.append(row)
assert len({(r['book'],r['entityID'])for r in out})==len(out)
result={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Format-only projection of exact independent report rows. Expected reviewed hashes preserved; current filesystem mismatch is not silently rebound. No semantic verdict or Wiki identity promotion.','sourceIndependentReportPath':str(src.relative_to(n)),'sourceIndependentReportSHA256':sha(src),'excludedInvalidMetadataRows':skipped,'rows':out};dest.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'rows':len(out),'output':str(dest.relative_to(n)),'sha256':sha(dest)}))
