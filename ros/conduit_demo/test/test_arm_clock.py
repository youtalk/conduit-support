"""arm_clock's move of Servo's wall-clock stamps onto Gazebo's clock (needs rclpy)."""

import pytest

pytest.importorskip('rclpy')
pytest.importorskip('trajectory_msgs')

from conduit_demo.arm_clock import to_sim_ns  # noqa: E402

S = 1_000_000_000


def test_wall_stamp_moves_by_the_clock_offset():
    wall_now = 1_794_389_000 * S
    sim_now = 120 * S
    # A trajectory stamped 0.18 s ago on the wall clock starts 0.18 s ago on Gazebo's.
    assert to_sim_ns(wall_now - 180_000_000, sim_now, wall_now) == sim_now - 180_000_000


def test_zero_stamp_stays_start_now():
    assert to_sim_ns(0, 120 * S, 1_794_389_000 * S) == 0


def test_stamp_before_the_simulation_start_is_start_now():
    wall_now = 1_794_389_000 * S
    assert to_sim_ns(wall_now - 2 * S, S, wall_now) == 0


def test_same_clocks_keep_the_stamp():
    now = 1_794_389_000 * S
    assert to_sim_ns(now - 5, now, now) == now - 5
