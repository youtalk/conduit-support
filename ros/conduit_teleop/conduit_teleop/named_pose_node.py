"""named_pose_node: move a MoveIt arm to an SRDF group state when Conduit asks for it.

Conduit's pose buttons publish the name of an SRDF ``group_state`` (std_msgs/String,
``/conduit/teleop/named_pose`` by default). This node plans and executes a move to
that state through move_group's MoveGroup action, pausing MoveIt Servo for the
move so the two never command the arm at once. It reports where the arm is on a
latched std_msgs/String (``/conduit/teleop/named_pose_state``): the name of the
group state the joints are at, or '' while moving or anywhere else.

A tap during a move cancels that move and starts the new one once the cancel has
finished (the newest tap wins). Servo stays paused across the hand-over and is
resumed when the last move ends, whether it succeeded, failed or was cancelled.

Everything runs on one single-threaded executor, so the callbacks never race.
"""

import signal
from typing import Optional

from action_msgs.msg import GoalStatus
from moveit_msgs.action import MoveGroup
from moveit_msgs.msg import Constraints, JointConstraint, MoveItErrorCodes
import rclpy
from rclpy.action import ActionClient
from rclpy.executors import ExternalShutdownException, SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy
from rclpy.signals import SignalHandlerOptions
from sensor_msgs.msg import JointState
from std_msgs.msg import String
from std_srvs.srv import SetBool

from conduit_teleop.named_pose_logic import (
    CANCEL_THEN_MOVE, REJECT, current_state, decide_command, parse_group_states, parse_parameters)

LATCHED = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.TRANSIENT_LOCAL)

GOAL_STATUS_NAMES = {
    GoalStatus.STATUS_SUCCEEDED: 'succeeded',
    GoalStatus.STATUS_ABORTED: 'aborted',
    GoalStatus.STATUS_CANCELED: 'cancelled',
}


class Move:
    """One requested move, from the command to its result."""

    def __init__(self, name: str):
        self.name = name
        self.goal_handle = None  # set once move_group accepts the goal
        self.pause_timer = None  # set while the Servo pause request is outstanding
        self.cancel_requested = False


class NamedPoseNode(Node):

    def __init__(self):
        super().__init__('conduit_named_pose')
        self._group = self.declare_parameter('planning_group', 'arm').value
        command_topic = self.declare_parameter('command_topic', '/conduit/teleop/named_pose').value
        state_topic = self.declare_parameter('state_topic', '/conduit/teleop/named_pose_state').value
        move_action = self.declare_parameter('move_action', 'move_action').value
        servo_pause_service = self.declare_parameter('servo_pause_service', '/servo_node/pause_servo').value
        self._velocity_scaling = self.declare_parameter('velocity_scaling', 0.2).value
        self._acceleration_scaling = self.declare_parameter('acceleration_scaling', 0.2).value
        self._tolerance = self.declare_parameter('tolerance', 0.01).value
        self._planning_time = self.declare_parameter('planning_time', 5.0).value
        # How long to wait for the Servo pause service or the MoveGroup action server.
        self._service_timeout = self.declare_parameter('service_timeout', 1.0).value
        parse_parameters(self._velocity_scaling, self._acceleration_scaling, self._tolerance, self._planning_time)

        self._states = {}  # group states of the planning group, SRDF order
        self._joint_positions = {}
        self._move: Optional[Move] = None
        self._pending: Optional[str] = None  # the tap that waits for the running move's cancel
        self._servo_paused = False  # True while this node holds Servo paused
        self._published_state: Optional[str] = None

        self._state_pub = self.create_publisher(String, state_topic, LATCHED)
        self._move_action = move_action
        self._move_client = ActionClient(self, MoveGroup, move_action)
        self._servo_client = self.create_client(SetBool, servo_pause_service)
        self.create_subscription(String, 'robot_description_semantic', self._on_srdf, LATCHED)
        self.create_subscription(JointState, 'joint_states', self._on_joint_states, 10)
        self.create_subscription(String, command_topic, self._on_command, 10)
        self._publish_state('')
        self.get_logger().info(
            f"Waiting for '{self._group}' group states on {command_topic}; state on {state_topic}")

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

    def _on_joint_states(self, msg: JointState) -> None:
        self._joint_positions.update(zip(msg.name, msg.position))
        self._update_state()

    def _on_command(self, msg: String) -> None:
        name = msg.data
        decision = decide_command(name, self._states, self._move is not None)
        if decision.action == REJECT:
            self.get_logger().warning(f'Ignoring named pose: {decision.reason}')
            return
        if decision.action == CANCEL_THEN_MOVE:
            self.get_logger().info(f"'{name}' requested: cancelling the move to '{self._move.name}' first")
            self._pending = name
            self._cancel(self._move)
            return
        self._start_move(name)

    # --- state topic ---

    def _publish_state(self, state: str) -> None:
        if state == self._published_state:
            return
        self._state_pub.publish(String(data=state))
        self._published_state = state

    def _update_state(self) -> None:
        if self._move is None:
            self._publish_state(current_state(self._joint_positions, self._states, self._tolerance))

    # --- moves ---

    def _start_move(self, name: str) -> None:
        move = Move(name)
        self._move = move
        self._publish_state('')
        self.get_logger().info(f"Moving '{self._group}' to '{name}'")
        if self._servo_paused:
            self._send_goal(move)
            return
        if not self._servo_client.wait_for_service(timeout_sec=self._service_timeout):
            self.get_logger().warning(
                f'Servo pause service {self._servo_client.srv_name} is not available; moving without pausing Servo')
            self._send_goal(move)
            return
        self._servo_paused = True
        future = self._servo_client.call_async(SetBool.Request(data=True))
        future.add_done_callback(lambda f: self._on_servo_paused(f, move))
        # Do not let a Servo that never answers hold the move back.
        move.pause_timer = self.create_timer(self._service_timeout, lambda: self._on_servo_paused(None, move))

    def _on_servo_paused(self, future, move: Move) -> None:
        if move.pause_timer is None:
            return  # the response or the timeout already went on with the move
        self.destroy_timer(move.pause_timer)
        move.pause_timer = None
        if future is None:
            self.get_logger().warning('Servo did not answer the pause request in time; moving anyway')
        else:
            self._log_servo_response(future, 'pause')
        if move.cancel_requested:
            self._end_move(move, 'cancelled before it was sent')
            return
        self._send_goal(move)

    def _send_goal(self, move: Move) -> None:
        if not self._move_client.wait_for_server(timeout_sec=self._service_timeout):
            self.get_logger().error(
                f'MoveGroup action {self._move_action} is not available; is move_group running?')
            self._end_move(move, 'not sent')
            return
        future = self._move_client.send_goal_async(self._goal(move.name))
        future.add_done_callback(lambda f: self._on_goal_response(f, move))

    def _goal(self, name: str) -> MoveGroup.Goal:
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
            for joint, value in self._states[name].items()
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
        if move.cancel_requested:
            goal_handle.cancel_goal_async()
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
        if move.cancel_requested:
            return
        move.cancel_requested = True
        if move.goal_handle is not None:
            move.goal_handle.cancel_goal_async()
        # Otherwise the goal is cancelled as soon as move_group accepts it, or never sent.

    def _end_move(self, move: Move, outcome: str) -> None:
        if self._move is not move:
            return
        self._move = None
        # rclpy refuses one call site logging at two severities, so these are two calls.
        if outcome == 'succeeded':
            self.get_logger().info(f"Move to '{move.name}' succeeded")
        else:
            self.get_logger().warning(f"Move to '{move.name}' {outcome}")
        if self._pending is not None:
            name, self._pending = self._pending, None
            self._start_move(name)  # Servo stays paused for the next move
            return
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
        """Cancel the running move and resume Servo, spinning executor until both finish."""
        self._pending = None
        move, self._move = self._move, None
        if move is not None:
            self.get_logger().info(f"Shutting down: cancelling the move to '{move.name}'")
            if move.goal_handle is not None:
                executor.spin_until_future_complete(move.goal_handle.cancel_goal_async(), timeout_sec=timeout_s)
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
    # spin with a timeout so the handler gets to run.
    rclpy.init(args=args, signal_handler_options=SignalHandlerOptions.NO)
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
