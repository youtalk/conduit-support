"""map_camera: a first-person camera for a robot that has none.

Draws the occupancy map from the robot's pose (TF ``map`` -> ``base_link``) with the
raycaster and publishes it as ``/camera/image_raw``, so the app's camera panel shows a
view that moves with the robot. Publishes nothing until both the map and the pose exist.
"""

import math

from nav_msgs.msg import OccupancyGrid
import rclpy
from rclpy.clock import Clock, ClockType
from rclpy.duration import Duration
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy
from rclpy.time import Time
from sensor_msgs.msg import Image
from tf2_ros import Buffer, TransformException, TransformListener

from conduit_demo.raycast import GridView, Pose2D, render


class MapCamera(Node):

    def __init__(self):
        super().__init__('map_camera')
        rate_hz = self.declare_parameter('rate_hz', 10.0).value
        self._width = int(self.declare_parameter('width', 320).value)
        self._height = int(self.declare_parameter('height', 240).value)
        self._fov_deg = self.declare_parameter('fov_deg', 70.0).value
        self._grid = None
        # Wall time whatever use_sim_time says: stamps and the timer ignore /clock.
        self._clock = Clock(clock_type=ClockType.SYSTEM_TIME)
        self._tf_buffer = Buffer()
        self._tf_listener = TransformListener(self._tf_buffer, self)
        map_qos = QoSProfile(
            depth=1, reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL)
        self.create_subscription(OccupancyGrid, '/map', self._on_map, map_qos)
        self._pub = self.create_publisher(Image, '/camera/image_raw', 1)
        self.create_timer(1.0 / rate_hz, self._tick, clock=self._clock)

    def _on_map(self, msg):
        info = msg.info
        self._grid = GridView(
            info.width, info.height, info.resolution,
            info.origin.position.x, info.origin.position.y, msg.data)

    def _pose(self):
        try:
            tf = self._tf_buffer.lookup_transform(
                'map', 'base_link', Time(), timeout=Duration(seconds=0.0))
        except TransformException:
            return None
        t, q = tf.transform.translation, tf.transform.rotation
        yaw = math.atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))
        return Pose2D(t.x, t.y, yaw)

    def _tick(self):
        pose = self._pose()
        if self._grid is None or pose is None:
            return
        image = render(self._grid, pose, self._width, self._height, self._fov_deg)
        msg = Image()
        msg.header.stamp = self._clock.now().to_msg()
        msg.header.frame_id = 'camera_link'
        msg.height, msg.width = image.shape[:2]
        msg.encoding = 'rgb8'
        msg.step = msg.width * 3
        msg.data = image.tobytes()
        self._pub.publish(msg)


def main():
    rclpy.init()
    node = MapCamera()
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
