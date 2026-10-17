from pathlib import Path
import json,hashlib,datetime
N=Path(__file__).resolve().parent
out={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'published':False,'scope':'AI-edited Japanese entity preview; independent source reviews, not expert certification or all-named-entity completion','resources':[]}
for book in ['1KI','2KI']:
 p=N/f'candidate/apps/ios/Sources/Core/Resources/entity-profiles-{book}.json'; d=json.loads(p.read_text())
 d['editingDisclosureJa']='公開原典に基づくAI日本語編集の人物・地名説明です。固定WEB本文と出典を別担当で照合しています。専門家による監修済み資料ではなく、同定できない人物・地名や位置の不確実性を残すプレビュー版です。'
 d['verification']={'publication':'release-candidate','independentSourceReview':'current-draft-and-evidence-bound','sourceWitnessVersion':'webp-usfx-2026-10-13-35a6adf626e5','allSourceCoordinatesReviewed':816 if book=='1KI'else 719,'allNamedEntitiesComplete':False,'pendingCasesRetainedInSourceMaps':True,'expertReviewed':False}
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');out['resources'].append({'book':book,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'baseProfiles':len(d['profiles']),'contexts':sum(len(x.get('contextProfiles',[]))for x in d['profiles']),'wikipediaLinks':sum(bool(x.get('wikipedia'))+sum(bool(c.get('wikipedia'))for c in x.get('contextProfiles',[]))for x in d['profiles'])})
(N/'candidate-metadata-finalization.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps(out,ensure_ascii=False))
