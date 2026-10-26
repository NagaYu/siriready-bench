"""HF package, pre-publication scan, name review, CI workflow shape."""
import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATASET = ROOT / "dataset"
PYTHON = shutil.which("python3.12") or sys.executable


def run(*args, python=PYTHON, **kw):
    return subprocess.run([python, *map(str, args)], capture_output=True, text=True, **kw)


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path, cases):
    path.write_text("".join(json.dumps(c, ensure_ascii=False) + "\n" for c in cases), encoding="utf-8")


# --- HF package -------------------------------------------------------------------------------

HAS_PYARROW = importlib.util.find_spec("pyarrow") is not None


@pytest.mark.skipif(not HAS_PYARROW, reason="pyarrow is needed to read the Parquet mirror")
def test_hf_package_checks_out():
    result = run(ROOT / "hf/build_hf.py", "--check", python=sys.executable)
    assert result.returncode == 0, result.stderr
    assert "624 rows" in result.stdout


def test_hf_package_is_dev_only_and_counts_match():
    manifest = json.loads((ROOT / "hf/MANIFEST.json").read_text(encoding="utf-8"))
    cases = read_jsonl(ROOT / "hf/data/dev.jsonl")
    assert manifest["rows"] == len(cases) == 624
    assert {c["split"] for c in cases} == {"dev"} and {c["app_id"] for c in cases} == {"messages"}
    assert manifest["locales"] == {"en-US": 312, "ja-JP": 312}
    # The package source moved from v1.1 to v1.2 with the rename (same 624 dev cases).
    assert (ROOT / "hf/data/dev.jsonl").read_bytes() == (DATASET / "v1.2/cases_dev.jsonl").read_bytes()
    card = (ROOT / "hf/README.md").read_text(encoding="utf-8")
    assert "Only the dev split is published" in card and "license: other" in card
    assert not any(p.name.startswith("cases_eval") for p in (ROOT / "hf").rglob("*"))


# --- pre-publication scan ---------------------------------------------------------------------

def scan(*args):
    return run(ROOT / "scripts/prepublish_scan.py", *args)


def test_scan_flags_planted_secrets_and_personal_data(tmp_path):
    (tmp_path / "ok.txt").write_text("synthetic data only, see https://nagayu-portfolio.nagayu.workers.dev/en\n")
    clean = scan("--dir", tmp_path)
    assert clean.returncode == 0, clean.stdout
    # Planted values are assembled from fragments so this test file itself stays clean for the scanner.
    (tmp_path / "leak.py").write_text("API_" + 'KEY = "' + "abcd1234" + 'efgh5678ijkl"\nkey = "AK' + "IA" + "ABCDEFGHIJKLMNOP" + '"\n')
    (tmp_path / "paths.md").write_text("built in /Us" + "ers/someone/project and mailed to someone" + chr(64) + "gmail.com\n")
    (tmp_path / "CLAUDE.md").write_text("instructions\n")
    dirty = scan("--dir", tmp_path)
    assert dirty.returncode == 1
    for label in ("generic secret assignment", "AWS access key", "home directory path", "e-mail address", "developer instruction file"):
        assert label in dirty.stdout


def test_scan_of_tracked_files_has_no_blocking_findings():
    result = scan()
    assert result.returncode == 0, result.stdout
    assert "0 blocking" in result.stdout


def test_name_review_is_current(tmp_path):
    before = (ROOT / "docs/name-review.md").read_bytes()
    assert run(ROOT / "scripts/list_names.py").returncode == 0
    assert (ROOT / "docs/name-review.md").read_bytes() == before


# --- CI workflows -----------------------------------------------------------------------------

@pytest.mark.skipif(importlib.util.find_spec("yaml") is None, reason="PyYAML not installed")
def test_workflows_shape():
    import yaml
    offline = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())
    real = yaml.safe_load((ROOT / ".github/workflows/real-run.yml").read_text())
    triggers = real[True] if True in real else real["on"]           # PyYAML reads `on:` as True
    assert set(triggers) == {"workflow_dispatch"}, "real runs are manual only"
    assert triggers["workflow_dispatch"]["inputs"]["app"]["default"] != "all"
    assert real["jobs"]["real"]["strategy"]["max-parallel"] == 1
    steps = " ".join(str(s.get("run", "")) for s in offline["jobs"]["offline"]["steps"])
    assert "scripts/ci_local.sh" in steps
