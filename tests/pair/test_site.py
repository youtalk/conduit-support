import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_association_file():
    data = json.loads((ROOT / "docs/.well-known/apple-app-site-association").read_text())
    assert data == {
        "applinks": {
            "details": [
                {
                    "appIDs": ["2AFT9XT8R2.jp.youtalk.conduit"],
                    "components": [{"/": "/pair*", "comment": "QR pairing"}],
                }
            ]
        }
    }


def test_pair_page():
    text = (ROOT / "docs/pair.md").read_text()
    assert "curl -fsSL https://conduit.direct/pair.sh | bash" in text
    assert "https://apps.apple.com/app/id6757171237" in text


def test_open_in_conduit_button():
    text = (ROOT / "docs/pair.md").read_text()
    # The fragment (pairing values and token) only ever becomes the conduit:// link.
    assert '"conduit://pair" + fragment' in text
    assert text.count("location.hash") == 1
    for leak in ("fetch(", "XMLHttpRequest", "sendBeacon", "localStorage", "console.log"):
        assert leak not in text


def test_site_loads_no_third_party_scripts():
    # The pair page reads the URL fragment, so the site must not load analytics or extra scripts.
    config = (ROOT / "mkdocs.yml").read_text()
    assert "analytics" not in config
    assert "extra_javascript" not in config
