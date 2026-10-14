#!/usr/bin/env python3
"""Build attributed CC BY-SA metadata only; never copies verse/dictionary prose."""
import json,re,hashlib,time,math
from pathlib import Path
root=Path(__file__).resolve().parents[1]; raw=root/'.cache/theographic'; out=root/'apps/ios/Sources/Core/Resources'
started=time.monotonic(); read=lambda n:json.loads((raw/(n+'.json')).read_text())
books,verses,people,places=map(read,['books','verses','people','places']);counts=json.loads((out/'verse-counts.json').read_text());canon=list(counts)
assert len(books)==66 and len(canon)==66
osis={b['fields']['osisName']:canon[b['fields']['bookOrder']-1] for b in books};orders={v:i+1 for i,v in enumerate(canon)}
ja={'God':'神','Holy Spirit':'聖霊','Jesus':'イエス','Jesus Christ':'イエス・キリスト','Christ':'キリスト','Paul':'パウロ','Saul':'サウル','Peter':'ペテロ','Simon Peter':'シモン・ペテロ','John':'ヨハネ','James':'ヤコブ','Barnabas':'バルナバ','Timothy':'テモテ','Titus':'テトス','Silas':'シラス','Luke':'ルカ','Mark':'マルコ','Apollos':'アポロ','Priscilla':'プリスキラ','Aquila':'アキラ','Sosthenes':'ソステネ','Felix':'フェリクス','Festus':'フェスト','Agrippa':'アグリッパ','Moses':'モーセ','Aaron':'アロン','Abraham':'アブラハム','Isaac':'イサク','Jacob':'ヤコブ','Joseph':'ヨセフ','David':'ダビデ','Solomon':'ソロモン','Joshua':'ヨシュア','Noah':'ノア','Adam':'アダム','Eve':'エバ','Mary':'マリア','Martha':'マルタ','Lazarus':'ラザロ','Pilate':'ピラト','Herod':'ヘロデ','Stephen':'ステパノ','Philip':'ピリポ','Judas':'ユダ','Matthew':'マタイ','Andrew':'アンデレ','Thomas':'トマス','Sarah':'サラ','Rebekah':'リベカ','Rachel':'ラケル','Leah':'レア','Ruth':'ルツ','Naomi':'ナオミ','Samuel':'サムエル','Elijah':'エリヤ','Elisha':'エリシャ','Isaiah':'イザヤ','Jeremiah':'エレミヤ','Daniel':'ダニエル','Jerusalem':'エルサレム','Israel':'イスラエル','Egypt':'エジプト','Rome':'ローマ','Corinth':'コリント','Ephesus':'エペソ','Antioch':'アンティオキア','Nazareth':'ナザレ','Bethlehem':'ベツレヘム','Galilee':'ガリラヤ','Samaria':'サマリア','Damascus':'ダマスコ','Jordan':'ヨルダン','Babylon':'バビロン','Capernaum':'カペナウム','Caesarea':'カイサリア','Tarsus':'タルソ','Athens':'アテネ','Philippi':'ピリピ','Thessalonica':'テサロニケ','Crete':'クレタ','Cyprus':'キプロス','Eden':'エデン','Canaan':'カナン','Sinai':'シナイ','Jericho':'エリコ','Bethany':'ベタニア'}
entities=[];indices={};patterns=[]
for kind,rows in [('person',people),('place',places)]:
 for row in rows:
  f=row['fields'];name=f.get('name') if kind=='person' else f.get('kjvName');name=name or f['displayTitle'];index=len(entities);indices[row['id']]=index
  entity={'id':kind+':'+f['slug'],'kind':kind,'name':name,'nameJa':ja.get(name),'appearances':[]}
  if kind=='place':
   try:
    lat,lon=float(f['latitude']),float(f['longitude'])
    if math.isfinite(lat) and math.isfinite(lon) and -90<=lat<=90 and -180<=lon<=180:
     entity['coordinate']=[lat,lon];entity['coordinateStatus']='source-verified-candidate' if f.get('recogitoStatus')=='VERIFIED' else 'unverified-candidate'
   except (KeyError,ValueError,TypeError):pass
  entities.append(entity);patterns.append(re.compile(r'(?<![A-Za-z])'+re.escape(name)+r'(?![A-Za-z])',re.I))
chapters={b+'.'+str(c+1):[] for b,cs in counts.items() for c in range(len(cs))};invalid=[];links=0
for row in verses:
 f=row['fields'];a=f['osisRef'].split('.');book=osis.get(a[0]);chapter,verse=map(int,a[1:])
 if not book or chapter>len(counts[book]) or verse>counts[book][chapter-1]:invalid.append(f['osisRef']);continue
 packed=orders[book]*1000000+chapter*1000+verse;group=[verse,[],[],[],[]];text=f.get('verseText','')
 for kind,key,offset in [('person','people',1),('place','places',3)]:
  for record_id in f.get(key,[]):
   index=indices.get(record_id)
   if index is None or entities[index]['kind']!=kind:continue
   group[offset if patterns[index].search(text) else offset+1].append(index)
   entities[index]['appearances'].append(packed);links+=1
 chapters[book+'.'+str(chapter)].append(group)
for values in chapters.values():values.sort(key=lambda v:v[0])
for e in entities:e['appearances']=sorted(set(e['appearances']))
sha=(raw/'commit.txt').read_text().strip();source='https://github.com/robertrouse/theographic-bible-metadata/tree/'+sha
result={'schemaVersion':1,'sourceURL':source,'sourceCommit':sha,'license':'CC-BY-SA-4.0','attribution':'Derived from Theographic Bible Metadata by Robert Rouse and contributors. Names and occurrence indexes only; prose removed, Japanese labels added, coordinates marked as candidates.','books':canon,'entities':entities,'chapters':chapters}
content=json.dumps(result,ensure_ascii=False,separators=(',',':')).encode();(out/'entity-index.json').write_bytes(content);(out/'entity-index-license.txt').write_bytes((raw/'LICENSE').read_bytes())
report={'schemaVersion':1,'sourceCommit':sha,'sourceURL':source,'license':'CC-BY-SA-4.0','sourceFiles':{p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in raw.glob('*.json') if p.name!='commit.json'},'outputBytes':len(content),'outputSha256':hashlib.sha256(content).hexdigest(),'buildSeconds':round(time.monotonic()-started,3),'books':len(canon),'chapters':len(chapters),'people':len(people),'places':len(places),'verses':sum(map(len,chapters.values())),'chaptersWithEntities':sum(any(any(r[1:]) for r in x) for x in chapters.values()),'entityLinks':links,'coordinates':sum('coordinate' in e for e in entities),'unmappedCanonicalReferences':invalid,'excludedFields':['verseText','mdText','richText','dictionaryText','dictText','birthYear','deathYear','familyRelations','images']}
(root/'docs/entity-index-provenance.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
