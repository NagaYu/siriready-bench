"""Phase 2 offline checks: reference-app generation, spot-check selection and sample, opt-in real smoke."""
import json
import os
import pathlib
import shutil
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
PYTHON = shutil.which("python3.12") or sys.executable
APPS = [("Messages", "OK", "MessagesOK", "dev.siriready.messages.ok"), ("Messages", "Broken", "MessagesBroken", "dev.siriready.messages.broken"),
        ("Calendar", "OK", "CalendarOK", "dev.siriready.calendar.ok"), ("Calendar", "Broken", "CalendarBroken", "dev.siriready.calendar.broken")]


def run(*args, **kw):
    return subprocess.run([PYTHON, *map(str, args)], capture_output=True, text=True, **kw)


@pytest.mark.parametrize("domain,variant,name,bundle", APPS)
def test_xcode_projects_are_generated_deterministically(tmp_path, domain, variant, name, bundle):
    result = run(ROOT / "Apps/tools/make_xcodeproj.py", "--name", name, "--bundle-id", bundle, "--app-dir", "App",
                 "--shared-dir", "../Shared", "--shared-dir", "../../Common", "--test-dir", "../../Harness", "--out", tmp_path)
    assert result.returncode == 0, result.stderr
    committed = ROOT / "Apps" / domain / variant / f"{name}.xcodeproj"
    for rel in ("project.pbxproj", f"xcshareddata/xcschemes/{name}.xcscheme"):
        assert (tmp_path / f"{name}.xcodeproj" / rel).read_bytes() == (committed / rel).read_bytes(), rel
    pbx = (committed / "project.pbxproj").read_text()
    assert "com.apple.product-type.bundle.ui-testing" in pbx and f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};" in pbx
    assert 'DEVELOPMENT_TEAM = "";' in pbx, "committed projects carry no signing team"


def test_seed_data_matches_the_v1_catalogs(tmp_path):
    assert run(ROOT / "Apps/tools/make_seed.py", "--apps-root", tmp_path).returncode == 0
    for domain in ("Messages", "Calendar"):
        assert (tmp_path / domain / "Shared/SeedData.swift").read_bytes() == (ROOT / "Apps" / domain / "Shared/SeedData.swift").read_bytes()


@pytest.mark.parametrize("domain,variant,name,bundle", APPS)
def test_every_app_declares_siriready_yaml_and_no_real_endpoints(domain, variant, name, bundle):
    app = ROOT / "Apps" / domain / variant
    assert (app / "siriready.yaml").exists()
    for src in app.rglob("*.swift"):
        for host in __import__("re").findall(r"https?://([^/\"]+)", src.read_text(encoding="utf-8")):
            assert host.endswith(".example"), f"{src}: {host} is not a reserved example domain"


def test_apps_readme_maps_fixtures_to_apps():
    readme = (ROOT / "Apps/README.md").read_text(encoding="utf-8")
    for fixture in ("messages_ok", "messages_broken", "calendar_ok", "calendar_broken"):
        assert fixture in readme
    assert "halting" in readme, "the toolchain-imposed deviation must be documented"


def test_spotcheck_selection_is_deterministic_and_stratified(tmp_path):
    assert run(ROOT / "dataset/select_spotcheck.py", "--out", tmp_path / "s.json").returncode == 0
    assert (tmp_path / "s.json").read_bytes() == (ROOT / "docs/spotcheck-cases.json").read_bytes()
    cases = json.loads((tmp_path / "s.json").read_text(encoding="utf-8"))["cases"]
    assert len(cases) == 30
    strata = {(c["app_id"], c["locale"]) for c in cases}
    assert strata == {("messages", "en-US"), ("messages", "ja-JP"), ("calendar", "en-US"), ("calendar", "ja-JP")}
    assert any(c["expected"]["resolution"] == "disambiguate" for c in cases)


def test_spotcheck_sample_is_labelled_and_template_matches():
    sample = json.loads((ROOT / "docs/spotcheck-sample.json").read_text(encoding="utf-8"))
    assert sample["sample"] is True and sample["protocol_version"] == "spotcheck-v1"
    assert all(r["notes"].startswith("SAMPLE") for r in sample["results"])
    assert "SAMPLE" in sample["device"]
    template = json.loads((ROOT / "docs/spotcheck-template.json").read_text(encoding="utf-8"))
    selected = [c["case_id"] for c in json.loads((ROOT / "docs/spotcheck-cases.json").read_text(encoding="utf-8"))["cases"]]
    assert template["sample"] is False
    assert [r["case_id"] for r in template["results"]] == selected == [r["case_id"] for r in sample["results"]]


@pytest.mark.skipif(os.environ.get("SIRIREADY_REAL") != "1", reason="real simulator smoke run is opt-in (SIRIREADY_REAL=1)")
def test_real_harness_smoke(tmp_path):
    """Discovers intents through AppIntentsTesting and executes one case on an iOS 27 simulator."""
    out = tmp_path / "smoke"
    result = subprocess.run([str(ROOT / "scripts/real_run.sh"), "messages_ok", "--limit", "1", "--out", str(out)],
                            capture_output=True, text=True, timeout=1800)
    assert result.returncode == 0, result.stdout[-2000:] + result.stderr[-2000:]
    raw = json.loads((out / "raw.json").read_text(encoding="utf-8"))
    assert raw["protocolVersion"] == "siriready-harness-v1"
    assert len(raw["cases"]) == 1 and raw["cases"][0]["run"]["ok"] is True
    assert raw["cases"][0]["effects"], "the executed intent left an observable effect"
    assert "(MOCK + REAL)" in (out / "mixed.md").read_text(encoding="utf-8")
