"""Crops the captures of test/readme_screenshots_test.dart for the README.

Usage: python3 tool/crop_readme_screenshots.py /tmp/readme-shots ../doc/readme

Crops are given in logical pixels of the 402 x 874 pt iPhone 17 Pro screen;
the captures are 3x. Requires Pillow.
"""

import sys
from pathlib import Path

from PIL import Image

SCALE = 3

# name: (capture scene, left, top, right, bottom) in logical pixels.
CROPS = {
    "bottom-bar": ("controls", 0, 786, 402, 874),
    "bottom-bar-fake": ("controls-fake", 0, 786, 402, 874),
    "controls": ("controls", 0, 40, 402, 140),
    "blend": ("blend", 50, 350, 370, 570),
    "colors": ("colors", 70, 345, 332, 590),
    "loupe": ("loupe", 0, 170, 402, 470),
}


def main(source: Path, target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    for name, (scene, *box) in CROPS.items():
        for brightness in ("light", "dark"):
            image = Image.open(source / f"{scene}-{brightness}.png").convert("RGB")
            cropped = image.crop(tuple(v * SCALE for v in box))
            out = target / f"{name}-{brightness}.jpg"
            cropped.save(out, quality=86, optimize=True, progressive=True)
            print(f"{out} {cropped.size[0]}x{cropped.size[1]} "
                  f"{out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
