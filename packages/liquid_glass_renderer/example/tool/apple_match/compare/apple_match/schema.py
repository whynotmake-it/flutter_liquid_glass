"""Scene validation with cross-field constraints."""

from __future__ import annotations

import json
from pathlib import Path

import jsonschema


def validate_scene(path: Path, schema_path: Path) -> dict:
    scene = json.loads(path.read_text())
    schema = json.loads(schema_path.read_text())
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.validate(scene, schema)
    probes = [probe["id"] for probe in scene["probes"]]
    if probes != ["A", "B", "C", "D"]:
        raise jsonschema.ValidationError("probes must be ordered exactly A, B, C, D")
    shape = scene["shape"]
    canvas = scene["canvas"]
    if shape["x"] + shape["width"] > canvas["logicalWidth"]:
        raise jsonschema.ValidationError("shape exceeds canvas width")
    if shape["y"] + shape["height"] > canvas["logicalHeight"]:
        raise jsonschema.ValidationError("shape exceeds canvas height")
    if shape["cornerRadius"] > shape["height"] / 2:
        raise jsonschema.ValidationError("corner radius exceeds capsule radius")
    return scene
