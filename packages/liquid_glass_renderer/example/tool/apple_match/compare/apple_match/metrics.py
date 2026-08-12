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
    details = {
        "shiftPixels": {"x": float(shift[0]), "y": float(shift[1])},
        "phaseCorrelationResponse": float(response),
        "outsideMeanAbsoluteError": {
            "red": float(channel_mean[0]),
            "green": float(channel_mean[1]),
            "blue": float(channel_mean[2]),
        },
        "outsideResidualP99": percentile_99,
        "passed": bool(
            abs(shift[0]) <= 0.51
            and abs(shift[1]) <= 0.51
            and percentile_99 <= 2.0 / 255.0
        ),
    }
    if not details["passed"]:
        raise ValueError(f"RGBW background registration failed: {details}")
    return details


def luminance(image: np.ndarray) -> np.ndarray:
    return image[..., 0] * 0.2126 + image[..., 1] * 0.7152 + image[..., 2] * 0.0722


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
    minimum = float(min(reference_delta.min(), candidate_delta.min()))
    maximum = float(max(reference_delta.max(), candidate_delta.max()))
    scale = max(maximum - minimum, 1e-6)
    reference_u8 = np.clip((reference_delta - minimum) / scale * 255, 0, 255).astype(
        np.uint8
    )
    candidate_u8 = np.clip((candidate_delta - minimum) / scale * 255, 0, 255).astype(
        np.uint8
    )
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
    combined = float(np.mean(np.abs(ref_a - can_a)))
    holdout = float(np.mean(np.abs(reference["B"] - candidate["B"])))

    zeros = np.zeros_like(ref_a)
    optical_flow = signed_optical_flow(
        reference["A"],
        zeros,
        candidate["A"],
        zeros,
    )
    flow = float(np.mean(np.abs(optical_flow)) / 4.0)

    _, _, ref_gradient = _gradient(reference["A"])
    _, _, can_gradient = _gradient(candidate["A"])
    height, width = ref_gradient.shape
    region = np.s_[height // 4 : 3 * height // 4, width // 6 : 5 * width // 6]
    ref_edge = float(np.mean(ref_gradient[region]))
    can_edge = float(np.mean(can_gradient[region]))
    sharpness = float(
        abs(ref_edge - can_edge)
        / (ref_edge + eps)
    )

    ref_c = luminance(reference["C"])
    can_c = luminance(candidate["C"])
    specular = float(np.mean(np.abs(ref_c - can_c)))

    channel_residuals = np.mean(np.abs(ref_a - can_a), axis=(0, 1))
    ref_d = reference["D"]
    can_d = candidate["D"]
    ref_chroma = ref_d - np.mean(ref_d, axis=2, keepdims=True)
    can_chroma = can_d - np.mean(can_d, axis=2, keepdims=True)
    white_balance = float(np.mean(np.abs(ref_chroma - can_chroma)))
    channel = float(np.mean(channel_residuals) + white_balance)
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
    }
    return errors, details


def score_images(reference: Dict[str, np.ndarray], candidate: Dict[str, np.ndarray]) -> MetricResult:
    aligned = {}
    shifts = []
    for probe in ("A", "B", "C", "D"):
        aligned[probe], shift = align(reference[probe], candidate[probe])
        shifts.append(shift)
    errors, details = component_errors(reference, aligned)
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
        "tintColor": 100.0
        * (1.0 - 0.65 * normalized["channel"] - 0.35 * normalized["holdout"]),
        "highlight": 100.0 * (1.0 - normalized["specular"]),
        "holdout": 100.0 * (1.0 - normalized["holdout"]),
    }
    mean_shift = tuple(float(np.mean([shift[i] for shift in shifts])) for i in range(2))
    return MetricResult(
        errors=errors,
        score=max(0.0, score),
        shift=mean_shift,
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

    zeros = np.zeros_like(reference["A"])
    flow = signed_optical_flow(reference["A"], zeros, candidate["A"], zeros)
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
