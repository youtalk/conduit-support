---
title: Teleoperation with a game controller
description: Drive a ROS 2 robot from a game controller paired with your iPhone, iPad or Mac, through teleop_twist_joy and a watchdog that stops the robot when the link drops.
---

# Teleoperation with a game controller

!!! note "Requires Conduit 2.5 or later"
    The Joy layout and the setup on this page need **Conduit 2.5 or later**. Settings → **About & Help** shows your version. Conduit 2.4 and earlier publish an older Joy layout with Best Effort QoS (see the next box).

Conduit's **Game Controller** sensor publishes `sensor_msgs/msg/Joy` from any controller paired with your iPhone, iPad or Mac (Xbox, PlayStation, MFi). It publishes on **`/conduit/joy`**: the sensor's topic is `joy`, under Conduit's namespace, which is `conduit` unless you changed Settings → **Namespace** (then it is `/<namespace>/joy`). That is why the commands below pass `joy_topic:=/conduit/joy`. On the robot, [`teleop_twist_joy`](https://github.com/ros2/teleop_twist_joy) turns the Joy messages into velocity commands. This page sets that up with **`conduit_teleop`**, a ROS 2 package in this repository.

!!! warning "Conduit 2.5 changes the Joy message to the ROS 2 `joy` layout"
    From Conduit 2.5, Game Controller publishes `Joy` exactly like the ROS 2 `joy` package's `game_controller_node`. Compared with Conduit 2.4 and earlier:

    - **Stick X axes:** left is now **+1** (it was −1). The Y axes are unchanged (up = +1).
    - **Triggers:** **0** when released and **−1** when fully pressed. They were 0 … +1.
    - **D-pad:** moved from `axes[6]` / `axes[7]` to `buttons[11]`–`buttons[14]`. `axes` now has 6 entries.
    - **Buttons:** follow the SDL order in the table below. `buttons` has 21 entries.
    - **QoS:** **Reliable** by default, which `teleop_twist_joy` needs. If you saved **Best Effort** for the Game Controller in an earlier version, Conduit switches it to Reliable once. You can set it back in the sensor's settings.

    If your robot remaps axes or inverts signs to make an earlier Conduit drive correctly, **remove that remapping**. Otherwise the robot turns the wrong way.

## Joy layout

The layout is the one that `game_controller_node` publishes in ROS 2 Jazzy (`joy` 3.3.0).

| index | `axes[i]` | value |
| --- | --- | --- |
| 0 | left stick, left / right | left = +1, right = −1 |
| 1 | left stick, up / down | up = +1, down = −1 |
| 2 | right stick, left / right | left = +1, right = −1 |
| 3 | right stick, up / down | up = +1, down = −1 |
| 4 | left trigger | released 0, fully pressed −1 |
| 5 | right trigger | released 0, fully pressed −1 |

| index | `buttons[i]` | Xbox | PlayStation |
| --- | --- | --- | --- |
| 0 | A | A | Cross |
| 1 | B | B | Circle |
| 2 | X | X | Square |
| 3 | Y | Y | Triangle |
| 4 | Back | View | Share / Create |
| 5 | Guide | Xbox button | PS button |
| 6 | Start | Menu | Options |
| 7 | Left stick press | LS | L3 |
| 8 | Right stick press | RS | R3 |
| 9 | Left shoulder | LB | L1 |
| 10 | Right shoulder | RB | R1 |
| 11–14 | D-pad up, down, left, right | | |
| 15–20 | always 0 | | |

A Siri Remote (Apple TV remote) sends its touch surface as the left stick (`axes[0]`, `axes[1]`), and its A, X and Menu buttons as `buttons[0]`, `buttons[2]` and `buttons[6]`.

Conduit publishes Joy at 50 Hz while a controller is connected, and stops when the controller disconnects.

## Host setup with `conduit_teleop`

```text
/conduit/joy ──► teleop_twist_joy ──► cmd_vel_in ──► joy_watchdog ──► /cmd_vel
      │                                                   ▲
      └──────────────── Joy freshness ────────────────────┘
```

- **`teleop_twist_joy`** uses `config/teleop_twist_joy.yaml`, or the file you pass as `params_file`. Hold **LB / L1** (`buttons[9]`) to drive. The left stick's up / down sets `linear.x` and its left / right sets `angular.z`. Releasing LB sends one zero twist. Turbo is off, because `teleop_twist_joy` checks the turbo button before the deadman, so a turbo button would drive the robot without LB held.
- **`joy_watchdog`** forwards the twist while the newest Joy is younger than 0.5 s. When Joy stops arriving, it publishes a zero twist at 10 Hz for 1 s and then goes quiet until Joy comes back. That happens when Wi-Fi drops, the controller disconnects, or Conduit goes to the background. `teleop_twist_joy` alone would leave a robot that keeps its last command moving.

### Install (ROS 2 Jazzy)

```bash
sudo apt install ros-jazzy-teleop-twist-joy
mkdir -p ~/conduit_ws/src
git clone https://github.com/youtalk/conduit-support.git ~/conduit_ws/src/conduit-support
cd ~/conduit_ws
source /opt/ros/jazzy/setup.bash
colcon build --packages-select conduit_teleop
source install/setup.bash
```

### Run

```bash
ros2 launch conduit_teleop conduit_teleop.launch.py joy_topic:=/conduit/joy
```

| argument | default | meaning |
| --- | --- | --- |
| `joy_topic` | `/joy` | Joy input. The Game Controller sensor publishes `/conduit/joy` (namespace `conduit`), so pass `joy_topic:=/conduit/joy`, or `/<namespace>/joy` if you changed the namespace. |
| `cmd_vel_topic` | `/cmd_vel` | Where the robot listens for `geometry_msgs/Twist`. |
| `params_file` | the package's `config/teleop_twist_joy.yaml` | The `teleop_twist_joy` parameter file. It replaces the shipped file, so start from a copy of it. |

At full stick the robot drives at 0.5 m/s and turns at 1.0 rad/s. To change that for your robot, copy the shipped file, change `scale_linear.x` and `scale_angular.yaw` in the copy, and pass it as `params_file`:

```bash
cp ~/conduit_ws/src/conduit-support/ros/conduit_teleop/config/teleop_twist_joy.yaml ~/my_robot_teleop.yaml
ros2 launch conduit_teleop conduit_teleop.launch.py joy_topic:=/conduit/joy params_file:=$HOME/my_robot_teleop.yaml
```

Keep the rest of the copy as it is, including the `teleop_twist_joy_node:` key. A parameter the file leaves out falls back to `teleop_twist_joy`'s own default, which is not this layout (its default deadman is `buttons[5]`). To try a speed without restarting, `ros2 param set /teleop_twist_joy_node scale_linear.x 0.3` changes the running node.

| `joy_watchdog` parameter | default | meaning |
| --- | --- | --- |
| `timeout` | `0.5` | Seconds without a Joy before the watchdog takes over. |
| `zero_rate_hz` | `10.0` | Rate of the zero twist once Joy is stale. |
| `zero_duration` | `1.0` | Seconds of zero twists after Joy goes stale; then the watchdog is silent until Joy comes back. |

!!! note "Sharing `cmd_vel_topic` with Nav2 or another teleop"
    `joy_watchdog` publishes only while you drive and for 1 s after Joy stops, so it does not keep overriding another node once you let go. While you drive, both would publish to the same topic, so for a robot that also runs Nav2 or a second teleop, feed both into [`twist_mux`](https://github.com/ros-teleop/twist_mux) and use the mux input as `cmd_vel_topic`.

!!! danger "Not an emergency stop"
    Neither Conduit nor `conduit_teleop` is a safety system. Keep the robot's own emergency stop within reach.

## Named poses

When you drive a MoveIt arm from Conduit, Conduit streams velocity commands (`TwistStamped`) to [MoveIt Servo](https://moveit.picknik.ai/main/doc/examples/realtime_servo/realtime_servo_tutorial.html) while you hold the clutch (**HOLD**). Conduit also has pose buttons. Each tap sends the name of a **group state** from the robot's SRDF, such as `ready` or `home`. Conduit sends a tap only while the clutch is released. The host node **`conduit_named_pose`** (executable `named_pose_node` in `conduit_teleop`) receives the name and moves the arm there through `move_group`.

```text
pose button ──► /conduit/teleop/named_pose ──► conduit_named_pose ──► move_group (MoveGroup action)
HOLD ─────────► /conduit/teleop/clutch ─────────────►│  ▲
                        pause / resume MoveIt Servo ◄┘  └── /joint_states, /robot_description_semantic
Conduit ◄── /conduit/teleop/named_pose_state ◄───────┘
```

| topic | type | direction | meaning |
| --- | --- | --- | --- |
| `/conduit/teleop/named_pose` | `std_msgs/msg/String` | Conduit → host | One message per tap. `data` is an SRDF `group_state` name of the planning group. |
| `/conduit/teleop/named_pose_state` | `std_msgs/msg/String` | host → Conduit | The group state the arm is at, or `""` while it moves or when it is at none of them. Latched: Reliable, Transient Local, depth 1. |
| `/conduit/teleop/clutch` | `std_msgs/msg/Bool` | Conduit → host | `true` while you hold HOLD, `false` when you let go. Conduit repeats it at 10 Hz as a heartbeat while the arm view is open. Reliable, Volatile. |

All three topics are under Conduit's namespace (`conduit` by default, Settings → **Namespace**).

What the node does:

- It reads the group states from `/robot_description_semantic` (the SRDF that `move_group` publishes), the joint positions from `/joint_states`, and the continuous joints from `/robot_description` (the URDF).
- **A known name:** it pauses Servo (`/servo_node/pause_servo`), publishes `""` on the state topic, and sends a `MoveGroup` goal that plans and executes a move to that state's joint positions. When the move ends, whether it succeeds, fails or is cancelled, it resumes Servo.
- **A tap during a move:** it cancels the move and starts the new one once the cancel has finished. Servo stays paused across the change and is resumed when the last move ends. A second tap on the button of the move that is running is ignored, so a double tap does not stop and restart the arm.
- **HOLD during a move:** a clutch `true` cancels the move, and a tap that waits for a cancel is dropped. The arm is to follow the phone now, so Servo is resumed as soon as the move has ended, and the state topic goes back to the group state the arm is at, or `""`. Conduit stops waiting for the pose when you press HOLD.
- **The heartbeat stops during a move:** if clutch messages were arriving when the move started, the node cancels the move once none has arrived for `clutch_timeout` (0.5 s, about five missed heartbeats). Conduit stops the heartbeat when the link drops or when the app goes to the background or closes. A move started without clutch messages, for example from `ros2 topic pub`, does not depend on the heartbeat.
- **A tap while HOLD is held** (the last clutch message was `true`, within `clutch_timeout`): the node logs a warning and ignores it. Conduit does not send one.
- **An unknown name**, or a group state of another planning group: it logs a warning and does nothing else.
- **The state topic:** while no move runs, the node compares `/joint_states` with each group state, in SRDF order, and publishes the first one that every joint matches within `tolerance`. A continuous joint matches its value plus any number of whole turns, as in MoveIt. It publishes only when the value changes.
- **No Servo:** if the pause service does not appear or answer within `service_timeout`, the node logs a warning and moves the arm anyway.
- **`move_group` stops answering:** the node gives a move up and resumes Servo if the `MoveGroup` action server goes away during the move, if `move_group` does not accept the goal or finish a cancel within 5 s, or if the move takes longer than `planning_time` + `max_move_duration`. It also sends a cancel, in case `move_group` is still there. When `move_group` crashes, the middleware can take up to about 20 s to notice that the server is gone; a tap in that time gives the move up after 5 s.
- **Shutdown** (Ctrl-C or SIGTERM): it cancels the running move, including one that `move_group` has not accepted yet, and resumes Servo.

### Run next to `move_group` and Servo

The node needs a running `move_group` with the robot's MoveIt configuration, and that `move_group` must publish the SRDF on `/robot_description_semantic`. The `move_group.launch.py` and `demo.launch.py` that the MoveIt Setup Assistant generates do that (through `moveit_configs_utils`' `generate_move_group_launch`). If you start `move_group` yourself with parameters from `MoveItConfigsBuilder`, add `.planning_scene_monitor(publish_robot_description_semantic=True)`. Servo is optional.

Install `moveit_msgs` (it also comes with MoveIt), and build `conduit_teleop` as in [Install](#install-ros-2-jazzy):

```bash
sudo apt install ros-jazzy-moveit-msgs
```

Start your robot's `move_group` and Servo, then:

```bash
ros2 launch conduit_teleop named_pose.launch.py planning_group:=arm
```

| argument | default | meaning |
| --- | --- | --- |
| `planning_group` | `arm` | The MoveIt planning group. Its SRDF group states are the names the buttons send. |
| `command_topic` | `/conduit/teleop/named_pose` | Where Conduit sends the names; `/<namespace>/teleop/named_pose` if you changed the namespace. |
| `state_topic` | `/conduit/teleop/named_pose_state` | Where the node reports the state; `/<namespace>/teleop/named_pose_state` if you changed the namespace. |
| `move_action` | `move_action` | `move_group`'s `moveit_msgs/action/MoveGroup` action. |
| `servo_pause_service` | `/servo_node/pause_servo` | MoveIt Servo's `std_srvs/srv/SetBool` pause service (ROS 2 Jazzy). Change it if your Servo node has another name. |
| `clutch_topic` | `/conduit/teleop/clutch` | Conduit's HOLD clutch; `/<namespace>/teleop/clutch` if you changed the namespace. |
| `velocity_scaling` | `0.2` | `max_velocity_scaling_factor` of each move, in (0, 1]. |
| `acceleration_scaling` | `0.2` | `max_acceleration_scaling_factor` of each move, in (0, 1]. |
| `tolerance` | `0.01` | Radians (meters for a prismatic joint). A joint within this of a group state's value counts as at it. Moves aim at a tenth of it. |
| `planning_time` | `5.0` | Seconds the planner may take. |
| `service_timeout` | `1.0` | Seconds to wait for the Servo pause service and the `MoveGroup` action server to appear, and for Servo to answer a pause request. |
| `max_move_duration` | `60.0` | Seconds a move may execute after `planning_time` before the node gives it up. |
| `clutch_timeout` | `0.5` | Seconds without a clutch message after which a move that started while clutch messages were arriving is cancelled. |

The launch arguments set the node's parameters of the same names. Without the launch file:

```bash
ros2 run conduit_teleop named_pose_node --ros-args -p planning_group:=arm -p velocity_scaling:=0.1
```

To try it without the phone:

```bash
ros2 topic echo /conduit/teleop/named_pose_state std_msgs/msg/String \
  --qos-durability transient_local --qos-reliability reliable
ros2 topic pub --once /conduit/teleop/named_pose std_msgs/msg/String "{data: ready}"
```

The state turns `""` when the move starts and `ready` when the arm gets there. With no clutch messages, the move does not depend on the heartbeat. To stop it as HOLD would:

```bash
ros2 topic pub --once /conduit/teleop/clutch std_msgs/msg/Bool "{data: true}"
```

Troubleshooting:

- **`Ignoring named pose: unknown group state`.** The name is not a group state of `planning_group`. The warning lists the names it knows. Check `planning_group` and the SRDF's `<group_state name="…" group="…">` entries.
- **`no group states known for the planning group`.** No SRDF has arrived. Check that `ros2 topic echo --once /robot_description_semantic --qos-durability transient_local` prints it; if not, make `move_group` publish it (see above).
- **`MoveGroup action move_action is not available`.** `move_group` is not running, or runs in another namespace; set `move_action`.
- **The state stays `""` after a move.** The arm stopped further than `tolerance` from the group state, for example because a controller stops short. Raise `tolerance`. Also check that `/joint_states` carries every joint of the group state (`ros2 topic echo --once /joint_states --field name`).
- **`HOLD engaged: clutch true: stopping the move to 'ready'`.** You pressed HOLD during the move, so the node cancelled it. Release HOLD and tap the pose again.
- **`clutch heartbeat lost: …: stopping the move to 'ready'`.** Conduit's clutch messages stopped during the move: the link dropped, or the app went to the background or closed. If it happens while the app is open and connected, check the link, or raise `clutch_timeout`.
- **`Ignoring named pose: 'ready' arrived while HOLD is engaged`.** A pose name arrived while the last clutch message was `true`. Check that nothing else publishes on the clutch or pose topics.
- **`Move to 'ready' lost move_group`**, or **`got no answer from move_group`.** `move_group` died, restarted or hangs. Servo has been resumed; restart `move_group` and tap again.
- **A move aborts with `MoveIt error code -27`** (`GOAL_STATE_INVALID`). The group state is in collision or outside the joint limits. Fix it in the SRDF.

## Troubleshooting

- **Nothing on `/cmd_vel` while you hold LB, and `ros2 topic hz /conduit/joy` shows nothing.** No Joy reaches the host. Check the topic name (`ros2 topic list | grep joy`), the domain ID and the transport.
- **The robot turns the wrong way.** Remove any axis inversion you set up for Conduit 2.4 or earlier.
- **Nothing on `/cmd_vel` although Joy arrives.** Hold LB (`buttons[9]`). Check `ros2 topic echo /conduit/joy --field buttons` while you press it.
- **Over DDS, nothing on `/cmd_vel` although `ros2 topic hz /conduit/joy` shows Joy.** Over DDS (`rmw_cyclonedds_cpp`) a Best Effort Joy does not match `teleop_twist_joy`'s Reliable subscription; keep the Game Controller sensor on Reliable. `ros2 topic info -v /conduit/joy` shows the publisher's reliability. Conduit 2.4 and earlier published Best Effort.
