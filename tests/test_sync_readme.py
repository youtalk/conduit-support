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
