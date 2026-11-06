"""Generate the OpenGraph share image (1200x630) for conduit.direct.

The card repeats the home page hero: the app name and one line of copy on the
left, and on the right the ROS 2 host's terminal running `ros2 topic list`
with an iPhone running Conduit in front of it.

- Text is SF Pro, the terminal SF Mono, the same families as the site.
- The topic list is read from the hero in scripts/sync_readme.py, so the card
  and the page always show the same topics.
- The iPhone is images/hero-iphone.png, the image the hero uses.

Output: images/og-card.png (served as assets/img/og-card.png).
Needs macOS for the system fonts and Pillow. Re-run after editing:

    python scripts/generate_og_image.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
IMAGES = ROOT / "images"
OUT = IMAGES / "og-card.png"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sync_readme import _HERO_HTML  # noqa: E402

# Drawn at 2x, saved at 1200x630.
W, H = 2400, 1260

# Colors from docs/assets/css/conduit.css.
BG = (245, 245, 247)
LABEL = (29, 29, 31)
LABEL2 = (110, 110, 115)
BLUE = (0, 122, 255)
TERM_BG = (28, 28, 30)
TERM_FG = (242, 242, 247)
TERM_PROMPT = (48, 209, 88)
LIGHTS = [(255, 95, 87), (254, 188, 46), (40, 200, 64)]

SF_PRO = "/System/Library/Fonts/SFNS.ttf"
SF_MONO = "/System/Library/Fonts/SFNSMono.ttf"


def font(path: str, size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    """A system variable font at a named weight."""
    f = ImageFont.truetype(path, size)
    try:
        f.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return f


def topics() -> list[str]:
    return re.findall(r"<li>([^<]+)</li>", _HERO_HTML)


def rounded(img: Image.Image, radius: float) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius, fill=255)
    img.putalpha(mask)
    return img


def place(canvas: Image.Image, img: Image.Image, x: int, y: int, shadow: float) -> None:
    """Paste with a soft drop shadow, like the hero's drop-shadow filter."""
    pad = 80
    alpha = img.split()[3].point(lambda v: int(v * shadow))
    sh = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 255), (pad, pad), alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(28))
    canvas.alpha_composite(sh, (x - pad, y - pad + 24))
    canvas.alpha_composite(img, (x, y))


def terminal(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=36, fill=TERM_BG)
    for i, color in enumerate(LIGHTS):
        d.ellipse((44 + i * 44, 40, 68 + i * 44, 64), fill=color)
    f = font(SF_MONO, 36)
    x, y, step = 52, 112, 51
    d.text((x, y), "$", font=f, fill=TERM_PROMPT)
    d.text((x + 44, y), "ros2 topic list", font=f, fill=TERM_FG)
    y += step + 8
    for topic in topics():
        if y > h - 70:
            break
        d.text((x + 44, y), topic, font=f, fill=TERM_FG)
        y += step
    return img


def build() -> None:
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(canvas)

    # App icon and name
    left, top = 130, 360
    icon = rounded(Image.open(IMAGES / "app_icon.png").convert("RGBA").resize((158, 158), Image.LANCZOS), 158 * 0.225)
    canvas.alpha_composite(icon, (left, top))
    title = font(SF_PRO, 150, "Bold")
    tb = d.textbbox((0, 0), "Conduit", font=title)
    d.text((left + icon.width + 33 - tb[0], top + (icon.height - (tb[3] - tb[1])) // 2 - tb[1]),
           "Conduit", font=title, fill=LABEL)

    # One line of copy, in two rows
    sub = font(SF_PRO, 50)
    y = top + icon.height + 45
    for line in ("Publish your iPhone, iPad and", "Mac sensors to ROS 2."):
        lb = d.textbbox((0, 0), line, font=sub)
        d.text((left - lb[0], y - lb[1]), line, font=sub, fill=LABEL2)
        y += 65

    foot = font(SF_PRO, 40, "Semibold")
    fb = d.textbbox((0, 0), "conduit.direct", font=foot)
    d.text((left - fb[0], H - 170 - fb[1]), "conduit.direct", font=foot, fill=BLUE)

    # The host's terminal, with the iPhone in front of it
    place(canvas, terminal(980, 1000), 1100, 130, shadow=0.25)
    phone = Image.open(IMAGES / "hero-iphone.png").convert("RGBA")
    phone = phone.resize((round(phone.width * 1080 / phone.height), 1080), Image.LANCZOS)
    place(canvas, phone, 1760, 90, shadow=0.18)

    canvas.convert("RGB").resize((1200, 630), Image.LANCZOS).save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    build()
