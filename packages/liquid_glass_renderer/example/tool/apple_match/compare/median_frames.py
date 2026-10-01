"""Write the per-pixel median of a small deterministic PNG frame set."""

from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: median_frames.py OUTPUT INPUT [INPUT ...]")
    output = Path(sys.argv[1])
    frames = [cv2.imread(path, cv2.IMREAD_UNCHANGED) for path in sys.argv[2:]]
    if not frames or any(frame is None for frame in frames):
        raise SystemExit("could not read all input frames")
    first = frames[0]
    if any(frame.shape != first.shape for frame in frames[1:]):
        raise SystemExit("input frames have different dimensions")
    median = np.rint(np.median(np.stack(frames, axis=0), axis=0)).astype(
        first.dtype
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(output), median):
        raise SystemExit(f"could not write {output}")


if __name__ == "__main__":
    main()
