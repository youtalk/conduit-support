#!/bin/bash
# Sources ROS 2 and the harness workspace, then runs the container command.
set -e
source "/opt/ros/${ROS_DISTRO}/setup.bash"
source /ros2_ws/install/setup.bash

# CycloneDDS network interface (cyclonedds.xml reads HARNESS_DDS_INTERFACE).
# Automatic selection can pick an interface that is down or not on the phone's
# LAN (a wired port without a cable, a VPN), and the phone never discovers the
# harness. Unless it is set, use the interface that routes to the phone, or the
# one with the default route.
if [ -z "${HARNESS_DDS_INTERFACE:-}" ]; then
  target="${CONDUIT_PHONE_IP:-}"
  case "$target" in "" | localhost | 127.*) target=1.1.1.1 ;; esac
  HARNESS_DDS_INTERFACE=$(ip -o route get "$target" 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')
fi
export HARNESS_DDS_INTERFACE="${HARNESS_DDS_INTERFACE:-lo}"

exec "$@"
