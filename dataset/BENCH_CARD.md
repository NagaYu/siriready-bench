# BENCH CARD — SiriReady Bench 発話データセット（公開版: v1.2）

> **公開版について。** このリポジトリに収録しているデータセットは **v1.2** のみ（`dataset/v1.2/`）。
> 旧版のデータセット（v0 / v1 / v1.1）と Phase 2–3 の生結果は、公開前に置き換えた人名を含むため公開せず、
> 開発側で保持している。v1.2 は v1.1 からの改名のみの差分で、スコアは完全一致する。
> 以下の v0 / v1 / v1.1 の記述は v1.2 に至る経緯の説明であり、該当するファイルは本リポジトリに含まれない。
>
> 登場する人名・組織名はすべて架空の合成データであり、実在の人物・団体とは関係ありません。


> v0（400 件）は Phase 1 の凍結版、v1（1,200 件 = v0 + 800）は Phase 2 の拡張版。
> どちらも MOCK 採点と、Phase 2 では参照アプリに対する AppIntentsTesting 実測（シミュレータ）の入力になる。
> いずれも実 Siri の言語理解の測定ではない（F1/F2 は MOCK のまま）。

## 0b. v1.2 の差分（改名のみ。v1 / v1.1 は凍結）

v1.2 = v1.1 から、架空の 6 名を改名しただけのもの（`dataset/v1.2/`）。公開前の名前点検（`docs/name-review.md`）で、
架空名が実在の著名人と一致したためである。**ケース構成・件数・case_id・分割（app-disjoint）・生成系統（holdout）・
期待結果の構造は v1.1 と同一**で、`validate.py --dataset v1.2` が「宣言した改名を v1.1 に当てると v1.2 と完全一致する」ことと、
v1.2 に旧名が残っていないことを検査する。

- 改名は生成器レベル（entity 定義とプール定義）で行い、v0 / v1 / v1.1 と同じ乱数系列・同じパイプラインで再生成した。
  旧名との対応表は開発側で保持し、公開しない。
- 改名の設計方針: 言語・性別・役割（同名ペア、同音ペア、表記ゆれ、ASR 変種）を保つ。entity ID も新しい名前に合わせて変更
  （会話 ID も同様）。
- 変化したケースは dev（messages）の 38 件のみ。eval（calendar）は v1.1 とバイト単位で同じ内容。
- typo ノイズは「名前の最も長いトークンの文字を入れ替える」生成規則のため、改名後の名前では入れ替わる位置が変わる
  （例: 姓が長くなったケース）。ノイズの種類と意味は不変。
- 参照アプリの seed は v1.2 カタログから再生成（`Apps/tools/make_seed.py`、既定 v1.2。`--dataset v1.1` で旧 seed を再現できる）。
- 実測: 改名した人物が関係するケース（messages 系 2 アプリ × 40 件）と、関係する Spotlight プローブだけを再実測し、
  それ以外は Phase 3 の観測を引き継いで `results/phase4/` を作った（`MERGE.json` に内訳）。results/phase2・phase3 は不変。
- 公開用 Hugging Face パッケージ（`hf/`）は v1.2 の dev スプリット（624 件）。

## 0a. v1.1 の差分（Phase 3。v1 は凍結）

v1.1 = v1（1,200 件、バイト一致のまま）+ 72 件。追加は Phase 2 の実測で見つかった「データ側の穴」に限る。
置き場所は `dataset/v1.1/`（`validate.py --dataset v1.1` が v1 部分の不変も検査する）。

| 追加 | 件数 | 対象スプリット | なぜ（Phase 2 の実測で見つかった穴） |
|---|---:|---|---|
| `gap_location`: 場所つきの予定作成（"… at Harbor Clinic" / 「…、場所はみなと歯科」） | 24（EN 12 / JA 12） | eval（calendar） | calendar_broken の外部ジオコーダは場所があるときだけ動く。v1 に場所つきケースが無く、F8 が実測 0 件で判定できなかった |
| `gap_calendar_alias`: カレンダー名つきの作成（Work / Personal、仕事 / プライベート） | 12 | eval | カレンダーの別名が索引に入っていなかった（Spotlight プローブ） |
| `gap_title_index`: 所有格の題名（"Maya's Graduation Party" など新規 3 件）と、長音・中黒を含むカタカナ題名（全社ミーティング、新規「オールハンズ・ミーティング」） | 12 | eval | 所有格の題名と「全社ミーティング」が自身の表記で Spotlight から返らなかった |
| `gap_conversation_index`: 会話を読み（JA、例「たかせみづきとのトークを開いて」）・愛称・所有格（EN）で開く | 24（EN 12 / JA 12） | dev（messages） | 会話 entity の読みが索引に入っていなかった |

- 規模: 1,272 件（EN 636 / JA 636、messages 624 / calendar 648）、敵対的 672 件（53%）。
- 生成系統: 追加分は `v1.1-gap-A`・`B`（dev のみ）/ `v1.1-gap-C`・`D`（eval のみ）。言い回しは v1 の同じ系統の A–D ラッパーを使い、generator-holdout を維持する。
- 新しい entity: 予定 4 件（上記の題名）。カタログは `dataset/v1.1/entities/`。参照アプリの seed も v1.1 カタログから生成する（v1 のケースが参照する entity は不変）。
- params: 作成ケースに `location` と `calendar`（カレンダー entity の ID）が加わる。MOCK のスロット抽出はこの 2 つを読む規則を追加したが、v1 のケースでの抽出結果・判定・スコアは変わらないことを確認済み。
- 公開: Hugging Face 用パッケージ（`hf/`）は **v1.1 の dev スプリットのみ**。eval（calendar、系統 C/D）は汚染防止のため公開しない。

## 0. v1 の要点（Phase 2）

| 項目 | 内容 |
|---|---|
| 規模 | 1,200 件（EN 600 / JA 600、messages 600 / calendar 600）。v0 の 400 件は case_id と期待結果を変えずにそのまま含む |
| 置き場所 | `dataset/v1/cases_dev.jsonl`（messages, 600）、`dataset/v1/cases_eval.jsonl`（calendar, 600）、`dataset/v1/entities/` |
| 追加分 | (ドメイン, ロケール) ごとに 100 件 × 2 ブロック。新しい架空 entity プール（連絡先 48 人、予定 48 件ほか）を同じシナリオ構成で使う |
| 生成系統（generator-holdout） | 全ケースに `generator` を付与: `v0-template` / `v1-para-A`・`B`（dev のみ）/ `v1-para-C`・`D`（eval のみ）。A = 依頼形（"Could you please …" / 「〜してもらえる？」）、B = 呼びかけ（"Hey, …" / 「ねえ、…」）、C = 要望形（"I need you to …" / 「〜しておいてほしい」）、D = 文末の添え（", thanks" / 「、お願い」）。eval 側の言い回し系統は dev に一度も現れない |
| holdout 検査 | `validate.py --dataset v1` が、系統ラベルとスプリットの不一致、他スプリットの系統の言い回しマーカー、言い換えスケルトン（entity・本文・時刻を伏せた発話）のスプリット間重複を検出し、非ゼロ終了する |
| `mention` | 名前で対象を指すケースに、対象を指す表層文字列を付与（816 件）。実測ハーネスはこれで `entities(matching:)` / `spotlightQuery` を引く |
| params | 全ケースが intent ごとの必須パラメータを持つ（`validate.py` が検査）。790 件が非空（本文、時刻、曜日、タイトル、招待者、既読） |
| params 採点の開始 | Phase 2 から params を採点に含める: MOCK 版は「MOCK のスロット抽出が expected.params と一致」、実測版はさらに「アプリが実際にその値を保存した（観測された副作用）」。v2 スコアの Parameter Accuracy（10%）。Phase 1 の 5 項目スコアは変更なし |

v1 の内訳: 敵対的 624 / 1,200（52%）、easy 336 / medium 612 / hard 252、確認が正解 135 件、
ノイズ各 60 件（typo / asr_homophone / code_switch / word_order）。カテゴリ: basic 336、noise 240、alias 96、
same_name_qualified 72、same_name_ambiguous 72、homophone 72、screen 144、screen_ambiguous 24、multi_turn 144。

## 1. 何を測るか（以下 §1–§5 は v0 を基準に記述。v1 も同じ構成）
- アプリの **ソース上の宣言**（App Schema 採用、App Shortcuts 登録、IndexedEntity と `indexAppEntities`、
  `EntityStringQuery`、View Annotations、`requestDisambiguation`、privacy ルーティング宣言）が欠けたとき、
  実ユーザーらしい言い方の依頼がどの段階（F1–F8）で失敗しうるか。
- 同じケース集合を「正しく実装した fixture」と「壊した fixture」に流したときの **差分**。

## 2. 何を測らないか
- 音声認識・自然言語理解・Siri の計画能力そのもの（音声は扱わず、ASR の誤りはテキストとして注入）
- 実 Spotlight セマンティックインデックスの再現率・ランキング（Index Recall は Phase 1 の代用値）
- アプリの実行時挙動（intent は一度も実行しない）、パラメータ抽出の正確さ
  （`expected.params` は記録のみで Phase 1 の採点対象外。Phase 2 の AppIntentsTesting で検証する）
- OS バージョン間の差。スコアは OS 非依存の絶対値ではない

## 3. 構成（400 ケース）

| 軸 | 内訳 |
|---|---|
| ドメイン × ロケール | messages en-US 100 / messages ja-JP 100 / calendar en-US 100 / calendar ja-JP 100 |
| スプリット（app-disjoint） | dev = messages アプリ 200 / eval = calendar アプリ 200（同一アプリは片方のみ） |
| 敵対的ケース | 208 / 400（52%） |
| 難易度 | easy 112 / medium 204 / hard 84 |
| ノイズ | none 320 / typo 20 / asr_homophone 20 / code_switch 20 / word_order 20 |
| 期待解決 | execute 355 / disambiguate（確認が正解）45 |

カテゴリ（`tags`）:

| tag | 件数 | 敵対的 | 内容 |
|---|---:|:---:|---|
| basic | 112 | | 正式名での基本依頼 |
| noise | 80 | | typo / ASR 同音 / コードスイッチ / 語順入れ替え |
| alias | 32 | ✓ | 略称・愛称・表記ゆれ（Kate→Katherine、QBR、齊藤/斉藤/斎藤、打ち合わせ/打合せ） |
| same_name_qualified | 24 | ✓ | 同名 entity 競合 + 区別できる修飾（「木曜のチーム定例」「Sam Lee from work」） |
| same_name_ambiguous | 24 | ✓ | 同名 entity 競合で確認が正解 |
| homophone | 24 | ✓ | 同音異義（JA: 美月/瑞希、講演/公演、加藤涼/加藤遼。EN: Jon Park / John Parke（v1.2 の名前）） |
| screen | 48 | ✓ | 画面参照（「これ」「2番目」「the second one」「reply to this」） |
| screen_ambiguous | 8 | ✓ | 複数表示中の「これ」— 確認が正解 |
| multi_turn | 48 | ✓ | 前ターンの entity の引き継ぎ（「その人に」「Move it to 4pm」） |

ケース形式は `generate.py` 冒頭と `docs/README.ja.md` の「データセット形式」を参照。指示書の形式に加えて
`expected.resolution` / `expected.candidates`（確認が正解のケース表現）と `tags`（カテゴリ）を持つ。

## 4. 生成方法
- `generate.py` がテンプレート + 語彙テーブルから決定論生成（`random.Random(27)`）。再実行でバイト一致
  （pytest で検査）。
- entity カタログ（`entities/*.json`）も同スクリプトが生成し、全件 `synthetic: true`。
- ASR 同音ノイズの綴り（Sean/Shawn、輝/光、店卸/棚卸 など）は生成側テーブルにのみあり、カタログには
  入れていない（インデックスが綴りを直接持つことによるリークを避けるため）。

## 5. 検証（`validate.py`）
形式、enum、`expected` / `state` の参照整合（存在しない entity・intent を指していないか）、
カタログの `synthetic` 宣言と related 参照、スプリットの app-disjoint、
同一 utterance（NFKC・大小文字・空白正規化）+ 同一 state の重複（スプリット間はリーク、スプリット内は重複）、
v0 プロファイル（400 件、ロケール・ドメイン均衡、敵対的 30% 以上、必須カテゴリ）。失敗時は非ゼロ終了。

## 6. 既知のバイアスと限界
- **作者バイアス / 設計の循環**: ケース、カタログ、MOCK 解決器の語彙・規則を同じ作者が同時に設計した。
  そのため *_ok fixture が 100 点になるのは「内部整合している」ことしか意味しない。Phase 1 の情報は
  ok と broken の **差** と、失敗が期待した F 分類に落ちることにある。
- **テンプレート由来の単調さ**: 言い回しは少数のテンプレートに限られ、実ユーザー発話の多様性は小さい。
- **語彙の小ささ**: 架空人名・予定名は各ロケール十数件。EN 名は Soundex 衝突を避けて選んだ（Jon Park / John Parke などの同音ペアを除き意図的に衝突させていない）。
- **日本語の読み**: MOCK の漢字→かな変換はデータセット語彙を覆う玩具辞書。実 ASR の誤りの分布は再現しない。
- **ロケール**: en-US と ja-JP のみ。敬語・方言・長文・複数依頼の連結は未収録。
- **画面状態**: `visible_entities` は表示順の ID 列で、レイアウトや部分的な可視性は表現しない。
- **ノイズ件数**: 各ノイズ種 20 件（v1 で 60 件）と少なく、ノイズ別スライスの率は粗い。
- **JA の読み辞書は語彙範囲内のみ**: MOCK の漢字→かな表は v0 の語彙に合わせて作ったまま Phase 2 で更新していない（SiriReadyCore を変えない方針）。v1 の新しい JA 名の ASR 変種（坂元陸、村神悠真、再用面接 など）は MOCK では読めず F3 になる。これは MOCK の限界で、アプリの不備ではない。
- **言い換え系統はラッパー型**: v1 の A–D は発話の前後に定型句を付ける変換で、語彙そのものの言い換え（"ping" や「連絡して」など）は含まない。holdout は「未知の丁寧さ・文型への頑健性」を見るもので、未知の動詞への汎化は測らない。
- **ASR 変種の一部は語の分割・結合を含む**（"Road Map Review"、"Partner Work Shop"）。MOCK はトークン数が変わると照合できないため、意図的に MOCK の弱点として残している。
- **名前と動作語の衝突**: 架空連絡先 "Mark Ellison" は MOCK の "mark (as read)" 語彙と衝突し MOCK では F2 になる。実在しうる衝突として残している。
- **params の採点範囲**: 本文・タイトルは正規化（NFKC・小文字・前後空白と文末記号）後の完全一致。時刻・曜日は 2026-11-01（日）を基準日とした決定論的な日時に変換して比較する（実測版）。言い換えや部分一致は不正解として扱う。

## 7. ライセンスと出所

| 要素 | 出所 | ライセンス |
|---|---|---|
| ケース（`cases_*.jsonl`） | 本リポジトリの `generate.py` が生成した自作合成データ | リポジトリと同じ（自作） |
| 人名・予定名・メッセージ本文・カタログ | 本ベンチ用に作った架空データ。実在人物・実在アプリのデータは含まない | 同上（自作） |
| テンプレート・語彙テーブル | 自作 | 同上（自作） |
| App Schema 名（`messages.sendMessage` 等） | Apple の公開ドキュメントに記載の識別子を参照のみ | 識別子の参照であり、文書の転載はしない |

## 8. バージョニング
- dataset `v0`（凍結）と `v1`。`generate.py` は両方を出力し、v0 はバイト一致のまま（pytest で検査）。ケースまたはカタログを変えたら再実行して生成物をコミットする。
- 参照アプリの seed（`Apps/*/Shared/SeedData.swift`）は v1 カタログから `Apps/tools/make_seed.py` で生成する。
- レポートはケースファイルとカタログの FNV-1a 指紋を記録する。指紋が異なるスコア同士は比較しない。
