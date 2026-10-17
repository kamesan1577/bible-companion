"""Build reversible 1KI/2KI runtime-shaped staging. Never approves or publishes content."""
from pathlib import Path
import copy,datetime,hashlib,json,re,runpy
N=Path(__file__).resolve().parent
runpy.run_path(str(N/'normalize-staging.py'))
O=N/'integrated-staging';O.mkdir(exist_ok=True)
canonical={p['id'] for p in json.loads((N/'candidate/apps/ios/Sources/Core/Resources/entity-index.json').read_text())['entities']}
decisions=json.loads((N/'reviews/root-integration-decisions.json').read_text())
inputs={'1KI':['verse-map-1KI-01-07.json','verse-map-1KI-08-15.json','verse-map-1KI-16-22.json'],'2KI':['verse-map-2KI-01-08.json','verse-map-2KI-09-17.json','verse-map-2KI-18-25.json']}
report={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'published':False,'semanticApproval':False,'books':{},'errors':[],'changes':[],'inputHashes':[]}
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def at(v):return v['chapter'],v['verse']
def coords(p):
 out=set()
 for q in p['passages']:
  if q['start']['chapter']!=q['end']['chapter']:raise ValueError('Cross-chapter author passage requires explicit expansion')
  out.update((q['start']['chapter'],v) for v in range(q['start']['verse'],q['end']['verse']+1))
 return out
def passages(book,cs):return [{'book':book,'start':{'chapter':c,'verse':v},'end':{'chapter':c,'verse':v}} for c,v in sorted(cs)]
def normalize_context(q,ss,book,tag,sources):
 q=copy.deepcopy(q);eid=q['id']
 if eid not in canonical:report['errors'].append({'type':'unknown-context-ID','id':eid,'tag':tag});return None
 if q['kind'] in ['collective','expression']:q['identityType']=q['kind'];q['kind']='person'
 mapping={s['id']:f'{book}-{eid.replace(":","-")}-{tag}-{s["id"]}' for s in ss}
 for s0 in ss:
  s=copy.deepcopy(s0);s['id']=mapping[s0['id']];sources[s['id']]=s
 for x in [q]+q.get('facts',[]):
  try:x['sourceIds']=[mapping[s] for s in x.get('sourceIds',[])]
  except KeyError as e:report['errors'].append({'type':'unknown-context-source','tag':tag,'source':str(e)})
 return q
# Preserve both meanings only where the fixed text explicitly contains both.
dualRows=decisions.get('dual',[])+json.loads((N/'context-edits/dual-meanings.json').read_text())['items']
dual={(x['book'],x['id']):{(v['chapter'],v['verse'])for v in x['coordinates']}for x in dualRows}
for book,names in inputs.items():
 catalog=json.loads((N/f'normalized-staging/entity-profiles-{book}.json').read_text());profiles={p['id']:p for p in catalog['profiles']};sources={s['id']:s for s in catalog['sources']};variantcount=0
 for f in sorted((N/'context-edits'/book).glob('*.json')):
  if f.name in ['index.json','context-index.json']:continue
  d=json.loads(f.read_text());raw=d.get('profile',d);qs=raw.get('contextProfiles',[raw]);report['inputHashes'].append({'path':str(f.relative_to(N)),'sha256':sha(f)})
  for ix,q0 in enumerate(qs):
   q=normalize_context(q0,d.get('sources',[]),book,f.stem+str(ix),sources)
   if not q:continue
   eid=q['id'];base=profiles.get(eid)
   if not base:report['errors'].append({'type':'missing-context-base','book':book,'id':eid});continue
   replace=str(f.relative_to(N))in decisions.get('replaceBaseProposals',[])
   if replace:
    previous=base.get('contextProfiles',[]);q['contextProfiles']=previous;profiles[eid]=q;report['changes'].append({'book':book,'id':eid,'action':'replace-base-with-source-specific-proposal','proposal':f.name});continue
   base.setdefault('contextProfiles',[]).append(q);variantcount+=1
 for base in profiles.values():
  for q in [base]+base.get('contextProfiles',[]):
   wiki=q.get('wikipedia')
   if wiki and 'noteJa' not in wiki and 'note' in wiki:
    wiki['noteJa']=wiki.pop('note');report['changes'].append({'book':book,'id':q['id'],'action':'native-wikipedia-note-field-normalization','semanticTextChanged':False})
 # Remove context-only passages from base so the source-specific meaning resolves.
 for eid,base in profiles.items():
  contextcoords=set().union(*(coords(q) for q in base.get('contextProfiles',[]))) if base.get('contextProfiles') else set()
  remove=contextcoords-dual.get((book,eid),set());before=coords(base);base['passages']=passages(book,(before-remove)|dual.get((book,eid),set()))
  if before&remove:report['changes'].append({'book':book,'id':eid,'action':'remove-context-only-base-passages','coordinates':sorted(before&remove)})
 occurrences={};maprows=[]
 for name in names:
  f=N/'reviews'/name;d=json.loads(f.read_text());report['inputHashes'].append({'path':'reviews/'+name,'sha256':sha(f)})
  for row in d['verses']:
   cv=row['chapter'],row['verse'];maprows.append(row)
   for e in row['entities']:
    eid=e['entityID'];base=profiles.get(eid)
    if not base:report['errors'].append({'type':'map-profile-excluded-or-missing','book':book,'coordinate':cv,'id':eid});continue
    variants=[base]+base.get('contextProfiles',[])
    applicable=[q for q in variants if cv in coords(q) and at(q['knownBy'])<=cv]
    if not applicable:
     if at(base['knownBy'])<=cv:
      base['passages']=passages(book,coords(base)|{cv})
      report['changes'].append({'book':book,'id':eid,'action':'extend-base-relevance-from-source-reviewed-map','coordinate':cv,'relationship':e['relationship'],'sourceMap':name})
     else:
      report['errors'].append({'type':'map-before-profile-context-introduction','book':book,'coordinate':cv,'id':eid});continue
    occurrences[(eid,*cv)]={'entityID':eid,'chapter':cv[0],'verse':cv[1],'directlyNamed':e['relationship']=='direct'}
 # Proposals add explicitly reviewed roles not yet carried in old map entities.
 for eid,base in profiles.items():
  for q in base.get('contextProfiles',[]):
   for c,v in coords(q):occurrences.setdefault((eid,c,v),{'entityID':eid,'chapter':c,'verse':v,'directlyNamed':False})
 # Explicit aliases become a single displayed feature only after their source revelation.
 aliases=[]
 if any(a['book']==book for a in decisions.get('aliases',[])):
  for a in [a for a in decisions['aliases']if a['book']==book]:
   aid,cid=a['aliasID'],a['canonicalID'];old=profiles.get(aid);target=profiles.get(cid)
   if not old or not target:report['errors'].append({'type':'alias-profile-missing','alias':aid});continue
   match=re.search('/'+book+r'(\d+)\.htm#V(\d+)$',a['citations'][0]['url'])
   gate=a.get('knownBy')or{'chapter':int(match[1]),'verse':int(match[2])}
   allcoords=coords(old);earlier={cv for cv in allcoords if cv<at(gate)}
   target['passages']=passages(book,coords(target)|allcoords)
   oldids=set(old['sourceIds'])|{sid for f in old.get('facts',[])for sid in f['sourceIds']};mapping={sid:sid+'-alias-revelation-'+cid.replace(':','-')for sid in oldids}
   for sid in sorted(oldids):
    source=copy.deepcopy(sources[sid]);source['id']=mapping[sid];source['knownBy']=max([source.get('knownBy')or gate,gate],key=at);sources[source['id']]=source
   merged=copy.deepcopy(old);merged['sourceIds']=[mapping[sid]for sid in old['sourceIds']]
   for f in merged.get('facts',[]):f['sourceIds']=[mapping[sid]for sid in f['sourceIds']];f['knownBy']=max([f['knownBy'],gate],key=at)
   gatefacts=[f for f in target['facts'] if at(f['knownBy'])==at(gate)]
   if gatefacts:
    gatefacts[0]['sourceIds']=list(dict.fromkeys(gatefacts[0]['sourceIds']+[sid for sid in merged['sourceIds']if sources[sid].get('category')=='primary-text'and at(sources[sid]['knownBy'])==at(gate)]))
   elif at(target['knownBy'])<at(gate):
    target['facts'].append({'textJa':old['summaryJa'],'knownBy':gate,'sourceIds':merged['sourceIds']})
   target['facts'].extend(f for f in merged.get('facts',[])if at(f['knownBy'])!=at(gate));target['sourceIds']=list(dict.fromkeys(target['sourceIds']+merged['sourceIds']))
   for key,row in list(occurrences.items()):
    if key[0]!=aid or (key[1],key[2])<at(gate):continue
    replacement=(cid,key[1],key[2]);existing=occurrences.get(replacement)
    if existing:existing['directlyNamed']|=row['directlyNamed']
    else:occurrences[replacement]={**row,'entityID':cid}
    del occurrences[key]
   if earlier:
    old['passages']=passages(book,earlier)
    if old.get('wikipedia'):
     old['wikipedia']['knownBy']=max([old['wikipedia'].get('knownBy')or gate,gate],key=at)
     for sid in old['sourceIds']:
      if sources[sid]['url']==old['wikipedia']['url']:sources[sid]['knownBy']=max([sources[sid].get('knownBy')or gate,gate],key=at)
   else:del profiles[aid]
   aliases.append({'aliasID':aid,'canonicalID':cid,'knownBy':gate,'sourceDraftPreserved':True,'coordinatePromoted':False,'earlierSeparateCoordinates':sorted(earlier)})
   report['changes'].append({'book':book,'action':'deduplicate-explicit-WEB-place-alias-after-revelation','aliasID':aid,'canonicalID':cid,'knownBy':gate,'earlierSeparateCoordinates':sorted(earlier)})
 # Keep constant reader fields free of authoring terminology; preserve raw evidence.
 for base in profiles.values():
  for q in [base]+base.get('contextProfiles',[]):
   fields=[(q,k) for k in ['identityNoteJa','modernLocationJa','locationNoteJa']]
   if q.get('wikipedia'):fields.append((q['wikipedia'],'noteJa'))
   for fact in q.get('facts',[]):
    before=fact['sourceIds'];after=[sid for sid in before if not sources[sid].get('knownBy') or at(sources[sid]['knownBy'])<=at(fact['knownBy'])]
    if before!=after:
     assert after,('fact-source-gate-empty',q['id'])
     fact['sourceIds']=after;report['changes'].append({'book':book,'id':q['id'],'action':'filter-future-source-from-gated-fact','knownBy':fact['knownBy'],'removedSourceIds':[sid for sid in before if sid not in after],'retainedSourceIds':after})
 catalog['sourceBoundAliases']=aliases
 # Unmapped drafts are preserved as source evidence, not counted as usable runtime profiles.
 active={row['entityID'] for row in occurrences.values()}
 unmapped=[eid for eid,p in profiles.items() if eid not in active and not p.get('supplemental')]
 catalog['runtimeExcludedUnmappedIDs']=unmapped
 for eid in unmapped:
  del profiles[eid]
  report['changes'].append({'book':book,'id':eid,'action':'exclude-unmapped-authoring-profile-from-runtime','reason':'No adopted occurrence in the source-reviewed maps; original draft/evidence preserved separately'})
 catalog['profiles']=list(profiles.values());catalog['sources']=list(sources.values());catalog['occurrences']=[occurrences[k] for k in sorted(occurrences,key=lambda x:(x[1],x[2],x[0]))]
 catalog['editingDisclosureJa']='公開原典に基づくAI日本語編集の未公開統合候補です。独立照合・表示検証の完了を意味しません。'
 catalog['verification']={'publication':'unpublished-integrated-staging','semanticApproval':False,'sourceWitnessVersion':'webp-usfx-2026-10-13-35a6adf626e5','allSourceCoordinatesReviewed':len(maprows),'allNamedEntitiesComplete':False,'pendingCasesRetainedInSourceMaps':True}
 (O/f'entity-profiles-{book}.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n');report['books'][book]={'baseProfiles':len(profiles),'contextProfiles':sum(len(p.get('contextProfiles',[])) for p in profiles.values()),'unmappedAuthoringProfilesExcluded':len(unmapped),'occurrences':len(occurrences),'sourceCoordinates':len(maprows),'sources':len(sources),'appResourcesWritten':False}
(O/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'books':report['books'],'errorCount':len(report['errors']),'errors':report['errors'][:35]},ensure_ascii=False))

if report['errors']:raise SystemExit(1)
