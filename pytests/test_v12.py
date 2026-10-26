"""Results on dataset v1.2 (results/phase4): provenance record of each run and the name review."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
APPS = ("messages_ok", "messages_broken", "calendar_ok", "calendar_broken")


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def test_phase4_results_record_what_was_measured_for_v12():
    for app in APPS:
        merge = json.loads((ROOT / f"results/phase4/{app}/MERGE.json").read_text(encoding="utf-8"))
        raw = json.loads((ROOT / f"results/phase4/{app}/raw.json").read_text(encoding="utf-8"))
        plan = json.loads((ROOT / f"results/phase4/{app}/plan.json").read_text(encoding="utf-8"))
        assert merge["app"] == app and merge["dataset"] == "v1.2"
        assert len(raw["indexProbes"]) == len(plan["indexProbes"])
        assert merge["carried_over_cases"] + len(merge["remeasured_cases"]) == len(raw["cases"])
        if app.startswith("messages"):
            assert merge["remeasured_cases"] and merge["remeasured_probes"] == 22
        else:
            assert merge["remeasured_cases"] == [] and merge["remeasured_probes"] == 0


def test_observed_ids_exist_in_the_v12_catalogs():
    for app in APPS:
        domain = app.split("_")[0]
        catalog = {e["id"] for e in json.loads((ROOT / f"dataset/v1.2/entities/{domain}.json").read_text(encoding="utf-8"))["entities"]}
        raw = json.loads((ROOT / f"results/phase4/{app}/raw.json").read_text(encoding="utf-8"))
        seen = {i for c in raw["cases"] for k in ("spotlight", "stringQuery", "annotations", "priorFetch") for i in (c.get(k) or {}).get("ids", [])}
        seen |= {i for p in raw["indexProbes"] for i in p["ids"] + [p["entityId"]]}
        assert seen <= catalog, sorted(seen - catalog)[:10]


def test_seed_data_uses_the_catalog_names():
    seed = (ROOT / "Apps/Messages/Shared/SeedData.swift").read_text(encoding="utf-8")
    catalog = json.loads((ROOT / "dataset/v1.2/entities/messages.json").read_text(encoding="utf-8"))
    for e in catalog["entities"]:
        if e["type"] == "ContactEntity":
            assert e["forms"][0]["text"] in seed, e["id"]


def test_name_review_reports_no_flags_on_v12():
    text = (ROOT / "docs/name-review.md").read_text(encoding="utf-8")
    assert "Result (v1.2): 81 names reviewed, 0 flagged" in text
    assert "## Renamed before publication" in text and "knowledge" in text
