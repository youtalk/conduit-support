#!/bin/bash
# Conduit's Zenoh router container.
#   router (default)  rmw_zenohd on port 7447, in the foreground. It logs
#                     "Started Zenoh router with id ..." once it listens; pair.sh
#                     waits for that line.
#   anything else     runs as a command with ROS 2 sourced, for example bash.
set -e
if [ $# -eq 0 ] || [ "$1" = router ]; then
  # shellcheck source=/dev/null
  source "/opt/ros/${ROS_DISTRO}/setup.bash"
  exec "$(ros2 pkg prefix rmw_zenoh_cpp)/lib/rmw_zenoh_cpp/rmw_zenohd"
fi
exec /usr/local/bin/with-ros "$@"
