"""fake_mobile_robot: the topics a Kachaka-class robot publishes, from a simulated world.

Run it in a namespace (the launch file uses `fake_robot`). Publishes
- camera/image_raw/compressed  sensor_msgs/CompressedImage, JPEG, `camera_rate` Hz, best effort
- camera/image_raw             sensor_msgs/Image rgb8 320x240, 10 Hz, best effort (`publish_raw_image`)
- /map                         nav_msgs/OccupancyGrid, once, reliable + transient local
- scan                         sensor_msgs/LaserScan, 10 Hz, best effort, frame `laser`
- odom                         nav_msgs/Odometry, 20 Hz, reliable
- battery_state                sensor_msgs/BatteryState, 1 Hz
- /diagnostics                 diagnostic_msgs/DiagnosticArray, 1 Hz (one WARN on purpose)
- /tf map->odom (10 Hz), odom->base_link (20 Hz); /tf_static base_link->laser, base_link->camera_link
and drives from /cmd_vel (geometry_msgs/Twist), stopping 0.5 s after the last command.
"""

import array
import io
import math
import time

import numpy as np
import rclpy
from diagnostic_msgs.msg import DiagnosticArray, DiagnosticStatus, KeyValue
from geometry_msgs.msg import TransformStamped, Twist
from nav_msgs.msg import OccupancyGrid, Odometry
from PIL import Image as PILImage
from PIL import ImageDraw
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy, qos_profile_sensor_data
from sensor_msgs.msg import BatteryState, CompressedImage, Image, LaserScan
from tf2_ros import StaticTransformBroadcaster, TransformBroadcaster

from conduit_robot_harness.fake_world import (
    GridSpec,
    Pose2D,
    compose,
    integrate,
    inverse,
    make_grid,
    scan,
    yaw_to_quaternion,
)

MAP_TO_ODOM = Pose2D(0.5, 0.2, 0.1)   # a fixed "localization" offset
LASER_ON_BASE = Pose2D(0.1, 0.0, 0.0)
SCAN_COUNT = 360
SCAN_RANGE_MAX = 8.0


def to_array(typecode: str, values: np.ndarray) -> array.array:
    out = array.array(typecode)
    out.frombytes(values.tobytes())
    return out


class FakeMobileRobot(Node):

    def __init__(self):
        super().__init__('fake_mobile_robot')
        self.camera_rate = float(self.declare_parameter('camera_rate', 30.0).value)
        self.publish_raw_image = bool(self.declare_parameter('publish_raw_image', True).value)
        self.cmd_timeout = float(self.declare_parameter('cmd_timeout', 0.5).value)

        self.spec = GridSpec()
        self.grid = make_grid(self.spec)
        self.pose = Pose2D()                 # true pose in the map frame
        self.cmd = (0.0, 0.0)
        self.cmd_time = 0.0
        self.battery = 1.0
        self.frame = 0
        self.start = time.monotonic()

        latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE,
                             durability=DurabilityPolicy.TRANSIENT_LOCAL)
        self.image_pub = self.create_publisher(CompressedImage, 'camera/image_raw/compressed', qos_profile_sensor_data)
        self.raw_pub = self.create_publisher(Image, 'camera/image_raw', qos_profile_sensor_data)
        self.map_pub = self.create_publisher(OccupancyGrid, '/map', latched)
        self.scan_pub = self.create_publisher(LaserScan, 'scan', qos_profile_sensor_data)
        self.odom_pub = self.create_publisher(Odometry, 'odom', 10)
        self.battery_pub = self.create_publisher(BatteryState, 'battery_state', 10)
        self.diag_pub = self.create_publisher(DiagnosticArray, '/diagnostics', 10)
        self.tf = TransformBroadcaster(self)
        self.static_tf = StaticTransformBroadcaster(self)
        self.create_subscription(Twist, '/cmd_vel', self.on_cmd_vel, 10)

        self.publish_static_tf()
        self.publish_map()
        self.create_timer(1.0 / self.camera_rate, self.publish_camera)
        if self.publish_raw_image:
            self.create_timer(0.1, self.publish_raw)
        self.create_timer(0.05, self.step)
        self.create_timer(0.1, self.publish_map_to_odom)
        self.create_timer(0.1, self.publish_scan)
        self.create_timer(1.0, self.publish_battery_and_diagnostics)
        self.get_logger().info('fake mobile robot up')

    # --- inputs -------------------------------------------------------------

    def on_cmd_vel(self, msg: Twist) -> None:
        self.cmd = (msg.linear.x, msg.angular.z)
        self.cmd_time = time.monotonic()

    # --- helpers ------------------------------------------------------------

    def transform(self, parent: str, child: str, pose: Pose2D, z: float, stamp) -> TransformStamped:
        t = TransformStamped()
        t.header.stamp = stamp
        t.header.frame_id = parent
        t.child_frame_id = child
        t.transform.translation.x = pose.x
        t.transform.translation.y = pose.y
        t.transform.translation.z = z
        qx, qy, qz, qw = yaw_to_quaternion(pose.yaw)
        t.transform.rotation.x, t.transform.rotation.y = qx, qy
        t.transform.rotation.z, t.transform.rotation.w = qz, qw
        return t

    def render(self, width: int, height: int) -> PILImage.Image:
        img = PILImage.new('RGB', (width, height), (30, 34, 40))
        draw = ImageDraw.Draw(img)
        draw.rectangle([0, height // 2, width, height], fill=(70, 74, 80))
        # A bar that slides with the heading, so turning shows on the camera.
        x = int((math.degrees(self.pose.yaw) % 360.0) / 360.0 * width)
        draw.rectangle([x - width // 32, height // 4, x + width // 32, 3 * height // 4], fill=(240, 160, 40))
        t = time.monotonic() - self.start
        draw.text((12, 12), f'fake_robot #{self.frame} t={t:.2f}s x={self.pose.x:.2f} y={self.pose.y:.2f}',
                  fill=(255, 255, 255))
        return img

    # --- publishers ---------------------------------------------------------

    def publish_static_tf(self) -> None:
        stamp = self.get_clock().now().to_msg()
        self.static_tf.sendTransform([
            self.transform('base_link', 'laser', LASER_ON_BASE, 0.2, stamp),
            self.transform('base_link', 'camera_link', Pose2D(0.15, 0.0, 0.0), 0.3, stamp),
        ])

    def publish_map(self) -> None:
        msg = OccupancyGrid()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'map'
        msg.info.map_load_time = msg.header.stamp
        msg.info.resolution = self.spec.resolution
        msg.info.width = self.spec.width
        msg.info.height = self.spec.height
        msg.info.origin.position.x = self.spec.origin_x
        msg.info.origin.position.y = self.spec.origin_y
        msg.info.origin.orientation.w = 1.0
        msg.data = to_array('b', self.grid.reshape(-1))
        self.map_pub.publish(msg)

    def publish_camera(self) -> None:
        self.frame += 1
        buffer = io.BytesIO()
        self.render(640, 480).save(buffer, format='JPEG', quality=70)
        msg = CompressedImage()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'camera_link'
        msg.format = 'jpeg'
        msg.data = array.array('B', buffer.getvalue())
        self.image_pub.publish(msg)

    def publish_raw(self) -> None:
        pixels = np.asarray(self.render(320, 240), dtype=np.uint8)
        msg = Image()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'camera_link'
        msg.height, msg.width = pixels.shape[0], pixels.shape[1]
        msg.encoding = 'rgb8'
        msg.step = msg.width * 3
        msg.data = to_array('B', pixels.reshape(-1))
        self.raw_pub.publish(msg)

    def step(self) -> None:
        v, w = self.cmd
        if time.monotonic() - self.cmd_time > self.cmd_timeout:
            v, w = 0.0, 0.0
        self.pose = integrate(self.pose, v, w, 0.05, self.grid, self.spec)
        stamp = self.get_clock().now().to_msg()
        odom_pose = compose(inverse(MAP_TO_ODOM), self.pose)
        self.tf.sendTransform(self.transform('odom', 'base_link', odom_pose, 0.0, stamp))
        msg = Odometry()
        msg.header.stamp = stamp
        msg.header.frame_id = 'odom'
        msg.child_frame_id = 'base_link'
        msg.pose.pose.position.x = odom_pose.x
        msg.pose.pose.position.y = odom_pose.y
        qx, qy, qz, qw = yaw_to_quaternion(odom_pose.yaw)
        msg.pose.pose.orientation.x, msg.pose.pose.orientation.y = qx, qy
        msg.pose.pose.orientation.z, msg.pose.pose.orientation.w = qz, qw
        msg.twist.twist.linear.x = v
        msg.twist.twist.angular.z = w
        self.odom_pub.publish(msg)

    def publish_map_to_odom(self) -> None:
        self.tf.sendTransform(self.transform('map', 'odom', MAP_TO_ODOM, 0.0, self.get_clock().now().to_msg()))

    def publish_scan(self) -> None:
        # Stamped 50 ms in the past, like a scan stamped at its start, so a
        # consumer interpolates TF between two samples.
        stamp = (self.get_clock().now() - Duration(seconds=0.05)).to_msg()
        laser = compose(self.pose, LASER_ON_BASE)
        increment = 2.0 * math.pi / SCAN_COUNT
        ranges = scan(self.grid, self.spec, laser, -math.pi, increment, SCAN_COUNT, SCAN_RANGE_MAX)
        msg = LaserScan()
        msg.header.stamp = stamp
        msg.header.frame_id = 'laser'
        msg.angle_min = -math.pi
        msg.angle_max = -math.pi + increment * (SCAN_COUNT - 1)
        msg.angle_increment = increment
        msg.time_increment = 0.0
        msg.scan_time = 0.1
        msg.range_min = 0.05
        msg.range_max = SCAN_RANGE_MAX
        msg.ranges = to_array('f', ranges)
        self.scan_pub.publish(msg)

    def publish_battery_and_diagnostics(self) -> None:
        self.battery = self.battery - 0.001 if self.battery > 0.15 else 1.0
        stamp = self.get_clock().now().to_msg()
        battery = BatteryState()
        battery.header.stamp = stamp
        battery.voltage = 25.0
        battery.percentage = float(self.battery)
        battery.power_supply_status = BatteryState.POWER_SUPPLY_STATUS_DISCHARGING
        battery.present = True
        self.battery_pub.publish(battery)

        def status(level, name, message, values):
            s = DiagnosticStatus()
            s.level = level
            s.name = name
            s.message = message
            s.hardware_id = 'fake_robot'
            s.values = [KeyValue(key=k, value=v) for k, v in values]
            return s

        diag = DiagnosticArray()
        diag.header.stamp = stamp
        diag.status = [
            status(DiagnosticStatus.OK, 'fake_robot: motors', 'Running', [('speed', f'{self.cmd[0]:.2f}')]),
            status(DiagnosticStatus.OK, 'fake_robot: lidar', 'Scanning', [('rate', '10 Hz')]),
            status(DiagnosticStatus.WARN, 'fake_robot: camera', 'Exposure clipped', [('fps', f'{self.camera_rate:.0f}')]),
            status(DiagnosticStatus.OK if self.battery > 0.2 else DiagnosticStatus.WARN,
                   'fake_robot: battery', 'Discharging', [('percentage', f'{self.battery * 100:.0f}')]),
        ]
        self.diag_pub.publish(diag)


def main():
    rclpy.init()
    node = FakeMobileRobot()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
