"""The MoveIt Servo overlay Conduit's arm view needs, loaded after the robot's Servo parameters."""

from pathlib import Path

import yaml

OVERLAY = Path(__file__).resolve().parents[1] / 'config' / 'servo_overlay.yaml'


def load():
    return yaml.safe_load(OVERLAY.read_text())


def test_overlay_applies_to_any_servo_node_name():
    # '/**' matches every node, so a robot that names its Servo node differently still gets it.
    assert list(load()) == ['/**']


def test_overlay_sets_speed_units_and_a_half_second_timeout():
    servo = load()['/**']['ros__parameters']['moveit_servo']
    assert servo == {'command_in_type': 'speed_units', 'incoming_command_timeout': 0.5}
