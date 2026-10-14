"""MoveIt Servo Panda on mock hardware with Conduit's Servo overlay and a gripper server.

Follows moveit_servo's Jazzy demo_ros_api.launch.py (ros2_control mock hardware,
panda_arm_controller, standalone servo_node), without RViz unless use_rviz:=true.
The overlay (conduit_teleop's config/servo_overlay.yaml, the same file users
load on real robots) is the last parameter source, so its values win.
"""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration
from launch_param_builder import ParameterBuilder
from launch_ros.actions import Node
from moveit_configs_utils import MoveItConfigsBuilder


def generate_launch_description():
    moveit_config = (
        MoveItConfigsBuilder('moveit_resources_panda')
        .robot_description(file_path='config/panda.urdf.xacro')
        .joint_limits(file_path='config/hard_joint_limits.yaml')
        .to_moveit_configs()
    )
    servo_params = {
        'moveit_servo': ParameterBuilder('moveit_servo').yaml('config/panda_simulated_config.yaml').to_dict()
    }
    overlay = os.path.join(get_package_share_directory('conduit_teleop'), 'config', 'servo_overlay.yaml')
    ros2_controllers = os.path.join(
        get_package_share_directory('moveit_resources_panda_moveit_config'), 'config', 'ros2_controllers.yaml')
    rviz_config = os.path.join(get_package_share_directory('moveit_servo'), 'config', 'demo_rviz_config_ros.rviz')

    return LaunchDescription([
        DeclareLaunchArgument('use_rviz', default_value='false'),
        Node(
            package='controller_manager',
            executable='ros2_control_node',
            parameters=[ros2_controllers],
            remappings=[('/controller_manager/robot_description', '/robot_description')],
            output='screen',
        ),
        Node(
            package='controller_manager',
            executable='spawner',
            arguments=['joint_state_broadcaster', '--controller-manager-timeout', '300',
                       '--controller-manager', '/controller_manager'],
        ),
        Node(
            package='controller_manager',
            executable='spawner',
            arguments=['panda_arm_controller', '-c', '/controller_manager'],
        ),
        Node(
            package='robot_state_publisher',
            executable='robot_state_publisher',
            parameters=[moveit_config.robot_description],
        ),
        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            arguments=['--frame-id', 'world', '--child-frame-id', 'panda_link0'],
        ),
        Node(
            package='moveit_servo',
            executable='servo_node',
            name='servo_node',
            output='screen',
            parameters=[
                servo_params,
                {'update_period': 0.01},
                {'planning_group_name': 'panda_arm'},
                moveit_config.robot_description,
                moveit_config.robot_description_semantic,
                moveit_config.robot_description_kinematics,
                moveit_config.joint_limits,
                overlay,
            ],
        ),
        Node(package='conduit_robot_harness', executable='conduit_gripper_server', output='screen'),
        Node(
            package='rviz2',
            executable='rviz2',
            arguments=['-d', rviz_config],
            parameters=[moveit_config.robot_description, moveit_config.robot_description_semantic],
            condition=IfCondition(LaunchConfiguration('use_rviz')),
        ),
    ])
