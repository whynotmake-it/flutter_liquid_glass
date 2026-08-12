#!/usr/bin/env python3
"""Write a deterministic per-channel median of equally sized PNG frames."""

import argparse
from pathlib import Path

import cv2
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("inputs", nargs="+", type=Path)
args = parser.parse_args()
images = [cv2.imread(str(path), cv2.IMREAD_COLOR) for path in args.inputs]
if any(image is None for image in images):
    raise SystemExit("one or more capture frames could not be read")
if len({image.shape for image in images}) != 1:
    raise SystemExit("capture frames have different dimensions")
median = np.median(np.stack(images), axis=0).astype(np.uint8)
args.output.parent.mkdir(parents=True, exist_ok=True)
if not cv2.imwrite(str(args.output), median):
    raise SystemExit(f"could not write {args.output}")
