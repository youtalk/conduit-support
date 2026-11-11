#!/usr/bin/env python3
"""Checks that the demo arm's clock works with Conduit's HOLD, the way the app uses it.

Conduit's arm view reads the robot's clock from /joint_states header stamps and stamps
the twists it sends to MoveIt Servo on that clock; Servo ages each twist as its own now
minus the twist's header.stamp and drops it after incoming_command_timeout (0.5 s in
conduit_teleop's servo_overlay.yaml). This script copies the app's rules:

- ClockOffsetEstimator: a /joint_states message stamped s, received at uptime u, gives the
  sample s - u (the robot epoch, early by that message's latency); the estimate is the
  largest sample of the last 10 s, trusted after 10 samples; a sample more than 0.1 s below
  a stored one drops the stored ones above it (a step back); 3 stamps in a row more than
  86 400 s from the wall clock make the clock "not wall time", which refuses HOLD.
- ArmTeleopController polls the newest /joint_states message at 10 Hz and adds one sample
  per new message.
- ClutchController stamps each twist robot epoch + uptime, and a clock that stops being an
  epoch while HOLD is held stops HOLD.

It exits 0 when
1. over --seconds, every /joint_states stamp is within 86 400 s of the wall clock, the
   stamps advance at the wall clock's rate (within --rate-tolerance, 5 %), and the
   estimate stays usable for HOLD the whole time once trusted; and
2. TwistStamped messages on /servo_node/delta_twist_cmds, stamped as the app stamps them
   and sent at 60 Hz for --twist-seconds (up, then back down), move a Panda arm joint by
   more than 0.01 rad within 1 s of the first twist, and the arm stops within 0.6 s of the
   last twist: Servo sends the arm's controller its last command (on --command-topic) no
   later than 0.6 s after the last twist, and the arm comes to rest within the 2 s it is
   watched (every arm joint within 0.002 rad of where it ends up, for at least the last
   0.5 s). No zero twist is sent at the end, as when the phone's link drops: Servo's command
   timeout (0.5 s) stops the arm, and 0.6 s is the app's bound for that (0.5 s plus
   ClockOffsetEstimator.stepTolerance). The 0.6 s is Servo's: after its last command the
   controller still finishes that command's trajectory (it reaches max_expected_latency,
   0.1 s, ahead) and the joints settle, about 0.8 s in all at real time; that time is
   printed too.

It prints the numbers of each check and `HOLD CLOCK PASS` or `HOLD CLOCK FAIL: <checks>`.
It needs rclpy and moveit_msgs, so it runs in a container of the demo image beside the
arm, for example:

    docker exec arm bash -c 'source /opt/ros/$ROS_DISTRO/setup.bash && python3 \\
        /ros2_ws/install/conduit_demo/share/conduit_demo/scripts/hold_clock_check.py'

No ROS 2 daemon is used. Exit 2: the arm's topics or Servo did not come up in time.
"""

import argparse
import math
import sys
import threading
import time

import rclpy
from geometry_msgs.msg import TwistStamped
from moveit_msgs.msg import ServoStatus
from moveit_msgs.srv import ServoCommandType
from rclpy.executors import SingleThreadedExecutor
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import JointState
from trajectory_msgs.msg import JointTrajectory

ARM_JOINTS = [f'panda_joint{i}' for i in range(1, 8)]
BASE_FRAME = 'panda_link0'
TWIST_TOPIC = '/servo_node/delta_twist_cmds'
SERVO_COMMAND_TYPE = '/servo_node/switch_command_type'
SERVO_STATUS = '/servo_node/status'
TWIST_RATE = 60.0       # Hz, Device Pose's frame rate
POLL_PERIOD = 0.1       # s, ArmTeleopController's heartbeat poll
MOVE_THRESHOLD = 0.01   # rad
MOVE_WITHIN = 1.0       # s after the first twist
STOP_WITHIN = 0.6       # s from the last twist to Servo's last command
REST_TOLERANCE = 0.002  # rad from the final position
REST_WINDOW = 0.5       # s at the end of the observation the arm must be at rest
OBSERVE_AFTER = 2.0     # s of joint states recorded after the last twist
COMMAND_TOPIC = '/panda_arm_controller/joint_trajectory'

# The app's QoS for /joint_states (QoSResolver.manualDefault): best effort, volatile, keep 1.
JOINT_STATES_QOS = QoSProfile(
    depth=1, history=HistoryPolicy.KEEP_LAST, reliability=ReliabilityPolicy.BEST_EFFORT,
    durability=DurabilityPolicy.VOLATILE)


class HoldStopped(Exception):
    """The robot clock stopped being usable while the twists streamed: HOLD let go."""


class ClockOffsetEstimator:
    """Conduit's ClockOffsetEstimator (Sources/Robots/Control/Arm), line for line."""

    WINDOW = 10.0
    MINIMUM_SAMPLES = 10
    MAX_WALL_CLOCK_DIFFERENCE = 86_400.0
    STEP_TOLERANCE = 0.1
    BAD_SAMPLE_LIMIT = 3

    def __init__(self):
        self.samples = []  # (receipt uptime, epoch)
        self.trusted = False
        self.not_wall_time = False
        self.bad_samples = 0

    def add(self, stamp, receipt_uptime, receipt_wall):
        if not all(math.isfinite(v) for v in (stamp, receipt_uptime, receipt_wall)):
            return
        if abs(stamp - receipt_wall) > self.MAX_WALL_CLOCK_DIFFERENCE:
            # Unstamped once the clock is known: another publisher on the topic.
            if stamp == 0 and self.trusted:
                return
            self.bad_samples += 1
            if self.bad_samples >= self.BAD_SAMPLE_LIMIT:
                self.samples.clear()
                self.trusted = False
                self.not_wall_time = True
            return
        self.bad_samples = 0
        self.not_wall_time = False
        epoch = stamp - receipt_uptime
        # Drop samples older than the window, and those above this one by more than the
        # step tolerance (a step back).
        self.samples = [
            (receipt, sample) for receipt, sample in self.samples
            if receipt_uptime - receipt <= self.WINDOW
            if sample <= epoch + self.STEP_TOLERANCE]
        self.samples.append((receipt_uptime, epoch))
        if len(self.samples) >= self.MINIMUM_SAMPLES:
            self.trusted = True

    def clock(self):
        """('notWallTime' | 'waiting' | 'epoch', epoch or None), as RobotClock."""
        if self.not_wall_time:
            return 'notWallTime', None
        if not self.trusted or not self.samples:
            return 'waiting', None
        return 'epoch', max(sample for _, sample in self.samples)


class HoldClockCheck:

    def __init__(self, command_topic, verbose=False):
        self.verbose = verbose
        # The node's own clock is never used: the app has no ROS clock, only its uptime
        # (time.monotonic here) and its wall clock (time.time).
        self.node = rclpy.create_node('conduit_demo_hold_clock_check')
        self.lock = threading.Lock()
        self.estimator = ClockOffsetEstimator()
        self.clock = ('waiting', None)
        self.epoch = None             # ClutchController.robotEpoch: the last epoch, kept
        self.latest = None            # (stamp, receipt uptime, receipt wall) of the newest
        self.polled_receipt = None
        self.samples = []             # every polled sample: (stamp, uptime, wall)
        self.clock_changes = []       # (uptime, state) whenever the state changes
        self.history = []             # (receipt uptime, {arm joint: position})
        self.status = {}              # Servo status code -> message, as seen
        self.commands = []            # receipt uptimes of Servo's commands to the controller
        self.node.create_subscription(
            JointState, '/joint_states', self._on_joints, JOINT_STATES_QOS)
        self.node.create_subscription(ServoStatus, SERVO_STATUS, self._on_status, 10)
        self.node.create_subscription(JointTrajectory, command_topic, self._on_command, 100)
        self.command_topic = command_topic
        self.twist = self.node.create_publisher(TwistStamped, TWIST_TOPIC, 10)
        self.servo_type = self.node.create_client(ServoCommandType, SERVO_COMMAND_TYPE)
        self.node.create_timer(POLL_PERIOD, self._poll)
        self.executor = SingleThreadedExecutor()
        self.executor.add_node(self.node)
        self.spinner = threading.Thread(target=self.executor.spin, daemon=True)
        self.spinner.start()

    def close(self):
        self.executor.shutdown()
        self.spinner.join(timeout=2.0)
        self.node.destroy_node()

    # --- the app's side ---------------------------------------------------------------

    def _on_joints(self, message):
        uptime, wall = time.monotonic(), time.time()
        stamp = message.header.stamp.sec + message.header.stamp.nanosec * 1e-9
        positions = {
            name: position for name, position in zip(message.name, message.position)
            if name in ARM_JOINTS}
        with self.lock:
            self.latest = (stamp, uptime, wall)
            if len(positions) == len(ARM_JOINTS):
                self.history.append((uptime, positions))

    def _on_command(self, _message):
        uptime = time.monotonic()
        with self.lock:
            self.commands.append(uptime)

    def _on_status(self, message):
        with self.lock:
            self.status.setdefault(message.code, message.message)

    def _poll(self):
        """ArmTeleopController.poll: one estimator sample per new /joint_states message."""
        with self.lock:
            latest = self.latest
            if latest is None or latest[1] == self.polled_receipt:
                return
            self.polled_receipt = latest[1]
            self.samples.append(latest)
            self.estimator.add(*latest)
            clock = self.estimator.clock()
            if clock[0] != self.clock[0]:
                self.clock_changes.append((latest[1], clock[0]))
            self.clock = clock
            if clock[0] == 'epoch':
                self.epoch = clock[1]

    def robot_stamp(self, uptime):
        """ClutchController.robotStamp(forUptime:): epoch + uptime; None before an epoch."""
        with self.lock:
            return None if self.epoch is None else self.epoch + uptime

    def usable(self):
        with self.lock:
            return self.clock[0] == 'epoch'

    # --- startup ----------------------------------------------------------------------

    def wait_ready(self, timeout_s):
        deadline = time.monotonic() + timeout_s
        while not self.servo_type.wait_for_service(timeout_sec=1.0):
            if time.monotonic() > deadline:
                raise RuntimeError(f'{SERVO_COMMAND_TYPE} not available within {timeout_s:.0f} s')
        while True:
            with self.lock:
                latest = self.latest
            if latest is not None:
                break
            if time.monotonic() > deadline:
                raise RuntimeError(f'no /joint_states message within {timeout_s:.0f} s')
            time.sleep(0.1)
        # The app switches Servo to TWIST when the link comes up; so does the demo's launch.
        future = self.servo_type.call_async(
            ServoCommandType.Request(command_type=ServoCommandType.Request.TWIST))
        deadline = time.monotonic() + 10.0
        while not future.done() and time.monotonic() < deadline:
            time.sleep(0.01)
        if not future.done() or not future.result().success:
            raise RuntimeError('Servo did not switch to TWIST commands')

    # --- check 1: the clock -----------------------------------------------------------

    def check_clock(self, seconds, rate_tolerance):
        # The app trusts the estimate after 10 samples, 1 s at its 10 Hz poll; a few more
        # seconds before the window starts.
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline and not self.usable():
            time.sleep(0.1)
        with self.lock:
            first = len(self.samples)
            changes_before = len(self.clock_changes)
        time.sleep(seconds)
        with self.lock:
            samples = self.samples[first:]
            changes = self.clock_changes[changes_before:]
            clock, epoch = self.clock, self.epoch
            kept = len(self.estimator.samples)
        failures = []
        if len(samples) < 2:
            return [f'only {len(samples)} /joint_states samples in {seconds:.0f} s']
        off_wall = max(abs(stamp - wall) for stamp, _, wall in samples)
        print(f'clock: {len(samples)} samples polled in {seconds:.0f} s; largest '
              f'|stamp - wall clock| {off_wall:.3f} s (limit 86400 s)')
        if off_wall > ClockOffsetEstimator.MAX_WALL_CLOCK_DIFFERENCE:
            failures.append(f'stamps {off_wall:.0f} s from the wall clock: HOLD refused '
                            '("more than a day apart (simulation time?)")')
        # The robot clock's rate against the wall clock: a least-squares slope of the
        # stamps over their receipts.
        mean_t = sum(wall for _, _, wall in samples) / len(samples)
        mean_s = sum(stamp for stamp, _, _ in samples) / len(samples)
        var = sum((wall - mean_t) ** 2 for _, _, wall in samples)
        cov = sum((wall - mean_t) * (stamp - mean_s) for stamp, _, wall in samples)
        rate = cov / var if var > 0 else math.nan
        print(f'clock: /joint_states stamps advance at {rate:.4f} x the wall clock '
              f'(allowed 1 +/- {rate_tolerance})')
        if not abs(rate - 1.0) <= rate_tolerance:
            failures.append(f'stamps advance at {rate:.3f} x wall time')
        if clock[0] == 'epoch':
            # The estimate is the lowest-latency sample of the last 10 s, so it runs ahead of
            # the newest stamp by that message's extra latency.
            stamp, uptime, _ = samples[-1]
            print(f'clock: estimate - newest stamp at its receipt: '
                  f'{(epoch + uptime - stamp) * 1000:+.1f} ms')
        print(f'clock: state {clock[0]} at the end ({kept} samples kept, '
              f'{ClockOffsetEstimator.MINIMUM_SAMPLES} needed once); changes in the window: '
              f'{[state for _, state in changes] or "none"}')
        if clock[0] != 'epoch':
            failures.append(f'robot clock {clock[0]}: HOLD refused')
        elif changes:
            failures.append(f'robot clock changed {[s for _, s in changes]}: HOLD stopped')
        return failures

    # --- check 2: Servo ---------------------------------------------------------------

    def positions_at(self, index):
        with self.lock:
            return dict(self.history[index][1]) if 0 <= index < len(self.history) else None

    def stream(self, linear_z, seconds):
        """Twists at TWIST_RATE for `seconds`; returns (first, last) send uptimes and the
        stamps' offsets from the newest /joint_states stamp at each send."""
        period = 1.0 / TWIST_RATE
        first = last = None
        leads = []
        end = time.monotonic() + seconds
        next_send = time.monotonic()
        while True:
            now = time.monotonic()
            if now >= end:
                break
            stamp = self.robot_stamp(now)
            if stamp is None or not self.usable():
                raise HoldStopped()
            message = TwistStamped()
            message.header.frame_id = BASE_FRAME
            message.header.stamp.sec = int(stamp // 1)
            message.header.stamp.nanosec = int((stamp % 1) * 1e9)
            message.twist.linear.z = linear_z
            self.twist.publish(message)
            with self.lock:
                newest = self.latest[0]
            leads.append(stamp - newest)
            if first is None:
                first = now
            last = now
            next_send += period
            time.sleep(max(0.0, next_send - time.monotonic()))
        return first, last, leads

    def check_servo(self, what, linear_z, seconds):
        with self.lock:
            start_index = len(self.history) - 1
        start = self.positions_at(start_index)
        if start is None:
            return [f'{what}: no /joint_states message with the arm joints']
        try:
            first, last, leads = self.stream(linear_z, seconds)
        except HoldStopped:
            return [f'{what}: the robot clock changed while HOLD was held (HOLD stopped)']
        time.sleep(OBSERVE_AFTER)
        with self.lock:
            history = [h for h in self.history[start_index:] if h[0] >= first]
        failures = []
        if not history:
            return [f'{what}: no /joint_states during the twists']

        def moved(positions, reference):
            return max(abs(positions[j] - reference[j]) for j in ARM_JOINTS)

        moved_at = next((t for t, p in history if moved(p, start) > MOVE_THRESHOLD), None)
        with self.lock:
            commands = [t for t in self.commands if t >= first]
        # The arm is at rest from the first sample after which every joint stays within
        # REST_TOLERANCE of its final position.
        final = history[-1][1]
        rest_at = first
        for t, p in history:
            if moved(p, final) >= REST_TOLERANCE:
                rest_at = t
        observed_until = history[-1][0]
        travel = moved(final, start)
        if self.verbose:
            # The arm's fastest joint speed in 50 ms bins around the last twist.
            bins = {}
            for (t0, p0), (t1, p1) in zip(history, history[1:]):
                if t1 > t0:
                    key = math.floor((t1 - last) / 0.05)
                    bins[key] = max(bins.get(key, 0.0), moved(p1, p0) / (t1 - t0))
            profile = ', '.join(
                f'{key * 0.05:+.2f} {speed:.3f}' for key, speed in sorted(bins.items())
                if -0.2 <= key * 0.05 <= 1.2)
            print(f'{what}: fastest joint speed (rad/s) by 50 ms after the last twist: {profile}')
        print(f'{what}: {len(leads)} twists in {last - first:.2f} s, stamps '
              f'{min(leads) * 1000:+.0f} to {max(leads) * 1000:+.0f} ms from the newest '
              f'/joint_states stamp; largest joint travel {travel:.3f} rad')
        if moved_at is None:
            failures.append(f'{what}: no arm joint moved {MOVE_THRESHOLD} rad')
        else:
            print(f'{what}: a joint moved {MOVE_THRESHOLD} rad {moved_at - first:.3f} s after '
                  f'the first twist (limit {MOVE_WITHIN} s)')
            if moved_at - first > MOVE_WITHIN:
                failures.append(f'{what}: moved {moved_at - first:.2f} s after the first twist')
        if not commands:
            failures.append(f'{what}: no command from Servo on {self.command_topic}')
        else:
            stopped = commands[-1] - last
            print(f'{what}: Servo sent its last command {stopped:.3f} s after the last twist '
                  f'(limit {STOP_WITHIN} s)')
            if stopped > STOP_WITHIN:
                failures.append(f'{what}: Servo stopped the arm {stopped:.2f} s after the last '
                                'twist')
        print(f'{what}: the arm at rest {rest_at - last:.3f} s after the last twist')
        if observed_until - rest_at < REST_WINDOW:
            failures.append(f'{what}: the arm still moving {observed_until - last:.1f} s after '
                            'the last twist')
        return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--seconds', type=float, default=30.0,
                        help='how long to watch the /joint_states clock (check 1)')
    parser.add_argument('--rate-tolerance', type=float, default=0.05)
    parser.add_argument('--twist-seconds', type=float, default=1.5,
                        help='how long each twist stream lasts (check 2)')
    parser.add_argument('--speed', type=float, default=0.05, help='m/s, up then down')
    parser.add_argument('--command-topic', default=COMMAND_TOPIC,
                        help="Servo's commands to the arm's controller")
    parser.add_argument('--startup-timeout', type=float, default=180.0)
    parser.add_argument('--verbose', action='store_true',
                        help="print the arm's speed around the last twist")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    rclpy.init()
    check = HoldClockCheck(args.command_topic, args.verbose)
    failures = []
    try:
        check.wait_ready(args.startup_timeout)
        failures += check.check_clock(args.seconds, args.rate_tolerance)
        if check.usable():
            failures += check.check_servo('up', args.speed, args.twist_seconds)
            if check.usable():
                failures += check.check_servo('down', -args.speed, args.twist_seconds)
        else:
            failures.append('Servo not tried: HOLD is refused on this clock')
        with check.lock:
            status = dict(check.status)
        print(f'servo status codes seen: {status or "none"}')
    except RuntimeError as error:
        print(f'HOLD CLOCK FAIL: {error}', flush=True)
        return 2
    finally:
        check.close()
        rclpy.try_shutdown()
    if failures:
        print('HOLD CLOCK FAIL: ' + '; '.join(failures), flush=True)
        return 1
    print('HOLD CLOCK PASS', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
