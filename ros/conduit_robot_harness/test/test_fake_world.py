import math

import numpy as np

from conduit_robot_harness.fake_world import (
    OCCUPIED,
    UNKNOWN,
    GridSpec,
    Pose2D,
    compose,
    integrate,
    inverse,
    is_blocked,
    make_grid,
    scan,
    yaw_to_quaternion,
)

SPEC = GridSpec()


def test_grid_has_walls_pillars_and_an_unknown_corner():
    grid = make_grid(SPEC)
    assert grid.shape == (150, 200)
    assert grid.dtype == np.int8
    assert grid[0, 100] == OCCUPIED and grid[149, 100] == OCCUPIED
    assert grid[50, 55] == OCCUPIED
    assert grid[140, 180] == UNKNOWN
    assert grid[75, 100] == 0


def test_origin_is_free_and_walls_block():
    grid = make_grid(SPEC)
    assert not is_blocked(grid, SPEC, 0.0, 0.0)
    assert is_blocked(grid, SPEC, -4.96, 0.0)
    assert is_blocked(grid, SPEC, 10.0, 0.0)


def test_scan_hits_the_east_wall_ahead():
    grid = make_grid(SPEC)
    ranges = scan(grid, SPEC, Pose2D(0.0, 0.0, 0.0), 0.0, math.pi / 2, 4, 8.0)
    assert ranges.dtype == np.float32
    assert abs(ranges[0] - 4.9) < 0.05           # east wall at x = 4.9
    assert abs(ranges[1] - 3.65) < 0.05          # north wall at y = 3.65
    assert abs(ranges[2] - 4.9) < 0.05           # west wall at x = -4.9
    assert abs(ranges[3] - 3.65) < 0.05          # south wall at y = -3.65


def test_scan_beyond_range_is_inf():
    grid = make_grid(SPEC)
    ranges = scan(grid, SPEC, Pose2D(0.0, 0.0, 0.0), 0.0, 0.1, 1, 1.0)
    assert math.isinf(ranges[0])


def test_integrate_moves_and_stops_at_walls():
    grid = make_grid(SPEC)
    moved = integrate(Pose2D(0.0, 0.0, 0.0), 1.0, 0.0, 0.5, grid, SPEC)
    assert abs(moved.x - 0.5) < 1e-9 and moved.y == 0.0
    at_wall = Pose2D(4.85, 0.0, 0.0)
    blocked = integrate(at_wall, 1.0, 0.0, 0.1, grid, SPEC)
    assert blocked.x == at_wall.x


def test_compose_and_inverse_round_trip():
    a = Pose2D(0.5, 0.2, 0.1)
    b = Pose2D(1.0, -2.0, 1.2)
    back = compose(inverse(a), compose(a, b))
    assert abs(back.x - b.x) < 1e-9 and abs(back.y - b.y) < 1e-9 and abs(back.yaw - b.yaw) < 1e-9


def test_yaw_to_quaternion():
    x, y, z, w = yaw_to_quaternion(math.pi / 2)
    assert (x, y) == (0.0, 0.0)
    assert abs(z - math.sqrt(0.5)) < 1e-9 and abs(w - math.sqrt(0.5)) < 1e-9
