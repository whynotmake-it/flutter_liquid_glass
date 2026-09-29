"""Rim, highlight and contour measurements from the solid black/white probes.

On a solid backdrop refraction cannot move content, so each glass pixel is an
affine function of the backdrop: ``out = emission + transmittance * backdrop``.
The black probe (C) therefore measures emission directly and the white probe
(D) minus the black probe measures transmittance. Binning both by signed edge
distance and SDF-normal angle yields a compact rim table that exposes the
properties the aggregate score dilutes: glint peak, glint width, angular
extent, dark-contour depth, and exterior outline/shadow.

All values stay in normalized 8-bit display space, matching the capture
encoding and the rest of the harness.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np

LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)

# Physical-pixel distance bins, negative outside the silhouette.
DISTANCE_BINS = np.arange(-6, 25, dtype=np.float32)
# 0 deg is a normal pointing up (toward the top light), 90 deg points right.
ANGLE_BIN_COUNT = 24
# The deep face used as the interior baseline for excess emission.
INTERIOR_RANGE = (20.0, 24.0)
# Band that contains the glint on every captured scene at 3x.
GLINT_RANGE = (0.0, 12.0)
CONTOUR_RANGE = (-3.0, 3.0)
EXTERIOR_RANGE = (-6.0, -1.0)


def _luma(image: np.ndarray) -> np.ndarray:
    return image[..., :3] @ LUMA


def silhouette_mask(black: np.ndarray, white: np.ndarray) -> np.ndarray:
    """Glass coverage from the pair: anything differing from pure backdrop."""
    black_delta = _luma(black) > 0.02
    white_delta = _luma(white) < 0.985
    mask = np.logical_or(black_delta, white_delta).astype(np.uint8)
    # The white probe also darkens the exterior shadow; the black probe is
    # the authoritative glass support, so require black-probe coverage and
    # only close sub-pixel gaps.
    mask = np.logical_and(mask, black_delta).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if count <= 1:
        return mask.astype(bool)
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return labels == largest


def signed_distance(mask: np.ndarray) -> np.ndarray:
    """Pixel ring index: 1 is the first covered ring, -1 the first exterior.

    Rings (rather than half-pixel-shifted distances) keep the first inside
    and first outside pixels in separate bins, which is where the glint and
    the dark contour live.
    """
    inside = cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5)
    outside = cv2.distanceTransform((~mask).astype(np.uint8), cv2.DIST_L2, 5)
    return np.where(mask, inside, -outside).astype(np.float32)


def normal_angle(distance: np.ndarray) -> np.ndarray:
    """Outward-normal angle in degrees, 0 = up, 90 = right."""
    smooth = cv2.GaussianBlur(distance, (0, 0), 3.0)
    gy, gx = np.gradient(smooth)
    # Outward is the negative distance gradient.
    nx, ny = -gx, -gy
    return (np.degrees(np.arctan2(nx, -ny)) + 360.0) % 360.0


@dataclass
class RimTable:
    """Median emission/transmittance per (distance, angle) bin."""

    emission: np.ndarray  # [distance, angle, rgb]
    transmittance: np.ndarray  # [distance, angle, rgb]
    counts: np.ndarray  # [distance, angle]
    interior_emission: np.ndarray  # rgb
    interior_transmittance: np.ndarray  # rgb

    def luma(self, field: str) -> np.ndarray:
        return getattr(self, field) @ LUMA


def rim_table(
    black: np.ndarray,
    white: np.ndarray,
    mask: Optional[np.ndarray] = None,
) -> RimTable:
    black = black[..., :3].astype(np.float32)
    white = white[..., :3].astype(np.float32)
    if mask is None:
        mask = silhouette_mask(black, white)
    ys, xs = np.where(mask)
    margin = 48
    y0, y1 = max(int(ys.min()) - margin, 0), min(int(ys.max()) + margin + 1, mask.shape[0])
    x0, x1 = max(int(xs.min()) - margin, 0), min(int(xs.max()) + margin + 1, mask.shape[1])
    mask = mask[y0:y1, x0:x1]
    black = black[y0:y1, x0:x1]
    white = white[y0:y1, x0:x1]
    distance = signed_distance(mask)
    angle = normal_angle(distance)
    emission = black
    transmittance = white - black
    d_index = np.round(distance - DISTANCE_BINS[0]).astype(np.int32)
    a_index = (np.floor(angle / (360.0 / ANGLE_BIN_COUNT)).astype(np.int32)) % ANGLE_BIN_COUNT
    valid = (d_index >= 0) & (d_index < len(DISTANCE_BINS))
    shape = (len(DISTANCE_BINS), ANGLE_BIN_COUNT, 3)
    e_table = np.full(shape, np.nan, dtype=np.float32)
    t_table = np.full(shape, np.nan, dtype=np.float32)
    counts = np.zeros(shape[:2], dtype=np.int32)
    flat_bin = (d_index * ANGLE_BIN_COUNT + a_index)[valid]
    order = np.argsort(flat_bin, kind="stable")
    sorted_bins = flat_bin[order]
    e_values = emission[valid][order]
    t_values = transmittance[valid][order]
    starts = np.flatnonzero(np.r_[True, sorted_bins[1:] != sorted_bins[:-1]])
    ends = np.r_[starts[1:], len(sorted_bins)]
    for start, end in zip(starts, ends):
        di, ai = divmod(int(sorted_bins[start]), ANGLE_BIN_COUNT)
        counts[di, ai] = int(end - start)
        e_table[di, ai] = np.median(e_values[start:end], axis=0)
        t_table[di, ai] = np.median(t_values[start:end], axis=0)
    interior = mask & (distance >= INTERIOR_RANGE[0]) & (distance <= INTERIOR_RANGE[1])
    if not np.any(interior):
        interior = mask & (distance >= np.percentile(distance[mask], 75))
    return RimTable(
        emission=e_table,
        transmittance=t_table,
        counts=counts,
        interior_emission=np.median(emission[interior], axis=0),
        interior_transmittance=np.median(transmittance[interior], axis=0),
    )


def _rows(lo: float, hi: float) -> np.ndarray:
    return np.where((DISTANCE_BINS >= lo) & (DISTANCE_BINS <= hi))[0]


def _angle_groups() -> Dict[str, List[int]]:
    width = 360.0 / ANGLE_BIN_COUNT
    centers = (np.arange(ANGLE_BIN_COUNT) + 0.5) * width

    def near(target: float, tolerance: float = 20.0) -> List[int]:
        delta = np.abs(((centers - target) + 180.0) % 360.0 - 180.0)
        return [int(i) for i in np.where(delta <= tolerance)[0]]

    return {
        "top": near(0.0),
        "right": near(90.0),
        "bottom": near(180.0),
        "left": near(270.0),
        "diagonal": near(45.0) + near(135.0) + near(225.0) + near(315.0),
    }


def _nanmean(values: np.ndarray, axis=None):
    with np.errstate(all="ignore"):
        import warnings

        with warnings.catch_warnings():
            warnings.simplefilter("ignore", category=RuntimeWarning)
            return np.nanmean(values, axis=axis)


def glint_profile(table: RimTable, group: List[int]) -> np.ndarray:
    """Excess emission luma above the interior, by distance bin."""
    luma = table.luma("emission")[:, group]
    base = float(table.interior_emission @ LUMA)
    return _nanmean(luma, axis=1) - base


def contour_profile(table: RimTable, group: List[int]) -> np.ndarray:
    """Transmittance luma relative to the interior, by distance bin."""
    luma = table.luma("transmittance")[:, group]
    base = float(table.interior_transmittance @ LUMA)
    return _nanmean(luma, axis=1) - base


def _fwhm(profile: np.ndarray, rows: np.ndarray) -> Tuple[float, float, float]:
    values = profile[rows]
    if not np.any(np.isfinite(values)):
        return 0.0, 0.0, 0.0
    values = np.nan_to_num(values, nan=0.0)
    peak_index = int(np.argmax(values))
    peak = float(values[peak_index])
    if peak <= 1.0 / 255.0:
        return peak, 0.0, float(DISTANCE_BINS[rows][peak_index])
    half = peak * 0.5
    above = values >= half
    # Contiguous run around the peak.
    lo = peak_index
    while lo > 0 and above[lo - 1]:
        lo -= 1
    hi = peak_index
    while hi < len(values) - 1 and above[hi + 1]:
        hi += 1
    return peak, float(hi - lo + 1), float(DISTANCE_BINS[rows][peak_index])


def summarize(table: RimTable) -> Dict[str, object]:
    groups = _angle_groups()
    glint_rows = _rows(*GLINT_RANGE)
    contour_rows = _rows(*CONTOUR_RANGE)
    exterior_rows = _rows(*EXTERIOR_RANGE)
    out: Dict[str, object] = {
        "interiorEmission8": [float(v * 255) for v in table.interior_emission],
        "interiorTransmittance": [float(v) for v in table.interior_transmittance],
        "sides": {},
    }
    for name, group in groups.items():
        glint = glint_profile(table, group)
        contour = contour_profile(table, group)
        peak, width, at = _fwhm(glint, glint_rows)
        t_values = np.nan_to_num(contour[contour_rows], nan=0.0)
        exterior_t = table.luma("transmittance")[:, group]
        exterior = float(np.nanmin(_nanmean(exterior_t[exterior_rows], axis=1)))
        out["sides"][name] = {
            "glintPeak8": peak * 255.0,
            "glintFwhmPx": width,
            "glintPeakDistancePx": at,
            "glintEnergy8Px": float(np.nansum(np.clip(glint[glint_rows], 0, None)) * 255.0),
            "contourMinTransmittanceDelta": float(np.min(t_values)),
            "exteriorMinTransmittance": exterior,
        }
    sides = out["sides"]
    axis = 0.5 * (sides["top"]["glintPeak8"] + sides["bottom"]["glintPeak8"])
    ends = 0.5 * (sides["left"]["glintPeak8"] + sides["right"]["glintPeak8"])
    out["glintAxisToSideRatio"] = axis / max(ends, 0.5)
    out["glintTopToBottomRatio"] = sides["top"]["glintPeak8"] / max(
        sides["bottom"]["glintPeak8"], 0.5
    )
    return out


def compare_tables(reference: RimTable, candidate: RimTable) -> Dict[str, float]:
    """Rim-specific errors, all in 8-bit units except transmittance."""
    band = _rows(-4.0, 12.0)
    glint_band = _rows(*GLINT_RANGE)
    ref_e = reference.luma("emission")[band]
    can_e = candidate.luma("emission")[band]
    ref_t = reference.luma("transmittance")[band]
    can_t = candidate.luma("transmittance")[band]
    valid = np.isfinite(ref_e) & np.isfinite(can_e)
    e_err = float(np.sqrt(np.mean((ref_e[valid] - can_e[valid]) ** 2)) * 255.0)
    t_err = float(np.sqrt(np.mean((ref_t[valid] - can_t[valid]) ** 2)))
    # Shape of the excess glint independent of the face level.
    ref_x = reference.luma("emission")[glint_band] - float(reference.interior_emission @ LUMA)
    can_x = candidate.luma("emission")[glint_band] - float(candidate.interior_emission @ LUMA)
    gv = np.isfinite(ref_x) & np.isfinite(can_x)
    glint_err = float(np.sqrt(np.mean((ref_x[gv] - can_x[gv]) ** 2)) * 255.0)
    ref_s = summarize(reference)
    can_s = summarize(candidate)
    width_err = float(
        np.mean(
            [
                abs(ref_s["sides"][k]["glintFwhmPx"] - can_s["sides"][k]["glintFwhmPx"])
                for k in ("top", "bottom")
            ]
        )
    )
    peak_err = float(
        np.mean(
            [
                abs(ref_s["sides"][k]["glintPeak8"] - can_s["sides"][k]["glintPeak8"])
                for k in ("top", "bottom", "left", "right", "diagonal")
            ]
        )
    )
    contour_err = float(
        np.mean(
            [
                abs(
                    ref_s["sides"][k]["contourMinTransmittanceDelta"]
                    - can_s["sides"][k]["contourMinTransmittanceDelta"]
                )
                for k in ("top", "bottom", "left", "right", "diagonal")
            ]
        )
    )
    face_e = float(np.mean(np.abs(reference.interior_emission - candidate.interior_emission)) * 255.0)
    face_t = float(np.mean(np.abs(reference.interior_transmittance - candidate.interior_transmittance)))
    return {
        "rimEmissionRms8": e_err,
        "rimTransmittanceRms": t_err,
        "glintShapeRms8": glint_err,
        "glintWidthErrorPx": width_err,
        "glintPeakError8": peak_err,
        "contourDepthError": contour_err,
        "faceEmissionError8": face_e,
        "faceTransmittanceError": face_t,
    }
