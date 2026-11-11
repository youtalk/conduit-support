#!/bin/bash
# Smoke test of the demo image's arm (Linux with Docker).
#
#   bash smoke_arm.sh <image> <host-port> <domain>
#   bash smoke_arm.sh conduit-demo:lyrical-dev 7471 131
#
# Starts <image> in mode `arm` with its Zenoh router published on <host-port>, then
# checks the arm from a second container of the same image, a Zenoh client of that
# router on the host network:
#   - the topics /joint_states, /wrist_camera/image_raw, /wrist_camera/camera_info,
#     /robot_description, /robot_description_semantic, /servo_node/status, /clock and
#     /diagnostics, and the actions /move_action and /panda_hand_controller/gripper_cmd,
#     with their types;
#   - joint_state_broadcaster, panda_arm_controller and panda_hand_controller active;
#   - /diagnostics carries the controller manager's status;
#   - /joint_states carries panda_finger_joint1;
#   - /wrist_camera/image_raw is 320 x 240 at 8 Hz or more, /wrist_camera/camera_info
#     publishes;
#   - /robot_description_semantic (transient local) has the panda_arm states
#     `extended` and `ready`;
#   - the launch switched Servo to TWIST commands;
#   - GripperCommand goals to 0.0 and 0.04 succeed with result.position within 0.005 m of
#     the target and move panda_finger_joint1 there;
#   - a goal to 0.0, a second to 0.04 about 100 ms later, then a cancel of the first: the
#     first ends aborted (or canceled), the second succeeds at 0.04, the finger ends at 0.04;
#   - MoveGroup goals to the SRDF states `extended`, `transport` and `ready` succeed
#     (error code 1);
#   - no ROS 2 daemon was started.
# Prints `SMOKE ARM PASS` or `SMOKE ARM FAIL: <check>`; exit 0 on pass. Both containers
# are removed on exit. SMOKE_STARTUP_S (default 300) bounds the wait for the graph.
#
# SMOKE_ROBOT_CONTAINER=<name> checks a demo container that is already running instead
# (mode standalone, join, all or arm), through the Zenoh router on <host-port>: its own,
# published there, or the one it joined. That container is left running.
set -u

if [ $# -ne 3 ]; then
  echo "usage: smoke_arm.sh <image> <host-port> <domain>" >&2
  exit 2
fi
IMAGE="$1"
PORT="$2"
DOMAIN="$3"
STARTUP_S="${SMOKE_STARTUP_S:-300}"
ROBOT="conduit-demo-smoke-arm-${PORT}"
CLIENT="conduit-demo-smoke-arm-client-${PORT}"
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
  echo "SMOKE ARM FAIL: $*"
  echo "--- last lines of the robot container's log ---"
  docker logs --tail 60 "$ROBOT" 2>&1 || true
  exit 1
}

robot_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$ROBOT" 2>/dev/null)" = "true" ]
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
"""rclpy checks for smoke_arm.sh (no ros2 CLI, so no daemon)."""

import sys
import time
import xml.etree.ElementTree as ET

import rclpy
from rclpy.qos import DurabilityPolicy, QoSProfile, qos_profile_sensor_data

ARM_GROUP = 'panda_arm'
FINGER = 'panda_finger_joint1'


def spin_until(node, condition, timeout_s):
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if condition():
            return True
        rclpy.spin_once(node, timeout_sec=0.05)
    return condition()


def actions(node, expected):
    if hasattr(node, 'get_action_names_and_types'):
        names_and_types = node.get_action_names_and_types
    else:  # before Lyrical
        from rclpy.action import get_action_names_and_types
        names_and_types = lambda: get_action_names_and_types(node)  # noqa: E731
    found = {}
    def present():
        found.update(dict(names_and_types()))
        return all(type_name in found.get(name, []) for name, type_name in expected)
    if not spin_until(node, present, 20.0):
        return f'actions missing (actions: {sorted(found.items())})'
    for name, type_name in expected:
        print(f'action {name} [{type_name}]')
    return None


def controllers(node, names, timeout_s=120.0):
    from controller_manager_msgs.srv import ListControllers
    client = node.create_client(ListControllers, '/controller_manager/list_controllers')
    states = {}
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if client.wait_for_service(timeout_sec=2.0):
            future = client.call_async(ListControllers.Request())
            rclpy.spin_until_future_complete(node, future, timeout_sec=5.0)
            if future.result() is not None:
                states = {c.name: c.state for c in future.result().controller}
                if all(states.get(name) == 'active' for name in names):
                    print('controllers active: ' + ' '.join(names))
                    return None
        spin_until(node, lambda: False, 2.0)
    return f'controllers not all active after {timeout_s:.0f} s: {states}'


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


def finger(node):
    from sensor_msgs.msg import JointState
    names = []
    node.create_subscription(
        JointState, '/joint_states', lambda m: names.extend(m.name), qos_profile_sensor_data)
    if not spin_until(node, lambda: names, 20.0):
        return 'no /joint_states message within 20 s'
    if FINGER not in names:
        return f'/joint_states has no {FINGER}: {sorted(set(names))}'
    print(f'/joint_states carries {FINGER}')
    return None


def camera(node, topic, info_topic, width, height, min_hz, window_s=5.0):
    from sensor_msgs.msg import CameraInfo, Image
    arrivals = []
    sizes = set()
    infos = []
    def on_image(msg):
        arrivals.append(time.monotonic())
        sizes.add((msg.width, msg.height, msg.encoding, msg.header.frame_id))
    node.create_subscription(Image, topic, on_image, qos_profile_sensor_data)
    node.create_subscription(CameraInfo, info_topic, infos.append, qos_profile_sensor_data)
    if not spin_until(node, lambda: arrivals and infos, 60.0):
        return f'no message on {topic} and {info_topic} within 60 s'
    arrivals.clear()
    spin_until(node, lambda: False, window_s)
    if len(arrivals) < 2:
        return f'{topic}: {len(arrivals)} messages in {window_s:.0f} s'
    hz = (len(arrivals) - 1) / (arrivals[-1] - arrivals[0])
    info = infos[-1]
    print(f'{topic}: {hz:.1f} Hz over {window_s:.0f} s, {sorted(sizes)}')
    print(f'{info_topic}: {info.width} x {info.height}, frame {info.header.frame_id}, '
          f'k {[round(float(v), 1) for v in info.k]}')
    if any((w, h) != (width, height) for w, h, _, _ in sizes):
        return f'{topic} is {sorted(sizes)}, expected {width} x {height}'
    if hz < min_hz:
        return f'{topic} at {hz:.1f} Hz, below {min_hz} Hz'
    return None


def semantic(node):
    """The SRDF from /robot_description_semantic: {state name: {joint: value}} for the arm."""
    from std_msgs.msg import String
    latched = QoSProfile(depth=1, durability=DurabilityPolicy.TRANSIENT_LOCAL)
    received = []
    node.create_subscription(String, '/robot_description_semantic', received.append, latched)
    if not spin_until(node, lambda: received, 30.0):
        return None, 'no /robot_description_semantic message within 30 s (transient local)'
    states = {}
    for state in ET.fromstring(received[-1].data).iter('group_state'):
        if state.get('group') == ARM_GROUP:
            states[state.get('name')] = {
                j.get('name'): float(j.get('value')) for j in state.iter('joint')}
    print(f'/robot_description_semantic: {ARM_GROUP} states {sorted(states)}')
    return states, None


def poses(node, names):
    states, error = semantic(node)
    if error:
        return error
    missing = [name for name in names if name not in states]
    if missing:
        return f'SRDF has no {ARM_GROUP} state {missing}'
    from moveit_msgs.action import MoveGroup
    from moveit_msgs.msg import Constraints, JointConstraint
    from rclpy.action import ActionClient
    client = ActionClient(node, MoveGroup, '/move_action')
    if not client.wait_for_server(timeout_sec=30.0):
        return '/move_action server not available within 30 s'
    for name in names:
        goal = MoveGroup.Goal()
        request = goal.request
        request.group_name = ARM_GROUP
        request.num_planning_attempts = 5
        request.allowed_planning_time = 5.0
        request.max_velocity_scaling_factor = 0.5
        request.max_acceleration_scaling_factor = 0.5
        constraints = Constraints(name=name)
        for joint, value in states[name].items():
            constraints.joint_constraints.append(JointConstraint(
                joint_name=joint, position=value,
                tolerance_above=0.01, tolerance_below=0.01, weight=1.0))
        request.goal_constraints.append(constraints)
        goal.planning_options.plan_only = False
        start = time.monotonic()
        future = client.send_goal_async(goal)
        rclpy.spin_until_future_complete(node, future, timeout_sec=10.0)
        handle = future.result()
        if handle is None or not handle.accepted:
            return f'MoveGroup goal {name} rejected'
        result = handle.get_result_async()
        rclpy.spin_until_future_complete(node, result, timeout_sec=60.0)
        if not result.done():
            handle.cancel_goal_async()
            spin_until(node, lambda: False, 1.0)
            return f'MoveGroup goal {name} not finished within 60 s'
        code = result.result().result.error_code.val
        print(f'MoveGroup to {name}: error code {code} in {time.monotonic() - start:.1f} s')
        if code != 1:
            return f'MoveGroup goal {name} ended with error code {code}'
    return None


def gripper_client(node):
    """(client, finger position list, error): the GripperCommand client and /joint_states."""
    from control_msgs.action import GripperCommand
    from rclpy.action import ActionClient
    from sensor_msgs.msg import JointState
    position = []
    def on_joints(msg):
        if FINGER in msg.name:
            position[:] = [msg.position[msg.name.index(FINGER)]]
    node.create_subscription(JointState, '/joint_states', on_joints, qos_profile_sensor_data)
    client = ActionClient(node, GripperCommand, '/panda_hand_controller/gripper_cmd')
    if not client.wait_for_server(timeout_sec=30.0):
        return None, None, '/panda_hand_controller/gripper_cmd server not available within 30 s'
    if not spin_until(node, lambda: position, 10.0):
        return None, None, f'no {FINGER} in /joint_states within 10 s'
    return client, position, None


def send_gripper_goal(node, client, target):
    """The accepted goal handle for a GripperCommand goal to `target`, or None."""
    from control_msgs.action import GripperCommand
    goal = GripperCommand.Goal()
    goal.command.position = target
    goal.command.max_effort = 20.0
    future = client.send_goal_async(goal)
    rclpy.spin_until_future_complete(node, future, timeout_sec=10.0)
    handle = future.result()
    return handle if handle is not None and handle.accepted else None


def gripper_result(node, handle, timeout_s=20.0):
    future = handle.get_result_async()
    rclpy.spin_until_future_complete(node, future, timeout_sec=timeout_s)
    return future.result() if future.done() else None


def gripper(node, targets, tolerance=0.005):
    from action_msgs.msg import GoalStatus
    client, position, error = gripper_client(node)
    if error:
        return error
    for target in targets:
        start = time.monotonic()
        handle = send_gripper_goal(node, client, target)
        if handle is None:
            return f'GripperCommand goal {target} rejected'
        reply = gripper_result(node, handle)
        if reply is None:
            return f'GripperCommand goal {target} not finished within 20 s'
        reached = spin_until(node, lambda: abs(position[0] - target) <= tolerance, 5.0)
        print(f'GripperCommand to {target}: status {reply.status}, result position '
              f'{reply.result.position:.4f}, {FINGER} {position[0]:.4f} after '
              f'{time.monotonic() - start:.1f} s')
        if reply.status != GoalStatus.STATUS_SUCCEEDED:
            return f'GripperCommand goal {target} ended with status {reply.status}'
        if abs(reply.result.position - target) > tolerance:
            return f'result.position {reply.result.position:.4f} not within {tolerance} of {target}'
        if not reached:
            return f'{FINGER} at {position[0]:.4f}, not within {tolerance} of {target}'
    return None


def gripper_preempt(node, first, second, tolerance=0.005):
    """A goal to `first`, one to `second` 100 ms later, then a cancel of the first."""
    from action_msgs.msg import GoalStatus
    client, position, error = gripper_client(node)
    if error:
        return error
    handle_first = send_gripper_goal(node, client, first)
    if handle_first is None:
        return f'GripperCommand goal {first} rejected'
    spin_until(node, lambda: False, 0.1)
    handle_second = send_gripper_goal(node, client, second)
    if handle_second is None:
        return f'GripperCommand goal {second} rejected'
    cancel = handle_first.cancel_goal_async()
    rclpy.spin_until_future_complete(node, cancel, timeout_sec=5.0)
    reply_first = gripper_result(node, handle_first)
    reply_second = gripper_result(node, handle_second)
    if reply_first is None or reply_second is None:
        return 'GripperCommand goals not finished within 20 s'
    reached = spin_until(node, lambda: abs(position[0] - second) <= tolerance, 5.0)
    print(f'GripperCommand {first} then {second} 100 ms later, first cancelled: first status '
          f'{reply_first.status}, second status {reply_second.status}, result position '
          f'{reply_second.result.position:.4f}, {FINGER} {position[0]:.4f}')
    if reply_first.status not in (GoalStatus.STATUS_ABORTED, GoalStatus.STATUS_CANCELED):
        return f'first goal ended with status {reply_first.status}, not aborted or canceled'
    if reply_second.status != GoalStatus.STATUS_SUCCEEDED:
        return f'second goal ended with status {reply_second.status}'
    if abs(reply_second.result.position - second) > tolerance:
        return (f'second result.position {reply_second.result.position:.4f} not within '
                f'{tolerance} of {second}')
    if not reached:
        return f'{FINGER} at {position[0]:.4f}, not within {tolerance} of {second}'
    return None


def main():
    rclpy.init()
    node = rclpy.create_node('conduit_demo_smoke_arm')
    name, args = sys.argv[1], sys.argv[2:]
    try:
        if name == 'actions':
            error = actions(node, [tuple(arg.split('=', 1)) for arg in args])
        elif name == 'controllers':
            error = controllers(node, args)
        elif name == 'finger':
            error = finger(node)
        elif name == 'diagnostics':
            error = diagnostics(node, args[0])
        elif name == 'camera':
            error = camera(node, args[0], args[1], int(args[2]), int(args[3]), float(args[4]))
        elif name == 'poses':
            error = poses(node, args)
        elif name == 'gripper':
            error = gripper(node, [float(arg) for arg in args])
        elif name == 'gripper_preempt':
            error = gripper_preempt(node, float(args[0]), float(args[1]))
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
  robot_running || fail "no running container ${ROBOT}"
  echo "Checking the running container ${ROBOT} through the router on host port ${PORT}," \
    "domain ${DOMAIN}"
else
  echo "Starting ${IMAGE} (mode arm, router on host port ${PORT}, domain ${DOMAIN})"
  docker run -d --name "$ROBOT" -p "${PORT}:7447" -e ROS_DOMAIN_ID="$DOMAIN" \
    "$IMAGE" arm >/dev/null || fail "docker run ${IMAGE} arm"
fi
docker run -d --name "$CLIENT" --network host --entrypoint sleep \
  -e RMW_IMPLEMENTATION=rmw_zenoh_cpp -e ROS_DOMAIN_ID="$DOMAIN" \
  -e ZENOH_CONFIG_OVERRIDE="mode=\"client\";connect/endpoints=[\"tcp/127.0.0.1:${PORT}\"]" \
  "$IMAGE" infinity >/dev/null || fail "docker run the client container"

# 1. Names table: wait until every topic is there with its type.
EXPECTED_TOPICS=(
  "/joint_states [sensor_msgs/msg/JointState]"
  "/wrist_camera/image_raw [sensor_msgs/msg/Image]"
  "/wrist_camera/camera_info [sensor_msgs/msg/CameraInfo]"
  "/robot_description [std_msgs/msg/String]"
  "/robot_description_semantic [std_msgs/msg/String]"
  "/servo_node/status [moveit_msgs/msg/ServoStatus]"
  "/clock [rosgraph_msgs/msg/Clock]"
  "/diagnostics [diagnostic_msgs/msg/DiagnosticArray]"
)

topics=""
missing=("${EXPECTED_TOPICS[@]}")
deadline=$((SECONDS + STARTUP_S))
while [ ${#missing[@]} -gt 0 ] && [ $SECONDS -lt $deadline ]; do
  sleep 3
  robot_running || fail "the robot container stopped"
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
echo "topics present after ${SECONDS} s: ${EXPECTED_TOPICS[*]}"

check 40 actions /move_action=moveit_msgs/action/MoveGroup \
  /panda_hand_controller/gripper_cmd=control_msgs/action/GripperCommand || fail "actions"

# 2. Controllers and joint states.
check 140 controllers joint_state_broadcaster panda_arm_controller panda_hand_controller \
  || fail "controllers"
check 40 diagnostics controller_manager: || fail "/diagnostics"
check 40 finger || fail "/joint_states"

# 3. The wrist camera (light setting: 320 x 240 at 10 Hz).
check 90 camera /wrist_camera/image_raw /wrist_camera/camera_info 320 240 8 \
  || fail "wrist camera"

# 4. Servo takes twists: the launch switched its command type to TWIST.
servo_deadline=$((SECONDS + 60))
until docker logs "$ROBOT" 2>&1 | grep -q 'Servo command type set to TWIST'; do
  [ $SECONDS -lt $servo_deadline ] || fail "Servo was not switched to TWIST"
  sleep 2
done
echo "Servo command type: TWIST"

# 5. The gripper: closed, then fully open; then a goal preempted by a newer one (as a
#    drag in Conduit's gripper arc does) and cancelled after it.
check 80 gripper 0.0 0.04 || fail "GripperCommand"
check 80 gripper_preempt 0.0 0.04 || fail "GripperCommand preempted"

# 6. The SRDF pose menu: MoveGroup goals to the panda_arm states.
check 260 poses extended transport ready || fail "MoveGroup"

# 7. No ROS 2 daemon: the client shares the host network, so a daemon there would
#    serve the host's ros2 CLI. The daemon's command line holds `_ros2_daemon` (Jazzy)
#    or `--name ros2-daemon` (Lyrical); the brackets keep grep from finding itself.
DAEMON_PATTERN='ros2[-_][d]aemon'
for container in "$CLIENT" "$ROBOT"; do
  if docker exec "$container" bash -c "grep -lE '${DAEMON_PATTERN}' /proc/[0-9]*/cmdline" >/dev/null 2>&1; then
    fail "a ROS 2 daemon runs in ${container}"
  fi
done
echo "no ROS 2 daemon"

echo "SMOKE ARM PASS"
