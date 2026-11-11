"""The simulated battery curve, tested without ROS."""

from conduit_demo.battery import battery_fraction, is_charging

PERIOD = 1800.0


def test_battery_drains_then_charges():
    assert battery_fraction(0.0) == 1.0
    assert abs(battery_fraction(0.8 * PERIOD) - 0.2) <= 0.01
    assert not is_charging(0.4 * PERIOD)
    assert is_charging(0.9 * PERIOD)
    assert battery_fraction(0.9 * PERIOD) > 0.2
    assert abs(battery_fraction(PERIOD) - 1.0) <= 0.01
    assert abs(battery_fraction(PERIOD + 10.0) - battery_fraction(10.0)) <= 1e-9
