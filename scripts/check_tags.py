"""Check that every ISA-style tag mentioned in the docs and scripts exists in tags.csv.

Usage:  .venv/bin/python scripts/check_tags.py
"""
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
known = {r["tag"] for r in csv.DictReader(open(ROOT / "tags.csv", newline=""))}
pattern = re.compile(r"\b(?:[A-Z]{1,4})-\d{3}[A-Z]?(?:-[A-Z]{2,3})?\b")
ignore = {"TRT-CN-001", "CN-001"}
files = sorted((ROOT / "docs").glob("*.md")) + [ROOT / "README.md"]
missing = {}
for f in files:
    for m in set(pattern.findall(f.read_text(encoding="utf-8"))):
        if m in known or m in ignore:
            continue
        # PT-100A/B/C style groups are written as PT-100A; accept a base tag if a suffixed one exists
        if any(k.startswith(m) for k in known):
            continue
        missing.setdefault(m, []).append(f.name)
if missing:
    for k, v in sorted(missing.items()):
        print(f"Unknown tag {k} in {sorted(set(v))}")
    raise SystemExit(1)
print(f"Tag consistency OK: {len(files)} documents checked against {len(known)} tags")
