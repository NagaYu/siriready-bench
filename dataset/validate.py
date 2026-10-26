#!/usr/bin/env python3
"""Validate the SiriReady Bench dataset: format, reference integrity, app-disjoint splits and leaks.

Standard library only. Exits non-zero (and prints every problem) if any check fails.

  python3.12 dataset/validate.py [--dataset v1.2] [--dev FILE] [--eval FILE] [--entities DIR] [--no-profile]

Validates dataset/v1.2 (1,272 cases) with its profile, including the generator-holdout checks;
every case needs `mention` / `generator`.
`--no-profile` skips the size/balance profile so the structural checks can be run on small
hand-made files.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import unicodedata
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent

ENUMS = {
    "split": {"dev", "eval"},
    "domain": {"messages", "calendar"},
    "locale": {"en-US", "ja-JP"},
    "noise": {"none", "asr_homophone", "code_switch", "typo", "word_order"},
    "difficulty": {"easy", "medium", "hard"},
}
RESOLUTIONS = {"execute", "disambiguate"}
CASE_KEYS = {"case_id", "split", "app_id", "domain", "locale", "utterance", "noise", "state", "expected",
             "adversarial", "difficulty", "tags"}
# Added in dataset v1 (optional in v0 files, required by the v1 profile).
OPTIONAL_KEYS = {"mention", "generator"}

# Parameters every case of an intent must carry (Phase 2 scores params).
REQUIRED_PARAMS = {
    "SendMessageIntent": {"body"}, "DraftMessageIntent": {"body"}, "SetMessageReadStatusIntent": {"is_read"},
    "OpenConversationIntent": set(), "CreateEventIntent": {"title", "day", "time"}, "UpdateEventIntent": {"time"},
    "DeleteEventIntent": set(), "OpenEventIntent": set(), "ShareEventIntent": {"invitee"},
}

# Generator-holdout: paraphrase families allowed per split, and the surface markers each family leaves.
HOLDOUT = {"dev": {"A", "B"}, "eval": {"C", "D"}}
FAMILY_MARKERS = {
    "A": [r"^Could you please ", r"もらえる？$", r"^すみません、"],
    "B": [r"^Hey, ", r"^ねえ、"],
    "C": [r"^I need you to ", r"おいてほしい$", r"^お願いなんだけど、"],
    "D": [r", thanks$", r"、お願い$"],
}
GENERATOR = re.compile(r"^(v0-template|(?:v1-para|v1\.1-gap)-([A-Z]))$")
STATE_KEYS = {"screen", "visible_entities", "prior_turn"}
EXPECTED_KEYS = {"intent", "entity_id", "params", "resolution", "candidates"}
CASE_ID = re.compile(r"^[a-z]+-[a-z]{2}-\d{3}$")


def load_jsonl(path, problems):
    cases = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            cases.append((path.name, n, json.loads(line)))
        except json.JSONDecodeError as e:
            problems.append(f"{path.name}:{n}: invalid JSON ({e})")
    return cases


def normalize(text):
    """Normalization used for leak detection: NFKC, casefold, collapse whitespace."""
    return " ".join(unicodedata.normalize("NFKC", text).casefold().split())


def check_format(where, c, problems):
    def bad(msg):
        problems.append(f"{where}: {msg}")

    if not isinstance(c, dict):
        return bad("case is not an object")
    missing, extra = CASE_KEYS - c.keys(), c.keys() - CASE_KEYS - OPTIONAL_KEYS
    if missing:
        bad(f"missing keys {sorted(missing)}")
    if extra:
        bad(f"unknown keys {sorted(extra)}")
    if missing:
        return
    if not isinstance(c["case_id"], str) or not CASE_ID.match(c["case_id"]):
        bad(f"case_id {c['case_id']!r} does not match {CASE_ID.pattern}")
    for key, allowed in ENUMS.items():
        if c[key] not in allowed:
            bad(f"{key}={c[key]!r} not in {sorted(allowed)}")
    if not isinstance(c["utterance"], str) or not c["utterance"].strip():
        bad("utterance must be a non-empty string")
    if not isinstance(c["adversarial"], bool):
        bad("adversarial must be a boolean")
    if not isinstance(c["tags"], list) or not all(isinstance(t, str) for t in c["tags"]):
        bad("tags must be a list of strings")
    state, expected = c["state"], c["expected"]
    if not isinstance(state, dict) or state.keys() != STATE_KEYS:
        bad(f"state must have exactly {sorted(STATE_KEYS)}")
    else:
        if state["screen"] is not None and not isinstance(state["screen"], str):
            bad("state.screen must be a string or null")
        if not isinstance(state["visible_entities"], list):
            bad("state.visible_entities must be a list")
        pt = state["prior_turn"]
        if pt is not None and (not isinstance(pt, dict) or not {"utterance", "intent", "entity_id"} <= pt.keys()):
            bad("state.prior_turn must be null or {utterance, intent, entity_id}")
    if not isinstance(expected, dict) or expected.keys() != EXPECTED_KEYS:
        bad(f"expected must have exactly {sorted(EXPECTED_KEYS)}")
    else:
        if expected["resolution"] not in RESOLUTIONS:
            bad(f"expected.resolution={expected['resolution']!r} not in {sorted(RESOLUTIONS)}")
        if not isinstance(expected["params"], dict):
            bad("expected.params must be an object")
        required = REQUIRED_PARAMS.get(expected.get("intent"), set())
        if isinstance(expected["params"], dict) and not required <= expected["params"].keys():
            bad(f"expected.params is missing {sorted(required - expected['params'].keys())} for {expected.get('intent')}")
        if expected["resolution"] == "disambiguate":
            if expected["entity_id"] is not None or len(expected["candidates"]) < 2:
                bad("a disambiguate case needs entity_id=null and >=2 candidates")
        elif expected["candidates"]:
            bad("an execute case must not list candidates")


def check_references(where, c, catalogs, problems):
    catalog = catalogs.get(c["app_id"])
    if catalog is None:
        problems.append(f"{where}: no entity catalog for app_id={c['app_id']!r}")
        return
    ids = catalog["_ids"]
    exp, state = c["expected"], c["state"]
    if exp["intent"] not in catalog["intents"]:
        problems.append(f"{where}: expected.intent {exp['intent']!r} is not an intent of app {c['app_id']}")
    refs = [("expected.entity_id", exp["entity_id"])] + [("expected.candidates", x) for x in exp["candidates"]]
    refs += [("state.visible_entities", x) for x in state["visible_entities"]]
    if state["prior_turn"]:
        refs.append(("state.prior_turn.entity_id", state["prior_turn"]["entity_id"]))
        if state["prior_turn"]["intent"] not in catalog["intents"]:
            problems.append(f"{where}: state.prior_turn.intent {state['prior_turn']['intent']!r} unknown")
    for label, ref in refs:
        if ref is not None and ref not in ids:
            problems.append(f"{where}: {label} {ref!r} does not exist in entities/{c['app_id']}.json")
    mention = c.get("mention")
    if mention is not None and normalize(mention) not in normalize(c["utterance"]):
        problems.append(f"{where}: mention {mention!r} does not occur in the utterance")
    if c["domain"] != catalog["domain"]:
        problems.append(f"{where}: domain {c['domain']!r} does not match app {c['app_id']} ({catalog['domain']})")


def load_catalogs(entities_dir, problems):
    catalogs = {}
    for path in sorted(pathlib.Path(entities_dir).glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("synthetic") is not True:
            problems.append(f"{path.name}: catalogs must be marked synthetic=true (no real personal data)")
        ids = [e["id"] for e in data.get("entities", [])]
        dupes = [i for i, n in Counter(ids).items() if n > 1]
        if dupes:
            problems.append(f"{path.name}: duplicate entity ids {dupes}")
        for e in data.get("entities", []):
            if not e.get("forms"):
                problems.append(f"{path.name}: entity {e.get('id')} has no forms")
            for k, v in e.get("related", {}).items():
                if v not in ids:
                    problems.append(f"{path.name}: entity {e['id']} related.{k}={v!r} does not exist")
        data["_ids"] = set(ids)
        catalogs[data["app_id"]] = data
    return catalogs


def check_splits(cases, problems):
    """App-disjoint splits and leak checks across (and within) splits."""
    apps_by_split = {}
    for where, c in cases:
        apps_by_split.setdefault(c["split"], set()).add(c["app_id"])
    split_names = sorted(apps_by_split)
    for i, a in enumerate(split_names):
        for b in split_names[i + 1:]:
            shared = apps_by_split[a] & apps_by_split[b]
            if shared:
                problems.append(f"leak: app(s) {sorted(shared)} appear in both {a} and {b} (splits must be app-disjoint)")
    seen = {}
    ids = {}
    for where, c in cases:
        key = (normalize(c["utterance"]), json.dumps(c["state"], sort_keys=True, ensure_ascii=False))
        if key in seen:
            other_where, other_split = seen[key]
            kind = "cross-split leak" if other_split != c["split"] else "duplicate"
            problems.append(f"{kind}: {where} repeats utterance+state of {other_where}")
        else:
            seen[key] = (where, c["split"])
        if c["case_id"] in ids:
            problems.append(f"duplicate case_id {c['case_id']} ({where}, {ids[c['case_id']]})")
        ids[c["case_id"]] = where


def skeleton(c):
    """Utterance with the entity mention, message bodies and digits masked (lineage fingerprint)."""
    u = c["utterance"]
    if c.get("mention"):
        u = re.sub(re.escape(c["mention"]), "<E>", u, flags=re.IGNORECASE)
    u = re.sub(r"「[^」]*」", "<B>", u)
    u = re.sub(r" saying .*$| : .*$|: .*$", " <B>", u)
    u = re.sub(r"\d+(:\d+)?\s*(am|pm|時半|時)?", "<T>", u)
    return normalize(u)


def check_holdout(cases, problems):
    """Generator-holdout: a paraphrase family may only appear in its own split."""
    by_split = {}
    for where, c in cases:
        gen = c.get("generator")
        if gen is None:
            problems.append(f"{where}: missing generator lineage")
            continue
        m = GENERATOR.match(gen)
        if not m:
            problems.append(f"{where}: unknown generator {gen!r}")
            continue
        family = m.group(2)
        if family and family not in HOLDOUT.get(c["split"], set()):
            problems.append(f"generator-holdout leak: {where} uses family {family} in the {c['split']} split")
        for fam, patterns in FAMILY_MARKERS.items():
            if fam not in HOLDOUT.get(c["split"], set()) and any(re.search(pat, c["utterance"]) for pat in patterns):
                problems.append(f"generator-holdout leak: {where} carries family {fam} phrasing in the {c['split']} split")
        if family:
            by_split.setdefault(c["split"], {}).setdefault(skeleton(c), where)
    splits = sorted(by_split)
    for i, a in enumerate(splits):
        for b in splits[i + 1:]:
            for sk in by_split[a].keys() & by_split[b].keys():
                problems.append(f"generator-holdout leak: paraphrase skeleton {sk!r} in both {a} ({by_split[a][sk]}) and {b} ({by_split[b][sk]})")


def check_v0_subset(cases, v0_dir, problems, label="v0"):
    """A newer version must keep every case of `v0_dir` with identical utterance, state and expectations."""
    v1 = {c["case_id"]: c for _, c in cases}
    for name in ("cases_dev.jsonl", "cases_eval.jsonl"):
        path = pathlib.Path(v0_dir) / name
        if not path.exists():
            continue
        for _, n, old in load_jsonl(path, problems):
            new = v1.get(old["case_id"])
            if new is None:
                problems.append(f"{label} case {old['case_id']} is missing")
                continue
            for key in ("utterance", "state", "expected", "split", "app_id", "locale", "noise", "adversarial", "difficulty", "tags",
                        "mention", "generator"):
                if key in old and new.get(key) != old[key]:
                    problems.append(f"{label} case {old['case_id']} changed {key}")


PROFILES = {"v1": {"total": 1200, "locale": (600, 600), "domain": (600, 600)},
            "v1.1": {"total": 1272, "locale": (636, 636), "domain": (624, 648)},
            "v1.2": {"total": 1272, "locale": (636, 636), "domain": (624, 648)}}


def check_profile_v1(cases, problems, version="v1"):
    prof = PROFILES[version]
    total = len(cases)
    if total != prof["total"]:
        problems.append(f"profile: expected {prof['total']} cases, found {total}")
    loc = Counter(c["locale"] for _, c in cases)
    dom = Counter(c["domain"] for _, c in cases)
    if (loc["en-US"], loc["ja-JP"]) != prof["locale"]:
        problems.append(f"profile: expected EN {prof['locale'][0]} / JA {prof['locale'][1]}, found {dict(loc)}")
    if (dom["messages"], dom["calendar"]) != prof["domain"]:
        problems.append(f"profile: expected messages {prof['domain'][0]} / calendar {prof['domain'][1]}, found {dict(dom)}")
    if version in ("v1.1", "v1.2"):
        tags = Counter(t for _, c in cases for t in c["tags"])
        for required in ("gap_location", "gap_calendar_alias", "gap_title_index", "gap_conversation_index"):
            if not tags[required]:
                problems.append(f"profile: no cases tagged {required}")
        if not any("location" in c["expected"]["params"] and c["app_id"] == "calendar" for _, c in cases):
            problems.append("profile: no calendar case carries a location (needed to observe F8)")
    if total and sum(c["adversarial"] for _, c in cases) / total < 0.30:
        problems.append("profile: adversarial share < 30%")
    for where, c in cases:
        if "mention" not in c or "generator" not in c:
            problems.append(f"{where}: v1 cases need mention and generator")


def check_profile(cases, problems):
    total = len(cases)
    if total != 400:
        problems.append(f"profile: expected 400 cases, found {total}")
    if not total:
        return
    loc = Counter(c["locale"] for _, c in cases)
    dom = Counter(c["domain"] for _, c in cases)
    if loc["en-US"] != loc["ja-JP"]:
        problems.append(f"profile: locale imbalance {dict(loc)}")
    if dom["messages"] != dom["calendar"]:
        problems.append(f"profile: domain imbalance {dict(dom)}")
    adv = sum(c["adversarial"] for _, c in cases) / total
    if adv < 0.30:
        problems.append(f"profile: adversarial share {adv:.0%} < 30%")
    tags = Counter(t for _, c in cases for t in c["tags"])
    for required in ("same_name_ambiguous", "same_name_qualified", "homophone", "alias", "screen", "multi_turn"):
        if not tags[required]:
            problems.append(f"profile: no cases tagged {required}")
    if not any(c["locale"] == "ja-JP" and "homophone" in c["tags"] for _, c in cases):
        problems.append("profile: no Japanese homophone (同音異義) cases")
    if not any(c["expected"]["resolution"] == "disambiguate" for _, c in cases):
        problems.append("profile: no cases where asking for clarification is correct")


def validate(dev, eval_, entities, profile=True, version="v0"):
    problems = []
    catalogs = load_catalogs(entities, problems)
    cases = []
    for path, split in ((pathlib.Path(dev), "dev"), (pathlib.Path(eval_), "eval")):
        for name, n, c in load_jsonl(path, problems):
            where = f"{name}:{n}"
            check_format(where, c, problems)
            if not isinstance(c, dict) or not CASE_KEYS <= c.keys():
                continue
            if c["split"] != split:
                problems.append(f"{where}: split={c['split']!r} but file is the {split} split")
            check_references(where, c, catalogs, problems)
            cases.append((where, c))
    check_splits(cases, problems)
    if version in ("v1", "v1.1", "v1.2"):
        check_holdout(cases, problems)
    if version in ("v1", "v1.1"):
        check_v0_subset(cases, HERE, problems)
    if version == "v1.1":
        check_v0_subset(cases, HERE / "v1", problems, label="v1")
    if profile:
        if version == "v0":
            check_profile(cases, problems)
        else:
            check_profile_v1(cases, problems, version)
    return problems, cases


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dataset", choices=["v1.2"], default="v1.2")
    parser.add_argument("--dev")
    parser.add_argument("--eval")
    parser.add_argument("--entities")
    parser.add_argument("--no-profile", action="store_true")
    args = parser.parse_args(argv)
    root = HERE if args.dataset == "v0" else HERE / args.dataset
    problems, cases = validate(args.dev or root / "cases_dev.jsonl", args.eval or root / "cases_eval.jsonl",
                               args.entities or root / "entities", profile=not args.no_profile, version=args.dataset)
    if problems:
        for p in problems:
            print(f"FAIL {p}", file=sys.stderr)
        print(f"{len(problems)} problem(s) in {len(cases)} case(s)", file=sys.stderr)
        return 1
    adv = sum(c["adversarial"] for _, c in cases)
    extra = ", generator-holdout clean" if args.dataset != "v0" else ""
    print(f"OK {len(cases)} cases, adversarial {adv}/{len(cases)}, splits app-disjoint, no leaks{extra}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
