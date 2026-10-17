---
title: Teleoperate a robot arm
description: Move a MoveIt Servo arm with your iPhone's motion.
---

# Teleoperate a robot arm

Hold the iPhone in one hand. While your thumb holds **HOLD**, the arm's end effector follows the
phone's motion: Conduit turns ARKit's pose of the phone into `geometry_msgs/TwistStamped` for
MoveIt Servo (`/servo_node/delta_twist_cmds`). The arm view is portrait on iPhone; iPad and Mac
open it read-only (wrist camera, joints, Servo status).

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
   (m)**, **Gripper closed (m)**; the Franka Panda's fingers travel from 0.0 to 0.04).

When the arm view opens, Conduit calls the profile's **Servo command type** service
(`/servo_node/switch_command_type` by default) to switch Servo to `TWIST`, and retries every few
seconds while Servo is missing or refuses. The status chip shows the result: "Connecting to
Servo", "Servo not found", "Servo refused TWIST", then `TWIST`, or what Servo reports ("Slowing:
near singularity", "Halted: joint bound", …). The clutch stays disabled until Servo is ready.

## Using it

1. Point the back camera the way the base frame's +x axis points, which is the robot's forward
   direction (stand behind the base and look along it), and tap **Align**: that heading becomes
   the base frame's +x. If you face the robot instead, the motion is mirrored. Hold the phone
   within 60° of horizontal. Align again after tracking restarts.
2. Hold **HOLD** and move. **0.5× / 1× / 2×** scales translation; **Rot** turns rotation on or off.
3. Release to stop: Conduit sends zero twists three times. Tracking loss, a covered camera or a
   pose jump also stop the arm; release and press again to resume. After motion tracking
   restarts or fails, Align again first.
4. Use **Open / Close** or the slider with the clutch released.

Conduit also publishes the raw pose (`<namespace>/pose`, `/tf`) and `<namespace>/teleop/clutch`
(`std_msgs/Bool`, true while the clutch is held, false on any pose discontinuity), so a custom
consumer can move relative to the pose at engage time. The namespace is `conduit` unless you
changed it in Settings. The pose and `/tf` come from the Device Pose sensor, which must be
enabled.

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
