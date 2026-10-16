"""Validate source-bound 1SA/2SA data and runtime references; not a semantic review."""
from pathlib import Path
from urllib.parse import urlsplit
import collections,hashlib,json,re
R=Path(__file__).resolve().parents[1];A=R/'data/entity-profiles/samuel-review';B=R/'apps/ios/Sources/Core/Resources'
known={e['id'] for e in json.loads((B/'entity-index.json').read_text())['entities']};errors=[];summary={}
cv=lambda x:(x['chapter'],x['verse'])
files={'1SA':['verse-map-1SA-01-10.json','verse-map-1SA-11-20.json','verse-map-1SA-21-31.json'],'2SA':['verse-map-2SA-01-08.json','verse-map-2SA-09-16.json','verse-map-2SA-17-24.json']}
for book,expected in [('1SA',810),('2SA',695)]:
 d=json.loads((B/f'entity-profiles-{book}.json').read_text());sources={s['id']:s for s in d['sources']};profiles={p['id']:p for p in d['profiles']}
 if len(profiles)!=len(d['profiles']) or len(sources)!=len(d['sources']):errors.append(book+' duplicate profile/source IDs')
 fixed=json.loads((A/f'inventory/targets/{"samuel1" if book=="1SA" else "samuel2"}-web-verses.json').read_text());witness={cv(x['canonical']):x for x in fixed};rows={}
 for name in files[book]:
  for v in json.loads((A/'reviews'/name).read_text())['verses']:
   pos=cv(v);s=witness.get(pos)
   if pos in rows:errors.append(book+' duplicate map coordinate')
   rows[pos]=v
   if not s or v['sourceText']!=s['text'] or (v.get('sourceURL')or v.get('citationURL'))!=s['citationURL'] or v['sourceTextSHA256']!=hashlib.sha256(s['text'].encode()).hexdigest():errors.append(book+' fixed witness mismatch '+str(pos))
   if not v.get('reasonJa'):errors.append(book+' unreasoned source row')
   conflict={e['entityID']for e in v['entities']}&{e.get('entityID')for e in v.get('excludedCandidates',[])if isinstance(e,dict)}
   if conflict:errors.append(book+' entity both adopted and excluded '+str(pos)+' '+','.join(sorted(conflict)))
 if len(rows)!=expected or set(rows)!=set(witness):errors.append(book+' source coordinate coverage mismatch')
 occ=set()
 for o in d['occurrences']:
  key=(o['entityID'],*cv(o))
  if key in occ:errors.append(book+' duplicate occurrence '+str(key))
  occ.add(key);p=profiles.get(o['entityID'])
  if not p:errors.append(book+' dangling occurrence');continue
  applicable=any(cv(q['knownBy'])<=cv(o) and any(cv(r['start'])<=cv(o)<=cv(r['end'])for r in q['passages'])for q in [p]+p.get('contextProfiles',[]))
  if not applicable:errors.append(book+' occurrence lacks applicable source-specific profile '+str(key))
 for base in profiles.values():
  if base['id']not in known:errors.append(book+' invented base ID')
  for p in [base]+base.get('contextProfiles',[]):
   if p['id']!=base['id']:errors.append(book+' invented context ID')
   if p['kind']not in ['person','place']:errors.append(book+' invalid native kind')
   if p.get('coordinate')is not None:errors.append(book+' unreviewed promoted coordinate')
   for q in p['passages']:
    if q['book']!=book or cv(q['start'])>cv(q['end']):errors.append(book+' invalid profile passage')
   for x in [p]+p.get('facts',[]):
    for sid in x.get('sourceIds',[]):
     source=sources.get(sid)
     if not source:errors.append(book+' unresolved source '+sid);continue
     if x is not p and source.get('knownBy')and cv(source['knownBy'])>cv(x['knownBy']):errors.append(book+' source later than gated fact '+p['id'])
   readerfields={k:p.get(k)or''for k in ['nameJa','subtitleJa','summaryJa','identityNoteJa','modernLocationJa','historicalRoleJa','locationNoteJa']}
   readerfields['wikipedia.noteJa']=(p.get('wikipedia')or{}).get('noteJa','')
   readerfields.update({f'fact-{i}':f['textJa']for i,f in enumerate(p.get('facts',[]))})
   for field,text in readerfields.items():
    if re.search(r'context|knownBy|sourceIds|profile|\bbase\b|(?<![A-Za-z])ID(?![A-Za-z])|プロフィール|このID|本ID|確定座標|作業で',text,re.I):errors.append(book+' editor-only language in reader field '+p['id']+' '+field)
   w=p.get('wikipedia')
   if w:
    u=urlsplit(w['url']);lang=w['language'];allowed=w['identityVerified'] or(w['kind']=='related-section'and w.get('relationVerified')and w.get('noteJa'))
    if not allowed or lang not in ['ja','en']or u.scheme!='https'or u.hostname!=lang+'.wikipedia.org'or u.username or u.password or u.port or u.query or not u.path.startswith('/wiki/')or ':'in u.path:errors.append(book+' unsafe/unqualified wiki '+p['id'])
    reachable=set(p.get('sourceIds',[]))|{sid for f in p.get('facts',[])for sid in f.get('sourceIds',[])}
    rights=[sources[sid] for sid in reachable if sid in sources and sources[sid]['url']==w['url']]
    if not rights or not any(s.get('category')=='secondary-reference' and s.get('license') in ['CC BY-SA 4.0','Creative Commons Attribution-ShareAlike 4.0 International'] and s.get('licenseURL') in ['https://creativecommons.org/licenses/by-sa/4.0/','https://en.wikipedia.org/wiki/Wikipedia:Copyrights','https://ja.wikipedia.org/wiki/Wikipedia:著作権'] and 'Wikipedia' in s.get('attribution','')for s in rights):errors.append(book+' Wikipedia lacks reachable licensed source '+p['id'])
    gate=cv(w.get('knownBy')or p['knownBy'])
    if any(s.get('knownBy')and cv(s['knownBy'])<gate for s in rights):errors.append(book+' Wikipedia source visible before article gate '+p['id'])
 for s in sources.values():
  if not all(s.get(k)for k in ['id','title','url','license','licenseURL','attribution']):errors.append(book+' incomplete source rights')
 aliases=d.get('sourceBoundAliases',[])
 for a in aliases:
  if any(k[0]==a['aliasID']and k[1:]>=cv(a['knownBy'])for k in occ):errors.append(book+' duplicate explicit alias display after revelation')
  if a['aliasID']in profiles and any(cv(r['end'])>=cv(a['knownBy'])for r in profiles[a['aliasID']]['passages']):errors.append(book+' alias profile extends beyond revelation')
 summary[book]={'profiles':len(profiles),'nestedContexts':sum(len(p.get('contextProfiles',[]))for p in profiles.values()),'sourceCoordinates':len(rows),'occurrences':len(occ),'mappedCoordinates':len({k[1:]for k in occ}),'explicitAliasesCollapsed':len(aliases),'sources':len(sources)}
print(json.dumps({'scope':'structural integration and fixed source preservation; independent semantic reviews are separately SHA-bound','books':summary,'errors':errors},ensure_ascii=False,indent=2));assert not errors
