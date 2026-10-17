---
title: Drive a mobile robot
description: Drive a ROS 2 mobile robot from Conduit with teleop_twist_joy and a watchdog.
---

# Drive a mobile robot

Conduit sends `sensor_msgs/Joy` at 50 Hz while the drive view is open, reliable with
KEEP_LAST 1, on the profile's **Joy output** topic (default `/joy`). The layout is that of the
ROS 2 `joy` package's `game_controller_node`, so `teleop_twist_joy` reads it as it reads a
gamepad.

## Host setup

Install `conduit_teleop` as described in [Teleoperation → Host setup](teleop.md#host-setup-with-conduit_teleop)
and run it with its default `joy_topic` (`/joy`) as described in
[Teleoperation → Drive view](teleop.md#drive-view).

`conduit_teleop` runs `teleop_twist_joy` with Conduit's parameter file and a watchdog. The
watchdog forwards `teleop_twist_joy`'s `Twist` to `cmd_vel` while the newest Joy is younger than
0.5 s. When the Joy goes stale it publishes zero twists at 10 Hz for 1 s and then stays silent
until Joy resumes (it is also silent before the first Joy), so it does not fight Nav2 or another
`cmd_vel` publisher. See [Joy layout](teleop.md#joy-layout) for every axis and button.

| input | Joy field | role |
| --- | --- | --- |
| stick up / down | `axes[1]` (up +) | `linear.x` |
| stick left / right | `axes[0]` (left +) | `angular.z` |
| touching the stick, Space, or the left shoulder | `buttons[9]` | deadman (`enable_button`) |
| right shoulder | `buttons[10]` | not used: turbo is off and masked unless the deadman is held |

- **Slow / Fast** is set on the phone and starts on Slow. Slow halves both the forward and the
  turn rate (also for a controller's sticks); Fast sends the stick unscaled. The parameter file
  holds the full-speed scales.
- **Game controllers** (MFi and other GameController devices) drive with their own buttons: hold
  LB / L1 and use the left stick. The on-screen stick hides while one is connected.
- **Hardware keyboard** (Mac, or an iPad with a keyboard): Space = deadman, arrows or WASD = stick, Shift = Fast while held.
- **VoiceOver:** four hold-to-move buttons (Forward, Back, Turn left, Turn right) replace the
  stick.
- After STOP, a lost link or the app going to the background, nothing drives until you let go of
  every input and press again.
- The Game Controller sensor publishes `<namespace>/joy` (`/conduit/joy` by default); the drive
  view publishes the profile's Joy topic (`/joy` by default). Run `conduit_teleop` on one of them,
  not both. If the profile's Joy topic is the sensor's topic, Conduit asks before it opens the
  drive view and pauses the sensor while the drive view is open.

## Kachaka

The [kachaka-api](https://github.com/pf-robotics/kachaka-api) ROS 2 bridge takes velocity on
`/kachaka/manual_control/cmd_vel` once manual control is enabled. On the host, run
`conduit_teleop`'s Kachaka launch file, which sets both up and drives at Kachaka's own speeds
([Teleoperation → Kachaka](teleop.md#kachaka)). It starts `conduit_teleop` itself, so use it
instead of `conduit_teleop.launch.py`, not together with it:

```bash
ros2 launch conduit_teleop kachaka.launch.py
```

Profile: Camera `/kachaka/front_camera/image_raw/compressed`, Map `/kachaka/mapping/map`, Map frame `map`, Base frame `base_footprint`, the
LaserScan, Odometry and Battery topics the bridge lists, Joy output `/joy`.
