"""CLI smoke test: scripts/demo.sh runs audit → bench → report end to end (offline)."""
import json
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]

pytestmark = pytest.mark.skipif(shutil.which("swift") is None, reason="Swift toolchain not available")


@pytest.fixture(scope="module")
def demo(tmp_path_factory):
    out = tmp_path_factory.mktemp("demo")
    result = subprocess.run([str(ROOT / "scripts" / "demo.sh"), str(out)], capture_output=True, text=True, timeout=900)
    assert result.returncode == 0, result.stdout[-3000:] + result.stderr[-3000:]
    return out, result.stdout


def load(out, name):
    return json.loads((out / name / "report.json").read_text(encoding="utf-8"))


def test_demo_produces_reports_for_every_fixture(demo):
    out, stdout = demo
    for name in ("messages_ok", "messages_broken", "calendar_ok", "calendar_broken"):
        assert (out / name / "report.md").read_text(encoding="utf-8").startswith("# SiriReady Bench report")
        assert (out / name / "audit.md").exists()
        assert load(out, name)["conditions"]["mode"] == "MOCK"
    assert (out / "messages_compare.md").exists() and (out / "calendar_compare.md").exists()
    assert "OK 1272 cases" in stdout


def test_broken_scores_lower_with_the_expected_failure_classes(demo):
    out, _ = demo
    for domain, expected in (("messages", {"F1", "F2", "F3", "F4", "F6"}), ("calendar", {"F1", "F3", "F5", "F8"})):
        ok, broken = load(out, f"{domain}_ok"), load(out, f"{domain}_broken")
        assert broken["score"]["overall"] < ok["score"]["overall"]
        assert {k for k, v in broken["failureCounts"].items() if v} == expected
        assert {k for k, v in ok["failureCounts"].items() if v} <= {"F2", "F3"}   # documented MOCK limits only


def test_every_report_is_labelled_mock(demo):
    out, stdout = demo
    for md in out.rglob("*.md"):
        if md.name.startswith("report") or md.name.endswith("_compare.md"):
            assert "MOCK" in md.read_text(encoding="utf-8"), md
    assert "[MOCK]" in stdout
