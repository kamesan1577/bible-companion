#!/usr/bin/env python3
"""Offline job ledger for explicitly selected native Codex workers. No network/client/API keys."""
import argparse,datetime,gzip,hashlib,json,sqlite3,time,uuid,threading,functools,os,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
_local=threading.local()
def managed(fn):
 @functools.wraps(fn)
 def call(*args,**kwargs):
  previous=getattr(_local,'connections',None);_local.connections=[]
  try:return fn(*args,**kwargs)
  finally:
   for connection in _local.connections:connection.close()
   _local.connections=previous
 return call
PROMPT='sourced-japanese-native-codex-v2'
SCHEMA='japanese-edits-v1'
def sha(value):return hashlib.sha256(value if isinstance(value,bytes)else json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def read(path):return json.loads(Path(path).read_text())
def write(path,value):
 path=Path(path);temporary=None
 try:
  with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=path.parent,prefix='.'+path.name+'.',delete=False)as target:
   temporary=Path(target.name);target.write(json.dumps(value,ensure_ascii=False,indent=2)+'\n');target.flush();os.fsync(target.fileno())
  os.replace(temporary,path)
 finally:
  if temporary is not None:temporary.unlink(missing_ok=True)
def db_open(root):
 db=sqlite3.connect(root/'jobs.sqlite',timeout=10);db.row_factory=sqlite3.Row
 if getattr(_local,'connections',None)is not None:_local.connections.append(db)
 db.execute('PRAGMA journal_mode=WAL');db.executescript('''CREATE TABLE IF NOT EXISTS controls(key TEXT PRIMARY KEY,value TEXT);CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,packet TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,worker TEXT,lease TEXT,expires REAL NOT NULL DEFAULT 0,draft TEXT,review TEXT,error TEXT,updated REAL NOT NULL); CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY,job TEXT,kind TEXT,at REAL,details TEXT);CREATE TABLE IF NOT EXISTS revisions(job TEXT,attempt INTEGER,draft_sha TEXT,entry TEXT,review TEXT,PRIMARY KEY(job,attempt));CREATE TABLE IF NOT EXISTS limits(id INTEGER PRIMARY KEY CHECK(id=1),max_workers INTEGER,max_attempts INTEGER,max_chars INTEGER,min_spacing REAL,last_claim REAL DEFAULT 0,dispatched_chars INTEGER DEFAULT 0);''');return db
def event(db,j,kind,details=''):db.execute('INSERT INTO events(job,kind,at,details)VALUES(?,?,?,?)',(j,kind,time.time(),str(details)))
def load_sources(book):
 resources=ROOT/'apps/ios/Sources/Core/Resources';catalog=read(resources/'commentary-catalog.json');units=[]
 for name in ['MHC','JFB']:
  rec=catalog['files'][name+':'+book];raw=(resources/rec['file']).read_bytes();assert sha(raw)==rec['sha256'];units.extend(json.loads(raw))
 return catalog,units

@managed
def prepare(root,book,ranges,model='gpt-6-luna',max_workers=3,max_attempts=2,max_chars=200000,min_spacing=1):
 assert model=='gpt-6-luna','No silent model fallback';assert 1<=max_workers<=6 and 1<=max_attempts<=3 and 0<max_chars<=2000000 and min_spacing>=0
 root.mkdir(parents=True,exist_ok=True);(root/'packets').mkdir(exist_ok=True);(root/'outputs').mkdir(exist_ok=True);(root/'reviews').mkdir(exist_ok=True);catalog,units=load_sources(book)
 primary={}
 corpus=ROOT/'data/scripture/webp-2026-10-13/verses.ndjson.gz';primary_hash=sha(gzip.decompress(corpus.read_bytes()))
 with gzip.open(corpus,'rt')as f:
  for line in f:
   row=json.loads(line);c=row.get('canonical')
   if c and c['book']==book and row.get('text'):primary[f"{book}:{c['chapter']}:{c['verse']}"]=row['text']
 index=read(ROOT/'apps/ios/Sources/Core/Resources/entity-index.json');bn=index['books'].index(book)+1;counts=read(ROOT/'packages/core/src/verse-counts.json')[book];seen=set();db=db_open(root)
 db.execute('INSERT OR IGNORE INTO limits(id,max_workers,max_attempts,max_chars,min_spacing)VALUES(1,?,?,?,?)',(max_workers,max_attempts,max_chars,min_spacing))
 configured=db.execute('SELECT max_workers,max_attempts,max_chars,min_spacing FROM limits WHERE id=1').fetchone();assert tuple(configured)==(max_workers,max_attempts,max_chars,min_spacing),'Resume must preserve configured limits'
 for rawrange in ranges:
  chapter,vs=rawrange.split(':');start,end=map(int,vs.split('-'));chapter=int(chapter);assert 1<=chapter<=len(counts) and 1<=start<=end<=counts[chapter-1]
  coords=[f'{book}:{chapter}:{v}'for v in range(start,end+1)];assert not seen.intersection(coords),'Duplicate/overlapping planned range';seen.update(coords);assert set(coords)<=primary.keys(),'Missing primary text'
  passage={'book':book,'start':{'chapter':chapter,'verse':start},'end':{'chapter':chapter,'verse':end}}
  anchors=[u for u in units if u['editionId'].startswith('MHC-')and u['ranges']==[passage]];assert len(anchors)==1,'Use a complete original meaning unit; do not split/truncate prose'
  supporting=[u for u in units if u['editionId'].startswith('JFB-')and all(r['book']==book and r['start']['chapter']==chapter and start<=r['start']['verse']<=r['end']['verse']<=end for r in u['ranges'])]
  sources=[{'id':u['id'],'editionId':u['editionId'],'sourceLocator':u['sourceLocator'],'ranges':u['ranges'],'originalText':u['originalText'],'plainTextSha256':sha(u['originalText'].encode()),'originalMarkupSha256':u['originalMarkupSha256']}for u in anchors+supporting]
  context={r:t for r,t in primary.items()if r.startswith(f'{book}:{chapter}:')and int(r.split(':')[2])<start}
  entities=[{**e,'appearances':[n for n in e['appearances']if bn*1000000+chapter*1000+1<=n<=bn*1000000+chapter*1000+end]}for e in index['entities']if any(bn*1000000+chapter*1000+v in e['appearances']for v in range(1,end+1))]
  packet={'schemaVersion':1,'schema':SCHEMA,'promptVersion':PROMPT,'reviewPromptVersion':'independent-source-comparison-v1','execution':'native-codex-subscription-only','model':model,'sourceCatalogVersion':catalog['version'],'primaryCorpusDecompressedSha256':primary_hash,'passage':passage,'sources':sources,'primaryText':{r:primary[r]for r in coords},'priorIdentityContext':context,'entityCandidates':entities,'instructions':'出典付き日本語編集を1範囲だけ作る。summaryJaは対象の各節の主要な意味が分かる2〜4文とし、単なる粗い章概説にしない。evidence.primaryRefsはACT:18:7のような座標文字列の配列にする。本文観察・著者の解釈・編集上の注意を区別する。原文にない歴史的事実や後の展開を追加しない。原典内の将来への言及も要約へ移さない。意味の不確かさは明記する。同名だけで人物を結合しない。引用は原文の完全一致文字列、primaryRefsは対象節に限定する。元の日本語訳への適合や専門家監修を主張しない。原典の範囲全体を読んでから編集し、読めなければ完了扱いにしない。結果はスキーマのentry一件のみ。既存ファイル・アプリ・他の仕事の成果を編集しない。'}
  packet['sourceCharacters']=sum(len(s['originalText'])for s in sources);assert packet['sourceCharacters']<=40000,'Meaning unit exceeds pilot size; manual subdivision with an explicit assembly job required'
  key=sha(packet);packet['jobId']=key;write(root/'packets'/f'{key}.json',packet);db.execute('INSERT OR IGNORE INTO jobs(id,packet,updated)VALUES(?,?,?)',(key,json.dumps(packet,ensure_ascii=False),time.time()));event(db,key,'planned')
 db.commit();db.close();return status(root)

@managed
def status(root):
 db=db_open(root);result={'model':'gpt-6-luna','execution':'native Codex subscription; no API client or keys','states':dict(db.execute('SELECT state,count(*) FROM jobs GROUP BY state').fetchall()),'jobs':[dict(r)for r in db.execute('SELECT id,state,attempts,worker,expires,error FROM jobs ORDER BY rowid')],'limits':dict(db.execute('SELECT * FROM limits').fetchone())};db.close();return result

@managed
def claim(root,worker,now=None):
 now=time.time()if now is None else now;db=db_open(root);db.execute('BEGIN IMMEDIATE');limit=db.execute('SELECT * FROM limits').fetchone()
 paused=db.execute("SELECT value FROM controls WHERE key='paused'").fetchone()
 if paused and paused[0]=='1':db.commit();db.close();return None
 for row in db.execute("SELECT * FROM jobs WHERE state='leased' AND expires<=?",(now,)).fetchall():
  db.execute("UPDATE jobs SET state=CASE WHEN attempts>=? THEN 'blocked' ELSE 'pending' END,lease=NULL,error='lease expired; inspect prior output before retry',updated=? WHERE id=?",(limit['max_attempts'],now,row['id']));event(db,row['id'],'lease-expired')
 if db.execute("SELECT count(*) FROM jobs WHERE state='leased'").fetchone()[0]>=limit['max_workers'] or now<limit['last_claim']+limit['min_spacing']:db.commit();db.close();return None
 row=db.execute("SELECT * FROM jobs WHERE state='pending' AND attempts<? ORDER BY rowid LIMIT 1",(limit['max_attempts'],)).fetchone()
 if not row:db.commit();db.close();return None
 packet=json.loads(row['packet']);key=packet.pop('jobId');assert sha(packet)==key,'Corrupt packet';packet['jobId']=key
 if limit['dispatched_chars']+packet['sourceCharacters']>limit['max_chars']:db.commit();db.close();return None
 token=str(uuid.uuid4());db.execute("UPDATE jobs SET state='leased',worker=?,lease=?,expires=?,attempts=attempts+1,updated=? WHERE id=?",(worker,token,now+900,now,row['id']));db.execute('UPDATE limits SET last_claim=?,dispatched_chars=dispatched_chars+? WHERE id=1',(now,packet['sourceCharacters']));event(db,row['id'],'claimed',worker);db.commit();db.close();return {'jobId':row['id'],'lease':token,'packet':str(root/'packets'/f"{row['id']}.json"),'output':str(root/'outputs'/f"{row['id']}.json"),'worker':worker}

def inspect_entry(entry,packet):
 errors=[];p=packet['passage'];allowed=set(packet['primaryText']);sources={s['id']:s for s in packet['sources']};candidates={e['id']:e for e in packet['entityCandidates']}
 required={'id','passage','titleJa','summaryJa','authorInterpretationJa','editorialNoteJa','sourceUnitIds','evidence','people','editingMethod','reviewStatus','spoilerEnd'}
 if not isinstance(entry,dict)or set(entry)!=required:return ['exact entry schema']
 if entry['passage']!=p or entry['spoilerEnd']!=p['end']:errors.append('range/boundary')
 for field in ['titleJa','summaryJa','authorInterpretationJa','editorialNoteJa']:
  if not isinstance(entry[field],str)or not entry[field].strip()or not any('\u3040'<=c<='\u9fff'for c in entry[field]):errors.append('Japanese text: '+field)
 expected=f"ja-v1:{p['book']}:{p['start']['chapter']}:{p['start']['verse']}-{p['end']['verse']}"
 if entry['id']!=expected:errors.append('entry id')
 if p['start']['chapter']!=p['end']['chapter']or p['end']['verse']-p['start']['verse']+1>8:errors.append('density: range over 8 verses')
 if isinstance(entry['summaryJa'],str)and not 2<=entry['summaryJa'].count('。')<=4:errors.append('density: summary requires 2-4 sentences')
 ids=entry['sourceUnitIds']
 if not isinstance(ids,list)or not ids or not all(isinstance(x,str)for x in ids)or len(set(ids))!=len(ids)or not set(ids)<=sources.keys():errors.append('source identities');ids=[]
 if not isinstance(entry['evidence'],list)or not entry['evidence']:errors.append('evidence required')
 else:
  for e in entry['evidence']:
   if not isinstance(e,dict)or set(e)!={'sourceUnitId','quote','primaryRefs'}:errors.append('evidence schema');continue
   sid=e['sourceUnitId'];s=sources.get(sid)if isinstance(sid,str)else None;quote=e['quote'];refs=e['primaryRefs']
   if e['sourceUnitId']not in ids or not s or not isinstance(quote,str)or len(quote.strip())<10 or quote not in s['originalText']:errors.append('exact original quote')
   if not isinstance(refs,list)or not refs or not all(isinstance(x,str)for x in refs)or len(set(refs))!=len(refs)or not set(refs)<=allowed:errors.append('bounded primary references')
 if not isinstance(entry['people'],list):errors.append('people array')
 else:
  seen=set()
  for person in entry['people']:
   if not isinstance(person,dict)or not {'id','nameJa','roleJa','identityStatus'}<=person.keys():errors.append('person schema');continue
   if not isinstance(person['id'],str):errors.append('person identity');continue
   if person['id']not in candidates or person['id']in seen:errors.append('person identity')
   seen.add(person['id'])
   if not person['nameJa']or not person['roleJa']or person['identityStatus']not in ['source-sense-compared','uncertain','prior-context-identified']:errors.append('person role/status')
 if entry['editingMethod']!='Codex gpt-6-luna source-based Japanese editorial summary; not a literal translation':errors.append('editing disclosure')
 if entry['reviewStatus']!='draft-awaiting-independent-source-review; no expert review':errors.append('review disclosure')
 return sorted(set(errors))

@managed
def submit(root,key,lease,path,now=None):
 now=time.time()if now is None else now;db=db_open(root);db.execute('BEGIN IMMEDIATE');row=db.execute('SELECT * FROM jobs WHERE id=?',(key,)).fetchone();assert row and row['state']=='leased' and row['lease']==lease and row['expires']>now,'Stale or foreign lease'
 entry=read(path);db.execute('INSERT OR IGNORE INTO revisions(job,attempt,draft_sha,entry)VALUES(?,?,?,?)',(key,row['attempts'],sha(entry),json.dumps(entry,ensure_ascii=False)));errors=inspect_entry(entry,json.loads(row['packet']));state='draft'if not errors else ('blocked'if row['attempts']>=db.execute('SELECT max_attempts FROM limits').fetchone()[0]else'pending')
 db.execute('UPDATE jobs SET state=?,draft=?,error=?,lease=NULL,expires=0,updated=? WHERE id=?',(state,json.dumps(entry,ensure_ascii=False),json.dumps(errors),now,key));event(db,key,'structural-pass'if not errors else'structural-fail',errors);db.commit();db.close();return {'jobId':key,'state':state,'errors':errors,'semanticReviewPassed':False}

@managed
def record_review(root,key,path):
 report=read(path);required={'jobId','draftSha256','reviewer','sourceCompared','primaryCompared','identityCompared','spoilerCompared','interpretationSeparated','verdict','notes'};assert set(report)==required and report['jobId']==key and report['verdict']in ['pass','revise','reject'] and report['reviewer'] and report['notes'];db=db_open(root);db.execute('BEGIN IMMEDIATE');row=db.execute('SELECT * FROM jobs WHERE id=?',(key,)).fetchone();assert row and row['state']=='draft';assert report['reviewer']!=row['worker'],'Different reviewer required';draft=json.loads(row['draft']);assert sha(draft)==report['draftSha256'],'Review must bind exact output';assert all(report[x]is True for x in ['sourceCompared','primaryCompared','identityCompared','spoilerCompared','interpretationSeparated']);state={'pass':'source-reviewed','revise':('pending'if row['attempts']<db.execute('SELECT max_attempts FROM limits').fetchone()[0]else'blocked'),'reject':'blocked'}[report['verdict']]
 db.execute('INSERT OR IGNORE INTO revisions(job,attempt,draft_sha,entry)VALUES(?,?,?,?)',(key,row['attempts'],sha(draft),row['draft']));db.execute('UPDATE revisions SET review=? WHERE job=? AND attempt=?',(json.dumps(report,ensure_ascii=False),key,row['attempts']));db.execute('UPDATE jobs SET state=?,review=?,updated=? WHERE id=?',(state,json.dumps(report,ensure_ascii=False),time.time(),key));event(db,key,'independent-review',report['verdict']);db.commit();db.close();return {'jobId':key,'state':state,'expertReview':False}

@managed
def export(root,path):
 db=db_open(root);jobs=db.execute('SELECT * FROM jobs ORDER BY rowid').fetchall();assert jobs and all(j['state']=='source-reviewed'for j in jobs),'Do not export missing/duplicate/failed/unreviewed jobs';entries=[json.loads(j['draft'])for j in jobs];assert len({e['id']for e in entries})==len(entries);assert not Path(path).exists();write(path,{'schemaVersion':1,'status':'candidate-only; not automatically merged into the app','model':'gpt-6-luna','promptVersion':PROMPT,'entries':entries,'reviews':[json.loads(j['review'])for j in jobs]});db.close();return {'candidate':str(path),'entries':len(entries),'appChanged':False}

@managed
def pause(root,paused=True):
 db=db_open(root);db.execute("INSERT INTO controls(key,value)VALUES('paused',?) ON CONFLICT(key)DO UPDATE SET value=excluded.value",('1'if paused else'0',));event(db,None,'paused'if paused else'resumed');db.commit();db.close();return {'paused':paused,'runningWorkersInterrupted':False}
@managed
def fail(root,key,lease,reason):
 assert reason in ['spawn-limit','quota','worker-failed','cancelled'];db=db_open(root);db.execute('BEGIN IMMEDIATE');row=db.execute('SELECT * FROM jobs WHERE id=?',(key,)).fetchone();assert row and row['state']=='leased'and row['lease']==lease,'Stale/foreign failure';limit=db.execute('SELECT max_attempts FROM limits').fetchone()[0];state='pending'if row['attempts']<limit else'blocked';db.execute('UPDATE jobs SET state=?,lease=NULL,expires=0,error=?,updated=? WHERE id=?',(state,reason,time.time(),key));event(db,key,'dispatch-failed',reason)
 if reason in ['quota','spawn-limit']:db.execute("INSERT INTO controls(key,value)VALUES('paused','1') ON CONFLICT(key)DO UPDATE SET value='1'")
 db.commit();db.close();return {'state':state,'paused':reason in ['quota','spawn-limit'],'modelFallback':False}

if __name__=='__main__':
 a=argparse.ArgumentParser();a.add_argument('--root',type=Path,required=True);s=a.add_subparsers(dest='command',required=True);p=s.add_parser('prepare');p.add_argument('--book',default='ACT');p.add_argument('--ranges',required=True);p.add_argument('--max-workers',type=int,default=3);p.add_argument('--max-attempts',type=int,default=2);p.add_argument('--max-chars',type=int,default=200000);p.add_argument('--min-spacing',type=float,default=1);p=s.add_parser('claim');p.add_argument('--worker',required=True);p=s.add_parser('submit');p.add_argument('--job',required=True);p.add_argument('--lease',required=True);p.add_argument('--file',type=Path,required=True);p=s.add_parser('review');p.add_argument('--job',required=True);p.add_argument('--file',type=Path,required=True);p=s.add_parser('export');p.add_argument('--file',type=Path,required=True);p=s.add_parser('fail');p.add_argument('--job',required=True);p.add_argument('--lease',required=True);p.add_argument('--reason',choices=['spawn-limit','quota','worker-failed','cancelled'],required=True);s.add_parser('pause');s.add_parser('resume');s.add_parser('status');args=a.parse_args();root=args.root.resolve()
 if args.command=='prepare':r=prepare(root,args.book,args.ranges.split(','),max_workers=args.max_workers,max_attempts=args.max_attempts,max_chars=args.max_chars,min_spacing=args.min_spacing)
 elif args.command=='claim':r=claim(root,args.worker)
 elif args.command=='submit':r=submit(root,args.job,args.lease,args.file)
 elif args.command=='review':r=record_review(root,args.job,args.file)
 elif args.command=='export':r=export(root,args.file)
 elif args.command=='fail':r=fail(root,args.job,args.lease,args.reason)
 elif args.command in ['pause','resume']:r=pause(root,args.command=='pause')
 else:r=status(root)
 print(json.dumps(r,ensure_ascii=False,indent=2))
