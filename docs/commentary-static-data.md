# 静的解説データの状態

MHC 2.2、JFB 3.0、Easton 2.0.1 の公式 SWORD パッケージを SHA256 で固定し、SWORD 1.9.0 の公式 API と mod2imp で変換した。SWORD は変換用ツールのみで、iOS にリンクしない。

MHC の本文対応は31,098 / 31,102座標、JFBは24,813 / 31,102座標、和集合は31,101座標。Easton は3,963見出し。本文が複数節で共用されるため、各節に独立した説明があることや意味の正確性を表す数字ではない。全文英語原文は後続箇所への言及を含み得るため spoilerSafe=false とする。

日本語は18範囲・215節座標。使徒18–23章に六つの章概説を追加し、六章212節座標を概説の対象とする。各節の独立した詳細注解が完成したという意味ではない。創世記1:1、詩篇23:1、ローマ9:1も収録。出典の英語原文、出典に基づく日本語要約、著者の信仰的解釈、編集上の注意を別フィールドに保持する。35件の英語引用・章見出し一致、一次本文の座標存在、人物ID・出現または明示した先行文脈を機械検証した。これは意味の正しさや専門家監修の証明ではない。一次本文は既存WEBのバージョンを使用し、日本語訳との全座標同一性は主張しない。

人物を名前だけで結合しない。使徒23章のアナニアは大祭司person:ananias_260。20:17–21と22:1–2のパウロは、選択節で名前が明示されないため先行文脈の根拠を別記した。

原文はパブリックドメイン。日本語編集の権利はアプリ本文として別扱いにし、人物索引のCC-BY-SA-4.0とは混同しない。現代の学術的合意を代表する解説とは表示しない。

## 再現

公式パッケージを用意し、公式SWORD（mod2imp、開発ヘッダー）、clang++、Homebrewが利用可能なMacで再現する。作業用キャッシュは新規のパスを指定する。ネットワーク取得やツール追加はこのスクリプトでは行わない：

```sh
python3 scripts/commentary/prepare-official-exports.py --archives PATH_TO_VERIFIED_ARCHIVES --cache .cache/commentary-new
python3 scripts/commentary/build-static-commentary.py --archives PATH_TO_VERIFIED_ARCHIVES --cache .cache/commentary-new
python3 scripts/commentary/audit-japanese.py
```

`docs/commentary-coverage.json` は全書対応監査、`docs/commentary-japanese-audit.json` は日本語比較に用いる一次本文と引用証拠。`data/commentary/japanese-edits.json` が編集入力、`commentary-ja.json` がバンドル用出力。入力または引用の不整合は変換時に失敗する。

## 未完

iOSの読書画面に静的説明を標準表示し、英語全文は明示した先読み同意後に開く実装を追加した。AI補足は別画面から任意に利用する。ライト・ダーク実画面確認と更新IPAは作業中。英語辞典の検索と、ログインせず章から保存注解を開く導線も追加した。既存0.1.3は変更していない。新たな課金、クラウド公開、アプリ内AI大量生成は行っていない。

## サムエル記下22:1

公式SWORD APIはMHC/JFBとも22:1に空の本文を返し、出力座標はII Samuel 22:1と一致した。mod2impにも同座標のエントリーはない。一方MHCの22:2エントリーには1節を含む詩の引用があり、22:0には章導入がある。原典本文全体の消失ではなく、配布モジュール内の節への割り当てによる対応欠落。自動的な22:1への付け替え・対応数の水増しは行わない。

全書の再開状況は`docs/commentary-japanese-progress.json`に書別の章概説・編集対象座標として保存する。未整備の書を原文対応だけで完成扱いにしない。
