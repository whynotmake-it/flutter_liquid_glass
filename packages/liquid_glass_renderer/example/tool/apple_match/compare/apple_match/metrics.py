"""Deterministic, decomposed image metrics for Apple glass matching."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Tuple

import cv2
import numpy as np


WEIGHTS = {
    "shape": 0.25,
    "combined": 0.15,
    "flow": 0.15,
    "sharpness": 0.10,
    "channel": 0.15,
    "specular": 0.10,
    "holdout": 0.10,
}


@dataclass(frozen=True)
class MetricResult:
    errors: Dict[str, float]
    score: float
    shift: Tuple[float, float]
    details: Dict[str, object]


def read_rgb(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"Could not read image: {path}")
    return cv2.cvtColor(image, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0


def verify_background_registration(
    reference: np.ndarray,
    candidate: np.ndarray,
    excluded_rect: Tuple[int, int, int, int],
) -> Dict[str, object]:
    """Fail when control pixels outside the glass disagree."""
    if reference.shape != candidate.shape:
        raise ValueError(
            f"Capture dimensions disagree: {reference.shape} != {candidate.shape}"
        )
    mask = np.ones(reference.shape[:2], dtype=np.float32)
    x, y, width, height = excluded_rect
    mask[y : y + height, x : x + width] = 0
    ref_gray = luminance(reference) * mask
    can_gray = luminance(candidate) * mask
    shift, response = cv2.phaseCorrelate(ref_gray, can_gray)
    residual = np.abs(reference - candidate)[mask > 0]
    channel_mean = np.mean(residual, axis=0)
    percentile_99 = float(np.percentile(residual, 99))
    maximum = float(np.max(residual))
    mismatched_fraction = float(np.mean(np.max(residual, axis=1) > 2.0 / 255.0))
    details = {
        "shiftPixels": {"x": float(shift[0]), "y": float(shift[1])},
        "phaseCorrelationResponse": float(response),
        "outsideMeanAbsoluteError": {
            "red": float(channel_mean[0]),
            "green": float(channel_mean[1]),
            "blue": float(channel_mean[2]),
        },
        "outsideResidualP99": percentile_99,
        "outsideResidualMaximum": maximum,
        "outsideMismatchedPixelFraction": mismatched_fraction,
        "passed": bool(
            abs(shift[0]) <= 0.51
            and abs(shift[1]) <= 0.51
            and maximum <= 2.0 / 255.0
        ),
    }
    if not details["passed"]:
        raise ValueError(f"RGBW background registration failed: {details}")
    return details


def luminance(image: np.ndarray) -> np.ndarray:
    return image[..., 0] * 0.2126 + image[..., 1] * 0.7152 + image[..., 2] * 0.0722


def transmission_boundary_profile(
    black: np.ndarray,
    white: np.ndarray,
    *,
    threshold: float = 0.75,
) -> Dict[str, np.ndarray]:
    """Subpixel top boundary and curvature from white-minus-black transfer.

    The transfer image largely cancels tint and specular lighting. Its outer
    field is one and its glass interior is lower, so a fixed isocontour gives a
    substantially cleaner geometry signal than thresholding either lit probe.
    """
    transfer = luminance(white - black)
    height, width = transfer.shape
    boundary = np.full(width, np.nan, dtype=np.float32)
    for x in range(width):
        column = transfer[:, x]
        below = np.flatnonzero(column < threshold)
        if below.size == 0:
            continue
        y1 = int(below[0])
        if y1 == 0:
            boundary[x] = 0.0
            continue
        y0 = y1 - 1
        v0 = float(column[y0])
        v1 = float(column[y1])
        fraction = (v0 - threshold) / max(v0 - v1, 1e-6)
        boundary[x] = y0 + np.clip(fraction, 0.0, 1.0)

    valid = np.isfinite(boundary)
    if np.count_nonzero(valid) < width * 0.25:
        return {
            "x": np.empty(0, dtype=np.float32),
            "boundary": np.empty(0, dtype=np.float32),
            "smoothBoundary": np.empty(0, dtype=np.float32),
            "slope": np.empty(0, dtype=np.float32),
            "curvature": np.empty(0, dtype=np.float32),
        }
    xs = np.flatnonzero(valid).astype(np.float32)
    ys = boundary[valid]
    smooth = cv2.GaussianBlur(ys[:, None], (1, 9), 0)[:, 0]
    slope = np.gradient(smooth, xs)
    curvature = np.gradient(slope, xs) / np.power(1.0 + slope * slope, 1.5)
    return {
        "x": xs,
        "boundary": ys,
        "smoothBoundary": smooth,
        "slope": slope,
        "curvature": curvature,
    }


def boundary_profile_error(
    reference: Dict[str, np.ndarray],
    candidate: Dict[str, np.ndarray],
) -> Dict[str, float]:
    ref = transmission_boundary_profile(reference["C"], reference["D"])
    can = transmission_boundary_profile(candidate["C"], candidate["D"])
    # A deliberately extreme material mismatch can remove the fixed
    # transmission isocontour entirely. That is a valid poor candidate, not a
    # malformed capture; keep the scorecard total and report a finite failure
    # metric instead of aborting the comparison.
    if ref["x"].size == 0 or can["x"].size == 0:
        width = float(reference["C"].shape[1])
        return {
            "positionMeanAbsoluteErrorPixels": width,
            "positionMaximumAbsoluteErrorPixels": width,
            "tangentMeanAbsoluteErrorRadians": float(np.pi / 2.0),
            "curvatureMeanAbsoluteErrorPerPixel": 1.0,
            "curvatureP99AbsoluteErrorPerPixel": 1.0,
        }
    common = np.intersect1d(ref["x"], can["x"])
    ref_indices = np.searchsorted(ref["x"], common)
    can_indices = np.searchsorted(can["x"], common)
    boundary_delta = can["smoothBoundary"][can_indices] - ref["smoothBoundary"][ref_indices]
    tangent_delta = (
        np.arctan(can["slope"][can_indices])
        - np.arctan(ref["slope"][ref_indices])
    )
    curvature_delta = can["curvature"][can_indices] - ref["curvature"][ref_indices]
    return {
        "positionMeanAbsoluteErrorPixels": float(np.mean(np.abs(boundary_delta))),
        "positionMaximumAbsoluteErrorPixels": float(np.max(np.abs(boundary_delta))),
        "tangentMeanAbsoluteErrorRadians": float(
            np.mean(np.abs(tangent_delta))
        ),
        "curvatureMeanAbsoluteErrorPerPixel": float(
            np.mean(np.abs(curvature_delta))
        ),
        "curvatureP99AbsoluteErrorPerPixel": float(
            np.percentile(np.abs(curvature_delta), 99)
        ),
    }


def fixed_blur_mix(
    image: np.ndarray,
    *,
    sigma: float,
    mix: float,
) -> np.ndarray:
    """Reference model for fixed-sigma blur mixed over the sharp input."""
    blurred = cv2.GaussianBlur(image, (0, 0), sigma)
    amount = float(np.clip(mix, 0.0, 1.0))
    return image * (1.0 - amount) + blurred * amount


def align(reference: np.ndarray, candidate: np.ndarray) -> Tuple[np.ndarray, Tuple[float, float]]:
    """Translation-align candidate to reference, retaining reference dimensions."""
    if reference.shape != candidate.shape:
        candidate = cv2.resize(
            candidate, (reference.shape[1], reference.shape[0]), interpolation=cv2.INTER_AREA
        )
    shift, _ = cv2.phaseCorrelate(luminance(reference), luminance(candidate))
    matrix = np.float32([[1, 0, shift[0]], [0, 1, shift[1]]])
    aligned = cv2.warpAffine(
        candidate,
        matrix,
        (reference.shape[1], reference.shape[0]),
        flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP,
        borderMode=cv2.BORDER_REFLECT,
    )
    return aligned, (float(shift[0]), float(shift[1]))


def _gradient(image: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    gray = luminance(image)
    gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    return gx, gy, cv2.magnitude(gx, gy)


def radial_field(image_a: np.ndarray, image_b: np.ndarray) -> np.ndarray:
    """Signed radial gradient field of A-B, preserving convex/lip direction."""
    delta = image_a - image_b
    gx, gy, _ = _gradient(delta)
    height, width = gx.shape
    yy, xx = np.mgrid[:height, :width].astype(np.float32)
    dx = xx - (width - 1) / 2
    dy = yy - (height - 1) / 2
    norm = np.maximum(np.sqrt(dx * dx + dy * dy), 1.0)
    return (gx * dx + gy * dy) / norm


def signed_optical_flow(
    reference_a: np.ndarray,
    reference_b: np.ndarray,
    candidate_a: np.ndarray,
    candidate_b: np.ndarray,
) -> np.ndarray:
    """Dense radial flow mapping the reference A-B field to the candidate."""
    if np.array_equal(reference_a, candidate_a) and np.array_equal(
        reference_b, candidate_b
    ):
        return np.zeros(reference_a.shape[:2], dtype=np.float32)
    reference_delta = luminance(reference_a - reference_b)
    candidate_delta = luminance(candidate_a - candidate_b)
    def normalize(image: np.ndarray) -> np.ndarray:
        minimum = float(image.min())
        scale = max(float(image.max()) - minimum, 1e-6)
        return np.clip((image - minimum) / scale * 255, 0, 255).astype(np.uint8)

    reference_u8 = normalize(reference_delta)
    candidate_u8 = normalize(candidate_delta)
    flow = cv2.calcOpticalFlowFarneback(
        reference_u8,
        candidate_u8,
        None,
        0.5,
        4,
        21,
        5,
        7,
        1.5,
        0,
    )
    height, width = reference_delta.shape
    yy, xx = np.mgrid[:height, :width].astype(np.float32)
    dx = xx - (width - 1) / 2
    dy = yy - (height - 1) / 2
    norm = np.maximum(np.sqrt(dx * dx + dy * dy), 1.0)
    return (flow[..., 0] * dx + flow[..., 1] * dy) / norm


def silhouette(image: np.ndarray, *, threshold: float = 0.02) -> np.ndarray:
    """Extract glass silhouette from the black solid probe."""
    mask = (luminance(image) > threshold).astype(np.uint8)
    kernel = np.ones((5, 5), np.uint8)
    return cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)


def _mask_measurements(mask: np.ndarray, core_mask: np.ndarray) -> Dict[str, float]:
    ys, xs = np.where(mask > 0)
    if not len(xs):
        return {
            "x": 0.0,
            "y": 0.0,
            "width": 0.0,
            "height": 0.0,
            "cornerRadius": 0.0,
            "bezelWidth": 0.0,
        }
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    middle_row = mask[(y0 + y1) // 2]
    top_band = mask[y0 : min(y0 + max((y1 - y0) // 10, 2), y1)]
    middle_x = np.where(middle_row > 0)[0]
    top_x = np.where(np.any(top_band > 0, axis=0))[0]
    corner_radius = float(max((top_x.min() - middle_x.min()) if len(top_x) and len(middle_x) else 0, 0))
    distance = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    core_edge = cv2.morphologyEx(core_mask, cv2.MORPH_GRADIENT, np.ones((3, 3), np.uint8)) > 0
    bezel = float(np.median(distance[core_edge])) if np.any(core_edge) else 0.0
    return {
        "x": float(x0),
        "y": float(y0),
        "width": float(x1 - x0),
        "height": float(y1 - y0),
        "cornerRadius": corner_radius,
        "bezelWidth": bezel,
    }


def shape_comparison(
    reference_black: np.ndarray, candidate_black: np.ndarray
) -> Tuple[float, Dict[str, object], np.ndarray, np.ndarray]:
    ref_mask = silhouette(reference_black)
    can_mask = silhouette(candidate_black)
    if not np.any(ref_mask) or not np.any(can_mask):
        details = {
            "iou": 0.0,
            "meanEdgeDistancePixels": float("inf"),
            "sizeError": 1.0,
            "cornerRadiusError": 1.0,
            "bezelWidthError": 1.0,
            "reference": _mask_measurements(ref_mask, ref_mask),
            "candidate": _mask_measurements(can_mask, can_mask),
        }
        return 1.0, details, ref_mask, can_mask
    intersection = float(np.logical_and(ref_mask, can_mask).sum())
    union = float(np.logical_or(ref_mask, can_mask).sum())
    iou = intersection / max(union, 1.0)
    ref_edge = cv2.morphologyEx(ref_mask, cv2.MORPH_GRADIENT, np.ones((3, 3), np.uint8))
    can_edge = cv2.morphologyEx(can_mask, cv2.MORPH_GRADIENT, np.ones((3, 3), np.uint8))
    ref_distance = cv2.distanceTransform(1 - ref_edge, cv2.DIST_L2, 5)
    can_distance = cv2.distanceTransform(1 - can_edge, cv2.DIST_L2, 5)
    edge_distance = 0.5 * (
        float(np.mean(ref_distance[can_edge > 0]))
        + float(np.mean(can_distance[ref_edge > 0]))
    )
    ref_measurements = _mask_measurements(
        ref_mask, silhouette(reference_black, threshold=0.20)
    )
    can_measurements = _mask_measurements(
        can_mask, silhouette(candidate_black, threshold=0.20)
    )
    size_error = (
        abs(ref_measurements["width"] - can_measurements["width"])
        + abs(ref_measurements["height"] - can_measurements["height"])
    ) / max(ref_measurements["width"] + ref_measurements["height"], 1.0)
    corner_error = abs(
        ref_measurements["cornerRadius"] - can_measurements["cornerRadius"]
    ) / max(ref_measurements["height"], 1.0)
    bezel_error = abs(
        ref_measurements["bezelWidth"] - can_measurements["bezelWidth"]
    ) / max(ref_measurements["height"], 1.0)
    shape_error = (
        0.45 * (1.0 - iou)
        + 0.25 * min(edge_distance / 8.0, 1.0)
        + 0.15 * min(size_error, 1.0)
        + 0.10 * min(corner_error, 1.0)
        + 0.05 * min(bezel_error, 1.0)
    )
    details = {
        "iou": iou,
        "meanEdgeDistancePixels": edge_distance,
        "sizeError": size_error,
        "cornerRadiusError": corner_error,
        "bezelWidthError": bezel_error,
        "reference": ref_measurements,
        "candidate": can_measurements,
    }
    return shape_error, details, ref_mask, can_mask


def component_errors(
    reference: Dict[str, np.ndarray], candidate: Dict[str, np.ndarray]
) -> Tuple[Dict[str, float], Dict[str, object]]:
    eps = 1e-6
    ref_a = reference["A"]
    can_a = candidate["A"]
    mask = silhouette(reference["C"]).astype(bool)
    combined = float(np.mean(np.abs(ref_a[mask] - can_a[mask])))
    holdout = float(
        np.mean(np.abs(reference["B"][mask] - candidate["B"][mask]))
    )

    # A/B are the paired primary/holdout RGBW fields.  Comparing A against a
    # zero image makes every foreground glyph and material response look like
    # optical flow; subtract the paired field first so the metric measures the
    # displacement of the shared backdrop instead.
    optical_flow = signed_optical_flow(
        reference["A"],
        reference["B"],
        candidate["A"],
        candidate["B"],
    )
    flow = float(np.mean(np.abs(optical_flow[mask])) / 4.0)

    _, _, ref_gradient = _gradient(reference["A"])
    _, _, can_gradient = _gradient(candidate["A"])
    ref_edge = float(np.mean(ref_gradient[mask]))
    can_edge = float(np.mean(can_gradient[mask]))
    sharpness = float(abs(ref_edge - can_edge) / (ref_edge + eps))

    ref_c = luminance(reference["C"])
    can_c = luminance(candidate["C"])
    black_specular = float(np.mean(np.abs(ref_c[mask] - can_c[mask])))
    eroded = cv2.erode(mask.astype(np.uint8), np.ones((15, 15), np.uint8)) > 0
    rim_band = np.logical_and(mask, np.logical_not(eroded))
    rgbw_rim = float(np.mean(np.abs(ref_a[rim_band] - can_a[rim_band])))
    specular = 0.65 * black_specular + 0.35 * rgbw_rim

    channel_residuals = np.mean(np.abs(ref_a[mask] - can_a[mask]), axis=0)
    mean_response_error = float(
        np.mean(
            np.abs(
                np.mean(ref_a[mask], axis=0)
                - np.mean(can_a[mask], axis=0)
            )
        )
    )
    contrast_response_error = float(
        np.mean(
            np.abs(
                np.std(ref_a[mask], axis=0)
                - np.std(can_a[mask], axis=0)
            )
        )
    )
    ref_saturation = np.max(ref_a[mask], axis=1) - np.min(ref_a[mask], axis=1)
    can_saturation = np.max(can_a[mask], axis=1) - np.min(can_a[mask], axis=1)
    saturation_response_error = float(
        abs(np.mean(ref_saturation) - np.mean(can_saturation))
    )
    ref_d = reference["D"]
    can_d = candidate["D"]
    ref_chroma = ref_d - np.mean(ref_d, axis=2, keepdims=True)
    can_chroma = can_d - np.mean(can_d, axis=2, keepdims=True)
    white_balance = float(
        np.mean(np.abs(ref_chroma[mask] - can_chroma[mask]))
    )
    black_response_error = float(
        abs(np.mean(ref_c[mask]) - np.mean(can_c[mask]))
    )
    white_response_error = float(
        abs(
            np.mean(luminance(ref_d)[mask])
            - np.mean(luminance(can_d)[mask])
        )
    )
    channel = float(
        0.45 * np.mean(channel_residuals)
        + 0.15 * mean_response_error
        + 0.15 * contrast_response_error
        + 0.15 * saturation_response_error
        + 0.10 * white_balance
    )
    shape, shape_details, _, _ = shape_comparison(reference["C"], candidate["C"])
    errors = {
        "shape": shape,
        "combined": combined,
        "flow": flow,
        "sharpness": sharpness,
        "channel": channel,
        "specular": specular,
        "holdout": holdout,
    }
    details = {
        "shape": shape_details,
        "channelResiduals": {
            "red": float(channel_residuals[0]),
            "green": float(channel_residuals[1]),
            "blue": float(channel_residuals[2]),
        },
        "neutralWhiteBalanceError": white_balance,
        "meanResponseError": mean_response_error,
        "contrastResponseError": contrast_response_error,
        "saturationResponseError": saturation_response_error,
        "blackResponseError": black_response_error,
        "whiteResponseError": white_response_error,
        "blackSpecularError": black_specular,
        "rgbwRimError": rgbw_rim,
        "highlightColorResiduals": {
            "red": float(
                np.mean(
                    np.abs(
                        reference["C"][..., 0][mask]
                        - candidate["C"][..., 0][mask]
                    )
                )
            ),
            "green": float(
                np.mean(
                    np.abs(
                        reference["C"][..., 1][mask]
                        - candidate["C"][..., 1][mask]
                    )
                )
            ),
            "blue": float(
                np.mean(
                    np.abs(
                        reference["C"][..., 2][mask]
                        - candidate["C"][..., 2][mask]
                    )
                )
            ),
        },
        "pixelResiduals": pixel_residuals(reference, candidate, mask),
    }
    return errors, details


def _residual_statistics(residual: np.ndarray) -> Dict[str, object]:
    """Absolute RGB residuals in normalized linear capture values.

    These statistics deliberately do not participate in the historical weighted
    score. They are the hard fidelity gate: an exact match is all zeroes, while
    percentiles expose whether a low mean is hiding a bad rim or highlight.
    """
    if residual.size == 0:
        return {
            "meanAbsoluteError": 0.0,
            "rootMeanSquareError": 0.0,
            "p95AbsoluteError": 0.0,
            "p99AbsoluteError": 0.0,
            "maximumAbsoluteError": 0.0,
            "meanAbsoluteError8Bit": 0.0,
            "p99AbsoluteError8Bit": 0.0,
            "mismatchedPixelFraction1Of255": 0.0,
            "mismatchedPixelFraction2Of255": 0.0,
            "meanSignedLuminanceError8Bit": 0.0,
            "brighterPixelFraction": 0.0,
            "darkerPixelFraction": 0.0,
            "meanBrighterLuminanceError8Bit": 0.0,
            "meanDarkerLuminanceError8Bit": 0.0,
        }
    per_channel = np.abs(residual).reshape(-1, 3)
    per_pixel = np.max(per_channel, axis=1)
    signed_luminance = luminance(residual)
    brighter = signed_luminance[signed_luminance > 0.0]
    darker = signed_luminance[signed_luminance < 0.0]
    mae = float(np.mean(per_channel))
    p99 = float(np.percentile(per_channel, 99))
    return {
        "meanAbsoluteError": mae,
        "rootMeanSquareError": float(np.sqrt(np.mean(np.square(per_channel)))),
        "p95AbsoluteError": float(np.percentile(per_channel, 95)),
        "p99AbsoluteError": p99,
        "maximumAbsoluteError": float(np.max(per_channel)),
        "meanAbsoluteError8Bit": mae * 255.0,
        "p99AbsoluteError8Bit": p99 * 255.0,
        "mismatchedPixelFraction1Of255": float(np.mean(per_pixel > 1.0 / 255.0)),
        "mismatchedPixelFraction2Of255": float(np.mean(per_pixel > 2.0 / 255.0)),
        # Positive means Flutter is brighter than Apple. Keeping the sign is
        # essential for lighting work: equal absolute errors can otherwise
        # hide an inverted highlight or shadow.
        "meanSignedLuminanceError8Bit": float(np.mean(signed_luminance) * 255.0),
        "brighterPixelFraction": float(np.mean(signed_luminance > 0.0)),
        "darkerPixelFraction": float(np.mean(signed_luminance < 0.0)),
        "meanBrighterLuminanceError8Bit": (
            float(np.mean(brighter) * 255.0) if brighter.size else 0.0
        ),
        "meanDarkerLuminanceError8Bit": (
            float(np.mean(darker) * 255.0) if darker.size else 0.0
        ),
    }


def pixel_residuals(
    reference: Dict[str, np.ndarray],
    candidate: Dict[str, np.ndarray],
    glass_mask: np.ndarray,
) -> Dict[str, object]:
    """Report direct residuals for every probe and glass sub-region."""
    mask_u8 = glass_mask.astype(np.uint8)
    core_mask = cv2.erode(mask_u8, np.ones((15, 15), np.uint8)) > 0
    rim_mask = np.logical_and(glass_mask, np.logical_not(core_mask))
    inward_distance = cv2.distanceTransform(mask_u8, cv2.DIST_L2, 5)
    outward_distance = cv2.distanceTransform(1 - mask_u8, cv2.DIST_L2, 5)
    silhouette_line_mask = np.logical_and(
        glass_mask,
        inward_distance <= 2.0,
    )
    exterior_contour_mask = np.logical_and(
        np.logical_not(glass_mask),
        outward_distance <= 2.0,
    )
    inner_rim_mask = np.logical_and(
        inward_distance > 2.0,
        inward_distance <= 5.0,
    )
    outer_contour_mask = np.logical_and(
        cv2.dilate(mask_u8, np.ones((5, 5), np.uint8)) > 0,
        cv2.erode(mask_u8, np.ones((5, 5), np.uint8)) == 0,
    )
    inner_bevel_mask = np.logical_and(
        inward_distance > 5.0,
        inward_distance <= 12.0,
    )
    inner_mask = cv2.erode(mask_u8, np.ones((7, 7), np.uint8)) > 0
    ys, xs = np.where(glass_mask)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    lip_depth = max(int(round((y1 - y0) * 0.20)), 1)
    rows = np.arange(glass_mask.shape[0])[:, None]
    columns = np.arange(glass_mask.shape[1])[None, :]
    center_y = (y0 + y1) / 2.0
    center_x = (x0 + x1) / 2.0
    top_half = rows < center_y
    bottom_half = rows >= center_y
    left_half = columns < center_x
    right_half = columns >= center_x
    # Classify each interior pixel by its nearest-facing side. Unlike a simple
    # top/bottom half split, the distance-field gradient keeps the curved
    # corners with the surface normal they actually belong to.
    distance_dx = cv2.Sobel(inward_distance, cv2.CV_32F, 1, 0, ksize=3)
    distance_dy = cv2.Sobel(inward_distance, cv2.CV_32F, 0, 1, ksize=3)
    vertical_facing = np.abs(distance_dy) >= np.abs(distance_dx)
    facing_masks = {
        "top": np.logical_and(vertical_facing, distance_dy >= 0.0),
        "bottom": np.logical_and(vertical_facing, distance_dy < 0.0),
        "left": np.logical_and(np.logical_not(vertical_facing), distance_dx >= 0.0),
        "right": np.logical_and(np.logical_not(vertical_facing), distance_dx < 0.0),
    }
    distance_bands = {
        "contour0To1": np.logical_and(glass_mask, inward_distance <= 1.0),
        "contour1To2": np.logical_and(inward_distance > 1.0, inward_distance <= 2.0),
        "bevel2To4": np.logical_and(inward_distance > 2.0, inward_distance <= 4.0),
        "bevel4To8": np.logical_and(inward_distance > 4.0, inward_distance <= 8.0),
        "bevel8To16": np.logical_and(inward_distance > 8.0, inward_distance <= 16.0),
        "bevel16To32": np.logical_and(inward_distance > 16.0, inward_distance <= 32.0),
    }
    exterior_bands = {
        "exterior0To1": np.logical_and(
            np.logical_not(glass_mask), outward_distance <= 1.0
        ),
        "exterior1To2": np.logical_and(
            outward_distance > 1.0, outward_distance <= 2.0
        ),
        "exterior2To4": np.logical_and(
            outward_distance > 2.0, outward_distance <= 4.0
        ),
        "exterior4To8": np.logical_and(
            outward_distance > 4.0, outward_distance <= 8.0
        ),
        # The cast-shadow fit is intentionally separated from the immediate
        # contour.  Pixels in this annulus are outside the silhouette, at
        # least two pixels away from the edge and no more than twenty pixels
        # away, so a broad BoxShadow can be evaluated without rewarding a
        # darker one-pixel outline.
        "exterior8To16": np.logical_and(
            outward_distance > 8.0, outward_distance <= 16.0
        ),
        "exterior16To20": np.logical_and(
            outward_distance > 16.0, outward_distance <= 20.0
        ),
    }
    exterior_shadow_annulus = np.logical_and(
        np.logical_not(glass_mask),
        np.logical_and(outward_distance > 2.0, outward_distance <= 20.0),
    )
    exterior_facing_masks = {
        "top": top_half,
        "bottom": bottom_half,
        "left": left_half,
        "right": right_half,
    }
    center_inset = int(round((x1 - x0) * 0.20))
    center_columns = np.logical_and(
        columns >= x0 + center_inset,
        columns < x1 - center_inset,
    )
    top_lip_mask = np.logical_and(inner_mask, rows < y0 + lip_depth)
    bottom_lip_mask = np.logical_and(inner_mask, rows >= y1 - lip_depth)
    top_center_lip_mask = np.logical_and(top_lip_mask, center_columns)
    bottom_center_lip_mask = np.logical_and(bottom_lip_mask, center_columns)
    face_start = max(int(round((y1 - y0) * 0.03)), 1)
    face_end = max(int(round((y1 - y0) * 0.22)), face_start + 1)
    top_face_mask = np.logical_and(inner_mask, rows >= y0 + face_start)
    top_face_mask = np.logical_and(top_face_mask, rows < y0 + face_end)
    top_face_mask = np.logical_and(top_face_mask, center_columns)
    bottom_face_mask = np.logical_and(inner_mask, rows >= y1 - face_end)
    bottom_face_mask = np.logical_and(bottom_face_mask, rows < y1 - face_start)
    bottom_face_mask = np.logical_and(bottom_face_mask, center_columns)
    exterior_mask = np.logical_and(
        cv2.dilate(mask_u8, np.ones((61, 61), np.uint8)) > 0,
        np.logical_not(glass_mask),
    )
    result: Dict[str, object] = {}
    for probe in ("A", "B", "C", "D"):
        residual = candidate[probe] - reference[probe]
        result[probe] = {
            "crop": _residual_statistics(residual),
            "glass": _residual_statistics(residual[glass_mask]),
            "core": _residual_statistics(residual[core_mask]),
            "rim": _residual_statistics(residual[rim_mask]),
            "outerContour": _residual_statistics(residual[outer_contour_mask]),
            "silhouetteLine": _residual_statistics(
                residual[silhouette_line_mask]
            ),
            "topSilhouetteLine": _residual_statistics(
                residual[np.logical_and(silhouette_line_mask, top_half)]
            ),
            "bottomSilhouetteLine": _residual_statistics(
                residual[np.logical_and(silhouette_line_mask, bottom_half)]
            ),
            "leftSilhouetteLine": _residual_statistics(
                residual[np.logical_and(silhouette_line_mask, left_half)]
            ),
            "rightSilhouetteLine": _residual_statistics(
                residual[np.logical_and(silhouette_line_mask, right_half)]
            ),
            "exteriorContour": _residual_statistics(
                residual[exterior_contour_mask]
            ),
            "innerRim": _residual_statistics(residual[inner_rim_mask]),
            "innerBevel": _residual_statistics(residual[inner_bevel_mask]),
            "topOuterContour": _residual_statistics(
                residual[np.logical_and(outer_contour_mask, top_half)]
            ),
            "bottomOuterContour": _residual_statistics(
                residual[np.logical_and(outer_contour_mask, bottom_half)]
            ),
            "leftOuterContour": _residual_statistics(
                residual[np.logical_and(outer_contour_mask, left_half)]
            ),
            "rightOuterContour": _residual_statistics(
                residual[np.logical_and(outer_contour_mask, right_half)]
            ),
            "topLip": _residual_statistics(residual[top_lip_mask]),
            "bottomLip": _residual_statistics(residual[bottom_lip_mask]),
            "topCenterLip": _residual_statistics(residual[top_center_lip_mask]),
            "bottomCenterLip": _residual_statistics(
                residual[bottom_center_lip_mask]
            ),
            "topFace": _residual_statistics(residual[top_face_mask]),
            "bottomFace": _residual_statistics(residual[bottom_face_mask]),
            "exterior": _residual_statistics(residual[exterior_mask]),
            "exteriorShadowAnnulus2To20": _residual_statistics(
                residual[exterior_shadow_annulus]
            ),
        }
        result[probe]["directionalDistanceBands"] = {
            f"{side}{band[0].upper()}{band[1:]}": _residual_statistics(
                residual[np.logical_and(side_mask, band_mask)]
            )
            for side, side_mask in facing_masks.items()
            for band, band_mask in distance_bands.items()
        }
        result[probe]["directionalExteriorBands"] = {
            f"{side}{band[0].upper()}{band[1:]}": _residual_statistics(
                residual[np.logical_and(side_mask, band_mask)]
            )
            for side, side_mask in exterior_facing_masks.items()
            for band, band_mask in exterior_bands.items()
        }
        result[probe]["directionalExteriorShadowAnnulus2To20"] = {
            side: _residual_statistics(
                residual[np.logical_and(side_mask, exterior_shadow_annulus)]
            )
            for side, side_mask in exterior_facing_masks.items()
        }
    emission_residual = candidate["C"] - reference["C"]
    transmission_residual = (
        candidate["D"] - candidate["C"]
    ) - (
        reference["D"] - reference["C"]
    )
    transfer_regions = {
        "crop": np.ones_like(glass_mask, dtype=bool),
        "glass": glass_mask,
        "rim": rim_mask,
        "outerContour": outer_contour_mask,
        "innerRim": inner_rim_mask,
        "innerBevel": inner_bevel_mask,
        "core": core_mask,
    }
    result["solidTransfer"] = {
        "emission": {
            name: _residual_statistics(
                emission_residual if name == "crop" else emission_residual[mask]
            )
            for name, mask in transfer_regions.items()
        },
        "transmission": {
            name: _residual_statistics(
                transmission_residual
                if name == "crop"
                else transmission_residual[mask]
            )
            for name, mask in transfer_regions.items()
        },
    }
    return result


def score_images(reference: Dict[str, np.ndarray], candidate: Dict[str, np.ndarray]) -> MetricResult:
    # Registration is verified on untouched RGBW control pixels before scoring.
    # Per-probe alignment would hide real silhouette and solid-probe errors.
    if not np.any(silhouette(candidate["C"])):
        raise ValueError(
            "Candidate black probe contains no measurable glass silhouette; "
            "the renderer is blank or the capture is invalid."
        )
    errors, details = component_errors(reference, candidate)
    crop_mae = float(
        np.mean(
            [
                details["pixelResiduals"][probe]["crop"]["meanAbsoluteError"]
                for probe in ("A", "B", "C", "D")
            ]
        )
    )
    details["directPixelMeanAbsoluteError"] = crop_mae
    details["directPixelMeanAbsoluteError8Bit"] = crop_mae * 255.0
    details["transmissionBoundaryProfile"] = boundary_profile_error(
        reference, candidate
    )
    details["directPixelScore"] = 100.0 * (1.0 - crop_mae)
    normalized = {
        "shape": min(errors["shape"] / 0.20, 1.0),
        "combined": min(errors["combined"] / 0.25, 1.0),
        "flow": min(errors["flow"], 1.0),
        "sharpness": min(errors["sharpness"], 1.0),
        "channel": min(errors["channel"] / 0.25, 1.0),
        "specular": min(errors["specular"] / 0.25, 1.0),
        "holdout": min(errors["holdout"] / 0.25, 1.0),
    }
    score = 100.0 * (1.0 - sum(WEIGHTS[key] * normalized[key] for key in WEIGHTS))
    details["stageScores"] = {
        "shape": 100.0 * (1.0 - normalized["shape"]),
        "refraction": 100.0 * (1.0 - normalized["flow"]),
        "blurMtf": 100.0 * (1.0 - normalized["sharpness"]),
        "tintColor": 100.0 * (1.0 - normalized["channel"]),
        "highlight": 100.0 * (1.0 - normalized["specular"]),
        "holdout": 100.0 * (1.0 - normalized["holdout"]),
        "refinement": 100.0
        * (
            1.0
            - 0.20 * normalized["shape"]
            - 0.20 * normalized["combined"]
            - 0.20 * normalized["flow"]
            - 0.15 * normalized["sharpness"]
            - 0.15 * normalized["channel"]
            - 0.10 * normalized["specular"]
        ),
    }
    return MetricResult(
        errors=errors,
        score=max(0.0, score),
        shift=(0.0, 0.0),
        details=details,
    )


def write_diagnostics(
    output: Path,
    reference: Dict[str, np.ndarray],
    candidate: Dict[str, np.ndarray],
) -> None:
    output.mkdir(parents=True, exist_ok=True)
    signed = np.clip((candidate["A"] - reference["A"]) * 4.0 * 0.5 + 0.5, 0, 1)
    cv2.imwrite(
        str(output / "signed_diff_x4.png"),
        cv2.cvtColor((signed * 255).astype(np.uint8), cv2.COLOR_RGB2BGR),
    )

    # Solid probes reveal the lighting model without patterned-background
    # refraction noise. Show signed luminance instead of absolute error so a
    # bright highlight and an over-dark shadow cannot cancel in an average.
    lighting_panels = []
    for probe, background_name in (("C", "black"), ("D", "white")):
        signed_luma = luminance(candidate[probe] - reference[probe])
        magnitude = np.clip(np.abs(signed_luma) * 8.0, 0.0, 1.0)
        panel = np.full((*signed_luma.shape, 3), 48, dtype=np.uint8)
        # RGB red = Flutter too bright; blue = Flutter too dark.
        panel[..., 0] = np.where(
            signed_luma > 0.0, 48 + magnitude * 207, 48
        ).astype(np.uint8)
        panel[..., 2] = np.where(
            signed_luma < 0.0, 48 + magnitude * 207, 48
        ).astype(np.uint8)
        cv2.putText(
            panel,
            f"{background_name}: red=too bright blue=too dark (x8)",
            (12, 28),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )
        lighting_panels.append(panel)
    cv2.imwrite(
        str(output / "solid_lighting_signed_residuals_x8.png"),
        cv2.cvtColor(np.concatenate(lighting_panels, axis=0), cv2.COLOR_RGB2BGR),
    )

    def gray_panel(values: np.ndarray, label: str) -> np.ndarray:
        gray = np.clip(luminance(values), 0.0, 1.0)
        panel = np.repeat((gray * 255).astype(np.uint8)[..., None], 3, axis=2)
        cv2.putText(
            panel, label, (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65,
            (255, 64, 64), 2, cv2.LINE_AA,
        )
        return panel

    def transfer_diff(candidate_values: np.ndarray, reference_values: np.ndarray, label: str) -> np.ndarray:
        delta = luminance(candidate_values - reference_values)
        magnitude = np.clip(np.abs(delta) * 8.0, 0.0, 1.0)
        panel = np.full((*delta.shape, 3), 48, dtype=np.uint8)
        panel[..., 0] = np.where(delta > 0.0, 48 + magnitude * 207, 48).astype(np.uint8)
        panel[..., 2] = np.where(delta < 0.0, 48 + magnitude * 207, 48).astype(np.uint8)
        cv2.putText(
            panel, label, (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65,
            (255, 255, 255), 2, cv2.LINE_AA,
        )
        return panel

    ref_emission = reference["C"]
    can_emission = candidate["C"]
    ref_transmission = reference["D"] - reference["C"]
    can_transmission = candidate["D"] - candidate["C"]
    transfer_rows = [
        np.concatenate([
            gray_panel(ref_emission, "Apple additive"),
            gray_panel(can_emission, "Flutter additive"),
            transfer_diff(can_emission, ref_emission, "additive residual x8"),
        ], axis=1),
        np.concatenate([
            gray_panel(ref_transmission, "Apple transmission"),
            gray_panel(can_transmission, "Flutter transmission"),
            transfer_diff(
                can_transmission, ref_transmission, "transmission residual x8"
            ),
        ], axis=1),
    ]
    cv2.imwrite(
        str(output / "solid_transfer_comparison.png"),
        cv2.cvtColor(np.concatenate(transfer_rows, axis=0), cv2.COLOR_RGB2BGR),
    )

    ref_profile = transmission_boundary_profile(reference["C"], reference["D"])
    can_profile = transmission_boundary_profile(candidate["C"], candidate["D"])
    profile_canvas = np.full((700, 1200, 3), 255, dtype=np.uint8)
    x_min = min(float(ref_profile["x"].min()), float(can_profile["x"].min()))
    x_max = max(float(ref_profile["x"].max()), float(can_profile["x"].max()))

    def draw_profile(values: Dict[str, np.ndarray], key: str, top: int, scale: float, color: tuple) -> None:
        px = 50 + ((values["x"] - x_min) / max(x_max - x_min, 1.0) * 1100)
        centered = values[key] - np.median(values[key])
        py = top - centered * scale
        points = np.column_stack((px, py)).astype(np.int32)
        cv2.polylines(profile_canvas, [points], False, color, 2, cv2.LINE_AA)

    cv2.putText(
        profile_canvas, "transmission isocontour: Apple black, Flutter orange",
        (40, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 2, cv2.LINE_AA,
    )
    draw_profile(ref_profile, "smoothBoundary", 250, 2.5, (0, 0, 0))
    draw_profile(can_profile, "smoothBoundary", 250, 2.5, (0, 100, 255))
    cv2.putText(
        profile_canvas, "curvature through straight-to-corner transition",
        (40, 390), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 2, cv2.LINE_AA,
    )
    draw_profile(ref_profile, "curvature", 560, 900.0, (0, 0, 0))
    draw_profile(can_profile, "curvature", 560, 900.0, (0, 100, 255))
    cv2.line(profile_canvas, (40, 560), (1160, 560), (180, 180, 180), 1)
    cv2.imwrite(str(output / "transmission_boundary_curvature.png"), profile_canvas)

    flow = signed_optical_flow(
        reference["A"],
        reference["B"],
        candidate["A"],
        candidate["B"],
    )
    limit = max(float(np.percentile(np.abs(flow), 99)), 1e-6)
    normalized = np.clip(flow / limit, -1, 1)
    visual = np.zeros((*flow.shape, 3), dtype=np.uint8)
    visual[..., 0] = np.where(normalized > 0, normalized * 255, 0).astype(np.uint8)
    visual[..., 2] = np.where(normalized < 0, -normalized * 255, 0).astype(np.uint8)
    cv2.imwrite(str(output / "signed_radial_flow.png"), cv2.cvtColor(visual, cv2.COLOR_RGB2BGR))

    _, _, ref_gradient = _gradient(reference["A"])
    _, _, can_gradient = _gradient(candidate["A"])
    profile = np.stack(
        [
            np.mean(ref_gradient, axis=0),
            np.mean(can_gradient, axis=0),
        ]
    )
    canvas = np.full((240, profile.shape[1], 3), 255, dtype=np.uint8)
    for values, color in zip(profile, ((0, 0, 0), (0, 90, 255))):
        values = values / max(float(values.max()), 1e-6)
        points = np.column_stack(
            (np.arange(values.size), 220 - (values * 200).astype(np.int32))
        ).astype(np.int32)
        cv2.polylines(canvas, [points], False, color, 2)
    cv2.imwrite(str(output / "gradient_profile.png"), canvas)

    _, _, ref_mask, can_mask = shape_comparison(reference["C"], candidate["C"])
    silhouette_visual = np.zeros((*ref_mask.shape, 3), dtype=np.uint8)
    silhouette_visual[..., 0] = ref_mask * 255
    silhouette_visual[..., 1] = can_mask * 255
    silhouette_visual[..., 2] = can_mask * 255
    overlap = np.logical_and(ref_mask, can_mask)
    silhouette_visual[overlap] = (255, 255, 255)
    cv2.putText(
        silhouette_visual,
        "red=Apple cyan=Flutter white=overlap",
        (12, 28),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2,
        cv2.LINE_AA,
    )
    cv2.imwrite(
        str(output / "silhouette_shape.png"),
        cv2.cvtColor(silhouette_visual, cv2.COLOR_RGB2BGR),
    )

    channel_panels = []
    for channel, label in enumerate(("R residual", "G residual", "B residual")):
        residual = np.clip(
            (candidate["A"][..., channel] - reference["A"][..., channel]) * 3.0
            + 0.5,
            0,
            1,
        )
        panel = np.repeat((residual * 255).astype(np.uint8)[..., None], 3, axis=2)
        cv2.putText(
            panel,
            label,
            (12, 28),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (0, 0, 255),
            2,
            cv2.LINE_AA,
        )
        channel_panels.append(panel)
    cv2.imwrite(
        str(output / "channel_residuals.png"),
        cv2.cvtColor(np.concatenate(channel_panels, axis=1), cv2.COLOR_RGB2BGR),
    )

    scatter = np.full((420, 720, 3), 255, dtype=np.uint8)
    mask = ref_mask.astype(bool)
    for channel, color in enumerate(((255, 0, 0), (0, 170, 0), (0, 0, 255))):
        ref_values = reference["A"][..., channel][mask][::40]
        can_values = candidate["A"][..., channel][mask][::40]
        points = np.column_stack(
            (
                40 + (ref_values * 300).astype(np.int32),
                360 - (can_values * 300).astype(np.int32),
            )
        )
        for point in points:
            cv2.circle(scatter, tuple(point), 1, color, -1)
    cv2.line(scatter, (40, 360), (340, 60), (80, 80, 80), 1)
    center = reference["A"].shape[0] // 2
    for channel, color in enumerate(((255, 0, 0), (0, 170, 0), (0, 0, 255))):
        for image, offset in ((reference["A"], 0), (candidate["A"], 330)):
            values = image[center, :, channel]
            values = cv2.resize(
                values[None, :], (330, 1), interpolation=cv2.INTER_AREA
            )[0]
            points = np.column_stack(
                (
                    370 + np.arange(values.size),
                    360 - (values * 300).astype(np.int32),
                )
            )
            cv2.polylines(
                scatter,
                [points],
                False,
                color if offset == 0 else tuple(int(c * 0.55) for c in color),
                1 if offset == 0 else 2,
            )
    cv2.putText(scatter, "RGB scatter", (40, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 0), 2)
    cv2.putText(scatter, "centerline profiles", (370, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 0), 2)
    cv2.imwrite(str(output / "rgb_scatter_profile.png"), scatter)

    holdout_diff = np.clip(
        (candidate["B"] - reference["B"]) * 3.0 * 0.5 + 0.5, 0, 1
    )
    holdout = np.concatenate(
        (reference["B"], candidate["B"], holdout_diff),
        axis=1,
    )
    cv2.imwrite(
        str(output / "holdout_comparison.png"),
        cv2.cvtColor((holdout * 255).astype(np.uint8), cv2.COLOR_RGB2BGR),
    )

    solid_rows = []
    for probe, label in (("C", "black"), ("D", "white")):
        amplified_diff = np.clip(
            (candidate[probe] - reference[probe]) * 3.0 * 0.5 + 0.5,
            0,
            1,
        )
        row = np.concatenate(
            (reference[probe], candidate[probe], amplified_diff),
            axis=1,
        )
        cv2.putText(
            row,
            f"{label}: Apple | Flutter | signed diff x3",
            (12, 28),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (1.0, 0.0, 0.0),
            2,
            cv2.LINE_AA,
        )
        solid_rows.append(row)
    solids = np.concatenate(solid_rows, axis=0)
    cv2.imwrite(
        str(output / "solid_lighting_comparison.png"),
        cv2.cvtColor((solids * 255).astype(np.uint8), cv2.COLOR_RGB2BGR),
    )
