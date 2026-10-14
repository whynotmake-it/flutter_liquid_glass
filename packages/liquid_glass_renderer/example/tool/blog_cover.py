"""Background and ink overlay of the cover of docs/liquid-glass-rewrite.md.

The cover follows the whynotmake.it look: a flat paper-grain color, chunky
off-white type and hand-drawn black ink. The glass in between is rendered by
test/blog_cover_test.dart, so the headline is refracted by the real renderer.

From example/:

    python3 tool/blog_cover.py background /tmp/cover-background.png
    flutter test --enable-impeller --enable-flutter-gpu \\
      --dart-define=BLOG_COVER_BACKGROUND=/tmp/cover-background.png \\
      --dart-define=BLOG_COVER_OUT=/tmp/cover-glass.png test/blog_cover_test.dart
    python3 tool/blog_cover.py overlay /tmp/cover-glass.png \\
      ../../../docs/assets/liquid-glass-rewrite/cover.jpg

The headline font, Space Grotesk (SIL Open Font License), is downloaded to
~/.cache on first use. Requires Pillow and NumPy.
"""

import math
import random
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Logical 1200 x 630 at 2x. Glass positions in blog_cover_test.dart use the
# same logical coordinates.
SCALE = 2
SIZE = (1200 * SCALE, 630 * SCALE)
BLUE = (99, 149, 236)
PAPER = (244, 240, 232)
INK = (22, 22, 24)

_FONT_URL = (
    "https://github.com/google/fonts/raw/main/ofl/spacegrotesk/"
    "SpaceGrotesk%5Bwght%5D.ttf"
)
_FONT = Path.home() / ".cache/liquid_glass_blog/SpaceGrotesk.ttf"


def font_px(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    """Space Grotesk at [size] pixels."""
    if not _FONT.exists():
        _FONT.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(_FONT_URL, _FONT)
    result = ImageFont.truetype(str(_FONT), size)
    result.set_variation_by_name(weight)
    return result


def font(size: float, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    return font_px(round(size * SCALE), weight)


def grain(image: Image.Image, strength: float = 9, seed: int = 7) -> Image.Image:
    """Paper grain: fine noise plus a few darker flecks."""
    rng = np.random.default_rng(seed)
    pixels = np.asarray(image.convert("RGB")).astype(np.float32)
    h, w, _ = pixels.shape
    noise = rng.normal(0, strength, (h // 2, w // 2)).astype(np.float32)
    noise = np.asarray(
        Image.fromarray(noise).resize((w, h), Image.BILINEAR)
    )
    pixels += noise[..., None]
    flecks = rng.random((h, w)) > 0.9994
    pixels[flecks] *= 0.7
    return Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))


def _catmull_rom(points, steps=24):
    out = []
    padded = [points[0], *points, points[-1]]
    for i in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[i - 1 : i + 3]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(
                tuple(
                    0.5
                    * (
                        2 * p1[k]
                        + (-p0[k] + p2[k]) * t
                        + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                        + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3
                    )
                    for k in range(2)
                )
            )
    out.append(points[-1])
    return out


def ink(draw: ImageDraw.ImageDraw, points, width=3.2, seed=1, wobble=1.6):
    """A hand-drawn pen stroke through logical [points]."""
    rng = random.Random(seed)
    coarse = _catmull_rom([(x * SCALE, y * SCALE) for x, y in points])
    path = []
    for (x0, y0), (x1, y1) in zip(coarse, coarse[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0)))
        path += [(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n) for i in range(n)]
    path.append(coarse[-1])
    phase = rng.random() * 10
    for index, (x, y) in enumerate(path):
        t = index / max(1, len(path) - 1)
        jitter = math.sin(index * 0.012 + phase) * wobble * SCALE
        taper = 0.75 + 0.25 * math.sin(math.pi * t)
        r = width * SCALE * taper / 2 * rng.uniform(0.9, 1.1)
        draw.ellipse(
            (x - r, y + jitter - r, x + r, y + jitter + r), fill=INK
        )


def arrowhead(draw, tip, direction, size=16, seed=3):
    """Two short strokes at logical [tip], pointing along [direction]."""
    angle = math.atan2(direction[1], direction[0])
    for side in (-1, 1):
        a = angle + math.pi - side * 0.5
        end = (tip[0] + math.cos(a) * size, tip[1] + math.sin(a) * size)
        ink(draw, [tip, end], width=3.2, seed=seed + side, wobble=0.4)


def background(target: Path) -> None:
    image = Image.new("RGB", SIZE, BLUE)
    draw = ImageDraw.Draw(image)
    draw.text(
        (84 * SCALE, 96 * SCALE),
        "liquid_glass_renderer",
        font=font(30, "Medium"),
        fill=PAPER,
    )
    headline = font(150)
    draw.text((76 * SCALE, 150 * SCALE), "Liquid glass,", font=headline, fill=PAPER)
    draw.text((76 * SCALE, 320 * SCALE), "rebuilt.", font=headline, fill=PAPER)
    ink(
        draw,
        [(80, 492), (300, 486), (560, 494), (720, 488)],
        width=3.4,
        seed=11,
    )
    grain(image).save(target)


def overlay(source: Path, target: Path) -> None:
    image = Image.open(source).convert("RGB")
    draw = ImageDraw.Draw(image)
    # A loop around the version, with an arrow to the glass.
    ink(
        draw,
        [(806, 556), (870, 526), (1010, 528), (1060, 556), (1000, 590),
         (860, 592), (800, 566), (840, 532)],
        width=3,
        seed=21,
    )
    draw.text(
        (933 * SCALE, 559 * SCALE),
        "1.0.0-dev.0",
        font=font(34, "Bold"),
        fill=PAPER,
        anchor="mm",
    )
    stroke = [(1068, 540), (1104, 508), (1106, 470), (1080, 442)]
    ink(draw, stroke, width=3, seed=31)
    arrowhead(
        draw,
        stroke[-1],
        (stroke[-1][0] - stroke[-2][0], stroke[-1][1] - stroke[-2][1]),
    )
    image.save(target, quality=90, optimize=True, progressive=True)
    print(f"{target} {image.width}x{image.height}")


if __name__ == "__main__":
    command, *paths = sys.argv[1:]
    if command == "background":
        background(Path(paths[0]))
    elif command == "overlay":
        overlay(Path(paths[0]), Path(paths[1]))
    else:
        raise SystemExit(__doc__)
