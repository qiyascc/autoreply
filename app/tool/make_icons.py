#!/usr/bin/env python3
"""Generates the Autoreply app mark and every Android density it needs.

The mark: a speech bubble carrying the iOS missed-call arrow — the whole product in
one glyph, "a call you missed turns into a message you sent". Everything is drawn at
4x and downsampled, which gives clean antialiasing without shipping a rasteriser.

    python3 tool/make_icons.py
"""
from __future__ import annotations

import math
import os
from PIL import Image, ImageDraw

S = 4  # supersampling factor
BASE = 1024
HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
RES = os.path.join(APP, "android", "app", "src", "main", "res")

# Apple-ish blue ramp, slightly deeper at the bottom so the icon has weight.
TOP = (10, 132, 255)
BOTTOM = (0, 58, 194)
ACCENT = (255, 159, 10)  # the missed-call arrow reads warm against the blue


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel(
            (0, y),
            tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return grad.resize((size, size), Image.BICUBIC)


def bubble_and_arrow(draw: ImageDraw.ImageDraw, size: int, bubble_fill, arrow_fill) -> None:
    """Draws the speech bubble plus missed-call arrow, scaled to a `size` box."""
    u = size / 100.0  # work in percentage units

    # Speech bubble body.
    left, top, right, bottom = 16 * u, 20 * u, 84 * u, 68 * u
    draw.rounded_rectangle([left, top, right, bottom], radius=14 * u, fill=bubble_fill)

    # Tail: a soft triangle hanging off the lower-left, angled like iMessage.
    draw.polygon(
        [(32 * u, bottom - 2 * u), (52 * u, bottom - 2 * u), (30 * u, 84 * u)],
        fill=bubble_fill,
    )

    # Missed-call arrow: a thick diagonal from upper-right to lower-left with a
    # two-stroke head, matching the glyph iOS puts next to a missed call.
    x1, y1 = 62 * u, 32 * u
    x2, y2 = 38 * u, 56 * u
    w = int(round(7 * u))
    draw.line([(x1, y1), (x2, y2)], fill=arrow_fill, width=w)
    # Rounded joints so the stroke does not look chiselled at this size.
    r = w / 2
    for (cx, cy) in ((x1, y1), (x2, y2)):
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=arrow_fill)

    head = 17 * u
    for dx, dy in ((head, 0), (0, -head)):
        ex, ey = x2 + dx, y2 + dy
        draw.line([(x2, y2), (ex, ey)], fill=arrow_fill, width=w)
        draw.ellipse([ex - r, ey - r, ex + r, ey + r], fill=arrow_fill)


def make_launcher(size: int, rounded: bool = True) -> Image.Image:
    big = size * S
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    bg = vertical_gradient(big, TOP, BOTTOM).convert("RGBA")
    if rounded:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, big - 1, big - 1], radius=int(big * 0.225), fill=255
        )
        img.paste(bg, (0, 0), mask)
    else:
        img.paste(bg, (0, 0))

    bubble_and_arrow(ImageDraw.Draw(img), big, (255, 255, 255, 255), ACCENT + (255,))
    return img.resize((size, size), Image.LANCZOS)


def make_adaptive_foreground(size: int) -> Image.Image:
    """Adaptive icons crop to a circle, so the glyph sits in the safe inner 66%."""
    big = size * S
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    inner = int(big * 0.62)
    layer = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    bubble_and_arrow(ImageDraw.Draw(layer), inner, (255, 255, 255, 255), ACCENT + (255,))
    img.paste(layer, ((big - inner) // 2, (big - inner) // 2), layer)
    return img.resize((size, size), Image.LANCZOS)


def make_adaptive_background(size: int) -> Image.Image:
    big = size * S
    return vertical_gradient(big, TOP, BOTTOM).convert("RGBA").resize((size, size), Image.LANCZOS)


def make_notification(size: int) -> Image.Image:
    """Status-bar icons must be a white silhouette on transparent; Android tints them."""
    big = size * S
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    inner = int(big * 0.86)
    layer = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    u = inner / 100.0
    d.rounded_rectangle([16 * u, 20 * u, 84 * u, 68 * u], radius=14 * u,
                        outline=(255, 255, 255, 255), width=int(6 * u))
    d.polygon([(32 * u, 66 * u), (52 * u, 66 * u), (30 * u, 84 * u)], fill=(255, 255, 255, 255))
    x1, y1, x2, y2 = 62 * u, 32 * u, 38 * u, 56 * u
    w = int(round(6 * u))
    d.line([(x1, y1), (x2, y2)], fill=(255, 255, 255, 255), width=w)
    for dx, dy in ((15 * u, 0), (0, -15 * u)):
        d.line([(x2, y2), (x2 + dx, y2 + dy)], fill=(255, 255, 255, 255), width=w)
    img.paste(layer, ((big - inner) // 2, (big - inner) // 2), layer)
    return img.resize((size, size), Image.LANCZOS)


DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def main() -> None:
    for bucket, px in DENSITIES.items():
        out = os.path.join(RES, f"mipmap-{bucket}")
        os.makedirs(out, exist_ok=True)
        make_launcher(px).save(os.path.join(out, "ic_launcher.png"))
        make_adaptive_foreground(px * 2).save(os.path.join(out, "ic_launcher_foreground.png"))
        make_adaptive_background(px * 2).save(os.path.join(out, "ic_launcher_background.png"))

        drawable = os.path.join(RES, f"drawable-{bucket}")
        os.makedirs(drawable, exist_ok=True)
        make_notification(max(24, px // 2)).save(os.path.join(drawable, "ic_stat_autoreply.png"))

    # Play-store / about-screen artwork.
    assets = os.path.join(APP, "assets", "brand")
    os.makedirs(assets, exist_ok=True)
    make_launcher(512).save(os.path.join(assets, "icon_512.png"))
    make_launcher(1024).save(os.path.join(assets, "icon_1024.png"))
    make_launcher(256).save(os.path.join(assets, "icon_256.png"))

    print("icons written to", RES)


if __name__ == "__main__":
    main()
