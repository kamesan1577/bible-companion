from pathlib import Path
import json
n=Path(__file__).resolve().parent;c=n/'candidate';r=c/'apps/ios/Sources/Core/Resources';ds={b:json.loads((r/('entity-profiles-'+b+'.json')).read_text())for b in ['1CH','2CH']}
flat=lambda d:[p for a in d['profiles']for p in [a]+a.get('contextProfiles',[])]
new=sum(len(d['profiles'])for d in ds.values());ctx=sum(len(flat(d))-len(d['profiles'])for d in ds.values());wiki=sum(bool(p.get('wikipedia'))for d in ds.values()for p in flat(d));coords={b:len({(e['chapter'],e['verse'])for e in d['occurrences']})for b,d in ds.items()}
counts={'newProfiles':new,'newContextVariants':ctx,'newWikiLinks':wiki,'newWikipediaLinks':wiki,'bookProfileRecords':2320+new,'bookContextVariants':27+ctx,'bookWikiLinksIncludingVariants':2198+wiki,'newLegacyCandidateMapEntries':0,'bookMapEntries':1044,'sourceCoordinatesReviewed':1764,'newRuntimeOccurrences':sum(len(d['occurrences'])for d in ds.values()),'runtimeCoveredSourceCoordinates':sum(coords.values())};(n/'release-counts.json').write_text(json.dumps(counts,indent=2)+'\n')
text=f'''# Bible Companion 0.1.16 preview (build 17)

歴代誌上・下の人物・地名の基本説明{new}件、文脈別説明{ctx}件、Wikipediaリンク{wiki}件を追加しました。
アプリで説明が表示されるのは{sum(coords.values())}節座標、計{counts['newRuntimeOccurrences']}件の人物・地名との対応です。
歴代誌上は{len(ds['1CH']['profiles'])}件、歴代誌下は{len(ds['2CH']['profiles'])}件の基本説明を収録する途中段階です。
全登場名や全節の詳細注解は完成していません。

固定したWorld English Bible全1,764節の本文対応を照合しました。
この原文対応の件数は、日本語説明の完成件数とは異なります。
AIが編集した日本語説明、原典、二次資料、独立レビューの状態を区別して記録しています。
同名人物や個人名と集団名が曖昧な候補、修正後の再照合が済んでいない候補は保留しました。
一次本文だけで裏付けられる一部の説明は、Wikipediaリンクを付けずに収録しています。

イスラエル個人、ガド、エフライムの説明は文脈に応じて切り替えます。
後の節で判明する情報と出典は、その節に到達してから表示します。
ヤベシュとヤベシュ・ギレアデ、バアラとキルヤテ・エアリムの確認済み用例は、同一のカードへまとめました。
未収録の箇所には、説明の作成途中であることを表示します。

新しい確認済み地図座標はありません。
専門家校閲、実機動作、署名済み共有AIの確認は未実施です。
既存の節注解、無料プラン、予算、認証設定は変更していません。

IPAはローカルのad-hoc署名で、SideStoreでの再署名が必要です。
元ソース、出典と権利表示、配布物の検証記録を同梱します。
'''
p=c/'docs/releases/v0.1.16-preview.1.md';p.write_text(text)
print(json.dumps(counts))
