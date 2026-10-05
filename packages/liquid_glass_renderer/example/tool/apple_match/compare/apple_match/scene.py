"""Shared scene loading and metric-family contracts."""

from __future__ import annotations

from pathlib import Path

from .schema import validate_scene


SCHEMA_PATH = Path(__file__).resolve().parents[2] / "scenes" / "schema.json"
SCORECARD_PROBES = frozenset("ABCD")


def load_scene(path: Path) -> dict:
    return validate_scene(Path(path), SCHEMA_PATH)


def probe_ids(scene: dict) -> tuple[str, ...]:
    return tuple(probe["id"] for probe in scene["probes"])


def scene_crop(scene: dict, margin: float = 30) -> tuple[int, int, int, int]:
    scale = scene["canvas"]["scale"]
    shapes = [scene["shape"]]
    if "mergeShape" in scene:
        shapes.append(scene["mergeShape"])
    left = min(shape["x"] for shape in shapes)
    top = min(shape["y"] for shape in shapes)
    right = max(shape["x"] + shape["width"] for shape in shapes)
    bottom = max(shape["y"] + shape["height"] for shape in shapes)
    return (
        round((left - margin) * scale),
        round((top - margin) * scale),
        round((right - left + 2 * margin) * scale),
        round((bottom - top + 2 * margin) * scale),
    )


def metric_family(scene: dict) -> str:
    probes = probe_ids(scene)
    if frozenset(probes) == SCORECARD_PROBES:
        return "scorecard"
    roles = scene.get("roles", {})
    if (
        "palette" in roles
        or "sameHue" in roles
        or "complement" in roles
    ):
        return "solidColor"
    raise ValueError(
        f"Unknown metric family for scene {scene.get('id', '<unknown>')!r} "
        f"with probes {list(probes)}"
    )
