"""conduit_named_pose: move a MoveIt arm to the SRDF group state Conduit's pose buttons name.

Run it next to move_group (which must publish /robot_description_semantic) and,
optionally, MoveIt Servo.
"""

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue

STRING_ARGUMENTS = [
    ('planning_group', 'arm', 'MoveIt planning group whose SRDF group states the buttons name'),
    ('command_topic', '/conduit/teleop/named_pose',
     "std_msgs/String with a group state name; Conduit publishes /<namespace>/teleop/named_pose"),
    ('state_topic', '/conduit/teleop/named_pose_state',
     "Latched std_msgs/String: the group state the arm is at, '' while moving or elsewhere"),
    ('move_action', 'move_action', "move_group's MoveGroup action"),
    ('servo_pause_service', '/servo_node/pause_servo',
     "MoveIt Servo's std_srvs/SetBool pause service, called around each move"),
]

# Typed explicitly, so that velocity_scaling:=1 is a float and planning_group:=1 a string.
FLOAT_ARGUMENTS = [
    ('velocity_scaling', '0.2', 'max_velocity_scaling_factor of each move, in (0, 1]'),
    ('acceleration_scaling', '0.2', 'max_acceleration_scaling_factor of each move, in (0, 1]'),
    ('tolerance', '0.01', 'How close (rad, or m) a joint must be to a group state value to count as at it'),
    ('planning_time', '5.0', 'Seconds the planner may take'),
    ('service_timeout', '1.0', 'Seconds to wait for the Servo pause service, its answer, and the MoveGroup action'),
    ('max_move_duration', '60.0', 'Seconds a move may execute after planning before the node gives it up'),
]


def generate_launch_description():
    parameters = {name: ParameterValue(LaunchConfiguration(name), value_type=str)
                  for name, _, _ in STRING_ARGUMENTS}
    parameters.update({name: ParameterValue(LaunchConfiguration(name), value_type=float)
                       for name, _, _ in FLOAT_ARGUMENTS})
    return LaunchDescription([
        *(DeclareLaunchArgument(name, default_value=default, description=description)
          for name, default, description in STRING_ARGUMENTS + FLOAT_ARGUMENTS),
        Node(
            package='conduit_teleop',
            executable='named_pose_node',
            name='conduit_named_pose',
            output='screen',
            parameters=[parameters],
        ),
    ])
