"""A Panda in Gazebo with a wrist camera, MoveIt Servo and move_group.

The arm of the Conduit Robots demo, with a real Panda's names (and those of the
mock-hardware Servo harness), so a Conduit arm profile fills itself in:

- Gazebo server, headless, with worlds/demo_table.sdf (a table, three cubes, a tray); the
  Panda from urdf/panda_gz.urdf.xacro spawned from /robot_description;
- gz_ros2_control with joint_state_broadcaster, panda_arm_controller and
  panda_hand_controller (config/panda_gz_controllers.yaml); gripper_command serves
  control_msgs/action/GripperCommand on /panda_hand_controller/gripper_cmd in front of the
  hand controller's ParallelGripperCommand server;
- ros_gz_bridge (config/gz_bridge.yaml): /clock, /wrist_camera/image_raw and
  /wrist_camera/camera_info;
- robot_state_publisher (/robot_description, /tf, /tf_static with world -> panda_link0);
- MoveIt Servo (servo_node) with moveit_servo's panda_simulated_config.yaml and
  conduit_teleop's config/servo_overlay.yaml last, switched to TWIST commands by
  servo_twist_mode once it is up;
- move_group with moveit_resources_panda's SRDF (published on
  /robot_description_semantic; its panda_arm states are Conduit's pose menu), OMPL, and
  execution on panda_arm_controller (/move_action).

Arguments:
  gpu           false (default): the light setting, camera 320 x 240 at 10 Hz, low-poly
                visuals, software rendering; true: 640 x 480 at 15 Hz, full visuals.
  use_sim_time  true (default): the clock of every node below. Gazebo publishes the
                graph's only /clock.
"""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import (DeclareLaunchArgument, IncludeLaunchDescription, OpaqueFunction,
                            RegisterEventHandler)
from launch.event_handlers import OnProcessExit
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_param_builder import ParameterBuilder
from launch_ros.actions import Node
from moveit_configs_utils import MoveItConfigsBuilder

WORLD = 'demo_table'
HAND_ACTION = '/panda_hand_controller/gripper_cmd'
HAND_CONTROLLER_ACTION = '/panda_hand_controller/parallel_gripper_cmd'


def _flag(context, name):
    return LaunchConfiguration(name).perform(context).strip().lower() in ('true', '1', 'yes', 'on')


def launch_setup(context):
    gpu = _flag(context, 'gpu')
    # The clock, in one place: every node of the arm gets use_sim_time from here (the
    # controller manager inside Gazebo always runs on Gazebo's clock).
    sim_time = {'use_sim_time': _flag(context, 'use_sim_time')}

    share = get_package_share_directory('conduit_demo')
    world = os.path.join(share, 'worlds', f'{WORLD}.sdf')
    controllers = os.path.join(share, 'config', 'panda_gz_controllers.yaml')
    bridge_config = os.path.join(share, 'config', 'gz_bridge.yaml')
    overlay = os.path.join(
        get_package_share_directory('conduit_teleop'), 'config', 'servo_overlay.yaml')

    moveit_config = (
        MoveItConfigsBuilder('moveit_resources_panda')
        .robot_description(
            file_path=os.path.join(share, 'urdf', 'panda_gz.urdf.xacro'),
            mappings={'gpu': 'true' if gpu else 'false'})
        .robot_description_semantic(file_path='config/panda.srdf')
        .joint_limits(file_path='config/hard_joint_limits.yaml')
        .planning_scene_monitor(
            publish_robot_description=False, publish_robot_description_semantic=True)
        .trajectory_execution(file_path='config/moveit_controllers.yaml')
        .planning_pipelines(pipelines=['ompl'])
        .to_moveit_configs()
    )
    servo_params = {
        'moveit_servo':
            ParameterBuilder('moveit_servo').yaml('config/panda_simulated_config.yaml').to_dict()
    }

    gazebo = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(
            get_package_share_directory('ros_gz_sim'), 'launch', 'gz_sim.launch.py')),
        launch_arguments={
            'gz_args': f'-s -r -v 2 --headless-rendering {world}',
            'on_exit_shutdown': 'true',
        }.items(),
    )

    robot_state_publisher = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        name='robot_state_publisher',
        output='screen',
        parameters=[moveit_config.robot_description, sim_time],
    )

    spawn = Node(
        package='ros_gz_sim',
        executable='create',
        name='spawn_panda',
        output='screen',
        arguments=['-world', WORLD, '-topic', '/robot_description', '-name', 'panda',
                   '-allow_renaming', 'false'],
        parameters=[sim_time],
    )

    bridge = Node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        name='ros_gz_bridge',
        output='screen',
        parameters=[{'config_file': bridge_config}, sim_time],
    )

    def spawner(controller, *extra):
        return Node(
            package='controller_manager',
            executable='spawner',
            arguments=[controller, '--controller-manager', '/controller_manager',
                       '--controller-manager-timeout', '120', '--param-file', controllers,
                       *extra],
            parameters=[sim_time],
        )

    joint_state_broadcaster = spawner('joint_state_broadcaster')
    arm_controller = spawner('panda_arm_controller')
    # The hand controller's ParallelGripperCommand server moves aside for gripper_command.
    hand_controller = spawner(
        'panda_hand_controller',
        '--controller-ros-args', f'-r {HAND_ACTION}:={HAND_CONTROLLER_ACTION}')

    gripper_command = Node(
        package='conduit_demo',
        executable='gripper_command',
        name='gripper_command',
        output='screen',
        parameters=[{'action_name': HAND_ACTION, 'controller_action': HAND_CONTROLLER_ACTION,
                     'joint': 'panda_finger_joint1'}, sim_time],
    )

    servo = Node(
        package='moveit_servo',
        executable='servo_node',
        name='servo_node',
        output='screen',
        parameters=[
            servo_params,
            {'update_period': 0.01, 'planning_group_name': 'panda_arm'},
            moveit_config.robot_description,
            moveit_config.robot_description_semantic,
            moveit_config.robot_description_kinematics,
            moveit_config.joint_limits,
            sim_time,
            overlay,
        ],
    )

    servo_twist_mode = Node(
        package='conduit_demo',
        executable='servo_twist_mode',
        name='servo_twist_mode',
        output='screen',
        parameters=[sim_time],
    )

    move_group = Node(
        package='moveit_ros_move_group',
        executable='move_group',
        output='screen',
        parameters=[moveit_config.to_dict(), sim_time],
    )

    return [
        gazebo,
        robot_state_publisher,
        bridge,
        spawn,
        move_group,
        gripper_command,
        # The controller manager exists once the Panda is in Gazebo.
        RegisterEventHandler(OnProcessExit(
            target_action=spawn,
            on_exit=[joint_state_broadcaster, arm_controller, hand_controller])),
        # Servo waits a few seconds for joint states at start, so it starts after them.
        RegisterEventHandler(OnProcessExit(
            target_action=joint_state_broadcaster,
            on_exit=[servo, servo_twist_mode])),
    ]


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument(
            'gpu', default_value='false',
            description='true: camera 640 x 480 at 15 Hz and full visuals (needs a GPU)'),
        DeclareLaunchArgument(
            'use_sim_time', default_value='true',
            description="The arm's nodes run on Gazebo's /clock"),
        OpaqueFunction(function=launch_setup),
    ])
