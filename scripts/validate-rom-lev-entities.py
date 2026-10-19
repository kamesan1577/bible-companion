from pathlib import Path
import json,hashlib,collections
ROOT=Path(__file__).resolve().parents[1];A=ROOT/'data/entity-profiles/rom-lev-review';R=ROOT/'apps/ios/Sources/Core/Resources'
errors=[];books={}
verse=lambda v:(v['chapter'],v['verse'])
for book,total in [('ROM',433),('LEV',859)]:
 p=R/f'entity-profiles-{book}.json';d=json.loads(p.read_text());sources={s['id']:s for s in d['sources']};ps=d['profiles'];ids=[p['id']for p in ps];assert len(ids)==len(set(ids))
 coords=set();links=[]
 for group in (["ROM-01-08","ROM-09-16"]if book=='ROM'else["LEV-01-13","LEV-14-27"]):
  m=json.loads((A/f'reviews/final-verse-map-{group}.json').read_text())
  for v in m['verses']:
   c=(v['chapter'],v['verse']);assert c not in coords;coords.add(c)
   links += [(e['entityID'],*c,e['relationship']=='direct')for e in v['entities']]
 assert len(coords)==total
 actual=[(x['entityID'],x['chapter'],x['verse'],x['directlyNamed'])for x in d['occurrences']]
 if set(actual)!=set(links):errors.append(book+' occurrence normalization differs from independently reviewed maps')
 if len(actual)!=len(set(actual)):errors.append(book+' duplicate occurrences')
 for base in ps:
  for p in [base]+base.get('contextProfiles',[]):
   if p['id']!=base['id']:errors.append(book+' invented context identity')
   for sid in p['sourceIds']:
    if sid not in sources:errors.append(book+' missing source '+sid)
   for f in p['facts']:
    for sid in f['sourceIds']:
     if sid not in sources:errors.append(book+' missing fact source '+sid);continue
     sg=sources[sid].get('knownBy')
     if sg and verse(sg)>verse(f['knownBy']):errors.append(book+' citation later than fact '+p['id'])
   w=p.get('wikipedia')
   if w:
    from urllib.parse import urlsplit
    u=urlsplit(w['url'])
    if u.scheme!='https'or u.hostname!=w['language']+'.wikipedia.org'or u.query or u.username or not u.path.startswith('/wiki/'):errors.append(book+' unsafe wiki '+p['id'])
    if not w['identityVerified']and not(w['kind']=='related-section'and w.get('relationVerified')and w['noteJa']):errors.append(book+' unqualified wiki '+p['id'])
   if p.get('coordinate'):errors.append(book+' unexpected promoted point '+p['id'])
 for x in d['occurrences']:
  if x['entityID']not in ids:errors.append(book+' dangling occurrence')
 books[book]={'profiles':len(ps),'contextVariants':sum(len(p.get('contextProfiles',[]))for p in ps),'canonicalVersesReviewed':total,'mappedVerses':len({(x['chapter'],x['verse'])for x in d['occurrences']}),'occurrences':len(actual),'wikipedia':sum(bool(p.get('wikipedia'))for b in ps for p in [b]+b.get('contextProfiles',[])),'catalogSHA256':hashlib.sha256(pth.read_bytes()).hexdigest()if(pth:=R/f'entity-profiles-{book}.json')else None}
result={'scope':'structural integration; semantic approval is separately SHA-bound in independent reviews','books':books,'errors':errors,'publication':'validation-only'}
print(json.dumps(result,ensure_ascii=False,indent=2));assert not errors
