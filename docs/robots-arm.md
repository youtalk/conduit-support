---
title: Teleoperate a robot arm
description: Move a MoveIt Servo arm with your iPhone's motion, and send it to named poses.
---

# Teleoperate a robot arm

Hold the iPhone in landscape with both hands. While one thumb holds **HOLD**, the arm's end
effector follows the phone's motion: Conduit turns ARKit's pose of the phone into
`geometry_msgs/TwistStamped` for MoveIt Servo (`/servo_node/delta_twist_cmds`). The other thumb
works the gripper, and pose buttons send the arm to named poses through MoveIt. iPad and Mac open
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
   `move_group` that publishes the SRDF on `/robot_description_semantic`. See
   [Named poses](#named-poses).

When the arm view opens, Conduit calls the profile's **Servo command type** service
(`/servo_node/switch_command_type` by default) to switch Servo to `TWIST`, and retries every few
seconds while Servo is missing or refuses. The status chip shows the result: "Connecting to
Servo", "Servo not found", "Servo refused TWIST", then `TWIST`, or what Servo reports ("Slowing:
near singularity", "Halted: joint bound", …), and "Servo not responding" when no Servo status
has arrived for a second. The clutch stays disabled until Servo is ready.

## The arm view

On iPhone the arm view is landscape, over the full-screen wrist camera. The screen turns to
landscape before the view comes up, either side, and stays there until you close the view.
Opening it pauses the camera sensors and Illuminance, which Conduit asks about first ("Opening
<robot> pauses … while the arm view is open. Device Pose uses ARKit, which needs the camera to
itself. Continue?"), and runs the Device Pose sensor. Closing it restarts what it paused and stops
Device Pose if the view started it.

- **Top left:** the status chip (Servo · motion tracking · camera latency, for example
  "TWIST · tracking ok · 42 ms"), a warning chip when the profile expects other connection
  settings, and under them the status line. The status line says what to do next ("Point the
  phone at the robot's front, then tap Align", "Hold HOLD to move the arm", "Holding: the arm
  follows the phone") or what is wrong.
- **Top centre:** the [pose buttons](#named-poses), then **Align**.
- **Top right:** **Joints**, which shows each joint's angle as a bar from −π to +π (the joint names
  shortened to their last part, "panda_joint4" → "joint4"); the gear, which opens the arm
  settings; and close.
- **Bottom corners:** the gripper under one thumb and **HOLD** under the other. The gripper starts
  under the left thumb; the gear's **Gripper** setting (**Left thumb** / **Right thumb**) moves
  it, and Conduit keeps that choice on the device for every arm. Without a Gripper action there
  is no gripper.

The camera's captions (STALE, "No data", "No wrist camera topic", …) sit in the space between.
When the top row runs out of room (a smaller iPhone, larger text), Joints shows only its symbol,
then the pose buttons show their numbers (1 to 4) in place of their titles, and last Align shows
only its symbol.

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
2. **Hold HOLD and move.** HOLD turns green and reads **HOLDING** while the arm follows.
3. **Release to stop.** Conduit sends zero twists three times. Tracking loss, a covered camera or
   a pose jump also stop the arm ("The pose jumped. Release and press again.", "Motion tracking
   paused. Release and press again."); release and press again to resume.
4. **Gripper.** With HOLD released, drag along the arc or tap **Open** / **Close**. The readout
   says "Gripper · 40 % open" (or "Moving · …" while a goal runs); the white handle is the opening
   asked for, and with a Gripper joint the teal stripe is the opening the robot reports. Until the
   opening is known the readout says "Opening unknown: tap Open or Close" and a drag sends
   nothing. The gripper is off while HOLD is held, and a HOLD press while your thumb is on the
   gripper is refused with "Lift your thumb off the gripper first".

**VoiceOver:** HOLD is the "Clutch" button: double-tap and hold to move the arm, and release to
stop. The gripper is the adjustable "Gripper opening": swipe up or down to open or close it by
10 %, with Open and Close as actions.

Conduit also publishes the raw pose (`<namespace>/pose`, `/tf`) and `<namespace>/teleop/clutch`
(`std_msgs/Bool`, true while the clutch is held, false on any pose discontinuity), so a custom
consumer can move relative to the pose at engage time. The namespace is `conduit` unless you
changed it in Settings. The pose and `/tf` come from the Device Pose sensor, which runs while the
arm view is open.

## Named poses

A pose button moves the arm to a **group state** of the robot's SRDF, such as `ready` or `home`,
through MoveIt. A tap sends the state's name once, as `std_msgs/String`, on
`<namespace>/teleop/named_pose` (`/conduit/teleop/named_pose` by default). On the robot computer,
`conduit_teleop`'s named-pose node plans and runs the move with `move_group` and reports the pose
the arm is at on `<namespace>/teleop/named_pose_state`. Its setup, parameters and troubleshooting
are in [Teleoperation → Named poses](teleop.md#named-poses).

### Which buttons the arm view shows

The arm view shows up to four pose buttons:

- **The profile's list.** The arm profile's **Named poses** section takes up to four poses. Each has
  the group state's name (letters, digits and underscores, as in the SRDF) and an optional button
  title. Without a title the button shows the name capitalized, with spaces for underscores
  (`fold` → "Fold"), and `ready` shows "Home". **Reorder poses** sets the button order. **Named
  pose command** and **Named pose state** change the two topics.
- **The robot's SRDF.** With an empty list, the arm view shows the group states of the robot's arm
  group, in SRDF order, once the named-pose node is running. The arm group is the `parent_group`
  of the SRDF's end effector, so the gripper's own states (such as `open` and `closed`) are not
  offered. When the robot has both `ready` and `home`, `ready` shows "Ready".
- **Both.** A profile list is used in its own order and with its own titles. Once the SRDF has
  arrived, a pose that is not a state of the arm group is left out.

Conduit reads the SRDF from `/robot_description_semantic`, which `move_group` publishes. A
`move_group` in a namespace publishes it elsewhere, so it offers no poses; use the profile's list
then. While the robot is online, the profile editor says which buttons the arm view will show
("The arm view shows the robot's poses: Work, Fold, Ready, Home.") and lists the robot's states
that are not in the list under **From the robot**, where a tap adds one.

### What a tap does

- The node pauses MoveIt Servo, moves the arm with `move_group`, and resumes Servo when the move
  ends, whether it succeeds, fails or is cancelled.
- The button shows a spinner and the status line "Moving to Fold…" until the node reports the arm
  there; then the button turns teal with a checkmark. A tap on the pose that is already on its way
  sends nothing; a tap on another pose replaces the move.
- The buttons take no tap while HOLD is pressed or held, or while the link is down. Buttons that
  appear while the view is open (the SRDF or the node arrived late) wait a second before they
  take a tap, so a tap meant for Align does not move the arm.
- **Let a pose move finish before you hold HOLD.** Servo stays paused until the move ends, so the
  arm does not follow the phone during it.
- A pose move runs on the host. Releasing HOLD, closing the arm view or putting the app in the
  background does not stop it; keep the arm's own emergency stop within reach.
- When nothing has ever arrived on the state topic 3 s after a tap, the status line says "No
  answer from the named-pose node on /conduit/teleop/named_pose_state" (with your state topic):
  start the node, or check the topics. The arm view stops waiting for a pose after 30 s. "Named poses unavailable" in place of
  the buttons means Conduit could not create the command publisher.

### Host side

1. Make `move_group` publish the SRDF. The `move_group.launch.py` and `demo.launch.py` that the
   MoveIt Setup Assistant generates do. A launch file that builds `move_group` from
   `MoveItConfigsBuilder` needs `.planning_scene_monitor(publish_robot_description_semantic=True)`,
   or the parameter `publish_robot_description_semantic: True` on the `move_group` node; it is
   off by default in Jazzy. Check it with:

    ```bash
    ros2 param get /move_group publish_robot_description_semantic   # Boolean value is: True
    ```

    The node reads the group states from this topic for a profile's list too.

2. Start the named-pose node with the arm's planning group:

    ```bash
    ros2 launch conduit_teleop named_pose.launch.py planning_group:=arm
    ```

### Example: poses that Servo can move from

Servo stops at a singularity ("Halted: singularity" on the status chip) and near the joint limits
("Halted: joint bound"). An arm's `ready` or `home` state can be singular, and then HOLD does
not move the arm after a tap on that button. On the six-joint desk arm below, both are. Give the
arm group states away from singularities and joint limits, and list them first so they become
the first buttons. On that arm, two such states, `work` and `fold`, sit before `ready` and
`home`:

```xml
<group_state name="work" group="arm">
    <joint name="link_002_joint" value="0"/>
    <joint name="link_003_joint" value="-0.95"/>
    <joint name="link_004_joint" value="1.2"/>
    <joint name="link_005_joint" value="-0.7"/>
    <joint name="link_006_joint" value="-0.1"/>
    <joint name="link_007_joint" value="0"/>
</group_state>
<group_state name="fold" group="arm">
    <joint name="link_002_joint" value="0"/>
    <joint name="link_003_joint" value="-1.6"/>
    <joint name="link_004_joint" value="1.6"/>
    <joint name="link_005_joint" value="-1.25"/>
    <joint name="link_006_joint" value="-0.3"/>
    <joint name="link_007_joint" value="0"/>
</group_state>
```

With an empty pose list, that arm's buttons read **Work**, **Fold**, **Ready** and **Home**. To
check a state, tap its button, wait for the checkmark, hold HOLD and move the phone along each
axis: the status chip should say `TWIST` or "Slowing: …", not "Halted: …". The values are the
desk arm's; find your arm's with the arm in place, its joints well inside their limits plus
Servo's `joint_limit_margins`.

## iPad and Mac

iPad and Mac show the arm view read-only: the wrist camera, the Servo status from the profile's
Servo status topic, and the joints, with "Arm control needs an iPhone. This view shows the wrist
camera, the joints and the Servo status." There is no HOLD, gripper, Align or pose button, and the
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
