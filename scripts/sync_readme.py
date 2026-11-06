"""MkDocs on_pre_build hook: regenerate docs/index.md from README.md.

Four responsibilities:

1. Rewrite image paths (``images/`` → ``assets/img/``) so the same Markdown
   source works as both the GitHub README and the MkDocs home page.
2. Rewrite internal links (``docs/X.md`` → ``x.md``, uppercase → lowercase
   with ``_`` → ``-``) so MkDocs Material's URL scheme is honoured.
3. Replace the README's centered icon + ``# Conduit`` heading block with a
   custom HTML hero that matches the Conduit app's design language. The hero
   ships inside ``index.md`` and is styled by ``docs/assets/css/conduit.css``.
4. Turn demo-video thumbnails (a YouTube thumbnail image linked to the watch
   page) into inline ``<iframe>`` players: GitHub strips ``<iframe>`` from
   README markup, so the README keeps the clickable thumbnails while the
   MkDocs site gets real embedded players.
"""
from __future__ import annotations

import re
from pathlib import Path

# ----- Link / asset rewrites -----

# docs/name.md or docs/UPPERCASE_WORDS.md  ->  name.md / uppercase-words.md
# (anchor preserved)
_DOCS_LINK_RE = re.compile(r"\bdocs/([A-Za-z][A-Za-z0-9_-]*)\.md(#[^\s)\"']*)?")
# ](docker/README.md) -> ](https://github.com/youtalk/conduit-support/tree/main/docker)
# Must run before the bare-uppercase rule below.
_DOCKER_README_RE = re.compile(r"\]\(docker/README\.md\)")
# ](UPPERCASE_WORDS.md) or ](../UPPERCASE_WORDS.md) with optional anchor.
# Anchored to "](" so we don't touch absolute URLs like
# https://github.com/.../README.md inside link targets.
_BARE_DOC_RE = re.compile(
    r"\]\((?:\.\./)?([A-Z][A-Z0-9_]*)\.md(#[^\s)\"']*)?\)"
)
# src="images/..." or href="images/..." (only relative, not absolute URLs)
_HTML_ATTR_RE = re.compile(r'(\b(?:src|href)=")images/')
# ](images/...)
_MD_INLINE_RE = re.compile(r"\]\(images/")
# A demo-video cell: <a href="...watch?v=ID"> wrapping a YouTube thumbnail
# <img> and a <b>Title</b>. Rewritten to an inline <iframe> player for the
# site (GitHub strips <iframe>, so README keeps the thumbnail link).
_YT_THUMB_RE = re.compile(
    r'<a href="https://www\.youtube\.com/watch\?v=([\w-]+)">\s*'
    r"<img[^>]*>\s*<br>\s*"
    r"<b>([^<]+)</b>\s*</a>"
)
# The README's raw HTML <table>s are media grids (demo videos, screenshots).
# GitHub needs a table to lay them out; on the site the class lets CSS turn
# them into a responsive grid. Markdown tables are not raw <table> tags, so
# they are not affected.
_MEDIA_TABLE_RE = re.compile(r"<table>")
# README <details> blocks hold Markdown (code, lists). Python-Markdown leaves
# raw HTML alone unless it is marked with markdown="1" (md_in_html).
_DETAILS_RE = re.compile(r"<details>")
_YT_IFRAME_ALLOW = (
    "accelerometer; autoplay; clipboard-write; encrypted-media; "
    "gyroscope; picture-in-picture; web-share"
)

# ----- Hero replacement -----

# Matches the README opening:
#
#   <div align="center">
#
#   <a href="https://apps.apple.com/app/id6757171237">
#   <img src="images/app_icon.png" width="128" height="128" alt="…">
#   </a>
#
#   # Conduit
#
#   </div>
#
# Anchored with \A so only the README's opening block is rewritten; if the
# same centered block ever recurs elsewhere it won't be silently consumed.
_HERO_BLOCK_RE = re.compile(
    r"\A\s*"
    r"<div align=\"center\">\s*"
    r"<a href=\"(?P<app_url>https://apps\.apple\.com/[^\"]+)\">\s*"
    r"<img src=\"images/app_icon\.png\"[^>]*>\s*"
    r"</a>\s*"
    r"#\s*Conduit\s*"
    r"</div>\s*"
    # The README's bold tagline repeats what the hero says; drop it too.
    r"(?:\*\*[^*\n]+\*\*[ \t]*\n\s*)?",
    re.MULTILINE,
)

_HERO_HTML = """\
<div class="conduit-hero" markdown="0">
  <div class="conduit-hero__copy">
    <div class="conduit-hero__brand">
      <a href="{app_url}" aria-label="Download Conduit on the App Store">
        <img class="conduit-hero__icon" src="assets/img/app_icon.png"
             alt="Conduit app icon" width="64" height="64">
      </a>
      <h1 class="conduit-hero__title">Conduit</h1>
    </div>
    <p class="conduit-hero__subtitle">
      Publish <strong>13 sensors</strong> of your iPhone, iPad or Mac to ROS 2:
      camera, LiDAR, IMU, GPS and more, over Zenoh or DDS, with no bridge.
    </p>
    <div class="conduit-hero__cta">
      <a class="conduit-btn conduit-btn--primary" href="{app_url}">Download on the App Store</a>
      <a class="conduit-btn conduit-btn--tinted" href="pair/">Connect with a QR code</a>
    </div>
    <p class="conduit-hero__note">
      Downloaded over 10,000 times. Ranked as high as #4 in Developer Tools
      on the Japanese App Store.
    </p>
  </div>
  <div class="conduit-hero__stage">
  <div class="conduit-terminal" role="img" aria-label="ros2 topic list on the ROS 2 host shows Conduit's topics">
    <span class="conduit-terminal__prompt">ros2 topic list</span>
    <ol>
      <li>/conduit/audio</li>
      <li>/conduit/barometer</li>
      <li>/conduit/battery_state</li>
      <li>/conduit/camera/wide/image_raw/compressed</li>
      <li>/conduit/fix</li>
      <li>/conduit/illuminance</li>
      <li>/conduit/imu</li>
      <li>/conduit/joy</li>
      <li>/conduit/magnetic_field</li>
      <li>/conduit/points</li>
      <li>/conduit/pose</li>
      <li>/conduit/range</li>
      <li>/conduit/temperature</li>
      <li>/tf</li>
      <li>/tf_static</li>
    </ol>
  </div>
  <img class="conduit-hero__device" src="assets/img/hero-iphone.png"
       alt="Conduit on iPhone, publishing the Motion sensors live"
       width="640" height="1319">
  </div>
</div>

"""


def rewrite(text: str) -> str:
    """Apply all README->index.md transforms. Pure, idempotent."""
    def _docs_repl(match: re.Match[str]) -> str:
        slug = match.group(1).lower().replace("_", "-")
        anchor = match.group(2) or ""
        return f"{slug}.md{anchor}"

    def _bare_repl(match: re.Match[str]) -> str:
        slug = match.group(1).lower().replace("_", "-")
        anchor = match.group(2) or ""
        return f"]({slug}.md{anchor})"

    def _hero_repl(match: re.Match[str]) -> str:
        return _HERO_HTML.format(app_url=match.group("app_url"))

    def _yt_repl(match: re.Match[str]) -> str:
        video_id, title = match.group(1), match.group(2)
        return (
            f'<div class="conduit-video"><iframe '
            f'src="https://www.youtube.com/embed/{video_id}" '
            f'title="{title}" loading="lazy" '
            f'allow="{_YT_IFRAME_ALLOW}" '
            f'referrerpolicy="strict-origin-when-cross-origin" '
            f"allowfullscreen></iframe></div>\n"
            f"<b>{title}</b>"
        )

    text = _HERO_BLOCK_RE.sub(_hero_repl, text, count=1)
    text = _DOCS_LINK_RE.sub(_docs_repl, text)
    text = _DOCKER_README_RE.sub(
        "](https://github.com/youtalk/conduit-support/tree/main/docker)",
        text,
    )
    text = _BARE_DOC_RE.sub(_bare_repl, text)
    text = _HTML_ATTR_RE.sub(r'\1assets/img/', text)
    text = _MD_INLINE_RE.sub("](assets/img/", text)
    text = _YT_THUMB_RE.sub(_yt_repl, text)
    text = _MEDIA_TABLE_RE.sub('<table class="conduit-media">', text)
    text = _DETAILS_RE.sub('<details markdown="1">', text)
    return text


def on_pre_build(config) -> None:  # type: ignore[no-untyped-def]
    """MkDocs hook entry point — called before each build."""
    docs_dir = Path(getattr(config, "docs_dir", "docs"))
    readme = Path("README.md")
    if not readme.exists():
        return
    docs_dir.mkdir(parents=True, exist_ok=True)
    text = readme.read_text(encoding="utf-8")
    index = docs_dir / "index.md"
    new = rewrite(text)
    # Write only on change: `mkdocs serve` watches docs/, so rewriting an
    # unchanged index.md would trigger a rebuild loop.
    if index.exists() and index.read_text(encoding="utf-8") == new:
        return
    index.write_text(new, encoding="utf-8", newline="\n")
