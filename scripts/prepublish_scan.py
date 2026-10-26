#!/usr/bin/env python3
"""Pre-publication scan for SiriReady Bench (standard library only).

  python3.12 scripts/prepublish_scan.py                 # tracked files of this repository
  python3.12 scripts/prepublish_scan.py --dir DIR       # an exported tree (e.g. dist/public)
  python3.12 scripts/prepublish_scan.py --history       # every blob and commit header in git history

Exit status 1 when a blocking finding is present: secrets or private keys, the owner's e-mail address or
home directory in file contents, signing identities, device identifiers in results, or (for --dir) a
developer-instruction file in the export. Non-blocking findings (warnings) are printed but do not fail.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

SECRET_PATTERNS = [
    ("AWS access key", r"\bAKIA[0-9A-Z]{16}\b"),
    ("private key block", r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----"),
    ("GitHub token", r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"),
    ("Anthropic/OpenAI style key", r"\bsk-(?:ant-)?[A-Za-z0-9_-]{24,}\b"),
    ("Slack token", r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"),
    ("Google API key", r"\bAIza[0-9A-Za-z_-]{35}\b"),
    ("generic secret assignment", r"(?i)\b(?:api[_-]?key|secret|passwd|password|token)\s*[:=]\s*['\"][A-Za-z0-9/+_-]{16,}['\"]"),
]
SIGNING_PATTERNS = [
    ("development team id", r"DEVELOPMENT_TEAM\s*=\s*\"?[A-Z0-9]{10}\"?;"),
    ("signing certificate name", r"(?:Apple Development|iPhone Developer|Apple Distribution|iPhone Distribution):\s*\S"),
    ("provisioning profile", r"PROVISIONING_PROFILE(?:_SPECIFIER)?\s*=\s*\"?[^\";]+"),
]
PERSONAL_PATTERNS = [
    ("home directory path", r"/Users/[A-Za-z0-9._-]+/"),
    ("e-mail address", r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
]
UDID = r"\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b"
# Addresses that may legitimately appear: commit-trailer bot address and RFC 2606 example domains.
EMAIL_ALLOW = re.compile(r"(?i)noreply@anthropic\.com$|@(?:[a-z0-9-]+\.)*example(?:\.com|\.org)?$")
DEV_INSTRUCTION_FILES = {"CLAUDE.md", "AGENTS.md", ".cursorrules"}
DEV_INSTRUCTION_DIRS = {".claude"}
SKIP_SUFFIXES = {".parquet", ".png", ".jpg", ".pdf", ".xcresult"}


def scan_text(path, text, findings, results_file=False):
    for label, pat in SECRET_PATTERNS + SIGNING_PATTERNS:
        for m in re.finditer(pat, text):
            findings.append(("BLOCK", path, label, m.group(0)[:60]))
    for label, pat in PERSONAL_PATTERNS:
        for m in re.finditer(pat, text):
            if label == "e-mail address" and EMAIL_ALLOW.search(m.group(0)):
                continue
            findings.append(("BLOCK", path, label, m.group(0)))
    if results_file:
        for m in re.finditer(UDID, text):
            findings.append(("BLOCK", path, "device / simulator UDID in results", m.group(0)))


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [ROOT / p for p in out.decode().split("\0") if p]


def scan_files(files, base, findings, export=False):
    for f in files:
        rel = f.relative_to(base).as_posix()
        parts = set(pathlib.PurePosixPath(rel).parts)
        if f.name in DEV_INSTRUCTION_FILES or parts & DEV_INSTRUCTION_DIRS:
            findings.append(("BLOCK" if export else "WARN", rel, "developer instruction file (exclude from the public export)", f.name))
        if f.suffix in SKIP_SUFFIXES or not f.is_file():
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        scan_text(rel, text, findings, results_file=rel.startswith("results/"))


def scan_history(findings):
    authors = subprocess.run(["git", "log", "--all", "--format=%an <%ae>|%cn <%ce>"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    idents = sorted({i for line in authors.splitlines() for i in line.split("|")})
    for ident in idents:
        findings.append(("WARN", "git history", "commit author/committer identity (published with the history)", ident))
    blobs = subprocess.run(["git", "rev-list", "--objects", "--all"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    seen = set()
    for line in blobs.splitlines():
        sha, _, path = line.partition(" ")
        if not path or sha in seen or pathlib.PurePosixPath(path).suffix in SKIP_SUFFIXES:
            continue
        seen.add(sha)
        kind = subprocess.run(["git", "cat-file", "-t", sha], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        if kind != "blob":
            continue
        data = subprocess.run(["git", "cat-file", "-p", sha], cwd=ROOT, capture_output=True).stdout
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        local = []
        scan_text(f"history:{path}@{sha[:8]}", text, local, results_file=path.startswith("results/"))
        findings.extend(local)
        if pathlib.PurePosixPath(path).name in DEV_INSTRUCTION_FILES:
            findings.append(("WARN", f"history:{path}", "developer instruction file exists in history", sha[:8]))
    messages = subprocess.run(["git", "log", "--all", "--format=%B"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    scan_text("git commit messages", messages, findings)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", help="scan an exported tree instead of the tracked files")
    ap.add_argument("--history", action="store_true", help="scan git history (blobs, identities, messages)")
    args = ap.parse_args(argv)
    findings = []
    if args.history:
        scan_history(findings)
    elif args.dir:
        base = pathlib.Path(args.dir).resolve()
        scan_files(sorted(p for p in base.rglob("*") if p.is_file() or p.name in DEV_INSTRUCTION_DIRS), base, findings, export=True)
    else:
        scan_files(tracked_files(), ROOT, findings)
    blocking = [f for f in findings if f[0] == "BLOCK"]
    seen = set()
    for level, where, label, sample in findings:
        key = (level, where, label, sample)
        if key in seen:
            continue
        seen.add(key)
        print(f"{level:5} {where}: {label}: {sample}")
    scope = "git history" if args.history else (args.dir or "tracked files")
    print(f"prepublish_scan ({scope}): {len(blocking)} blocking, {len(findings) - len(blocking)} warning(s)")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
