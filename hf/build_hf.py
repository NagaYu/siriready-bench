#!/usr/bin/env python3
"""Assemble the Hugging Face dataset package in hf/ (nothing is uploaded).

Only the **dev** split of dataset v1.2 (messages app) is packaged. The eval split (calendar app,
paraphrase families C/D) is withheld so it can serve as an uncontaminated held-out set.

  python3 hf/build_hf.py            # (re)build hf/data and hf/MANIFEST.json
  python3 hf/build_hf.py --check    # verify the package matches the dataset (CI)

Needs pyarrow for the Parquet mirror (packaging only; the dataset tools themselves are stdlib).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
import tempfile

import pyarrow as pa
import pyarrow.parquet as pq

ROOT = pathlib.Path(__file__).resolve().parents[1]
HF = ROOT / "hf"
SOURCE = ROOT / "dataset" / "v1.2"
DATASET_VERSION = "v1.2"

SCHEMA = pa.schema([
    ("case_id", pa.string()), ("split", pa.string()), ("app_id", pa.string()), ("domain", pa.string()),
    ("locale", pa.string()), ("utterance", pa.string()), ("noise", pa.string()), ("adversarial", pa.bool_()),
    ("difficulty", pa.string()), ("tags", pa.list_(pa.string())), ("mention", pa.string()), ("generator", pa.string()),
    ("state_json", pa.string()), ("expected_intent", pa.string()), ("expected_entity_id", pa.string()),
    ("expected_resolution", pa.string()), ("expected_candidates", pa.list_(pa.string())), ("expected_params_json", pa.string()),
])


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows(cases):
    for c in cases:
        e = c["expected"]
        yield {"case_id": c["case_id"], "split": c["split"], "app_id": c["app_id"], "domain": c["domain"], "locale": c["locale"],
               "utterance": c["utterance"], "noise": c["noise"], "adversarial": c["adversarial"], "difficulty": c["difficulty"],
               "tags": c["tags"], "mention": c.get("mention"), "generator": c.get("generator"),
               "state_json": json.dumps(c["state"], ensure_ascii=False, sort_keys=True),
               "expected_intent": e["intent"], "expected_entity_id": e["entity_id"], "expected_resolution": e["resolution"],
               "expected_candidates": e["candidates"], "expected_params_json": json.dumps(e["params"], ensure_ascii=False, sort_keys=True)}


def build(out):
    data = out / "data"
    data.mkdir(parents=True, exist_ok=True)
    dev_text = (SOURCE / "cases_dev.jsonl").read_text(encoding="utf-8")
    cases = [json.loads(line) for line in dev_text.splitlines() if line.strip()]
    if {c["split"] for c in cases} != {"dev"}:
        raise SystemExit("refusing to package: non-dev cases found")
    (data / "dev.jsonl").write_text(dev_text, encoding="utf-8")
    table = pa.Table.from_pylist(list(rows(cases)), schema=SCHEMA)
    pq.write_table(table, data / "dev.parquet", compression="zstd", use_dictionary=False, write_statistics=False)
    catalog = json.loads((SOURCE / "entities" / "messages.json").read_text(encoding="utf-8"))
    (data / "entities_messages.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    locales = {}
    for c in cases:
        locales[c["locale"]] = locales.get(c["locale"], 0) + 1
    manifest = {
        "dataset": "SiriReady Bench utterances", "version": DATASET_VERSION, "split": "dev", "app": "messages (synthetic \"Relay\")",
        "withheld": "eval split (calendar app, paraphrase families C/D) is not published",
        "rows": len(cases), "locales": dict(sorted(locales.items())),
        "adversarial": sum(c["adversarial"] for c in cases), "catalog_entities": len(catalog["entities"]),
        "files": {name: {"sha256": sha256(data / name), "bytes": (data / name).stat().st_size}
                  for name in ("dev.jsonl", "dev.parquet", "entities_messages.json")},
        "source": {"cases": "dataset/v1.2/cases_dev.jsonl", "sha256": sha256(SOURCE / "cases_dev.jsonl")},
        "parquet_writer": f"pyarrow {pa.__version__}",
    }
    (out / "MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def check():
    manifest = json.loads((HF / "MANIFEST.json").read_text(encoding="utf-8"))
    problems = []
    for name, meta in manifest["files"].items():
        if sha256(HF / "data" / name) != meta["sha256"]:
            problems.append(f"checksum mismatch: hf/data/{name}")
    if manifest["source"]["sha256"] != sha256(SOURCE / "cases_dev.jsonl"):
        problems.append("hf package is stale: dataset/v1.2/cases_dev.jsonl changed")
    cases = [json.loads(l) for l in (HF / "data" / "dev.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    table = pq.read_table(HF / "data" / "dev.parquet")
    if len(cases) != manifest["rows"] or table.num_rows != manifest["rows"]:
        problems.append(f"row counts differ: jsonl {len(cases)}, parquet {table.num_rows}, manifest {manifest['rows']}")
    if table.to_pylist() != list(rows(cases)):
        problems.append("parquet rows differ from dev.jsonl")
    if any(c["split"] != "dev" for c in cases) or any(c["app_id"] != "messages" for c in cases):
        problems.append("package contains non-dev or non-messages cases")
    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = build(pathlib.Path(tmp))
        for name in ("dev.jsonl", "entities_messages.json"):
            if rebuilt["files"][name]["sha256"] != manifest["files"][name]["sha256"]:
                problems.append(f"rebuild differs: {name}")
        if rebuilt["parquet_writer"] == manifest["parquet_writer"] and rebuilt["files"]["dev.parquet"]["sha256"] != manifest["files"]["dev.parquet"]["sha256"]:
            problems.append("rebuild differs: dev.parquet (same pyarrow version)")
    for p in problems:
        print(f"FAIL {p}", file=sys.stderr)
    print(f"hf package: {manifest['rows']} rows, {len(manifest['files'])} files, {'OK' if not problems else 'FAILED'}")
    return 1 if problems else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    if args.check:
        return check()
    m = build(HF)
    print(f"built hf/: {m['rows']} rows ({m['locales']}), files {list(m['files'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
