#!/usr/bin/env python3
"""Validate the evidence contract for the shipped LiquidGlassSettings fields."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "settings" / "evidence_manifest.json"
SETTINGS_DART = ROOT.parents[2] / "lib" / "src" / "liquid_glass_settings.dart"
EXPECTED_API_EXEMPTIONS = {"visibility"}


def public_fields() -> set[str]:
    source = SETTINGS_DART.read_text()
    return set(re.findall(r"^\s*final\s+[\w<>?]+\s+(\w+);", source, re.MULTILINE))


def load_manifest() -> dict[str, object]:
    return json.loads(MANIFEST.read_text())


def validate(*, strict: bool) -> tuple[list[str], list[str]]:
    manifest = load_manifest()
    entries = manifest["settings"]
    errors: list[str] = []
    notes: list[str] = []
    fields = public_fields()
    if set(entries) != fields:
        errors.append(
            f"manifest fields {sorted(entries)} do not match Dart fields {sorted(fields)}"
        )
    for field, entry in entries.items():
        status = entry.get("status")
        evidence = entry.get("evidence", [])
        if status not in {"qualified", "pending", "rejected", "exempt"}:
            errors.append(f"{field}: invalid status {status!r}")
        if status == "exempt" and field not in EXPECTED_API_EXEMPTIONS:
            errors.append(f"{field}: only documented API utilities may be exempt")
        scenes = {scene for row in evidence for scene in row.get("scenes", [])}
        if status == "qualified" and len(scenes) < 2:
            errors.append(f"{field}: qualified entry needs two distinct scenes")
        if status in {"pending", "rejected"}:
            notes.append(f"{field}: {status}")
    if strict:
        for field, entry in entries.items():
            if entry.get("status") not in {"qualified", "exempt"}:
                errors.append(f"{field}: strict evidence gate is not closed")
    return errors, notes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    errors, notes = validate(strict=args.strict)
    for note in notes:
        print(f"PENDING: {note}")
    for error in errors:
        print(f"ERROR: {error}")
    if not errors:
        print("Evidence manifest structure is valid.")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
