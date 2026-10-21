---
title: Teleoperate a robot arm
description: Move a MoveIt Servo arm with your iPhone's motion, and send it to named poses.
---

# Teleoperate a robot arm

Hold the iPhone in landscape with both hands. While one thumb holds **HOLD**, the arm's end
effector follows the phone's motion: Conduit turns ARKit's pose of the phone into
`geometry_msgs/TwistStamped` for MoveIt Servo (`/servo_node/delta_twist_cmds`). The other thumb
works the gripper, and a pose menu sends the arm to a named pose through MoveIt. iPad and Mac open
the arm view [read-only](#ipad-and-mac).

## Host setup

Arms need MoveIt Servo from Jazzy or later: the arm profile reads `moveit_msgs/ServoStatus` and
the overlay uses the `moveit_servo.` parameter namespace, which Humble's Servo publishes and
configures differently.

1. **Servo overlay.** Load `conduit_teleop`'s Servo overlay after your robot's own Servo
    parameters, so Servo takes speeds and keeps twists for 0.5 s. The
    [Servo overlay](#servo-overlay) section below shows the file and how to load it.

2. **Time sync.** Servo drops a twist whose stamp is older than `incoming_command_timeout` on its
    own clock, and it keeps moving on the last twist until then. Conduit therefore stamps every
    twist, moving or zero, on the robot's clock instead of the phone's. It measures that clock
    from the profile's **Joint states** topic: the difference between each message's
    `header.stamp` and the time it arrives, taking the lowest-latency sample over the last 10 s,
    and it never stamps a twist ahead of the robot's real time. The 0.5 s stop when the link is
    lost then holds even when the phone's clock differs from the host's, so neither chrony nor
    **Set Automatically** is needed for it. The requirements on the Joint states topic:

    - It must be stamped by the computer that runs Servo (the same clock Servo uses), and never
      in the future. Joint states published by another computer, such as a robot controller
      while Servo runs on a laptop, are measured as if they were Servo's clock, and Conduit
      cannot tell.
    - New arm profiles bind `/joint_states` by default. A namespaced topic, for example
      `/arm/joint_states`, must be typed into the **Joint states** slot.
    - The host must run on wall-clock time. With simulation time (`use_sim_time`), HOLD cannot
      be used.

    HOLD is refused until the robot clock is known. The arm view says why:

    | Message | Meaning |
    | --- | --- |
    | "Set Joint states in the profile. HOLD needs the robot clock." | No Joint states topic is bound. |
    | "Reading the robot clock from Joint states" | Conduit is still collecting stamps (it needs ten Joint states messages). |
    | "Robot and phone clocks are more than a day apart (simulation time?). HOLD is off." | The stamps are not wall-clock time: simulation time, unstamped messages, or a clock that was never set. |

    If the robot clock becomes unusable while HOLD is held (a simulator starts, say), the arm
    lets go and shows "Robot clock changed. Release and press again."

3. **Gripper (optional).** A `control_msgs/action/GripperCommand` server; the profile holds its
    action name (**Gripper action**) and the open and closed positions in metres (**Gripper open
    (m)**, **Gripper closed (m)**; the Franka Panda's fingers travel from 0.0 to 0.04). With
    **Gripper joint** (optional) set to the finger joint in Joint states, the arm view shows the
    opening the robot reports.

4. **Named poses (optional).** `conduit_teleop`'s named-pose node next to `move_group`, and a
    `move_group` that publishes the SRDF on `/robot_description_semantic`. The profile needs
    nothing for them. See [Named poses](#named-poses).

When the arm view opens, Conduit calls the profile's **Servo command type** service
(`/servo_node/switch_command_type` by default) to switch Servo to `TWIST`, and retries every few
seconds while Servo is missing or refuses. The status chip shows the result: "Connecting to
Servo", "Servo not found", "Servo refused TWIST", then `TWIST`, or what Servo reports ("Slowing:
near singularity", "Halted: joint bound", …), and "Servo not responding" when no Servo status
has arrived for a second. The clutch stays disabled until Servo is ready.

## The arm view

On iPhone the arm view is landscape, over the full-screen wrist camera. The screen turns to
landscape before the view comes up, either side, and stays there until you close the view;
closing it turns the screen back to portrait. The view runs the Device Pose sensor, which uses
ARKit and needs the camera to itself, so opening it pauses the enabled sensors that use the
camera (the cameras, except the wide back camera while LiDAR is on, whose images already come
from ARKit) and Illuminance. When any of them is enabled, Conduit asks first ("Opening <robot> pauses … while the
arm view is open. Device Pose uses ARKit, which needs the camera to itself. Continue?"). Closing
the view restarts what it paused and stops Device Pose if the view started it.

- **Top left:** the status chip (Servo · motion tracking · camera latency, for example
  "TWIST · tracking ok · 42 ms"), a warning chip when the profile expects other connection
  settings, and under them the status line. The status line says what to do next ("Point the
  phone at the robot's front, then tap Align", "Hold HOLD to move the arm", "Holding: the arm
  follows the phone") or what is wrong.
- **Top centre:** the [pose menu](#named-poses), then **Align**. Without a pose menu, only **Align**.
- **Top right:** **Joints**, which shows each joint's angle as a bar from −π to +π (the joint names
  shortened to their last part, "panda_joint4" → "joint4"); the gear, which opens the arm
  settings; and close.
- **Bottom corners:** the gripper under one thumb and **HOLD** under the other. The gripper starts
  under the left thumb; the gear's **Gripper** setting (**Left thumb** / **Right thumb**) moves
  it, and Conduit keeps that choice on the device for every arm. Without a Gripper action there
  is no gripper, and HOLD sits in the bottom right corner.

The camera's captions (STALE, "No data", "No wrist camera topic", …) sit in the space between.
When the top row runs out of room (a smaller iPhone, larger text), Joints shows only its symbol,
then the pose menu's button narrows (a long pose name is cut at its end) down to the width of
"Poses", then shows only its symbol, then the pose menu and Align move right of the centre, and
last Align shows only its symbol.

The gear's panel holds the settings that change the motion:

| setting | values | what it does |
| --- | --- | --- |
| **Scale** | **0.5×**, **1×** (default), **2×** | Scales translation. At 1× the end effector moves at up to 0.25 m/s. |
| **Rotation** | on (default) / off | Off sends no rotation. Rotation goes up to 1 rad/s. |
| **Gripper** | **Left thumb** (default) / **Right thumb** | Which bottom corner has the gripper; HOLD takes the other. Shown only with a Gripper action. |

The panel is off while HOLD is held.

## Using it

1. **Align.** Stand behind the robot's base and face the way its base frame's +x axis points,
   which is the robot's forward direction. Point the back camera that way, or tilt the phone down
   to watch the screen, down to lying flat with the top of the screen pointing that way, and tap
   **Align**: that heading becomes the base frame's +x. If you face the robot instead, the motion
   is mirrored. Align says why when it refuses: "Tilt the phone down: the camera points too far
   up" (the camera points more than 60° above the horizon), "Point the top of the screen toward
   the robot's front", "Wait for motion tracking, then Align" or "Release the clutch to Align".
   Align again after motion tracking restarts or fails ("Motion tracking restarted. Align again.").
2. **Hold HOLD and move.** HOLD is dimmed until the link is up, Servo is ready, the robot clock
   is known and you have tapped Align; the status line says which one is missing. A press also
   needs normal motion tracking, and is refused with "Waiting for motion tracking" or "Motion
   tracking is limited. Move the phone slowly." without it. HOLD turns green and reads
   **HOLDING** while the arm follows.
3. **Release to stop.** Releasing HOLD sends three zero twists at once. Tracking loss, a covered
   camera, a pose jump or a lost link also stop the arm, with one zero twist ("The pose jumped.
   Release and press again.", "Motion tracking paused. Release and press again."); release and
   press again to resume.
4. **Gripper.** With HOLD released, drag along the arc or tap **Open** / **Close**. The readout
   says "Gripper · 40 % open" (or "Moving · …" while a goal runs); the white handle is the opening
   asked for, and with a Gripper joint the teal stripe is the opening the robot reports. Until the
   opening is known the readout says "Opening unknown: tap Open or Close" and a drag sends
   nothing. The gripper is off while HOLD is held, and a HOLD press while your thumb is on the
   gripper is refused with "Lift your thumb off the gripper first".

Without Conduit Plus, the status line shows the weekly free time's warnings for a few seconds
("30 minutes of free time left this week", "5 minutes left — the session stops when this week's
free time is used up"). When the free time is used up while you hold HOLD, the arm keeps
following until you release it, for at most 5 more minutes. Then Conduit stops the arm, closes
the arm view and shows the Conduit Plus paywall.

**VoiceOver:** HOLD is the "Clutch" button: double-tap and hold to move the arm, and release to
stop. The gripper is the adjustable "Gripper opening": swipe up or down to open or close it by
10 %, with Open and Close as actions.

Conduit also publishes the raw pose (`<namespace>/pose`, `/tf`) and `<namespace>/teleop/clutch`
(`std_msgs/Bool`, true while the clutch is held, false on any pose discontinuity), so a custom
consumer can move relative to the pose at engage time. The namespace is `conduit` unless you
changed it in Settings. The pose and `/tf` come from the Device Pose sensor, which runs while the
arm view is open.

## Named poses

The pose menu moves the arm to a **group state** of the robot's SRDF, such as `stand` or `home`,
through MoveIt. Picking a pose sends the state's name once, as `std_msgs/String`, on
`<namespace>/teleop/named_pose` (`/conduit/teleop/named_pose` by default). On the robot computer,
`conduit_teleop`'s named-pose node plans and runs the move with `move_group` and reports the pose
the arm is at on `<namespace>/teleop/named_pose_state`. Those two topics are fixed: the robot
profile has no pose settings, and a pose list saved by an earlier build is ignored. The namespace
is `conduit` unless you changed it in Settings. The node's setup, parameters and troubleshooting
are in [Teleoperation → Named poses](teleop.md#named-poses).

### The pose menu

The menu sits next to **Align** and lists every group state of the robot's arm group, in the order
the SRDF has them and with the names exactly as the SRDF writes them (`work`, `stand`, `ready`,
`home`, not "Work"). The pose the arm is at is checked.

- **The button** reads the name of the pose the arm is at, or "Poses" when it is at none of them.
  At a pose it is teal with a checkmark. While the arm moves to a pose, it shows a spinner and the
  name of the pose you picked. A name longer than the button is cut at its end.
- **Picking a pose** moves the arm there at once; there is no confirmation. Picking the checked
  pose does nothing, and so does picking the pose the arm is already moving to. Picking another
  pose while the arm moves replaces the move.
- **The menu is off** (the button is dimmed and does not open) while HOLD is pressed or held, while
  the link is down, after the session stopped or the view failed to set up, and for 1 s after the
  set of poses changes (the SRDF or the named-pose node arrived late, or a changed SRDF dropped or
  reordered a pose). The pause keeps a tap meant for Align from moving the arm. VoiceOver says why:
  "Off while HOLD is held.", "Off while the robot link is down.", "Off: the session stopped.",
  "The pose list just changed.".
- **No menu** appears without an SRDF that has states for the arm group, or until Conduit sees the
  named-pose node (a publisher on the **named_pose_state** topic). A MoveIt arm without the node
  therefore shows no poses that nothing would answer. The iPad and Mac views have no menu.
- **"Named poses unavailable"** takes the menu's place (or a warning symbol, where the row is
  tight) when Conduit could not create the pose command publisher.

The arm group is the `parent_group` of the SRDF's end effector. When several end effectors name
a parent group, the first whose group has states counts. Without an end effector, it is the first
group that is not an end effector's own group. The gripper's own states (such as `open` and
`closed`) are therefore not offered. Start the named-pose node with that group as its
`planning_group`. A state name that an SRDF repeats exactly is listed once; two names that differ
only in case are two poses.

Conduit reads the SRDF from `/robot_description_semantic` only, which `move_group` publishes. A
`move_group` in a namespace publishes it under that namespace, so the arm view finds no poses
and shows no menu.

### What a pick does

- The node pauses MoveIt Servo, moves the arm with `move_group`, and resumes Servo when the move
  ends, whether it succeeds, fails or is cancelled.
- The status line reads "Moving to stand…" until the node reports the arm there; then the button
  turns teal with the checkmark.
- Servo publishes no status while it is paused, so during a move the status chip reads "Servo not
  responding". It returns to `TWIST` when the move ends.
- **HOLD stops a pose move.** Conduit sends the clutch on `<namespace>/teleop/clutch`
  (`/conduit/teleop/clutch` by default) and repeats it at 10 Hz while the arm view is open. When
  you press HOLD, the named-pose node cancels the move and resumes Servo as soon as `move_group`
  has ended the cancel (usually well under a second; the node waits at most 5 s), so the arm
  follows the phone again right away. Conduit ends the spinner when you press HOLD. The arm stops
  where it is, so the button reads "Poses" until the arm reaches a pose.
- **A lost link, the background or closing the arm view stops it too.** In each case the clutch
  messages stop, and the node cancels the move after `clutch_timeout` (0.5 s by default) without
  one and resumes Servo. This works for a move that started while clutch messages were arriving,
  as every pick from Conduit does.
- The 30 s limit below only ends the spinner. The clutch messages keep coming then, so the node
  goes on with the move until it ends or the node gives it up after `planning_time` +
  `max_move_duration` (65 s by default). Keep the arm's own emergency stop within reach.
- When nothing has ever arrived on the state topic 3 s after a pick, the status line says "No
  answer from the named-pose node on /conduit/teleop/named_pose_state" (with your state topic):
  check the node and the topics. The arm view stops waiting for a pose after 30 s.

### Host side

1. Make `move_group` publish the SRDF. The `move_group.launch.py` and `demo.launch.py` that the
   MoveIt Setup Assistant generates do. A launch file that builds `move_group` from
   `MoveItConfigsBuilder` needs `.planning_scene_monitor(publish_robot_description_semantic=True)`,
   or the parameter `publish_robot_description_semantic: True` on the `move_group` node; it is
   off by default in Jazzy. Check it with:

    ```bash
    ros2 param get /move_group publish_robot_description_semantic   # Boolean value is: True
    ```

2. Start the named-pose node with the arm's planning group:

    ```bash
    ros2 launch conduit_teleop named_pose.launch.py planning_group:=arm
    ```

### Example: poses that Servo can move from

Servo stops at a singularity ("Halted: singularity" on the status chip) and near the joint limits
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
wait for the checkmark, hold HOLD and move the phone along each axis: the status chip should say
`TWIST` or "Slowing: …", not "Halted: …". The values are the desk arm's, measured in simulation;
find your arm's with the arm in place, its joints well inside their limits plus Servo's
`joint_limit_margins`.

## iPad and Mac

iPad and Mac show the arm view read-only: the wrist camera, the Servo status from the profile's
Servo status topic, and the joints, with "Arm control needs an iPhone. This view shows the wrist
camera, the joints and the Servo status." There is no HOLD, gripper, Align or pose menu, and the
view pauses no sensors and does not start Device Pose.

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
