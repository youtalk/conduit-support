"""Unit tests for scripts/sync_readme.py."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import sync_readme  # noqa: E402


def test_rewrites_relative_image_src():
    out = sync_readme.rewrite('<img src="images/app_icon.png" width="128">')
    assert out == '<img src="assets/img/app_icon.png" width="128">'


def test_rewrites_markdown_image():
    out = sync_readme.rewrite("![icon](images/app_icon.png)")
    assert out == "![icon](assets/img/app_icon.png)"


def test_leaves_absolute_image_urls_alone():
    src = '<img src="https://img.youtube.com/vi/x/0.jpg">'
    assert sync_readme.rewrite(src) == src


def test_rewrites_uppercase_docs_link():
    out = sync_readme.rewrite("[FAQ](docs/FAQ.md)")
    assert out == "[FAQ](faq.md)"


def test_rewrites_docs_link_with_underscore_to_hyphen():
    out = sync_readme.rewrite("[Platform Notes](docs/PLATFORM_NOTES.md)")
    assert out == "[Platform Notes](platform-notes.md)"


def test_preserves_anchor_on_docs_link():
    out = sync_readme.rewrite(
        "[Troubleshooting](docs/TROUBLESHOOTING.md#some-anchor)"
    )
    assert out == "[Troubleshooting](troubleshooting.md#some-anchor)"


def test_idempotent():
    once = sync_readme.rewrite("![icon](images/app_icon.png)")
    twice = sync_readme.rewrite(once)
    assert once == twice


def test_on_pre_build_hook_writes_index(tmp_path, monkeypatch):
    readme = tmp_path / "README.md"
    readme.write_text("# Conduit\n![icon](images/app_icon.png)\n")
    docs_path = tmp_path / "docs"
    docs_path.mkdir()
    monkeypatch.chdir(tmp_path)

    class FakeConfig(dict):
        docs_dir = str(docs_path)

    sync_readme.on_pre_build(FakeConfig())

    out = (docs_path / "index.md").read_text()
    assert "![icon](assets/img/app_icon.png)" in out


def test_rewrites_bare_uppercase_md_link():
    out = sync_readme.rewrite("[Privacy](PRIVACY.md)")
    assert out == "[Privacy](privacy.md)"


def test_rewrites_bare_uppercase_md_with_underscore():
    out = sync_readme.rewrite("[Platform Notes](PLATFORM_NOTES.md)")
    assert out == "[Platform Notes](platform-notes.md)"


def test_rewrites_bare_uppercase_md_preserves_anchor():
    out = sync_readme.rewrite("[Trouble](TROUBLESHOOTING.md#some-anchor)")
    assert out == "[Trouble](troubleshooting.md#some-anchor)"


def test_rewrites_docker_readme_to_github_url():
    out = sync_readme.rewrite("[Docker](docker/README.md)")
    assert out == (
        "[Docker](https://github.com/youtalk/conduit-support/tree/main/docker)"
    )


def test_leaves_uppercase_url_alone_when_part_of_path():
    # Don't accidentally munge things that aren't intended .md filenames
    src = "[GitHub](https://github.com/youtalk/conduit-support/blob/main/README.md)"
    assert sync_readme.rewrite(src) == src


def test_replaces_centered_hero_block():
    """The README opening with icon + # Conduit becomes the hero HTML."""
    readme_opening = (
        '<div align="center">\n'
        '\n'
        '<a href="https://apps.apple.com/app/id6757171237">\n'
        '<img src="images/app_icon.png" width="128" height="128" alt="x">\n'
        '</a>\n'
        '\n'
        '# Conduit\n'
        '\n'
        '</div>\n'
        '\n'
        '**Your iPhone as a ROS 2 sensor**\n'
        '\n'
        'Conduit publishes sensors.'
    )
    out = sync_readme.rewrite(readme_opening)
    assert 'class="conduit-hero"' in out
    # The bare `# Conduit` heading must be gone — replaced by the hero title.
    assert "\n# Conduit\n" not in out
    # The App Store URL must be carried into the hero.
    assert "apps.apple.com/app/id6757171237" in out
    # The bold tagline repeats the hero and is dropped; the body survives.
    assert "**Your iPhone as a ROS 2 sensor**" not in out
    assert "Conduit publishes sensors." in out


def test_hero_replacement_only_runs_once():
    """A page that doesn't open with the centered block isn't touched."""
    src = "## Section\n\nNo hero here.\n"
    assert sync_readme.rewrite(src) == src


_DEMO_CELL = (
    '<a href="https://www.youtube.com/watch?v=d28sQYQlpYY">\n'
    '<img src="https://img.youtube.com/vi/d28sQYQlpYY/0.jpg" width="280" '
    'alt="Teleoperation Demo"><br>\n'
    "<b>Teleoperation</b>\n"
    "</a><br>\n"
    "<sub>Control robots using Game Controller sensor</sub>"
)


def test_demo_thumbnail_becomes_iframe_embed():
    out = sync_readme.rewrite(_DEMO_CELL)
    assert 'src="https://www.youtube.com/embed/d28sQYQlpYY"' in out
    assert "<iframe" in out
    # Title and surrounding caption are preserved.
    assert "<b>Teleoperation</b>" in out
    assert "<sub>Control robots using Game Controller sensor</sub>" in out
    # The clickable watch-page link is gone — it became the iframe player.
    assert "youtube.com/watch?v=" not in out


def test_demo_thumbnail_rewrite_is_idempotent():
    once = sync_readme.rewrite(_DEMO_CELL)
    assert sync_readme.rewrite(once) == once


def test_non_youtube_anchor_with_image_is_untouched():
    src = (
        '<a href="https://example.com/page">\n'
        '<img src="https://img.youtube.com/vi/x/0.jpg"><br>\n'
        "<b>Not a video</b>\n</a>"
    )
    assert sync_readme.rewrite(src) == src


_README_OPENING = (
    '<div align="center">\n'
    '\n'
    '<a href="https://apps.apple.com/app/apple-store/id6757171237'
    '?pt=1392401&amp;ct=conduit-direct&amp;mt=8">\n'
    '<img src="images/app_icon.png" width="128" height="128" alt="x">\n'
    '</a>\n'
    '\n'
    '# Conduit\n'
    '\n'
    '</div>\n'
)


def test_hero_download_is_the_app_store_badge():
    out = sync_readme.rewrite(_README_OPENING)
    assert '<img class="conduit-badge__img" src="assets/img/app-store-badge.svg"' in out
    assert 'alt="Download on the App Store"' in out
    # The text button it replaces is gone.
    assert ">Download on the App Store</a>" not in out


def test_hero_carries_the_campaign_link_as_written():
    """The README's link is already HTML-escaped; the hero must not escape it again."""
    out = sync_readme.rewrite(_README_OPENING)
    assert (
        'href="https://apps.apple.com/app/apple-store/id6757171237'
        '?pt=1392401&amp;ct=conduit-direct&amp;mt=8"'
    ) in out
    assert "&amp;amp;" not in out
