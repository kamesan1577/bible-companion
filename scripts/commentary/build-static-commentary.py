#!/usr/bin/env python3
"""Convert official SWORD exports and API-audited verse maps into static PD data.
The SWORD engine is a build tool only; no library or executable enters the app.
"""
import argparse,collections,hashlib,html,json,re,runpy
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PIN={'MHC':('2.2','6bcb936873ca144e317805e5c1677940fd86e2403f7c14517752e44f25c8882b'),'JFB':('3.0','078ebd45ae6928b522a2739343187494b927d656870257be79cbdba39d3a3999'),'Easton':('2.0.1','f6dd054554764e2e97d5d189a697eb26039054578a9ccf98ce668ab810341c6e')}
def digest(b):return hashlib.sha256(b).hexdigest()
def entries(path):
 text=path.read_text();parts=re.split(r'^\$\$\$(.*)\n',text,flags=re.M)
 return list(zip(parts[1::2],(x.strip()for x in parts[2::2])))
class Plain(HTMLParser):
 def __init__(self):super().__init__(convert_charrefs=True);self.parts=[]
 def handle_starttag(self,tag,attrs):
  if tag in ['p','div','title','lb','br']:self.parts.append('\n')
 def handle_endtag(self,tag):
  if tag in ['p','title']:self.parts.append('\n')
 def handle_data(self,data):self.parts.append(data)
def plain(text):
 
 for _ in range(2):
  p=Plain();p.feed(text);p.close();text=''.join(p.parts)
 return re.sub(r'\n\s*\n+','\n\n',re.sub(r'[^\S\n]+',' ',text)).strip()
def runs(refs,order):
 refs=sorted(refs,key=lambda r:(order[r[0]],r[1],r[2]));out=[]
 for b,c,v in refs:
  if out and out[-1]['book']==b and out[-1]['start']['chapter']==c and out[-1]['end']['verse']==v-1:out[-1]['end']['verse']=v
  else:out.append({'book':b,'start':{'chapter':c,'verse':v},'end':{'chapter':c,'verse':v}})
 return out

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--cache',type=Path,default=ROOT/'.cache/commentary');ap.add_argument('--archives',type=Path,required=True);a=ap.parse_args()
 counts=json.loads((ROOT/'packages/core/src/verse-counts.json').read_text());canon=list(counts);order={b:i for i,b in enumerate(canon)}
 output=ROOT/'apps/ios/Sources/Core/Resources';catalog={'schemaVersion':1,'license':'public-domain','referenceSystem':'KJV','editions':[],'files':{},'coverage':{}}
 allmapped=set();report={}
 for name in ['MHC','JFB']:
  version,sha=PIN[name];assert digest((a.archives/(name+'.zip')).read_bytes())==sha
  raw=entries(a.cache/(name+'.imp'));raw_by_hash={digest(t.encode()):(k,t)for k,t in raw if t}
  names=list(dict.fromkeys(re.sub(r' \d+:\d+$','',k)for k,t in raw if re.search(r' \d+:\d+$',k)));assert len(names)==66;booknames=dict(zip(canon,names))
  rows=[json.loads(l)for l in (a.cache/(name+'-verse-map.ndjson')).read_text().splitlines()];assert len(rows)==31102
  groups=collections.defaultdict(list);missing=[];seen=set()
  for r in rows:
   b,c,v=r['ref'].split(':');c,v=int(c),int(v);assert b in counts and 1<=c<=len(counts[b])and 1<=v<=counts[b][c-1];assert r['ref']not in seen;seen.add(r['ref']);assert (r['actualBook'],r['chapter'],r['verse'])==(booknames[b],c,v)
   if r['bytes']:assert r['sha256']in raw_by_hash;groups[r['sha256']].append((b,c,v))
   else:missing.append(r['ref'])
  books=collections.defaultdict(list);nonprose=[];readable=set()
  for sha,refs in groups.items():
   loc,markup=raw_by_hash[sha];ranges=runs(refs,order);assert len(set(b for b,c,v in refs))==1
   body=plain(markup)
   if not body:nonprose.append({'sourceLocator':loc,'ranges':ranges});continue
   for b,c,v in refs:readable.add(f'{b}:{c}:{v}');allmapped.add(f'{b}:{c}:{v}')
   item={'id':name.lower()+':'+sha,'editionId':name+'-'+version,'sourceLocator':loc,'ranges':ranges,'originalText':body,'originalMarkupSha256':sha,'language':'en','kind':'passage-commentary','reviewStatus':'original-text-converted-not-editorially-reviewed','spoilerSafe':False}
   books[refs[0][0]].append(item)
  perbook={}
  for b in canon:
   records=sorted(books[b],key=lambda x:(x['ranges'][0]['start']['chapter'],x['ranges'][0]['start']['verse']));path=output/('commentary-'+name+'-'+b+'.json');data=(json.dumps(records,ensure_ascii=False,separators=(',',':'))+'\n').encode();path.write_bytes(data);catalog['files'][name+':'+b]={'file':path.name,'sha256':digest(data),'bytes':len(data),'units':len(records)};perbook[b]={'units':len(records),'linkedVerses':sum(len(v)for k,v in groups.items()if v[0][0]==b)}
  report[name]={'moduleVersion':version,'archiveSha256':PIN[name][1],'booksWithContent':sum(v['units']>0 for v in perbook.values()),'chaptersWithLinkedText':len(set((b,c)for refs in groups.values()for b,c,v in refs)),'canonicalCoordinates':31102,'rawLinkedNonemptyVerses':31102-len(missing),'linkedNonemptyVerses':len(readable),'independentCanonicalBodyUnits':sum(len(v)for v in books.values()),'nonProseUnits':nonprose,'officialExportUnitsIncludingIntroductions':len(raw),'missingCoordinates':missing,'perBook':perbook,'notClaimed':'No claim of independent or equally detailed commentary for every verse; headings excluded from canonical unit count'}
  catalog['editions'].append({'id':name+'-'+version,'title':"Matthew Henry's Complete Commentary"if name=='MHC'else'Jamieson-Fausset-Brown Commentary','authors':'Matthew Henry and continuators'if name=='MHC'else'Robert Jamieson, A. R. Fausset, David Brown','historicalDate':'early eighteenth century, later continuation/editing'if name=='MHC'else'1871','tradition':'historical Reformed/Presbyterian devotional'if name=='MHC'else'historical conservative Protestant','language':'en','license':'public-domain','licenseURL':'https://www.crosswire.org/sword/modules/ModInfo.jsp?modName='+name,'sourceURL':'https://www.crosswire.org/ftpmirror/pub/sword/packages/rawzip/'+name+'.zip','archiveSha256':PIN[name][1],'moduleVersion':version})
 name='Easton';version,sha=PIN[name];assert digest((a.archives/(name+'.zip')).read_bytes())==sha
 dictionary=[{'id':'easton:'+digest(k.encode()),'headword':k,'originalText':plain(t),'sourceLocator':k,'editionId':'Easton-2.0.1','reviewStatus':'original-not-editorially-reviewed','spoilerSafe':False}for k,t in entries(a.cache/'Easton.imp')if t];assert len(dictionary)==3963
 p=output/'commentary-Easton.json';data=(json.dumps(dictionary,ensure_ascii=False,separators=(',',':'))+'\n').encode();p.write_bytes(data);catalog['files']['Easton']={'file':p.name,'bytes':len(data),'sha256':digest(data),'entries':len(dictionary)}
 catalog['editions'].append({'id':'Easton-2.0.1','title':"Easton's Bible Dictionary",'authors':'M. G. Easton','historicalDate':'1897 third edition','tradition':'historical Scottish Presbyterian','language':'en','license':'public-domain','licenseURL':'https://www.crosswire.org/sword/modules/ModInfo.jsp?modName=Easton','sourceURL':'https://www.crosswire.org/ftpmirror/pub/sword/packages/rawzip/Easton.zip','archiveSha256':sha,'moduleVersion':version})
 catalog['coverage']={'MHC':report['MHC'],'JFB':report['JFB'],'unionLinkedVerses':len(allmapped),'dictionaryHeadwords':3963,'japaneseEditedRanges':0,'japaneseIndependentVerseExplanations':0}
 ja=runpy.run_path(str(ROOT/'scripts/commentary/audit-japanese.py'))['audit'](output)
 catalog['files']['JapaneseEdits']={k:ja[k] for k in ['file','bytes','sha256']}
 catalog['coverage'].update(japaneseEditedRanges=ja['editedRanges'],japaneseCoveredCoordinates=ja['coveredCoordinates'],japaneseIndependentVerseExplanations=ja['singleVerseEntries'],japaneseDetailedRanges=ja['detailedRanges'],independentAiReviewedRanges=ja['independentAiReviewedRanges'])
 identity={'editions':catalog['editions'],'files':catalog['files']};catalog['version']=digest(json.dumps(identity,sort_keys=True,separators=(',',':')).encode())
 (output/'commentary-catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':'))+'\n')
 (ROOT/'docs/commentary-coverage.json').write_text(json.dumps({'schemaVersion':1,'catalogVersion':catalog['version'],'conversion':'Official mod2imp plus official SWORD1.9.0 API for all canonical coordinates. Markup stripped to plain English. GPL engine used only at build time.','sourceBodyUnits':report,'unionLinkedVerses':len(allmapped),'dictionaryHeadwords':3963,'japaneseEditedRanges':ja['editedRanges'],'japaneseCoveredCoordinates':ja['coveredCoordinates'],'japaneseAudit':ja,'semanticQuality':'not asserted by nonempty/index coverage'},ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'catalogVersion':catalog['version'],'bytes':sum(f['bytes']for f in catalog['files'].values()),'unionLinkedVerses':len(allmapped),'MHC':report['MHC']['linkedNonemptyVerses'],'JFB':report['JFB']['linkedNonemptyVerses'],'JapaneseEditedRanges':ja['editedRanges']}))
if __name__=='__main__':main()
