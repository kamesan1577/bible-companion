from pathlib import Path
import json
n=Path(__file__).resolve().parent;c=n/'candidate';r=c/'apps/ios/Sources/Core/Resources';ds={b:json.loads((r/f'entity-profiles-{b}.json').read_text())for b in ['1CH','2CH']};old={b:json.loads((n/f'candidate-v0.1.16-frozen/apps/ios/Sources/Core/Resources/entity-profiles-{b}.json').read_text())for b in ds};flat=lambda d:[p for a in d['profiles']for p in [a]+a.get('contextProfiles',[])]
new=sum(len(d['profiles'])for d in ds.values());ctx=sum(len(flat(d))-len(d['profiles'])for d in ds.values());wiki=sum(bool(p.get('wikipedia'))for d in ds.values()for p in flat(d));coords={b:len({(e['chapter'],e['verse'])for e in d['occurrences']})for b,d in ds.items()};delta=new-sum(len(d['profiles'])for d in old.values())
counts={'newProfiles':new,'extensionProfilesComparedWithV016':delta,'newContextVariants':ctx,'newWikiLinks':wiki,'newWikipediaLinks':wiki,'bookProfileRecords':2320+new,'bookContextVariants':27+ctx,'bookWikiLinksIncludingVariants':2198+wiki,'newLegacyCandidateMapEntries':0,'bookMapEntries':1044,'sourceCoordinatesReviewed':1764,'newRuntimeOccurrences':sum(len(d['occurrences'])for d in ds.values()),'runtimeCoveredSourceCoordinates':sum(coords.values())};(n/'extension-release-counts.json').write_text(json.dumps(counts,indent=2)+'\n')
text=f'''# Bible Companion 0.1.17 preview (build 18)

歴代誌上・下の人物・地名の基本説明を前版から{delta}件増やし、合計{new}件に拡充しました。
文脈別説明は{ctx}件、Wikipediaリンクは{wiki}件です。
説明が表示されるのは{sum(coords.values())}節座標、計{counts['newRuntimeOccurrences']}件の人物・地名との対応です。
歴代誌上は{len(ds['1CH']['profiles'])}件、歴代誌下は{len(ds['2CH']['profiles'])}件の基本説明を収録しています。
全登場名や全節の詳細注解は完成していません。

AIが編集した日本語説明を、固定したWorld English Bible本文と照合しました。
一次本文、二次資料、独立レビュー、保留状態を区別して記録しています。
固定WEB全1,764節の原文対応は、日本語説明の完成件数とは異なります。
同名人物、系譜、初出より後の情報を先取りする説明を再点検し、問題の残る候補は保留しました。
一次本文だけで裏付けられる一部の説明には、Wikipediaリンクを付けていません。
出典と情報は、対応する節に到達してから表示します。

新しい確認済み地図座標はありません。
専門家校閲、実機動作、署名済み共有AIの確認は未実施です。
既存の節注解、無料プラン、予算、認証設定は変更していません。
元ソースと編集・照合記録は、状態を明記して保存しています。
一部の古い中間記録には保存前に上書きされていたものがあり、保存済みとは扱いません。

IPAはローカルのad-hoc署名で、SideStoreでの再署名が必要です。
''';(c/'docs/releases/v0.1.17-preview.1.md').write_text(text);print(json.dumps(counts))
