#!/usr/bin/env python3
"""Mechanical evidence audit. This does not establish semantic/expert review."""
import gzip,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def audit(output):
 edits=json.loads((ROOT/'data/commentary/japanese-edits.json').read_text())
 units={u['id']:u for p in output.glob('commentary-*.json') if p.name.startswith(('commentary-MHC-','commentary-JFB-')) for u in json.loads(p.read_text())}
 primary={}
 with gzip.open(ROOT/'data/scripture/webp-2026-10-13/verses.ndjson.gz','rt') as f:
  for line in f:
   row=json.loads(line); c=row.get('canonical')
   if c and row.get('text'):primary[f"{c['book']}:{c['chapter']}:{c['verse']}"]=row['text']
 entities=json.loads((output/'entity-index.json').read_text()); byid={e['id']:e for e in entities['entities']}
 covered=set(); checks=0; ids=set(); samples=[]
 for e in edits['entries']:
  assert e['id'] not in ids;ids.add(e['id']); p=e['passage'];b=p['book'];s=p['start'];end=p['end']
  assert s['chapter']==end['chapter'] and s['verse']<=end['verse']
  refs={f"{b}:{s['chapter']}:{v}" for v in range(s['verse'],end['verse']+1)}
  assert refs<=primary.keys(),e['id'];covered|=refs
  assert e['spoilerEnd']==end
  assert set(e['sourceUnitIds'])<=units.keys()
  for ev in e['evidence']:
   assert ev['sourceUnitId'] in e['sourceUnitIds'];assert ev['quote'] in units[ev['sourceUnitId']]['originalText'],e['id']
   assert set(ev['primaryRefs'])<=refs,e['id'];checks+=1
  for person in e['people']:
   assert person['id'] in byid
   appearances=byid[person['id']]['appearances'];bn=entities['books'].index(b)+1
   identityrefs=person.get('identityEvidenceRefs',list(refs))
   for r in identityrefs:
    rb,rc,rv=r.split(':');assert rb==b and (int(rc),int(rv))<=(end['chapter'],end['verse']) and r in primary
   assert any(bn*1000000+int(r.split(':')[1])*1000+int(r.split(':')[2]) in appearances for r in identityrefs),(e['id'],person['id'])
  samples.append({'id':e['id'],'primaryText':{r:primary[r] for r in sorted(refs)},'evidence':e['evidence']})
 data=(json.dumps(edits,ensure_ascii=False,separators=(',',':'))+'\n').encode();(output/'commentary-ja.json').write_bytes(data)
 result={'editedRanges':len(ids),'coveredCoordinates':len(covered),'singleVerseEntries':sum(e['passage']['start']==e['passage']['end'] for e in edits['entries']),'acts18to23CoveredCoordinates':sum(r.startswith('ACT:') for r in covered),'exactOriginalQuoteChecks':checks,'primaryCoordinateChecks':True,'personOccurrenceChecks':True,'primaryCorpusDecompressedSha256':hashlib.sha256(gzip.decompress((ROOT/'data/scripture/webp-2026-10-13/verses.ndjson.gz').read_bytes())).hexdigest(),'expertReview':False,'semanticAccuracyEstablishedByThisAudit':False,'file': 'commentary-ja.json','bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
 counts=json.loads((ROOT/'packages/core/src/verse-counts.json').read_text())
 progress={'schemaVersion':1,'statusMeaning':'coordinates included in edited ranges or chapter overviews; not independently completed verse explanations','books':{b:{'canonicalCoordinates':sum(chs),'japaneseRangeCoordinates':sum(r.startswith(b+':') for r in covered),'chapterOverviews':[e['passage']['start']['chapter'] for e in edits['entries'] if e['passage']['book']==b and e['id'].endswith('chapter-overview')],'remainingWork':'source comparison, Japanese editing, identity checks, spoiler checks and independent editorial review'} for b,chs in counts.items()}}
 (ROOT/'docs/commentary-japanese-progress.json').write_text(json.dumps(progress,ensure_ascii=False,indent=2)+'\n')
 (ROOT/'docs/commentary-japanese-audit.json').write_text(json.dumps({'summary':result,'comparisonInputs':samples},ensure_ascii=False,indent=2)+'\n')
 return result
if __name__=='__main__': print(json.dumps(audit(ROOT/'apps/ios/Sources/Core/Resources'),ensure_ascii=False))
