"""Generate the OpenGraph share image (1200x630) for conduit.youtalk.jp.

Layout:
- Plain white background — no tint, no gradient mesh, no glass card.
- App icon on the left at its native rounded-square shape (no drop shadow).
- "Conduit" rendered in the heaviest SF Pro Rounded weight available,
  filled with the Apple Blue → Indigo gradient.
- Subtitle and footer in muted dark gray.

Output: docs/assets/img/og-card.png (committed; not part of MkDocs build).

Re-run after editing:

    python scripts/generate_og_image.py
"""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "docs" / "assets" / "img" / "app_icon.png"
OUT = ROOT / "docs" / "assets" / "img" / "og-card.png"

WIDTH, HEIGHT = 1200, 630

# Apple system palette (matches docs/assets/css/conduit.css).
BLUE   = (0, 122, 255)
INDIGO = (88, 86, 214)
LABEL  = (29, 29, 31)      # #1d1d1f
LABEL2 = (110, 110, 115)   # SF secondary-label-ish


def _font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    """SF Pro Rounded at the requested named weight, with safe fallbacks.

    On modern macOS the rounded family ships as a single variable font
    (``SFNSRounded.ttf``) whose default variation is Regular — opening it
    via ``ImageFont.truetype`` without selecting a named variation silently
    gives Regular weight regardless of what the caller asked for. We pick
    the matching named instance via ``set_variation_by_name``.
    """
    weight_chain = {
        "Heavy":    ["Heavy", "Black", "Bold"],
        "Black":    ["Black", "Heavy", "Bold"],
        "Bold":     ["Bold", "Heavy"],
        "Semibold": ["Semibold", "Bold"],
        "Medium":   ["Medium", "Semibold", "Regular"],
        "Regular":  ["Regular", "Medium"],
    }
    weights = weight_chain.get(weight, [weight])

    # 1) Discrete OTF files (older Apple installs, custom installs).
    for w in weights:
        for path in (
            f"/System/Library/Fonts/SF-Pro-Rounded-{w}.otf",
            f"/Library/Fonts/SF-Pro-Rounded-{w}.otf",
        ):
            if os.path.exists(path):
                try:
                    return ImageFont.truetype(path, size)
                except OSError:
                    continue

    # 2) Variable font with named instances (default on modern macOS).
    for path in ("/System/Library/Fonts/SFNSRounded.ttf",
                 "/System/Library/Fonts/SFCompactRounded.ttf"):
        if not os.path.exists(path):
            continue
        try:
            f = ImageFont.truetype(path, size)
        except OSError:
            continue
        try:
            names = {n.decode("ascii", "ignore") for n in f.get_variation_names()}
        except (OSError, AttributeError):
            names = set()
        for w in weights:
            if w in names:
                try:
                    f.set_variation_by_name(w)
                except (OSError, AttributeError):
                    pass
                return f
        return f

    # 3) Last resort.
    for fallback in ("/System/Library/Fonts/Helvetica.ttc",
                     "/Library/Fonts/Arial Unicode.ttf"):
        if os.path.exists(fallback):
            try:
                return ImageFont.truetype(fallback, size)
            except OSError:
                continue
    return ImageFont.load_default()


def _gradient_text(
    text: str,
    font: ImageFont.FreeTypeFont,
    color_start: tuple[int, int, int],
    color_end: tuple[int, int, int],
) -> Image.Image:
    """Render `text` filled with a horizontal gradient.

    Returns a tight RGBA image just big enough to hold the glyphs.
    """
    # Probe the bounding box on a throwaway canvas.
    probe = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    pd = ImageDraw.Draw(probe)
    bbox = pd.textbbox((0, 0), text, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    # Add a tiny pad so descenders / anti-aliasing aren't clipped.
    pad_x, pad_y = 4, 6
    canvas_w, canvas_h = w + pad_x * 2, h + pad_y * 2

    # 1. Build the gradient fill.
    grad = Image.new("RGB", (canvas_w, canvas_h))
    g_px = grad.load()
    for x in range(canvas_w):
        t = x / max(canvas_w - 1, 1)
        r = int(color_start[0] * (1 - t) + color_end[0] * t)
        g = int(color_start[1] * (1 - t) + color_end[1] * t)
        b = int(color_start[2] * (1 - t) + color_end[2] * t)
        for y in range(canvas_h):
            g_px[x, y] = (r, g, b)

    # 2. Build the text alpha mask.
    mask = Image.new("L", (canvas_w, canvas_h), 0)
    md = ImageDraw.Draw(mask)
    md.text((pad_x - bbox[0], pad_y - bbox[1]), text, font=font, fill=255)

    # 3. Compose gradient + mask onto a transparent RGBA tile.
    out = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out


def build() -> None:
    bg = Image.new("RGBA", (WIDTH, HEIGHT), (255, 255, 255, 255))

    # ----- App icon (no shadow, no decorative frame) -----
    icon_size = 220
    icon = Image.open(ICON).convert("RGBA").resize(
        (icon_size, icon_size), Image.LANCZOS
    )
    rmask = Image.new("L", (icon_size, icon_size), 0)
    ImageDraw.Draw(rmask).rounded_rectangle(
        (0, 0, icon_size, icon_size),
        radius=int(icon_size * 0.225),
        fill=255,
    )
    icon.putalpha(rmask)
    icon_x, icon_y = 120, (HEIGHT - icon_size) // 2
    bg.alpha_composite(icon, dest=(icon_x, icon_y))

    # ----- Text block -----
    eyebrow_font = _font(28, "Semibold")
    title_font   = _font(132, "Heavy")     # heaviest SF Rounded available
    sub_font     = _font(34, "Regular")
    foot_font    = _font(26, "Medium")

    text_x = 380
    draw = ImageDraw.Draw(bg)

    # Eyebrow — Apple Blue, uppercase.
    draw.text(
        (text_x, icon_y - 6),
        "APPLE-NATIVE · ROS 2",
        font=eyebrow_font,
        fill=BLUE + (255,),
    )

    # Title — heavy weight, blue → indigo gradient.
    title_img = _gradient_text("Conduit", title_font, BLUE, INDIGO)
    bg.alpha_composite(title_img, dest=(text_x - 4, icon_y + 30))

    # Subtitle — muted dark gray.
    subtitle_y = icon_y + 30 + title_img.height + 10
    draw.text(
        (text_x, subtitle_y),
        "Stream 12 real-time sensors from iPhone,\n"
        "iPad, Mac, and Apple Vision Pro into ROS 2.",
        font=sub_font,
        fill=LABEL + (255,),
        spacing=10,
    )

    # Footer URL — secondary gray.
    draw.text(
        (text_x, HEIGHT - 110),
        "conduit.youtalk.jp",
        font=foot_font,
        fill=LABEL2 + (255,),
    )

    bg.convert("RGB").save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    build()
