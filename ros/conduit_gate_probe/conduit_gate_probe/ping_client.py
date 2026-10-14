"""conduit_gate_ping: the phone side of conduit_gate_probe's clock echo.

Sends `count` pings at 5 Hz on /conduit/gate/ping and prints the clock offset
(probe host - this host) of the shortest round trip. Use it to check the probe
from another host; Conduit does the same on the phone in Debug builds launched
with `-ConduitGateEcho YES`.
"""

import time

import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import Header

from conduit_gate_probe.stats import NS_PER_S, offset_from_echo


class GatePing(Node):

    def __init__(self):
        super().__init__('conduit_gate_ping')
        self.count = int(self.declare_parameter('count', 50).value)
        qos = QoSProfile(reliability=ReliabilityPolicy.RELIABLE, durability=DurabilityPolicy.VOLATILE,
                         history=HistoryPolicy.KEEP_LAST, depth=50)
        self.ping_pub = self.create_publisher(Header, '/conduit/gate/ping', qos)
        self.create_subscription(Header, '/conduit/gate/pong', self.on_pong, qos)
        self.samples = []
        self.sent = 0
        self.done = False
        self.timer = self.create_timer(0.2, self.tick)

    def tick(self) -> None:
        if self.sent >= self.count:
            self.timer.cancel()
            self.finish()
            return
        t1 = time.time_ns()
        msg = Header()
        msg.stamp.sec = t1 // NS_PER_S
        msg.stamp.nanosec = t1 % NS_PER_S
        msg.frame_id = str(self.sent)
        self.sent += 1
        self.ping_pub.publish(msg)

    def on_pong(self, msg: Header) -> None:
        t4 = time.time_ns()
        _, t2 = msg.frame_id.split('|', 1)
        t1 = msg.stamp.sec * NS_PER_S + msg.stamp.nanosec
        self.samples.append((t1, int(t2), t4))

    def finish(self) -> None:
        best = offset_from_echo(self.samples)
        if best is None:
            self.get_logger().error('no pong received: is conduit_gate_probe running on this domain?')
        else:
            offset, rtt = best
            self.get_logger().info(
                f'offset_ns={offset} ({offset / 1e6:.2f} ms) rtt_ms={rtt / 1e6:.2f} '
                f'samples={len(self.samples)}/{self.sent}')
        self.done = True


def main():
    rclpy.init()
    node = GatePing()
    try:
        while rclpy.ok() and not node.done:
            rclpy.spin_once(node, timeout_sec=0.1)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
