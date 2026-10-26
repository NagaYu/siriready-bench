#!/usr/bin/env python3
"""Select the 30 cases for a manual Siri spot check (docs/spotcheck-protocol.md).

Standard library only, deterministic. Stratified over app (messages / calendar) × locale
(en-US / ja-JP); inside each stratum one case per scenario family, then two extra cases
where asking for clarification is the correct outcome.

  python3.12 dataset/select_spotcheck.py [--dataset v1.2] [--out docs/spotcheck-cases.json] [--docs]

`--docs` also rewrites docs/spotcheck-template.json and the clearly-labelled fictional
docs/spotcheck-sample.json for the selected cases.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import random

HERE = pathlib.Path(__file__).resolve().parent
FAMILIES = ["basic", "noise", "alias", "same_name_qualified", "homophone", "screen", "multi_turn"]
SEED = 2702
TOTAL = 30


def load(root):
    cases = []
    for name in ("cases_dev.jsonl", "cases_eval.jsonl"):
        cases += [json.loads(line) for line in (root / name).read_text(encoding="utf-8").splitlines() if line.strip()]
    return cases


def select(cases):
    rnd = random.Random(SEED)
    picked = []
    strata = [(app, loc) for app in ("messages", "calendar") for loc in ("en-US", "ja-JP")]
    for app, loc in strata:
        pool = [c for c in cases if c["app_id"] == app and c["locale"] == loc]
        for fam in FAMILIES:
            options = sorted((c for c in pool if fam in c["tags"]), key=lambda c: c["case_id"])
            if options:
                picked.append(rnd.choice(options))
    ambiguous = sorted((c for c in cases if c["expected"]["resolution"] == "disambiguate" and c not in picked),
                       key=lambda c: c["case_id"])
    while len(picked) < TOTAL:
        c = rnd.choice(ambiguous)
        if c not in picked:
            picked.append(c)
    return picked


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dataset", default="v1.2")
    ap.add_argument("--docs", action="store_true", help="also write the template and the SAMPLE log")
    ap.add_argument("--out", default=str(HERE.parent / "docs" / "spotcheck-cases.json"))
    args = ap.parse_args(argv)
    root = HERE / args.dataset if args.dataset != "v0" else HERE
    picked = select(load(root))
    rows = [{"case_id": c["case_id"], "app_id": c["app_id"], "locale": c["locale"], "tags": c["tags"],
             "utterance": c["utterance"], "state": c["state"],
             "expected": {"intent": c["expected"]["intent"], "entity_id": c["expected"]["entity_id"],
                          "resolution": c["expected"]["resolution"], "candidates": c["expected"]["candidates"]}}
            for c in picked]
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"dataset": args.dataset, "seed": SEED, "cases": rows}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {len(rows)} cases to {out}")
    if args.docs:
        write_docs(rows, out.parent)


# Fictional outcomes used to illustrate the protocol in the SAMPLE log (never observations).
SAMPLE_OUTCOMES = {
    "messages-en-135": (False, "SendMessageIntent", None, "SAMPLE: code-switched '下書き' was treated as send"),
    "messages-ja-071": (True, "OpenConversationIntent", "disambiguation", "SAMPLE: Siri asked which みづき"),
    "calendar-en-269": (False, "DeleteEventIntent", "ev_neal_lunch", "SAMPLE: deleted without asking"),
    "calendar-ja-170": (False, None, None, "SAMPLE: Siri answered with a web result"),
    "calendar-ja-084": (True, "DeleteEventIntent", "ev_from_expected", "SAMPLE: confirmation dialog shown first"),
}


def write_docs(rows, docs):
    template = {"protocol_version": "spotcheck-v1", "sample": False, "device": "", "os": "", "locale": "", "siri_settings": "",
                "recorded_on": "", "results": [{"case_id": c["case_id"], "input_mode": "", "reached_intent": None,
                                                "resolved_entity": None, "success": False, "notes": ""} for c in rows]}
    results = []
    for i, c in enumerate(rows):
        exp = c["expected"]
        default = (True, exp["intent"], exp["entity_id"] or ("disambiguation" if exp["resolution"] == "disambiguate" else None),
                   "SAMPLE: matched expected")
        ok, intent, ent, note = SAMPLE_OUTCOMES.get(c["case_id"], default)
        if ent == "ev_from_expected":
            ent = exp["entity_id"]
        results.append({"case_id": c["case_id"], "input_mode": "voice" if i % 3 else "typed", "reached_intent": intent,
                        "resolved_entity": ent, "success": ok, "notes": note})
    sample = {"protocol_version": "spotcheck-v1", "sample": True, "device": "SAMPLE (no device was used)",
              "os": "SAMPLE (iOS 27.x)", "locale": "SAMPLE (en-US / ja-JP)",
              "siri_settings": "SAMPLE — fictional values for illustration only", "recorded_on": None, "results": results}
    for name, data in (("spotcheck-template.json", template), ("spotcheck-sample.json", sample)):
        (docs / name).write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {docs / 'spotcheck-template.json'} and {docs / 'spotcheck-sample.json'} (SAMPLE)")


if __name__ == "__main__":
    main()
