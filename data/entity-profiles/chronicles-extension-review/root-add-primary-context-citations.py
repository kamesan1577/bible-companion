"""Add source IDs for unchanged, previously reviewed namesake-comparison prose.
No approval is implied; every edit requires a peer reclosure.
"""
from pathlib import Path
import json,hashlib,datetime,copy
n=Path(__file__).resolve().parent;sha=lambda b:hashlib.sha256(b).hexdigest();dump=lambda d:(json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode();fixedpath=n/'inventory/targets/chronicles1-web-verses.json';fixed=json.loads(fixedpath.read_text());ix={(r['sourceChapter'],r['sourceVerse']):r for r in fixed}
refs={'person:azariah_378':[(6,9)],'person:ezbon_1236':[('GEN',46,16)],'person:ezer_1241':[(1,38),(1,42)],'person:hilkiah_1526':[(26,10)],'person:ira_610':[(11,28)],'person:jahaziel_698':[(12,4)],'person:obed_2229':[(2,12)],'person:ishi_626':[(4,42)]}
ledger=json.loads((n/'normalized-staging/ledger.json').read_text());current=json.loads((n/'reviews/root-current-independent-review-bindings.json').read_text());bindings={r['draftPath']:(g,r)for g,x in current['groups'].items()for r in x['currentRecords']};records=[]
for eid,coordinates in refs.items():
 item=next(r for r in ledger if r['book']=='1CH'and r['id']==eid);dp=n/item['input'];dr=dp.read_bytes();d=json.loads(dr);p=d['profile'];oldp=copy.deepcopy(p);group,binding=bindings[item['input']];ep=n/binding['evidencePath'];er=ep.read_bytes();e=json.loads(er);oldph=sha(dump(p));checks=[]
 for ref in coordinates:
  if len(ref)==2:
   book='1CH';c,v=ref;s=ix[c,v];text=s['text'];url=s['citationURL'];gate={'chapter':c,'verse':v};version='webp-usfx-2026-10-13-35a6adf626e5'
  else:
   book,c,v=ref;text='The sons of Gad: Ziphion, Haggi, Shuni, Ezbon, Eri, Arodi, and Areli.';url='https://ebible.org/engwebp/GEN46.htm#V16';gate=p['knownBy'];version='engwebp-live-read-2026-10-16; earlier-book contextual citation'
  sid='reader-context-'+eid.replace(':','-')+'-'+book.lower()+'-'+str(c)+'-'+str(v);assert sid not in p['sourceIds'];source={'id':sid,'title':'World English Bible, '+('歴代誌上'if book=='1CH'else'創世記')+' '+str(c)+':'+str(v),'url':url,'license':'Public Domain','licenseURL':'https://ebible.org/web/copyright.htm','attribution':'World English Bible, public domain. Japanese text is an editorial paraphrase.','category':'primary-text','knownBy':gate};d['sources'].append(source);p['sourceIds'].append(sid);checks.append({'book':book,'chapter':c,'verse':v,'text':text,'textSHA256':sha(text.encode()),'citationURL':url,'sourceID':sid,'displayGate':gate,'sourceVersion':version,'supports':'Existing same-name/genealogical comparison; no new occurrence identity or prose added.'})
 newdr=dump(d);newph=sha(dump(p));e['draftSHA256']=sha(newdr);e['profileSHA256']=newph;e.setdefault('supplementalPrimaryContextChecks',[]).extend(checks);newer=dump(e)
 for raw in [dr,er]:(n/'preservation/objects'/sha(raw)).write_bytes(raw)
 assert {k for k in oldp if oldp[k]!=p[k]}=={'sourceIds'}
 dp.write_bytes(newdr);ep.write_bytes(newer);records.append({'book':'1CH','entityID':eid,'priorGroup':group,'draftPath':str(dp.relative_to(n)),'evidencePath':str(ep.relative_to(n)),'beforeDraftSHA256':sha(dr),'afterDraftSHA256':sha(newdr),'beforeEvidenceSHA256':sha(er),'afterEvidenceSHA256':sha(newer),'beforeProfileSHA256':oldph,'afterProfileSHA256':newph,'unchangedReaderFieldsAndFacts':True,'addedPrimaryChecks':checks})
report={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'editor':'root','scope':'Eight primary citation additions to unchanged reader descriptions, nine citation coordinates. All current Chronicle passages were read from the pinned witness; Genesis46:16 was read at official engwebp. No prose/facts/gates/occurrences/IDs changed; not self-approved.','fixedWitnessSHA256':sha(fixedpath.read_bytes()),'records':records,'independentReclosurePending':True};out=n/'evidence/root-author-primary-context-citations.json';out.write_bytes(dump(report));print(json.dumps({'report':str(out.relative_to(n)),'sha256':sha(out.read_bytes()),'records':len(records)}))
