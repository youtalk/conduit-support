"""arm_clock: the demo arm's joint states and Servo commands across its two clocks.

Gazebo's clock starts at zero and runs slower than wall time whenever Gazebo cannot keep
up (software rendering on a Mac, say). The arm's controllers run inside Gazebo, on that
clock. Conduit's HOLD needs the arm's clock to look like wall time: /joint_states stamps
within a day of the phone's clock and advancing at its rate, and MoveIt Servo aging the
app's twists (stamped on that clock) on the same clock. So Servo, move_group and
robot_state_publisher run on wall time, and this node joins the two sides:

- joint_state_broadcaster publishes on `joint_states_in` (default
  /joint_state_broadcaster/joint_states), stamped on Gazebo's clock. Each message goes
  out unchanged on `joint_states_out` (default /joint_states) but stamped with the wall
  clock when it arrived.
- Servo publishes its trajectory_msgs/JointTrajectory commands on `trajectory_in` (default
  /servo_node/joint_trajectory), stamped on wall time. Each goes out on `trajectory_out`
  (default /panda_arm_controller/joint_trajectory) with its header.stamp moved onto
  Gazebo's clock (stamp + Gazebo's now - wall now), so the trajectory controller starts
  it at the matching moment of its own clock. A zero stamp ("start now") stays zero.
  Commands that arrive before Gazebo's first /clock message are dropped.

Run it with use_sim_time true: the node's ROS clock is Gazebo's, its wall clock the
system's.
"""

import rclpy
from rclpy.clock import Clock, ClockType
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.time import Time
from sensor_msgs.msg import JointState
from trajectory_msgs.msg import JointTrajectory


def to_sim_ns(stamp_ns, sim_now_ns, wall_now_ns):
    """A wall-clock stamp on the simulation clock; 0 (start now) stays 0 and a stamp before
    the simulation's start becomes 0."""
    if stamp_ns == 0:
        return 0
    return max(0, stamp_ns + sim_now_ns - wall_now_ns)


class ArmClock(Node):

    def __init__(self):
        super().__init__('arm_clock')
        joint_states_in = self.declare_parameter(
            'joint_states_in', '/joint_state_broadcaster/joint_states').value
        joint_states_out = self.declare_parameter('joint_states_out', '/joint_states').value
        trajectory_in = self.declare_parameter(
            'trajectory_in', '/servo_node/joint_trajectory').value
        trajectory_out = self.declare_parameter(
            'trajectory_out', '/panda_arm_controller/joint_trajectory').value
        self._wall = Clock(clock_type=ClockType.SYSTEM_TIME)
        self._joint_states = self.create_publisher(JointState, joint_states_out, 10)
        self._trajectory = self.create_publisher(JointTrajectory, trajectory_out, 10)
        self.create_subscription(JointState, joint_states_in, self._on_joint_state, 10)
        self.create_subscription(JointTrajectory, trajectory_in, self._on_trajectory, 10)
        if not self.get_parameter('use_sim_time').value:
            self.get_logger().warning('use_sim_time is false: commands pass with their stamps')
        self.get_logger().info(
            f'{joint_states_in} -> {joint_states_out} on wall time; '
            f'{trajectory_in} -> {trajectory_out} on the simulation clock')

    def _on_joint_state(self, message):
        message.header.stamp = self._wall.now().to_msg()
        self._joint_states.publish(message)

    def _on_trajectory(self, message):
        sim_now = self.get_clock().now().nanoseconds
        if sim_now == 0:
            self.get_logger().warning(
                'no /clock yet: dropping a trajectory command', throttle_duration_sec=5.0)
            return
        stamp = Time.from_msg(message.header.stamp).nanoseconds
        message.header.stamp = Time(
            nanoseconds=to_sim_ns(stamp, sim_now, self._wall.now().nanoseconds)).to_msg()
        self._trajectory.publish(message)


def main():
    rclpy.init()
    node = ArmClock()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
