# Codex Lunaによる静的日本語編集

外部APIではなく、正規のCodexサブエージェント機能で `gpt-6-luna` を明示指定する。新しいAPIキー、プロバイダー接続、非公開API、認証情報抽出、追加の課金実行は不要。この仕組みはアプリ内の推論・Cloudflareの予算や設定を変更しない。

## 実装範囲

`scripts/commentary/codex-jobs.py` はネットワークを使わないSQLiteジョブ台帳。公式変換原典のハッシュ、原典の意味単位、対象範囲、一次本文ハッシュ、モデル、編集プロンプト版、レビュー版をパケットに固定し、その正規化SHA256をキャッシュキーにする。現行プランナーは完全なMHC原典単位と、その範囲内のJFB補助ノートを入力にする。自動的な文章切断はせず、4万文字を超える単位や、現行プランナーで表現できない複合範囲は手動分割の対象として止める。全書を無条件に自動分割できる完成品とはしない。

完了済みの同一入力は再実行しない。並列上限、開始間隔、試行回数、累計原典文字数をSQLiteトランザクションで制御する。leaseにより重複作業と古いワーカーの上書きを防ぎ、失敗した範囲だけ再試行する。revisionとeventに出力・判定・チェックポイントを保存する。枠不足や起動上限はpauseにし、別モデルや有料APIへ切り替えない。

生成後の機械検査は範囲・ID・出典・完全一致の引用・参照座標・人物候補・文数・重複を調べる。これだけで意味の正しさを確認済みとはしない。別のLunaワーカーが原典と本文を比較し、解釈の帰属・人物・先読み・主張の不足を点検する。レビューは出力のSHA256に結び付ける。モデルによる別段階の点検であり、独立した専門家校閲ではない。

## 操作

```sh
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work prepare --ranges 18:7-11,18:12-17,19:8-12 --max-workers 3 --max-attempts 3 --max-chars 200000 --min-spacing 1
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work claim --worker WORKER_ALIAS
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work status
```

Codexの担当エージェントはclaim後、返ったパケットだけを正規の `collaboration.spawn_agent` で配る。指定は `fork_turns="none", model="gpt-6-luna"`。既存の同モデルワーカーはfollowupで再利用できる。CLIはCodex内部の非公開APIを呼ばず、エージェントを自動起動する秘密の仕組みも持たない。起動が拒否されたら以下を記録し、保留にする。

```sh
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work fail --job JOB --lease LEASE --reason spawn-limit
# quota / worker-failed / cancelled も明示して記録可能
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work pause
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work resume
```

ワーカーはentry一件をJSONで返す。契約と実例は `docs/commentary-worker-contract.json`。`evidence.primaryRefs` は `ACT:18:7` 等の文字列配列。概ね1–5節、まとまり上必要なら最大8節、具体的な本文の意味を2–4文で説明する。日本語の句点数は機械検査上の代理指標であり、各節の意味の十分さは別段階で比較する。

```sh
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work submit --job JOB --lease LEASE --file OUTPUT.json
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work review --job JOB --file REVIEW.json
python3 scripts/commentary/codex-jobs.py --root .cache/luna-work export --file CANDIDATE.json
python3 scripts/commentary/inspect-candidate.py CANDIDATE.json --report REPORT.json
```

exportは全件の別ワーカー点検記録がpassになるまで拒否する。候補はアプリへ自動統合しない。既存の日本語説明との重複を解消し、正確な出典と一次本文版を維持して取り込む。原文対応・章概説・節範囲の具体的説明は別に集計する。

## 初回試走

3つのLunaワーカーを実際に指定起動し、使徒18:7–11、18:12–17、19:8–12の計16節を試した。原典入力は計34,109文字。6回のclaim（修正を含む）を経て、3件とも機械検査と別ワーカーの原典比較を通過した。参照を辞書で返す形式誤り、宿所変更と読める曖昧さ、18:10の保護の約束の説明不足を検出し、問題の範囲だけ修正した。

最初のclaimから最後の比較pass記録までは844.9秒（約14.1分）。基盤実装、手動の配布待ち、修正指示を含む壁時計時間で、安定したモデル単体速度ではない。外部API呼び出し・API費用は0。サブスク枠の消費量をこの試走だけへ帰属できるテレメトリーはない。並列上限はツール説明でrootを含む7枠、今回確認したのは子3並列のみ。サービス全体や他スレッドを含む無制限の並列数を意味しない。

この16節の成功を全巻の当日完成、31,102節の同粒度説明、専門家点検の完了へ外挿しない。次は文体・長さの異なる詩篇、書簡、系図等の小サンプルを同じゲートで計測し、修正率と待ち時間を含む実績を増やす。

## Libraryから受領した下書きの取扱い

正式なLibrary materializationで取得し、Mac上のサイズ・可読性・ZIP整合性・ハッシュを検証する。生ファイルは変更しない。

```sh
python3 scripts/commentary/stage-legacy-drafts.py --input EXTRACTED_DIRECTORY --output .cache/incoming-staging
```

統合版27–28を選び、古い章別JSON・同じ内容のMarkdownは重複取込しない。1–17、24–28の第0版では230範囲・795座標を取得したが、14:21が19–21と21–24で重複し、4:1–12と25:13–21は8節を超えた。原典の見出し自体の重なりや誤字をそのまま本文範囲へ拡大せず、両半節の意味を落とさずに再分割する。

KJVと手元のWEBの間には8:37、15:34、24:7の本文差がある。KJVで書かれた下書きを、WEBまたは共有された日本語訳で照合済みと自動判定しない。stagingの出典ID候補は意味の照合前で、evidenceは空のまま点検待ちにする。原典の字句・引用・人物IDを補ってから別段階で比較する。JSONの文数や欠落検査を通っただけの原稿は内容検証済みとしない。

## 使徒の統合（2026-10-15）

Library最新版3をMacで正式に取得し、566,665 bytes、ZIP CRC、版属性、SHA-256 `412a33a77f33537b8fb2cd2d8651d4b925a9118b5e85b1579e1352cadc9cb4ef` を確認した。旧版2の既存書巻原稿は状態メモ以外同一。旧版、章別の部分版、Markdownの写しは追加分として数えていない。

正規の `gpt-6-luna` 子ワーカー6件を指定起動し、既存使徒原稿の原典比較、18–23章の詳細化、別担当による本文・出典・同名人物・先読みの照合を分担した。構造だけを整えた初期候補は受け入れず、具体的な本文の欠落、未完文、空疎な定型句、原典にない帰属、先読み、KJVとWEBの違いを修正した。これはAIによる別段階の比較であり、独立した専門家校閲ではない。APIキー・有料API・課金設定の変更はない。

使徒は291範囲・1,004節座標をアプリへ収録する。18–23章の章概説は短い具体的説明に置き換え、既存の23:1と23:2–5は保持する。各範囲は最大8節、通常1–5節で、要約は2–4文。英語原文が同じ意味単位を共有する場合があり、出典IDを複数範囲で共有しても、本文座標を重ねて収録することはない。全書合計は294範囲で、使徒以外の従来の3サンプルを含む。

使徒8:37、15:34、24:7は手元のWEB本文にない。KJVに基づく下書きをそのままWEBに照合済みとせず、通常説明へ補作していない。31,102節座標中31,101に対応する英語原文の数は、日本語説明の完成数ではない。全聖書の同粒度説明と専門家校閲は未完。

受入判定は `data/commentary/acts-independent-reviews.json` に各候補の正規化SHA-256と5つの比較項目を保存した。候補内のdraft用reviewStatusはハッシュ照合のため保持し、最終受入はこの別台帳とアプリ文書のindependentReviewedEntryIdsで表す。改訂でハッシュが変わった範囲は再比較する。原文の英語引用は日本語説明の通常画面に出さず、英語原文全体を読む操作には従来どおり先読み同意を挟む。

創世記424範囲・1,533座標、ローマ250範囲・433座標、出エジプト記360範囲・1,213座標は未受入の下書きとして整理した。創世記とローマには座標重複が残り、ローマ3:9–18は粒度超過、16:25–27は手元のWEBとの対応が未確定。出エジプト記は13–18章の統合版を選び、13–15章の部分版は二重取込しない。これらの網羅検査を内容レビューとは扱わず、今回新規にアプリへ取り込まない。

JFB創世記9:25のアフリカ系の人々の奴隷化へ拡張する主張は通常説明へ採用せず、`data/commentary/editorial-exclusions.json` に原典IDと除外理由を残した。原典の保存、歴史的解釈の紹介、通常説明での採用判断を区別する。

### 追加受領版4

版4も別ディレクトリへ取得し、886,939 bytes、ZIP CRC、版属性、SHA-256 `14f1e39d2bd0448a7c1470e912bfabcfbfc4d37a8ec3497e99bc8f0f08b08cae` を確認した。版3の既存書巻原稿は状態メモ以外同一。レビ記236範囲・859座標、民数記386範囲・1,288座標、申命記25–34章71範囲・304座標を未受入の下書きとして正規化した。申命記1–24章はこのパックにはない。民数記13–24章は結合版を選び、分割版と二重計上しない。レビ記13–15章の部分版も13–18章の統合版と重ねない。

本文表示では一般的な出典注意や作業工程メモを繰り返さず、具体的な本文の要約を中心にする。原典の解釈・個別注の有無・具体的な版差は範囲ごとの資料欄に残し、一般的な出典と検証上の注意は整備状況欄で示す。
