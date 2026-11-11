"""The map camera's raycaster and renderer, tested without ROS."""

import math

import numpy as np

from conduit_demo.raycast import GridView, Pose2D, cast_ray, render


def make_grid(wall_x=1.5, fill=0):
    """20 x 20 cells at 0.1 m, with a wall column at ``wall_x`` metres (or none)."""
    size = 20
    data = [fill] * (size * size)
    if wall_x is not None:
        col = int(wall_x / 0.1)
        for row in range(size):
            data[row * size + col] = 100
    return GridView(size, size, 0.1, 0.0, 0.0, data)


def wall_rows(image, column):
    """Number of rows in ``column`` that are neither ceiling (top) nor floor (bottom)."""
    top, bottom = image[0, column], image[-1, column]
    pixels = image[:, column]
    return int(np.sum(~(np.all(pixels == top, axis=1) | np.all(pixels == bottom, axis=1))))


def test_cast_ray_hits_the_wall_ahead():
    assert abs(cast_ray(make_grid(), 0.5, 1.0, 0.0) - 1.0) <= 0.1


def test_cast_ray_counts_the_grid_edge_as_a_wall():
    # No wall: the ray from x = 0.5 reaches the edge at x = 2.0 (1.5 m away).
    assert abs(cast_ray(make_grid(wall_x=None), 0.5, 1.0, 0.0) - 1.5) <= 0.1


def test_cast_ray_passes_unknown_cells():
    grid = make_grid(wall_x=None, fill=-1)
    assert abs(cast_ray(grid, 0.5, 1.0, 0.0) - 1.5) <= 0.1


def test_cast_ray_returns_max_range_when_nothing_is_hit():
    assert cast_ray(make_grid(), 0.5, 1.0, 0.0, max_range=0.5) == 0.5


def test_render_shape_and_dtype():
    image = render(make_grid(), Pose2D(0.5, 1.0, 0.0))
    assert image.shape == (240, 320, 3)
    assert image.dtype == np.uint8


def test_nearer_wall_draws_taller():
    near = render(make_grid(), Pose2D(1.0, 1.0, 0.0))  # 0.5 m from the wall
    far = render(make_grid(), Pose2D(0.3, 1.0, 0.0))  # 1.2 m from the wall
    assert wall_rows(near, 160) > wall_rows(far, 160)


def test_turning_changes_the_view():
    grid = make_grid()
    facing = render(grid, Pose2D(0.5, 1.0, 0.0))
    away = render(grid, Pose2D(0.5, 1.0, math.pi))
    assert not np.array_equal(facing, away)
