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
    assert "location.hash" not in text
