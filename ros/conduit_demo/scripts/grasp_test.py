#!/usr/bin/env python3
"""Grasp acceptance test of the demo Panda in Gazebo (light or GPU setting).

Each run picks up one cube the way a Conduit user would, with the demo's own interfaces:

1. open the gripper (GripperCommand on /panda_hand_controller/gripper_cmd, 0.035);
2. MoveGroup (/move_action) to the pre-grasp joint configuration: the hand pointing down,
   LIFT above the grasp height over the cube's start (a /compute_ik solution, seeded with
   the SRDF state `ready`);
3. reset the cubes to their places in worlds/demo_table.sdf (Gazebo `set_pose_vector`);
4. Servo down (TwistStamped on /servo_node/delta_twist_cmds) to the grasp height;
5. close the gripper to 0.0 and require panda_finger_joint1 to stop at the cube
   (>= MIN_FINGER m), both fingers on it (finger1 + finger2 = the cube's width) and the cube
   centred (finger1 = finger2, so finger1 reads half the real opening, as Conduit's gripper
   arc expects);
6. Servo up LIFT (10 cm) from where it gripped and hold 10 s; require the cube >= MIN_LIFT
   (9 cm) above its start and the fingers as in 5 over the whole hold;
7. Servo down LIFT, open, Servo up LIFT; require the cube back on the table (put down).

The cube's pose comes from Gazebo (gz-transport, /world/demo_table/pose/info) and the hand's
from /tf. Twists are stamped on the robot's clock as Conduit stamps them: wall time plus the
offset of /joint_states header stamps from it, so the test works whether the arm runs on
Gazebo's clock or on wall time. A failed run opens the gripper and moves the hand up, and
the next run starts over.

It prints one line per run and a summary, and exits 0 when at least --min-pass runs pass
(default: 9 of 10, i.e. 90 % of --runs rounded up).

It needs rclpy, the message packages and Gazebo's Python bindings, so it runs inside a
container of the demo image in mode `arm`, beside Gazebo, for example:

    docker run -d --name arm conduit-demo:lyrical-dev arm
    docker exec -i arm bash -c \
        'source /opt/ros/$ROS_DISTRO/setup.bash && python3 - --runs 10' < grasp_test.py

or with the copy installed in the image:

    docker exec arm bash -c 'source /opt/ros/$ROS_DISTRO/setup.bash && python3 \
        /ros2_ws/install/conduit_demo/share/conduit_demo/scripts/grasp_test.py --runs 10'

It waits up to --startup-timeout s for the arm's servers. No ROS 2 daemon is used.
"""

import argparse
import math
import subprocess
import sys
import threading
import time
from collections import deque

import rclpy
from action_msgs.msg import GoalStatus
from control_msgs.action import GripperCommand
from geometry_msgs.msg import PoseStamped, TwistStamped
from gz.msgs.pose_v_pb2 import Pose_V
from gz.transport import Node as GzNode
from moveit_msgs.action import MoveGroup
from moveit_msgs.msg import Constraints, JointConstraint
from moveit_msgs.srv import GetPositionIK, ServoCommandType
from rclpy.action import ActionClient
from rclpy.executors import SingleThreadedExecutor
from rclpy.qos import qos_profile_sensor_data
from rclpy.time import Time
from sensor_msgs.msg import JointState
from tf2_ros import Buffer, TransformListener

WORLD = 'demo_table'
ARM_GROUP = 'panda_arm'
BASE_FRAME = 'panda_link0'
HAND_FRAME = 'panda_hand'
FINGER = 'panda_finger_joint1'
MIMIC_FINGER = 'panda_finger_joint2'
GRIPPER_ACTION = '/panda_hand_controller/gripper_cmd'
TWIST_TOPIC = '/servo_node/delta_twist_cmds'
SERVO_COMMAND_TYPE = '/servo_node/switch_command_type'
TWIST_COMMAND_TYPE = 1

# The SRDF state `ready` of panda_arm: the IK seed of the pre-grasp configuration.
READY = {
    'panda_joint1': 0.0, 'panda_joint2': -0.785, 'panda_joint3': 0.0, 'panda_joint4': -2.356,
    'panda_joint5': 0.0, 'panda_joint6': 1.571, 'panda_joint7': 0.785,
}
# panda_hand pointing down with its axes on the world's (as in `ready`): the fingers close
# along the world's y axis, square to the cubes' faces.
HAND_DOWN = (1.0, 0.0, 0.0, 0.0)  # x, y, z, w
TCP_OFFSET = 0.1034  # panda_hand to the point between the finger pads, along the hand's z

# The cubes and their places in worlds/demo_table.sdf.
CUBE_SIZE = 0.045
CUBES = {
    'red': ('red_cube', (0.5, -0.12, CUBE_SIZE / 2)),
    'green': ('green_cube', (0.5, 0.0, CUBE_SIZE / 2)),
    'blue': ('blue_cube', (0.5, 0.12, CUBE_SIZE / 2)),
}

GRASP_HEIGHT = CUBE_SIZE / 2  # the pads' centre at the cube's centre
LIFT = 0.10
MIN_LIFT = 0.09
MIN_FINGER = 0.015
FINGER_SUM_TOLERANCE = 0.006  # finger1 + finger2 vs the cube's width: both fingers on it
FINGER_ASYMMETRY = 0.005      # |finger1 - finger2|: finger1 reports half the real opening
PUT_DOWN_TOLERANCE = 0.005
OPEN = 0.035  # the SRDF state `open`, Conduit's open gripper (--open)
CLOSED = 0.0
# GripperCommand max_effort, as the smoke test sends it. The fingers are position
# controlled, so the force is their effort limit in the URDF whatever this says.
MAX_EFFORT = 20.0


class Failure(Exception):
    """One run failed; the message says why."""


def wait_future(future, timeout_s):
    deadline = time.monotonic() + timeout_s
    while not future.done() and time.monotonic() < deadline:
        time.sleep(0.01)
    return future.done()


class RobotClock:
    """The robot's clock as Conduit estimates it: wall time plus the largest recent offset of
    /joint_states header stamps from wall time (the smallest transport delay)."""

    def __init__(self):
        self._offsets = deque(maxlen=200)
        self._lock = threading.Lock()

    def observe(self, stamp):
        offset = stamp.sec + stamp.nanosec * 1e-9 - time.time()
        with self._lock:
            self._offsets.append(offset)

    def ready(self):
        with self._lock:
            return bool(self._offsets)

    def now(self):
        with self._lock:
            offset = max(self._offsets)
        return Time(seconds=time.time() + offset).to_msg()


class CubePoses:
    """The cubes' world poses from Gazebo's pose/info."""

    def __init__(self, names):
        self._names = set(names)
        self._poses = {}
        self._lock = threading.Lock()
        self._topic = f'/world/{WORLD}/pose/info'
        self._gz = GzNode()
        if not self._gz.subscribe(Pose_V, self._topic, self._on_poses):
            raise RuntimeError(f'cannot subscribe to {self._topic}')

    def close(self):
        """Unsubscribes: a gz-transport subscriber left at interpreter exit segfaults."""
        self._gz.unsubscribe(self._topic)

    def _on_poses(self, message):
        found = {}
        for pose in message.pose:
            if pose.name in self._names:
                p, q = pose.position, pose.orientation
                found[pose.name] = ((p.x, p.y, p.z), (q.x, q.y, q.z, q.w), time.monotonic())
        with self._lock:
            self._poses.update(found)

    def get(self, name, max_age_s=0.5):
        with self._lock:
            entry = self._poses.get(name)
        if entry is None or time.monotonic() - entry[2] > max_age_s:
            return None
        return entry[0], entry[1]

    @staticmethod
    def set(places):
        """Moves each model in `places` ({name: position}) there, upright, in one request.

        Through the `gz service` CLI: a request from this process's gz-transport node can
        time out while the node's pose/info callback waits for the Python GIL."""
        request = ' '.join(
            f'pose: {{name: "{name}", position: {{x: {x}, y: {y}, z: {z}}}, '
            f'orientation: {{w: 1}}}}' for name, (x, y, z) in places.items())
        try:
            reply = subprocess.run(
                ['gz', 'service', '-s', f'/world/{WORLD}/set_pose_vector',
                 '--reqtype', 'gz.msgs.Pose_V', '--reptype', 'gz.msgs.Boolean',
                 '--timeout', '3000', '--req', request],
                capture_output=True, text=True, timeout=10.0)
        except subprocess.TimeoutExpired:
            return False
        return 'data: true' in reply.stdout


def tilt(quaternion):
    """The angle between a body's z axis and the world's z axis, rad."""
    x, y, _, _ = quaternion
    return math.acos(max(-1.0, min(1.0, 1.0 - 2.0 * (x * x + y * y))))


class GraspTest:

    def __init__(self, args):
        self.args = args
        self.verbose = args.verbose
        self.node = rclpy.create_node('conduit_demo_grasp_test')
        self.clock = RobotClock()
        self.joints = {}
        self.node.create_subscription(
            JointState, '/joint_states', self._on_joints, qos_profile_sensor_data)
        self.tf = Buffer()
        self.tf_listener = TransformListener(self.tf, self.node, spin_thread=False)
        self.twist = self.node.create_publisher(TwistStamped, TWIST_TOPIC, 10)
        self.move = ActionClient(self.node, MoveGroup, '/move_action')
        self.gripper = ActionClient(self.node, GripperCommand, GRIPPER_ACTION)
        self.ik = self.node.create_client(GetPositionIK, '/compute_ik')
        self.servo_type = self.node.create_client(ServoCommandType, SERVO_COMMAND_TYPE)
        self.cubes = CubePoses(name for name, _ in CUBES.values())
        self.executor = SingleThreadedExecutor()
        self.executor.add_node(self.node)
        self.spinner = threading.Thread(target=self.executor.spin, daemon=True)
        self.spinner.start()
        self.pregrasp = {}

    def close(self):
        self.cubes.close()
        self.executor.shutdown()
        self.spinner.join(timeout=2.0)
        self.node.destroy_node()

    def _on_joints(self, message):
        self.clock.observe(message.header.stamp)
        for name, position in zip(message.name, message.position):
            self.joints[name] = position

    # --- startup --------------------------------------------------------------------

    def wait_ready(self, timeout_s):
        deadline = time.monotonic() + timeout_s
        checks = [
            ('/move_action', lambda: self.move.wait_for_server(timeout_sec=1.0)),
            (GRIPPER_ACTION, lambda: self.gripper.wait_for_server(timeout_sec=1.0)),
            ('/compute_ik', lambda: self.ik.wait_for_service(timeout_sec=1.0)),
            (SERVO_COMMAND_TYPE, lambda: self.servo_type.wait_for_service(timeout_sec=1.0)),
            ('/joint_states', lambda: self.clock.ready() and FINGER in self.joints),
            ('/tf', lambda: self.hand() is not None),
            ('cube poses from Gazebo',
             lambda: all(self.cubes.get(name) for name, _ in CUBES.values())),
        ]
        for what, ready in checks:
            while not ready():
                if time.monotonic() > deadline:
                    raise RuntimeError(f'{what} not available within {timeout_s:.0f} s')
                time.sleep(0.2)
        # The launch switches Servo to TWIST commands; do it again in case it has not yet.
        request = ServoCommandType.Request(command_type=TWIST_COMMAND_TYPE)
        future = self.servo_type.call_async(request)
        if not wait_future(future, 10.0) or not future.result().success:
            raise RuntimeError('Servo did not switch to TWIST commands')

    def solve_pregrasp(self, cube):
        """The joint configuration with the pads' centre LIFT above the grasp point of `cube`."""
        _, (x, y, _) = CUBES[cube]
        request = GetPositionIK.Request()
        ik = request.ik_request
        ik.group_name = ARM_GROUP
        ik.avoid_collisions = True
        ik.ik_link_name = HAND_FRAME
        ik.robot_state.joint_state.name = list(READY)
        ik.robot_state.joint_state.position = list(READY.values())
        ik.pose_stamped = PoseStamped()
        ik.pose_stamped.header.frame_id = BASE_FRAME
        ik.pose_stamped.pose.position.x = x
        ik.pose_stamped.pose.position.y = y
        ik.pose_stamped.pose.position.z = GRASP_HEIGHT + LIFT + TCP_OFFSET
        o = ik.pose_stamped.pose.orientation
        o.x, o.y, o.z, o.w = HAND_DOWN
        ik.timeout.sec = 2
        future = self.ik.call_async(request)
        if not wait_future(future, 10.0):
            raise RuntimeError(f'/compute_ik did not answer for the {cube} cube')
        response = future.result()
        if response.error_code.val != 1:
            raise RuntimeError(f'no IK solution above the {cube} cube '
                               f'(error code {response.error_code.val})')
        state = response.solution.joint_state
        return {n: p for n, p in zip(state.name, state.position) if n in READY}

    # --- arm ------------------------------------------------------------------------

    def hand(self):
        """(position, z axis) of panda_hand in panda_link0, or None before /tf has it."""
        try:
            t = self.tf.lookup_transform(BASE_FRAME, HAND_FRAME, Time())
        except Exception:  # noqa: BLE001 - any TF error means "not yet"
            return None
        p, q = t.transform.translation, t.transform.rotation
        x, y, z, w = q.x, q.y, q.z, q.w
        z_axis = (2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y))
        return (p.x, p.y, p.z), z_axis

    def tcp(self):
        hand = self.hand()
        if hand is None:
            raise Failure('no panda_hand transform')
        (px, py, pz), (zx, zy, zz) = hand
        return (px + TCP_OFFSET * zx, py + TCP_OFFSET * zy, pz + TCP_OFFSET * zz)

    def move_to(self, joints, what):
        goal = MoveGroup.Goal()
        request = goal.request
        request.group_name = ARM_GROUP
        request.num_planning_attempts = 5
        request.allowed_planning_time = 5.0
        request.max_velocity_scaling_factor = 0.5
        request.max_acceleration_scaling_factor = 0.5
        constraints = Constraints(name=what)
        for joint, value in joints.items():
            constraints.joint_constraints.append(JointConstraint(
                joint_name=joint, position=value,
                tolerance_above=0.005, tolerance_below=0.005, weight=1.0))
        request.goal_constraints.append(constraints)
        goal.planning_options.plan_only = False
        future = self.move.send_goal_async(goal)
        if not wait_future(future, 10.0) or not future.result().accepted:
            raise Failure(f'MoveGroup goal {what} not accepted')
        result = future.result().get_result_async()
        if not wait_future(result, 30.0):
            future.result().cancel_goal_async()
            raise Failure(f'MoveGroup to {what} not finished within 30 s')
        code = result.result().result.error_code.val
        if code != 1:
            raise Failure(f'MoveGroup to {what} ended with error code {code}')

    def publish_twist(self, linear):
        message = TwistStamped()
        message.header.stamp = self.clock.now()
        message.header.frame_id = BASE_FRAME
        message.twist.linear.x, message.twist.linear.y, message.twist.linear.z = linear
        self.twist.publish(message)

    def servo_to(self, target, what, timeout_s=15.0, tolerance=0.002):
        """Servos the pads' centre to `target` in panda_link0: a P loop on /tf.

        The arm trails Servo's commands by about 0.1 s (gz_ros2_control's position loop), so
        the gain is low enough that the hand slows down before the target instead of
        overshooting it."""
        speed, gain = self.args.servo_speed, 2.0
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            error = [t - p for t, p in zip(target, self.tcp())]
            norm = math.sqrt(sum(e * e for e in error))
            if norm < tolerance:
                break
            scale = min(gain, speed / norm)
            self.publish_twist([e * scale for e in error])
            time.sleep(0.02)
        for _ in range(10):
            self.publish_twist((0.0, 0.0, 0.0))
            time.sleep(0.02)
        time.sleep(0.4)  # the trajectory controller settles
        error = math.dist(target, self.tcp())
        if error > 0.005:
            raise Failure(f'Servo {what}: {error * 1000:.1f} mm from the target')

    # --- gripper --------------------------------------------------------------------

    def grip(self, position, timeout_s=10.0):
        goal = GripperCommand.Goal()
        goal.command.position = position
        goal.command.max_effort = MAX_EFFORT
        future = self.gripper.send_goal_async(goal)
        if not wait_future(future, 10.0) or not future.result().accepted:
            raise Failure(f'GripperCommand {position} not accepted')
        result = future.result().get_result_async()
        if not wait_future(result, timeout_s):
            raise Failure(f'GripperCommand {position} not finished within {timeout_s:.0f} s')
        if result.result().status != GoalStatus.STATUS_SUCCEEDED:
            raise Failure(f'GripperCommand {position} ended with status {result.result().status}')
        time.sleep(0.3)  # the fingers settle on the cube
        return self.joints.get(FINGER, math.nan), self.joints.get(MIMIC_FINGER, math.nan)

    # --- cubes ----------------------------------------------------------------------

    def reset_cubes(self):
        places = dict(CUBES.values())
        if not (self.cubes.set(places) or self.cubes.set(places)):
            raise Failure('Gazebo set_pose_vector failed twice')
        time.sleep(1.0)  # they settle on the table
        for name, position in CUBES.values():
            pose = self.cubes.get(name)
            if pose is None:
                raise Failure(f'no pose of {name} from Gazebo')
            offset = math.dist(pose[0], position)
            if offset > 0.002:
                raise Failure(f'{name} {offset * 1000:.1f} mm from its place after set_pose')

    def cube_pose(self, name):
        """(position, orientation) of the cube from Gazebo."""
        pose = self.cubes.get(name)
        if pose is None:
            raise Failure(f'no pose of {name} from Gazebo')
        return pose

    def trace(self, step, name):
        """With --verbose: the pads' centre, the fingers and the cube after `step`."""
        if not self.verbose:
            return
        hand = self.hand()
        if hand is None:
            print(f'  {step}: no panda_hand transform', flush=True)
            return
        tcp = self.tcp()
        pose = self.cubes.get(name)
        cube = 'none' if pose is None else (
            '({:.4f}, {:.4f}, {:.4f}) tilt {:.1f} deg'.format(
                *pose[0], math.degrees(tilt(pose[1]))))
        print(f'  {step}: pads ({tcp[0]:.4f}, {tcp[1]:.4f}, {tcp[2]:.4f}) '
              f'f1 {self.joints.get(FINGER, math.nan):.4f} '
              f'f2 {self.joints.get(MIMIC_FINGER, math.nan):.4f} cube {cube}', flush=True)

    # --- one run --------------------------------------------------------------------

    def check_fingers(self, finger, mimic, when):
        """Both fingers on the cube, and finger1 reporting half the real opening."""
        if finger < MIN_FINGER:
            raise Failure(f'{FINGER} {finger:.4f} < {MIN_FINGER} {when} (not on the cube)')
        if abs(finger + mimic - CUBE_SIZE) > FINGER_SUM_TOLERANCE:
            raise Failure(
                f'fingers {finger:.4f} + {mimic:.4f} {when}, not on a {CUBE_SIZE} m cube')
        if abs(finger - mimic) > FINGER_ASYMMETRY:
            raise Failure(
                f'fingers {finger:.4f} and {mimic:.4f} {when}: the cube slid sideways')

    def run(self, cube):
        name, (x, y, z0) = CUBES[cube]
        above = (x, y, GRASP_HEIGHT + LIFT)
        report = {}
        try:
            self.grip(self.args.open)
            self.move_to(self.pregrasp[cube], f'pre-grasp {cube}')
            self.reset_cubes()
            start = self.cube_pose(name)[0]
            self.trace('pre-grasp', name)
            self.servo_to((x, y, GRASP_HEIGHT), 'down to the cube')
            grasp = self.tcp()
            self.trace('down', name)
            finger, mimic = self.grip(CLOSED)
            self.trace('closed', name)
            report['closed'] = f'closed f1 {finger:.4f} f2 {mimic:.4f}'
            self.check_fingers(finger, mimic, 'after closing')

            # Servo up LIFT from where the hand gripped, then hold.
            above = (x, y, grasp[2] + LIFT)
            self.servo_to(above, 'up')
            self.trace('up', name)
            lowest, finger_min, asymmetry = math.inf, math.inf, 0.0
            hold_end = time.monotonic() + self.args.hold
            while time.monotonic() < hold_end:
                lowest = min(lowest, self.cube_pose(name)[0][2] - start[2])
                finger, mimic = self.joints.get(FINGER, 0.0), self.joints.get(MIMIC_FINGER, 0.0)
                finger_min = min(finger_min, finger)
                asymmetry = max(asymmetry, abs(finger - mimic))
                time.sleep(0.05)
            self.trace('held', name)
            report['held'] = (f'held {self.args.hold:.0f} s: cube min {lowest:+.4f} m, '
                              f'f1 min {finger_min:.4f}, |f1 - f2| max {asymmetry:.4f}')
            if lowest < MIN_LIFT:
                raise Failure(f'cube {lowest:+.4f} m above its start during the hold, '
                              f'below {MIN_LIFT} (slipped)')
            self.check_fingers(finger, mimic, 'after the hold')
            if finger_min < MIN_FINGER or asymmetry > FINGER_ASYMMETRY:
                raise Failure(f'fingers moved during the hold: f1 min {finger_min:.4f}, '
                              f'|f1 - f2| max {asymmetry:.4f}')

            # Servo down LIFT (2 mm short, not to press the cube into the table), open, up.
            self.servo_to((x, y, grasp[2] + 0.002), 'down to put the cube down')
            self.trace('down again', name)
            self.grip(self.args.open)
            self.trace('opened', name)
            self.servo_to(above, 'up from the cube')
            self.trace('retreated', name)
            pose = self.cube_pose(name)
            report['put down'] = (f'put down at z {pose[0][2]:.4f} '
                                  f'tilt {math.degrees(tilt(pose[1])):.1f} deg')
            if abs(pose[0][2] - z0) > PUT_DOWN_TOLERANCE:
                raise Failure(f'cube not on the table after the release: z {pose[0][2]:.4f}')
            return True, '', report
        except Failure as failure:
            self.trace(f'failed ({failure})', name)
            self.recover(above)
            return False, str(failure), report

    def recover(self, above):
        """Releases the cube and clears the table, so the next run starts clean."""
        try:
            self.grip(self.args.open)
            position = self.tcp()
            if position[2] < above[2] - 0.01:
                self.servo_to((position[0], position[1], above[2]), 'up (recovery)',
                              tolerance=0.005)
        except Failure as failure:
            print(f'  recovery: {failure}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--runs', type=int, default=10)
    parser.add_argument('--min-pass', type=int, default=None,
                        help='runs that must pass (default: 90 %% of --runs, rounded up)')
    parser.add_argument('--cube', choices=['all', *CUBES], default='all',
                        help='the cube to pick up; all takes red, green and blue in turn')
    parser.add_argument('--hold', type=float, default=10.0, help='seconds to hold the cube up')
    parser.add_argument('--open', type=float, default=OPEN,
                        help='the open gripper position, m (default: the SRDF state open)')
    parser.add_argument('--servo-speed', type=float, default=0.08, help='m/s')
    parser.add_argument('--startup-timeout', type=float, default=180.0)
    parser.add_argument('--verbose', action='store_true', help='print every step')
    args = parser.parse_args()
    min_pass = args.min_pass if args.min_pass is not None else math.ceil(0.9 * args.runs)
    cubes = list(CUBES) if args.cube == 'all' else [args.cube]

    rclpy.init()
    test = GraspTest(args)
    passed = 0
    try:
        test.wait_ready(args.startup_timeout)
        for cube in cubes:
            test.pregrasp[cube] = test.solve_pregrasp(cube)
        for index in range(args.runs):
            cube = cubes[index % len(cubes)]
            start = time.monotonic()
            ok, reason, report = test.run(cube)
            passed += ok
            details = ', '.join(report.values())
            verdict = 'PASS' if ok else f'FAIL ({reason})'
            print(f'run {index + 1}/{args.runs} {cube}: {verdict}; {details}; '
                  f'{time.monotonic() - start:.1f} s', flush=True)
    except RuntimeError as error:
        print(f'grasp test: {error}', flush=True)
        return 2
    finally:
        test.close()
        rclpy.try_shutdown()
    print(f'grasp: {passed}/{args.runs} passed (need {min_pass})', flush=True)
    return 0 if passed >= min_pass else 1


if __name__ == '__main__':
    sys.exit(main())
