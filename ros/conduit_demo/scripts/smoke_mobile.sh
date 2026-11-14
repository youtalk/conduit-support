#!/bin/bash
# Smoke test of the demo image's mobile robot (Linux with Docker).
#
#   bash smoke_mobile.sh <image> <host-port> <domain>
#   bash smoke_mobile.sh conduit-demo:lyrical-dev 7470 130
#
# Starts <image> in mode `mobile` with its Zenoh router published on <host-port>, then
# checks the robot from a second container of the same image, a Zenoh client of that
# router on the host network:
#   - the names table: /map, /odom, /scan, /camera/image_raw (the only image topic),
#     /battery_state, /joy, /turtlebot3/{robot_description,joint_states} and the
#     /navigate_to_pose action, with their types;
#   - no /clock, /robot_description or /joint_states;
#   - /diagnostics carries a status of one of Nav2's lifecycle managers;
#   - /camera/image_raw at 8 Hz or more;
#   - a NavigateToPose goal to a free point of the map succeeds within 60 s;
#   - a /joy message with the deadman held and the stick forward moves /odom;
#   - no ROS 2 daemon was started.
# Prints `SMOKE MOBILE PASS` or `SMOKE MOBILE FAIL: <check>`; exit 0 on pass. Both
# containers are removed on exit. SMOKE_STARTUP_S (default 180) bounds the wait for the
# graph.
#
# SMOKE_ROBOT_CONTAINER=<name> checks a demo container that is already running instead
# (mode standalone, join, all or mobile), through the Zenoh router on <host-port>: its
# own, published there, or the one it joined. That container is left running. With the
# arm on the same graph (any mode but mobile), /clock, /robot_description and
# /joint_states must come from the arm alone (ros_gz_bridge, robot_state_publisher and
# arm_clock), and /head_camera/image_raw and /wrist_camera/image_raw are image topics too.
set -u

if [ $# -ne 3 ]; then
  echo "usage: smoke_mobile.sh <image> <host-port> <domain>" >&2
  exit 2
fi
IMAGE="$1"
PORT="$2"
DOMAIN="$3"
STARTUP_S="${SMOKE_STARTUP_S:-180}"
ROBOT="conduit-demo-smoke-robot-${PORT}"
CLIENT="conduit-demo-smoke-client-${PORT}"
EXISTING="${SMOKE_ROBOT_CONTAINER:-}"
if [ -n "$EXISTING" ]; then
  ROBOT="$EXISTING"
fi

cleanup() {
  if [ -n "$EXISTING" ]; then
    docker rm -f "$CLIENT" >/dev/null 2>&1 || true
  else
    docker rm -f "$ROBOT" "$CLIENT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

fail() {
  echo "SMOKE MOBILE FAIL: $*"
  echo "--- last lines of the robot container's log ---"
  docker logs --tail 40 "$ROBOT" 2>&1 || true
  exit 1
}

# Runs a command in the client container with ROS 2 sourced.
in_client() {
  docker exec -i "$CLIENT" bash -c "source /opt/ros/\$ROS_DISTRO/setup.bash && $1"
}

# Runs one of the rclpy checks below in the client container, bounded by <seconds>.
check() {
  local seconds="$1"
  shift
  printf '%s\n' "$CHECKS_PY" | in_client "timeout -s INT -k 2 ${seconds} python3 - $*"
}

# read returns 1 at the end of the here-document.
read -r -d '' CHECKS_PY <<'PY' || true
"""rclpy checks for smoke_mobile.sh (no ros2 CLI, so no daemon)."""

import math
import sys
import time

import rclpy
from rclpy.qos import qos_profile_sensor_data


def spin_until(node, condition, timeout_s):
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if condition():
            return True
        rclpy.spin_once(node, timeout_sec=0.05)
    return condition()


def action(node, name, type_name):
    if hasattr(node, 'get_action_names_and_types'):
        names_and_types = node.get_action_names_and_types
    else:  # before Lyrical
        from rclpy.action import get_action_names_and_types
        names_and_types = lambda: get_action_names_and_types(node)  # noqa: E731
    found = {}
    def present():
        found.update(dict(names_and_types()))
        return type_name in found.get(name, [])
    if not spin_until(node, present, 10.0):
        return f'action {name} [{type_name}] missing (actions: {sorted(found.items())})'
    print(f'action {name} [{type_name}]')
    return None


def rate(node, topic, min_hz, window_s=5.0):
    from sensor_msgs.msg import Image
    arrivals = []
    node.create_subscription(
        Image, topic, lambda _msg: arrivals.append(time.monotonic()), qos_profile_sensor_data)
    if not spin_until(node, lambda: arrivals, 30.0):
        return f'no message on {topic} within 30 s'
    arrivals.clear()
    spin_until(node, lambda: False, window_s)
    if len(arrivals) < 2:
        return f'{topic}: {len(arrivals)} messages in {window_s:.0f} s'
    hz = (len(arrivals) - 1) / (arrivals[-1] - arrivals[0])
    print(f'{topic}: {hz:.1f} Hz over {window_s:.0f} s')
    if hz < min_hz:
        return f'{topic} at {hz:.1f} Hz, below {min_hz} Hz'
    return None


def navigate(node, x, y, limit_s=60.0):
    from action_msgs.msg import GoalStatus
    from nav2_msgs.action import NavigateToPose
    from rclpy.action import ActionClient
    client = ActionClient(node, NavigateToPose, '/navigate_to_pose')
    if not client.wait_for_server(timeout_sec=30.0):
        return '/navigate_to_pose server not available within 30 s'
    goal = NavigateToPose.Goal()
    goal.pose.header.frame_id = 'map'
    goal.pose.pose.position.x = x
    goal.pose.pose.position.y = y
    goal.pose.pose.orientation.w = 1.0
    # Nav2 rejects goals until its lifecycle nodes are active: retry for a while.
    deadline = time.monotonic() + 60.0
    while True:
        future = client.send_goal_async(goal)
        rclpy.spin_until_future_complete(node, future, timeout_sec=10.0)
        handle = future.result()
        if handle is not None and handle.accepted:
            break
        if time.monotonic() > deadline:
            return 'NavigateToPose goal rejected for 60 s'
        spin_until(node, lambda: False, 2.0)
    start = time.monotonic()
    result = handle.get_result_async()
    rclpy.spin_until_future_complete(node, result, timeout_sec=limit_s)
    elapsed = time.monotonic() - start
    if not result.done():
        handle.cancel_goal_async()
        spin_until(node, lambda: False, 1.0)
        return f'NavigateToPose to ({x}, {y}) not finished within {limit_s:.0f} s'
    status = result.result().status
    if status != GoalStatus.STATUS_SUCCEEDED:
        return f'NavigateToPose to ({x}, {y}) ended with status {status} after {elapsed:.1f} s'
    print(f'NavigateToPose to ({x}, {y}): SUCCEEDED in {elapsed:.1f} s')
    return None


def publishers(node, expected, timeout_s=60.0):
    """Each topic's publishers are exactly the named nodes: [(topic, [node, ...])]."""
    found = {}
    def exact():
        for topic, names in expected:
            found[topic] = sorted(
                info.node_name for info in node.get_publishers_info_by_topic(topic))
        return all(found[topic] == sorted(names) for topic, names in expected)
    if not spin_until(node, exact, timeout_s):
        return f'publishers {found}, expected {dict(expected)}'
    for topic, names in expected:
        print(f'{topic} published by {" ".join(names)} only')
    return None


def diagnostics(node, prefix, timeout_s=30.0):
    """A DiagnosticArray on /diagnostics with a status whose name starts with `prefix`
    (diagnostic_updater names each status `<node>: <task>`)."""
    from diagnostic_msgs.msg import DiagnosticArray
    statuses = set()
    def on_diagnostics(msg):
        statuses.update(status.name for status in msg.status)
    node.create_subscription(
        DiagnosticArray, '/diagnostics', on_diagnostics, qos_profile_sensor_data)
    def matching():
        return any(name.startswith(prefix) for name in statuses)
    if not spin_until(node, matching, timeout_s):
        return (f'no /diagnostics status named {prefix}... within {timeout_s:.0f} s '
                f'(statuses seen: {sorted(statuses)})')
    publishers = sorted(
        info.node_name for info in node.get_publishers_info_by_topic('/diagnostics'))
    print(f'/diagnostics from {" ".join(publishers)}: {sorted(statuses)}')
    return None


def drive(node, enable_button, linear_axis, seconds=3.0, min_distance=0.3):
    from nav_msgs.msg import Odometry
    from sensor_msgs.msg import Joy
    poses = []
    node.create_subscription(
        Odometry, '/odom', lambda m: poses.append(m.pose.pose.position),
        qos_profile_sensor_data)
    joy_pub = node.create_publisher(Joy, '/joy', 10)
    if not spin_until(node, lambda: poses, 10.0):
        return 'no /odom message within 10 s'
    if not spin_until(node, lambda: joy_pub.get_subscription_count() > 0, 10.0):
        return 'nothing subscribes to /joy'
    spin_until(node, lambda: False, 1.0)
    start = poses[-1]
    joy = Joy()
    joy.axes = [0.0] * 6
    joy.buttons = [0] * 15
    joy.axes[linear_axis] = 1.0
    joy.buttons[enable_button] = 1
    end_time = time.monotonic() + seconds
    while time.monotonic() < end_time:
        joy.header.stamp = node.get_clock().now().to_msg()
        joy_pub.publish(joy)
        spin_until(node, lambda: False, 0.05)
    spin_until(node, lambda: False, 0.5)
    end = poses[-1]
    distance = math.hypot(end.x - start.x, end.y - start.y)
    print(f'/joy (button {enable_button} held, axis {linear_axis} = 1.0) for {seconds:.0f} s: '
          f'/odom moved {distance:.2f} m')
    if distance < min_distance:
        return f'/joy did not move /odom ({distance:.2f} m < {min_distance} m)'
    return None


def main():
    rclpy.init()
    node = rclpy.create_node('conduit_demo_smoke')
    name, args = sys.argv[1], sys.argv[2:]
    try:
        if name == 'action':
            error = action(node, args[0], args[1])
        elif name == 'rate':
            error = rate(node, args[0], float(args[1]))
        elif name == 'navigate':
            error = navigate(node, float(args[0]), float(args[1]))
        elif name == 'drive':
            error = drive(node, int(args[0]), int(args[1]))
        elif name == 'diagnostics':
            error = diagnostics(node, args[0])
        elif name == 'publishers':
            error = publishers(node, [
                (topic, names.split(',')) for topic, names in
                (arg.split('=', 1) for arg in args)])
        else:
            error = f'unknown check {name}'
    finally:
        node.destroy_node()
        rclpy.try_shutdown()
    if error:
        print(error)
        sys.exit(1)


main()
PY

cleanup
if [ -n "$EXISTING" ]; then
  MODE=$(docker inspect -f '{{if .Args}}{{index .Args 0}}{{end}}' "$ROBOT" 2>/dev/null) \
    || fail "no container ${ROBOT}"
  echo "Checking the running container ${ROBOT} (mode ${MODE}) through the router on" \
    "host port ${PORT}, domain ${DOMAIN}"
else
  MODE=mobile
  echo "Starting ${IMAGE} (mode mobile, router on host port ${PORT}, domain ${DOMAIN})"
  docker run -d --name "$ROBOT" -p "${PORT}:7447" -e ROS_DOMAIN_ID="$DOMAIN" \
    "$IMAGE" mobile >/dev/null || fail "docker run ${IMAGE} mobile"
fi
WITH_ARM=false
[ "$MODE" = mobile ] || WITH_ARM=true
docker run -d --name "$CLIENT" --network host --entrypoint sleep \
  -e RMW_IMPLEMENTATION=rmw_zenoh_cpp -e ROS_DOMAIN_ID="$DOMAIN" \
  -e ZENOH_CONFIG_OVERRIDE="mode=\"client\";connect/endpoints=[\"tcp/127.0.0.1:${PORT}\"]" \
  "$IMAGE" infinity >/dev/null || fail "docker run the client container"

# 1. Names table: wait until every topic is there with its type.
EXPECTED_TOPICS=(
  "/map [nav_msgs/msg/OccupancyGrid]"
  "/odom [nav_msgs/msg/Odometry]"
  "/scan [sensor_msgs/msg/LaserScan]"
  "/camera/image_raw [sensor_msgs/msg/Image]"
  "/battery_state [sensor_msgs/msg/BatteryState]"
  "/joy [sensor_msgs/msg/Joy]"
  "/turtlebot3/robot_description [std_msgs/msg/String]"
  "/turtlebot3/joint_states [sensor_msgs/msg/JointState]"
  "/diagnostics [diagnostic_msgs/msg/DiagnosticArray]"
)
ABSENT_TOPICS=(/clock /robot_description /joint_states)
EXPECTED_IMAGES="/camera/image_raw "
if [ "$WITH_ARM" = true ]; then
  EXPECTED_TOPICS+=(
    "/clock [rosgraph_msgs/msg/Clock]"
    "/robot_description [std_msgs/msg/String]"
    "/joint_states [sensor_msgs/msg/JointState]"
    "/head_camera/image_raw [sensor_msgs/msg/Image]"
    "/wrist_camera/image_raw [sensor_msgs/msg/Image]"
  )
  EXPECTED_IMAGES="/camera/image_raw /head_camera/image_raw /wrist_camera/image_raw "
fi

topics=""
missing=("${EXPECTED_TOPICS[@]}")
deadline=$((SECONDS + STARTUP_S))
while [ ${#missing[@]} -gt 0 ] && [ $SECONDS -lt $deadline ]; do
  sleep 3
  topics=$(in_client "timeout -s INT -k 2 20 ros2 topic list -t --no-daemon" </dev/null 2>/dev/null)
  missing=()
  for entry in "${EXPECTED_TOPICS[@]}"; do
    grep -qxF "$entry" <<<"$topics" || missing+=("$entry")
  done
done
if [ ${#missing[@]} -gt 0 ]; then
  printf 'topics seen:\n%s\n' "$topics"
  fail "topics missing after ${STARTUP_S} s: ${missing[*]}"
fi
echo "topics present: ${EXPECTED_TOPICS[*]}"

if [ "$WITH_ARM" = true ]; then
  check 70 publishers /clock=ros_gz_bridge /robot_description=robot_state_publisher \
    /joint_states=arm_clock || fail "publishers of the arm's topics"
else
  for name in "${ABSENT_TOPICS[@]}"; do
    if grep -q "^${name} \[" <<<"$topics"; then
      fail "${name} exists"
    fi
  done
  echo "topics absent: ${ABSENT_TOPICS[*]}"
fi

images=$(grep -E '\[sensor_msgs/msg/(Image|CompressedImage)\]' <<<"$topics" | cut -d' ' -f1 | tr '\n' ' ')
[ "$images" = "$EXPECTED_IMAGES" ] || fail "image topics are '${images}', expected '${EXPECTED_IMAGES}'"

check 30 action /navigate_to_pose nav2_msgs/action/NavigateToPose || fail "action /navigate_to_pose"
# Nav2's lifecycle managers report its health: lifecycle_manager_nav2 on Lyrical,
# lifecycle_manager_navigation and lifecycle_manager_map_server before it.
check 40 diagnostics lifecycle_manager_ || fail "/diagnostics"

# 2. The map camera's rate.
check 60 rate /camera/image_raw 8 || fail "/camera/image_raw rate"

# 3. A goal to a free point of tb3_sandbox (0.6 m from the nearest wall).
check 160 navigate 0.6 -0.6 || fail "NavigateToPose"

# 4. Joy drives the robot. Conduit's layout, as in conduit_teleop's
#    config/teleop_twist_joy.yaml: enable_button 9 (deadman), axis_linear.x 1.
check 40 drive 9 1 || fail "/joy -> /odom"

# 5. No ROS 2 daemon: the client shares the host network, so a daemon there would
#    serve the host's ros2 CLI. The daemon's command line holds `_ros2_daemon` (Jazzy)
#    or `--name ros2-daemon` (Lyrical); the brackets keep grep from finding itself.
DAEMON_PATTERN='ros2[-_][d]aemon'
for container in "$CLIENT" "$ROBOT"; do
  if docker exec "$container" bash -c "grep -lE '${DAEMON_PATTERN}' /proc/[0-9]*/cmdline" >/dev/null 2>&1; then
    fail "a ROS 2 daemon runs in ${container}"
  fi
done
echo "no ROS 2 daemon"

echo "SMOKE MOBILE PASS"
