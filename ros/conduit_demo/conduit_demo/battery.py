"""A simulated battery for the demo robot: drains, then charges, then repeats.

``battery_fraction`` and ``is_charging`` are pure; the node publishes them as a
``sensor_msgs/BatteryState`` at 1 Hz.
"""

DRAIN_SHARE = 0.8  # the first 80 % of a period drains, the rest charges
EMPTY = 0.2
MIN_VOLTAGE = 11.1
MAX_VOLTAGE = 12.6


def _phase(t_seconds, period_s):
    return (t_seconds % period_s) / period_s


def is_charging(t_seconds, period_s=1800.0):
    return _phase(t_seconds, period_s) >= DRAIN_SHARE


def battery_fraction(t_seconds, period_s=1800.0):
    """1.0 falling linearly to 0.2 over 80 % of the period, then charging back to 1.0."""
    phase = _phase(t_seconds, period_s)
    if phase < DRAIN_SHARE:
        return 1.0 - (1.0 - EMPTY) * phase / DRAIN_SHARE
    return EMPTY + (1.0 - EMPTY) * (phase - DRAIN_SHARE) / (1.0 - DRAIN_SHARE)


def voltage(fraction):
    return MIN_VOLTAGE + (MAX_VOLTAGE - MIN_VOLTAGE) * fraction


def main():
    import time

    from sensor_msgs.msg import BatteryState
    import rclpy
    from rclpy.executors import ExternalShutdownException
    from rclpy.node import Node

    class Battery(Node):

        def __init__(self):
            super().__init__('battery')
            self._period_s = self.declare_parameter('period_s', 1800.0).value
            self._start = time.monotonic()
            self._pub = self.create_publisher(BatteryState, '/battery_state', 10)
            self.create_timer(1.0, self._tick)

        def _tick(self):
            t = time.monotonic() - self._start
            fraction = battery_fraction(t, self._period_s)
            msg = BatteryState()
            msg.header.stamp = self.get_clock().now().to_msg()
            msg.percentage = float(fraction)
            msg.voltage = float(voltage(fraction))
            msg.present = True
            msg.power_supply_status = (
                BatteryState.POWER_SUPPLY_STATUS_CHARGING
                if is_charging(t, self._period_s)
                else BatteryState.POWER_SUPPLY_STATUS_DISCHARGING)
            self._pub.publish(msg)

    rclpy.init()
    node = Battery()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
