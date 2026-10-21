"""NamedPoseNode wiring of the clutch. Needs ROS 2 (rclpy, moveit_msgs); skipped without it."""

from unittest.mock import MagicMock

import pytest

pytest.importorskip('rclpy')
pytest.importorskip('moveit_msgs')

import rclpy  # noqa: E402
from std_msgs.msg import Bool, String  # noqa: E402

from conduit_teleop.named_pose_logic import RUNNING  # noqa: E402
from conduit_teleop.named_pose_node import Move, NamedPoseNode  # noqa: E402


@pytest.fixture
def node():
    rclpy.init()
    node = NamedPoseNode()
    node._states = {'ready': {'j1': 1.0}, 'home': {'j1': 0.0}}
    yield node
    node.destroy_node()
    rclpy.shutdown()


def running_move(node, watch_heartbeat=False):
    move = Move('ready', {'j1': 1.0})
    move.watch_heartbeat = watch_heartbeat
    move.enter(RUNNING)
    move.goal_handle = MagicMock()
    node._move = move
    return move


def clutch(node, value):
    node._on_clutch(Bool(data=value))


def tap(node, name):
    node._on_command(String(data=name))


def test_hold_cancels_a_running_move(node):
    move = running_move(node)
    clutch(node, True)
    assert move.cancel_requested
    assert 'HOLD' in move.stop_reason
    move.goal_handle.cancel_goal_async.assert_called_once()


def test_tap_after_a_hold_stop_is_dropped_by_the_next_hold(node):
    move = running_move(node)
    clutch(node, True)  # HOLD stops the move to 'ready'; move_group is slow to end the cancel
    clutch(node, False)  # HOLD released
    tap(node, 'home')  # waits for the cancel
    assert node._pending == 'home'
    clutch(node, True)  # HOLD again before the cancel ended
    assert node._pending is None
    clutch(node, False)
    node._end_move(move, 'cancelled')
    assert node._move is None  # no move to 'home' started


def test_tap_after_a_hold_stop_survives_while_the_clutch_stays_released(node):
    running_move(node)
    clutch(node, True)
    clutch(node, False)
    tap(node, 'home')
    clutch(node, False)
    assert node._pending == 'home'


def test_clutch_message_makes_a_running_move_watch_the_heartbeat(node):
    move = running_move(node, watch_heartbeat=False)  # started without clutch traffic (a CLI tap)
    clutch(node, False)
    assert move.watch_heartbeat
    assert not move.stop_reason
