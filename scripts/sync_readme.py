"""MkDocs on_pre_build hook: regenerate docs/index.md from README.md.

Three responsibilities:

1. Rewrite image paths (``images/`` → ``assets/img/``) so the same Markdown
   source works as both the GitHub README and the MkDocs home page.
2. Rewrite internal links (``docs/X.md`` → ``x.md``, uppercase → lowercase
   with ``_`` → ``-``) so MkDocs Material's URL scheme is honoured.
3. Replace the README's centered icon + ``# Conduit`` heading block with a
   custom HTML hero that matches the Conduit app's design language. The hero
   ships inside ``index.md`` and is styled by ``docs/assets/css/conduit.css``.
"""
from __future__ import annotations

import re
from pathlib import Path

# ----- Link / asset rewrites -----

# docs/UPPERCASE_WORDS.md  ->  lowercase-words.md  (anchor preserved)
_DOCS_LINK_RE = re.compile(r"\bdocs/([A-Z][A-Z0-9_]*)\.md(#[^\s)\"']*)?")
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
    r"</div>\s*",
    re.MULTILINE,
)

_HERO_HTML = """\
<div class="conduit-hero" markdown="0">
  <div class="conduit-hero__inner">
    <a href="{app_url}" aria-label="Download Conduit on the App Store">
      <img class="conduit-hero__icon" src="assets/img/app_icon.png"
           alt="Conduit app icon" width="96" height="96">
    </a>
    <div class="conduit-hero__copy">
      <span class="conduit-hero__eyebrow">Apple-native · ROS 2</span>
      <h1 class="conduit-hero__title">Conduit</h1>
      <p class="conduit-hero__subtitle">
        Stream 12 real-time sensors from iPhone, iPad, Mac, and Apple Vision Pro
        straight into your ROS 2 graph — Zenoh or DDS, no bridge required.
      </p>
      <div class="conduit-hero__cta">
        <a class="conduit-btn conduit-btn--primary" href="{app_url}">
          Download on the App Store
        </a>
        <a class="conduit-btn conduit-btn--ghost" href="#demo-videos">
          Watch demos
        </a>
      </div>
      <div class="conduit-stats" role="list">
        <div class="conduit-stat" role="listitem">
          <span class="conduit-stat__num">10,000+</span>
          <span class="conduit-stat__label">ROS 2 developers</span>
        </div>
        <div class="conduit-stat" role="listitem">
          <span class="conduit-stat__num">#4</span>
          <span class="conduit-stat__label">Developer Tools, JP</span>
        </div>
        <div class="conduit-stat" role="listitem">
          <span class="conduit-stat__num">12</span>
          <span class="conduit-stat__label">sensor topics</span>
        </div>
        <div class="conduit-stat" role="listitem">
          <span class="conduit-stat__num">Zenoh · DDS</span>
          <span class="conduit-stat__label">native transports</span>
        </div>
      </div>
    </div>
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

    text = _HERO_BLOCK_RE.sub(_hero_repl, text, count=1)
    text = _DOCS_LINK_RE.sub(_docs_repl, text)
    text = _DOCKER_README_RE.sub(
        "](https://github.com/youtalk/conduit-support/tree/main/docker)",
        text,
    )
    text = _BARE_DOC_RE.sub(_bare_repl, text)
    text = _HTML_ATTR_RE.sub(r'\1assets/img/', text)
    text = _MD_INLINE_RE.sub("](assets/img/", text)
    return text


def on_pre_build(config) -> None:  # type: ignore[no-untyped-def]
    """MkDocs hook entry point — called before each build."""
    docs_dir = Path(getattr(config, "docs_dir", "docs"))
    readme = Path("README.md")
    if not readme.exists():
        return
    docs_dir.mkdir(parents=True, exist_ok=True)
    text = readme.read_text(encoding="utf-8")
    (docs_dir / "index.md").write_text(rewrite(text), encoding="utf-8", newline="\n")
