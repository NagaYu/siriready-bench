---
pretty_name: SiriReady Bench utterances (dev, v1.2)
language:
  - en
  - ja
license: other
license_name: siriready-bench-terms
license_link: LICENSE
task_categories:
  - text-classification
tags:
  - app-intents
  - siri
  - ios
  - entity-resolution
  - synthetic
size_categories:
  - n<1K
configs:
  - config_name: default
    data_files:
      - split: dev
        path: data/dev.parquet
---

# SiriReady Bench utterances — dev split (v1.2)

Synthetic English and Japanese requests to a fictional iOS messages app ("Relay"), each annotated with the
App Intent it should reach, the entity it should act on (or the candidates the system should ask about),
the parameters it carries, and the app state it was spoken in. The dataset is the utterance layer of
**SiriReady Bench**, which checks whether an iOS app's App Intents surface (App Schemas, `IndexedEntity`,
View Annotations) lets requests reach the right intent and entity.

> **Only the dev split is published.** The eval split (a different app — calendar — and different paraphrase
> families) is withheld so it stays an uncontaminated held-out set. Do not train on this data if you intend
> to report results on SiriReady Bench.

## Contents

| File | Rows | Description |
|---|---:|---|
| `data/dev.jsonl` | 624 | One case per line, exactly as in the benchmark repository (`dataset/v1.2/cases_dev.jsonl`) |
| `data/dev.parquet` | 624 | Same cases, flattened: nested `state` and `expected.params` are JSON strings |
| `data/entities_messages.json` | 178 entities | Synthetic catalog the cases refer to (contacts, conversations, messages) |
| `MANIFEST.json` | — | Row counts and SHA-256 checksums of every file |

624 cases: en-US 312 / ja-JP 312; 336 adversarial. Scenario families: canonical names, typo / ASR-homophone /
code-switch / word-order noise, nicknames and orthographic variants (表記ゆれ), same-name contacts with and
without a qualifier (asking is correct without one), sound-alike names (Jon Park / John Parke, 美月 / 瑞希), on-screen
references ("the second one", 「これ」), previous-turn references ("them", 「その人」), and cases for
conversations named by kana reading, nickname or possessive.

Case fields: `case_id`, `split`, `app_id`, `domain`, `locale`, `utterance`, `noise`,
`state{screen, visible_entities, prior_turn}`, `expected{intent, entity_id, params, resolution, candidates}`,
`adversarial`, `difficulty`, `tags`, `mention` (surface string naming the target), `generator` (lineage).

## What it measures — and what it does not

- **Measures** whether an app's declarations let a request be routed to the right intent, resolve the right
  entity (by name, on screen, or from the previous turn), ask when asking is correct, and carry the right
  parameters. In SiriReady Bench this is scored by a rule-based MOCK resolver and, for reference apps, by
  AppIntentsTesting runs on an iOS simulator.
- **Does not measure** Siri itself: speech recognition, language understanding and planning are not exercised
  by these labels. ASR errors are injected as text. There is no audio.
- Labels describe the intended behaviour of the benchmark's fictional app, not of any real product.

## How it was generated

Deterministically by `dataset/generate.py` (fixed seed, standard library only): templates and vocabulary tables
over an invented entity catalog. v1.1 = v1 (1,200 cases) + 72 cases targeting gaps found by real simulator runs.
**v1.2 = v1.1 with six fictional people renamed** because their invented names coincided with well-known public
figures; case structure, splits and lineage are unchanged, and v1.2 differs from v1.1 only by those renames
(checked in the development repository; earlier versions are not published). Regeneration is byte-identical and
checked in CI.

## Split design

- **App-disjoint:** dev = messages app, eval = calendar app. No app appears in both splits.
- **Generator holdout:** every case records its generator lineage. Paraphrase families A/B ("Could you
  please …", "Hey, …" / 「〜してもらえる？」「ねえ、…」) occur only in dev; families C/D occur only in eval. The
  validator rejects a family label, a family's surface marker, or a paraphrase skeleton that crosses splits.

## Known biases and limitations

- Author bias: cases, catalog and the MOCK resolver were designed together; a perfect MOCK score on a correct
  app only shows internal consistency.
- Template-driven phrasing; small vocabulary; paraphrase families are wrappers, not lexical paraphrases.
- en-US and ja-JP only; no honorific variation, dialects, or multi-request utterances.
- The MOCK's Japanese reading dictionary covers only the dataset vocabulary.
- All people and organization names in the data are fictional, synthetic data and are not related to any real person or organization. 登場する人名・組織名はすべて架空の合成データであり、実在の人物・団体とは関係ありません。 Common names inevitably match private individuals; names that matched well-known
  public figures were replaced before publication (see the repository's `docs/name-review.md`).

## License and provenance

| Component | Source | License |
|---|---|---|
| Cases, catalog, names, message texts | Created for SiriReady Bench by the author; fully synthetic | SiriReady Bench terms (see `LICENSE`) |
| App Schema identifiers (`messages.sendMessage` …) | Referenced from Apple's public documentation | Identifiers only; no documentation text is reproduced |

Contact: <https://nagayu-portfolio.nagayu.workers.dev/en>
