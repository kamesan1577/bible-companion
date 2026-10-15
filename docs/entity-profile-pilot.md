# 人物・場所説明パイロット（未公開）

対象は使徒18:24–19:7。基準ソースは公開0.1.8のcommit 8f8d86850fdd17211088131d95d15d08600dfdc3。候補のバージョン表記は0.1.9/build10で、公開・署名配布は行っていない。

## 収録と実装

実際のTheographic節リンクから12項目を確定し、既存サーバーカードの安定ID person-disciples-act19を使う匿名集団1項目を補った。人物名・宗教的呼称8、匿名集団1、場所4。神・聖霊を人間の人物として紹介せず、洗礼者ヨハネ person:john_1676 と使徒ヨハネ person:john_1677 を区別する。アポロ、アキラ、プリスキラ、パウロも別IDを維持する。

apps/ios/Sources/Core/Resources/entity-profiles.json に日本語名・人物紹介・同名注意・現代位置・当時の役割・節別の追加事実・出典・利用条件を永続保存する。既存entity-index.jsonはバイト単位で変更していない。lookupと描画にAI/API呼び出しを追加していない。通常の人物・地図タブおよび共有拡張の共通部品から参照する。同じ書の別節リンクから人物・場所の一覧を開ける。範囲外にはこのパイロットの紹介を自動流用しない。

紹介の基本情報は選択末尾より前の本文に基づき、後の節の事実はknownByで分離した。使徒18:24だけでは18:25の洗礼についての情報を出さず、19:1だけでは集団の人数を出さない。「先の登場箇所も見る」を有効にすると追加事実と先の参照リンクを表示する。リンク先の外部原典には先の内容がある旨を表示する。

アカイアは属州であり、都市のピンを置かない。3都市の点はPleiadesの都市代表位置であり、出来事の建物や古代海岸線の復元ではない。古代コリントと現代市街を区別する。

## 原典・利用条件

人物紹介は同梱の固定版World English Bible（Public domain）の19節に照合し、原文はdata/entity-profiles/pilot-evidence/web-source-witnesses.jsonに保存した。日本語はAIによる編集で、既存日本語訳の転載ではない。専門家の校閲は未実施。

地理はPleiades公式データのcommit e0ad89cad8f55ab4b85138fb4f852d9ca07b1ebc、Alexandria727070/Ephesus599612/Corinth570182/Achaia981502に照合した。CC BY3.0のクレジット・リンク・編集内容を各説明に保持し、Corinth/Ephesus上流のOpenStreetMap ODbLクレジットも保持した。原データとSHA256、抜粋をpilot-evidenceへ同梱した。Pleiadesの経度・緯度をアプリの緯度・経度へ明示変換した。

人物・場所IDおよび節関連はTheographic Bible Metadata commit52e049efb3b95e4f1da52d11a3303fbd2d648922（CC BY-SA4.0）由来。既存の出典欄を保持し、この派生するID・節関連にもCC BY-SA4.0を維持する。World English BibleのPD、Pleiades CC BY3.0、OSM ODbLはそれぞれの原素材に継続適用される。既存コードのライセンスを変更しない。

古いEastonのアレクサンドリア図書館焼失伝承や都市住民に対する道徳的な一般化は採用していない。JFB節注解は本パイロットの生成元ではなく、旧注解作業は再開していない。

## 検証

Swift Core173件成功（追加4件は人物同定・境界・地理の回帰テスト）。実際のReadingViewの人物タブからアポロを開き、地図タブからアレクサンドリアの現在位置・当時の役割・出典を開くSimulator UIテスト1件成功。アプリと共有拡張のSimulatorビルド成功。スクリーンショット4点を成果物に添付。端末・SideStoreでの実機インストールと共有転送はこの候補では未確認。

verify-pilot.pyで実際の範囲内ID集合、13紹介、出典参照、3代表点の原データ一致、アカイアの点なし、元索引SHA256を検証した。パース成功のみを内容品質保証として扱っていない。

## 全件拡張の残件

既存索引は人物3067・場所1298で、今回の対象はそのうち12項目と匿名集団1件に限る。今回13紹介を全聖書完了と数えない。日本語名が既存で付いているのも人物96・場所31に限られ、未収録の紹介は明示的に未収録と表示する。

全件には、各節の実体リンク・同名人物・別名・同名都市の再点検、基本紹介と将来情報の区分、書をまたぐ読書順の定義、節番号差の確認、現代位置と古代地域の区別、不明地点の扱い、出典の個別利用条件の保持、専門家による内容校閲が必要。現行knownByはACT内のパイロット専用であり、このまま全聖書の時系列に一般化しない。地域形状の表示や不確実位置の視覚化も別途必要。自動生成・全件拡張・有料API利用・公開は開始していない。

## 作業時間

UTC開始2026-10-15T10:26:43Z。最終終了時刻と経過は成果物のtiming.jsonに記録する。これはツール待機を含む実経過であり、全件作業時間の見積りではない。

## UI保持の修正

0.1.8および0.1.1由来のPlaceMapViewを確認した。元の地図は、資料カードの「地図で概略位置を確認」から開くMapKit標準地図であり、相対的な点の位置図とは別に存在する。既存MaterialCardViewとPlaceMapViewを維持し、各カードおよび地図に人物・場所説明へのリンクを加えた。既存カードを先に表示し、それでカバーされない項目のみ同じBibleReadingSurfaceのカードとして補う。

比較画像はDEBUG専用で0.1.8のビュー原実装を名前変更して組み込み、公開ソースの既存資料カードを同じ選択範囲で表示して撮影した。公開IPAそのものの実機写真ではない。最初の試作画像は資料カードを空にしたfixtureであり、元の人物カードとMapKit地図の導線を示せていなかった。今回は人物カード、場所カード、MapKit地図を前後で比較し、カード・地図から説明画面への遷移も検証する。

説明文・追加事実・座標・出典は前版とのJSON比較で変更なし。既存カードIDとの接続情報のみ追加し、説明データを再生成していない。追加大量生成・公開は未実施。

## Wikipedia reading links

13 verified targets (9 Japanese / 4 English) were added as optional reading links. Aquila and Priscilla use distinct verified sections of a shared article; the unnamed disciples use an explicitly labelled related section of Acts 19, not an invented biography. See entity-profile-wikipedia-links.md for the Japanese mapping and identity checks. All URLs returned HTTP200 and all 3 section anchors exist. Existing prose, facts, coordinates and primary sources are byte-equivalent after removing the new optional wikipedia field. Wikipedia article text is not copied into profiles. The UI warns about future content. Core175 tests passed.

この文書の「未公開」およびpublished:falseは候補検証時点の記録です。本人承認後の0.1.9公開結果は、リリース添付の来歴・CI・匿名再取得記録を参照してください。

公開前検証で、旧UI比較用のDEBUG専用ビュー4件をTests/UIBaseline018へ配置し、アプリの比較描画時だけコンパイルする構成へ整理した。Swift PackageのCoreテストからは除外する。ビュー内容や本番表示は変更せず、デザイン検査への例外も追加していない。
