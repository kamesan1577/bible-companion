"""Prepare unapproved verse review inputs; never derive approval from raw index matches."""
from pathlib import Path
import json,hashlib
N=Path(__file__).resolve().parent;dest=N/'verse-review-inputs';dest.mkdir(exist_ok=True)
targets=json.loads((N/'inventory/targets.json').read_text())['books'];manifest=[]
for book,name,chunks in [('1CH','chronicles1',[(1,9),(10,19),(20,29)]),('2CH','chronicles2',[(1,12),(13,24),(25,36)])]:
 src=N/'inventory/targets'/f'{name}-web-verses.json';raw=json.loads(src.read_text());assert len(raw)==(942 if book=='1CH'else 822)
 bycoord={}
 for t in targets[book]:
  for a in t['appearances']:bycoord.setdefault((a['chapter'],a['verse']),[]).append({'entityID':t['id'],'kind':t['kind'],'name':t['name'],'status':'unverified-index-candidate'})
 for start,end in chunks:
  out={'book':book,'chapters':[start,end],'fixedWitnessSHA256':hashlib.sha256(src.read_bytes()).hexdigest(),'status':'unreviewed-input-only','instructionsJa':'全節の固定WEB本文を読み、人物・民族・地名・地理/祭儀範囲を文脈で区別する。rawCandidatesは誤対応や欠落を含む。採用は既存IDと現原稿の根拠を照合し、未マップ節にも理由を記す。未来の知識から人物を推定せず、原典から独立に関係を判断する。','verses':[]}
  for v in raw:
   c=v['canonical'];ch,verse=c['chapter'],c['verse']
   if start<=ch<=end:out['verses'].append({'chapter':ch,'verse':verse,'text':v['text'],'citationURL':v['citationURL'],'rawCandidates':bycoord.get((ch,verse),[]),'reviewStatus':'unreviewed'})
  p=dest/f'{book}-{start:02}-{end:02}.json';p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');manifest.append({'path':p.relative_to(N).as_posix(),'verses':len(out['verses']),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
assert sum(x['verses']for x in manifest)==1764
(dest/'manifest.json').write_text(json.dumps({'status':'unreviewed','canonicalVerses':1764,'chunks':manifest},indent=2)+'\n');print(json.dumps(manifest))
