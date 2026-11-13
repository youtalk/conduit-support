"""The initial pose's yaw-to-quaternion helper, tested without ROS."""

import math

from conduit_demo.initial_pose import yaw_to_quaternion


def test_yaw_to_quaternion():
    assert yaw_to_quaternion(0.0) == (0.0, 1.0)
    z, w = yaw_to_quaternion(math.pi / 2.0)
    assert abs(z - math.sqrt(0.5)) <= 1e-12
    assert abs(w - math.sqrt(0.5)) <= 1e-12
    z, w = yaw_to_quaternion(math.pi)
    assert abs(z - 1.0) <= 1e-12
    assert abs(w) <= 1e-12
