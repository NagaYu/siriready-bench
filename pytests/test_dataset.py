"""Dataset v1.2 tests: validation, deterministic generation, profile, generator-holdout and the validator's checks.

generate.py / validate.py target Python 3.12; when a python3.12 interpreter is available the
scripts are executed with it as subprocesses, otherwise with the interpreter running pytest.
"""
import json
import pathlib
import shutil
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATASET = ROOT / "dataset"
V12 = DATASET / "v1.2"
PYTHON = shutil.which("python3.12") or sys.executable

sys.path.insert(0, str(DATASET))
import validate  # noqa: E402


def run(*args):
    return subprocess.run([PYTHON, *map(str, args)], capture_output=True, text=True)


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path, cases):
    path.write_text("".join(json.dumps(c, ensure_ascii=False) + "\n" for c in cases), encoding="utf-8")


def all_cases():
    return read_jsonl(V12 / "cases_dev.jsonl") + read_jsonl(V12 / "cases_eval.jsonl")


@pytest.fixture()
def copy(tmp_path):
    """A writable copy of the committed dataset."""
    shutil.copytree(V12, tmp_path / "v12")
    return tmp_path / "v12"


def validate_dir(d, *extra):
    return run(DATASET / "validate.py", "--dataset", "v1.2", "--dev", d / "cases_dev.jsonl", "--eval", d / "cases_eval.jsonl",
               "--entities", d / "entities", *extra)


def test_committed_dataset_passes_validation():
    result = run(DATASET / "validate.py")
    assert result.returncode == 0, result.stderr
    assert "OK 1272 cases" in result.stdout and "generator-holdout clean" in result.stdout


def test_generation_is_deterministic_and_matches_committed_files(tmp_path):
    for out in ("a", "b"):
        result = run(DATASET / "generate.py", "--out", tmp_path / out)
        assert result.returncode == 0, result.stderr
    assert sorted(p.name for p in (tmp_path / "a").iterdir()) == ["v1.2"]
    for rel in ("cases_dev.jsonl", "cases_eval.jsonl", "entities/messages.json", "entities/calendar.json"):
        a = (tmp_path / "a" / "v1.2" / rel).read_bytes()
        assert a == (tmp_path / "b" / "v1.2" / rel).read_bytes(), f"{rel} differs between runs"
        assert a == (V12 / rel).read_bytes(), f"v1.2/{rel} is stale; re-run dataset/generate.py"


def test_profile_size_balance_and_adversarial_share():
    cases = all_cases()
    assert len(cases) == 1272
    assert sum(c["locale"] == "en-US" for c in cases) == 636
    assert sum(c["domain"] == "messages" for c in cases) == 624
    assert sum(c["adversarial"] for c in cases) / len(cases) >= 0.30
    tags = {t for c in cases for t in c["tags"]}
    assert {"same_name_ambiguous", "same_name_qualified", "homophone", "alias", "screen", "multi_turn"} <= tags
    assert {"gap_location", "gap_calendar_alias", "gap_title_index", "gap_conversation_index"} <= tags
    assert {c["noise"] for c in cases} == {"none", "asr_homophone", "code_switch", "typo", "word_order"}


def test_splits_are_app_disjoint_and_generator_families_are_held_out():
    dev = read_jsonl(V12 / "cases_dev.jsonl")
    ev = read_jsonl(V12 / "cases_eval.jsonl")
    assert {c["app_id"] for c in dev} == {"messages"} and {c["app_id"] for c in ev} == {"calendar"}
    assert all(c["split"] == "dev" for c in dev) and all(c["split"] == "eval" for c in ev)
    assert {c["generator"] for c in dev} == {"v0-template", "v1-para-A", "v1-para-B", "v1.1-gap-A", "v1.1-gap-B"}
    assert {c["generator"] for c in ev} == {"v0-template", "v1-para-C", "v1-para-D", "v1.1-gap-C", "v1.1-gap-D"}


def test_every_case_has_params_and_named_cases_have_a_mention():
    for c in all_cases():
        exp, state = c["expected"], c["state"]
        if (exp["entity_id"] or exp["candidates"]) and not state["prior_turn"] and not state["visible_entities"]:
            assert c["mention"], c["case_id"]
    creates = [c for c in all_cases() if c["expected"]["intent"] == "CreateEventIntent"]
    assert creates and all({"title", "day", "time"} <= c["expected"]["params"].keys() for c in creates)
    assert any("location" in c["expected"]["params"] for c in creates)


def test_catalogs_are_synthetic():
    for name in ("messages", "calendar"):
        catalog = json.loads((V12 / "entities" / f"{name}.json").read_text(encoding="utf-8"))
        assert catalog["synthetic"] is True
        assert "synthetic" in catalog["license"].lower()
        assert catalog["dataset_version"] == "v1.2"


def test_cross_split_leak_is_detected(copy):
    dev = read_jsonl(copy / "cases_dev.jsonl")
    ev = read_jsonl(copy / "cases_eval.jsonl")
    leaked = dict(ev[0], case_id="calendar-en-999", split="dev")  # same utterance + state, now also in dev
    write_jsonl(copy / "cases_dev.jsonl", dev + [leaked])
    result = validate_dir(copy, "--no-profile")
    assert result.returncode != 0
    assert "cross-split leak" in result.stderr
    assert "appear in both" in result.stderr  # the calendar app now spans both splits


def test_same_utterance_with_different_case_noise_is_still_a_leak(copy):
    dev = read_jsonl(copy / "cases_dev.jsonl")
    twin = dict(dev[0], case_id="messages-en-998", utterance="  " + dev[0]["utterance"].upper() + " ")
    write_jsonl(copy / "cases_dev.jsonl", dev + [twin])
    result = validate_dir(copy, "--no-profile")
    assert result.returncode != 0 and "duplicate" in result.stderr


def test_family_relabelled_into_the_wrong_split_is_a_leak(copy):
    dev = read_jsonl(copy / "cases_dev.jsonl")
    next(c for c in dev if c["generator"] == "v1-para-A")["generator"] = "v1-para-C"
    write_jsonl(copy / "cases_dev.jsonl", dev)
    result = validate_dir(copy)
    assert result.returncode != 0
    assert "generator-holdout leak" in result.stderr and "family C in the dev split" in result.stderr


def test_eval_phrasing_in_dev_is_a_leak_even_if_labelled(copy):
    dev = read_jsonl(copy / "cases_dev.jsonl")
    target = next(c for c in dev if c["generator"] == "v1-para-B" and c["locale"] == "en-US")
    target["utterance"] = "I need you to " + target["utterance"]   # eval family C wrapper, still labelled B
    write_jsonl(copy / "cases_dev.jsonl", dev)
    result = validate_dir(copy)
    assert result.returncode != 0 and "carries family C phrasing in the dev split" in result.stderr


def test_missing_entity_reference_is_detected(copy):
    dev = read_jsonl(copy / "cases_dev.jsonl")
    dev[0]["expected"]["entity_id"] = "c_does_not_exist"
    dev[1]["state"]["visible_entities"] = ["msg_xx_99"]
    write_jsonl(copy / "cases_dev.jsonl", dev)
    result = validate_dir(copy)
    assert result.returncode != 0
    assert "c_does_not_exist" in result.stderr and "msg_xx_99" in result.stderr


def test_format_errors_are_detected(copy):
    dev = read_jsonl(copy / "cases_dev.jsonl")
    dev[0]["noise"] = "reverb"
    del dev[1]["difficulty"]
    dev[2]["expected"]["resolution"] = "disambiguate"  # but with an entity_id and no candidates
    write_jsonl(copy / "cases_dev.jsonl", dev)
    result = validate_dir(copy)
    assert result.returncode != 0
    assert "noise='reverb'" in result.stderr
    assert "missing keys ['difficulty']" in result.stderr
    assert "disambiguate case needs" in result.stderr


def test_missing_params_and_bad_mention_are_detected(copy):
    ev = read_jsonl(copy / "cases_eval.jsonl")
    create = next(c for c in ev if c["expected"]["intent"] == "CreateEventIntent" and c["generator"] != "v0-template")
    del create["expected"]["params"]["time"]
    named = next(c for c in ev if c["mention"] and c["generator"] != "v0-template")
    named["mention"] = "Nonexistent Meeting"
    write_jsonl(copy / "cases_eval.jsonl", ev)
    result = validate_dir(copy)
    assert result.returncode != 0
    assert "params is missing ['time']" in result.stderr
    assert "does not occur in the utterance" in result.stderr


def test_unknown_intent_and_wrong_split_are_detected(copy):
    ev = read_jsonl(copy / "cases_eval.jsonl")
    ev[0]["expected"]["intent"] = "SendMessageIntent"  # not a calendar intent
    ev[1]["split"] = "dev"
    write_jsonl(copy / "cases_eval.jsonl", ev)
    result = validate_dir(copy, "--no-profile")
    assert result.returncode != 0
    assert "not an intent of app calendar" in result.stderr
    assert "file is the eval split" in result.stderr


def test_non_synthetic_catalog_is_rejected(copy):
    path = copy / "entities" / "messages.json"
    catalog = json.loads(path.read_text(encoding="utf-8"))
    catalog["synthetic"] = False
    path.write_text(json.dumps(catalog, ensure_ascii=False), encoding="utf-8")
    result = validate_dir(copy)
    assert result.returncode != 0 and "synthetic=true" in result.stderr


def test_profile_flags_wrong_size(copy):
    write_jsonl(copy / "cases_eval.jsonl", read_jsonl(copy / "cases_eval.jsonl")[:-1])
    result = validate_dir(copy)
    assert result.returncode != 0 and "expected 1272 cases" in result.stderr
    assert validate_dir(copy, "--no-profile").returncode == 0


def test_normalize_is_used_for_leak_keys():
    assert validate.normalize("  Cancel  QBR ") == validate.normalize("cancel qbr")
    assert validate.normalize("ＱＢＲをキャンセル") == validate.normalize("qbrをキャンセル")
