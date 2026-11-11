#!/bin/bash
# Measures the demo image's arm (Linux or macOS with Docker): Gazebo's real-time factor,
# the wrist camera's rate, hold_clock_check.py (Conduit's HOLD on the arm's clock) and
# grasp_test.py.
#
#   bash measure_arm.sh <image> <domain> [docker run options...] [-- launch arguments...]
#
#   bash measure_arm.sh conduit-demo:lyrical-dev 133                 # light setting
#   bash measure_arm.sh conduit-demo:lyrical-dev 134 --runtime nvidia \
#       -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=all -- gpu:=true
#   bash measure_arm.sh conduit-demo:lyrical-dev 135 --cpus 2        # a slower machine
#   GZ_RTF=0.7 bash measure_arm.sh conduit-demo:lyrical-dev 136      # Gazebo held at 0.7
#
# It starts <image> in mode `arm` (no published port: the router and every check run
# inside the container) and, once Servo takes twists:
#   1. the real-time factor from Gazebo's /stats over STATS_S s (Δsim / Δreal, and the
#      median of the messages' per-step real_time_factor);
#   2. the rate and size of /wrist_camera/image_raw over STATS_S s;
#   3. hold_clock_check.py --seconds HOLD_SECONDS;
#   4. grasp_test.py --runs RUNS, with the real-time factor over the whole test.
# Both Python scripts are taken from this script's directory and copied into the
# container. It prints one `measure:` line per result and exits 0 when the HOLD check and
# the grasp test pass. The container is removed on exit.
#
# Environment: RUNS (default 10; 0 skips the grasp test), HOLD_SECONDS (default 30),
# STATS_S (default 10), GZ_RTF (a target real-time factor for the world, set through
# Gazebo's set_physics service before measuring, to check the arm below real time),
# STARTUP_S (default 300, the wait for Servo).
set -u

usage() {
  echo "usage: measure_arm.sh <image> <domain> [docker run options...] [-- launch arguments...]" >&2
  exit 2
}
[ $# -ge 2 ] || usage
IMAGE="$1"
DOMAIN="$2"
shift 2
DOCKER_OPTS=()
LAUNCH_ARGS=()
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then
    shift
    LAUNCH_ARGS=("$@")
    break
  fi
  DOCKER_OPTS+=("$1")
  shift
done

RUNS="${RUNS:-10}"
HOLD_SECONDS="${HOLD_SECONDS:-30}"
STATS_S="${STATS_S:-10}"
STARTUP_S="${STARTUP_S:-300}"
GZ_RTF="${GZ_RTF:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="conduit-demo-measure-${DOMAIN}"
WORLD=demo_table

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  echo "measure: FAIL: $*"
  echo "--- last lines of the arm container's log ---"
  docker logs --tail 40 "$NAME" 2>&1 || true
  exit 1
}

# Runs a command in the container with ROS 2 and the demo sourced.
in_arm() {
  docker exec -i "$NAME" bash -c "source /opt/ros/\$ROS_DISTRO/setup.bash && source /ros2_ws/install/setup.bash && $1"
}

# read returns 1 at the end of the here-document.
read -r -d '' PROBE_PY <<'PY' || true
"""Probes for measure_arm.sh: Gazebo's /stats and the wrist camera."""

import sys
import threading
import time


def stats(seconds):
    """Δsim/Δreal over `seconds` of /stats, and the messages' real_time_factor range."""
    from gz.msgs.world_stats_pb2 import WorldStatistics
    from gz.transport import Node
    samples = []
    lock = threading.Lock()

    def on_stats(message):
        with lock:
            samples.append((message.sim_time.sec + message.sim_time.nsec * 1e-9,
                            message.real_time.sec + message.real_time.nsec * 1e-9,
                            message.real_time_factor))
    node = Node()
    if not node.subscribe(WorldStatistics, '/stats', on_stats):
        print('no /stats subscription')
        return 1
    deadline = time.monotonic() + 10.0
    while time.monotonic() < deadline and not samples:
        time.sleep(0.05)
    with lock:
        samples.clear()
    time.sleep(seconds)
    node.unsubscribe('/stats')  # a subscriber left at exit segfaults
    with lock:
        window = list(samples)
    if len(window) < 2:
        print(f'{len(window)} /stats messages in {seconds:.0f} s')
        return 1
    dsim = window[-1][0] - window[0][0]
    dreal = window[-1][1] - window[0][1]
    # Each message's real_time_factor covers one step and jitters; its median is shown.
    factors = sorted(f for _, _, f in window)
    print(f'{dsim / dreal:.3f} (sim {dsim:.1f} s / real {dreal:.1f} s; /stats '
          f'real_time_factor median {factors[len(factors) // 2]:.3f}, {len(window)} messages)')
    return 0


def snapshot():
    """One /stats message: sim_time real_time."""
    from gz.msgs.world_stats_pb2 import WorldStatistics
    from gz.transport import Node
    got = []

    def on_stats(message):
        if not got:
            got.append((message.sim_time.sec + message.sim_time.nsec * 1e-9,
                        message.real_time.sec + message.real_time.nsec * 1e-9))
    node = Node()
    node.subscribe(WorldStatistics, '/stats', on_stats)
    deadline = time.monotonic() + 10.0
    while time.monotonic() < deadline and not got:
        time.sleep(0.02)
    node.unsubscribe('/stats')
    if not got:
        print('no /stats message within 10 s')
        return 1
    print(f'{got[0][0]:.3f} {got[0][1]:.3f}')
    return 0


def camera(seconds):
    import rclpy
    from rclpy.qos import qos_profile_sensor_data
    from sensor_msgs.msg import Image
    rclpy.init()
    node = rclpy.create_node('conduit_demo_measure_camera')
    arrivals, sizes = [], set()

    def on_image(message):
        arrivals.append(time.monotonic())
        sizes.add(f'{message.width} x {message.height} {message.encoding}')
    node.create_subscription(Image, '/wrist_camera/image_raw', on_image, qos_profile_sensor_data)
    deadline = time.monotonic() + 30.0
    while not arrivals and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.05)
    arrivals.clear()
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        rclpy.spin_once(node, timeout_sec=0.05)
    node.destroy_node()
    rclpy.try_shutdown()
    if len(arrivals) < 2:
        print(f'{len(arrivals)} images in {seconds:.0f} s')
        return 1
    hz = (len(arrivals) - 1) / (arrivals[-1] - arrivals[0])
    print(f'{hz:.2f} Hz, {", ".join(sorted(sizes))}')
    return 0


name = sys.argv[1]
if name == 'stats':
    sys.exit(stats(float(sys.argv[2])))
elif name == 'snapshot':
    sys.exit(snapshot())
elif name == 'camera':
    sys.exit(camera(float(sys.argv[2])))
sys.exit(f'unknown probe {name}')
PY

# Indents each line of its input as it arrives.
indent() {
  while IFS= read -r line; do
    printf '  %s\n' "$line"
  done
}

probe() {
  local seconds="$1"
  shift
  printf '%s\n' "$PROBE_PY" | in_arm "timeout -s INT -k 2 ${seconds} python3 - $*"
}

echo "measure: image ${IMAGE}, docker options [${DOCKER_OPTS[*]+${DOCKER_OPTS[*]}}], launch arguments [${LAUNCH_ARGS[*]+${LAUNCH_ARGS[*]}}], domain ${DOMAIN}${GZ_RTF:+, GZ_RTF ${GZ_RTF}}"
echo "measure: host $(uname -sm), docker CPUs $(docker info --format '{{.NCPU}}' 2>/dev/null), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
cleanup
docker run -d --name "$NAME" -e ROS_DOMAIN_ID="$DOMAIN" ${DOCKER_OPTS[@]+"${DOCKER_OPTS[@]}"} \
  "$IMAGE" arm ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"} >/dev/null || fail "docker run ${IMAGE} arm"
docker cp "${HERE}/hold_clock_check.py" "${NAME}:/tmp/hold_clock_check.py" >/dev/null \
  || fail "docker cp hold_clock_check.py"
docker cp "${HERE}/grasp_test.py" "${NAME}:/tmp/grasp_test.py" >/dev/null || fail "docker cp grasp_test.py"

start=$SECONDS
until docker logs "$NAME" 2>&1 | grep -q 'Servo command type set to TWIST'; do
  [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ] \
    || fail "the arm container stopped"
  [ $((SECONDS - start)) -lt "$STARTUP_S" ] || fail "Servo not switched to TWIST within ${STARTUP_S} s"
  sleep 2
done
echo "measure: Servo takes twists $((SECONDS - start)) s after docker run"

if [ -n "$GZ_RTF" ]; then
  reply=$(in_arm "gz service -s /world/${WORLD}/set_physics --reqtype gz.msgs.Physics \
    --reptype gz.msgs.Boolean --timeout 5000 \
    --req 'max_step_size: 0.001 real_time_factor: ${GZ_RTF}'" </dev/null 2>&1)
  grep -q 'data: true' <<<"$reply" || fail "set_physics real_time_factor ${GZ_RTF}: ${reply}"
  echo "measure: Gazebo's target real-time factor set to ${GZ_RTF}"
  sleep 3
fi

rtf=$(probe $((STATS_S + 25)) stats "$STATS_S" </dev/null) || fail "/stats: ${rtf}"
echo "measure: real-time factor (idle, ${STATS_S} s): ${rtf}"
camera=$(probe $((STATS_S + 45)) camera "$STATS_S" </dev/null) || fail "wrist camera: ${camera}"
echo "measure: wrist camera: ${camera}"
echo "measure: container $(docker stats --no-stream --format '{{.CPUPerc}} CPU, {{.MemUsage}}' "$NAME")"

status=0
in_arm "timeout -s INT -k 2 $((HOLD_SECONDS + 240)) python3 /tmp/hold_clock_check.py --seconds ${HOLD_SECONDS}" \
  </dev/null | indent
hold=${PIPESTATUS[0]}
if [ "$hold" -eq 0 ]; then
  echo "measure: hold_clock_check: PASS"
else
  echo "measure: hold_clock_check: FAIL (exit ${hold})"
  status=1
fi

if [ "$RUNS" -gt 0 ]; then
  before=$(probe 20 snapshot </dev/null) || fail "/stats: ${before}"
  grasp_start=$SECONDS
  in_arm "timeout -s INT -k 2 $((RUNS * 120 + 240)) python3 /tmp/grasp_test.py --runs ${RUNS}" \
    </dev/null | indent
  grasp=${PIPESTATUS[0]}
  after=$(probe 20 snapshot </dev/null) || fail "/stats: ${after}"
  # shellcheck disable=SC2086
  set -- $before $after
  test_rtf=$(awk -v s0="$1" -v r0="$2" -v s1="$3" -v r1="$4" \
    'BEGIN { printf "%.3f (sim %.0f s / real %.0f s)", (s1 - s0) / (r1 - r0), s1 - s0, r1 - r0 }')
  if [ "$grasp" -eq 0 ]; then
    echo "measure: grasp_test --runs ${RUNS}: PASS in $((SECONDS - grasp_start)) s"
  else
    echo "measure: grasp_test --runs ${RUNS}: FAIL (exit ${grasp}) in $((SECONDS - grasp_start)) s"
    status=1
  fi
  echo "measure: real-time factor over the grasp test: ${test_rtf}"
fi

echo "measure: done, exit ${status}"
exit "$status"
