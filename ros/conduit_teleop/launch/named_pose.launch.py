"""conduit_named_pose: move a MoveIt arm to the SRDF group state Conduit's pose buttons name.

Run it next to move_group (which must publish /robot_description_semantic) and,
optionally, MoveIt Servo.
"""

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

ARGUMENTS = [
    ('planning_group', 'arm', 'MoveIt planning group whose SRDF group states the buttons name'),
    ('command_topic', '/conduit/teleop/named_pose',
     "std_msgs/String with a group state name; Conduit publishes /<namespace>/teleop/named_pose"),
    ('state_topic', '/conduit/teleop/named_pose_state',
     "Latched std_msgs/String: the group state the arm is at, '' while moving or elsewhere"),
    ('move_action', 'move_action', "move_group's MoveGroup action"),
    ('servo_pause_service', '/servo_node/pause_servo',
     "MoveIt Servo's std_srvs/SetBool pause service, called around each move"),
]


def generate_launch_description():
    return LaunchDescription([
        *(DeclareLaunchArgument(name, default_value=default, description=description)
          for name, default, description in ARGUMENTS),
        Node(
            package='conduit_teleop',
            executable='named_pose_node',
            name='conduit_named_pose',
            output='screen',
            parameters=[{name: LaunchConfiguration(name) for name, _, _ in ARGUMENTS}],
        ),
    ])
