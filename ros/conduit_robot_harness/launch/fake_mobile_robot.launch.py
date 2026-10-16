"""Fake mobile robot behind conduit_teleop (teleop_twist_joy + joy_watchdog)."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    teleop = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(
            get_package_share_directory('conduit_teleop'), 'launch', 'conduit_teleop.launch.py')),
        launch_arguments={
            'joy_topic': LaunchConfiguration('joy_topic'),
            'cmd_vel_topic': '/cmd_vel',
        }.items(),
    )
    robot = Node(
        package='conduit_robot_harness',
        executable='fake_mobile_robot',
        namespace='fake_robot',
        output='screen',
        parameters=[{'camera_rate': LaunchConfiguration('camera_rate')}],
    )
    return LaunchDescription([
        DeclareLaunchArgument('joy_topic', default_value='/joy'),
        DeclareLaunchArgument('camera_rate', default_value='30.0'),
        teleop,
        robot,
    ])
