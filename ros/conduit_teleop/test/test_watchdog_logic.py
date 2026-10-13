"""joy_watchdog's decision logic, tested without ROS."""

import pytest

from conduit_teleop.watchdog_logic import (
    FORWARD, SILENT, ZERO, is_joy_fresh, parse_parameters, watchdog_action)

TIMEOUT_NS = 500_000_000  # 0.5 s
ZERO_NS = 1_000_000_000  # zero twists for 1 s after the Joy goes stale


def test_no_joy_yet_is_stale():
    assert not is_joy_fresh(now_ns=1_000_000_000, last_joy_ns=None, timeout_ns=TIMEOUT_NS)


def test_joy_just_received_is_fresh():
    assert is_joy_fresh(now_ns=5_000_000_000, last_joy_ns=5_000_000_000, timeout_ns=TIMEOUT_NS)


def test_joy_younger_than_timeout_is_fresh():
    assert is_joy_fresh(now_ns=5_499_999_999, last_joy_ns=5_000_000_000, timeout_ns=TIMEOUT_NS)


def test_joy_exactly_timeout_old_is_stale():
    assert not is_joy_fresh(now_ns=5_500_000_000, last_joy_ns=5_000_000_000, timeout_ns=TIMEOUT_NS)


def test_joy_older_than_timeout_is_stale():
    assert not is_joy_fresh(now_ns=9_000_000_000, last_joy_ns=5_000_000_000, timeout_ns=TIMEOUT_NS)


def test_no_joy_yet_is_silent():
    # Never fight another cmd_vel publisher before the phone has driven at all.
    assert watchdog_action(1_000_000_000, None, TIMEOUT_NS, ZERO_NS) == SILENT


def test_fresh_joy_forwards():
    assert watchdog_action(5_499_999_999, 5_000_000_000, TIMEOUT_NS, ZERO_NS) == FORWARD


def test_stale_joy_publishes_zero_for_one_second():
    assert watchdog_action(5_500_000_000, 5_000_000_000, TIMEOUT_NS, ZERO_NS) == ZERO
    assert watchdog_action(6_499_999_999, 5_000_000_000, TIMEOUT_NS, ZERO_NS) == ZERO


def test_after_the_zero_window_the_watchdog_is_silent():
    assert watchdog_action(6_500_000_000, 5_000_000_000, TIMEOUT_NS, ZERO_NS) == SILENT
    assert watchdog_action(60_000_000_000, 5_000_000_000, TIMEOUT_NS, ZERO_NS) == SILENT


def test_a_new_joy_forwards_again_and_rearms_the_zero_window():
    assert watchdog_action(70_000_000_000, 70_000_000_000, TIMEOUT_NS, ZERO_NS) == FORWARD
    assert watchdog_action(70_600_000_000, 70_000_000_000, TIMEOUT_NS, ZERO_NS) == ZERO


def test_parse_parameters_defaults():
    assert parse_parameters(0.5, 10.0, 1.0) == (500_000_000, 0.1, 1_000_000_000)


@pytest.mark.parametrize('timeout_s, zero_rate_hz, zero_duration_s', [
    (0.0, 10.0, 1.0), (-1.0, 10.0, 1.0), (0.5, 0.0, 1.0), (0.5, -5.0, 1.0), (0.5, 10.0, 0.0), (0.5, 10.0, -1.0)])
def test_parse_parameters_rejects_non_positive(timeout_s, zero_rate_hz, zero_duration_s):
    with pytest.raises(ValueError):
        parse_parameters(timeout_s, zero_rate_hz, zero_duration_s)
