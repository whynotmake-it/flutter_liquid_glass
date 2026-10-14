"""Composes the figures of docs/liquid-glass-rewrite.md.

Usage, from example/:

    python3 tool/compose_blog_figures.py /tmp/blog-figures /tmp/apple-refs \\
        ../../../docs/assets/liquid-glass-rewrite

The first argument holds the captures of test/blog_figures_test.dart. The
cover is made by tool/blog_cover.py. The second holds the Apple references
of the two comparison scenes, materialized from Git LFS as
<scene>/<probe>.png. Our side of the comparisons and the bridge crops are the
frozen inputs under the target's raw/ directory and merge-bridge-variants.png.
The pipeline and render-pass diagrams are drawn here.

Only crops, rounded corners, shadows and labels are added. Glass pixels are
never retouched; comparison panels are cropped from the same coordinates and
the difference is the plain per-channel absolute difference, not amplified.
Styling (paper grain, Space Grotesk) comes from blog_cover.py.
Requires Pillow and NumPy.
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

import blog_cover
from blog_cover import BLUE, PAPER

SCALE = 3
BACKGROUND = PAPER
INK = blog_cover.INK
MUTED = (96, 92, 86)


def font(size: int, weight: str = "Medium") -> ImageFont.FreeTypeFont:
    return blog_cover.font_px(size, weight)


def paper(size) -> Image.Image:
    """The whynotmake.it paper: off-white with grain."""
    return blog_cover.grain(Image.new("RGB", size, PAPER), strength=5).convert("RGBA")


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1), radius, fill=255
    )
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def drop(canvas: Image.Image, tile: Image.Image, xy, blur=28, offset=14, alpha=60):
    """Pastes [tile] with a soft shadow beneath it."""
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    silhouette = Image.new("RGBA", tile.size, (0, 0, 0, alpha))
    silhouette.putalpha(tile.getchannel("A").point(lambda a: a * alpha // 255))
    shadow.paste(silhouette, (xy[0], xy[1] + offset), silhouette)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(tile, xy)


def crop(image: Image.Image, box) -> Image.Image:
    return image.crop(tuple(v * SCALE for v in box))


def phone(screen: Image.Image, width: int) -> Image.Image:
    """A bezel around a full-screen capture, scaled to [width]."""
    bezel = round(width * 0.035)
    inner = width - 2 * bezel
    screen = screen.convert("RGB").resize(
        (inner, round(screen.height * inner / screen.width)), Image.LANCZOS
    )
    radius = round(inner * 0.137)
    body = Image.new("RGBA", (width, screen.height + 2 * bezel), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        (0, 0, body.width - 1, body.height - 1),
        radius + bezel,
        fill=(18, 18, 20, 255),
    )
    body.alpha_composite(rounded(screen, radius), (bezel, bezel))
    return body


def save(image: Image.Image, path: Path) -> None:
    image = image.convert("RGB")
    if path.suffix == ".jpg":
        image.save(path, quality=88, optimize=True, progressive=True)
    else:
        image.save(path, optimize=True)
    print(f"{path.name} {image.width}x{image.height} {path.stat().st_size // 1024} KB")


def phones(figures: Path, names, target: Path, width=640, gap=120, pad=110):
    tiles = [phone(Image.open(figures / f"{name}.png"), width) for name in names]
    canvas = paper(
        (pad * 2 + width * len(tiles) + gap * (len(tiles) - 1), tiles[0].height + pad * 2)
    )
    for index, tile in enumerate(tiles):
        drop(canvas, tile, (pad + index * (width + gap), pad), blur=40, offset=24, alpha=70)
    save(canvas, target)


def tiles(images, target: Path, radius=36, gap=40, pad=60):
    rounded_tiles = [rounded(image.convert("RGB"), radius) for image in images]
    height = max(tile.height for tile in rounded_tiles)
    width = sum(tile.width for tile in rounded_tiles) + gap * (len(rounded_tiles) - 1)
    canvas = paper((width + pad * 2, height + pad * 2))
    x = pad
    for tile in rounded_tiles:
        drop(canvas, tile, (x, pad), blur=24, offset=12, alpha=50)
        x += tile.width + gap
    save(canvas, target)


def comparison(apple: Path, ours: dict, box, target: Path, tile_width=600):
    """Rows of probes: Apple, ours and their unamplified difference."""
    columns = ["iOS 27", "liquid_glass_renderer", "Difference"]
    labels = {"A": "Colour grid", "C": "Black", "D": "White"}
    rows = []
    for probe, path in ours.items():
        a = Image.open(apple / f"{probe}.png").convert("RGB").crop(box)
        b = Image.open(path).convert("RGB").crop(box)
        rows.append((labels[probe], [a, b, ImageChops.difference(a, b)]))
    scale = tile_width / rows[0][1][0].width
    size = (tile_width, round(rows[0][1][0].height * scale))
    gap, pad, header, side = 28, 60, 84, 230
    canvas = paper(
        (
            pad * 2 + side + 3 * size[0] + 2 * gap,
            pad + header + len(rows) * (size[1] + gap) - gap + pad,
        )
    )
    draw = ImageDraw.Draw(canvas)
    for column, text in enumerate(columns):
        draw.text(
            (pad + side + column * (size[0] + gap) + size[0] / 2, pad + 26),
            text,
            font=font(34),
            fill=INK if column < 2 else MUTED,
            anchor="mm",
        )
    for row, (label, images) in enumerate(rows):
        y = pad + header + row * (size[1] + gap)
        draw.text(
            (pad, y + size[1] / 2), label, font=font(30), fill=MUTED, anchor="lm"
        )
        for column, image in enumerate(images):
            tile = rounded(image.resize(size, Image.LANCZOS), 22)
            drop(
                canvas,
                tile,
                (pad + side + column * (size[0] + gap), y),
                blur=14,
                offset=6,
                alpha=40,
            )
    save(canvas, target)


def bridges(source: Path, target: Path):
    """Restyles the frozen bridge crops (Apple, then blend 28 to 40)."""
    frozen = Image.open(source).convert("RGB")
    labels = ["iOS 27", "28", "32", "36", "40"]
    crops = [frozen.crop((16 + 380 * i, 66, 376 + 380 * i, 436)) for i in range(5)]
    gap, pad, header = 28, 50, 70
    w, h = crops[0].size
    canvas = paper((pad * 2 + 5 * w + 4 * gap + 40, pad + header + h + pad))
    draw = ImageDraw.Draw(canvas)
    for index, (image, text) in enumerate(zip(crops, labels)):
        x = pad + index * (w + gap) + (40 if index else 0)
        draw.text(
            (x + w / 2, pad + 20),
            text if index == 0 else f"blend {text}",
            font=font(30, "Bold" if index in (0, 2) else "Medium"),
            fill=INK if index in (0, 2) else MUTED,
            anchor="mm",
        )
        canvas.alpha_composite(rounded(image, 18), (x, pad + header))
    draw.line(
        (pad + w + gap / 2 + 20, pad + header, pad + w + gap / 2 + 20, pad + header + h),
        fill=(200, 194, 184),
        width=3,
    )
    save(canvas, target)


TEAL = BLUE
AMBER = (232, 92, 84)


def box(draw, xy, title, subtitle, accent, fill=(255, 253, 248)):
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, 28, fill=fill, outline=accent, width=6)
    cx = (x0 + x1) / 2
    draw.text((cx, y0 + 62), title, font=font(40, "Bold"), fill=INK, anchor="mm")
    for index, line in enumerate(subtitle.split("\n")):
        draw.text(
            (cx, y0 + 116 + index * 42), line, font=font(30, "Regular"),
            fill=MUTED, anchor="mm",
        )


def arrow(draw, points, color=INK, width=5):
    draw.line(points, fill=color, width=width, joint="curve")
    (x0, y0), (x1, y1) = points[-2], points[-1]
    if x1 != x0:
        d = 1 if x1 > x0 else -1
        head = [(x1, y1), (x1 - 22 * d, y1 - 13), (x1 - 22 * d, y1 + 13)]
    else:
        d = 1 if y1 > y0 else -1
        head = [(x1, y1), (x1 - 13, y1 - 22 * d), (x1 + 13, y1 - 22 * d)]
    draw.polygon(head, fill=color)


def tag(draw, xy, text, color):
    w = draw.textlength(text, font=font(26, "Bold")) + 36
    x, y = xy
    draw.rounded_rectangle((x - w / 2, y - 22, x + w / 2, y + 22), 22, fill=color)
    draw.text((x, y), text, font=font(26, "Bold"), fill=(255, 255, 255), anchor="mm")


def pipeline(target: Path):
    canvas = paper((2200, 960))
    draw = ImageDraw.Draw(canvas)
    w, h = 440, 220
    shapes = (100, 120, 100 + w, 120 + h)
    matte = (900, 120, 900 + w, 120 + h)
    backdrop = (100, 620, 100 + w, 620 + h)
    final = (900, 620, 900 + w, 620 + h)
    frame = (1660, 620, 1660 + w, 620 + h)
    box(draw, shapes, "Shapes", "position, size,\ncorner radius", TEAL)
    box(draw, matte, "Matte", "edge distance, surface\ndirection, offset", TEAL)
    box(draw, backdrop, "Background", "whatever is\nbehind the glass", AMBER)
    box(draw, final, "Final shader", "bend, tint, light", INK)
    box(draw, frame, "Screen", "the finished pixels", INK)
    arrow(draw, [(shapes[2], 230), (matte[0] - 4, 230)])
    arrow(draw, [((matte[0] + matte[2]) / 2, matte[3]), ((matte[0] + matte[2]) / 2, final[1] - 4)])
    arrow(draw, [(backdrop[2], 730), (final[0] - 4, 730)])
    arrow(draw, [(final[2], 730), (frame[0] - 4, 730)])
    tag(draw, ((shapes[2] + matte[0]) / 2, 176), "when a shape changes", TEAL)
    tag(draw, ((backdrop[2] + final[0]) / 2, 676), "every frame", AMBER)
    draw.text(
        (matte[2] + 60, 230),
        "Kept between frames.\nA scroll behind still\nglass never touches it.",
        font=font(30, "Regular"), fill=MUTED, anchor="lm", spacing=12,
    )
    save(canvas, target)


def passes(target: Path):
    canvas = paper((2200, 1100))
    draw = ImageDraw.Draw(canvas)
    draw.text((100, 110), "Render passes for two blurred panels",
              font=font(52, "Bold"), fill=INK, anchor="lm")
    draw.text((100, 180), "Predicted by impeeler and confirmed in GPU traces, Flutter 3.47.1",
              font=font(32, "Regular"), fill=MUTED, anchor="lm")
    base, unit = 900, 46
    groups = [("Metal, M4 Max", 11, 5), ("Pixel 10, Vulkan", 12, 6)]
    for index, (label, separate, shared) in enumerate(groups):
        x = 260 + index * 1000
        for offset, value, color, name in [
            (0, separate, AMBER, "separate"),
            (330, shared, TEAL, "shared backdrop"),
        ]:
            x0 = x + offset
            draw.rounded_rectangle((x0, base - value * unit, x0 + 240, base), 20, fill=color)
            draw.rectangle((x0, base - 20, x0 + 240, base), fill=color)
            draw.text((x0 + 120, base - value * unit - 44), str(value),
                      font=font(56, "Bold"), fill=INK, anchor="mm")
            draw.text((x0 + 120, base + 44), name, font=font(30, "Regular"),
                      fill=MUTED, anchor="mm")
        draw.text((x + 285, base + 110), label, font=font(36, "Bold"), fill=INK, anchor="mm")
    draw.line((160, base, 2040, base), fill=INK, width=5)
    save(canvas, target)


def main(figures: Path, apple: Path, target: Path) -> None:
    pipeline(target / "pipeline.jpg")
    passes(target / "render-passes.jpg")
    raw = target / "raw"
    phones(figures, ["controls-light", "controls-dark"], target / "hero-controls.jpg")
    tiles(
        [
            crop(Image.open(figures / "blend-light.png"), (21, 352, 381, 580)),
            crop(Image.open(figures / "blend-dark.png"), (21, 352, 381, 580)),
        ],
        target / "hero-blend.jpg",
    )
    tiles(
        [crop(Image.open(figures / "colors-light.png"), (36, 292, 366, 612))],
        target / "hero-colors.jpg",
    )
    tiles(
        [crop(Image.open(figures / "loupe-light.png"), (0, 40, 402, 408))],
        target / "hero-loupe.jpg",
    )
    comparison(
        apple / "toolbar_capsule",
        {p: raw / f"toolbar-fitted-{p}.png" for p in "ACD"},
        (210, 1110, 996, 1518),
        target / "toolbar-comparison.jpg",
    )
    comparison(
        apple / "merge_equal_rects_gap",
        {p: raw / f"merge-blend32-{p}.png" for p in "ACD"},
        (177, 1143, 1029, 1479),
        target / "merge-comparison.jpg",
    )
    bridges(target / "merge-bridge-variants.png", target / "merge-bridges.jpg")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
