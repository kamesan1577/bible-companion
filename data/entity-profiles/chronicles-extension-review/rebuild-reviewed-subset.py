from pathlib import Path
import subprocess,sys,datetime
n=Path(__file__).resolve().parent
steps=[['reconcile-current-reviews.py'],['normalize-staging.py','--reviewed-only'],['audit-reader-future-references.py'],['preview-reviewed-occurrence-edges.py'],['build-conservative-runtime-preview.py'],['build-qualified-primary-preview.py'],['build-reviewed-context-preview.py','qualified-primary-runtime-preview'],['build-reviewed-alias-preview.py'],['stage-reviewed-candidate.py','reviewed-alias-runtime-preview']]
p=n.parent/'chronicles-final-rebuild.log'
with p.open('w')as f:
 for a in steps:
  print('RUN',*a,flush=True);r=subprocess.run([sys.executable,*a],cwd=n,stdout=f,stderr=subprocess.STDOUT);f.flush()
  if r.returncode:raise SystemExit(r.returncode)
print('rebuild complete')
