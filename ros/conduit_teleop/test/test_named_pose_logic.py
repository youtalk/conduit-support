"""named_pose_node's decision logic, tested without ROS."""

import pytest

from conduit_teleop.named_pose_logic import (
    CANCEL_THEN_MOVE, DEFAULT_TOLERANCE, MOVE, REJECT, at_state, current_state, decide_command,
    parse_group_states, parse_parameters)

# The shape of the Maker Arm's SRDF: an arm group with ready / home and a gripper group
# with open / closed.
MAKER_ARM_SRDF = """<?xml version="1.0" encoding="UTF-8"?>
<robot name="maker_arm">
  <group name="arm">
    <chain base_link="base_link" tip_link="tool_link"/>
  </group>
  <group name="gripper">
    <joint name="gripper_joint"/>
  </group>
  <group_state name="ready" group="arm">
    <joint name="joint1" value="0"/>
    <joint name="joint2" value="-0.785"/>
    <joint name="joint3" value="1.571"/>
    <joint name="joint4" value="0.785"/>
  </group_state>
  <group_state name="home" group="arm">
    <joint name="joint1" value="0"/>
    <joint name="joint2" value="0"/>
    <joint name="joint3" value="0"/>
    <joint name="joint4" value="0"/>
  </group_state>
  <group_state name="open" group="gripper">
    <joint name="gripper_joint" value="0.02"/>
  </group_state>
  <group_state name="closed" group="gripper">
    <joint name="gripper_joint" value="0"/>
  </group_state>
  <end_effector name="hand" parent_link="tool_link" group="gripper"/>
  <disable_collisions link1="base_link" link2="link1" reason="Adjacent"/>
</robot>
"""

READY = {'joint1': 0.0, 'joint2': -0.785, 'joint3': 1.571, 'joint4': 0.785}
HOME = {'joint1': 0.0, 'joint2': 0.0, 'joint3': 0.0, 'joint4': 0.0}


def arm_states():
    states, error = parse_group_states(MAKER_ARM_SRDF)
    assert error == ''
    return states['arm']


# --- parse_group_states ---

def test_parses_the_maker_arm_srdf():
    states, error = parse_group_states(MAKER_ARM_SRDF)
    assert error == ''
    assert states == {
        'arm': {'ready': READY, 'home': HOME},
        'gripper': {'open': {'gripper_joint': 0.02}, 'closed': {'gripper_joint': 0.0}},
    }


def test_keeps_srdf_order():
    # current_state picks the first match, so the order must be the SRDF's.
    states, _ = parse_group_states(MAKER_ARM_SRDF)
    assert list(states['arm']) == ['ready', 'home']
    assert list(states['gripper']) == ['open', 'closed']


def test_malformed_xml_is_empty_with_an_error():
    states, error = parse_group_states('<robot name="x"><group_state name="ready"')
    assert states == {}
    assert error.startswith('malformed SRDF')


def test_empty_text_is_malformed():
    states, error = parse_group_states('')
    assert states == {}
    assert error


def test_srdf_without_group_states_is_empty_without_an_error():
    assert parse_group_states('<robot name="x"><group name="arm"/></robot>') == ({}, '')


def test_skips_a_group_state_without_a_group():
    srdf = ('<robot name="x"><group_state name="a"><joint name="j" value="1"/></group_state>'
            '<group_state name="b" group="arm"><joint name="j" value="2"/></group_state></robot>')
    states, error = parse_group_states(srdf)
    assert states == {'arm': {'b': {'j': 2.0}}}
    assert 'without a name or group' in error


def test_skips_a_multi_dof_joint_value_and_keeps_the_rest():
    srdf = ('<robot name="x"><group_state name="park" group="base">'
            '<joint name="world_joint" value="0 0 0"/><joint name="lift" value="0.5"/>'
            '</group_state></robot>')
    states, error = parse_group_states(srdf)
    assert states == {'base': {'park': {'lift': 0.5}}}
    assert 'world_joint' in error


def test_parses_scientific_notation_and_negative_values():
    srdf = ('<robot name="x"><group_state name="s" group="g">'
            '<joint name="a" value="-1.5e-3"/><joint name="b" value="3.14159"/></group_state></robot>')
    states, _ = parse_group_states(srdf)
    assert states['g']['s'] == {'a': -0.0015, 'b': 3.14159}


# --- at_state ---

def test_exactly_at_the_state():
    assert at_state(dict(READY), READY)


def test_within_tolerance_is_at_the_state():
    positions = {joint: value + 0.009 for joint, value in READY.items()}
    assert at_state(positions, READY, tolerance=0.01)


def test_outside_tolerance_is_not_at_the_state():
    positions = dict(READY, joint3=READY['joint3'] + 0.011)
    assert not at_state(positions, READY, tolerance=0.01)


def test_default_tolerance_is_a_hundredth_of_a_radian():
    assert DEFAULT_TOLERANCE == 0.01
    assert at_state(dict(READY, joint1=0.0099), READY)
    assert not at_state(dict(READY, joint1=0.0101), READY)


def test_missing_joint_is_not_at_the_state():
    positions = {joint: value for joint, value in READY.items() if joint != 'joint4'}
    assert not at_state(positions, READY)


def test_extra_joints_do_not_matter():
    # /joint_states also carries the gripper and other groups' joints.
    assert at_state(dict(READY, gripper_joint=0.02, wheel=12.0), READY)


def test_empty_target_never_matches():
    assert not at_state(dict(READY), {})


# --- current_state ---

def test_current_state_names_the_state_the_arm_is_at():
    assert current_state(dict(HOME), arm_states()) == 'home'
    assert current_state(dict(READY, gripper_joint=0.0), arm_states()) == 'ready'


def test_current_state_is_empty_between_states():
    positions = {joint: (READY[joint] + HOME[joint]) / 2 for joint in READY}
    assert current_state(positions, arm_states()) == ''


def test_current_state_is_empty_without_joint_states():
    assert current_state({}, arm_states()) == ''


def test_current_state_is_empty_without_states():
    assert current_state(dict(HOME), {}) == ''


def test_current_state_picks_the_first_match_in_srdf_order():
    states = {'zero': {'j': 0.0}, 'also_zero': {'j': 0.005}}
    assert current_state({'j': 0.0}, states) == 'zero'
    reversed_states = {'also_zero': {'j': 0.005}, 'zero': {'j': 0.0}}
    assert current_state({'j': 0.0}, reversed_states) == 'also_zero'


def test_current_state_uses_the_tolerance():
    assert current_state(dict(HOME, joint1=0.05), arm_states(), tolerance=0.1) == 'home'
    assert current_state(dict(HOME, joint1=0.05), arm_states(), tolerance=0.01) == ''


# --- decide_command ---

def test_known_state_moves():
    assert decide_command('ready', arm_states(), move_active=False) == (MOVE, '')


def test_known_state_during_a_move_cancels_then_moves():
    assert decide_command('home', arm_states(), move_active=True) == (CANCEL_THEN_MOVE, '')


def test_same_state_during_a_move_still_cancels_then_moves():
    # The newest tap wins, even when it repeats the running goal.
    assert decide_command('ready', arm_states(), move_active=True).action == CANCEL_THEN_MOVE


def test_unknown_state_is_rejected_with_the_known_names():
    action, reason = decide_command('wave', arm_states(), move_active=False)
    assert action == REJECT
    assert "'wave'" in reason
    assert 'ready, home' in reason


def test_unknown_state_during_a_move_is_rejected_and_does_not_cancel():
    assert decide_command('wave', arm_states(), move_active=True).action == REJECT


def test_another_groups_state_is_rejected():
    # 'open' is the gripper's; the node drives one planning group.
    assert decide_command('open', arm_states(), move_active=False).action == REJECT


def test_empty_name_is_rejected():
    action, reason = decide_command('', arm_states(), move_active=False)
    assert action == REJECT
    assert 'empty' in reason


def test_rejected_before_the_srdf_arrives():
    action, reason = decide_command('ready', {}, move_active=False)
    assert action == REJECT
    assert 'SRDF' in reason


def test_state_without_joints_is_rejected():
    assert decide_command('nothing', {'nothing': {}}, move_active=False).action == REJECT


# --- parse_parameters ---

def test_default_parameters_are_valid():
    parse_parameters(0.2, 0.2, 0.01, 5.0)


@pytest.mark.parametrize('velocity, acceleration, tolerance, planning_time', [
    (0.0, 0.2, 0.01, 5.0),
    (1.5, 0.2, 0.01, 5.0),
    (0.2, -0.1, 0.01, 5.0),
    (0.2, 0.2, 0.0, 5.0),
    (0.2, 0.2, 0.01, 0.0),
])
def test_out_of_range_parameters_raise(velocity, acceleration, tolerance, planning_time):
    with pytest.raises(ValueError):
        parse_parameters(velocity, acceleration, tolerance, planning_time)
