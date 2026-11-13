"""Both robots of the Conduit Robots demo: the TurtleBot3 and the Panda.

The one launch the demo image's modes start (docker/demo/entrypoint.sh standalone, join
and all): mobile.launch.py (the TurtleBot3 on Nav2's loopback simulator with the map
camera) and arm.launch.py (the Panda in Gazebo with the wrist camera, Servo and
move_group).

Each runs in its own scope, so the launch configurations one sets do not reach the other:
Nav2's bringup sets use_composition and container_name, which ros_gz_sim's
gz_sim.launch.py reads too. Each node's use_sim_time is set where the node is (wall time
for the TurtleBot3, the arm's two clocks as arm.launch.py describes), so there is no
global use_sim_time here.

Arguments:
  gpu   for arm.launch.py: false (default) the light setting, true 640 x 480 at 15 Hz
        with full visuals
"""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, GroupAction, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration


def _scoped_include(launch_file, arguments=None):
    launch_dir = os.path.join(get_package_share_directory('conduit_demo'), 'launch')
    return GroupAction(
        [IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(launch_dir, launch_file)),
            launch_arguments=(arguments or {}).items())],
        scoped=True)


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument(
            'gpu', default_value='false',
            description='true: the wrist camera at 640 x 480 and 15 Hz, full visuals '
                        '(needs a GPU)'),
        _scoped_include('mobile.launch.py'),
        _scoped_include('arm.launch.py', {'gpu': LaunchConfiguration('gpu')}),
    ])
