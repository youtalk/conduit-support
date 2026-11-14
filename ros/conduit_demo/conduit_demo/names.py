"""The names the Conduit Robots demo uses on a ROS 2 graph, and the rule for a conflict.

Before the demo joins a PC's graph (docker/demo/entrypoint.sh join), check_conflicts
reads that graph and compares it with these names. A name the PC already uses means the
demo would disturb the PC's own robot (a second publisher on its topics, its frames in a
merged TF tree, a second /clock, the phone's Joy driving it), so the demo does not start.

The lists are what standalone runs of the demo have on their graphs, as `check_conflicts
--list` prints it against each run: every topic, action and TF frame (seen on /tf and
/tf_static), and every service, except
- SHARED: /tf and /tf_static carry both robots' frames (the frames themselves count),
  /diagnostics is shared by convention, and every graph has /rosout and
  /parameter_events;
- the services each node has under its own name (NODE_SERVICES: parameters, type
  description, logger levels), which say nothing about the names in use.

Topics, actions and frames are listed by name. A service under a namespace is listed by
the namespace's first part, the node or namespace that offers it (DEMO_SERVICE_PREFIXES:
/panda_ stands for both Panda controllers, /move_group/ for move_group's own), and a
topic or an action under one of those prefixes counts too; the services at the top level
(MoveIt's capabilities, Nav2's /is_path_valid, the waypoint follower's /fromLL client) are
listed by name (DEMO_SERVICES). Listed from the Jazzy, Kilted and Lyrical images on
2026-11-11; the lists are their union, so a name the demo has on one distribution only (Nav2's
lifecycle managers, for example: lifecycle_manager_navigation and the map server's before
Lyrical, lifecycle_manager_nav2 on Lyrical) counts on every distribution.
"""

from collections.abc import Iterable

SHARED = frozenset({'/tf', '/tf_static', '/diagnostics', '/rosout', '/parameter_events'})

# The last name of the services every node has: rclcpp and rclpy create them under the
# node's own name (`~/get_parameters` and so on).
NODE_SERVICES = frozenset({
    'describe_parameters', 'get_parameter_types', 'get_parameters', 'list_parameters',
    'set_parameters', 'set_parameters_atomically', 'get_type_description',
    'get_logger_levels', 'set_logger_levels',
})

DEMO_TOPICS = frozenset({
    '/attached_collision_object',
    '/battery_state',
    '/behavior_server/transition_event',
    '/behavior_tree_log',
    '/bond',
    '/bt_navigator/transition_event',
    '/bt_navigator_navigate_through_poses_rclcpp_node/transition_event',
    '/bt_navigator_navigate_to_pose_rclcpp_node/transition_event',
    '/camera/image_raw',
    '/clock',
    '/cmd_vel',
    '/cmd_vel_nav',
    '/cmd_vel_smoothed',
    '/cmd_vel_teleop',
    '/collision_monitor/collision_points_marker',
    '/collision_monitor/transition_event',
    '/collision_monitor/triggering_points',
    '/collision_monitor_state',
    '/collision_object',
    '/controller_manager/activity',
    '/controller_manager/introspection_data/full',
    '/controller_manager/introspection_data/names',
    '/controller_manager/introspection_data/values',
    '/controller_manager/statistics/full',
    '/controller_manager/statistics/names',
    '/controller_manager/statistics/values',
    '/controller_selector',
    '/controller_server/candidate_trajectories',
    '/controller_server/critics_stats',
    '/controller_server/optimal_path',
    '/controller_server/optimal_trajectory',
    '/controller_server/transition_event',
    '/detected_dock_pose',
    '/display_contacts',
    '/display_planned_path',
    '/dock_pose',
    '/docking_server/transition_event',
    '/docking_trajectory',
    '/filtered_dock_pose',
    '/filtered_dynamic_pose',
    '/following_server/transition_event',
    '/global_costmap/costmap',
    '/global_costmap/costmap_raw',
    '/global_costmap/costmap_raw_updates',
    '/global_costmap/costmap_updates',
    '/global_costmap/footprint',
    '/global_costmap/global_costmap/transition_event',
    '/global_costmap/obstacle_layer',
    '/global_costmap/obstacle_layer_raw',
    '/global_costmap/obstacle_layer_raw_updates',
    '/global_costmap/obstacle_layer_updates',
    '/global_costmap/published_footprint',
    '/global_costmap/static_layer',
    '/global_costmap/static_layer_raw',
    '/global_costmap/static_layer_raw_updates',
    '/global_costmap/static_layer_updates',
    '/goal_checker_selector',
    '/goal_pose',
    '/head_camera/camera_info',
    '/head_camera/image_raw',
    '/initialpose',
    '/joint_state_broadcaster/dynamic_joint_states',
    '/joint_state_broadcaster/joint_states',
    '/joint_state_broadcaster/transition_event',
    '/joint_states',
    '/joy',
    '/keepout_costmap_filter_info',
    '/lifecycle_manager_nav2/managed_nodes_activated',
    '/local_costmap/clearing_endpoints',
    '/local_costmap/costmap',
    '/local_costmap/costmap_raw',
    '/local_costmap/costmap_raw_updates',
    '/local_costmap/costmap_updates',
    '/local_costmap/footprint',
    '/local_costmap/local_costmap/transition_event',
    '/local_costmap/published_footprint',
    '/local_costmap/voxel_grid',
    '/local_costmap/voxel_layer',
    '/local_costmap/voxel_layer_raw',
    '/local_costmap/voxel_layer_raw_updates',
    '/local_costmap/voxel_layer_updates',
    '/loopback_simulator/transition_event',
    '/map',
    '/map_server/transition_event',
    '/monitored_planning_scene',
    '/odom',
    '/optimal_trajectory',
    '/panda_arm_controller/controller_state',
    '/panda_arm_controller/joint_trajectory',
    '/panda_arm_controller/speed_scaling_input',
    '/panda_arm_controller/transition_event',
    '/panda_hand_controller/transition_event',
    '/path_handler_selector',
    '/pipeline_state',
    '/plan',
    '/plan_smoothed',
    '/planner_selector',
    '/planner_server/transition_event',
    '/planning_scene',
    '/planning_scene_world',
    '/preempt_teleop',
    '/progress_checker_selector',
    '/robot_description',
    '/robot_description_semantic',
    '/route',
    '/route_graph',
    '/route_server/transition_event',
    '/scan',
    '/servo_node/delta_joint_cmds',
    '/servo_node/delta_twist_cmds',
    '/servo_node/joint_trajectory',
    '/servo_node/pose_target_cmds',
    '/servo_node/publish_planning_scene',
    '/servo_node/status',
    '/smoother_server/transition_event',
    '/speed_costmap_filter_info',
    '/speed_limit',
    '/staging_pose',
    '/tracking_feedback',
    '/trajectories',
    '/trajectory_execution_event',
    '/transformed_global_plan',
    '/turtlebot3/joint_states',
    '/turtlebot3/robot_description',
    '/velocity_smoother/transition_event',
    '/waypoint_follower/transition_event',
    '/wrist_camera/camera_info',
    '/wrist_camera/image_raw',
})

DEMO_ACTIONS = frozenset({
    '/assisted_teleop',
    '/backup',
    '/compute_and_track_route',
    '/compute_path_through_poses',
    '/compute_path_to_pose',
    '/compute_route',
    '/dock_robot',
    '/drive_on_heading',
    '/execute_trajectory',
    '/follow_gps_waypoints',
    '/follow_object',
    '/follow_path',
    '/follow_waypoints',
    '/move_action',
    '/navigate_through_poses',
    '/navigate_to_pose',
    '/panda_arm_controller/follow_joint_trajectory',
    '/panda_hand_controller/gripper_cmd',
    '/panda_hand_controller/parallel_gripper_cmd',
    '/smooth_path',
    '/spin',
    '/undock_robot',
    '/wait',
})

DEMO_SERVICE_PREFIXES = (
    '/behavior_server/',
    '/bt_navigator/',
    '/bt_navigator_navigate_through_poses_rclcpp_node/',
    '/bt_navigator_navigate_to_pose_rclcpp_node/',
    '/collision_monitor/',
    '/controller_manager/',
    '/controller_server/',
    '/docking_server/',
    '/following_server/',
    '/global_costmap/',
    '/lifecycle_manager_map_server/',
    '/lifecycle_manager_nav2/',
    '/lifecycle_manager_navigation/',
    '/local_costmap/',
    '/loopback_simulator/',
    '/map_server/',
    '/move_group/',
    '/nav2_container/',
    '/panda_',
    '/planner_server/',
    '/route_server/',
    '/servo_node/',
    '/smoother_server/',
    '/velocity_smoother/',
    '/waypoint_follower/',
)

DEMO_SERVICES = frozenset({
    '/apply_planning_scene',
    '/check_state_validity',
    '/clear_octomap',
    '/compute_cartesian_path',
    '/compute_fk',
    '/compute_ik',
    '/fromLL',
    '/get_planner_params',
    '/get_planning_scene',
    '/get_urdf',
    '/is_path_valid',
    '/load_geometry_from_file',
    '/load_map',
    '/plan_kinematic_path',
    '/query_planner_interface',
    '/save_geometry_to_file',
    '/save_map',
    '/set_planner_params',
})

DEMO_FRAMES = frozenset({
    'base_footprint',
    'base_link',
    'base_scan',
    'camera_depth_frame',
    'camera_depth_optical_frame',
    'camera_link',
    'camera_rgb_frame',
    'camera_rgb_optical_frame',
    'caster_back_left_link',
    'caster_back_right_link',
    'head_camera_link',
    'head_camera_optical_frame',
    'imu_link',
    'map',
    'odom',
    'panda_hand',
    'panda_leftfinger',
    'panda_link0',
    'panda_link1',
    'panda_link2',
    'panda_link3',
    'panda_link4',
    'panda_link5',
    'panda_link6',
    'panda_link7',
    'panda_link8',
    'panda_rightfinger',
    'world',
    'wrist_camera_link',
    'wrist_camera_optical_frame',
})

# Actions show on the graph as hidden topics and services under `<action>/_action/`;
# service introspection as a hidden topic `<service>/_service_event`.
_ACTION_INFIX = '/_action/'
_SERVICE_EVENT_SUFFIX = '/_service_event'


def is_node_service(name: str) -> bool:
    """True for a service every node has under its own name (`~/get_parameters`, ...)."""
    return name.rsplit('/', 1)[-1] in NODE_SERVICES


def split_graph(topic_names: Iterable[str],
                service_names: Iterable[str]) -> tuple[list[str], list[str], list[str]]:
    """(topics, services, actions), each sorted and unique, from a graph's topic and service
    names: an action's hidden topics and services become the action's name, a service's
    introspection topic is dropped."""
    topics, services, actions = set(), set(), set()
    for name in topic_names:
        if _ACTION_INFIX in name:
            actions.add(name.split(_ACTION_INFIX, 1)[0])
        elif not name.endswith(_SERVICE_EVENT_SUFFIX):
            topics.add(name)
    for name in service_names:
        if _ACTION_INFIX in name:
            actions.add(name.split(_ACTION_INFIX, 1)[0])
        else:
            services.add(name)
    return sorted(topics), sorted(services), sorted(actions)


def _under_demo_prefix(name: str) -> bool:
    return name.startswith(DEMO_SERVICE_PREFIXES)


def find_conflicts(topics: Iterable[str], services: Iterable[str], actions: Iterable[str],
                   frames: Iterable[str]) -> list[str]:
    """The names of a graph that the demo uses too, sorted and unique.

    A topic conflicts by exact name (DEMO_TOPICS) or prefix (DEMO_SERVICE_PREFIXES), a
    service by exact name (DEMO_SERVICES) or prefix, an action by exact name
    (DEMO_ACTIONS) or prefix, a TF frame by exact name (DEMO_FRAMES; a leading slash is
    ignored). SHARED names and the services every node has never conflict.
    """
    conflicts = set()
    for name in topics:
        if name not in SHARED and (name in DEMO_TOPICS or _under_demo_prefix(name)):
            conflicts.add(name)
    for name in services:
        if not is_node_service(name) and (name in DEMO_SERVICES or _under_demo_prefix(name)):
            conflicts.add(name)
    for name in actions:
        if name not in SHARED and (name in DEMO_ACTIONS or _under_demo_prefix(name)):
            conflicts.add(name)
    for frame in frames:
        frame = frame.lstrip('/')
        if frame in DEMO_FRAMES:
            conflicts.add(frame)
    return sorted(conflicts)
