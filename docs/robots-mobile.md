---
title: Drive a mobile robot
description: Drive a ROS 2 mobile robot from Conduit with teleop_twist_joy and a watchdog, and send it navigation goals from the map.
---

# Drive a mobile robot

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
  the mini map is in the other corner, and the status banner is between them.
- **Upright:** the same top row, the status banner above the bottom row, the joystick in the
  bottom corner of the hand that holds the phone (the right hand unless you change it), and the
  mini map in the other corner.

The chips show the battery, the speed from the odometry, the camera's latency and frame rate
(the frame rate only when the robot's and the phone's clocks disagree; "No video" before the
first frame; red while the camera is STALE) and the diagnostics (tap it for the full list). The
battery, speed and diagnostics chips appear once they have a value.
Pinch the camera to scale it between the whole image and filling the screen, and drag to pan
it; Conduit keeps the zoom for each orientation. The mini map shows when the profile has a Map
or LaserScan topic; tap it for the full-screen map.

### iPad and Mac

The camera fills two thirds of the width, next to a column of **Map**, **Status** and
**Diagnostics** tiles. Drag the divider between them to resize (the camera keeps at least 40 %
of the width); double-tap it to restore the default. Tap a tile to open it in a sheet. Pinch and
drag the camera to zoom it within its tile. With a hardware keyboard connected, the hint "Space +
arrows or WASD to drive" shows above the banner. In a narrow iPad window the drive view uses the
iPhone's landscape layout.

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

The full-screen map (a sheet on iPad and Mac) pinch-zooms between 0.5× and 20×, pans with a drag,
and resets with a double tap. Nothing drives while the map, Status or Diagnostics is open; the
banner says "Paused while a panel is open", and after you close it every input needs a fresh
press.

To send a navigation goal, set the profile's **Goal pose** topic (`/goal_pose` for Nav2). The
profile also needs a Map topic. Then, on the full-screen map:

1. Tap **Set goal**.
2. Touch the goal and drag toward the heading the robot should face. A tap without a drag points
   the goal away from the robot.

Conduit sends one `geometry_msgs/PoseStamped` in the profile's **Map frame**, with a zero stamp
(the latest transform), like RViz's **2D Goal Pose** tool, and then returns to panning. It waits
up to 2 s for a subscriber and then sends anyway. The map says "Goal sent on `<topic>`", or "Goal
sent, but nothing subscribes to `<topic>`" when no subscriber matched. The goal stays on the map
until you close the drive view.

Conduit cannot cancel a goal. Releasing the joystick, closing the map or closing the drive view
does not stop the robot driving to it.

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
frame `map`, Base frame `base_footprint`, Goal pose `/kachaka/goal_pose`, the LaserScan,
Odometry and Battery topics the bridge lists, Joy output `/joy`.
