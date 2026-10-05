"""Shared shape masks and settings geometry for image diagnostics."""

from __future__ import annotations

import json

import cv2
import numpy as np


def shape_mask(scene: dict) -> np.ndarray:
    scale = scene["canvas"]["scale"]
    canvas_width = round(scene["canvas"]["logicalWidth"] * scale)
    canvas_height = round(scene["canvas"]["logicalHeight"] * scale)
    shape = scene["shape"]
    x = shape["x"] * scale
    y = shape["y"] * scale
    width = shape["width"] * scale
    height = shape["height"] * scale
    yy, xx = np.mgrid[:canvas_height, :canvas_width].astype(np.float32)
    px = xx + 0.5 - (x + width / 2)
    py = yy + 0.5 - (y + height / 2)
    kind = shape["kind"]
    if kind == "circle":
        return px * px + py * py <= (min(width, height) / 2) ** 2

    radius = min(shape["cornerRadius"] * scale, width / 2, height / 2)
    if kind == "roundedSuperellipse":
        exponent = 4.0
        nx = np.abs(px) / max(width / 2, 1.0)
        ny = np.abs(py) / max(height / 2, 1.0)
        return nx**exponent + ny**exponent <= 1.0

    qx = np.abs(px) - (width / 2 - radius)
    qy = np.abs(py) - (height / 2 - radius)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    return outside + inside <= radius


def region_masks(scene: dict) -> dict[str, np.ndarray]:
    mask = shape_mask(scene)
    distance = cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5)
    outside_distance = cv2.distanceTransform((~mask).astype(np.uint8), cv2.DIST_L2, 5)
    height, width = mask.shape
    yy, xx = np.mgrid[:height, :width]
    shape = scene["shape"]
    scale = scene["canvas"]["scale"]
    cx = (shape["x"] + shape["width"] / 2) * scale
    cy = (shape["y"] + shape["height"] / 2) * scale
    dx = xx - cx
    dy = yy - cy
    vertical = np.abs(dy) >= np.abs(dx)
    return {
        "glass": mask,
        "outerContour0To3px": mask & (distance <= 3),
        "innerBevel3To12px": mask & (distance > 3) & (distance <= 12),
        "faceOver12px": mask & (distance > 12),
        "outside0To3px": ~mask & (outside_distance <= 3),
        "outside3To12px": ~mask & (outside_distance > 3) & (outside_distance <= 12),
        "outside12To36px": ~mask
        & (outside_distance > 12)
        & (outside_distance <= 36),
        "outsideTop0To12px": ~mask
        & (outside_distance <= 12)
        & (dy < 0),
        "outsideBottom0To12px": ~mask
        & (outside_distance <= 12)
        & (dy >= 0),
        "topFacing": mask & vertical & (dy < 0),
        "bottomFacing": mask & vertical & (dy >= 0),
        "leftFacing": mask & ~vertical & (dx < 0),
        "rightFacing": mask & ~vertical & (dx >= 0),
    }


def apply_settings_geometry(scene: dict, settings: dict) -> dict:
    adjusted = json.loads(json.dumps(scene))
    shape = adjusted["shape"]
    center_x = float(shape["x"]) + float(shape["width"]) * 0.5
    center_y = float(shape["y"]) + float(shape["height"]) * 0.5
    width = float(settings.get("shapeWidth", shape["width"]))
    height = float(settings.get("shapeHeight", shape["height"]))
    center_x += float(settings.get("shapeOffsetX", 0.0))
    center_y += float(settings.get("shapeOffsetY", 0.0))
    shape.update(
        {
            "x": center_x - width * 0.5,
            "y": center_y - height * 0.5,
            "width": width,
            "height": height,
        }
    )
    if "cornerRadius" in shape or "cornerRadius" in settings:
        shape["cornerRadius"] = float(
            settings.get("cornerRadius", shape.get("cornerRadius", 0))
        )
    return adjusted
