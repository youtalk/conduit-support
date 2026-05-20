"""Generate the OpenGraph share image (1200x630) for conduit.youtalk.jp.

Renders the same visual language as the in-app hero:
- App icon on the left at App-icon scale
- Gradient backdrop (Apple Blue -> Indigo with subtle blue/purple haze)
- Tagline in SF Pro Rounded if available, otherwise system fallback
- Soft glass card containing the tagline

Output: docs/assets/img/og-card.png

Run manually (not part of MkDocs build) so the image is committed:

    python scripts/generate_og_image.py
"""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "docs" / "assets" / "img" / "app_icon.png"
OUT = ROOT / "docs" / "assets" / "img" / "og-card.png"

WIDTH, HEIGHT = 1200, 630


def _font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    """Best-effort SF Pro Rounded; otherwise a reasonable system fallback."""
    candidates = [
        f"/System/Library/Fonts/SF-Pro-Rounded-{weight}.otf",
        f"/System/Library/Fonts/SFNSRounded.ttf",
        f"/Library/Fonts/SF-Pro-Rounded-{weight}.otf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def _radial(size: tuple[int, int], color: tuple[int, int, int, int],
            center: tuple[float, float], radius: float) -> Image.Image:
    """A radial gradient on a transparent canvas, centred at `center`."""
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    cx, cy = center[0] * w, center[1] * h
    r, g, b, a_max = color
    # 1px mask scaled up — much faster than per-pixel loops.
    mask = Image.new("L", size, 0)
    md = ImageDraw.Draw(mask)
    steps = 22
    for i in range(steps, 0, -1):
        rad = radius * (i / steps)
        alpha = int(a_max * (1 - i / steps) ** 1.6)
        md.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=alpha)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=radius * 0.18))
    tint = Image.new("RGBA", size, (r, g, b, 255))
    img.paste(tint, (0, 0), mask)
    return img


def build() -> None:
    # Apple gradient background (top-left → bottom-right blue -> indigo)
    bg = Image.new("RGB", (WIDTH, HEIGHT), (245, 245, 247))
    grad = Image.new("RGB", (WIDTH, HEIGHT))
    g_px = grad.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            t = (x / WIDTH * 0.55 + y / HEIGHT * 0.45)
            r = int(0 * (1 - t) + 88 * t)
            g = int(122 * (1 - t) + 86 * t)
            b = int(255 * (1 - t) + 214 * t)
            g_px[x, y] = (r, g, b)
    bg = grad

    # Atmospheric blurred orbs for depth.
    bg = Image.alpha_composite(
        bg.convert("RGBA"),
        _radial((WIDTH, HEIGHT), (0, 122, 255, 180), (0.08, 0.10), 520),
    )
    bg = Image.alpha_composite(
        bg, _radial((WIDTH, HEIGHT), (175, 82, 222, 160), (0.92, 0.18), 460),
    )
    bg = Image.alpha_composite(
        bg, _radial((WIDTH, HEIGHT), (48, 176, 199, 140), (0.85, 0.92), 480),
    )

    draw = ImageDraw.Draw(bg)

    # ----- Glass card (frosted panel containing the headline) -----
    card_pad = 60
    card = (card_pad, card_pad, WIDTH - card_pad, HEIGHT - card_pad)
    card_img = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    cdraw = ImageDraw.Draw(card_img)
    cdraw.rounded_rectangle(card, radius=44, fill=(255, 255, 255, 64))
    cdraw.rounded_rectangle(card, radius=44, outline=(255, 255, 255, 140), width=2)
    bg = Image.alpha_composite(bg, card_img)
    draw = ImageDraw.Draw(bg)

    # ----- App icon -----
    icon_size = 220
    icon = Image.open(ICON).convert("RGBA")
    icon = icon.resize((icon_size, icon_size), Image.LANCZOS)

    # Round the corners.
    rmask = Image.new("L", (icon_size, icon_size), 0)
    ImageDraw.Draw(rmask).rounded_rectangle(
        (0, 0, icon_size, icon_size), radius=int(icon_size * 0.225), fill=255
    )
    icon.putalpha(rmask)

    # Soft shadow under the icon.
    shadow = Image.new("RGBA", (icon_size + 80, icon_size + 80), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (40, 50, icon_size + 40, icon_size + 50),
        radius=int(icon_size * 0.225), fill=(0, 60, 200, 160),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    bg.alpha_composite(shadow, dest=(120 - 40, 180 - 40))
    bg.alpha_composite(icon, dest=(120, 180))

    # ----- Text -----
    eyebrow = _font(28, "Semibold")
    title   = _font(112, "Bold")
    sub     = _font(34, "Regular")
    foot    = _font(26, "Medium")

    text_x = 380
    draw.text((text_x, 180), "APPLE-NATIVE · ROS 2", font=eyebrow,
              fill=(255, 255, 255, 230))
    draw.text((text_x, 220), "Conduit", font=title, fill=(255, 255, 255, 255))
    draw.text((text_x, 360),
              "Stream 12 real-time sensors from iPhone,\n"
              "iPad, Mac, and Apple Vision Pro into ROS 2.",
              font=sub, fill=(255, 255, 255, 235), spacing=10)
    draw.text((text_x, 500), "conduit.youtalk.jp", font=foot,
              fill=(255, 255, 255, 200))

    bg.convert("RGB").save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    build()
