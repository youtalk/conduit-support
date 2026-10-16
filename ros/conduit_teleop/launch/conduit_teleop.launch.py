"""teleop_twist_joy with Conduit's Joy layout, followed by joy_watchdog."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    joy_topic = LaunchConfiguration('joy_topic')
    cmd_vel_topic = LaunchConfiguration('cmd_vel_topic')
    params_file = LaunchConfiguration('params_file')
    default_params_file = os.path.join(
        get_package_share_directory('conduit_teleop'), 'config', 'teleop_twist_joy.yaml')

    return LaunchDescription([
        DeclareLaunchArgument(
            'joy_topic', default_value='/joy',
            description="sensor_msgs/Joy input; Conduit's Game Controller sensor publishes "
                        '/<namespace>/joy (/conduit/joy by default)'),
        DeclareLaunchArgument(
            'cmd_vel_topic', default_value='/cmd_vel',
            description='geometry_msgs/Twist output the robot listens to'),
        DeclareLaunchArgument(
            'params_file', default_value=default_params_file,
            description='teleop_twist_joy parameter file (key teleop_twist_joy_node). It replaces '
                        "this package's config/teleop_twist_joy.yaml, so copy that file and change "
                        'the speeds'),
        Node(
            package='teleop_twist_joy',
            executable='teleop_node',
            name='teleop_twist_joy_node',
            parameters=[params_file],
            remappings=[('joy', joy_topic), ('cmd_vel', 'cmd_vel_in')],
        ),
        Node(
            package='conduit_teleop',
            executable='joy_watchdog',
            name='joy_watchdog',
            remappings=[('joy', joy_topic), ('cmd_vel', cmd_vel_topic)],
        ),
    ])
