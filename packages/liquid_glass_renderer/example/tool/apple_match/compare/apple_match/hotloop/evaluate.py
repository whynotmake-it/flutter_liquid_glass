"""The core of the fast loop: params -> hot reload -> settled frame -> loss.

One persistent Flutter app stays resident on the pinned simulator. Each
evaluation writes a small candidate JSON into the app sandbox, triggers a hot
reload, waits for the app to report a settled frame, screenshots the four
probes, and scores them against the pinned Apple reference in-process.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import time
from pathlib import Path

from ..metrics import read_rgb, score_images
from .session import FlutterRunSession, SessionError, SignalReloadTrigger

BUNDLE_ID = "dev.liquidglass.appleMatchFlutter"
PINNED_DEVICE_NAME = "AppleMatch-iPhone17Pro-iOS27"
PINNED_DEVICE_UDID = "DB4F41F3-1C36-476D-B775-AFDC3686C75B"
PROBES = ("A", "B", "C", "D")
CANDIDATE_FILE_NAME = "apple_match_candidate.json"
STATUS_FILE_NAME = "apple_match_status.json"

# Keep this list in lock-step with matchGlassSettings/matchGlassShape and the
# geometry overrides in flutter/lib/scene_view.dart. An optimizer parameter
# that never reaches the renderer makes a flat search axis look like evidence.
SUPPORTED_SETTINGS = frozenset(
    {
        "shapeWidth",
        "shapeHeight",
        "shapeOffsetX",
        "shapeOffsetY",
        "cornerRadius",
        "shapeProfile",
        "glassRed",
        "glassGreen",
        "glassBlue",
        "glassAlpha",
        "thickness",
        "blur",
        "lightAngle",
        "lightIntensity",
        "ambientStrength",
        "highlightLuminance",
        "highlightAlpha",
        "edgeLuminance",
        "edgeAlpha",
        "edgeWidth",
        "edgeInset",
        "outerContourLuminance",
        "outerContourAlpha",
        "outerContourWidth",
        "specularWrap",
        "bleedStrength",
        "transmissionGamma",
        "vibrancy",
        "faceShadingStrength",
        "faceShadingDepth",
        "innerShadowStrength",
        "innerShadowDepth",
        "innerShadowDirectionality",
        "refractiveIndex",
        "saturation",
        "chromaticAberration",
        "shadowLuminance",
        "shadowAlpha",
        "shadowOffsetX",
        "shadowOffsetY",
        "shadowBlur",
        "shadowSpread",
        "contactShadowLuminance",
        "contactShadowAlpha",
        "contactShadowOffsetX",
        "contactShadowOffsetY",
        "contactShadowBlur",
        "contactShadowSpread",
    }
)


def validate_settings(settings: dict) -> None:
    unknown = sorted(set(settings) - SUPPORTED_SETTINGS)
    if unknown:
        raise ValueError(
            "Apple-match settings are not wired to the live renderer: "
            f"{unknown}"
        )
    profile = settings.get("shapeProfile", "roundedRectangle")
    if profile not in ("roundedRectangle", "superellipse"):
        raise ValueError(f"Unsupported shapeProfile: {profile!r}")


def simctl(*arguments: str) -> str:
    return subprocess.check_output(
        ["xcrun", "simctl", *arguments], text=True
    ).strip()


def atomic_write_json(path: Path, payload: dict) -> None:
    # The container tmp dir may not exist yet on a fresh install.
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(payload))
    os.replace(tmp, path)


def read_json_file(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def ensure_pinned_simulator(udid: str, *, simctl_fn=simctl) -> None:
    """Reuse the one reference-capture simulator; never create or clone one."""
    data = json.loads(simctl_fn("list", "devices", "-j"))
    devices = [
        device
        for entries in data["devices"].values()
        for device in entries
        if device.get("isAvailable", False)
    ]
    pinned = next(
        (
            device
            for device in devices
            if device.get("udid") == PINNED_DEVICE_UDID
            and device.get("name") == PINNED_DEVICE_NAME
        ),
        None,
    )
    if pinned is None:
        raise RuntimeError(
            f"Required pinned simulator {PINNED_DEVICE_NAME} "
            f"({PINNED_DEVICE_UDID}) is unavailable; refusing to create a clone."
        )
    if udid != PINNED_DEVICE_UDID:
        raise RuntimeError(
            f"Candidates must use reference simulator {PINNED_DEVICE_UDID}; "
            f"refusing requested simulator {udid}."
        )
    if pinned.get("state") != "Booted":
        simctl_fn("boot", PINNED_DEVICE_UDID)
    simctl_fn("bootstatus", PINNED_DEVICE_UDID, "-b")


def prepare_simulator(udid: str) -> None:
    """Enforce the deterministic environment on the pinned reference device."""
    ensure_pinned_simulator(udid)
    simctl("ui", udid, "appearance", "light")
    simctl("ui", udid, "content_size", "large")
    simctl("ui", udid, "increase_contrast", "disabled")
    simctl(
        "spawn", udid, "defaults", "write", "com.apple.Accessibility",
        "ReduceMotionEnabled", "-bool", "YES",
    )
    simctl(
        "spawn", udid, "defaults", "write", "com.apple.Accessibility",
        "ReduceTransparencyEnabled", "-bool", "NO",
    )


def scene_crop(scene: dict) -> tuple:
    """The same shape-plus-margin crop the CLI comparator scores."""
    shape = scene["shape"]
    scale = scene["canvas"]["scale"]
    margin = 30
    return (
        round((shape["x"] - margin) * scale),
        round((shape["y"] - margin) * scale),
        round((shape["width"] + 2 * margin) * scale),
        round((shape["height"] + 2 * margin) * scale),
    )


def load_reference_probes(reference_dir: Path, crop: tuple) -> dict:
    x, y, width, height = crop
    return {
        probe: read_rgb(reference_dir / f"{probe}.png")[
            y : y + height, x : x + width
        ]
        for probe in PROBES
    }


class CaptureSession:
    """Lifecycle of the one persistent flutter run capture app."""

    def __init__(
        self,
        *,
        udid: str,
        flutter_bin: str,
        flutter_project: Path,
        scene_path: Path,
        work_dir: Path,
        readiness_timeout: float = 900.0,
        env: dict = None,
    ):
        self.udid = udid
        self.flutter_bin = flutter_bin
        self.flutter_project = flutter_project
        self.scene_path = scene_path
        self.work_dir = work_dir
        self.readiness_timeout = readiness_timeout
        self.env = env or os.environ.copy()
        self.session: FlutterRunSession = None
        self.candidate_path: Path = None
        self.status_path: Path = None
        self.startup_seconds = 0.0
        self.runtime_capabilities = {}

    def __enter__(self) -> "CaptureSession":
        started = time.monotonic()
        self.work_dir.mkdir(parents=True, exist_ok=True)
        prepare_simulator(self.udid)
        scene_b64 = base64.b64encode(self.scene_path.read_bytes()).decode()
        command = [
            self.flutter_bin,
            "run",
            "-d",
            self.udid,
            "--debug",
            "--enable-impeller",
            "--enable-flutter-gpu",
            f"--dart-define=SCENE_B64={scene_b64}",
            f"--pid-file={self.work_dir / 'flutter.pid'}",
            "--device-timeout=15",
        ]
        aa_width = self.env.get("LIQUID_GLASS_GEOMETRY_AA_HALF_WIDTH")
        if aa_width:
            command.append(
                f"--dart-define=LIQUID_GLASS_GEOMETRY_AA_HALF_WIDTH={aa_width}"
            )
        if self.env.get("LIQUID_GLASS_DISABLE_CANVAS_CONTOUR") == "1":
            command.append(
                "--dart-define=LIQUID_GLASS_DISABLE_CANVAS_CONTOUR=true"
            )
        self.session = FlutterRunSession.start(
            command, cwd=self.flutter_project, env=self.env
        )
        ready = self.session.wait_ready(timeout=self.readiness_timeout)
        self.runtime_capabilities = {
            "shaderFiltersSupported": ready.get("shaderFiltersSupported"),
        }
        if self.runtime_capabilities["shaderFiltersSupported"] is not True:
            self.session.terminate()
            raise SessionError(
                "Apple-match capture requires Impeller runtime shader filters; "
                f"runtime reported {self.runtime_capabilities}"
            )
        # The tool registers its SIGUSR1/SIGUSR2 handlers only once the VM
        # service is attached; signaling earlier kills the process.
        self.session.wait_for_output(
            ("Flutter run key commands", "Dart VM Service"), timeout=180.0
        )
        pid_file = self.work_dir / "flutter.pid"
        for _ in range(100):
            if pid_file.exists():
                self.session.trigger = SignalReloadTrigger(
                    int(pid_file.read_text().strip())
                )
                break
            time.sleep(0.1)
        candidate_path = Path(ready.get("candidatePath", ""))
        status_path = Path(ready.get("statusPath", ""))
        if not candidate_path.parent.exists():
            candidate_path, status_path = self._container_paths()
        self.candidate_path = candidate_path
        self.status_path = status_path
        self.startup_seconds = time.monotonic() - started
        return self

    def _container_paths(self) -> tuple:
        container = Path(simctl("get_app_container", self.udid, BUNDLE_ID, "data"))
        return (
            container / "tmp" / CANDIDATE_FILE_NAME,
            container / "tmp" / STATUS_FILE_NAME,
        )

    def refresh_paths(self) -> None:
        """Re-resolve the sandbox IPC paths from the current app container.

        A reinstall (e.g. the tool's hot restart after a lost connection, or
        a concurrent actor) rotates the data container UUID, invalidating
        paths captured at session start.
        """
        self.candidate_path, self.status_path = self._container_paths()

    def __exit__(self, exc_type, exc, traceback) -> None:
        if self.session is not None:
            (self.work_dir / "flutter-run.log").write_text(
                self.session.transport.tail_text()
            )
            self.session.terminate()
        subprocess.run(
            ["xcrun", "simctl", "terminate", self.udid, BUNDLE_ID], check=False
        )


class Evaluator:
    """Evaluate one settings dict to a scalar loss inside the live session.

    ``loss = 100 - score`` where score is the comparator's 0-100 match score,
    so lower is better. Screenshots land in ``capture_dir`` (overwritten each
    call; copy them away to keep a candidate).
    """

    def __init__(
        self,
        *,
        session: CaptureSession,
        reference: dict,
        crop: tuple,
        capture_dir: Path,
        settle_frames: int = 4,
        settle_timeout: float = 30.0,
        restart_timeout: float = 90.0,
        screenshot=None,
    ):
        self.session = session
        self.reference = reference
        self.crop = crop
        self.capture_dir = capture_dir
        self.settle_frames = settle_frames
        self.settle_timeout = settle_timeout
        self.restart_timeout = restart_timeout
        self._screenshot = screenshot or (
            lambda path: simctl("io", session.udid, "screenshot", str(path))
        )
        self._serial = 0
        self.evaluations = 0
        self.last_modes: dict = {}

    def evaluate(self, params: dict) -> float:
        validate_settings(params)
        started = time.monotonic()
        self.evaluations += 1
        self.capture_dir.mkdir(parents=True, exist_ok=True)
        images = {}
        modes = {}
        for probe in PROBES:
            self._serial += 1
            serial = self._serial
            candidate_id = f"eval-{serial:05d}"
            payload = {
                "candidateId": candidate_id,
                "probe": probe,
                "serial": serial,
                "settleFrames": self.settle_frames,
                "settings": params,
            }
            try:
                atomic_write_json(self.session.candidate_path, payload)
            except FileNotFoundError:
                # The data container rotated under us (reinstall); re-resolve.
                self.session.refresh_paths()
                atomic_write_json(self.session.candidate_path, payload)
            status = self.session.session.request_settle(
                candidate_id=candidate_id,
                probe=probe,
                serial=serial,
                read_status=lambda: read_json_file(self.session.status_path),
                settle_timeout=self.settle_timeout,
                restart_timeout=self.restart_timeout,
            )
            modes[probe] = status["reloadMode"]
            if status["reloadMode"] == "hotRestart":
                # A restart may reinstall the app, rotating the container.
                self.session.refresh_paths()
            png = self.capture_dir / f"{probe}.png"
            self._screenshot(png)
            images[probe] = self._read_cropped(png)
        self.last_modes = modes
        result = score_images(self.reference, images)
        self.last_images = images
        self.last_result = result
        self.last_score = result.score
        self.last_seconds = time.monotonic() - started
        return 100.0 - result.score

    def _read_cropped(self, png: Path):
        x, y, width, height = self.crop
        return read_rgb(png)[y : y + height, x : x + width]
