"""Validation helpers for Apple-match scene descriptions."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import jsonschema


def validate_scene(scene_path: Path, schema_path: Path) -> dict[str, Any]:
    """Load and validate a scene, returning the validated JSON object.

    Keeping schema validation in the comparator package means every capture
    and optimizer entry point rejects malformed scene geometry before it can
    contaminate a reference comparison.
    """
    scene = json.loads(scene_path.read_text())
    schema = json.loads(schema_path.read_text())
    jsonschema.validate(scene, schema)
    for probe in scene["probes"]:
        background = probe["background"]
        if background["kind"] != "tileGrid":
            continue
        pattern = background["pattern"]
        widths = {len(row) for row in pattern}
        if len(widths) != 1:
            raise ValueError(
                f"tileGrid probe {probe['id']} pattern rows must have equal width"
            )
        palette = set(background["palette"])
        symbols = set("".join(pattern))
        missing = sorted(symbols - palette)
        if missing:
            raise ValueError(
                f"tileGrid probe {probe['id']} uses undefined palette symbols: "
                f"{missing}"
            )
    return scene
