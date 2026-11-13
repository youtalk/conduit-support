"""First-person view of an occupancy grid, drawn by casting one ray per image column.

Pure numpy, no ROS: the ``map_camera`` node converts its messages to these types.
"""

from dataclasses import dataclass
import math
from typing import Sequence

import numpy as np

OCCUPIED = 50  # OccupancyGrid values at or above this are walls; unknown (-1) is free

CEILING = (60, 70, 90)
FLOOR = (110, 100, 90)
WALL = (210, 190, 150)
WALL_HEIGHT_FRACTION = 0.4  # image height of a wall seen from 1 m away


@dataclass(frozen=True)
class GridView:
    """An OccupancyGrid: row-major ``data``, cell (0, 0) at (origin_x, origin_y)."""

    width: int
    height: int
    resolution: float
    origin_x: float
    origin_y: float
    data: Sequence[int]


@dataclass(frozen=True)
class Pose2D:
    """A pose in the map frame."""

    x: float
    y: float
    yaw: float


def _cast_rays(grid, x, y, angles, max_range):
    """Distance along each angle to the first wall cell or the grid edge, capped."""
    angles = np.asarray(angles, dtype=np.float64)
    cells = np.asarray(grid.data, dtype=np.int16).reshape(grid.height, grid.width)
    step = grid.resolution / 2.0
    distances = np.arange(step, max_range + step / 2.0, step)
    xs = x + np.cos(angles)[:, None] * distances[None, :]
    ys = y + np.sin(angles)[:, None] * distances[None, :]
    col = np.floor((xs - grid.origin_x) / grid.resolution).astype(np.int64)
    row = np.floor((ys - grid.origin_y) / grid.resolution).astype(np.int64)
    outside = (col < 0) | (col >= grid.width) | (row < 0) | (row >= grid.height)
    values = cells[np.clip(row, 0, grid.height - 1), np.clip(col, 0, grid.width - 1)]
    hit = outside | (values >= OCCUPIED)
    first = np.argmax(hit, axis=1)
    found = hit[np.arange(len(angles)), first]
    return np.where(found, distances[first], max_range)


def cast_ray(grid, x, y, angle, max_range=8.0):
    """Distance from (x, y) along ``angle`` to the first cell >= 50 or the grid edge.

    Unknown cells are free. Returns ``max_range`` when nothing is hit within it.
    """
    return float(_cast_rays(grid, x, y, [angle], max_range)[0])


def render(grid, pose, width=320, height=240, fov_deg=70.0, max_range=8.0):
    """Draw the view from ``pose`` as a (height, width, 3) uint8 RGB image.

    Ceiling above, floor below, one wall slice per column. The slice height is
    inversely proportional to the perpendicular distance (the ray length times the
    cosine of its angle off the view axis, so straight walls stay straight) and the
    wall is shaded darker with distance.
    """
    half_tan = math.tan(math.radians(fov_deg) / 2.0)
    offsets = np.arctan((2.0 * (np.arange(width) + 0.5) / width - 1.0) * half_tan)
    # Column 0 is the left edge of the view, which is +yaw (counter-clockwise).
    angles = pose.yaw - offsets
    dist = _cast_rays(grid, pose.x, pose.y, angles, max_range)
    perpendicular = np.maximum(dist * np.cos(offsets), 1e-3)
    wall_rows = np.minimum(WALL_HEIGHT_FRACTION * height / perpendicular, height)
    shade = 1.0 - 0.75 * np.minimum(dist / max_range, 1.0)

    rows = np.arange(height)[:, None]
    top = (height - wall_rows) / 2.0
    is_wall = (rows >= top[None, :]) & (rows < (top + wall_rows)[None, :])
    is_floor = rows >= height / 2.0

    image = np.empty((height, width, 3), dtype=np.uint8)
    image[:] = np.array(CEILING, dtype=np.uint8)
    image[is_floor & ~is_wall] = np.array(FLOOR, dtype=np.uint8)
    wall_colors = (np.array(WALL)[None, :] * shade[:, None]).astype(np.uint8)
    wall_image = np.broadcast_to(wall_colors[None, :, :], (height, width, 3))
    image[is_wall] = wall_image[is_wall]
    return image
