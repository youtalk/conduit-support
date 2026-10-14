#!/bin/bash
# Sources ROS 2 and the harness workspace, then runs the container command.
set -e
source "/opt/ros/${ROS_DISTRO}/setup.bash"
source /ros2_ws/install/setup.bash
exec "$@"
