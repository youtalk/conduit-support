"""Decision logic of joy_watchdog, free of rclpy so plain pytest can test it."""

from typing import Optional, Tuple

FORWARD = 'forward'
ZERO = 'zero'
SILENT = 'silent'


def parse_parameters(timeout_s: float, zero_rate_hz: float, zero_duration_s: float) -> Tuple[int, float, int]:
    """Validate joy_watchdog's parameters.

    Return the Joy timeout in nanoseconds, the timer period in seconds and the
    length of the zero-twist window in nanoseconds. Raise ValueError for a value
    that is not positive.
    """
    if timeout_s <= 0:
        raise ValueError(f'timeout must be positive, got {timeout_s}')
    if zero_rate_hz <= 0:
        raise ValueError(f'zero_rate_hz must be positive, got {zero_rate_hz}')
    if zero_duration_s <= 0:
        raise ValueError(f'zero_duration must be positive, got {zero_duration_s}')
    return round(timeout_s * 1e9), 1.0 / zero_rate_hz, round(zero_duration_s * 1e9)


def is_joy_fresh(now_ns: int, last_joy_ns: Optional[int], timeout_ns: int) -> bool:
    """Return True when a Joy has arrived and the newest one is younger than timeout_ns."""
    if last_joy_ns is None:
        return False
    return now_ns - last_joy_ns < timeout_ns


def watchdog_action(now_ns: int, last_joy_ns: Optional[int], timeout_ns: int, zero_duration_ns: int) -> str:
    """What joy_watchdog does at now_ns.

    FORWARD while the newest Joy is younger than timeout_ns. ZERO (publish a zero
    Twist on each timer tick) for zero_duration_ns once it is older. SILENT after
    that window and before any Joy has arrived, so another cmd_vel publisher such
    as Nav2 is not overridden while nobody drives from the phone.
    """
    if is_joy_fresh(now_ns, last_joy_ns, timeout_ns):
        return FORWARD
    if last_joy_ns is not None and now_ns - last_joy_ns < timeout_ns + zero_duration_ns:
        return ZERO
    return SILENT
