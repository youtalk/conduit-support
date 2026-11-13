#!/usr/bin/env bats
# `curl -fsSL https://conduit.direct/pair.sh | bash` runs /bin/bash on a Mac:
# bash 3.2, which has no coproc, no {var} file descriptors and no ${var,,}.
# The script must parse there and its check-in listener must run there.
# PAIR_BASH32 names that bash; the tests skip where there is none.

bats_require_minimum_version 1.5.0
load helpers

BASH32="${PAIR_BASH32:-/bin/bash}"

setup() {
  if [[ ! -x "$BASH32" || "$("$BASH32" -c 'echo "${BASH_VERSINFO[0]}"')" != 3 ]]; then
    skip "no bash 3.x at $BASH32"
  fi
}

# in_bash32 SNIPPET: run SNIPPET under bash 3.2 with the script sourced.
in_bash32() {
  run "$BASH32" -c 'set -euo pipefail; CONDUIT_PAIR_SOURCED=1; source "$1"; eval "$2"' bash32 "$SCRIPT" "$1"
}

@test "pair.sh parses under bash 3.2" {
  run "$BASH32" -n "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the check-in listener starts under bash 3.2" {
  command -v python3 > /dev/null || skip "no python3"
  in_bash32 '
    start_checkin Zk3q9cA1bT0x 0
    pid=$CHECKIN_PID
    python3 - "$PAIR_CHECKIN_PORT" << "PY"
import json, socket, sys
req = {"app_version": "3.0.0", "device": "My iPhone", "namespace": "conduit",
       "node": "conduit_node", "token": "Zk3q9cA1bT0x"}
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5) as s:
    s.sendall(json.dumps(req).encode() + b"\n")
    print("reply " + s.makefile().readline().strip())
PY
    wait_checkin
    echo "device=$PAIR_DEVICE node=$PAIR_NODE from=$PAIR_PHONE_IP"
    stop_checkin
    if kill -0 "$pid" 2> /dev/null; then echo "still running"; else echo "stopped"; fi
  '
  [ "$status" -eq 0 ]
  has 'reply {"ok":true}'
  has "device=My iPhone node=conduit_node from=127.0.0.1"
  [ "${lines[${#lines[@]} - 1]}" = stopped ]
}

@test "the check-in listener ends with the script under bash 3.2, even without the trap" {
  command -v python3 > /dev/null || skip "no python3"
  in_bash32 '
    start_checkin Zk3q9cA1bT0x 0
    echo "pid=$CHECKIN_PID"
    trap - EXIT
  '
  [ "$status" -eq 0 ]
  pid="$(sed -n 's/^pid=//p' <<< "$output")"
  [ -n "$pid" ]
  # The listener sees its stdin close and exits.
  for _ in $(seq 50); do kill -0 "$pid" 2> /dev/null || break; sleep 0.1; done
  run kill -0 "$pid"
  [ "$status" -ne 0 ]
}
