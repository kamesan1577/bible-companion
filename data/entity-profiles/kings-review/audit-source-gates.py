"""Structural warnings only; independent reading is required for acceptance."""
from pathlib import Path
import json,hashlib,re
N=Path(__file__).resolve().parent;out=[]
def coord(x):return (x['chapter'],x['verse']) if x else None
for f in sorted((N/'drafts').glob('*/*.json')):
 if f.name=='progress.json':continue
 d=json.loads(f.read_text());p=d.get('profile')
 if not p or not p.get('passages'):continue
 book=d.get('review',{}).get('book')or d.get('book');issues=[];source={s['id']:s for s in d.get('sources',[])}
 first=min(coord(x['start'])for x in p['passages']);gate=coord(p.get('knownBy'))
 if gate is None or gate>first:issues.append({'type':'base-after-first-passage','gate':gate,'first':first})
 for label,obj in [('base',p)]+[(f'fact{i}',v)for i,v in enumerate(p.get('facts',[]))]:
  g=coord(obj.get('knownBy'))
  for sid in obj.get('sourceIds',[]):
   s=source.get(sid)
   if not s:issues.append({'type':'unresolved-source','field':label,'id':sid});continue
   sg=coord(s.get('knownBy'))
   if label!='base' and g and sg and sg>g:issues.append({'type':'citation-gate-later-than-visible-object','field':label,'id':sid,'objectGate':g,'sourceGate':sg})
   m=re.search(r'/'+str(book)+r'(\d+)\.htm#V(\d+)$',s.get('url',''))
   if m and sg and sg<tuple(map(int,m.groups())):issues.append({'type':'primary-source-gate-before-text','id':sid,'gate':sg,'url':s['url']})
 if issues:out.append({'group':f.parent.name,'file':str(f.relative_to(N)),'book':book,'id':p['id'],'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'warnings':issues})
(N/'source-gate-warnings.json').write_text(json.dumps({'semanticApproval':False,'records':out},ensure_ascii=False,indent=2)+'\n')
from collections import Counter
print(json.dumps({'warningRecords':len(out),'byGroup':Counter(x['group']for x in out),'byType':Counter(w['type']for x in out for w in x['warnings'])}))
