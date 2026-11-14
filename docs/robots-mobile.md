---
title: Drive a mobile robot
description: Drive a ROS 2 mobile robot from Conduit with teleop_twist_joy and a watchdog, and send it navigation goals from the map.
---

# Drive a mobile robot

!!! info "Coming in Conduit 3"
    Robots is part of Conduit 3, which is not on the App Store yet. The Conduit on the App Store
    today (2.x) publishes sensors but has no robot button. This page describes Robots as it will
    ship in Conduit 3.

Conduit sends `sensor_msgs/Joy` at 50 Hz while the drive view is open and the robot link is up,
reliable with KEEP_LAST 1, on the profile's **Joy output** topic (default `/joy`). The layout is
that of the ROS 2 `joy` package's `game_controller_node`, so `teleop_twist_joy` reads it as it
reads a gamepad.

## The drive view

### iPhone

The drive view follows how you hold the phone: landscape for two hands, upright for one. Turn
the phone to switch; with the system's rotation lock on, it stays upright. A turn lets go of
every input, so press again to drive.

- **Landscape:** status chips at the top left, the gear and close at the top right. At the
  bottom, the joystick is under one thumb (the left one unless you change it in the gear panel),
  the small window starts in the other corner, and the status banner is between them.
- **Upright:** the same top row, the status banner above the bottom row, the joystick in the
  bottom corner of the hand that holds the phone (the right hand unless you change it), and the
  small window starting in the other corner.

With a Map topic, the view opens on the full map behind the controls and the camera in the small
window; with only a LaserScan topic, it opens on the camera and the mini map in the window. Tap
the window to swap the two; each robot's drive view opens on its last choice. Without a Map or
LaserScan topic, the camera fills the screen and there is no window. The robot keeps driving
whatever is behind the controls.

Drag the window anywhere: it stays where you let go, and moves aside if it would cover a control
or a warning. Pinch it or double-tap it to switch between three sizes. Conduit keeps its place for
each robot and each way of holding the phone. With VoiceOver, its actions move it to a free corner
or edge and resize it.

The chips show the battery, the speed from the odometry, the camera's latency and frame rate
(the frame rate only when the robot's and the phone's clocks disagree; "No video" before the
first frame; red while the camera is STALE) and the diagnostics (tap it for the full list). The
battery, speed and diagnostics chips appear once they have a value.
Pinch the camera to scale it between the whole image and filling the screen, and drag to pan
it; Conduit keeps the zoom for each orientation.

### iPad and Mac

The controls are the iPhone's landscape layout, with the joystick on the left (larger where the
window is wide enough), and they stay as they are when the iPad turns. With a Camera topic and a
Map or LaserScan topic, the camera and the full map share the screen behind the controls: side by
side where the window is at least as wide as it is tall (the camera on the left), one above the
other where it is taller (the camera on top). Drag the divider between them to resize; each keeps
at least a quarter, and the divider stops at half when you bring it near the middle. Conduit keeps
the split on the device, one for each direction. The camera opens on the whole image; pinch and
drag it to zoom it within its side. Each side shows its own captions. With only one of the two,
it fills the screen, and there is no small window.

The diagnostics chip opens the diagnostics in a sheet. With a hardware keyboard connected, the
banner shows the hint "Space + arrows or WASD to drive".

### Gear panel

- **Max speed:** 25%, 50%, 75% or 100% of the stick's full travel, for the forward speed and the
  turn rate alike. It applies to the on-screen joystick, the keyboard and a game controller's left
  stick. Every drive view opens at 50%. Changing it while you drive releases every input until you
  press again, so the robot never jumps to the new speed.
- **Stick** (iPhone, landscape): **Left thumb** or **Right thumb** for the joystick.
- **Hand** (iPhone, upright): **Left hand** or **Right hand**, the hand that holds the phone.

Conduit keeps the Stick and Hand choices per robot on this device. The robot keeps driving while
the gear panel is open.

### Map and navigation goals

The full map pinch-zooms between 0.5× and 20×, pans with a drag, and resets with a double tap.
Conduit keeps each robot's view of the map and opens it where you left it. The robot keeps
driving while the map is shown. Only the diagnostics pause driving: the banner says "Paused while
a panel is open", and after you close them every input needs a fresh press.

To send a navigation goal, the profile needs a Map topic and a **Nav2 goal action** (Nav2's
`nav2_msgs/action/NavigateToPose`; `/navigate_to_pose` unless your robot uses another name).
Then, with the map in view (on iPhone the full map behind the controls, on iPad and Mac the map
side of the split):

1. Tap the flag button next to the gear. The banner says "Touch the goal and drag toward the
   heading".
2. Touch the goal on the map and drag toward the way the robot should face. A tap without a drag
   points the goal away from the robot.

The flag is dimmed until a map has arrived and Conduit sees the action on the robot's graph;
without it, the banner says "This robot has no Nav2 NavigateToPose action". Tap the flag again to
stop placing a goal.

Conduit sends the goal as a pose in the profile's **Map frame**, with a zero stamp (the latest
transform) and Nav2's default behavior tree, like RViz's **Nav2 Goal** tool. It waits up to 2 s
for the action server. The banner then follows the goal: "Sending goal…", "Driving to the goal",
and "Goal reached", or "Nav2 refused the goal", "Nav2 aborted the goal: <reason>", "Goal
canceled". It stays until the next goal or until you close the drive view. If the goal cannot be
sent, the banner says why, for example "Cannot send goal: Nav2's NavigateToPose action was not
found" or "Nav2 did not answer the goal".

While a goal is on its way, a red **Cancel goal** button sits right above the joystick: tap it to
ask Nav2 to stop ("Canceling goal…", then "Goal canceled"). A new goal cancels the one on its way
first, and closing the drive view cancels it too. If Nav2 does not confirm, the banner says
"Cancel not confirmed — check the robot"; if the link is lost, "Goal status unknown — the link was
lost".

Without Conduit Plus, a goal on its way when the weekly free time runs out may finish, for at most
5 more minutes ("Free time is up. The robot is finishing its goal (up to 5 min).") and is then
canceled; new goals are off.

## Inputs

| input | Joy field | role |
| --- | --- | --- |
| stick up / down | `axes[1]` (up +) | `linear.x` |
| stick left / right | `axes[0]` (left +) | `angular.z` |
| touching the stick, Space, or the left shoulder | `buttons[9]` | deadman (`enable_button`) |
| right shoulder | `buttons[10]` | not used: turbo is off, and Conduit masks it unless the deadman is held |

See [Joy layout](teleop.md#joy-layout) for every axis and button.

- **On-screen joystick:** the touch input in every case, also with VoiceOver and with a game
  controller connected. Touch it to drive and lift your finger to stop.
- **Game controllers** (MFi and other GameController devices): hold LB / L1 and use the left
  stick. The "Game controller" chip next to the joystick shows that one is connected; you can use
  either.
- **Hardware keyboard** (Mac, or an iPad with a keyboard): hold Space and use the arrows or WASD.
  The keys drive at the max speed.
- **VoiceOver:** the joystick takes direct touch. It is labelled "Drive joystick" with the hint
  "Drag to drive; lift your finger to stop", and VoiceOver announces "Driving" and "Stopped".
- After a lost link, the app going to the background, a closed panel, a turn of the phone or a max
  speed change, nothing drives until you let go of every input and press again; while you still
  hold one, the banner says "Release and touch again to drive". While the link is down it says
  "Disconnected", and while Conduit is inactive "Paused while Conduit is inactive".
- Without Conduit Plus, a chip over the camera shows the week's free-time notices; tap it to
  dismiss it. When the free time runs out, the robot stops and the drive view stays behind the
  Conduit Plus paywall until you close it.
- The Game Controller sensor publishes `<namespace>/joy` (`/conduit/joy` by default); the drive
  view publishes the profile's Joy output topic (`/joy` by default). Run `conduit_teleop` on one of
  them, not both. If the profile's Joy output is the sensor's topic and the sensor is enabled,
  Conduit asks before it opens the drive view and pauses the sensor while the drive view is open.

## Host setup

Install `conduit_teleop` as described in [Teleoperation → Host setup](teleop.md#host-setup-with-conduit_teleop)
and run it with its default `joy_topic` (`/joy`) as described in
[Teleoperation → Drive view](teleop.md#drive-view).

`conduit_teleop` runs `teleop_twist_joy` with Conduit's parameter file and a watchdog. With the
shipped file, full stick is 0.5 m/s and 1.0 rad/s, so the default max speed of 50% tops out at
0.25 m/s and 0.5 rad/s. The watchdog forwards `teleop_twist_joy`'s `Twist` to `cmd_vel` while the
newest Joy is younger than 0.5 s. When the Joy goes stale it publishes zero twists at 10 Hz for
1 s and then stays silent until Joy resumes (it is also silent before the first Joy), so it does
not fight Nav2 or another `cmd_vel` publisher.

## Kachaka

The [kachaka-api](https://github.com/pf-robotics/kachaka-api) ROS 2 bridge takes velocity on
`/kachaka/manual_control/cmd_vel` once manual control is enabled. On the host, run
`conduit_teleop`'s Kachaka launch file, which sets both up and drives at Kachaka's own speeds
([Teleoperation → Kachaka](teleop.md#kachaka)). It starts `conduit_teleop` itself, so use it
instead of `conduit_teleop.launch.py`, not together with it:

```bash
ros2 launch conduit_teleop kachaka.launch.py
```

Profile: Camera `/kachaka/front_camera/image_raw/compressed`, Map `/kachaka/mapping/map`, Map
frame `map`, Base frame `base_footprint`, the LaserScan, Odometry and Battery topics the bridge
lists, Joy output `/joy`.
