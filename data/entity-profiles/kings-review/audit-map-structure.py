"""Validate pinned map mechanics, never semantic approval or publication."""
from pathlib import Path
import collections, hashlib, json
K=Path(__file__).resolve().parent
index={e['id'] for e in json.loads((K/'candidate/apps/ios/Sources/Core/Resources/entity-index.json').read_text())['entities']}
allRows=[]; reports=[]
for path in sorted((K/'reviews').glob('verse-map-*.json')):
 d=json.loads(path.read_text());book=d['book'];fixed={(v['sourceChapter'],v['sourceVerse']):v for v in json.loads((K/f'inventory/targets/kings{1 if book=="1KI" else 2}-web-verses.json').read_text())};errors=[];seen=[]
 for row in d['verses']:
  cv=(row['chapter'],row['verse']); seen.append(cv); allRows.append((book,*cv)); witness=fixed.get(cv)
  if not witness: errors.append({'coordinate':cv,'type':'outside-fixed-witness'});continue
  text=row['sourceText'];url=row.get('citationURL',row.get('sourceURL'))
  if text!=witness['text'] or url!=witness['citationURL'] or row['sourceTextSHA256']!=hashlib.sha256(text.encode()).hexdigest():errors.append({'coordinate':cv,'type':'fixed-witness-mismatch'})
  ids=[e['entityID']for e in row['entities']]
  for entity in row['entities']:
   if entity['entityID'] not in index:errors.append({'coordinate':cv,'type':'unknown-ID','id':entity['entityID']})
   if entity['relationship'] not in ['direct','context']:errors.append({'coordinate':cv,'type':'invalid-relationship','id':entity['entityID']})
  if len(set(ids))!=len(ids):errors.append({'coordinate':cv,'type':'duplicate-ID'})
  for excluded in row.get('excludedCandidates',[]):
   eid=excluded.get('entityID')
   if eid and eid not in index:errors.append({'coordinate':cv,'type':'unknown-excluded-ID','id':eid})
  if set(ids)&{x.get('entityID')for x in row.get('excludedCandidates',[])}:errors.append({'coordinate':cv,'type':'simultaneously-included-and-excluded'})
 if len(set(seen))!=len(seen):errors.append({'type':'duplicate-coordinates'})
 reports.append({'path':str(path.relative_to(K)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'rows':len(seen),'errors':errors})
expected=set()
for b,n in [('1KI',1),('2KI',2)]:
 for v in json.loads((K/f'inventory/targets/kings{n}-web-verses.json').read_text()):expected.add((b,v['sourceChapter'],v['sourceVerse']))
counts=collections.Counter(allRows)
report={'maps':reports,'totalPresentCoordinates':len(counts),'expectedCoordinates':len(expected),'missingCoordinates':sorted(expected-set(counts)),'extraCoordinates':sorted(set(counts)-expected),'duplicateCoordinates':[cv for cv,count in counts.items()if count>1],'semanticApproval':False,'publicationApproved':False}
(K/'reviews/root-map-structural-preflight.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'coordinates':len(counts),'expected':len(expected),'rowErrors':sum(len(m['errors'])for m in reports),'missing':len(report['missingCoordinates']),'duplicates':len(report['duplicateCoordinates']),'semanticApproval':False}))
