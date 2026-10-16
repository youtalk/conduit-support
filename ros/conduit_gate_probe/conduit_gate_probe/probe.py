"""conduit_gate_probe: host-clock timing for the Conduit 3.0 device gates (G1, G2).

Subscribes the phone's outputs and what the host makes of them, stamps every
receipt with the host clock, and reports:

- joy_to_cmd_vel: /joy phone stamp -> cmd_vel on the host (G1, p95 <= 100 ms),
- stop_after_release / stop_after_joy_silence: deadman released or Joy lost ->
  first zero cmd_vel (G1, Wi-Fi off must stop within 1 s),
- twist_delay: Servo twist phone stamp -> host receipt (what Servo's
  incoming_command_timeout sees),
- servo_stop_after_release: clutch released -> Servo commanding zero velocity
  (G2, <= 200 ms).

Clock offset: the phone (or conduit_gate_ping) publishes std_msgs/Header on
/conduit/gate/ping with its send time in `stamp`; the probe echoes it on
/conduit/gate/pong with `frame_id` = "<ping frame_id>|<host receive ns>". The
sender computes the offset from the round trip. Pass it as `phone_offset_ns`
(host - phone); otherwise the probe uses min(host receive - ping stamp), an
upper bound that includes the smallest one-way delay.
"""

import json
import os
import time

import rclpy
from geometry_msgs.msg import Twist, TwistStamped
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import Joy
from std_msgs.msg import Bool, Header
from trajectory_msgs.msg import JointTrajectory

from conduit_gate_probe.stats import NS_PER_S, JoyCmdTracker, ServoStopTracker, summarize

DEADMAN_BUTTON = 9  # JoyLayout.Button.leftShoulder (ROS joy game_controller_node)


def stamp_ns(stamp) -> int:
    return stamp.sec * NS_PER_S + stamp.nanosec


def is_zero_twist(twist) -> bool:
    values = (twist.linear.x, twist.linear.y, twist.linear.z,
              twist.angular.x, twist.angular.y, twist.angular.z)
    return all(abs(v) < 1e-6 for v in values)


class GateProbe(Node):

    def __init__(self):
        super().__init__('conduit_gate_probe')
        self.joy_topic = self.declare_parameter('joy_topic', '/joy').value
        self.cmd_vel_topic = self.declare_parameter('cmd_vel_topic', '/cmd_vel').value
        self.twist_topic = self.declare_parameter('twist_topic', '/servo_node/delta_twist_cmds').value
        self.clutch_topic = self.declare_parameter('clutch_topic', '/conduit/teleop/clutch').value
        self.servo_output_topic = self.declare_parameter(
            'servo_output_topic', '/panda_arm_controller/joint_trajectory').value
        self.offset_param = int(self.declare_parameter('phone_offset_ns', 0).value)
        self.report_dir = self.declare_parameter('report_dir', '/tmp/conduit_gate_probe').value

        qos = QoSProfile(reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.VOLATILE,
                         history=HistoryPolicy.KEEP_LAST, depth=50)
        self.joy_cmd = JoyCmdTracker(offset_ns=self.offset_param)
        self.servo = ServoStopTracker()
        self.twist_delay_ms = []
        self.min_ping_delta_ns = None
        self.pings = 0

        self.pong_pub = self.create_publisher(Header, '/conduit/gate/pong', qos)
        self.create_subscription(Header, '/conduit/gate/ping', self.on_ping, qos)
        self.create_subscription(Joy, self.joy_topic, self.on_joy, qos)
        self.create_subscription(Twist, self.cmd_vel_topic, self.on_cmd_vel, qos)
        self.create_subscription(TwistStamped, self.twist_topic, self.on_twist, qos)
        self.create_subscription(Bool, self.clutch_topic, self.on_clutch, qos)
        self.create_subscription(JointTrajectory, self.servo_output_topic, self.on_servo_output, qos)
        self.create_timer(5.0, self.log_summary)
        self.get_logger().info(
            f'probing joy={self.joy_topic} cmd_vel={self.cmd_vel_topic} twist={self.twist_topic} '
            f'clutch={self.clutch_topic} servo_out={self.servo_output_topic}')

    def offset_ns(self) -> int:
        if self.offset_param != 0:
            return self.offset_param
        return self.min_ping_delta_ns or 0

    def on_ping(self, msg: Header) -> None:
        t2 = time.time_ns()
        delta = t2 - stamp_ns(msg.stamp)
        self.min_ping_delta_ns = delta if self.min_ping_delta_ns is None else min(self.min_ping_delta_ns, delta)
        self.pings += 1
        self.joy_cmd.offset_ns = self.offset_ns()
        pong = Header()
        pong.stamp = msg.stamp
        pong.frame_id = f'{msg.frame_id}|{t2}'
        self.pong_pub.publish(pong)

    def on_joy(self, msg: Joy) -> None:
        deadman = len(msg.buttons) > DEADMAN_BUTTON and msg.buttons[DEADMAN_BUTTON] == 1
        self.joy_cmd.on_joy(time.time_ns(), stamp_ns(msg.header.stamp), deadman)

    def on_cmd_vel(self, msg: Twist) -> None:
        self.joy_cmd.on_cmd(time.time_ns(), is_zero_twist(msg))

    def on_twist(self, msg: TwistStamped) -> None:
        now = time.time_ns()
        self.servo.on_twist(now, not is_zero_twist(msg.twist))
        self.twist_delay_ms.append((now - (stamp_ns(msg.header.stamp) + self.offset_ns())) / 1e6)

    def on_clutch(self, msg: Bool) -> None:
        self.servo.on_clutch(time.time_ns(), msg.data)

    def on_servo_output(self, msg: JointTrajectory) -> None:
        if not msg.points:
            return
        velocities = msg.points[0].velocities
        self.servo.on_output(time.time_ns(), max((abs(v) for v in velocities), default=0.0))

    def report(self) -> dict:
        offset_source = 'parameter' if self.offset_param else ('ping-min' if self.pings else 'none')
        return {
            'offset_ns': self.offset_ns(),
            'offset_source': offset_source,
            'pings': self.pings,
            'joy_to_cmd_vel': summarize(self.joy_cmd.latencies_ms),
            'stop_after_release': summarize(self.joy_cmd.release_stops_ms),
            'stop_after_joy_silence': summarize(self.joy_cmd.silence_stops_ms),
            'twist_delay': summarize(self.twist_delay_ms),
            'servo_stop_after_release': summarize(self.servo.stops_ms),
        }

    def log_summary(self) -> None:
        self.get_logger().info(json.dumps(self.report()))

    def write_report(self) -> str:
        os.makedirs(self.report_dir, exist_ok=True)
        path = os.path.join(self.report_dir, time.strftime('gate-%Y%m%d-%H%M%S.json'))
        with open(path, 'w') as f:
            json.dump(self.report(), f, indent=2)
        return path


def main():
    rclpy.init()
    node = GateProbe()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        print(f'report: {node.write_report()}', flush=True)
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
