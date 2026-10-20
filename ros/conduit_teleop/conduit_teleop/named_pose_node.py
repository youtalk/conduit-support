"""named_pose_node: move a MoveIt arm to an SRDF group state when Conduit asks for it.

Conduit's pose buttons publish the name of an SRDF ``group_state`` (std_msgs/String,
``/conduit/teleop/named_pose`` by default). This node plans and executes a move to
that state through move_group's MoveGroup action, pausing MoveIt Servo for the
move so the two never command the arm at once. It reports where the arm is on a
latched std_msgs/String (``/conduit/teleop/named_pose_state``): the name of the
group state the joints are at, or '' while moving or anywhere else.

A tap during a move cancels that move and starts the new one once the cancel has
finished (the newest tap wins); a repeat of the running move's name is ignored.
Servo stays paused across the hand-over and is resumed when the last move ends,
whether it succeeded, failed, was cancelled or lost move_group.

Conduit's clutch (std_msgs/Bool, ``/conduit/teleop/clutch``) is true while HOLD is
held and is repeated at 10 Hz while the arm view is open. A clutch true stops the
move (and drops a tap that waits for a cancel), because the arm is to follow the
phone. When clutch messages were arriving as the move started, the move also stops
once they stay away for clutch_timeout: the app lost the link, went to the
background or closed. A tap while HOLD is held is ignored.

Everything runs on one single-threaded executor, so the callbacks never race, and
no callback blocks: a 10 Hz tick drives each move through its phases, waits for
Servo and move_group without sleeping, and gives up a move whose move_group has
gone or stopped answering.
"""

import signal
import time
from typing import Optional

from action_msgs.msg import GoalStatus
from moveit_msgs.action import MoveGroup
from moveit_msgs.msg import Constraints, JointConstraint, MoveItErrorCodes
import rclpy
from rclpy.action import ActionClient
from rclpy.clock import Clock, ClockType
from rclpy.executors import ExternalShutdownException, SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy, qos_profile_sensor_data
from rclpy.signals import SignalHandlerOptions
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool, String
from std_srvs.srv import SetBool

from conduit_teleop.named_pose_logic import (
    CANCEL_THEN_MOVE, CANCELLING, IGNORE, MOVE, REJECT, RUNNING, SENDING, ClutchWatch, current_state,
    decide_command, move_watchdog, parse_continuous_joints, parse_group_states, parse_parameters)

LATCHED = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.TRANSIENT_LOCAL)
# Conduit publishes the clutch Reliable and Volatile (KEEP_LAST 1), as `ros2 topic pub` does by default.
CLUTCH_QOS = QoSProfile(depth=10, reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.VOLATILE)

TICK_PERIOD = 0.1  # s

# Phases of a move before its goal goes to move_group (the later ones are in named_pose_logic).
WAIT_SERVO = 'wait_servo'  # waiting for the Servo pause service to appear
PAUSING = 'pausing'  # the pause request is out; waiting for Servo's answer
WAIT_SERVER = 'wait_server'  # waiting for the MoveGroup action server to appear
BEFORE_GOAL = (WAIT_SERVO, PAUSING, WAIT_SERVER)

GOAL_STATUS_NAMES = {
    GoalStatus.STATUS_SUCCEEDED: 'succeeded',
    GoalStatus.STATUS_ABORTED: 'aborted',
    GoalStatus.STATUS_CANCELED: 'cancelled',
}


class Move:
    """One requested move, from the command to its result."""

    def __init__(self, name: str, target: dict):
        self.name = name
        self.target = target  # {joint: position}, taken from the SRDF at the tap
        self.phase = ''
        self.since = 0.0  # time.monotonic() when the phase began
        self.sent_at = 0.0  # time.monotonic() when the goal went to move_group
        self.goal_future = None  # set once the goal is sent
        self.goal_handle = None  # set once move_group accepts the goal
        self.cancel_future = None  # set once the goal's cancel is requested
        self.cancel_requested = False
        self.watch_heartbeat = False  # clutch messages were arriving when the move started
        self.stop_reason = ''  # why the clutch stopped the move

    def enter(self, phase: str) -> None:
        self.phase = phase
        self.since = time.monotonic()


class NamedPoseNode(Node):

    def __init__(self):
        super().__init__('conduit_named_pose')
        self._group = self.declare_parameter('planning_group', 'arm').value
        command_topic = self.declare_parameter('command_topic', '/conduit/teleop/named_pose').value
        state_topic = self.declare_parameter('state_topic', '/conduit/teleop/named_pose_state').value
        move_action = self.declare_parameter('move_action', 'move_action').value
        servo_pause_service = self.declare_parameter('servo_pause_service', '/servo_node/pause_servo').value
        clutch_topic = self.declare_parameter('clutch_topic', '/conduit/teleop/clutch').value
        self._velocity_scaling = self.declare_parameter('velocity_scaling', 0.2).value
        self._acceleration_scaling = self.declare_parameter('acceleration_scaling', 0.2).value
        self._tolerance = self.declare_parameter('tolerance', 0.01).value
        self._planning_time = self.declare_parameter('planning_time', 5.0).value
        # How long to wait for the Servo pause service and the MoveGroup action server to appear,
        # and for Servo to answer a pause request.
        self._service_timeout = self.declare_parameter('service_timeout', 1.0).value
        # How long a move may execute after planning before the node gives it up.
        self._max_move_duration = self.declare_parameter('max_move_duration', 60.0).value
        # How long the clutch heartbeat may stay away before a move started under it stops.
        clutch_timeout = self.declare_parameter('clutch_timeout', 0.5).value
        parse_parameters(self._velocity_scaling, self._acceleration_scaling, self._tolerance, self._planning_time,
                         self._service_timeout, self._max_move_duration, clutch_timeout)

        self._states = {}  # group states of the planning group, SRDF order
        self._continuous = frozenset()  # continuous joints of the URDF, compared modulo a turn
        self._joint_positions = {}
        self._move: Optional[Move] = None
        self._pending: Optional[str] = None  # the tap that waits for the running move's cancel
        self._servo_paused = False  # True while this node holds Servo paused
        self._published_state: Optional[str] = None
        self._clutch = ClutchWatch(clutch_timeout)

        self._state_pub = self.create_publisher(String, state_topic, LATCHED)
        self._move_action = move_action
        self._move_client = ActionClient(self, MoveGroup, move_action)
        self._servo_client = self.create_client(SetBool, servo_pause_service)
        self.create_subscription(String, 'robot_description_semantic', self._on_srdf, LATCHED)
        self.create_subscription(String, 'robot_description', self._on_urdf, LATCHED)
        # Best Effort matches both Reliable and Best Effort joint state publishers.
        self.create_subscription(JointState, 'joint_states', self._on_joint_states, qos_profile_sensor_data)
        self.create_subscription(String, command_topic, self._on_command, 10)
        self.create_subscription(Bool, clutch_topic, self._on_clutch, CLUTCH_QOS)
        # A steady clock keeps the tick going when /clock stops.
        self.create_timer(TICK_PERIOD, self._tick, clock=Clock(clock_type=ClockType.STEADY_TIME))
        self._publish_state('')
        self.get_logger().info(
            f"Waiting for '{self._group}' group states on {command_topic}; state on {state_topic}; "
            f'clutch on {clutch_topic}')

    # --- inputs ---

    def _on_srdf(self, msg: String) -> None:
        states, error = parse_group_states(msg.data)
        if error:
            self.get_logger().warning(f'robot_description_semantic: {error}')
        self._states = states.get(self._group, {})
        if self._states:
            self.get_logger().info(f"'{self._group}' group states: {', '.join(self._states)}")
        else:
            groups = ', '.join(states) or 'none'
            self.get_logger().warning(
                f"The SRDF has no group states for planning group '{self._group}' (groups with states: {groups})")
        self._update_state()

    def _on_urdf(self, msg: String) -> None:
        self._continuous, error = parse_continuous_joints(msg.data)
        if error:
            self.get_logger().warning(f'robot_description: {error}; comparing every joint without wrapping')
        self._update_state()

    def _on_joint_states(self, msg: JointState) -> None:
        self._joint_positions.update(zip(msg.name, msg.position))
        self._update_state()

    def _on_command(self, msg: String) -> None:
        name = msg.data
        move = self._move
        decision = decide_command(name, self._states, move.name if move else None,
                                  move is not None and move.cancel_requested,
                                  self._clutch.engaged(time.monotonic()))
        if decision.action == REJECT:
            self.get_logger().warning(f'Ignoring named pose: {decision.reason}')
            return
        if decision.action == IGNORE:
            self.get_logger().info(f'Ignoring named pose: {decision.reason}')
            return
        if decision.action == CANCEL_THEN_MOVE:
            self.get_logger().info(f"'{name}' requested: cancelling the move to '{move.name}' first")
            self._pending = name
            self._cancel(move)
            return
        self._start_move(name)

    def _on_clutch(self, msg: Bool) -> None:
        self._clutch.receive(msg.data, time.monotonic())
        if self._move is not None:
            self._check_clutch(self._move)

    # --- state topic ---

    def _publish_state(self, state: str) -> None:
        if state == self._published_state:
            return
        self._state_pub.publish(String(data=state))
        self._published_state = state

    def _update_state(self) -> None:
        if self._move is None:
            self._publish_state(
                current_state(self._joint_positions, self._states, self._tolerance, self._continuous))

    # --- moves ---

    def _start_move(self, name: str) -> None:
        move = Move(name, dict(self._states[name]))
        move.watch_heartbeat = self._clutch.fresh(time.monotonic())
        self._move = move
        self._publish_state('')
        self.get_logger().info(f"Moving '{self._group}' to '{name}'"
                               + (' (stops if the clutch heartbeat is lost)' if move.watch_heartbeat else ''))
        # Servo stays paused when this move follows a cancelled one.
        self._enter(move, WAIT_SERVER if self._servo_paused else WAIT_SERVO)

    def _enter(self, move: Move, phase: str) -> None:
        move.enter(phase)
        self._advance(move)

    def _tick(self) -> None:
        if self._move is not None:
            self._check_clutch(self._move)
        if self._move is not None:
            self._advance(self._move)

    def _check_clutch(self, move: Move) -> None:
        """Stop move (and drop the tap that waits for its cancel) when the clutch says so."""
        if move.stop_reason:
            return  # already stopping for the clutch
        reason = self._clutch.stop_reason(move.watch_heartbeat, time.monotonic())
        if not reason:
            return
        move.stop_reason = reason
        dropped = f" and dropping the waiting '{self._pending}'" if self._pending is not None else ''
        self.get_logger().warning(f"{reason}: stopping the move to '{move.name}'{dropped}")
        self._pending = None
        self._cancel(move)

    def _advance(self, move: Move) -> None:
        """Take move as far as it can go now; the tick calls this again until the move ends."""
        if self._move is not move:
            return
        now = time.monotonic()
        elapsed = now - move.since
        if move.phase in BEFORE_GOAL and move.cancel_requested:
            self._end_move(move, 'cancelled before it was sent')
        elif move.phase == WAIT_SERVO:
            if self._servo_client.service_is_ready():
                self._servo_paused = True
                move.enter(PAUSING)
                future = self._servo_client.call_async(SetBool.Request(data=True))
                future.add_done_callback(lambda f: self._on_servo_paused(f, move))
            elif elapsed >= self._service_timeout:
                self.get_logger().warning(
                    f'Servo pause service {self._servo_client.srv_name} is not available; '
                    'moving without pausing Servo')
                self._enter(move, WAIT_SERVER)
        elif move.phase == PAUSING:
            # Do not let a Servo that never answers hold the move back.
            if elapsed >= self._service_timeout:
                self.get_logger().warning('Servo did not answer the pause request in time; moving anyway')
                self._enter(move, WAIT_SERVER)
        elif move.phase == WAIT_SERVER:
            if self._move_client.server_is_ready():
                self._send_goal(move)
            elif elapsed >= self._service_timeout:
                self.get_logger().error(
                    f'MoveGroup action {self._move_action} is not available; is move_group running?')
                self._end_move(move, 'not sent')
        else:
            since = move.sent_at if move.phase in (SENDING, RUNNING) else move.since
            reason = move_watchdog(move.phase, now - since, self._move_client.server_is_ready(),
                                   self._planning_time + self._max_move_duration)
            if reason:
                self._cancel_goal(move)  # in case move_group is still there but stuck
                self._end_move(move, reason)

    def _on_servo_paused(self, future, move: Move) -> None:
        self._log_servo_response(future, 'pause')
        if self._move is move and move.phase == PAUSING:
            self._enter(move, WAIT_SERVER)

    def _send_goal(self, move: Move) -> None:
        move.enter(SENDING)
        move.sent_at = move.since
        move.goal_future = self._move_client.send_goal_async(self._goal(move))
        move.goal_future.add_done_callback(lambda f: self._on_goal_response(f, move))

    def _goal(self, move: Move) -> MoveGroup.Goal:
        goal = MoveGroup.Goal()
        request = goal.request
        request.group_name = self._group
        request.num_planning_attempts = 1
        request.allowed_planning_time = float(self._planning_time)
        request.max_velocity_scaling_factor = float(self._velocity_scaling)
        request.max_acceleration_scaling_factor = float(self._acceleration_scaling)
        request.start_state.is_diff = True  # plan from the current state
        # The planner aims a tenth of the reporting tolerance from the target, so the
        # arm reports the state once it stops.
        goal_tolerance = self._tolerance / 10.0
        request.goal_constraints = [Constraints(joint_constraints=[
            JointConstraint(joint_name=joint, position=value, tolerance_above=goal_tolerance,
                            tolerance_below=goal_tolerance, weight=1.0)
            for joint, value in move.target.items()
        ])]
        goal.planning_options.plan_only = False
        goal.planning_options.planning_scene_diff.is_diff = True
        goal.planning_options.planning_scene_diff.robot_state.is_diff = True
        return goal

    def _on_goal_response(self, future, move: Move) -> None:
        goal_handle = future.result()
        if goal_handle is None or not goal_handle.accepted:
            self._end_move(move, 'rejected by move_group')
            return
        move.goal_handle = goal_handle
        if self._move is not move:
            # The move was given up (or the node is shutting down) before move_group
            # accepted it: stop it before the arm starts.
            self._cancel_goal(move)
            return
        if move.cancel_requested:
            self._cancel_goal(move)
            move.enter(CANCELLING)
        else:
            move.phase = RUNNING  # the run timeout counts from sent_at
        goal_handle.get_result_async().add_done_callback(lambda f: self._on_result(f, move))

    def _on_result(self, future, move: Move) -> None:
        response = future.result()
        if response is None:
            self._end_move(move, 'no result')
            return
        outcome = GOAL_STATUS_NAMES.get(response.status, f'status {response.status}')
        error_code = response.result.error_code.val
        if response.status != GoalStatus.STATUS_CANCELED and error_code != MoveItErrorCodes.SUCCESS:
            outcome += f' (MoveIt error code {error_code})'
        self._end_move(move, outcome)

    def _cancel(self, move: Move) -> None:
        """Cancel move; the pending tap, if any, starts when the move ends."""
        if move.cancel_requested:
            return
        move.cancel_requested = True
        if move.phase == RUNNING:
            self._cancel_goal(move)
            move.enter(CANCELLING)
        elif move.phase in BEFORE_GOAL:
            self._advance(move)  # ends it now
        # SENDING: the goal is cancelled as soon as move_group accepts it.

    def _cancel_goal(self, move: Move):
        """Ask move_group to cancel move's goal once; return the cancel future, or None before acceptance."""
        if move.goal_handle is not None and move.cancel_future is None:
            move.cancel_future = move.goal_handle.cancel_goal_async()
        return move.cancel_future

    def _end_move(self, move: Move, outcome: str) -> None:
        if self._move is not move:
            return
        self._move = None
        if move.stop_reason:
            outcome += f' ({move.stop_reason})'
        # rclpy refuses one call site logging at two severities, so these are two calls.
        if outcome == 'succeeded':
            self.get_logger().info(f"Move to '{move.name}' succeeded")
        else:
            self.get_logger().warning(f"Move to '{move.name}' {outcome}")
        if self._pending is not None:
            name, self._pending = self._pending, None
            # The SRDF may have changed since the tap.
            decision = decide_command(name, self._states, clutch_engaged=self._clutch.engaged(time.monotonic()))
            if decision.action == MOVE:
                self._start_move(name)  # Servo stays paused for the next move
                return
            self.get_logger().warning(f'Dropping the named pose that waited for the cancel: {decision.reason}')
        self._resume_servo()
        self._update_state()

    # --- Servo ---

    def _resume_servo(self, log_response: bool = True):
        """Resume Servo if this node paused it. Return the call's future, or None."""
        if not self._servo_paused:
            return None
        self._servo_paused = False
        if not self._servo_client.service_is_ready():
            self.get_logger().warning(f'Servo pause service {self._servo_client.srv_name} is gone; cannot resume Servo')
            return None
        future = self._servo_client.call_async(SetBool.Request(data=False))
        if log_response:
            future.add_done_callback(lambda f: self._log_servo_response(f, 'resume'))
        return future

    def _log_servo_response(self, future, verb: str) -> None:
        response = future.result()
        if response is None or not response.success:
            message = response.message if response is not None else 'no response'
            self.get_logger().warning(f'Servo did not {verb}: {message}')
        else:
            self.get_logger().info(f'Servo {verb}d ({response.message})')

    # --- shutdown ---

    def shutdown(self, executor, timeout_s: float = 2.0) -> None:
        """Cancel the running move and resume Servo, spinning executor until both finish.

        Callbacks still queued on the executor run while it spins here. With the move
        detached and marked cancelled, a late Servo answer does not send the goal, and
        a late goal acceptance cancels the goal.
        """
        self._pending = None
        move, self._move = self._move, None
        if move is not None:
            move.cancel_requested = True
            self.get_logger().info(f"Shutting down: cancelling the move to '{move.name}'")
            if move.goal_future is not None:
                if not move.goal_future.done():
                    executor.spin_until_future_complete(move.goal_future, timeout_sec=timeout_s)
                if move.goal_handle is None and move.goal_future.done():
                    goal_handle = move.goal_future.result()
                    if goal_handle is not None and goal_handle.accepted:
                        move.goal_handle = goal_handle
                if not move.goal_future.done():
                    self.get_logger().warning('move_group did not answer the goal in time; it may still run it')
            cancel_future = self._cancel_goal(move)
            if cancel_future is not None:
                executor.spin_until_future_complete(cancel_future, timeout_sec=timeout_s)
                if not cancel_future.done():
                    self.get_logger().warning('move_group did not answer the cancel in time')
        # A done callback would only be queued on the executor, which stops spinning here,
        # so the response is logged directly.
        future = self._resume_servo(log_response=False)
        if future is not None:
            executor.spin_until_future_complete(future, timeout_sec=timeout_s)
            if future.done():
                self._log_servo_response(future, 'resume')
            else:
                self.get_logger().warning('Servo did not answer the resume request in time')


def _raise_keyboard_interrupt(_signum, _frame):
    raise KeyboardInterrupt


def main(args=None):
    # rclpy's own SIGINT handler shuts the context down at once, and the goal cancel
    # and the Servo resume need it alive. Handle SIGINT / SIGTERM here instead and
    # spin with a timeout so the handler gets to run. SIGINT is set explicitly, as
    # rclpy's handler would be: Python keeps a SIGINT ignored by the parent (a
    # launch started from a script's background job), and such a node would ignore
    # the SIGINT that ros2 launch stops it with.
    rclpy.init(args=args, signal_handler_options=SignalHandlerOptions.NO)
    signal.signal(signal.SIGINT, _raise_keyboard_interrupt)
    signal.signal(signal.SIGTERM, _raise_keyboard_interrupt)
    node = NamedPoseNode()
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    try:
        while rclpy.ok():
            executor.spin_once(timeout_sec=0.1)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if rclpy.ok():
            node.shutdown(executor)
        executor.shutdown()
        node.destroy_node()
        rclpy.try_shutdown()
