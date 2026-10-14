import math

from conduit_gate_probe.stats import (
    JoyCmdTracker,
    ServoStopTracker,
    offset_from_echo,
    percentile,
    summarize,
)

MS = 1_000_000


def test_percentile_interpolates_and_handles_edges():
    assert math.isnan(percentile([], 50))
    assert percentile([7.0], 95) == 7.0
    assert percentile([1.0, 2.0, 3.0, 4.0], 50) == 2.5
    assert percentile(list(range(1, 101)), 95) == 95.05


def test_summarize_empty_and_values():
    assert summarize([]) == {'n': 0, 'p50_ms': None, 'p95_ms': None, 'max_ms': None}
    assert summarize([10.0, 20.0, 30.0]) == {'n': 3, 'p50_ms': 20.0, 'p95_ms': 29.0, 'max_ms': 30.0}


def test_offset_from_echo_uses_the_shortest_round_trip():
    # Host clock is 5 s ahead. Sample A: 4 ms each way. Sample B: 1 ms up, 9 ms down.
    host_ahead = 5_000 * MS
    a = (0, 4 * MS + host_ahead, 8 * MS)
    b = (100 * MS, 101 * MS + host_ahead, 110 * MS)
    offset, rtt = offset_from_echo([b, a])
    assert rtt == 8 * MS
    assert offset == host_ahead
    assert offset_from_echo([]) is None


def test_joy_to_cmd_latency_uses_the_offset():
    tracker = JoyCmdTracker(offset_ns=2_000 * MS)  # host is 2 s ahead of the phone
    tracker.on_joy(host_ns=2_010 * MS, stamp_ns=0, deadman=True)
    tracker.on_cmd(host_ns=2_030 * MS, is_zero=False)
    assert tracker.latencies_ms == [30.0]


def test_cmd_long_after_the_joy_is_not_a_latency_sample():
    tracker = JoyCmdTracker()
    tracker.on_joy(host_ns=0, stamp_ns=0, deadman=True)
    tracker.on_cmd(host_ns=500 * MS, is_zero=False)
    assert tracker.latencies_ms == []


def test_release_stop_is_the_first_zero_after_the_deadman_goes_up():
    tracker = JoyCmdTracker()
    tracker.on_joy(host_ns=0, stamp_ns=0, deadman=True)
    tracker.on_cmd(host_ns=10 * MS, is_zero=False)
    tracker.on_joy(host_ns=100 * MS, stamp_ns=100 * MS, deadman=False)
    tracker.on_cmd(host_ns=112 * MS, is_zero=True)
    tracker.on_cmd(host_ns=200 * MS, is_zero=True)
    assert tracker.release_stops_ms == [12.0]


def test_silence_stop_is_measured_from_the_last_joy():
    tracker = JoyCmdTracker()
    tracker.on_joy(host_ns=0, stamp_ns=0, deadman=True)
    tracker.on_cmd(host_ns=10 * MS, is_zero=False)
    tracker.on_cmd(host_ns=600 * MS, is_zero=True)   # watchdog zero after 0.5 s
    tracker.on_cmd(host_ns=700 * MS, is_zero=True)   # recorded once
    assert tracker.silence_stops_ms == [600.0]
    assert tracker.release_stops_ms == []


def test_servo_stop_after_a_zero_twist():
    tracker = ServoStopTracker()
    tracker.on_twist(0, nonzero=True)
    tracker.on_output(5 * MS, 0.2)
    tracker.on_twist(100 * MS, nonzero=False)
    tracker.on_output(150 * MS, 0.05)
    tracker.on_output(180 * MS, 0.0)
    assert tracker.stops_ms == [80.0]


def test_servo_stop_after_the_clutch_goes_false():
    tracker = ServoStopTracker()
    tracker.on_twist(0, nonzero=True)
    tracker.on_clutch(50 * MS, engaged=False)
    tracker.on_twist(60 * MS, nonzero=False)
    tracker.on_output(90 * MS, 0.0)
    assert tracker.stops_ms == [40.0]


def test_servo_still_output_without_a_release_records_nothing():
    tracker = ServoStopTracker()
    tracker.on_output(0, 0.0)
    tracker.on_twist(10 * MS, nonzero=True)
    tracker.on_output(20 * MS, 0.0)
    assert tracker.stops_ms == []
