"""gripper_command: a control_msgs/action/GripperCommand server in front of a parallel gripper.

ROS 2 Lyrical's gripper action controller (parallel_gripper_action_controller) serves
control_msgs/action/ParallelGripperCommand; Conduit's gripper, like most GripperCommand
clients, sends control_msgs/action/GripperCommand. This node serves GripperCommand on
`action_name` (default /panda_hand_controller/gripper_cmd) and forwards each goal to the
controller's ParallelGripperCommand server on `controller_action` (default
/panda_hand_controller/parallel_gripper_cmd) for the finger joint `joint`:

- the goal's position goes to the joint, its max_effort as the joint's effort when > 0;
- feedback and result carry the joint's position and effort (from the controller's state,
  or /joint_states when the controller has not reported yet), stalled and reached_goal;
- a new goal aborts the one in progress (the controller preempts its own goal too), and a
  cancel is passed on to the controller.
"""

import threading
import time

import rclpy
from action_msgs.msg import GoalStatus
from control_msgs.action import GripperCommand, ParallelGripperCommand
from rclpy.action import ActionClient, ActionServer, CancelResponse, GoalResponse
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import ExternalShutdownException, MultiThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import JointState

POLL_PERIOD = 0.02


def joint_value(names, values, joint):
    """The value of `joint` in a JointState's names and values; 0.0 when it is missing."""
    names = list(names)
    values = list(values)
    if joint in names:
        index = names.index(joint)
        if index < len(values):
            return float(values[index])
    if len(names) == 0 and len(values) == 1:
        return float(values[0])
    return 0.0


def _can_end(goal_handle):
    """True when the goal may take a terminal state (rcl_action: from EXECUTING or CANCELING)."""
    return goal_handle.status in (GoalStatus.STATUS_EXECUTING, GoalStatus.STATUS_CANCELING)


def parallel_command(joint, position, max_effort):
    """The ParallelGripperCommand goal for one GripperCommand goal."""
    goal = ParallelGripperCommand.Goal()
    goal.command.name = [joint]
    goal.command.position = [float(position)]
    if max_effort > 0.0:
        goal.command.effort = [float(max_effort)]
    return goal


class GripperCommandServer(Node):

    def __init__(self):
        super().__init__('gripper_command')
        self.action_name = self.declare_parameter(
            'action_name', '/panda_hand_controller/gripper_cmd').value
        self.controller_action = self.declare_parameter(
            'controller_action', '/panda_hand_controller/parallel_gripper_cmd').value
        self.joint = self.declare_parameter('joint', 'panda_finger_joint1').value
        group = ReentrantCallbackGroup()
        self._client = ActionClient(
            self, ParallelGripperCommand, self.controller_action, callback_group=group)
        self._lock = threading.Lock()
        self._active = None
        self._joint_state = None  # the latest /joint_states message with `joint`
        self.create_subscription(
            JointState, '/joint_states', self._on_joint_states, qos_profile_sensor_data,
            callback_group=group)
        self._server = ActionServer(
            self, GripperCommand, self.action_name,
            execute_callback=self.execute,
            goal_callback=lambda _goal: GoalResponse.ACCEPT,
            handle_accepted_callback=self.on_accepted,
            cancel_callback=lambda _goal: CancelResponse.ACCEPT,
            callback_group=group,
        )
        self.get_logger().info(
            f'GripperCommand on {self.action_name} -> ParallelGripperCommand on '
            f'{self.controller_action} ({self.joint})')

    def _on_joint_states(self, message):
        if self.joint in message.name:
            self._joint_state = message

    def on_accepted(self, goal_handle):
        # execute() moves the goal from ACCEPTED to EXECUTING (it only schedules the
        # execute callback), inside the lock, so _active never holds an ACCEPTED goal: a
        # goal can end only from EXECUTING or CANCELING.
        with self._lock:
            previous, self._active = self._active, goal_handle
            if previous is not None and _can_end(previous):
                previous.abort()
            goal_handle.execute()

    def _finish(self, goal_handle, end):
        """Ends the goal with `end` ('succeed', 'abort' or 'canceled') unless it has ended.

        Under the lock, because a newer goal aborts this one from another thread.
        """
        with self._lock:
            if _can_end(goal_handle):
                getattr(goal_handle, end)()

    def _result(self, state, stalled=False, reached_goal=False):
        result = GripperCommand.Result()
        if state is None or (self.joint not in state.name and len(state.position) != 1):
            state = self._joint_state  # the controller reported no state yet
        if state is not None:
            result.position = joint_value(state.name, state.position, self.joint)
            result.effort = joint_value(state.name, state.effort, self.joint)
        result.stalled = bool(stalled)
        result.reached_goal = bool(reached_goal)
        return result

    def _wait(self, future, goal_handle, timeout_s):
        """Waits for `future`; False when it times out or the goal stops being active."""
        deadline = time.monotonic() + timeout_s
        while not future.done():
            if not goal_handle.is_active or time.monotonic() > deadline:
                return False
            time.sleep(POLL_PERIOD)
        return True

    def execute(self, goal_handle):
        command = goal_handle.request.command
        last_state = []

        def on_feedback(message):
            feedback = message.feedback
            last_state[:] = [feedback.state]
            if goal_handle.is_active:
                out = GripperCommand.Feedback()
                out.position = joint_value(feedback.state.name, feedback.state.position, self.joint)
                out.effort = joint_value(feedback.state.name, feedback.state.effort, self.joint)
                out.stalled = feedback.stalled
                out.reached_goal = feedback.reached_goal
                goal_handle.publish_feedback(out)

        if not self._client.wait_for_server(timeout_sec=5.0):
            self.get_logger().error(f'{self.controller_action} is not available')
            self._finish(goal_handle, 'abort')
            return self._result(None)
        # Under the lock that on_accepted takes, so a newer goal's controller goal is
        # always sent after this one's, never before.
        with self._lock:
            if self._active is not goal_handle or not goal_handle.is_active:
                return self._result(None)
            sent = self._client.send_goal_async(
                parallel_command(self.joint, command.position, command.max_effort),
                feedback_callback=on_feedback)
        if not self._wait(sent, goal_handle, 5.0) or not sent.result().accepted:
            self._finish(goal_handle, 'abort')
            return self._result(None)
        controller_goal = sent.result()
        result_future = controller_goal.get_result_async()
        while not result_future.done():
            if not goal_handle.is_active:  # aborted by a newer goal
                return self._result(last_state[0] if last_state else None)
            if goal_handle.is_cancel_requested:
                controller_goal.cancel_goal_async()
                self._finish(goal_handle, 'canceled')
                return self._result(last_state[0] if last_state else None)
            time.sleep(POLL_PERIOD)
        response = result_future.result()
        outcome = response.result
        result = self._result(outcome.state, outcome.stalled, outcome.reached_goal)
        if response.status == GoalStatus.STATUS_SUCCEEDED:
            self._finish(goal_handle, 'succeed')
        elif response.status == GoalStatus.STATUS_CANCELED and goal_handle.is_cancel_requested:
            self._finish(goal_handle, 'canceled')
        else:
            self._finish(goal_handle, 'abort')
        return result


def main():
    rclpy.init()
    node = GripperCommandServer()
    executor = MultiThreadedExecutor()
    executor.add_node(node)
    try:
        executor.spin()
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
