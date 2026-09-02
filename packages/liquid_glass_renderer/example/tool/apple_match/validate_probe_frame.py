#!/usr/bin/env python3
"""Validate that a screenshot reached the requested deterministic probe."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np


def _rgb(hex_color: str) -> tuple[int, int, int]:
    value = int(hex_color.removeprefix("#"), 16)
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def expected_rgb(scene: dict, probe_id: str, physical_x: int, physical_y: int):
    probe = next(probe for probe in scene["probes"] if probe["id"] == probe_id)
    spec = probe["background"]
    if spec["kind"] == "solid":
        return _rgb(spec["color"])

    scale = scene["canvas"]["scale"]
    x = physical_x / scale
    y = physical_y / scale
    if spec["kind"] == "linearGradient":
        width = float(scene["canvas"]["logicalWidth"])
        height = float(scene["canvas"]["logicalHeight"])
        axis = spec["axis"]
        if axis == "vertical":
            position = y / max(height - 1.0, 1.0)
        elif axis == "diagonal":
            position = (x / max(width - 1.0, 1.0) + y / max(height - 1.0, 1.0)) * 0.5
        else:
            position = x / max(width - 1.0, 1.0)
        position = min(max(position, 0.0), 1.0)
        start = np.array(_rgb(spec["startColor"]), dtype=np.float32)
        end = np.array(_rgb(spec["endColor"]), dtype=np.float32)
        return tuple(np.rint(start + (end - start) * position).astype(np.int16))
    cell = spec["cellSize"]
    column = int(x // cell)
    row = int(y // cell)
    if x % cell >= cell - spec["gutter"] or y % cell >= cell - spec["gutter"]:
        return _rgb(spec["gutterColor"])

    if spec["kind"] == "tileGrid":
        pattern = spec["pattern"]
        pattern_row = pattern[row % len(pattern)]
        return _rgb(spec["palette"][pattern_row[column % len(pattern_row)]])

    marker_row = row - spec["markerRow"]
    marker_column = column - spec["markerColumn"]
    if (
        0 <= marker_row < len(spec["marker"])
        and 0 <= marker_column < len(spec["marker"][marker_row])
    ):
        code = spec["marker"][marker_row][marker_column]
        index = "RGBW".index(code)
    elif spec["layout"] == "primary":
        index = (column + 2 * row + row // 4) % 4
    else:
        index = (3 * column + row + column // 5) % 4
    return _rgb(spec["colors"][index])


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: validate_probe_frame.py SCENE PROBE SCREENSHOT")
    scene = json.loads(Path(sys.argv[1]).read_text())
    probe = sys.argv[2]
    image = cv2.imread(sys.argv[3], cv2.IMREAD_COLOR)
    if image is None:
        raise SystemExit(2)
    # Confirm the deterministic probe at several points. A single corner was
    # insufficient: a launch-transition frame could have the right background
    # while the glass had not appeared yet.
    height, width = image.shape[:2]
    sample_points = (
        (5, 5), (width - 6, 5), (5, height - 24), (width - 6, height - 24)
    )
    for physical_x, physical_y in sample_points:
        expected = expected_rgb(scene, probe, physical_x, physical_y)
        actual_bgr = tuple(int(value) for value in image[physical_y, physical_x])
        actual = tuple(reversed(actual_bgr))
        probe_kind = next(
            item["background"]["kind"]
            for item in scene["probes"]
            if item["id"] == probe
        )
        # SwiftUI's UnitPoint gradient projection is implementation-defined
        # at the corners (the line is not a simple x/y average). A generous
        # bound still rejects a stale/solid frame while allowing that valid
        # projection; exact solid/grid probes retain the strict bound.
        tolerance = 110 if probe_kind == "linearGradient" else 16
        if max(abs(a - b) for a, b in zip(actual, expected)) > tolerance:
            raise SystemExit(1)

    # Confirm that the glass itself is present. Sample the declared shape box
    # against the exact source background and require a non-trivial material
    # residual. This rejects the transient all-background frames that caused
    # the legacy pill/circle references to be ambiguous.
    scale = scene["canvas"]["scale"]
    shape = scene["shape"]
    left = round(shape["x"] * scale)
    top = round(shape["y"] * scale)
    right = round((shape["x"] + shape["width"]) * scale)
    bottom = round((shape["y"] + shape["height"]) * scale)
    residuals = []
    for physical_y in range(top, bottom, scale):
        for physical_x in range(left, right, scale):
            expected = np.array(expected_rgb(scene, probe, physical_x, physical_y))
            actual = image[physical_y, physical_x, ::-1].astype(np.int16)
            residuals.append(int(np.max(np.abs(actual - expected))))
    if not residuals or float(np.percentile(residuals, 95)) < 4.0:
        raise SystemExit(1)
    raise SystemExit(0)


if __name__ == "__main__":
    main()
