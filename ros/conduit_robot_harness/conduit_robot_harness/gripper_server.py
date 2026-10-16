"""conduit_gripper_server: a minimal control_msgs/action/GripperCommand server.

Stands in for the Panda hand on the Servo harness. A goal moves a simulated
finger position toward the (clamped) target at `speed` m/s with feedback at
20 Hz and succeeds on arrival. A new goal aborts the one in progress, as
Conduit's gripper client expects (spec §9.6).
"""

import threading
import time

import rclpy
from control_msgs.action import GripperCommand
from rclpy.action import ActionServer, CancelResponse, GoalResponse
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node

STEP_PERIOD = 0.05


class GripperServer(Node):

    def __init__(self):
        super().__init__('conduit_gripper_server')
        self.action_name = self.declare_parameter('action_name', '/panda_hand_controller/gripper_cmd').value
        self.min_position = float(self.declare_parameter('min_position', 0.0).value)
        self.max_position = float(self.declare_parameter('max_position', 0.04).value)
        self.speed = float(self.declare_parameter('speed', 0.05).value)
        self.position = self.max_position
        self._lock = threading.Lock()
        self._active = None
        self._server = ActionServer(
            self, GripperCommand, self.action_name,
            execute_callback=self.execute,
            goal_callback=lambda _goal: GoalResponse.ACCEPT,
            handle_accepted_callback=self.on_accepted,
            cancel_callback=lambda _goal: CancelResponse.ACCEPT,
            callback_group=ReentrantCallbackGroup(),
        )
        self.get_logger().info(f'GripperCommand server on {self.action_name}')

    def on_accepted(self, goal_handle) -> None:
        with self._lock:
            previous, self._active = self._active, goal_handle
        if previous is not None and previous.is_active:
            previous.abort()
        goal_handle.execute()

    def execute(self, goal_handle):
        command = goal_handle.request.command
        target = min(max(command.position, self.min_position), self.max_position)
        step = self.speed * STEP_PERIOD
        feedback = GripperCommand.Feedback()
        while True:
            if not goal_handle.is_active:          # aborted by a newer goal
                break
            if goal_handle.is_cancel_requested:
                goal_handle.canceled()
                break
            delta = target - self.position
            if abs(delta) <= step:
                self.position = target
                goal_handle.succeed()
                break
            self.position += step if delta > 0 else -step
            feedback.position = self.position
            feedback.effort = 0.0
            feedback.stalled = False
            feedback.reached_goal = False
            goal_handle.publish_feedback(feedback)
            time.sleep(STEP_PERIOD)
        result = GripperCommand.Result()
        result.position = self.position
        result.effort = 0.0
        result.stalled = False
        result.reached_goal = abs(self.position - target) < 1e-9
        return result


def main():
    rclpy.init()
    node = GripperServer()
    executor = MultiThreadedExecutor()
    executor.add_node(node)
    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
