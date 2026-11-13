"""initial_pose: give Nav2's loopback simulator the robot's starting pose.

The loopback simulator publishes no odometry, no scan and no ``map`` -> ``odom``
transform until a pose arrives on ``/initialpose``. This node publishes the pose of
its ``x``, ``y`` and ``yaw`` parameters once a second until the transform ``map`` ->
``base_footprint`` exists, then exits, so it never moves the robot afterwards.
"""

import math


def yaw_to_quaternion(yaw):
    """(z, w) of the rotation by ``yaw`` radians about +z (x and y are 0)."""
    return math.sin(yaw / 2.0), math.cos(yaw / 2.0)


def main():
    from geometry_msgs.msg import PoseWithCovarianceStamped
    import rclpy
    from rclpy.executors import ExternalShutdownException
    from rclpy.node import Node
    from rclpy.time import Time
    from tf2_ros import Buffer, TransformListener

    class InitialPose(Node):

        def __init__(self):
            super().__init__('initial_pose')
            self._x = float(self.declare_parameter('x', 0.0).value)
            self._y = float(self.declare_parameter('y', 0.0).value)
            self._yaw = float(self.declare_parameter('yaw', 0.0).value)
            self.placed = False
            self._tf_buffer = Buffer()
            self._tf_listener = TransformListener(self._tf_buffer, self)
            self._pub = self.create_publisher(PoseWithCovarianceStamped, '/initialpose', 10)
            self.create_timer(1.0, self._tick)

        def _tick(self):
            if self._tf_buffer.can_transform('map', 'base_footprint', Time()):
                self.get_logger().info(
                    f'robot placed at x {self._x}, y {self._y}, yaw {self._yaw}')
                self.placed = True
                return
            msg = PoseWithCovarianceStamped()
            msg.header.stamp = self.get_clock().now().to_msg()
            msg.header.frame_id = 'map'
            msg.pose.pose.position.x = self._x
            msg.pose.pose.position.y = self._y
            msg.pose.pose.orientation.z, msg.pose.pose.orientation.w = yaw_to_quaternion(
                self._yaw)
            self._pub.publish(msg)

    rclpy.init()
    node = InitialPose()
    try:
        while rclpy.ok() and not node.placed:
            rclpy.spin_once(node, timeout_sec=0.5)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
