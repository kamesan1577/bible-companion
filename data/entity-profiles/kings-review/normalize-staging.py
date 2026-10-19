"""Reversible authoring normalization. Never writes app resources or approves content."""
from pathlib import Path
import json,hashlib,copy,re,datetime
N=Path(__file__).resolve().parent;O=N/'normalized-staging';O.mkdir(exist_ok=True)
index=json.loads((N/'candidate/apps/ios/Sources/Core/Resources/entity-index.json').read_text());known={x['id']for x in index['entities']};report={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'published':False,'semanticApproval':False,'contextProposalsIntegrated':False,'verseOccurrenceMapsIntegrated':False,'books':{},'errors':[]};ledger=[]
for book in ['1KI','2KI']:
 profiles=[];sources={};seen=set();excluded=[]
 for file in sorted((N/'drafts').glob('*/*.json')):
  if file.name=='progress.json':continue
  d=json.loads(file.read_text());rev=d.get('review',{});p=copy.deepcopy(d.get('profile'));b=rev.get('book')or d.get('book');eid=(p or{}).get('id')or rev.get('entityID')
  if b!=book:continue
  row={'book':book,'id':eid,'input':str(file.relative_to(N)),'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'quality':'unapproved'};ledger.append(row)
  if eid in seen:report['errors'].append({'type':'duplicate-book-ID','book':book,'id':eid});continue
  seen.add(eid)
  if not p or not p.get('passages'):
   row['disposition']='excluded-or-held';excluded.append(eid);continue
  if eid not in known:report['errors'].append({'type':'unknown-ID','book':book,'id':eid});continue
  if p['kind']in ['collective','expression']:p['identityType']=p['kind'];p['kind']='person'
  # No book-specific ritual identity coercion.
  if p['kind']=='place' and p.get('identityType')=='collective':
   report['errors'].append({'type':'place-collective-identity-conflict','book':book,'id':eid,'input':str(file.relative_to(N))})
  for passage in p['passages']:
   if passage['book']!=book or (passage['start']['chapter'],passage['start']['verse'])>(passage['end']['chapter'],passage['end']['verse']):report['errors'].append({'type':'bad-passage','book':book,'id':eid,'passage':passage})
  if p.get('contextProfiles')is None:p.pop('contextProfiles',None)
  oldsources=d.get('sources',[]);mapping={s['id']:book+'-'+eid.replace(':','-')+'-'+s['id']for s in oldsources}
  for s0 in oldsources:
   s=copy.deepcopy(s0);s['id']=mapping[s0['id']];url=s.get('url','');s['category']='secondary-reference'if'wikipedia.org/wiki/'in url else'primary-text'if'ebible.org/engwebp/'in url else s.get('category','geographic-reference')
   match=re.search('/'+book+r'(\d+)\.htm#V(\d+)$',url)
   if match and not s.get('knownBy'):ch,v=map(int,match.groups());s['knownBy']={'chapter':ch,'verse':v}
   if s['id']in sources and s!=sources[s['id']]:report['errors'].append({'type':'conflicting-source','book':book,'id':s['id']})
   sources[s['id']]=s
  for obj in [p]+p.get('facts',[]):
   try:obj['sourceIds']=[mapping[x]for x in obj.get('sourceIds',[])]
   except KeyError as exc:report['errors'].append({'type':'unresolved-source','book':book,'id':eid,'source':str(exc)})
  w=p.get('wikipedia')
  if w:
   gate=w.get('knownBy')or p['knownBy'];matching=[s for s in sources.values()if s['url']==w['url']and s['id'].startswith(book+'-'+eid.replace(':','-')+'-')]
   if matching:
    ws=matching[0]
    for articleSource in matching:
     previous=articleSource.get('knownBy');articleSource['knownBy']=max([previous or gate,gate],key=lambda v:(v['chapter'],v['verse']))
     if previous!=articleSource['knownBy']:row.setdefault('articleSourceGateNormalizations',[]).append({'sourceID':articleSource['id'],'before':previous,'after':articleSource['knownBy'],'reason':'Every matching article attribution is gated no earlier than the explicit reading-link gate.'})
   else:
    report['errors'].append({'type':'missing-explicit-wikipedia-source','book':book,'id':eid,'url':w['url']})
    sid=book+'-'+eid.replace(':','-')+'-wikipedia-reading-link'
    ws={'id':sid,'title':'Wikipedia · '+w['title'],'url':w['url'],'license':'CC BY-SA 4.0','licenseURL':'https://creativecommons.org/licenses/by-sa/4.0/','attribution':'Wikipedia contributors','knownBy':gate,'category':'secondary-reference'};sources[sid]=ws
   if ws['id']not in p['sourceIds']:p['sourceIds'].append(ws['id'])
  row['disposition']='normalized-unapproved';profiles.append(p)
 catalog={'schemaVersion':1,'scope':{'book':book,'start':{'chapter':1,'verse':1},'end':{'chapter':22 if book=='1KI' else 25,'verse':53 if book=='1KI' else 30}},'editingDisclosureJa':'公開原典に基づくAI日本語編集の未公開候補です。独立照合・文脈表示の統合は未完了です。','profiles':profiles,'sources':list(sources.values()),'occurrences':[],'verification':{'publication':'unpublished-staging','semanticApproval':False,'contextVariantsPending':True,'allVerseMapsPending':True,'sourceWitnessVersion':'webp-usfx-2026-10-13-35a6adf626e5'}}
 (O/f'entity-profiles-{book}.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n');report['books'][book]={'inputRecords':len(seen),'baseProfiles':len(profiles),'excludedOrHeld':len(excluded),'wikiLinks':sum(bool(p.get('wikipedia'))for p in profiles),'sources':len(sources),'occurrences':0,'appResourcesWritten':False}
(O/'ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n');(O/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
if report['errors']:raise SystemExit(1)
