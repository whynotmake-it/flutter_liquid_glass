"""Tiny online optimizer: coordinate descent over per-axis value lists.

Each iteration evaluates the one-step neighborhood of the current point
(previous/next value on every axis), moves to the best candidate if it
improves the loss, and stops when no neighbor improves or the iteration
budget is exhausted.
"""

from __future__ import annotations

import random

# Default axes mirror the bounds already explored by the staged search; each
# axis is a small ordered list, so a neighborhood is at most 2 x axes evals.
DEFAULT_AXES = {
    "thickness": [0.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0],
    "blur": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0],
    "lightIntensity": [0.0, 0.1, 0.2, 0.25, 0.3, 0.4, 0.5],
    "glassAlpha": [0.45, 0.48, 0.5, 0.52, 0.54, 0.56, 0.6, 0.65],
    "saturation": [0.8, 1.0, 1.2, 1.5, 1.8],
    "refractiveIndex": [1.0, 1.1, 1.15, 1.2, 1.25, 1.3],
    "lightAngle": [0.7853981633974483, 1.5707963267948966, 2.356194490192345],
}


def neighbor_values(values, current):
    """The one-step neighborhood of ``current`` on one ordered axis.

    Returns the closest listed value below and above ``current`` (the
    bracketing grid points when the current value sits between listings).
    """
    values = sorted(values)
    lower = [value for value in values if value < current]
    upper = [value for value in values if value > current]
    neighbors = []
    if lower:
        neighbors.append(lower[-1])
    if upper:
        neighbors.append(upper[0])
    return neighbors


def coordinate_descent(
    evaluate,
    baseline: dict,
    axes: dict,
    *,
    max_iters: int = 8,
    min_improvement: float = 1e-4,
    on_step=None,
) -> dict:
    """Minimize ``evaluate(params)`` starting from ``baseline``.

    Returns ``{"bestParams", "bestLoss", "history"}`` where every history row
    is ``{"iteration", "params", "loss", "isBest"}``.
    """
    current = dict(baseline)
    current_loss = evaluate(current)
    history = [
        {
            "iteration": 0,
            "params": dict(current),
            "loss": current_loss,
            "isBest": True,
        }
    ]
    if on_step:
        on_step(history[-1])
    for iteration in range(1, max_iters + 1):
        best_candidate, best_loss, best_row = None, current_loss, None
        for axis, values in axes.items():
            if axis not in current:
                continue
            for value in neighbor_values(values, current[axis]):
                candidate = {**current, axis: value}
                loss = evaluate(candidate)
                row = {
                    "iteration": iteration,
                    "params": candidate,
                    "loss": loss,
                    "isBest": False,
                }
                history.append(row)
                if on_step:
                    on_step(row)
                if loss < best_loss - min_improvement:
                    best_candidate, best_loss, best_row = candidate, loss, row
        if best_candidate is None:
            break
        current, current_loss = best_candidate, best_loss
        best_row["isBest"] = True
    return {"bestParams": current, "bestLoss": current_loss, "history": history}


def spsa_descent(
    evaluate,
    baseline: dict,
    bounds: dict,
    *,
    max_iters: int = 12,
    learning_rate: float = 0.1,
    perturbation: float = 0.02,
    decay: float = 0.0,
    seed: int = 0,
    min_improvement: float = 1e-4,
    on_step=None,
) -> dict:
    """Bounded continuous descent for coupled black-box renderer parameters.

    Flutter/Impeller does not expose derivatives through rasterization, so the
    harness estimates a gradient with a two-sided simultaneous perturbation
    (SPSA). Each iteration needs only two probe renders for the gradient plus a
    candidate render, regardless of the number of fitted parameters. Bounds
    and deterministic Rademacher directions keep updates reproducible and
    prevent invalid JSON settings. A rejected step is backtracked before the
    optimizer advances, which makes this suitable for noisy GPU-golden losses.

    ``bounds`` maps each fitted key to ``(lower, upper)``. Non-fitted keys in
    ``baseline`` are carried through unchanged. The return shape matches
    :func:`coordinate_descent` so existing scorecard/report code can consume
    either optimizer.
    """
    keys = tuple(bounds)
    if not keys:
        raise ValueError("SPSA requires at least one bounded parameter")
    current = dict(baseline)
    spans = {}
    for key in keys:
        if key not in current:
            raise ValueError(f"baseline is missing bounded parameter {key!r}")
        lower, upper = bounds[key]
        if lower > upper:
            raise ValueError(f"invalid bounds for {key!r}: {bounds[key]!r}")
        spans[key] = max(float(upper) - float(lower), 1e-12)
        current[key] = min(max(float(current[key]), lower), upper)

    current_loss = evaluate(current)
    history = [
        {
            "iteration": 0,
            "params": dict(current),
            "loss": current_loss,
            "isBest": True,
            "accepted": True,
        }
    ]
    if on_step:
        on_step(history[-1])

    rng = random.Random(seed)
    for iteration in range(1, max_iters + 1):
        # A decaying perturbation is useful when the initial model is far from
        # the target but the final fit needs sub-slider precision.
        c = perturbation / (1.0 + decay * max(iteration - 1, 0))
        direction = {key: (1.0 if rng.getrandbits(1) else -1.0) for key in keys}
        plus = dict(current)
        minus = dict(current)
        normalized = {
            key: (current[key] - bounds[key][0]) / spans[key] for key in keys
        }
        for key in keys:
            lower, upper = bounds[key]
            plus_normalized = min(
                max(normalized[key] + c * direction[key], 0.0), 1.0
            )
            minus_normalized = min(
                max(normalized[key] - c * direction[key], 0.0), 1.0
            )
            plus[key] = lower + plus_normalized * spans[key]
            minus[key] = lower + minus_normalized * spans[key]
        plus_loss = evaluate(plus)
        minus_loss = evaluate(minus)

        gradient = {}
        for key in keys:
            denominator = (
                (plus[key] - bounds[key][0]) / spans[key]
                - (minus[key] - bounds[key][0]) / spans[key]
            )
            if abs(denominator) < 1e-12:
                gradient[key] = 0.0
            else:
                # The loss is minimized, so the update moves opposite this
                # estimated derivative. Using the actual clipped denominator
                # keeps boundary steps numerically well-behaved.
                gradient[key] = (plus_loss - minus_loss) / denominator

        step = learning_rate / (1.0 + decay * max(iteration - 1, 0))
        # Loss scales are scene-dependent (and can jump at a clipped SDF
        # boundary). Normalize the simultaneous direction before applying the
        # learning rate so one noisy channel cannot throw every other axis to
        # a bound. This is the bounded analogue of gradient clipping.
        gradient_scale = max(1.0, *(abs(value) for value in gradient.values()))
        candidate = dict(current)
        for key in keys:
            lower, upper = bounds[key]
            candidate_normalized = min(
                max(normalized[key] - step * gradient[key] / gradient_scale, 0.0),
                1.0,
            )
            candidate[key] = lower + candidate_normalized * spans[key]
        candidate_loss = evaluate(candidate)

        # A noisy render can flip the sign of one estimate. Backtrack rather
        # than accepting a regression, preserving monotonic best-so-far loss.
        accepted = candidate_loss < current_loss - min_improvement
        if not accepted:
            for factor in (0.5, 0.25, 0.125):
                retry = dict(current)
                for key in keys:
                    lower, upper = bounds[key]
                    retry_normalized = min(
                        max(
                            normalized[key]
                            - step * factor * gradient[key] / gradient_scale,
                            0.0,
                        ),
                        1.0,
                    )
                    retry[key] = lower + retry_normalized * spans[key]
                retry_loss = evaluate(retry)
                if retry_loss < current_loss - min_improvement:
                    candidate, candidate_loss, accepted = retry, retry_loss, True
                    break

        row = {
            "iteration": iteration,
            "params": dict(candidate if accepted else current),
            "loss": candidate_loss if accepted else current_loss,
            "isBest": accepted,
            "accepted": accepted,
            "gradient": gradient,
            "plusLoss": plus_loss,
            "minusLoss": minus_loss,
        }
        history.append(row)
        if on_step:
            on_step(row)
        if accepted:
            current, current_loss = candidate, candidate_loss

    return {"bestParams": current, "bestLoss": current_loss, "history": history}
