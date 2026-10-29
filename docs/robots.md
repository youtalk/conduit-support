---
title: Robots
description: Watch a ROS 2 robot's camera, map and diagnostics on your iPhone, iPad or Mac, and drive it.
---

# Robots

Conduit 3.0 subscribes as well as publishes. A **robot profile** says which topics hold the
robot's camera, map, odometry, battery and diagnostics, and where Conduit sends its commands.
**Open** shows the drive view:

- **Mobile robots** — camera, map with the robot's pose and LaserScan, status and
  diagnostics; drive with the on-screen joystick, a game controller or a hardware keyboard, and
  set a navigation goal on the map. Conduit sends `sensor_msgs/Joy`;
  [`conduit_teleop`](robots-mobile.md) turns it into `cmd_vel`.
- **Robot arms** — hold HOLD and move your iPhone or iPad: a [MoveIt Servo](robots-arm.md) arm
  follows, while the screen shows the wrist camera, the gripper, diagnostics and a menu that
  moves the arm to the poses of its SRDF. On a Mac the arm view only watches.

## What you need

- A ROS 2 host (Humble, Jazzy, Kilted, Lyrical or Rolling) reachable over Zenoh or DDS with the
  same settings Conduit already uses for publishing: **Transport**, **Domain ID** and
  **Distribution** in Settings. One connection serves the whole app.
- On the host: `conduit_teleop` for mobile robots, and Nav2 (or another node that takes a
  `geometry_msgs/PoseStamped` goal) for map goals. For arms, MoveIt Servo from Jazzy or later
  and the Servo overlay, plus a `move_group` that publishes the SRDF if you want the pose menu.

## Where to find it

Tap the robot button in the toolbar, before Recordings and Settings. It is in the same place on
iPhone, iPad and Mac. The Robots list opens as a sheet, with the Start button in its bottom
corner as on the main screen.

Each robot in the list shows a glyph for its kind, its name, its kind (**Mobile robot** or
**Arm**), a status line and **Open**. Tap a robot to edit it; swipe it to delete it.

## Create a profile

1. Tap **+**. The editor opens with **Kind** set to **Mobile robot**; switch it to **Arm** for a
   robot arm. Give the robot a name.
2. Tap **Start** in the bottom corner (while Conduit is offline, a "Discover your robot" tip
   points at it). Conduit goes online and fills in the new profile from the robot:
    - each empty topic field that has exactly one discovered topic of the right type, including
      Servo's twist topic, command type service and status topic, and the gripper action;
    - the frames: for a mobile robot the **Map frame** from the map and the **Base frame** from
      the odometry; for an arm the **Base frame**, the **Gripper joint** and the gripper's
      **Open** and **Closed** positions from the robot's SRDF and URDF.

    Each field is filled once. A field you type in or clear stays as you left it, and a saved
    profile is never filled again. The list button next to a field shows every discovered topic
    that fits it.
3. Check the fields. An empty field shows a usual name in grey. **Joy output** and **Goal pose**
   are never discovered, because only the robot subscribes to them: type them if the grey name is
   wrong. Under **Required topics**, an empty field is saved as the grey default. Under
   **Optional topics**, an empty field turns off what it feeds.
4. Tap **Save**. An arm's named poses are not part of the profile: the arm view's pose menu lists
   the group states of the robot's SRDF; see [Named poses](robots-arm.md#named-poses).

If Conduit finds no topics, the editor shows "No topics found" with the likely causes: the
Distribution (Humble vs Jazzy and later), the domain ID, the Zenoh router or the DDS peers, and
the profile's connection. You can still type the topic names.

A profile remembers the connection it was made with. If the app uses a different transport or
domain, or Humble where the profile was made for a later distribution (or the reverse), the
Robots list and the drive view say so ("Profile expects DDS · domain 123 · Jazzy"). The list
offers **Stop & edit settings**, and the editor offers **Use the app settings for this
profile**. Jazzy and the later distributions share one wire format, so switching between them
raises no warning. Under each robot the list also shows **Offline**, how many of the profile's
topics are live ("3 of 5 topics live"), or, for an arm, "Servo not found".

## Open

The Start button is the app's one online switch. **Open** on an offline app starts it in Publish
mode with the sensors you have enabled (none is fine), and so does Start in the Robots list and
the editor. If a recording is running offline, Conduit asks "Publish & Record?" first. If the
week's free time is used up, the Conduit Plus paywall opens instead of the drive view.

The drive view comes up the way you hold the device and turns with it; the system's rotation
lock keeps it as it is. On iPhone, landscape is the two-handed layout and upright the one-handed
one, and closing the drive view turns the screen back to portrait. On iPad the arm view always
uses the two-handed layout. On iPad and Mac the mobile drive view shows the camera next to Map,
Status and Diagnostics tiles (in a narrow window, the iPhone's landscape layout).

Close (**×**) ends what the drive view started. The app stays online until you tap Stop on the
Start button. The drive view also closes when the app goes offline: when the first connection
fails, or when the app goes to the background with **Background Publishing** off.

## Free time and Conduit Plus

Robots is part of the free plan's 5 hours of use a week. A drive view counts while its robot link
is connected; a ROS 2 subscriber to Conduit's topics and a running recording count too. On iPhone
and iPad, time counts only while Conduit is in the foreground; a Mac counts in the background
too. Each device has its own time, and it refills on Monday at 00:00 local time. The dial around
the Start button shows what is left: orange at 30 minutes, red at 5 minutes. Conduit Plus removes
the limit.

When the time runs out in a drive view, a held stick, a held HOLD or a running pose move gets up
to 5 more minutes to end. Conduit then sends its stop commands, closes a running recording, stops,
and shows the paywall over the stopped drive view. Closing the paywall returns you to the Robots
list.

## Safety

!!! warning "Conduit is not an emergency stop"
    Releasing the drive controls stops Conduit's commands. That cannot stop a robot whose
    controller keeps the last command, and it does nothing when the network is gone. Keep the
    robot's own emergency stop within reach.

- Mobile robots: letting go of the stick, the game controller or the keys sends Joy with the
  enable button released. Opening the map, status or diagnostics panel and the app going to the
  background do the same; after them, and after a lost link, driving needs a fresh press. Run
  `conduit_teleop`: its watchdog forwards velocity commands while the newest `/joy` is younger
  than 0.5 s. When Joy goes stale, for example because the phone dropped off Wi-Fi, it publishes
  zero velocity at 10 Hz for 1 s and then stays silent until Joy resumes (it is also silent before the first Joy), so the robot
  stops without the watchdog fighting Nav2. A map goal is a plain topic message: Conduit cannot
  cancel it.
- Arms: releasing HOLD sends zero twists at once. If the link is lost, Servo stops on its command
  timeout (0.5 s with the overlay). Conduit stamps every twist, the zero ones included, on the
  robot's clock, which it reads from the profile's Joint states topic, so the stop does not depend
  on the device's clock being right. HOLD stays off until that clock is known
  ([time sync](robots-arm.md#host-setup)). A [named-pose](robots-arm.md#named-poses) move is
  planned and run by `move_group` on the host. Pressing HOLD, opening the diagnostics, closing the
  arm view and the app going to the background cancel it, and so does a move that has not
  ended after 30 s. A cancel needs the link: a move running when Wi-Fi drops completes on the
  host, and after the reconnect Conduit keeps HOLD off until the arm has stopped, or for at most
  30 s from the pick.

## When something is wrong

| What you see | What to check |
| --- | --- |
| "No topics found" in the profile editor | Distribution (Humble vs Jazzy and later), domain ID, the Zenoh router or DDS unicast peers, the profile's connection |
| "Robot link lost" in the profile editor | The link is down ("Router connection lost", "No data from the robot" or "Robot publishers left the graph"); Conduit keeps retrying |
| "Servo not found" in the Robots list | Nothing publishes the arm profile's **Servo status** topic: Servo is not running, or the profile names another node |
| "No data — check Distribution / QoS" | The topic exists but nothing arrives: a type mismatch from the wrong Distribution, or QoS |
| "No TF `<map frame>` → `<base frame>`" (for example "No TF map → base_footprint") | The map → base transform is not published; the map and scan still show. It appears once the map has arrived |
| "Unsupported encoding: X" | The camera publishes an encoding Conduit does not draw. It draws JPEG and PNG `CompressedImage`, and `Image` in rgb8, bgr8, rgba8, bgra8 and mono8 |
| "Disconnected" in the mobile drive view, "Connecting…" in the arm view's status line | The link is down; Conduit reconnects with backoff. Driving needs a fresh touch afterwards, and HOLD a fresh press |
| Red **STALE** over the camera | No camera frame for 0.5 s. The last image stays, dimmed, until frames come back, and the camera chip turns red |
| Camera at 15 fps, or "Paused — device is hot" / "Camera paused: the device is too hot" | The device is hot: the camera is drawn at 15 fps when it is seriously hot and stops drawing when it is critically hot. Control is never slowed down |
| "Camera paused: use Conduit full screen" in the iPad arm view | iPadOS pauses motion tracking while Conduit shares the screen with other apps. Use Conduit full screen |

## Demo video

A demo video of a Kachaka driven from the iPhone and a MoveIt Servo arm following the phone will
be added here.

<!-- TODO(owner): embed the video here once it is recorded, in the same form as the demo videos
     in README.md, and reword the sentence above to "The video below shows …". -->
