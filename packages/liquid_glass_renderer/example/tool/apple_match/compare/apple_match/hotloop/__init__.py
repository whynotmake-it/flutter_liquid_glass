"""Hot-reload fast iteration loop for the Apple-match harness."""

from .evaluate import (
    CaptureSession,
    Evaluator,
    PINNED_DEVICE_NAME,
    PINNED_DEVICE_UDID,
    ensure_pinned_simulator,
    load_reference_probes,
    prepare_simulator,
    scene_crop,
)
from .optimize import DEFAULT_AXES, coordinate_descent, neighbor_values, spsa_descent
from .session import (
    FlutterRunSession,
    SessionError,
    SettleTimeout,
    SignalReloadTrigger,
)

__all__ = [
    "CaptureSession",
    "DEFAULT_AXES",
    "Evaluator",
    "PINNED_DEVICE_NAME",
    "PINNED_DEVICE_UDID",
    "FlutterRunSession",
    "SessionError",
    "SettleTimeout",
    "SignalReloadTrigger",
    "coordinate_descent",
    "ensure_pinned_simulator",
    "load_reference_probes",
    "neighbor_values",
    "prepare_simulator",
    "scene_crop",
    "spsa_descent",
]
