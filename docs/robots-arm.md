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

1. **Servo overlay.** Load `conduit_teleop`'s Servo overlay after your robot's own Servo
   parameters, so Servo takes speeds and keeps phone-stamped twists for 0.5 s. The
   [Servo overlay](#servo-overlay) section below shows the file and how to load it.

2. **Time sync.** Servo drops a twist whose stamp is older than `incoming_command_timeout` on the
   host clock. Keep the host on NTP with chrony, and the iPhone on **Settings → General → Date &
   Time → Set Automatically**:

   ```bash
   sudo apt install chrony
   chronyc tracking      # "System time" should be a few milliseconds
   ```

   If the clocks still differ, the arm view shows **Robot clock differs from the phone**. Conduit
   measures the difference from the stamps on the profile's **Joint states** topic, so bind it.

3. **Gripper (optional).** A `control_msgs/action/GripperCommand` server; the profile holds its
   action name (**Gripper action**) and the open and closed positions in metres (**Gripper open
   (m)**, **Gripper closed (m)**; the Franka Panda's fingers travel from 0.0 to 0.04).

When the arm view opens, Conduit calls the profile's **Servo command type** service
(`/servo_node/switch_command_type` by default) to switch Servo to `TWIST`, and retries every few
seconds while Servo is missing or refuses. The status chip shows the result: "Connecting to
Servo", "Servo not found", "Servo refused TWIST", then `TWIST`, or what Servo reports ("Slowing:
near singularity", "Halted: joint bound", …). The clutch stays disabled until Servo is ready.

## Using it

1. Point the back camera at the robot's front and tap **Align**: that heading becomes the base
   frame's +x. Hold the phone within 60° of horizontal. Align again after tracking restarts.
2. Hold **HOLD** and move. **0.5× / 1× / 2×** scales translation; **Rot** turns rotation on or off.
3. Release to stop: Conduit sends zero twists three times. Tracking loss, a covered camera or a
   pose jump also stop the arm; release and press again to resume. After motion tracking
   restarts or fails, Align again first.
4. Use **Open / Close** or the slider with the clutch released.

Conduit also publishes the raw pose (`/conduit/pose`, `/tf`) and `/conduit/teleop/clutch`
(`std_msgs/Bool`, true while the clutch is held, false on any pose discontinuity), so a custom
consumer can move relative to the pose at engage time.
