"""Tests for the check-in listener embedded in pair/pair.sh."""
import os
import pathlib
import socket
import subprocess
import time

import pytest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "pair" / "pair.sh"
TOKEN = "Zk3q9cA1bT0x"
GOLDEN = '{"app_version":"3.0.0","device":"iPhone","namespace":"conduit","node":"conduit_node","token":"Zk3q9cA1bT0x"}'


@pytest.fixture
def checkin_py(tmp_path):
    lines = SCRIPT.read_text(encoding="utf-8").splitlines()
    start = lines.index("# >>> python:checkin") + 1
    end = lines.index("# <<< python:checkin")
    path = tmp_path / "checkin.py"
    path.write_text("\n".join(lines[start:end]) + "\n", encoding="utf-8")
    return path


@pytest.fixture
def listener(checkin_py):
    procs = []

    def start(port=0, env=None):
        proc = subprocess.Popen(
            ["python3", "-u", str(checkin_py), TOKEN, str(port)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
            env={**os.environ, **(env or {})},
        )
        procs.append(proc)
        first = proc.stdout.readline().strip()
        assert first.startswith("PORT=")
        return proc, int(first[5:])

    yield start
    for proc in procs:
        proc.kill()
        proc.wait()


def send(port, payload):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
        s.sendall(payload.encode() + b"\n")
        return s.makefile().readline()


def test_valid_checkin(listener):
    proc, port = listener()
    assert send(port, GOLDEN) == '{"ok":true}\n'
    assert proc.stdout.readline() == (
        "CHECKIN phone_ip=127.0.0.1 node=conduit_node namespace=conduit "
        "device=iPhone app_version=3.0.0\n"
    )


def test_wrong_token_does_not_complete(listener):
    proc, port = listener(env={"CONDUIT_PAIR_HINT_SECONDS": "1"})
    assert send(port, GOLDEN.replace(TOKEN, "wrongwrongwr")) == '{"ok":false,"error":"bad_token"}\n'
    # The next stdout line is the hint, not a CHECKIN.
    assert proc.stdout.readline() == "HINT no_checkin\n"


def test_garbage_is_bad_request(listener):
    _, port = listener()
    assert send(port, "not json") == '{"ok":false,"error":"bad_request"}\n'
    assert send(port, '{"token":"x"}') == '{"ok":false,"error":"bad_request"}\n'


def test_port_fallback(listener):
    with socket.socket() as busy:
        busy.bind(("0.0.0.0", 0))
        busy.listen()
        taken = busy.getsockname()[1]
        _, port = listener(port=taken)
        assert port != taken and port > 0


def test_unsafe_characters_are_replaced(listener):
    proc, port = listener()
    send(port, GOLDEN.replace('"iPhone"', '"a;b$(c)"'))
    assert "device=a_b__c_ " in proc.stdout.readline()


def test_hint_after_timeout(listener):
    proc, _ = listener(env={"CONDUIT_PAIR_HINT_SECONDS": "1"})
    assert proc.stdout.readline() == "HINT no_checkin\n"


def test_exits_when_stdin_closes(listener):
    proc, _ = listener()
    proc.stdin.close()
    deadline = time.time() + 5
    while proc.poll() is None and time.time() < deadline:
        time.sleep(0.1)
    assert proc.poll() is not None
