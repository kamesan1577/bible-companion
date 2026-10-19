from pathlib import Path
import sys,json,hashlib
n=Path(__file__).resolve().parent;group=sys.argv[1];batch=sys.argv[2]if len(sys.argv)>2 else'batch01';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assignment=n/f'assignments/{batch}/{group}.json';a=json.loads(assignment.read_text());files=[];rows=[]
for p in(n/'drafts'/group).glob('*.json'):
 d=json.loads(p.read_text());r=d.get('review',{});pr=d.get('profile')or{};files.append((p,r.get('entityID')or pr.get('id'),r.get('book')or d.get('book')))
for item in a:
 found=[p for p,eid,book in files if eid==item['id']and book==item['book']];assert len(found)==1,(item['id'],len(found));p=found[0];es=[n/'evidence'/group/(p.stem+x)for x in ['.json','-sources.json']if(n/'evidence'/group/(p.stem+x)).exists()];assert len(es)==1
 rows.append({'book':item['book'],'entityID':item['id'],'draftPath':str(p.relative_to(n)),'draftSHA256':sha(p),'evidencePath':str(es[0].relative_to(n)),'evidenceSHA256':sha(es[0])})
revision=('-'+sys.argv[3])if len(sys.argv)>3 else''
out=n/f'reviews/{batch}-{group}-frozen-input{revision}.json';assert not out.exists(),'Preserve prior frozen input; pass a new revision name.';out.write_text(json.dumps({'scope':f'{batch} {group} only; author-fixed, not independently approved','records':rows,'count':len(rows),'assignmentSHA256':sha(assignment)},ensure_ascii=False,indent=2)+'\n');print(out.name,len(rows),sha(out))
