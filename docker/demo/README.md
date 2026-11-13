# Conduit Robots demo image

For maintainers. The image carries both demo robots: a TurtleBot3 on Nav2's loopback
simulator with a camera drawn from the map, and a Panda in Gazebo with a wrist camera, a
head camera, MoveIt Servo, move_group and a gripper. The ROS 2 package is `ros/conduit_demo`.

One `Dockerfile` builds the image for each ROS 2 distribution the demo is offered on:
Jazzy, Kilted and Lyrical. There is no Humble image (its Zenoh wire format and its Servo
interface differ from what Conduit's arm view needs); a Rolling PC uses the Lyrical image.

## Modes

`docker run <image> <mode> [launch arguments...]` (`docker/demo/entrypoint.sh`):

| Mode | What runs | Network |
|---|---|---|
| `standalone` (default) | a Zenoh router on port 7447 in the container, then both robots (`demo.launch.py`) | publish 7447: `-p <host-port>:7447` |
| `join` | both robots on the PC's ROS 2 graph, after `check_conflicts`; no router, no ROS 2 daemon | `--network host` |
| `all` | the same as `standalone` | as `standalone` |
| `mobile` | the router, then the TurtleBot3 only (`mobile.launch.py`) | as `standalone` |
| `arm` | the router, then the Panda only (`arm.launch.py`) | as `standalone` |
| anything else | runs as a command with ROS 2 and the demo sourced, for example `bash` | |

`join` takes the PC's graph from the environment: `RMW_IMPLEMENTATION` (`rmw_zenoh_cpp`,
`rmw_cyclonedds_cpp` or `rmw_fastrtps_cpp`), `ROS_DOMAIN_ID`, and for Zenoh
`ZENOH_CONFIG_OVERRIDE='mode="client";connect/endpoints=["tcp/127.0.0.1:7447"]'` (the PC's
router), or `CYCLONEDDS_URI`. Its exit status: 3 when the graph already uses a name of the
demo (one `CONFLICT <name>` line each), 1 when it cannot join the graph (for example, no
router), otherwise the demo starts and `check_conflicts: no conflicts (…)` is in the log.

Launch arguments: `gpu:=true` raises both cameras to 640 x 480 at 15 Hz with full visuals
(needs a GPU in the container); the default light setting is 320 x 240 at 10 Hz, rendered in
software.

`docker stop -t 30 conduit-demo` stops it (the image's stop signal is SIGINT; the full demo
takes up to about 20 s to shut down). Gazebo's own transport stays in the container:
`GZ_PARTITION=conduit_demo` and `GZ_IP=127.0.0.1` are set in the image.

```bash
docker run -d --name conduit-demo -p 7447:7447 conduit-demo:lyrical-dev
docker run -d --name conduit-demo --network host -e RMW_IMPLEMENTATION=rmw_zenoh_cpp \
  -e ROS_DOMAIN_ID=0 \
  -e ZENOH_CONFIG_OVERRIDE='mode="client";connect/endpoints=["tcp/127.0.0.1:7447"]' \
  conduit-demo:jazzy-dev join
```

## Local build

From the repository root, for one distribution (`jazzy`, `kilted` or `lyrical`):

```bash
docker build -f docker/demo/Dockerfile --build-arg ROS_DISTRO=jazzy -t conduit-demo:jazzy-dev .
```

The images are about 5.4 GB (Jazzy, Kilted) and 7.3 GB (Lyrical); a first build takes
about 3 minutes on a fast connection. `docker buildx build --platform linux/arm64 …`
builds the arm64 image (natively on an Apple Silicon Mac).

## Checks

All in `ros/conduit_demo/scripts`, against a local image:

- `smoke_mobile.sh <image> <host-port> <domain>` and `smoke_arm.sh <image> <host-port>
  <domain>`: start the image in mode `mobile` or `arm` and check the robot's names, types,
  rates and actions. With `SMOKE_ROBOT_CONTAINER=<name>` they check a running demo
  container (any mode) through the router on `<host-port>` instead.
- `measure_arm.sh <image> <domain>`: Gazebo's real-time factor, both cameras' rates,
  `hold_clock_check.py` (Conduit's HOLD on the arm's clock) and `grasp_test.py` (10 grasps).
- Unit tests: `python3 -m pytest test` in `ros/conduit_demo`.

## Names and the conflict check

`conduit_demo/names.py` lists every name the demo uses: the union of what
`ros2 run conduit_demo check_conflicts --list` prints against a `standalone` run of each
distribution's image. When a distribution's packages change the names (Nav2's lifecycle
managers differ between Jazzy, Kilted and Lyrical, for example), list that image again
and merge the new names; `check_conflicts` against a `standalone` run must report every
listed name as a conflict.

## Distribution differences

The package names are the same on every distribution. What differs is handled where it
matters, with as little branching as possible:

| Difference | Jazzy | Kilted | Lyrical | Where |
|---|---|---|---|---|
| Gazebo | Harmonic | Ionic | Jetty | the vendor packages of `ros_gz`; the camera sensor sets both `frame_id` and `gz_frame_id` |
| Map server | started by the demo | started by the demo | `nav2_bringup` (`serve_static_map`) | `mobile.launch.py` |
| Loopback simulator | plain node | plain node | lifecycle node | `mobile.launch.py` |
| Nav2 `cmd_vel` | `Twist` | `TwistStamped` | `TwistStamped` | `mobile.launch.py` (`teleop_twist_joy`'s `publish_stamped_twist`) |
| Nav2 lifecycle managers | `lifecycle_manager_navigation`, `lifecycle_manager_map_server` | as Jazzy | `lifecycle_manager_nav2` | `names.py` (all of them) |
| GripperCommand controller | shipped (`gripper_controllers`), not used | none | none | `parallel_gripper_action_controller` behind the `gripper_command` relay on every distribution |

## Release

`.github/workflows/demo-image.yml` publishes the images to
`ghcr.io/youtalk/conduit-demo`:

- a pull request that touches the demo builds the Lyrical image for `linux/amd64`, without
  pushing;
- a tag `demo-v<version>` (or a manual run with that version) builds every distribution
  for `linux/amd64` and `linux/arm64` on native runners and publishes
  `<distro>-<version>`, which pair.sh pins, and `<distro>`.

```bash
git tag demo-v0.1.0 && git push origin demo-v0.1.0
```

A new GHCR package starts private: after the first publish, make `conduit-demo` public in
its package settings, so `docker pull` works without a login.
