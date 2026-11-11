"""gripper_command's GripperCommand -> ParallelGripperCommand mapping (needs control_msgs)."""

import pytest

pytest.importorskip('control_msgs')

from conduit_demo.gripper_command import joint_value, parallel_command  # noqa: E402


def test_joint_value_by_name():
    names = ['panda_finger_joint1', 'panda_finger_joint2']
    assert joint_value(names, [0.02, 0.03], 'panda_finger_joint2') == 0.03
    assert joint_value(names, [0.02, 0.03], 'panda_finger_joint1') == 0.02


def test_joint_value_missing():
    assert joint_value(['other'], [0.02], 'panda_finger_joint1') == 0.0
    assert joint_value(['panda_finger_joint1'], [], 'panda_finger_joint1') == 0.0


def test_joint_value_unnamed_single():
    assert joint_value([], [0.01], 'panda_finger_joint1') == 0.01


def test_parallel_command():
    goal = parallel_command('panda_finger_joint1', 0.04, 20.0)
    assert list(goal.command.name) == ['panda_finger_joint1']
    assert list(goal.command.position) == [0.04]
    assert list(goal.command.effort) == [20.0]


def test_parallel_command_without_effort():
    goal = parallel_command('panda_finger_joint1', 0.0, 0.0)
    assert list(goal.command.position) == [0.0]
    assert list(goal.command.effort) == []
