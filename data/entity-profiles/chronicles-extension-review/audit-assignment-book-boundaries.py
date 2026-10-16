from pathlib import Path
import json,re,hashlib,datetime,collections
N=Path(__file__).resolve().parent;assignments={};errors=[];rows=[]
for f in sorted((N/'assignments').glob('*.json')):
 if not isinstance(json.loads(f.read_text()),list):continue
 for item in json.loads(f.read_text()):
  key=(item['book'],item['id'])
  if key in assignments:errors.append({'type':'duplicate-full-book-ID-assignment','key':key})
  assignments[key]=f.stem
witness={}
for book,name in [('1CH','chronicles1'),('2CH','chronicles2')]:
 d=json.loads((N/f'inventory/targets/{name}-web-verses.json').read_text());items=d if isinstance(d,list)else d.get('verses',d.get('rows',[]));witness[book]={(r['canonical']['chapter'],r['canonical']['verse'])for r in items}
for f in sorted((N/'drafts').glob('*/*.json')):
 d=json.loads(f.read_text());review=d.get('review')or{};p=d.get('profile')or{};book=review.get('book')or d.get('book');eid=review.get('entityID')or p.get('id')
 if not book or not eid:continue
 key=(book,eid);problems=[]
 if assignments.get(key)!=f.parent.name:problems.append('book-ID-not-assigned-to-this-group')
 if not f.name.startswith(book+'_'):problems.append('filename-book-mismatch')
 for passage in p.get('passages',[]):
  if passage['book']!=book:problems.append('passage-book-mismatch')
  for field in ['start','end']:
   v=passage[field]
   if(v['chapter'],v['verse'])not in witness.get(book,set()):problems.append('passage-coordinate-outside-book')
 if p.get('passages'):
  for item in [p]+p.get('facts',[]):
   gate=item.get('knownBy')
   if not gate or(gate['chapter'],gate['verse'])not in witness.get(book,set()):problems.append('gate-coordinate-outside-book')
  own=[]
  for source in d.get('sources',[]):
   m=re.search(r'/engwebp/(1CH|2CH)(\d+)\.htm#V(\d+)$',source.get('url',''))
   if m and m[1]==book:
    own.append(source['id'])
    if(int(m[2]),int(m[3]))not in witness[book]:problems.append('primary-coordinate-outside-book')
  if not own:problems.append('no-current-book-primary-citation')
 rows.append({'path':str(f.relative_to(N)),'book':book,'id':eid,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'errors':sorted(set(problems))})
 errors.extend({'path':str(f.relative_to(N)),'type':x}for x in sorted(set(problems)))
out={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'counts':{'fullAssignedBookIDPairs':len(assignments),'draftPairs':len(rows),'draftBooks':dict(collections.Counter(r['book']for r in rows))},'errors':errors,'records':rows,'semanticApproval':False,'scope':'Assignment/book-coordinate integrity only; no identity or article approval'}
(N/'reviews/root-assignment-book-boundaries.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'counts':out['counts'],'errors':errors[:30]},ensure_ascii=False));raise SystemExit(bool(errors))
