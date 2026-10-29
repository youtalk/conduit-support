"""kachaka.launch.py's structure, checked without starting anything.

conduit-support's CI installs only requirements.txt (no ROS), so this module skips
there; ROS_CHECK runs it in the Jazzy container.
"""

import importlib.util
import os

import pytest

pytest.importorskip("launch")
pytest.importorskip("launch_ros")

from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, TimerAction  # noqa: E402


def _load():
    path = os.path.join(os.path.dirname(__file__), "..", "launch", "kachaka.launch.py")
    spec = importlib.util.spec_from_file_location("kachaka_launch", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.generate_launch_description()


def test_declares_the_joy_topic_and_the_kachaka_namespace():
    names = {e.name for e in _load().entities if isinstance(e, DeclareLaunchArgument)}
    assert names == {"joy_topic", "kachaka_namespace"}


def test_includes_conduit_teleop_with_the_kachaka_parameter_file():
    includes = [e for e in _load().entities if isinstance(e, IncludeLaunchDescription)]
    assert len(includes) == 1
    args = dict(includes[0].launch_arguments)
    assert set(args) == {"joy_topic", "cmd_vel_topic", "params_file"}
    assert "kachaka_teleop_twist_joy.yaml" in repr(args["params_file"])


def test_enables_manual_control():
    assert any(isinstance(e, TimerAction) for e in _load().entities)
