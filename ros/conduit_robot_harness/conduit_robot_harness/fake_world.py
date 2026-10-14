"""The fake mobile robot's world: an occupancy grid, ray casting and motion.

Pure numpy (no rclpy) so it is unit-tested on any machine. The grid follows
nav_msgs/OccupancyGrid: row 0 is the bottom edge (y = origin_y), cells hold
-1 (unknown), 0 (free) or 100 (occupied).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

FREE = 0
OCCUPIED = 100
UNKNOWN = -1


@dataclass(frozen=True)
class GridSpec:
    width: int = 200          # cells
    height: int = 150         # cells
    resolution: float = 0.05  # m per cell
    origin_x: float = -5.0    # map-frame x of cell (0, 0)'s corner
    origin_y: float = -3.75


@dataclass(frozen=True)
class Pose2D:
    x: float = 0.0
    y: float = 0.0
    yaw: float = 0.0


def wrap(angle: float) -> float:
    return math.atan2(math.sin(angle), math.cos(angle))


def compose(a: Pose2D, b: Pose2D) -> Pose2D:
    """a * b: pose b expressed in a's frame, moved into a's parent frame."""
    c, s = math.cos(a.yaw), math.sin(a.yaw)
    return Pose2D(a.x + c * b.x - s * b.y, a.y + s * b.x + c * b.y, wrap(a.yaw + b.yaw))


def inverse(a: Pose2D) -> Pose2D:
    c, s = math.cos(a.yaw), math.sin(a.yaw)
    return Pose2D(-(c * a.x + s * a.y), -(-s * a.x + c * a.y), wrap(-a.yaw))


def make_grid(spec: GridSpec = GridSpec()) -> np.ndarray:
    """A walled room with two pillars and an unknown corner."""
    grid = np.full((spec.height, spec.width), FREE, dtype=np.int8)
    grid[0:2, :] = OCCUPIED
    grid[-2:, :] = OCCUPIED
    grid[:, 0:2] = OCCUPIED
    grid[:, -2:] = OCCUPIED
    grid[40:60, 50:60] = OCCUPIED      # pillar at x -2.5..-2.0, y -1.75..-0.75
    grid[90:110, 130:150] = OCCUPIED   # pillar at x 1.5..2.5, y 0.75..1.75
    grid[spec.height - 20:spec.height - 2, spec.width - 30:spec.width - 2] = UNKNOWN
    return grid


def is_blocked(grid: np.ndarray, spec: GridSpec, x: float, y: float) -> bool:
    col = math.floor((x - spec.origin_x) / spec.resolution)
    row = math.floor((y - spec.origin_y) / spec.resolution)
    if row < 0 or col < 0 or row >= spec.height or col >= spec.width:
        return True
    return int(grid[row, col]) == OCCUPIED


def scan(grid: np.ndarray, spec: GridSpec, laser: Pose2D, angle_min: float,
         angle_increment: float, count: int, range_max: float) -> np.ndarray:
    """Ranges (float32, inf for no return) from the laser pose, in the map frame."""
    angles = laser.yaw + angle_min + angle_increment * np.arange(count)
    steps = np.arange(0.0, range_max, spec.resolution * 0.5)
    xs = laser.x + np.outer(np.cos(angles), steps)
    ys = laser.y + np.outer(np.sin(angles), steps)
    cols = np.floor((xs - spec.origin_x) / spec.resolution).astype(int)
    rows = np.floor((ys - spec.origin_y) / spec.resolution).astype(int)
    outside = (rows < 0) | (cols < 0) | (rows >= spec.height) | (cols >= spec.width)
    hit = outside | (grid[np.clip(rows, 0, spec.height - 1), np.clip(cols, 0, spec.width - 1)] == OCCUPIED)
    first = np.argmax(hit, axis=1)
    return np.where(hit.any(axis=1), steps[first], np.inf).astype(np.float32)


def integrate(pose: Pose2D, v: float, w: float, dt: float,
              grid: np.ndarray, spec: GridSpec) -> Pose2D:
    """One unicycle step; a step into an occupied cell only turns (the robot stops at walls)."""
    yaw = wrap(pose.yaw + w * dt)
    x = pose.x + v * math.cos(yaw) * dt
    y = pose.y + v * math.sin(yaw) * dt
    if is_blocked(grid, spec, x, y):
        return Pose2D(pose.x, pose.y, yaw)
    return Pose2D(x, y, yaw)


def yaw_to_quaternion(yaw: float):
    """(x, y, z, w) of a rotation about z."""
    return (0.0, 0.0, math.sin(yaw / 2.0), math.cos(yaw / 2.0))
