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
    return scene
