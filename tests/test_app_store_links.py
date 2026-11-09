"""Every App Store link this repository publishes carries the conduit-direct campaign.

conduit.direct and the README on GitHub both send people straight to the App Store, so App
Store Connect counts their downloads under one campaign: pt is the provider token, ct the
campaign.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAMPAIGN_LINK = (
    "https://apps.apple.com/app/apple-store/id6757171237?pt=1392401&ct=conduit-direct&mt=8"
)
_APP_STORE_URL_RE = re.compile(r"https://apps\.apple\.com/[^\s)\"'<>]+")


def _published_sources() -> list[Path]:
    paths = [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md"))]
    paths += sorted((ROOT / "overrides").rglob("*.html"))
    return [p for p in paths if p.name != "index.md"]  # index.md is generated from README.md


def test_app_store_links_carry_the_campaign():
    links = [
        (path.relative_to(ROOT).as_posix(), url.replace("&amp;", "&"))
        for path in _published_sources()
        for url in _APP_STORE_URL_RE.findall(path.read_text(encoding="utf-8"))
    ]
    assert links, "no App Store link found"
    assert [link for link in links if link[1] != CAMPAIGN_LINK] == []
