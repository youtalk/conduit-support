#!/bin/bash
# Conduit Robots demo: entrypoint.sh <mode> [launch arguments...]
#
#   mobile   a Zenoh router on port 7447 inside the container, then the TurtleBot3
#            on Nav2's loopback simulator with the map camera (mobile.launch.py)
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

if [ $# -eq 0 ]; then
  echo "usage: entrypoint.sh mobile [launch arguments...] | <command>" >&2
  exit 2
fi

mode="$1"
case "$mode" in
  mobile)
    shift
    start_router
    exec ros2 launch conduit_demo mobile.launch.py "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
