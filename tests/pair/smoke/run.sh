#!/usr/bin/env bash
# CI smoke test for RHEL and Fedora: runs pair.sh against fake_conduit.py on
# this machine (a container) with the sourced ROS 2 and RMW_IMPLEMENTATION.
# Every prompt takes its default answer. Exits with pair.sh's status.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log="$(mktemp)"
answers="$(mktemp)"

PAIR_ALLOW_CONTAINER=1 PAIR_TTY="$answers" bash "$here/../../../pair/pair.sh" --lan --no-qr > "$log" 2>&1 &
pair=$!

link=""
for _ in $(seq 120); do
  link="$(grep -o 'https://conduit.direct/pair#[^[:space:]]*' "$log" | head -n1 || true)"
  [[ -z "$link" ]] || break
  kill -0 "$pair" 2> /dev/null || break
  sleep 1
done
if [[ -z "$link" ]]; then
  cat "$log"
  echo "pair.sh printed no pairing link." >&2
  exit 1
fi

python3 "$here/fake_conduit.py" "$link" 360 &
fake=$!

status=0
wait "$pair" || status=$?
kill "$fake" 2> /dev/null || true
wait "$fake" 2> /dev/null || true
cat "$log"
echo "pair.sh exited with $status."
exit "$status"
