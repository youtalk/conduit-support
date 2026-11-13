#!/bin/bash
# Conduit Robots demo: entrypoint.sh <mode> [launch arguments...]
#
#   standalone  a Zenoh router on port 7447 inside the container, then both robots
#               (demo.launch.py: the TurtleBot3 and the Panda; arguments such as
#               gpu:=true go to it). For a PC without ROS 2: publish the router's port.
#   join        both robots on the ROS 2 graph the environment describes, for a PC with
#               ROS 2 (run on the host network): RMW_IMPLEMENTATION, ROS_DOMAIN_ID and
#               ZENOH_CONFIG_OVERRIDE (a client of the PC's router) or CYCLONEDDS_URI.
#               It starts no router and no ROS 2 daemon. check_conflicts reads the graph
#               first: when the PC already uses a name of the demo, it prints a
#               `CONFLICT <name>` line for each and the container exits 3 without
#               starting the demo; otherwise demo.launch.py, as in standalone.
#   all         the same as standalone
#   mobile      the router, then the TurtleBot3 on Nav2's loopback simulator with the
#               map camera (mobile.launch.py)
#   arm         the router, then the Panda in Gazebo with the wrist camera, MoveIt Servo
#               and move_group (arm.launch.py; arguments such as gpu:=true go to it)
#
# Anything else runs as a command with ROS 2 and the demo workspace sourced, for
# example: docker run --rm -it conduit-demo:lyrical-dev bash
#
# set -e only: the setup scripts read unset variables, so no -u.
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
  echo "usage: entrypoint.sh standalone|join|all|mobile|arm [launch arguments...] | <command>" >&2
  exit 2
fi

mode="$1"
case "$mode" in
  standalone | all)
    shift
    start_router
    exec ros2 launch conduit_demo demo.launch.py "$@"
    ;;
  join)
    shift
    status=0
    ros2 run conduit_demo check_conflicts || status=$?
    if [ "$status" -ne 0 ]; then
      exit "$status"
    fi
    exec ros2 launch conduit_demo demo.launch.py "$@"
    ;;
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
  *)
    exec "$@"
    ;;
esac
