"""The demo's names and the conflict rule, tested without ROS."""

from conduit_demo.names import (DEMO_ACTIONS, DEMO_FRAMES, DEMO_SERVICES, DEMO_SERVICE_PREFIXES,
                                DEMO_TOPICS, SHARED, find_conflicts, split_graph)


def test_empty_graph_has_no_conflicts():
    assert find_conflicts([], [], [], []) == []


def test_map_topic_conflicts():
    assert find_conflicts(['/map', '/my_robot/scan'], [], [], []) == ['/map']


def test_shared_topics_never_conflict():
    shared = ['/tf', '/tf_static', '/diagnostics', '/rosout', '/parameter_events']
    assert SHARED == frozenset(shared)
    assert find_conflicts(shared, [], [], []) == []


def test_servo_service_prefix_conflicts():
    assert '/servo_node/' in DEMO_SERVICE_PREFIXES
    services = ['/servo_node/switch_command_type', '/my_robot/reset']
    assert find_conflicts([], services, [], []) == ['/servo_node/switch_command_type']


def test_navigate_to_pose_action_conflicts():
    assert find_conflicts([], [], ['/navigate_to_pose', '/my_robot/dock'], []) == [
        '/navigate_to_pose']


def test_base_link_frame_conflicts():
    assert find_conflicts([], [], [], ['base_link', 'my_robot_base']) == ['base_link']


def test_conflicts_are_sorted_and_unique():
    conflicts = find_conflicts(
        ['/scan', '/map', '/map'],
        ['/servo_node/pause_servo', '/servo_node/pause_servo'],
        ['/navigate_to_pose', '/navigate_to_pose'],
        ['odom', 'map', 'odom'])
    assert conflicts == [
        '/map', '/navigate_to_pose', '/scan', '/servo_node/pause_servo', 'map', 'odom']


def test_the_names_the_demo_uses_conflict():
    # The spec's names table and what the demo publishes besides (/initialpose, the
    # broadcaster's and Servo's raw outputs, the parallel gripper action, Nav2's cmd_vel).
    topics = [
        '/map', '/odom', '/scan', '/battery_state', '/camera/image_raw', '/joy', '/cmd_vel',
        '/initialpose', '/turtlebot3/robot_description', '/turtlebot3/joint_states',
        '/robot_description', '/robot_description_semantic', '/joint_states',
        '/joint_state_broadcaster/joint_states', '/servo_node/joint_trajectory',
        '/panda_arm_controller/joint_trajectory', '/wrist_camera/image_raw',
        '/wrist_camera/camera_info', '/clock',
    ]
    services = ['/controller_manager/list_controllers', '/servo_node/switch_command_type']
    actions = [
        '/navigate_to_pose', '/move_action', '/panda_hand_controller/gripper_cmd',
        '/panda_hand_controller/parallel_gripper_cmd',
        '/panda_arm_controller/follow_joint_trajectory',
    ]
    frames = [
        'map', 'odom', 'base_footprint', 'base_link', 'camera_link', 'world', 'panda_link0',
        'panda_hand', 'panda_leftfinger', 'wrist_camera_link', 'wrist_camera_optical_frame',
    ]
    assert find_conflicts(topics, services, actions, frames) == sorted(
        topics + services + actions + frames)


def test_exact_names_are_listed_without_shared_ones():
    assert not (DEMO_TOPICS | DEMO_ACTIONS) & SHARED
    assert {'/map', '/clock', '/initialpose'} <= DEMO_TOPICS
    assert {'/navigate_to_pose', '/move_action'} <= DEMO_ACTIONS
    assert {'base_link', 'world', 'wrist_camera_optical_frame'} <= DEMO_FRAMES
    assert not any(frame.startswith('/') for frame in DEMO_FRAMES)


def test_top_level_services_conflict_by_name():
    assert {'/compute_ik', '/is_path_valid'} <= DEMO_SERVICES
    services = ['/compute_ik', '/compute_ik_fast', '/is_path_valid']
    assert find_conflicts([], services, [], []) == ['/compute_ik', '/is_path_valid']


def test_node_services_never_conflict():
    # The services every node has, named after the node, say nothing about the names in use.
    services = [
        '/servo_node/describe_parameters', '/servo_node/get_parameters',
        '/controller_manager/set_parameters', '/panda_arm_controller/get_type_description',
        '/move_group/list_parameters',
    ]
    assert find_conflicts([], services, [], []) == []


def test_split_graph_finds_actions_from_their_hidden_names():
    topics, services, actions = split_graph(
        ['/map', '/navigate_to_pose/_action/feedback', '/navigate_to_pose/_action/status',
         '/my_robot/dock/_action/status', '/map_server/map/_service_event'],
        ['/navigate_to_pose/_action/send_goal', '/navigate_to_pose/_action/cancel_goal',
         '/navigate_to_pose/_action/get_result', '/map_server/map'])
    assert topics == ['/map']
    assert services == ['/map_server/map']
    assert actions == ['/my_robot/dock', '/navigate_to_pose']
