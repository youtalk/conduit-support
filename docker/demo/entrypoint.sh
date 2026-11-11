#!/bin/bash
# Conduit Robots demo: entrypoint.sh <mode> [launch arguments...]
#
#   mobile   a Zenoh router on port 7447 inside the container, then the TurtleBot3
#            on Nav2's loopback simulator with the map camera (mobile.launch.py)
#   arm      the router, then the Panda in Gazebo with the wrist camera, MoveIt Servo
#            and move_group (arm.launch.py; arguments such as gpu:=true go to it)
#   all      the router, then both robots (mobile.launch.py and arm.launch.py; the
#            arguments go to arm.launch.py). Ctrl-C (SIGINT, Docker's stop signal)
#            stops both; either launch ending stops the other.
#
# Anything else runs as a command with ROS 2 and the demo workspace sourced, for
# example: docker run --rm -it conduit-demo:lyrical-dev bash
set -e
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# shellcheck source=/dev/null
source /ros2_ws/install/setup.bash

ROUTER_PORT=7447

# Starts rmw_zenohd in the background and waits until it accepts connections, so
# the nodes find their router on the first try.
start_router() {
  export RMW_IMPLEMENTATION=rmw_zenoh_cpp
  ros2 run rmw_zenoh_cpp rmw_zenohd &
  for _ in $(seq 1 50); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${ROUTER_PORT}") 2>/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  echo "entrypoint: the Zenoh router did not start on port ${ROUTER_PORT}" >&2
  exit 1
}

# Runs mobile.launch.py and arm.launch.py side by side until one of them ends or a
# SIGINT / SIGTERM arrives, then stops both with SIGINT (their Ctrl-C shutdown). A
# non-interactive shell starts background commands with SIGINT ignored, which ros2
# launch would keep; env --default-signal=INT gives it back.
run_all() {
  env --default-signal=INT ros2 launch conduit_demo mobile.launch.py &
  local mobile=$!
  env --default-signal=INT ros2 launch conduit_demo arm.launch.py "$@" &
  local arm=$!
  trap 'kill -INT "$mobile" "$arm" 2>/dev/null || true' INT TERM
  local status=0
  wait -n "$mobile" "$arm" || status=$?
  kill -INT "$mobile" "$arm" 2>/dev/null || true
  wait "$mobile" "$arm" || true
  return "$status"
}

if [ $# -eq 0 ]; then
  echo "usage: entrypoint.sh mobile|arm|all [launch arguments...] | <command>" >&2
  exit 2
fi

mode="$1"
case "$mode" in
  mobile)
    shift
    start_router
    exec ros2 launch conduit_demo mobile.launch.py "$@"
    ;;
  arm)
    shift
    start_router
    exec ros2 launch conduit_demo arm.launch.py "$@"
    ;;
  all)
    shift
    start_router
    run_all "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
