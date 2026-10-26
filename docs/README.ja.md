# SiriReady Bench — Phase 1 + Phase 2（詳細・日本語）

> 公開用の英語 README はリポジトリ直下の [`README.md`](../README.md)。この文書は Phase 1–2 の設計と経緯の詳細版。
> 公開リポジトリに収録しているのは dataset v1.2 と `results/phase4/` のみ。以下に出てくる旧版データセット（v0 / v1 / v1.1）と
> Phase 2–3 の生結果は、公開前に置き換えた人名を含むため開発側で保持し、公開していない。最新の結果は [`BENCHMARKS.md`](../BENCHMARKS.md)。

SiriReady Bench は、iOS アプリが iOS 27 の新 Siri に **発見され、正しく解決され、実行されるか** を
外部から検証するためのベンチです。WWDC26 以降、App Intents（App Schemas / IndexedEntity /
View Annotations）が新 Siri への統合面になりました。開発者は「schema に適合しているか」は Xcode で
確かめられますが、「実ユーザーの言い方で Siri に届くか」を知る手段はありません。このベンチはその
ギャップを測ることを目指します。

> **何が実測で、何が MOCK か。**
> - **Phase 1**（オフライン）の数値はすべて **MOCK**（決定論ルールベース解決器）。
> - **Phase 2** で、ビルド可能な参照アプリ 4 本に対し **AppIntentsTesting による実測を iOS 27.0 シミュレータで実行した**。
>   実測したのは entity クエリ、Spotlight 検索、View Annotations、intent の実行とその副作用（保存値・通信の試み）。
> - **発話が正しい intent に届くか（F1/F2）は Phase 2 でも MOCK のまま**。AppIntentsTesting は intent を直接呼ぶので、
>   Siri の音声認識・言語理解・計画は一切通らない。実機 Siri は手順書に沿った手動スポットチェック（スコア外）だけで扱う。
> - スコアの各内訳と総合には出所（`real` / `mock` / `static` / `spotcheck`）を必ず併記する。
>   スコアは OS・SDK・端末・ロケールに依存し、絶対値として比較しない。

## 範囲（Phase 1 / Phase 2）

| 層 | Phase 1（オフライン） | Phase 2（追加） | Phase 2 でも測っていないもの |
|---|---|---|---|
| 1. Static Audit | C1–C5（テキスト解析 + `siriready.yaml`） | ビルド可能な参照アプリにも同じ監査を適用（指摘 ID はソース fixture と一致） | — |
| 2. Utterance Bench | v0: 400 件 | v1: 1,200 件（v0 を内包）、generator-holdout、`mention`、params 完備 | 実ユーザー発話、音声 |
| 3. Resolution Runner | MOCK 解決 + F1–F8 | AppIntentsTesting ハーネス（UI Testing、シミュレータ）で F3–F8 の段を実測 | F1/F2（Siri の言語理解）、システムの確認 UI、実機 |
| 4. Score / Report | Siri Visibility Score（MOCK, 5 項目） | v2 スコア（Parameter Accuracy を追加、6 項目）、出所タグ、MOCK+REAL レポート、スポットチェック欄 | CI、公開 |

## Phase 1 の範囲（参考）

| 層 | Phase 1 で実装したもの | Phase 1 で **しない** こと |
|---|---|---|
| 1. Static Audit | Swift ソースのテキスト解析 + `siriready.yaml` による C1–C5 チェック | 完全な構文解析・型解決、ビルド |
| 2. Utterance Bench | 発話データセット v0（400 ケース, EN/JA, messages/calendar）、生成・検証スクリプト | 実ユーザー発話の収集、音声 |
| 3. Resolution Runner | MOCK 解決器 + F1–F8 分類（オフライン） | AppIntentsTesting 実行、実 Siri 呼び出し |
| 4. Score / Report | Siri Visibility Score（MOCK）、Markdown/JSON レポート、ok/broken 比較、demo.sh | CI 連携、実測値の公開 |

対象アプリのコードを書き換える機能はありません。監査は修正「提案」のテキストまでです。

## クイックスタート

必要なもの: macOS、Swift 6 toolchain（`swift test` には Xcode の toolchain が必要）、Python 3.12（標準ライブラリのみ）、テスト用に pytest。

```bash
scripts/demo.sh
```

```bash
scripts/test.sh
```

Phase 2 の実測（Xcode 27 と iOS 27 シミュレータが必要。署名 ID は不要）:

```bash
scripts/real_run.sh messages_ok
```

`messages_ok` の代わりに `messages_broken` / `calendar_ok` / `calendar_broken` も指定できる。1 本あたり 8〜10 分ほど
（画面参照ケースごとにアプリを再起動するため）。結果は `out/real/<variant>/mixed.md` と `mixed.json`。

個別に実行する場合:

```bash
swift build
.build/debug/siriready audit --app Fixtures/apps/messages_broken
.build/debug/siriready bench --app Fixtures/apps/messages_broken --cases dataset/v1.2/cases_dev.jsonl --out out/messages_broken
.build/debug/siriready report --compare out/messages_ok out/messages_broken
python3.12 dataset/generate.py && python3.12 dataset/validate.py
```

| コマンド | 説明 |
|---|---|
| `siriready audit --app <dir> [--json] [--out <file>]` | 静的監査。発見可能性への影響順に指摘を出す |
| `siriready bench --app <dir> --cases <jsonl> --out <dir> [--catalog <json>]` | 監査 → MOCK 解決 → 採点。`report.json` と `report.md` を出力 |
| `siriready report --in <dir> [--out <dir>]` | `report.json` から Markdown を再生成 |
| `siriready report --compare <dirA> <dirB> [--out <file>]` | 2 つの実行のスコア内訳と F 分類を並べて比較 |
| `siriready plan --app <fixture> --cases <jsonl> --bundle-id <id> --out <plan.json>` | Phase 2: MOCK 段（F1/F2、対象選択、スロット抽出）から実測ハーネス用の計画を作る |
| `siriready ingest --app <fixture> --cases <jsonl> --plan <plan.json> --raw <raw.json> --out <dir> [--spotcheck <json>]` | Phase 2: ハーネスの生結果を F 分類・v2 スコアに変換し、MOCK+REAL レポート（`mixed.md` / `mixed.json`）を出す |
| `bench ... --spotcheck <json>` | スポットチェック記録をレポートに独立欄として添える（スコアには入らない） |

カタログは既定で `<cases のディレクトリ>/entities/<app_id>.json` を使います。ケースファイルに別アプリの
ケースが混ざっている場合は、対象アプリの `app_id` に一致するケースだけを使います。

### デモ結果（MOCK, bench 0.1.0, dataset v0）

| fixture | Score (MOCK) | Discoverability | Entity Res. | Index Recall | On-screen & MT | Static Health | 失敗 |
|---|---:|---:|---:|---:|---:|---:|---|
| messages_ok | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | なし |
| messages_broken | 60.3 | 72.0 | 32.4 | 60.8 | 76.2 | 68.5 | F1=56, F4=69, F6=10 |
| calendar_ok | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 | なし |
| calendar_broken | 84.0 | 83.0 | 84.3 | 100.0 | 90.0 | 68.4 | F1=34, F5=20, F8=24 |

ok が 100 になるのは、MOCK の規則とデータセットを同じ作者が設計したためです（`dataset/BENCH_CARD.md` §6）。
Phase 1 で意味があるのは、ok と broken の差と、各破損が想定どおりの F 分類に落ちることです。

## fixture と `siriready.yaml`

`Fixtures/apps/` には架空アプリのソース fixture が 4 つあります（ビルドしません）。

| fixture | 内容 |
|---|---|
| `messages_ok` | Relay（架空のメッセージアプリ）。sendMessage/draftMessage、IndexedEntity、全画面に View Annotations |
| `messages_broken` | (a) draftMessage の相方なし → C1/F1、(b) ContactEntity が IndexedEntity でない → C2/F4、(c) MessageDetailView に annotation なし → C3/F6 |
| `calendar_ok` | Orbit Calendar（架空のカレンダーアプリ）。同名予定の disambiguation、ShareEvent は App Intent |
| `calendar_broken` | (a) disambiguation なし → F5、(b) ShareEvent が SiriKit（INIntent）のまま → C5（と F1）、(c) on_device_only の CreateEvent が外部 API を呼ぶ → C4/F8 |

`siriready.yaml` は、ソースだけでは判断できない開発者の意図を宣言します（サポートするのは YAML のサブセット）:

```yaml
app_id: messages            # dataset の app_id と一致させる
domain: messages            # MOCK の語彙表の選択に使う
indexed_entities: [ContactEntity, MessageEntity]   # Spotlight に供出するつもりの entity
annotated_views: [ContactListView]                 # View Annotations を付けるつもりの view
privacy:                     # intent ごとの想定ルーティング
  SendMessageIntent: on_device_only                # on_device_only | cloud_allowed
screens:                     # 主要画面と、そこで表示される entity 種別
  contact_list:
    view: ContactListView
    entities: [ContactEntity]
```

## 層1: Static Audit（C1–C5）

| ID | チェック | 検出するもの | 根拠 |
|---|---|---|---|
| C1 | Companion schema | アクション系 schema に対する相方の欠落（宣言的テーブル `companionRules`） | sendMessage→draftMessage は WWDC26 #240（Xcode が欠落を報告）。他は App Schema ドメインページに基づく SiriReady のヒューリスティック（レポートに明示） |
| C2 | IndexedEntity coverage | IndexedEntity でない AppEntity、yaml との不整合、`indexAppEntities` 呼び出しの欠落、供出カバー率 | WWDC26 #240 / #295、App Intents updates |
| C3 | View Annotations coverage | entity を表示する画面の view に `.appEntityIdentifier` / `.appEntityUIElements` がない、別 entity の識別子を付けている | WWDC26 #240 / #295、`appEntityUIElements(_:)` ドキュメント |
| C4 | Privacy manifest consistency | `on_device_only` 宣言の intent に外部送信の痕跡（URLSession、URLRequest、NWConnection、リモート URL リテラル）、宣言漏れ・古い宣言 | SiriReady 独自（yaml 宣言との整合） |
| C5 | SiriKit remnants | `import Intents`、INIntent、INExtension、`*IntentHandling`、`.intentdefinition`。App Intent に移行していない SiriKit intent | 本指示書の前提（下記「逸脱と根拠」参照） |

指摘は重大度（critical > high > medium > low）、次にチェックの発見可能性への影響順（C1 > C5 > C2 > C3 > C4）で並びます。
各指摘には check ID、重大度、場所、理由、修正提案、そして MOCK で現れると想定される F 分類が付きます。

### 解析の限界（テキスト解析）
- 構文木も型情報も使いません。コメントと文字列リテラルを空白でマスクしたうえで正規表現とブレース対応で宣言を拾います。
- 拾えないもの: マクロ展開後のコード、型エイリアス、プロトコル継承の連鎖（`IndexedEntity` を継承した独自プロトコル）、
  条件付きコンパイル（`#if`）、別モジュールの型、生文字列 `#"…"#` 内のブレース、文字列補間内の入れ子文字列。
- `requestDisambiguation` は intent 本体と、本体から名前で参照される型の本体（1 ホップ）だけを探します。
- 外部送信の検出はパターン一致のヒューリスティックです（SDK 経由の送信、間接呼び出しは見逃します）。
- intent の「対象 entity」は、型がアプリの entity である最初の `@Parameter` とみなします。
- `siriready.yaml` パーサは YAML のサブセット（ブロック map、スカラーの列、インライン列、引用符、コメント）のみです。

## 層2: 発話データセット v0

- `dataset/generate.py` が決定論生成（シード固定）し、`dataset/validate.py` が形式、参照整合、app-disjoint、リークを検査します。
- 400 ケース（EN 200 / JA 200、messages 200 / calendar 200）、敵対的 52%。スプリットは app-disjoint（messages = dev、calendar = eval）。
- 人名・予定名・本文はすべて架空の合成データです。詳細とバイアスは [`dataset/BENCH_CARD.md`](../dataset/BENCH_CARD.md) を参照してください。

ケース形式（1 行 1 ケース）:

```json
{"case_id": "calendar-ja-063", "split": "eval", "app_id": "calendar", "domain": "calendar", "locale": "ja-JP",
 "utterance": "チーム定例をキャンセルして", "noise": "none",
 "state": {"screen": null, "visible_entities": [], "prior_turn": null},
 "expected": {"intent": "DeleteEventIntent", "entity_id": null, "params": {},
              "resolution": "disambiguate", "candidates": ["jev_teirei_mon", "jev_teirei_thu"]},
 "adversarial": true, "difficulty": "hard", "tags": ["same_name_ambiguous"]}
```

## 層3: MOCK 解決と採点

MOCK 解決器（`mock_resolver.swift`）は、監査が抽出した宣言と合成カタログだけを使う決定論の規則です。

1. **行為の認識**: ドメイン別の語彙表（EN トークン / JA 部分文字列）から概念（例 `messages.draftMessage`）を決めます。
2. **発見**: その schema を採用した intent、または名前から導いた概念（`OpenEventIntent` → `open.event`）を持ち
   `AppShortcutsProvider` に登録された intent だけが到達可能です。なければ **F1**。
3. **対象の解決**:
   - 序数・指示語（「2番目」「this」）は画面参照として扱います。画面の view に該当 entity 型の View Annotation がなければ **F6**。
   - 照応（「その人」「it」）は前ターンの entity を引き継ぎます。EntityQuery で取り直せなければ **F7**。
   - 名前による参照: 型が IndexedEntity かつ `indexAppEntities` 済みなら、別名・typo（OSA 距離 1）・Soundex・かな読み・
     同音展開・修飾語による絞り込みを使って照合します。`EntityStringQuery` だけなら正式名の完全一致のみです。
     どちらもなければ **F4**。
   - 候補が複数あるとき、intent に disambiguation があれば確認し、なければ先頭を選びます（期待が確認なら **F5**）。
4. **ルーティング**: `on_device_only` 宣言の intent に外部送信の痕跡があれば **F8**。

| F | 名称 | 定義 |
|---|---|---|
| F1 | Not Discovered | 依頼された行為に到達できる App Intent がない |
| F2 | Wrong Target | 期待と異なる intent が選ばれた |
| F3 | Entity Misresolution | 正しい intent だが、名前の対象が別 entity に解決された（または索引済みなのに見つからない） |
| F4 | Not Indexed | 対象 entity 型が索引されず、文字列クエリもないため名前を解決できない |
| F5 | Disambiguation Failure | 曖昧なのに確認せず選んだ、または曖昧でないのに確認した |
| F6 | On-screen Reference Failure | 画面参照を解決できない（View Annotation の欠落など） |
| F7 | Context Loss | 前ターンの参照を引き継げない |
| F8 | Privacy Routing Mismatch | 解決は成功したが、`on_device_only` 宣言の intent が端末外に送信する |

分類は最初に失敗した段階で決まります（F1/F2 → F6/F7/F4 → F5/F3 → F8）。

### Siri Visibility Score（MOCK）

重みは `scoring.swift` の定数テーブルにあり、テストで固定しています。

| 内訳 | 重み | 計算 |
|---|---:|---|
| Discoverability | 25% | 期待 intent に到達したケースの割合（F1/F2 以外） |
| Entity Resolution | 25% | 到達したケースのうち、名前参照ケースで F3/F4/F5 でない割合 |
| Index Recall | 15% | **Phase 1 の代用値**: 0.5 × C2 供出カバー率 + 0.5 × 合成カタログ上の語彙・音韻検索の簡易シミュレーション再現率。実 Spotlight の測定ではない |
| On-screen & Multi-turn | 15% | 到達した画面参照・前ターン参照ケースで F3/F5/F6/F7 でない割合 |
| Static Health | 20% | 0.7 × 監査健全度（100 − 指摘ペナルティ: critical 30 / high 15 / medium 7 / low 2、下限 0）+ 0.3 × privacy ルーティング適合率 |

該当ケースがない内訳は `n/a` とし、その重みは残りに再配分します。レポートには測定条件（MOCK であること、
bench/resolver/dataset のバージョン、ケースとカタログの指紋、対象 OS/SDK 欄＝未測定、ホスト OS）を必ず記載します。
指紋や resolver バージョンが異なる実行どうしは比較しません。

## リポジトリ構成

```
Package.swift                  Swift 6, 外部依存ゼロ（Foundation のみ）
Sources/SiriReadyCore/         audit / checks / dataset / mock_resolver / scoring / report
                               + Phase 2: params / scoring_v2 / realrun / spotcheck / report_v2
Sources/siriready/main.swift   CLI（audit / bench / report / plan / ingest）
Fixtures/apps/                 架空アプリのソース fixture ×4（+ siriready.yaml）。MOCK と監査の入力
Apps/                          ビルド可能な参照アプリ ×4（Xcode 27 プロジェクト）と Harness/（UI Testing）。Apps/README.md 参照
dataset/                       generate.py, validate.py, select_spotcheck.py, v1.2/, BENCH_CARD.md
docs/                          実機スポットチェック手順書、テンプレート、SAMPLE
results/phase4/                dataset v1.2 実測の計画・生結果・MOCK+REAL レポート（scripts/reingest.sh で再生成）
Tests/SiriReadyTests/          XCTest（監査・解決・採点・レポート・実測取り込み・出所・params）
pytests/test_*.py              pytest（データセット v0/v1・リーク・holdout・アプリ生成・スポットチェック・CLI スモーク）
scripts/demo.sh, test.sh, real_run.sh, reingest.sh
```

## 環境メモ

- XCTest と Swift Testing のマクロは Command Line Tools に含まれない。`scripts/test.sh` と `scripts/real_run.sh` は
  `DEVELOPER_DIR` を `/Applications/Xcode.app/Contents/Developer` に向ける（xcode-select は変更しない）。
- Python は 3.12 / 3.13 の混在環境を前提にしている。`generate.py` / `validate.py` / `select_spotcheck.py` は Python 3.12
  （標準ライブラリのみ）で、テストからは `python3.12` があればそれで呼ぶ。pytest は `PYTEST_PYTHON`（既定 `python3`）で動かし、
  この環境では pytest が 3.13 にしか入っていない。スクリプトは何も pip install しない。
- このチェックアウトのフォルダ名は末尾に空白がある。pytest 9 は親ディレクトリから起動すると収集に失敗するため、
  `scripts/test.sh` は `Tests/` の中から pytest を起動して吸収している（フォルダは改名しない）。
- 実測のスモークテスト（シミュレータで seed intent を発見して 1 ケース実行）は時間がかかるため opt-in:
  `SIRIREADY_REAL=1 scripts/test.sh`。

## 指示書からの逸脱と根拠

1. **ロジックはライブラリ `SiriReadyCore` に置いた**（指示書の目安は `Sources/siriready/` 直下）。テストから `@testable import`
   するためで、CLI は `Sources/siriready/main.swift` のままです。補助ファイル（`yaml.swift`、`source_scanner.swift`、
   `text_matching.swift`、`bench.swift`）を追加しました。
2. **schema 識別子は Apple の App Schema ドメインページに合わせた**: messages は `sendMessage` / `draftMessage` /
   `setMessageReadStatus`、entity は `message` / `messagePerson` / `conversation`。calendar は `createEvent` /
   `updateEvent` / `deleteEvent`、entity は `event` / `calendar`。calendar ドメインに open / share の schema はないため、
   `OpenEventIntent` と `ShareEventIntent` は schema なしの App Intent + App Shortcuts としました。
   根拠: [Messages](https://developer.apple.com/documentation/appintents/app-schema-domain-messages)、
   [Calendar](https://developer.apple.com/documentation/appintents/app-schema-domain-calendar)。
3. **C1 で Apple の資料に根拠があるのは sendMessage→draftMessage だけ**です（[WWDC26 #240](https://developer.apple.com/videos/play/wwdc2026/240/)）。
   それ以外の組み合わせは SiriReady のヒューリスティックとしてテーブルで区別し、指摘文にも明記します。
4. **SiriKit の「非推奨化」**: 確認した Apple のページ（WWDC26 #240 の説明、App Schema ドメインページ）には
   SiriKit 非推奨の明記を見つけられませんでした。C5 は本指示書の前提に従って実装しましたが、指摘文は
   「SiriKit is legacy; the new Siri integrates through App Intents」と、断定を避けた表現にしています。
5. **View Annotations の API**: `.appEntityIdentifier(EntityIdentifier(for:identifier:))`（[#240](https://developer.apple.com/videos/play/wwdc2026/240/)）と
   [`appEntityUIElements(_:)`](https://developer.apple.com/documentation/swiftui/view/appentityuielements(_:)) の両方を annotation として認めます。
6. **ケース形式の拡張**: `expected.resolution`（`execute` / `disambiguate`）、`expected.candidates`、`tags` を追加しました。
   「確認が正解」のケースを指示書の `expected{intent, entity_id, params}` だけでは表せないためです。
7. **pytest の置き場所は `pytests/`**（指示書は `tests/`）。macOS の既定ファイルシステムは大文字小文字を区別しないため、
   `tests/` と `Tests/`（SwiftPM のテストディレクトリ）は同じディレクトリになります。Phase 2 までは `Tests/test_*.py` に
   置いていましたが、Phase 3 で大文字小文字に依存しない別名の `pytests/` に移しました（内容は変更なし）。
8. **テストフレームワーク**: XCTest を使いました。Command Line Tools には XCTest も Swift Testing のマクロもないため、
   `swift test` は Xcode の toolchain で実行します（`scripts/test.sh` が `DEVELOPER_DIR` を設定します）。

Phase 2 で公式（SDK とツールチェーン）を優先した点:

9. **App Schema の必須プロパティ・パラメータ・型は iOS 27.1 SDK の AppIntents メタデータ処理系に従った**。
   参照アプリの intent はスキーマの名前（`destination`、`content`、`event`、`entity`、`span`…）と union 型
   （`@UnionValue enum MessageDestination` など）を使う。Phase 1 のソース fixture の名前（`recipients`、`target`）とは異なるが、
   宣言内容（どの schema を採用し、どこを壊したか）は同じ。対応は [`Apps/README.md`](../Apps/README.md)。
10. **messages_broken (b) は純粋な形ではビルドできない**: 「索引されず、文字列クエリも無い連絡先」は Xcode 27.1 が
    halting error（`AppSchemaIntent 'SendMessageIntent' requires UnionValue case 'ContactEntity' to conform to 'IndexedEntity', … provide a default 'EntityStringQuery', or provide an 'IntentValueQuery'`）
    で止める。ビルド可能な broken は IndexedEntity ではないまま、名前だけの `EntityStringQuery` を持つ（ソース fixture は Phase 1 のまま）。
11. **C1 の根拠が強まった**: `draftMessage` を欠いた `sendMessage` に対し、Xcode 27.1 が
    `warning: App Intents use case 'Message Sending' is missing the schema 'messages.draftMessage'` を出すことを実ビルドで確認した。
12. **AppIntentsTesting の API は SDK の swiftinterface に合わせた**: `IntentDefinitions(bundleIdentifier:)`、`intents[...]`、
    `entities[...]`、`makeIntent(...)`（動的呼び出し）、`run()`、`entities(matching:)`、`entities(identifiers:)`、
    `spotlightQuery(_:)`、`viewAnnotations()`（[WWDC26 #295](https://developer.apple.com/videos/play/wwdc2026/295/)）。
    セッションでは明言されていなかったシミュレータでの動作は、Step 0 で実地に確認した。
13. **スコアの出所タグに `static` を加えた**（指示書は real / mock / spotcheck）。C1–C5 の監査はアプリを動かした測定でも
    MOCK の模擬でもないため、混ぜずに区別した。
14. **Phase 1 の SiriReadyCore への変更は追加のみ**: `BenchCase` に任意項目 `mention` / `generator`、`BenchResult` に任意項目
    `scoreV2` / `params` / `spotcheck`、Phase 1 レポートの得点表に Source 列と v2 節を追加。F1–F8 の定義、v1 の重み、
    MOCK 解決器の規則は変えていない。既存テスト 31 件（swift）と 16 件（pytest）は期待値を変えずにすべて通る。

## Phase 2: 実基盤接続（到達範囲）

**到達点: iOS 27.0 シミュレータで実測が回った。** 4 本の参照アプリそれぞれ 600 ケース（MOCK が F1/F2 で止めたものを除く）を
AppIntentsTesting で実行し、各アプリの全 entity 表記に対する Spotlight プローブも実行した。実機（物理 iPhone）では
実行していない（このマシンに署名 ID がないため）。実機 Siri は手順書による手動スポットチェック（スコア外）だけで扱う。

### 各段で何を実測し、何が MOCK のままか

| 段 | 実測（`real`）の方法 | 判定 | MOCK のまま残るもの |
|---|---|---|---|
| 発話 → intent（F1/F2） | — | MOCK の語彙表 | すべて（AppIntentsTesting は Siri を通らない）。ただし intent がバイナリに無いことは実測で検出（metadata error 401 → F1） |
| 名前 → entity（F3/F4） | `entities(matching: mention)` と `spotlightQuery(mention)` | 期待 entity が返らなければ F3。その型に Spotlight のヒットが 1 件も無い場合は F4 | 修飾語（「木曜の」「from work」）で候補を絞る段は MOCK |
| 確認（F5） | `run()` が `AppIntentsServicesExecutionErrorDomain` 206「requested disambiguation」で止まるか。実行された副作用の対象が同名の別 entity か | 確認が正解なのに実行 → F5。名指しなのに確認 → F5。同名の別 entity に実行 → F5 | システム側の確認 UI（画面参照の曖昧ケースは、全候補に annotation があれば合格扱い） |
| 画面参照（F6） | 起動引数で画面状態を作り `viewAnnotations()` | 表示中 entity に annotation が無ければ F6 | 序数・指示語の解釈は MOCK |
| 前ターン（F7） | `entities(identifiers:)` で前ターンの entity を取り直す | 取れなければ F7 | 照応語の検出は MOCK |
| 実行と副作用 | `makeIntent(...).run()`、アプリが保存した値（DEBUG 専用の `DebugProbeIntent` で回収） | 実行エラーは別欄に報告 | — |
| プライバシー（F8） | アプリ内の URLProtocol が全 HTTP(S) をローカルで受けて宛先を記録（外部には出ない） | `on_device_only` 宣言の intent が通信を試みたら F8 | — |
| params | MOCK のスロット抽出値を渡し、アプリが保存した値を `expected.params` と照合 | 抽出（mock）と保存（real）の両方が正しいときだけ正解 | スロット抽出 |
| Index Recall | 全 entity の全表記・読みで `spotlightQuery` し、本人が返るか | 0.5 × C2 カバー率（static）+ 0.5 × プローブ再現率（real） | — |

### v2 スコア（Phase 2）

Phase 1 の 5 項目スコア（重み 25/25/15/15/20）はそのまま残し、別プロファイル v2 として Parameter Accuracy を加えた
6 項目スコアを出す（重みは `scoring_v2.swift` の定数でテスト固定）。

| 内訳 | 重み | MOCK 実行での出所 | MOCK + REAL での出所 |
|---|---:|---|---|
| Discoverability | 20% | mock | mock |
| Entity Resolution | 20% | mock | real |
| Parameter Accuracy | 10% | mock | mock 50% · real 50% |
| Index Recall | 15% | static 50% · mock 50% | static 50% · real 50% |
| On-screen & Multi-turn | 15% | mock | real |
| Static Health | 20% | static 70% · mock 30% | static 70% · real 30% |

総合スコアには内訳の重みで合成した出所構成（例: `real 54% · mock 25% · static 21%`）を必ず併記する。

### Phase 2 の結果（dataset v1 1,200 件、iOS 27.0 シミュレータ、2026-10-26）

内訳の列は v2 の順（Discoverability / Entity Resolution / Parameter Accuracy / Index Recall / On-screen & MT / Static Health）。
MOCK 行はソース fixture に対する MOCK のみ（出所 `mock 78% · static 21%`）、MOCK+REAL 行は参照アプリでの実測を含む
（出所 `real 54% · mock 25% · static 21%`）。Phase 2 の生データは開発側で保持（非公開）。公開版の生データ・計画・レポートは [`results/phase4/`](../results/phase4/)。

| アプリ | 実行 | v1 (MOCK) | **v2** | Disc. | Entity | Params | Index | On-screen & MT | Static | F 分類 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| messages_ok | MOCK | 99.3 | **99.4** | 99.5 | 97.7 | 100.0 | 100.0 | 100.0 | 100.0 | F2=3, F3=10 |
| messages_ok | MOCK+REAL | — | **95.1** | 99.5 | 77.6 | 100.0 | 98.0 | 100.0 | 100.0 | F2=3, F3=43, F5=56 |
| messages_broken | MOCK | 60.1 | **65.0** | 71.5 | 32.0 | 100.0 | 60.8 | 76.2 | 68.5 | F1=168, F2=3, F3=2, F4=204, F6=30 |
| messages_broken | MOCK+REAL | — | **68.4** | 71.5 | 50.5 | 100.0 | 58.9 | 76.2 | 68.5 | F1=168, F2=3, F3=9, F4=112, F5=29, F6=30 |
| calendar_ok | MOCK | 99.1 | **99.3** | 100.0 | 96.5 | 100.0 | 100.0 | 100.0 | 100.0 | F3=13 |
| calendar_ok | MOCK+REAL | — | **94.1** | 100.0 | 73.4 | 99.6 | 96.2 | 100.0 | 100.0 | F3=45, F5=54 |
| calendar_broken | MOCK | 83.1 | **84.9** | 82.8 | 81.0 | 100.0 | 100.0 | 90.0 | 68.4 | F1=103, F3=10, F5=60, F8=72 |
| calendar_broken | MOCK+REAL | — | **83.6** | 82.8 | 65.6 | 99.5 | 96.2 | 100.0 | 72.7 | F1=103, F3=42, F5=63 |

実行エラー（確認要求以外で `run()` が失敗）は 4 本とも 0 件。F1/F2 は MOCK のまま（MOCK+REAL 行でも同じ値）。

#### 実測で初めて分かったこと（MOCK との食い違い）

1. **ok 版の確認ロジックが「聞きすぎ」る**（ok で F5 = 56 / 54 件）。「木曜の Team Sync を…」「Sam Lee from work」のように
   利用者が修飾語で 1 件に絞っても、Phase 1 の ok 設計（同名・同読みがあれば `perform()` 内で必ず
   `requestDisambiguation`）は確認を求める。MOCK は修飾語での絞り込みを Siri 側でモデル化していたため見落としていた。
2. **Spotlight は typo や音の近い綴りを拾わない**（ok で F3 が 10→43 / 13→45）。"Ktaherine Osei"、"Sean Patel"
   （正: Shawn）、"Design Revue"、"Qaurterly Business Review" などに `spotlightQuery` も `entities(matching:)` も何も返さない。
   MOCK は「索引済みならあいまい照合できる」と仮定しており、楽観的すぎた。
3. **messages_broken の F4 は 204→112 件**。ツールチェーンが強制した名前だけの `EntityStringQuery` が、正式名や
   部分一致（"Alex" → "Alex Rivera"）の依頼を救う。その結果、broken の v2 は MOCK より上がった（65.0 → 68.4）。
   索引に入っていないこと自体は実測でも確認できる（Contact のプローブ 0 件ヒット、Index 58.9）。
4. **calendar_broken の F8 は MOCK 72 件 → 実測 0 件**。外部ジオコーダ呼び出しは「場所パラメータがあるとき」だけ実行され、
   v1 の作成依頼に場所を含むものは無い。静的監査（C4）は正しく不整合を指摘しているが、データセットの入力では
   データは端末外に出なかった。実測が静的解析の過大評価を示した例。
5. **calendar_broken は同名の別予定に黙って実行する**（F5 のうち 15 件以上）。「Friday's Vendor Sync」を指定しても、
   最初に見つかった Tuesday 側を更新した。MOCK は修飾語が効くので合格としていた。
6. **Spotlight プローブで見えた索引の穴**: 所有格を含む題名（"Jon's Birthday Dinner"、"Bryce's Farewell Party" など）と
   「全社ミーティング」が自身の表記で返らない。ConversationEntity の読み（`keywords` を持たない）と
   CalendarEntity の別名（`alternateNames` を持たない）は索引に入っていない。いずれも参照アプリの設計の穴として実測で初めて見えた。
7. **別名レベルの同音（瑞希／美月）は Spotlight が 1 件しか返さず、アプリの確認ロジック（正式名・正式読みで比較）も
   反応しない**ため、確認が正解のケースが黙って実行される（F5）。
8. 画面上の曖昧参照（「これを削除して」で 3 件表示）は、アプリ側では確認を観測できない。全候補に View Annotation が
   あれば合格とした（システムが候補を提示できる前提）。このため calendar_broken の MOCK F5 のうち 12 件は実測では合格になる。
   測定の限界であり、改善ではない。
9. 1 件（calendar-ja-213「移行作業を水曜の10時半に移動して」）は、対象予定がもともと水曜で、修飾語と移動先の曜日が
   同じ語になるため、MOCK のスロット処理が移動先の日付を誤る（Parameter Accuracy の 1 件の不一致）。

## Phase 3 に向けて

- **公開ベンチの対象アプリを増やす**: 参照アプリは「宣言の差分を 1 つずつ入れた対照実験」としては有効だが、
  実アプリの多様性はない。次の段階では (1) 他のスキーマドメイン（Mail、Notes、Reminders など）の参照アプリを同じ手法で
  増やし、(2) 第三者アプリは開発者がビルド済みアプリと `siriready.yaml` を提出してハーネスを回す方式にする
  （bundle ID だけで動くので、アプリのソースは要らない）。どちらも seed データは合成に限り、実在の個人データは扱わない。
- **CI 上で実測を回せるか**: 実測はシミュレータと署名なしで回るので、macOS ランナー（Xcode 27 と iOS 27 ランタイム付き）
  なら CI に載る。1 本あたり 8〜10 分で、大半は画面参照ケースごとのアプリ再起動。画面状態の切り替えを再起動なしの
  debug intent にすれば短縮できる。Spotlight の索引待ちは起動時の待機で吸収しているが、CI の遅いランナーでは
  タイムアウトの調整が要る。
- **OS / SDK の追跡**: 実測値は iOS 27.0 シミュレータ・Xcode 27.1 のもの。公開ベンチでは OS ビルド・Xcode ビルド・
  ランタイムを結果に必ず含め、ランタイムを固定した行列（例: 27.0 / 27.1）で回す。
- **F1/F2 の扱い**: AppIntentsTesting では原理的に測れない。手動スポットチェックの規模を上げるか、Apple が将来
  発話レベルのテスト API を提供するかに依存する。公開時もスポットチェックはスコアに合算しない。
- **ベンチ自体の健全性**: 実測で MOCK の楽観（あいまい照合、修飾語）と悲観（broken の F4）が両方見つかった。MOCK の規則は
  実測に合わせて改めるのではなく、`resolver` の版を上げ、旧版との差を公開する。
- **公開（GitHub / Hugging Face）**: データセットとカタログは自作の合成データなので公開可能。公開前に BENCH_CARD の
  ライセンス表、架空名と実在人物の偶然の一致の確認、generator-holdout の eval 側の非公開化（汚染防止）を判断する。

## ライセンス・データ
fixture、データセット、カタログはすべて本リポジトリ用に作った架空・合成データです。実在アプリのソースや実在人物の
データは含みません。
