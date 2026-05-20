"""MkDocs on_pre_build hook: regenerate docs/index.md from README.md.

Rewrites image paths (images/ -> assets/img/) and internal markdown links
(docs/X.md -> x.md, with _ converted to -) so README.md can serve both as
the GitHub repo landing and as the MkDocs site root.
"""
from __future__ import annotations

import re
from pathlib import Path

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
