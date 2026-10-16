"""The shipped teleop_twist_joy parameters match Conduit's Joy layout (ROS 2 joy)."""

from pathlib import Path

import yaml

CONFIG = Path(__file__).resolve().parents[1] / 'config' / 'teleop_twist_joy.yaml'


def params():
    return yaml.safe_load(CONFIG.read_text())['teleop_twist_joy_node']['ros__parameters']


def test_driving_subset_matches_the_joy_layout():
    p = params()
    assert p['axis_linear']['x'] == 1      # axes[1]: left stick up/down, up = +1
    assert p['axis_angular']['yaw'] == 0   # axes[0]: left stick left/right, left = +1
    assert p['enable_button'] == 9         # buttons[9]: left shoulder, the deadman


def test_deadman_required_and_turbo_off():
    # teleop_twist_joy checks the turbo button before the deadman, so any turbo
    # button would drive without the deadman held.
    p = params()
    assert p['require_enable_button'] is True
    assert p['enable_turbo_button'] == -1


def test_full_stick_speeds_are_doubles_and_twist_is_unstamped():
    p = params()
    assert isinstance(p['scale_linear']['x'], float)
    assert isinstance(p['scale_angular']['yaw'], float)
    assert p['publish_stamped_twist'] is False  # joy_watchdog forwards geometry_msgs/Twist
