"""Mark independently source-crosschecked NUM/JOS data for a locally tested release candidate."""
from pathlib import Path
import json,hashlib,datetime,shutil
N=Path(__file__).resolve().parent;C=N/'candidate';B=C/'apps/ios/Sources/Core/Resources';D=C/'data/entity-profiles/num-jos-review';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
bindings=json.loads((N/'reviews/root-final-main-review-bindings.json').read_text());assert len(bindings['records'])==885 and not bindings['errors']
for r in bindings['records']:assert sha(N/r['draftPath'])==r['currentDraftSHA256'],r['draftPath']
assert json.loads((N/'reviews/final-closure-places_1.json').read_text())['publicationReadiness'].get('status')!='not-ready-wikipedia-evidence-open'
output={'preparedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'version':'0.1.12','build':'13','published':False,'mainDrafts':885,'sourceReviewBindingSHA256':sha(N/'reviews/root-final-main-review-bindings.json'),'resources':[]}
for book,count in [('NUM',1288),('JOS',658)]:
 f=B/f'entity-profiles-{book}.json';d=json.loads(f.read_text());d['editingDisclosureJa']='公開聖書本文と補助資料に基づくAIによる日本語編集です。独立の出典照合を行い、同名・地理の留保を記録しています。専門家の校閲はありません。'
 d['verification']={'publication':'release-build','expertReviewed':False,'independentReview':'source-cross-checked-with-documented-qualifications','sourceWitnessVersion':'webp-usfx-2026-10-13-35a6adf626e5','canonicalVerseCoordinates':count,'allSourceCoordinatesReviewed':count,'allNamedEntitiesComplete':False,'allVerseCommentaryComplete':False,'pendingCasesRetainedInSourceMaps':True,'newIndependentlyVerifiedCoordinates':0,'contentReviewLedger':'data/entity-profiles/num-jos-review/reviews/root-final-main-review-bindings.json','qualityReport':'data/entity-profiles/num-jos-review/final-quality-report.json','explicitAliasPolicy':'source-bound and gated to revealing verse; original authoring drafts preserved','contextReview':'data/entity-profiles/num-jos-review/reviews/independent-context-edits-NUM-postwiki.json' if book=='NUM' else 'data/entity-profiles/num-jos-review/reviews/closure-context-edits-JOS-postfix.json'}
 f.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');output['resources'].append({'file':str(f.relative_to(C)),'sha256':sha(f),'profiles':len(d['profiles']),'contextProfiles':sum(len(p.get('contextProfiles',[]))for p in d['profiles'])})
(N/'release-candidate-preparation.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n');print(json.dumps(output,ensure_ascii=False))
