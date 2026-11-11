"""TurtleBot3 on Nav2's loopback simulator, with a camera drawn from the map.

Starts what nav2_bringup's tb3_loopback_simulation_launch.py starts, without RViz,
changed for the Conduit Robots demo:

- Everything runs on wall time (use_sim_time false, set on every node: the demo arm
  brings Gazebo's /clock into the same graph) and the loopback simulator publishes no
  /clock, so Gazebo's stays the only one.
- robot_state_publisher, named turtlebot3_state_publisher, has its robot_description
  and joint_states renamed to /turtlebot3/robot_description and
  /turtlebot3/joint_states, because robot_state_publisher, /robot_description and
  /joint_states belong to the demo arm.
- initial_pose places the robot at tb3_sandbox's spawn point: the loopback simulator
  publishes no odometry, scan or transforms until it has an initial pose.
- map_camera (/camera/image_raw), battery (/battery_state) and teleop_twist_joy
  (/joy -> /cmd_vel, with Conduit's Joy layout) are added. The model's camera_link
  is the map camera's frame.
"""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch_ros.actions import LifecycleNode, Node
from launch_ros.descriptions import ParameterFile
from nav2_common.launch import RewrittenYaml

# tb3_sandbox's spawn point, as in nav2_bringup's Gazebo simulation.
START_X = -2.0
START_Y = -0.5
START_YAW = 0.0

# Nav2 takes geometry_msgs/TwistStamped on cmd_vel from Kilted on, Twist before.
STAMPED_CMD_VEL = os.environ.get('ROS_DISTRO', '') not in ('humble', 'jazzy')


def generate_launch_description():
    bringup_dir = get_package_share_directory('nav2_bringup')
    sim_dir = get_package_share_directory('nav2_minimal_tb3_sim')
    teleop_dir = get_package_share_directory('conduit_teleop')
    params_file = os.path.join(bringup_dir, 'params', 'nav2_params.yaml')
    with open(os.path.join(sim_dir, 'urdf', 'turtlebot3_waffle.urdf')) as urdf:
        robot_description = urdf.read()

    robot_state_publisher = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        name='turtlebot3_state_publisher',
        output='screen',
        parameters=[{'use_sim_time': False, 'robot_description': robot_description}],
        remappings=[
            ('robot_description', '/turtlebot3/robot_description'),
            ('joint_states', '/turtlebot3/joint_states'),
        ],
    )

    loopback_simulator = LifecycleNode(
        package='nav2_loopback_sim',
        executable='loopback_simulator',
        name='loopback_simulator',
        namespace='',
        output='screen',
        autostart=True,
        parameters=[
            ParameterFile(
                RewrittenYaml(
                    source_file=params_file, root_key='', param_rewrites={},
                    convert_types=True),
                allow_substs=True),
            {'scan_frame_id': 'base_scan', 'use_sim_time': False, 'publish_clock': False},
        ],
    )

    nav2 = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(bringup_dir, 'launch', 'bringup_launch.py')),
        launch_arguments={
            'map': os.path.join(bringup_dir, 'maps', 'tb3_sandbox.yaml'),
            'graph': os.path.join(bringup_dir, 'graphs', 'turtlebot3_graph.geojson'),
            'params_file': params_file,
            'use_sim_time': 'False',
            'autostart': 'True',
            'use_composition': 'True',
            'use_localization': 'False',
            'serve_static_map': 'True',
            'use_keepout_zones': 'False',
            'use_speed_zones': 'False',
            'container_name': 'nav2_container',
        }.items(),
    )

    initial_pose = Node(
        package='conduit_demo',
        executable='initial_pose',
        name='initial_pose',
        output='screen',
        parameters=[{'x': START_X, 'y': START_Y, 'yaw': START_YAW, 'use_sim_time': False}],
    )

    map_camera = Node(
        package='conduit_demo',
        executable='map_camera',
        name='map_camera',
        output='screen',
        parameters=[{'rate_hz': 10.0, 'width': 320, 'height': 240, 'use_sim_time': False}],
    )

    battery = Node(
        package='conduit_demo',
        executable='battery',
        name='battery',
        output='screen',
        parameters=[{'use_sim_time': False}],
    )

    teleop = Node(
        package='teleop_twist_joy',
        executable='teleop_node',
        name='teleop_twist_joy_node',
        output='screen',
        parameters=[
            os.path.join(teleop_dir, 'config', 'teleop_twist_joy.yaml'),
            {'publish_stamped_twist': STAMPED_CMD_VEL, 'frame': 'base_link', 'use_sim_time': False},
        ],
        remappings=[('joy', '/joy'), ('cmd_vel', '/cmd_vel')],
    )

    return LaunchDescription([
        robot_state_publisher,
        loopback_simulator,
        nav2,
        initial_pose,
        map_camera,
        battery,
        teleop,
    ])
