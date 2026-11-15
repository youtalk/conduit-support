#!/usr/bin/env bash
# CI smoke test for the container path: on a runner with Docker and no ROS 2,
# runs pair.sh --container against fake_conduit.py, which runs in a second
# container on the router container's network. CONDUIT_ROUTER_IMAGE names the
# router image (built by the job). Every prompt takes its default answer.
# Exits with pair.sh's status.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
distro="${1:?usage: run_container.sh DISTRO}"
log="$(mktemp)"
answers="$(mktemp)"
fake=conduit-fake

# shellcheck disable=SC2317 # called by the EXIT trap
cleanup() {
  docker rm -f "$fake" conduit-router > /dev/null 2>&1 || true
}
trap cleanup EXIT

# The output goes to the CI log as it comes, and to $log for the link.
PAIR_TTY="$answers" bash "$here/../../../pair/pair.sh" --container --distro "$distro" --lan --no-qr \
  > >(tee "$log") 2>&1 &
pair=$!

link=""
for _ in $(seq 120); do
  link="$(grep -o 'https://conduit.direct/pair#[^[:space:]]*' "$log" | head -n1 || true)"
  [[ -z "$link" ]] || break
  kill -0 "$pair" 2> /dev/null || break
  sleep 1
done
if [[ -z "$link" ]]; then
  echo "pair.sh printed no pairing link." >&2
  exit 1
fi

# The fake app checks in at the PC's address and joins the router's graph, as
# the user's own containers would (--network container:conduit-router).
docker run -d --name "$fake" --network container:conduit-router \
  -v "$here:/smoke:ro" "$CONDUIT_ROUTER_IMAGE" python3 /smoke/fake_conduit.py "$link" 360 > /dev/null

status=0
wait "$pair" || status=$?
echo "pair.sh exited with $status."
echo "fake_conduit's log:"
docker logs "$fake" 2>&1 | sed 's/^/  /' || true
exit "$status"
