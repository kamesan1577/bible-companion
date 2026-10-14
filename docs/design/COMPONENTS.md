# コンポーネント契約

共通部品は `apps/ios/Sources/DesignSystem` に置きます。
機能側は意味とデータを渡し、色、書体、角、余白、動きの数値を持ちません。

| 部品・API | 責務 | 使わない場所 |
|---|---|---|
| `BibleTheme.color(_:scheme:increasedContrast:)` | 意味に対応した Light / Dark の不透明色 | 標準バーの材質を上書きする用途 |
| `.bibleForeground(_:)` | 外観と Increase Contrast に対応する文字色 | ガラス上の標準ラベルの無理な再着色 |
| `.bibleTextStyle(_:)` | システム文字スタイルと読みやすい本文行間 | 固定サイズのロゴ風表示 |
| `.bibleCanvas()` | 内容側の背景とアクセント | 個々の toolbar に追加する背景 |
| `BibleReadingColumn { ... }` | 最大幅、左右余白、縦の読書リズム | 標準 Form や List の余白を二重にする用途 |
| `BibleReadingSurface { ... }` | 不透明な関連情報のグループ | 項目ごとの無制限なカード化 |
| `BibleSectionHeader(title:subtitle:)` | 見出しと補足、VoiceOver 見出し | 装飾だけの見出し |
| `BibleRangeBadge(text:)` | 範囲の短い補助表示 | タップできるように見せる疑似ボタン |
| `BibleScopeNotice(text:)` | 選択全体・終端などの範囲説明 | 曖昧な「安全です」表示 |
| `BibleActionLabel(title:systemImage:)` | 標準 Button 内のラベルと最小高さ | Button の代わりのタップジェスチャ |
| `BibleStateView(title:message:systemImage:)` | 空、失敗、未対応の説明 | 失敗を成功風に見せる用途 |
| `BibleLoadingView(title:message:)` | 標準 ProgressView と短い状況説明 | 偽の進捗率や無期限の演出 |
| `.bibleStateAnimation(value:)` | 内容の局所的な状態変化。Reduce Motion で停止 | sheet、タブ、戻る操作の独自アニメーション |
| `.bibleSelectionFeedback(trigger:)` | 明示的な選択の触覚 | 自動更新、ストリーミング |
| `.bibleSuccessFeedback(trigger:)` | 確定した保存の触覚 | 通信前の楽観的な成功表示 |

`BibleActionLabel` 自体は Button ではありません。
アクション、disabled、role、アクセシビリティの意味、ネイティブな押下表現は呼び出し元の標準 Button が持ちます。
範囲を表示するバッジも操作ではありません。変更できる場合は、別の標準 Button または Menu で示します。

## 使用例

```swift
ScrollView {
    BibleReadingColumn {
        BibleSectionHeader(title: "使徒の働き", subtitle: "YouVersion から共有")
        Text(selection.displayReference).bibleTextStyle(.verseReference)
        BibleRangeBadge(text: selection.scopeDescription)
        BibleScopeNotice(text: selection.endBoundaryDescription)
        BibleReadingSurface {
            Text(explanation).bibleTextStyle(.body).bibleForeground(.textPrimary)
        }
        Button { showsQuestion = true } label: {
            BibleActionLabel(title: "この範囲について質問", systemImage: BibleTheme.Symbol.question)
        }
        .buttonStyle(.bordered)
    }
}
.bibleCanvas()
```

例の変数名は呼び出し方を示すもので、データ層の型を規定しません。
入力・認証・課金などの機能責務をデザインシステムに持ち込みません。

## 標準部品をそのまま使う領域

NavigationStack、NavigationLink、TabView、toolbar、sheet、Menu、Button、Picker、Form、List、Toggle、TextField、TextEditor は原則として標準 API を使います。
標準ラベルには `.primary` / `.secondary` などシステムの意味色を使っても構いません。
システム側が持つガラス、文字サイズ、フォーカス、戻る動作をカスタム部品で複製しません。

## 大きな文字

共有コンポーネントは文章を折り返し、縦に拡張します。
機能側の HStack や segmented Picker は、Accessibility サイズで VStack または標準 Menu に切り替える責務があります。
共通部品を使うだけではすべての画面がアクセシブルになるわけではありません。

## 開発用ギャラリー

`BibleDesignCatalog` は DEBUG 限定です。
Light、Dark、最大 Dynamic Type、Increase Contrast、Reduce Motion / Transparency のプレビューを用意しています。
製品に第四のタブとして追加しません。
プレビュー定義が存在することと、Xcode 上で表示を確認したことは別です。
