"""joy_watchdog: stop the robot when the phone's Joy stream goes stale.

teleop_twist_joy publishes a Twist only when a Joy arrives, so when the phone loses
its link, a robot that keeps its last command keeps moving. This node sits between
teleop_twist_joy and the robot. It forwards ``cmd_vel_in`` while the newest Joy is
younger than ``timeout``. When the Joy goes stale it publishes a zero Twist at
``zero_rate_hz`` for ``zero_duration`` seconds, then stays silent until a Joy
arrives again, so it does not fight another cmd_vel publisher such as Nav2.
Freshness is the host's receipt time, so the phone's clock does not matter.
"""

import time

from geometry_msgs.msg import Twist
import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from sensor_msgs.msg import Joy

from conduit_teleop.watchdog_logic import FORWARD, ZERO, parse_parameters, watchdog_action


class JoyWatchdog(Node):

    def __init__(self):
        super().__init__('joy_watchdog')
        timeout_s = self.declare_parameter('timeout', 0.5).value
        zero_rate_hz = self.declare_parameter('zero_rate_hz', 10.0).value
        zero_duration_s = self.declare_parameter('zero_duration', 1.0).value
        self._timeout_ns, period_s, self._zero_duration_ns = parse_parameters(
            timeout_s, zero_rate_hz, zero_duration_s)
        self._last_joy_ns = None
        self._stale_reported = False
        self._publisher = self.create_publisher(Twist, 'cmd_vel', 10)
        self._joy_sub = self.create_subscription(Joy, 'joy', self._on_joy, 10)
        self._cmd_sub = self.create_subscription(Twist, 'cmd_vel_in', self._on_cmd_vel_in, 10)
        self._timer = self.create_timer(period_s, self._on_timer)

    def _action(self) -> str:
        return watchdog_action(time.monotonic_ns(), self._last_joy_ns, self._timeout_ns, self._zero_duration_ns)

    def _on_joy(self, _msg: Joy) -> None:
        self._last_joy_ns = time.monotonic_ns()

    def _on_cmd_vel_in(self, msg: Twist) -> None:
        if self._action() == FORWARD:
            self._publisher.publish(msg)

    def _on_timer(self) -> None:
        action = self._action()
        if action == FORWARD:
            if self._stale_reported:
                self.get_logger().info('Joy is back: forwarding cmd_vel_in')
                self._stale_reported = False
            return
        if action != ZERO:
            return  # silent: before the first Joy, or after the zero window
        if not self._stale_reported:
            self.get_logger().warning(
                f'No Joy for {self._timeout_ns / 1e9:.2f} s: publishing zero cmd_vel for '
                f'{self._zero_duration_ns / 1e9:.1f} s')
            self._stale_reported = True
        self._publisher.publish(Twist())


def main(args=None):
    rclpy.init(args=args)
    node = JoyWatchdog()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()
