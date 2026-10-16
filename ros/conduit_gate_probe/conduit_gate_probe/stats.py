"""Timing helpers for conduit_gate_probe.

Pure Python (no rclpy) so they are unit-tested on any machine. All times are
integer nanoseconds; the host clock is the reference. A phone stamp converts to
the host clock as ``stamp + offset_ns`` (offset = host clock - phone clock).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Iterable, List, Optional, Tuple

NS_PER_S = 1_000_000_000


def percentile(values: List[float], p: float) -> float:
    """Linear-interpolated percentile of ``values`` (p in [0, 100]); NaN when empty."""
    if not values:
        return math.nan
    ordered = sorted(values)
    rank = (p / 100.0) * (len(ordered) - 1)
    low = math.floor(rank)
    high = math.ceil(rank)
    if low == high:
        return ordered[low]
    return ordered[low] + (ordered[high] - ordered[low]) * (rank - low)


def summarize(values_ms: List[float]) -> dict:
    """Count, p50, p95 and max of a list of milliseconds (None when empty)."""
    if not values_ms:
        return {'n': 0, 'p50_ms': None, 'p95_ms': None, 'max_ms': None}
    return {
        'n': len(values_ms),
        'p50_ms': round(percentile(values_ms, 50), 2),
        'p95_ms': round(percentile(values_ms, 95), 2),
        'max_ms': round(max(values_ms), 2),
    }


def offset_from_echo(samples: Iterable[Tuple[int, int, int]]) -> Optional[Tuple[int, int]]:
    """Clock offset from echo samples ``(t1, t2, t4)``.

    t1: client send time (client clock), t2: host receive time (host clock),
    t4: client receive time of the echo (client clock). Returns
    ``(offset_ns, rtt_ns)`` of the sample with the shortest round trip, where
    offset = host clock - client clock under symmetric delays; None without samples.
    """
    best: Optional[Tuple[int, int]] = None
    for t1, t2, t4 in samples:
        rtt = t4 - t1
        if rtt < 0:
            continue
        if best is None or rtt < best[1]:
            best = (t2 - (t1 + t4) // 2, rtt)
    return best


@dataclass
class JoyCmdTracker:
    """Pairs /joy (phone stamp) with the cmd_vel it causes, on the host clock.

    - latencies_ms: a non-zero cmd_vel within ``pair_window_ns`` of a deadman-held
      Joy, measured from the Joy's phone stamp (converted with ``offset_ns``).
    - release_stops_ms: first zero cmd_vel after the deadman is released.
    - silence_stops_ms: first zero cmd_vel after Joy stopped arriving while the
      deadman was held (the phone lost its link).
    """

    offset_ns: int = 0
    pair_window_ns: int = 200_000_000
    latencies_ms: List[float] = field(default_factory=list)
    release_stops_ms: List[float] = field(default_factory=list)
    silence_stops_ms: List[float] = field(default_factory=list)
    _last_joy: Optional[Tuple[int, int, bool]] = None
    _deadman_held: bool = False
    _release_at: Optional[int] = None
    _silence_recorded: bool = False

    def on_joy(self, host_ns: int, stamp_ns: int, deadman: bool) -> None:
        if self._deadman_held and not deadman and self._release_at is None:
            self._release_at = host_ns
        if deadman:
            self._release_at = None
        self._deadman_held = deadman
        self._last_joy = (host_ns, stamp_ns, deadman)
        self._silence_recorded = False

    def on_cmd(self, host_ns: int, is_zero: bool) -> None:
        if is_zero and self._release_at is not None:
            self.release_stops_ms.append((host_ns - self._release_at) / 1e6)
            self._release_at = None
        if self._last_joy is None:
            return
        joy_host, joy_stamp, deadman = self._last_joy
        recent = host_ns - joy_host <= self.pair_window_ns
        if deadman and not is_zero and recent:
            self.latencies_ms.append((host_ns - (joy_stamp + self.offset_ns)) / 1e6)
        if deadman and is_zero and not recent and not self._silence_recorded:
            self.silence_stops_ms.append((host_ns - joy_host) / 1e6)
            self._silence_recorded = True


@dataclass
class ServoStopTracker:
    """Time from releasing the clutch to Servo commanding zero velocity (host clock).

    The release is the first zero TwistStamped after a moving one, or the clutch
    topic going false, whichever comes first.
    """

    still_threshold: float = 1e-3
    stops_ms: List[float] = field(default_factory=list)
    _moving: bool = False
    _release_at: Optional[int] = None

    def on_twist(self, host_ns: int, nonzero: bool) -> None:
        if nonzero:
            self._moving = True
            self._release_at = None
        elif self._moving:
            self._release(host_ns)

    def on_clutch(self, host_ns: int, engaged: bool) -> None:
        if not engaged and self._moving:
            self._release(host_ns)

    def on_output(self, host_ns: int, max_abs_velocity: float) -> None:
        if self._release_at is not None and max_abs_velocity < self.still_threshold:
            self.stops_ms.append((host_ns - self._release_at) / 1e6)
            self._release_at = None

    def _release(self, host_ns: int) -> None:
        self._moving = False
        if self._release_at is None:
            self._release_at = host_ns
