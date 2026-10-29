"""The Kachaka parameter file: Conduit's Joy layout with Kachaka's speeds."""

from pathlib import Path

import yaml

CONFIG = Path(__file__).resolve().parents[1] / 'config'


def params(name):
    return yaml.safe_load((CONFIG / name).read_text())['teleop_twist_joy_node']['ros__parameters']


def test_full_stick_is_the_bridges_top_speed():
    # kachaka-api's manual_control divides cmd_vel by 0.3 m/s and 1.57 rad/s.
    p = params('kachaka_teleop_twist_joy.yaml')
    assert p['scale_linear'] == {'x': 0.3}
    assert p['scale_angular'] == {'yaw': 1.57}


def test_keeps_the_joy_layout_deadman_and_turbo_off():
    # params_file replaces teleop_twist_joy.yaml, and a key the file leaves out falls back to
    # teleop_twist_joy's own default (deadman button 5), so the file repeats every one of them.
    p = params('kachaka_teleop_twist_joy.yaml')
    assert p['require_enable_button'] is True
    assert p['enable_button'] == 9         # buttons[9]: left shoulder, the deadman
    assert p['enable_turbo_button'] == -1  # turbo off: teleop_twist_joy checks it before the deadman
    assert p['axis_linear'] == {'x': 1}    # axes[1]: left stick up/down
    assert p['axis_angular'] == {'yaw': 0}  # axes[0]: left stick left/right
    assert p['publish_stamped_twist'] is False
