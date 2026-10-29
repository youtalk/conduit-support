---
title: Teleoperate a robot arm
description: Move a MoveIt Servo arm with the motion of your iPhone or iPad, and send it to named poses through move_group.
---

# Teleoperate a robot arm

While you hold **HOLD**, the arm's end effector follows the motion of your iPhone or iPad:
Conduit turns ARKit's pose of the device into `geometry_msgs/TwistStamped` for MoveIt Servo
(`/servo_node/delta_twist_cmds` by default). A gripper arc works the gripper, and a pose menu
sends the arm to a named pose through MoveIt. On a Mac the arm view is
[view-only](#ipad-and-mac).

## Host setup

Arms need MoveIt Servo from Jazzy or later: the arm profile reads `moveit_msgs/ServoStatus` and
the overlay uses the `moveit_servo.` parameter namespace, which Humble's Servo publishes and
configures differently.

1. **Servo overlay.** Load `conduit_teleop`'s Servo overlay after your robot's own Servo
    parameters, so Servo takes speeds and keeps twists for 0.5 s. The
    [Servo overlay](#servo-overlay) section below shows the file and how to load it.

2. **Time sync.** Servo drops a twist whose stamp is older than `incoming_command_timeout` on its
    own clock, and it keeps moving on the last twist until then. Conduit therefore stamps every
    twist, moving or zero, on the robot's clock instead of the device's. It measures that clock
    from the profile's **Joint states** topic: the difference between each message's
    `header.stamp` and the time it arrives, taking the lowest-latency sample over the last 10 s,
    and it never stamps a twist ahead of the robot's real time. The 0.5 s stop when the link is
    lost then holds even when the device's clock differs from the host's, so neither chrony nor
    **Set Automatically** is needed for it. The requirements on the Joint states topic:

    - It must be stamped by the computer that runs Servo (the same clock Servo uses), and never
      in the future. Joint states published by another computer, such as a robot controller
      while Servo runs on a laptop, are measured as if they were Servo's clock, and Conduit
      cannot tell.
    - An empty **Joint states** field is saved as `/joint_states`. A namespaced topic, for
      example `/arm/joint_states`, must be in the field.
    - The host must run on wall-clock time. With simulation time (`use_sim_time`), HOLD cannot
      be used.

    HOLD is refused until the robot clock is known. The status line says why:

    | Message | Meaning |
    | --- | --- |
    | "Reading the robot clock from Joint states" | Conduit is still collecting stamps (it needs ten Joint states messages). |
    | "Robot and device clocks are more than a day apart (simulation time?). HOLD is off." | The stamps are not wall-clock time: simulation time, unstamped messages, or a clock that was never set. |
    | "Set Joint states in the profile. HOLD needs the robot clock." | The profile has no Joint states topic. |

    If the robot clock becomes unusable while HOLD is held (a simulator starts, say), the arm
    lets go and shows "Robot clock changed. Release and press again."

3. **Gripper (optional).** A `control_msgs/action/GripperCommand` server. The profile holds its
    action name (**Gripper action**) and, in its **Gripper** section, the open and closed
    positions in metres (**Open (m)**, **Closed (m)**; the Franka Panda's fingers travel from 0.0
    to 0.04). With **Gripper joint** set to the finger joint in Joint states, the arm view shows
    the opening the robot reports.

4. **Named poses (optional).** A `move_group` that publishes the SRDF on
    `/robot_description_semantic` and serves `/move_action`, and Servo's pause service. Conduit
    sends the moves itself, so there is nothing to install for them, and the profile needs nothing.
    See [Named poses](#named-poses).

When the arm view opens, Conduit calls the profile's **Servo command type** service
(`/servo_node/switch_command_type` by default) to switch Servo to `TWIST`, and retries every few
seconds while Servo is missing or refuses. The Servo chip shows the result: "Connecting to
Servo", "Servo not found", "Servo refused TWIST", then `TWIST`, or what Servo reports ("Slowing:
near singularity", "Halted: joint bound", …), and "Servo not responding" when no Servo status
has arrived for a second. HOLD stays off until Servo is ready.

## The arm view

The arm view runs the Device Pose sensor, which uses ARKit and needs the camera to itself, so
opening it pauses the enabled sensors that use the camera (the cameras, except the wide back
camera while LiDAR is on, whose images already come from ARKit) and Illuminance. When any of them
is enabled, Conduit asks first ("Opening <robot> pauses … while the arm view is open. Device Pose
uses ARKit, which needs the camera to itself. Continue?"). Closing the view restarts what it
paused and stops Device Pose if the view started it.

The wrist camera fills the screen behind the controls. Pinch it to scale between the whole image
and filling the screen, and drag to pan where the image is larger than the screen. Each layout
keeps its own zoom.

On iPhone the layout follows how you hold the phone; with the rotation lock on, it stays as it
is. Turning the phone releases HOLD and stops a gripper drag, and keeps the alignment. Closing the
view returns the app to portrait.

- **Landscape, two hands.** Along the top: the status chips and the status line, the
  [pose menu](#named-poses) and **Align**, then the gear and close. In the bottom corners, the
  gripper arc under one thumb and **HOLD** under the other. Without a Gripper action there is no
  arc, and HOLD sits in the bottom right corner. An iPad always uses this layout, in any
  orientation.
- **Upright, one hand.** Along the top: the status chips, the gear and close; under them the pose
  menu and **Align**. The status line sits above the bottom controls. HOLD is in the bottom corner
  under the thumb of the hand that holds the phone, with the gripper arc around it.

The status chips: Servo, motion tracking (only while it is not normal, for example "tracking
limited (excessive motion)" or "no tracking"), the wrist camera's latency and frame rate ("42 ms ·
30 fps") and, when the profile has a Diagnostics topic, the diagnostics. Tap the diagnostics chip
to open the diagnostics; this releases HOLD, stops a gripper drag and cancels a pose move.
The status line appears only when something needs saying: a fault, a refusal, why HOLD is off,
a pose move, or the free-time notice. The camera's captions (STALE, "No data", "No wrist camera
topic", …) and the warning that the profile expects other connection settings sit in the space
between the controls.

When the top row runs out of room (a smaller iPhone, larger text), the pose menu narrows (a long
pose name is cut at its end) down to the width of "Poses", then shows only its symbol, and last
Align shows only its symbol.

The gear's panel holds the settings that change the motion:

| setting | values | what it does |
| --- | --- | --- |
| **Max speed** | **0.5×**, **1×** (default), **2×** | Scales translation. At 1× the end effector moves at up to 0.25 m/s. |
| **Translation** | on (default) / off | Off sends no translation, so the end effector turns without moving. |
| **Rotation** | on (default) / off | Off sends no rotation. Rotation goes up to 1 rad/s. |
| **Gripper** | **Left thumb** (default) / **Right thumb** | Landscape, with a Gripper action: which bottom corner has the gripper arc; HOLD takes the other. |
| **Hand** | **Left hand** / **Right hand** (default) | Upright: the hand that holds the phone, which gets HOLD and the arc. |

Gripper and Hand are one choice: the hand that holds the phone upright is the one whose thumb has
HOLD in landscape. Conduit keeps it per robot on the device. Max speed, Translation and Rotation
start at their defaults each time the view opens. The panel is off while HOLD is held.

## Using it

1. **Align.** Stand behind the robot's base and face the way its base frame's +x axis points,
   which is the robot's forward direction. Point the back camera that way, or tilt the device down
   to watch the screen, down to lying flat with the top of the screen pointing that way, and tap
   **Align**: that heading becomes the base frame's +x. If you face the robot instead, the motion
   is mirrored. Align says why when it refuses: "Tilt the device down: the camera points too far
   up" (the camera points more than 60° above the horizon), "Point the top of the screen toward
   the robot's front" or "Wait for motion tracking, then Align". Align again after motion tracking
   restarts or fails ("Motion tracking restarted. Align again.", "Motion tracking failed. Align
   again.").
2. **Hold HOLD and move.** HOLD is dimmed until the link is up, Servo is ready, the robot clock
   is known and you have tapped Align. The status line says what it waits for ("Connecting…", a
   Servo problem, the robot clock, "Starting…"). A press when only Align is
   missing opens a "Tap Align first" dialog. A press also needs normal motion tracking, and is
   refused with "Waiting for motion tracking" or "Motion tracking is limited. Move the device
   slowly." without it. HOLD turns green and reads **HOLDING** while the arm follows.
3. **Release to stop.** Releasing HOLD sends three zero twists at once. Tracking loss, a covered
   camera, a pose jump or a lost link also stop the arm, with one zero twist ("The pose jumped.
   Release and press again.", "Motion tracking paused. Release and press again."); release and
   press again to resume.
4. **Gripper.** With HOLD released, tap the arc to open or close the gripper, or drag along it to
   set an opening. The readout along the arc says "40 % open" ("Moving · 40 % open" while a goal
   runs). The white handle is the opening asked for, and with a Gripper joint the track fills
   teal up to the opening the robot reports. Until the opening is known the readout says
   "Unknown: tap the arc": a drag sends nothing, and a tap opens. The gripper is off while HOLD
   is held ("Off while HOLD is held"), and a HOLD press while your thumb is on the gripper is
   refused with "Lift your thumb off the gripper first".

Without Conduit Plus, the status line shows the weekly free time's warnings for a few seconds
("30 minutes of free time left this week", "5 minutes left — the session stops when this week's
free time is used up"). When the free time is used up while you hold HOLD or a pose move runs,
the arm keeps going until you release HOLD and the move ends, for at most 5 more minutes. Then
Conduit stops the arm and shows the Conduit Plus paywall over the arm view; closing the paywall
closes the arm view.

**VoiceOver:** HOLD is the "Clutch" button: double-tap and hold to move the arm, and release to
stop. The gripper is the adjustable "Gripper opening": double-tap to open or close it, swipe up
or down to open or close it by 10 %, with Open and Close as actions. The wrist camera has "Show
whole image" and "Fill screen" actions.

Conduit also publishes the raw pose (`<namespace>/pose`, `/tf`) and `<namespace>/teleop/clutch`
(`std_msgs/Bool`, true while the clutch is held, false on any pose discontinuity), so a custom
consumer can move relative to the pose at engage time. The namespace is `conduit` unless you
changed it in Settings. The pose and `/tf` come from the Device Pose sensor, which runs while the
arm view is open.

## Named poses

The pose menu moves the arm to a **group state** of the robot's SRDF, such as `stand` or `home`,
through MoveIt. Conduit talks to `move_group` itself: a pick sends a `moveit_msgs/action/MoveGroup`
goal to `/move_action`, and Conduit pauses MoveIt Servo for the move. The host needs no extra node
and nothing to install for poses, and the robot profile has no pose settings. Named poses work on
Jazzy and later.

### The pose menu

The menu sits next to **Align** and lists every group state of the robot's arm group, in the order
the SRDF has them and with the names exactly as the SRDF writes them (`work`, `stand`, `ready`,
`home`, not "Work"). The pose the arm is at is checked.

- **The button** reads the name of the pose the arm is at, or "Poses" when it is at none of them.
  At a pose it is teal with a checkmark. While the arm moves to a pose, it shows a spinner and the
  name of the pose you picked. A name longer than the button is cut at its end.
- **Picking a pose** moves the arm there at once; there is no confirmation. Picking the pose the
  arm is already moving to does nothing. Picking another pose while the arm moves cancels that move
  and starts the new one once the cancel has ended.
- **The menu is off** (the button is dimmed and does not open) while HOLD is pressed or held, while
  the link is down, after the session stopped or the view failed to set up, and for 1 s after the
  set of poses changes (the SRDF arrived late, or a changed SRDF dropped or reordered a pose). The
  pause keeps a tap meant for Align from moving the arm. VoiceOver says why: "Off while HOLD is
  held.", "Off while the robot link is down.", "Off: the session stopped.", "The pose list just
  changed.".
- **No menu** appears without an SRDF that has states for the arm group. The menu appears as soon
  as the SRDF arrives. The Mac's view-only arm view has no menu.

The arm group is the `parent_group` of the SRDF's end effector. When several end effectors name
a parent group, the first whose group has states counts. Without an end effector, it is the first
group that is not an end effector's own group. The gripper's own states (such as `open` and
`closed`) are therefore not offered. The goals plan for that group. A state name that an SRDF
repeats is listed once and moves to the last state of that name, as in MoveIt; two names that
differ only in case are two poses.

Conduit reads the SRDF from `/robot_description_semantic` and sends goals to `/move_action`, both
absolute names. A `move_group` in a namespace publishes and serves them under that namespace, so the
arm view finds no poses and shows no menu.

### What a pick does

- **The goal** plans and executes a move of the arm group to the state's joint positions, read
  from the newest SRDF when the move starts: one joint constraint per joint of the state, at
  ±0.001 rad, from the arm's current state, with one planning attempt, 5 s planning time, and
  velocity and acceleration scaled to 0.2.
- **Servo** is paused before the goal and resumed when the move ends, whether it succeeds, fails or
  is cancelled. Conduit uses Servo's `std_srvs/srv/SetBool` pause service next to the profile's
  **Servo command type** service: `/servo_node/pause_servo` by default. While the move runs, the
  Servo chip reads "Servo paused for the pose move". Without the pause service, the move still
  runs. When the arm view connects, Conduit also resumes Servo, in case an earlier session left
  it paused.
- **The status line** reads "Moving to stand…" while the move runs. The checkmark comes from
  the profile's Joint states topic: the arm is at a pose when every joint of the state is within
  0.01 rad (metres for a prismatic joint) of it. Joints compare modulo a full turn, so a joint exactly one turn
  away from the SRDF value also counts as at the pose.
- **HOLD stops a pose move.** Pressing HOLD cancels the move ("Stopping the move to stand…"), and
  the press does not engage, even if you keep your finger down. Once the move has ended and
  Servo is resumed, usually well under a second later, the status line reads "Pose move
  stopped. Press HOLD again.": press HOLD again to move the arm. The arm stops where it is, so
  the button reads "Poses" until the arm reaches a pose.
- **The background, opening the diagnostics, closing the arm view and the free-time stop** cancel
  the move too, and resume Servo.
- **30 s after the pick** a move that has not ended is cancelled. When `move_group` does not end a
  cancel within 5 s, the arm view stops waiting for it.

!!! warning "Cancels need the link"
    Conduit cancels a move by sending the cancel to `move_group`, which only works while the link
    is up. A move running when Wi-Fi drops completes on the host. After the reconnect, the status
    line reads "Waiting for the move to stand to end…": HOLD stays off and Servo stays paused until
    the joint states show the arm still for a second (counted from 6 s after the pick, while
    `move_group` may still be planning), or 30 s after the pick. Then Conduit resumes Servo.

    If the app is killed and opened again while its move still runs, the new arm view knows
    nothing about that move: it resumes Servo when it connects and allows HOLD while the arm may
    still be moving. Keep the arm's own emergency stop within reach.

### Host side

1. Make `move_group` publish the SRDF. The `move_group.launch.py` and `demo.launch.py` that the
   MoveIt Setup Assistant generates do. A launch file that builds `move_group` from
   `MoveItConfigsBuilder` needs `.planning_scene_monitor(publish_robot_description_semantic=True)`,
   or the parameter `publish_robot_description_semantic: True` on the `move_group` node; it is
   off by default in Jazzy. Check it with:

    ```bash
    ros2 param get /move_group publish_robot_description_semantic   # Boolean value is: True
    ```

2. Check that `move_group` serves the `MoveGroup` action and that Servo has its pause service:

    ```bash
    ros2 action list | grep move_action           # /move_action
    ros2 service type /servo_node/pause_servo     # std_srvs/srv/SetBool
    ```

### When a pose move fails

The status line says what happened, until the next pick or HOLD press:

| Message | What to check |
| --- | --- |
| "move_group not found on /move_action" | `move_group` is not running, or runs in a namespace. |
| "move_group refused the move to stand" | `move_group` rejected the goal; check the `move_group` log on the host. |
| "move_group did not answer the move to stand" | `move_group` did not accept the goal, or end a cancel, within 5 s: it hangs or restarted. |
| "The move to stand failed: …" | Planning or execution failed; the rest is MoveIt's error code (see below) and, when `move_group` sends one, its own message after "MoveIt:". Without either, the line reads "The move to stand failed": check the `move_group` log on the host. |
| "move_group stopped the move to stand" | `move_group` cancelled the goal itself, for example because another client sent it a goal ("…: preempted (-7)"). |
| "The move to stand took over 30 s and was stopped" | The 30 s limit. A slow arm needs states closer together. |
| "stand is no longer in the SRDF" | A pick waited for a cancel while a new SRDF dropped that state. |
| "stand has no joint values in the SRDF" | The state names no joint with one number as its value. |
| "The move to stand was not sent: …" | Conduit could not send the goal, for example "Not connected to the robot". |
| "Waiting for the move to stand to end…" | The link dropped during the move (see above). |

The most useful MoveIt error codes, as the status line shows them after "The move to stand
failed:":

| Text | Code | What to do |
| --- | --- | --- |
| "planning failed (-1)" | `PLANNING_FAILED` | No path to the state within 5 s. Move the arm closer with HOLD, or check obstacles in the planning scene. |
| "the pose is in collision or outside the joint limits (-27)" | `GOAL_STATE_INVALID` | The group state itself is invalid. Fix it in the SRDF. |
| "the arm starts in collision (-10)" | `START_STATE_IN_COLLISION` | The arm is in collision where it is. Jog it clear with HOLD, then pick again. |
| "the controller failed (-4)" | `CONTROL_FAILED` | The trajectory controllers on the host refused or aborted the trajectory. Check that they are active (`ros2 control list_controllers`). |
| "timed out (-6)" | `TIMED_OUT` | Execution took longer than the controllers allow. Check the host's controllers. |
| "unknown planning group (-15)" | `INVALID_GROUP_NAME` | `move_group` has no group of the name the SRDF's arm group has: its MoveIt configuration is not the SRDF it publishes. |

Other codes read as their short text with the number, or "MoveIt error <code>".

If the checkmark does not appear after a move, the arm stopped further than 0.01 rad from the
state, or the Joint states topic does not carry every joint of the state
(`ros2 topic echo --once /joint_states --field name`).

### Example: poses that Servo can move from

Servo stops at a singularity ("Halted: singularity" on the Servo chip) and near the joint limits
("Halted: joint bound"). An arm's `ready` or `home` state can be singular, and then HOLD does
not move the arm after a pick of it. On the six-joint desk arm below (the Maker Arm), both are:
the Jacobian condition number at the gripper is 35.2 at `ready` and 42.2 at `home`, above Servo's
`hard_stop_singularity_threshold` of 30. Give the arm group states away from singularities and
joint limits, and list them first, so they are the first entries of the menu. On that arm, two
such states, `work` and `stand`, sit before `ready` and `home`:

```xml
<group_state name="work" group="arm">
    <joint name="link_002_joint" value="0"/>
    <joint name="link_003_joint" value="-0.95"/>
    <joint name="link_004_joint" value="1.2"/>
    <joint name="link_005_joint" value="-0.7"/>
    <joint name="link_006_joint" value="-0.1"/>
    <joint name="link_007_joint" value="0"/>
</group_state>
<group_state name="stand" group="arm">
    <joint name="link_002_joint" value="0"/>
    <joint name="link_003_joint" value="-1.6"/>
    <joint name="link_004_joint" value="1.6"/>
    <joint name="link_005_joint" value="-1.25"/>
    <joint name="link_006_joint" value="0"/>
    <joint name="link_007_joint" value="0"/>
</group_state>
```

That arm's menu lists `work`, `stand`, `ready` and `home`, in that order. The condition number is
25.4 at `work` and 21.7 at `stand`: between Servo's `lower_singularity_threshold` (17) and the
hard stop, so Servo moves along every axis and slows down near them. To check a state, pick it,
wait for the checkmark, hold HOLD and move the device along each axis: the Servo chip should say
`TWIST` or "Slowing: …", not "Halted: …". The values are the desk arm's, measured in simulation;
find your arm's with the arm in place, its joints well inside their limits plus Servo's
`joint_limit_margins`.

## iPad and Mac

An iPad drives the arm like an iPhone, always in the two-handed layout. iPadOS pauses ARKit while
Conduit shares the screen with other apps (Split View or a window); the tracking chip then reads
"Camera paused: use Conduit full screen", and HOLD stops working until Conduit is full screen
again. The diagnostics open in a sheet.

A Mac has no ARKit world tracking, so its arm view is view-only: the wrist camera (pinch and drag
work, and it opens on the whole image), the Servo status from the profile's **Servo status**
topic, and the diagnostics, with "Arm control needs an iPhone or iPad. This view shows the wrist
camera, Servo and diagnostics." There is no HOLD, gripper, Align or pose menu, and the view
pauses no sensors and does not start Device Pose.

## Servo overlay

`conduit_teleop` installs a MoveIt Servo parameter overlay at
`share/conduit_teleop/config/servo_overlay.yaml` (source:
[`ros/conduit_teleop/config/servo_overlay.yaml`](https://github.com/youtalk/conduit-support/blob/main/ros/conduit_teleop/config/servo_overlay.yaml)).
Build `conduit_teleop` as described in [Teleoperation](teleop.md) to get it.

```yaml
/**:
  ros__parameters:
    moveit_servo:
      incoming_command_timeout: 0.5
      command_in_type: "speed_units"
```

| parameter | value | what it does |
| --- | --- | --- |
| `moveit_servo.command_in_type` | `speed_units` | Servo reads the twist as m/s and rad/s, which is what Conduit sends (not unitless −1 … 1 commands). |
| `moveit_servo.incoming_command_timeout` | `0.5` | Servo drops a twist whose `header.stamp` is older than this on the host clock (default 0.1 s). Conduit stamps its twists on the robot's clock and they cross Wi-Fi, so 0.1 s drops many of them; 0.5 s keeps them, and a lost link stops the arm within about half a second (see Time sync above). Releasing the clutch stops the arm at once with explicit zero twists. |

The `/**` key applies the file to any node, so it works whatever your launch file names the
Servo node.

**Load it after your robot's own Servo parameters.** A node applies its parameter sources in
order, so the last one wins:

```python
from launch.substitutions import PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare

servo_node = Node(
    package="moveit_servo", executable="servo_node", name="servo_node",
    parameters=[servo_params, robot_description, robot_description_semantic,
                robot_description_kinematics,
                PathJoinSubstitution([FindPackageShare("conduit_teleop"), "config", "servo_overlay.yaml"])],
)
```

Check that it took effect (with your Servo node's name):

```bash
ros2 param get /servo_node moveit_servo.incoming_command_timeout   # Double value is: 0.5
ros2 param get /servo_node moveit_servo.command_in_type            # String value is: speed_units
```
