#!/usr/bin/env python3
"""Reproduce exports with installed official SWORD tools; never downloads or installs."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
a=argparse.ArgumentParser();a.add_argument('--archives',type=Path,required=True);a.add_argument('--cache',type=Path,required=True);args=a.parse_args()
cache=args.cache.resolve();cache.mkdir(parents=True,exist_ok=False);sword=cache/'sword';sword.mkdir()
pins=runpy.run_path(str(ROOT/'scripts/commentary/build-static-commentary.py'))['PIN']
for name,(_,expected) in pins.items():
 raw=(args.archives/(name+'.zip')).read_bytes();assert hashlib.sha256(raw).hexdigest()==expected,name
 with zipfile.ZipFile(args.archives/(name+'.zip'))as z:
  assert sum(i.file_size for i in z.infolist())<100_000_000
  for i in z.infolist():
   target=(sword/i.filename).resolve();assert target.is_relative_to(sword) and (i.external_attr>>16)&0o170000!=0o120000
  z.extractall(sword)
env={**os.environ,'SWORD_PATH':str(sword)}
for name in pins:
 with (cache/(name+'.imp')).open('wb')as out:subprocess.run(['mod2imp',name],env=env,stdout=out,check=True)
text=(cache/'MHC.imp').read_text();keys=re.findall(r'^\$\$\$(.*)',text,re.M);names=list(dict.fromkeys(re.sub(r' \d+:\d+$','',k)for k in keys if re.search(r' \d+:\d+$',k)));assert len(names)==66
counts=json.loads((ROOT/'packages/core/src/verse-counts.json').read_text());refs=''.join(f'{b}:{c}:{v}\t{name} {c}:{v}\n'for (b,chs),name in zip(counts.items(),names)for c,n in enumerate(chs,1)for v in range(1,n+1));(cache/'canonical-refs.tsv').write_text(refs)
prefix=subprocess.check_output(['brew','--prefix','sword'],text=True).strip();exe=cache/'map-sword-verses'
subprocess.run(['clang++','-std=c++17','-I'+prefix+'/include/sword','-L'+prefix+'/lib','-lsword',str(ROOT/'scripts/commentary/map-sword-verses.cpp'),'-o',str(exe)],check=True)
for name in ['MHC','JFB']:
 with (cache/(name+'-verse-map.ndjson')).open('wb')as out:subprocess.run([str(exe),str(sword),name],input=refs.encode(),stdout=out,check=True)
print(json.dumps({'exports':list(pins),'canonicalCoordinatesPerCommentary':31102,'cache':str(cache)}))
