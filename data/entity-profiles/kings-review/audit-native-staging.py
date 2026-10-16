"""Read-only native schema/content checks on reversible staging, no app activation."""
from pathlib import Path
import contextlib,io,json
K=Path(__file__).resolve().parent
script=K/'candidate/scripts/validate-kings-entities.py'
code=script.read_text().replace("R=Path(__file__).resolve().parents[1];A=R/'data/entity-profiles/kings-review';B=R/'apps/ios/Sources/Core/Resources'",f"R=Path({str(K)!r});A=R;B=R/'integrated-staging'")
code=code.replace("(B/'entity-index.json')","(R/'candidate/apps/ios/Sources/Core/Resources/entity-index.json')")
buffer=io.StringIO()
with contextlib.redirect_stdout(buffer):
 try:exec(compile(code,str(script),'exec'),{'__file__':str(script)})
 except AssertionError:pass
result=json.loads(buffer.getvalue());result['semanticApproval']=False;result['appResourcesWritten']=False
(K/'reviews/root-native-staging-preflight.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False))
raise SystemExit(bool(result['errors']))
