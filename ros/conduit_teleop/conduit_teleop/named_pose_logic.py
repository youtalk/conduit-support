"""Decision logic of named_pose_node, free of rclpy so plain pytest can test it.

A named pose is an SRDF ``group_state``: a name and a position for each joint of
one planning group. Conduit's pose buttons send that name.
"""

from collections import namedtuple
import math
from typing import AbstractSet, Dict, FrozenSet, Mapping, Optional, Tuple
import xml.etree.ElementTree as ET

# {group: {state: {joint: position}}}, in SRDF order.
GroupStates = Dict[str, Dict[str, Dict[str, float]]]

REJECT = 'reject'
IGNORE = 'ignore'
MOVE = 'move'
CANCEL_THEN_MOVE = 'cancel_then_move'

DEFAULT_TOLERANCE = 0.01  # rad

# Conduit repeats the clutch at 10 Hz while the arm view is open: 0.5 s is about five
# missed repeats.
DEFAULT_CLUTCH_TIMEOUT = 0.5  # s

# Phases of a move once its goal is on its way to move_group.
SENDING = 'sending'  # the goal is sent; move_group has not accepted it yet
RUNNING = 'running'  # accepted; waiting for the result
CANCELLING = 'cancelling'  # a cancel is requested; waiting for the result

# move_group accepts a goal, and ends a cancelled one, within moments. A move that
# waits longer than this for either has lost move_group.
ANSWER_TIMEOUT = 5.0  # s

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


def parse_continuous_joints(urdf_xml: str) -> Tuple[FrozenSet[str], str]:
    """The names of the URDF's continuous joints, and an error ('' when the URDF parsed).

    Malformed XML gives an empty set and the parser's error.
    """
    try:
        root = ET.fromstring(urdf_xml)
    except ET.ParseError as e:
        return frozenset(), f'malformed URDF: {e}'
    return frozenset(joint.get('name') for joint in root.iter('joint')
                     if joint.get('type') == 'continuous' and joint.get('name')), ''


def joint_distance(position: float, value: float, continuous: bool = False) -> float:
    """How far position is from value; a continuous joint takes the short way round."""
    if continuous:
        return abs(math.remainder(position - value, 2.0 * math.pi))
    return abs(position - value)


def at_state(joint_positions: Mapping[str, float], target: Mapping[str, float],
             tolerance: float = DEFAULT_TOLERANCE, continuous: AbstractSet[str] = frozenset()) -> bool:
    """True when every joint of target is in joint_positions and within tolerance of it.

    A joint named in continuous matches its value plus any number of turns, as
    MoveIt's joint constraints do. A target without joints never matches.
    """
    if not target:
        return False
    for joint, value in target.items():
        position = joint_positions.get(joint)
        if position is None or joint_distance(position, value, joint in continuous) > tolerance:
            return False
    return True


def current_state(joint_positions: Mapping[str, float], states_of_group: Mapping[str, Mapping[str, float]],
                  tolerance: float = DEFAULT_TOLERANCE, continuous: AbstractSet[str] = frozenset()) -> str:
    """The first state (in SRDF order) the joints are at, or '' when they are at none."""
    for name, target in states_of_group.items():
        if at_state(joint_positions, target, tolerance, continuous):
            return name
    return ''


def decide_command(name: str, states_of_group: Mapping[str, Mapping[str, float]],
                   moving_to: Optional[str] = None, cancelling: bool = False,
                   clutch_engaged: bool = False) -> CommandDecision:
    """What named_pose_node does with a requested state name.

    moving_to is the state the running move goes to (None when no move runs),
    cancelling is True once that move is being cancelled for another tap, and
    clutch_engaged is ClutchWatch.engaged(): HOLD is held in Conduit.

    REJECT (with a reason) a tap while HOLD is held (Conduit never sends one; the arm
    follows the phone then) and a name the planning group does not define. With no move
    running, MOVE. A repeat of the running move's name is IGNOREd, so a double tap
    does not stop and restart the arm; once that move is being cancelled, the repeat
    is a new tap like any other. Any other name during a move is CANCEL_THEN_MOVE
    (the newest tap wins).
    """
    if clutch_engaged:
        return CommandDecision(REJECT, f"'{name}' arrived while HOLD is engaged (the last clutch message was true)")
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
    if moving_to is None:
        return CommandDecision(MOVE, '')
    if name == moving_to and not cancelling:
        return CommandDecision(IGNORE, f"already moving to '{name}'")
    return CommandDecision(CANCEL_THEN_MOVE, '')


def move_watchdog(phase: str, elapsed: float, server_ready: bool, run_timeout: float,
                  answer_timeout: float = ANSWER_TIMEOUT) -> str:
    """Why a move whose goal went to move_group must be given up, or '' while it may go on.

    elapsed counts from when the goal was sent (SENDING, RUNNING) or from the cancel
    request (CANCELLING). The move is given up when the MoveGroup action server has
    gone, when move_group has not accepted the goal or ended the cancel within
    answer_timeout, or when it has not finished the move within run_timeout.
    """
    if not server_ready:
        return 'lost move_group (the MoveGroup action server is gone)'
    if phase == SENDING and elapsed > answer_timeout:
        return f'got no answer from move_group within {answer_timeout:g} s'
    if phase == RUNNING and elapsed > run_timeout:
        return f'did not finish within {run_timeout:g} s'
    if phase == CANCELLING and elapsed > answer_timeout:
        return f'was not cancelled by move_group within {answer_timeout:g} s'
    return ''


class ClutchWatch:
    """The last message on Conduit's clutch topic (std_msgs/Bool) and when it arrived.

    Conduit publishes true while HOLD is held and false when it is released, and
    repeats the value at 10 Hz as a heartbeat while the arm view is open. Times are
    monotonic seconds. A message older than timeout counts as none: it no longer
    tells what Conduit does.
    """

    def __init__(self, timeout: float = DEFAULT_CLUTCH_TIMEOUT):
        self.timeout = timeout
        self.value: Optional[bool] = None
        self.received_at: Optional[float] = None

    def receive(self, engaged: bool, now: float) -> None:
        self.value = engaged
        self.received_at = now

    def fresh(self, now: float) -> bool:
        """A clutch message arrived within timeout: Conduit's arm view is driving."""
        return self.received_at is not None and now - self.received_at <= self.timeout

    def engaged(self, now: float) -> bool:
        """HOLD is held: the last message was true and is fresh."""
        return self.value is True and self.fresh(now)

    def stop_reason(self, watching_heartbeat: bool, now: float) -> str:
        """Why the clutch stops a move, or '' while the move may go on.

        HOLD engaged stops any move. watching_heartbeat is fresh() at the start of the
        move: Conduit was driving then, so losing its heartbeat (the link dropped, or
        the app went to the background or closed) stops the move too. A move started
        without clutch traffic (a CLI publish) never stops for a missing heartbeat.
        """
        if self.engaged(now):
            return 'HOLD engaged: clutch true'
        if watching_heartbeat and not self.fresh(now):
            return f'clutch heartbeat lost: no clutch message for more than {self.timeout:g} s'
        return ''


def parse_parameters(velocity_scaling: float, acceleration_scaling: float, tolerance: float,
                     planning_time: float, service_timeout: float = 1.0, max_move_duration: float = 60.0,
                     clutch_timeout: float = DEFAULT_CLUTCH_TIMEOUT) -> None:
    """Raise ValueError for a named_pose_node parameter that is out of range."""
    for label, value in (('velocity_scaling', velocity_scaling), ('acceleration_scaling', acceleration_scaling)):
        if not 0.0 < value <= 1.0:
            raise ValueError(f'{label} must be in (0, 1], got {value}')
    if tolerance <= 0:
        raise ValueError(f'tolerance must be positive, got {tolerance}')
    for label, value in (('planning_time', planning_time), ('service_timeout', service_timeout),
                         ('max_move_duration', max_move_duration), ('clutch_timeout', clutch_timeout)):
        if value <= 0:
            raise ValueError(f'{label} must be positive, got {value}')
