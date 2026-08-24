"""Tiny online optimizer: coordinate descent over per-axis value lists.

Each iteration evaluates the one-step neighborhood of the current point
(previous/next value on every axis), moves to the best candidate if it
improves the loss, and stops when no neighbor improves or the iteration
budget is exhausted.
"""

from __future__ import annotations

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
