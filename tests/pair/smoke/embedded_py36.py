"""Runs pair.sh's embedded Python (QR encoder and check-in listener) on the
interpreter that runs this file: CI runs it with RHEL 8's Python 3.6, the
python3 of ROS 2 Humble on RHEL 8.

Usage: python3 embedded_py36.py PATH/TO/pair.sh
"""
import json
import socket
import subprocess
import sys

TOKEN = "Zk3q9cA1bT0x"
LINK = ("https://conduit.direct/pair#v=1&transport=dds&distro=humble&domain=0"
        "&host=192.168.1.85&checkin=192.168.1.85%3A7449&token=" + TOKEN + "&name=pc")


def block(lines, name):
    start = lines.index("# >>> python:%s" % name) + 1
    end = lines.index("# <<< python:%s" % name)
    return "\n".join(lines[start:end]) + "\n"


def main():
    with open(sys.argv[1], encoding="utf-8") as f:
        lines = f.read().splitlines()

    qr = subprocess.run([sys.executable, "-c", block(lines, "qr"), LINK],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if qr.returncode != 0 or "█" not in qr.stdout:
        sys.exit("QR encoder failed:\n" + qr.stderr)
    print("QR encoder: ok")

    listener = subprocess.Popen([sys.executable, "-u", "-c", block(lines, "checkin"), TOKEN, "0"],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, universal_newlines=True)
    try:
        first = listener.stdout.readline().strip()
        if not first.startswith("PORT="):
            sys.exit("check-in listener did not report a port: %r" % first)
        request = {"app_version": "3.0.0", "device": "iPhone", "namespace": "conduit",
                   "node": "conduit_node", "token": TOKEN}
        with socket.create_connection(("127.0.0.1", int(first[5:])), timeout=5) as conn:
            conn.sendall(json.dumps(request).encode() + b"\n")
            reply = conn.makefile().readline()
        if reply != '{"ok":true}\n':
            sys.exit("check-in reply: %r" % reply)
        line = listener.stdout.readline()
        if not line.startswith("CHECKIN phone_ip=127.0.0.1 node=conduit_node namespace=conduit"):
            sys.exit("check-in line: %r" % line)
    finally:
        listener.kill()
        listener.wait()
    print("check-in listener: ok")


if __name__ == "__main__":
    main()
