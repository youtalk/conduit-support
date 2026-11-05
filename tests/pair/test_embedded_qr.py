"""Tests for the QR encoder embedded in pair/pair.sh."""
import pathlib
import subprocess

import pytest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "pair" / "pair.sh"

DDS = (
    "https://conduit.direct/pair#v=1&transport=dds&distro=jazzy&domain=123"
    "&host=192.168.1.85&checkin=192.168.1.85%3A7449&token=Zk3q9cA1bT0x&name=youtalk-desktop"
)
ZENOH = (
    "https://conduit.direct/pair#v=1&transport=zenoh&distro=lyrical&domain=0"
    "&host=100.101.102.103&port=7447&checkin=100.101.102.103%3A7449&token=Zk3q9cA1bT0x&name=robot%20pc"
)


@pytest.fixture
def qr_py(tmp_path):
    lines = SCRIPT.read_text(encoding="utf-8").splitlines()
    start = lines.index("# >>> python:qr") + 1
    end = lines.index("# <<< python:qr")
    path = tmp_path / "qr.py"
    path.write_text("\n".join(lines[start:end]) + "\n", encoding="utf-8")
    return path


def run_qr(qr_py, link, *flags):
    return subprocess.run(
        ["python3", str(qr_py), link, *flags],
        check=True, capture_output=True, text=True,
    ).stdout


@pytest.mark.parametrize("link", [DDS, ZENOH])
def test_qr_decodes_to_the_link(qr_py, tmp_path, link):
    pbm = tmp_path / "qr.pbm"
    pbm.write_text(run_qr(qr_py, link, "--pbm"))
    out = subprocess.run(
        ["zbarimg", "--raw", "-q", str(pbm)],
        check=True, capture_output=True, text=True,
    ).stdout
    assert out.strip() == link


def test_terminal_output_height(qr_py):
    lines = run_qr(qr_py, DDS).splitlines()
    assert 0 < len(lines) <= 30
    assert set("".join(lines)) <= set("▀▄█ ")
