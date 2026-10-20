"""Decision logic of named_pose_node, free of rclpy so plain pytest can test it.

A named pose is an SRDF ``group_state``: a name and a position for each joint of
one planning group. Conduit's pose buttons send that name.
"""

from collections import namedtuple
from typing import Dict, Mapping, Tuple
import xml.etree.ElementTree as ET

# {group: {state: {joint: position}}}, in SRDF order.
GroupStates = Dict[str, Dict[str, Dict[str, float]]]

REJECT = 'reject'
MOVE = 'move'
CANCEL_THEN_MOVE = 'cancel_then_move'

DEFAULT_TOLERANCE = 0.01  # rad

CommandDecision = namedtuple('CommandDecision', ['action', 'reason'])


def parse_group_states(srdf_xml: str) -> Tuple[GroupStates, str]:
    """Read every ``group_state`` of an SRDF.

    Return ``({group: {state: {joint: value}}}, error)``. ``error`` is '' when the
    SRDF parsed cleanly. Malformed XML gives an empty dict and the parser's error.
    A ``group_state`` without a name or group, and a joint without a name or with a
    value that is not one number (a multi-DOF joint), are skipped and named in
    ``error``; the rest of the SRDF is still returned.
    """
    try:
        root = ET.fromstring(srdf_xml)
    except ET.ParseError as e:
        return {}, f'malformed SRDF: {e}'
    states: GroupStates = {}
    problems = []
    for element in root.iter('group_state'):
        name = element.get('name')
        group = element.get('group')
        if not name or not group:
            problems.append('a group_state without a name or group')
            continue
        joints = {}
        for joint in element.iter('joint'):
            joint_name = joint.get('name')
            if not joint_name:
                problems.append(f'{group}/{name}: a joint without a name')
                continue
            try:
                joints[joint_name] = float(joint.get('value', ''))
            except ValueError:
                problems.append(f"{group}/{name}: joint '{joint_name}' value {joint.get('value')!r} is not one number")
        states.setdefault(group, {})[name] = joints
    return states, '; '.join(problems)


def at_state(joint_positions: Mapping[str, float], target: Mapping[str, float],
             tolerance: float = DEFAULT_TOLERANCE) -> bool:
    """True when every joint of target is in joint_positions and within tolerance of it.

    A target without joints never matches.
    """
    if not target:
        return False
    for joint, value in target.items():
        position = joint_positions.get(joint)
        if position is None or abs(position - value) > tolerance:
            return False
    return True


def current_state(joint_positions: Mapping[str, float], states_of_group: Mapping[str, Mapping[str, float]],
                  tolerance: float = DEFAULT_TOLERANCE) -> str:
    """The first state (in SRDF order) the joints are at, or '' when they are at none."""
    for name, target in states_of_group.items():
        if at_state(joint_positions, target, tolerance):
            return name
    return ''


def decide_command(name: str, states_of_group: Mapping[str, Mapping[str, float]],
                   move_active: bool) -> CommandDecision:
    """What named_pose_node does with a requested state name.

    REJECT (with a reason) a name the planning group does not define. Otherwise
    CANCEL_THEN_MOVE while a move is active (the newest tap wins), else MOVE.
    """
    if not name:
        return CommandDecision(REJECT, 'empty group state name')
    if not states_of_group:
        return CommandDecision(REJECT, 'no group states known for the planning group (no SRDF received yet, '
                                       'or the SRDF defines none for it)')
    if name not in states_of_group:
        known = ', '.join(states_of_group)
        return CommandDecision(REJECT, f"unknown group state '{name}' (known: {known})")
    if not states_of_group[name]:
        return CommandDecision(REJECT, f"group state '{name}' has no joints")
    if move_active:
        return CommandDecision(CANCEL_THEN_MOVE, '')
    return CommandDecision(MOVE, '')


def parse_parameters(velocity_scaling: float, acceleration_scaling: float, tolerance: float,
                     planning_time: float) -> None:
    """Raise ValueError for a named_pose_node parameter that is out of range."""
    for label, value in (('velocity_scaling', velocity_scaling), ('acceleration_scaling', acceleration_scaling)):
        if not 0.0 < value <= 1.0:
            raise ValueError(f'{label} must be in (0, 1], got {value}')
    if tolerance <= 0:
        raise ValueError(f'tolerance must be positive, got {tolerance}')
    if planning_time <= 0:
        raise ValueError(f'planning_time must be positive, got {planning_time}')
