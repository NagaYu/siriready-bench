# 実機 Siri スポットチェック手順書（spotcheck-v1）

SiriReady Bench の F1（Not Discovered）/ F2（Wrong Target）、つまり「発話が正しい App Intent に届くか」は
AppIntentsTesting では観測できない（ハーネスは intent を直接呼ぶため、Siri の言語理解を通らない）。
この手順書は、その部分を**手順を固定した手動プロトコル**として実機 Siri で確かめるためのもの。

- 結果は `spotcheck` という出所でレポートに**独立表示**し、自動スコア（Siri Visibility Score）には**混ぜない**（Phase 2 の判断）。
- 1 回のチェックは 30 ケース。記録は JSON（下記テンプレート）で残し、`siriready bench|ingest --spotcheck <file>` でレポートに添える。

## 1. 前提

| 項目 | 固定する内容 |
|---|---|
| デバイス | 物理 iPhone 1 台（機種名を記録）。シミュレータは不可（Siri が使えないため） |
| OS | iOS 27.x（ビルド番号まで記録）。チェック期間中はアップデートしない |
| アプリ | `Apps/` の参照アプリ（MessagesOK / MessagesBroken / CalendarOK / CalendarBroken）を Debug 構成でインストール |
| 署名 | 実機インストールには開発チーム（個人チームで可。無料チームはプロビジョニングが 7 日で失効）での署名が必要。アプリとテストランナーは同じチームで署名する |
| Apple Intelligence / Siri | 有効。Siri の言語、Siri の声、「Siri に話しかける」の方式（"Siri" / "Hey Siri" / ボタン）、「Siri にタイプ入力」の有無を記録 |
| ロケール | ケースのロケールに合わせて端末の言語と Siri の言語を設定する（en-US ケースは英語（米国）、ja-JP ケースは日本語）。切り替えたら記録 |
| データ | 参照アプリは起動時に架空の seed データ（dataset v1 カタログ）を投入し、Spotlight にインデックスする。チェック前に一度アプリを前面で起動し、10 秒待つ |
| ネットワーク | 参照アプリの通信は Debug ビルド内でインターセプトされ外部に出ない。Siri 自体の通信は端末の通常設定に従う |

## 2. ケースの選び方（層別 30 件）

```bash
python3.12 dataset/select_spotcheck.py
```

`docs/spotcheck-cases.json` に 30 件が決定論的に出力される（シード固定）。層は アプリ（messages / calendar）× ロケール（en-US / ja-JP）の 4 層で、
各層からシナリオ系統（basic / noise / alias / same_name_qualified / homophone / screen / multi_turn）を 1 件ずつ、
残りを「確認が正解」のケースから補う。ケースを差し替える場合は理由を `notes` に残す。

## 3. 1 ケースの手順

1. **状態をそろえる**
   - `state.screen` があるケース: Xcode の Scheme の Arguments に `-siriready-screen <screen> -siriready-ids <id,id,…>` を設定してアプリを起動し、その画面が表示された状態にする（`visible_entities` の順に並ぶ）。
   - `state.prior_turn` があるケース: まず `prior_turn.utterance` を Siri に言い（またはタイプし）、その応答を確認してから本番の発話に進む。
   - それ以外: ホーム画面から開始する。
2. **発話する**
   - 音声: `utterance` をそのまま 1 回だけ読み上げる。言い直しはしない。
   - タイプ入力: 「Siri にタイプ入力」で `utterance` をそのまま入力する。
   - どちらで行ったかを `input_mode`（`voice` / `typed`）に必ず記録する（ASR ノイズ系ケースは voice を推奨）。
3. **観察して記録する**
   - `reached_intent`: Siri が実行（または実行確認を提示）した参照アプリの intent。アプリの画面・確認ダイアログ・アプリ内の結果表示から判断する。参照アプリ以外が反応したら `"other:<アプリ名や機能>"`、何も起きなければ `null`。
   - `resolved_entity`: 対象になった entity の ID（参照アプリの表示名から `dataset/v1.2/entities/*.json` で引く）。確認（どれにしますか？）が出た場合は `"disambiguation"`。
   - `success`: `expected` と一致したら `true`。`expected.resolution` が `disambiguate` のケースは、確認が出たときだけ `true`。
   - `notes`: Siri の応答文の要約、想定外の挙動、言い直しが必要だった事情など。
4. 次のケースの前に Siri を閉じ、参照アプリを終了する。

## 4. 記録形式

`docs/spotcheck-template.json` をコピーして埋める。

```json
{
  "protocol_version": "spotcheck-v1",
  "sample": false,
  "device": "iPhone 17 Pro",
  "os": "iOS 27.1 (24B…)",
  "locale": "ja-JP / en-US (switched per case block)",
  "siri_settings": "Siri language: …, voice: …, activation: side button, type to Siri: on",
  "recorded_on": "2026-11-…",
  "results": [
    {"case_id": "messages-en-022", "input_mode": "voice", "reached_intent": "DraftMessageIntent",
     "resolved_entity": "c_marcus", "success": true, "notes": "Siri showed the draft before saving."}
  ]
}
```

- `sample: true` は手順の説明用に架空の値で埋めた記録にだけ使う。レポートには「SAMPLE」と明示される。
- `siriready` はレポート作成時にプロトコル版、`input_mode`、ケースの重複を検査する。

## 5. 解釈上の注意

- 30 件は傾向を見るためのサンプルで、率を自動スコアと比べたり合算したりしない。
- 音声とタイプ入力を混ぜた場合は、入力方式別に読む（レポートは件数を分けて表示する）。
- OS / Siri の更新で結果は変わりうる。結果には必ず OS ビルドと記録日を添える。
- 架空 seed データの名前が実在の連絡先と衝突しないよう、チェック用端末の連絡先は空にするか、別の Apple アカウントを使う。

## 6. サンプル

`docs/spotcheck-sample.json` は、この手順書どおりに 1 回分を**架空の結果で**埋めた例（`"sample": true`）。
観測値ではない。レポートでの見え方の確認用に、`siriready bench … --spotcheck docs/spotcheck-sample.json` で表示できる。
