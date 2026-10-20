---
title: Robots
description: Watch a ROS 2 robot's camera, map and diagnostics on your iPhone, and drive it.
---

# Robots

Conduit 3.0 subscribes as well as publishes. A **robot profile** says which topics hold the
robot's camera, map, odometry, battery and diagnostics, and where Conduit sends its commands.
**Open** shows the drive view:

- **Mobile robots** — camera, map with the robot's pose and LaserScan, status and
  diagnostics; drive with the on-screen joystick, a game controller or a hardware keyboard. Conduit
  sends `sensor_msgs/Joy`; [`conduit_teleop`](robots-mobile.md) turns it into `cmd_vel`.
- **Robot arms** — hold the clutch and move the iPhone: a [MoveIt Servo](robots-arm.md) arm
  follows, while the screen shows the wrist camera, the gripper, the joints and buttons that move
  the arm to named poses.

## What you need

- A ROS 2 host (Humble, Jazzy, Kilted, Lyrical or Rolling) reachable over Zenoh or DDS with the
  same settings Conduit already uses for publishing: **Transport**, **Domain ID** and
  **Distribution** in Settings. One connection serves the whole app.
- On the host: `conduit_teleop` for mobile robots; for arms, MoveIt Servo from Jazzy or later
  and the Servo overlay, plus `conduit_teleop`'s named-pose node if you want pose buttons.

## Where to find it

- **iPhone:** the **Robots** tab.
- **iPad and Mac:** the **Robots** button in the toolbar, next to Recordings and Settings.

Each robot in the list shows a glyph for its kind (mobile robot or arm), its name, its kind and a
status line.

## Create a profile

1. Tap **+**. The editor opens with **Kind** set to **Mobile robot**; switch it to **Arm** for a
   robot arm. Give the robot a name.
2. Under **Discovery**, Conduit lists the topics it finds on the host, filtered by type. A slot
   with exactly one match is filled for you. Discovery needs Conduit online: "Go online to
   discover topics" starts it.
3. If nothing is discovered, type the topic names. Check that the Distribution matches the host
   (Humble vs Jazzy and later), the domain ID, and the DDS unicast peers.
4. Check the frames (**Map frame** and **Base frame** for a mobile robot, **Base frame** and the
   gripper positions for an arm). For an arm, **Named poses** lists the pose buttons; see
   [Named poses](robots-arm.md#named-poses). Tap **Save**.

A profile remembers the connection it was made with. If the app uses a different transport or
domain, or Humble where the profile was made for a later distribution (or the reverse), the
Robots list and the drive view say so ("Profile expects DDS · domain 123 · Jazzy"), and the list
offers **Stop & edit settings**. Jazzy and the later distributions share one wire format, so
switching between them raises no warning. Under each robot the list also shows whether the app is
**Offline**, how many of the profile's topics are live ("3 of 5 topics live"), or, for an arm,
"Servo not found".

## Open

The floating button is the app's only online switch. **Open** on an offline app starts it in
Publish mode with the sensors you have enabled (none is fine). Closing the drive view stops
everything the drive view started; the floating button keeps running until you stop it. If a
recording is running offline, Open asks "Publish & Record?" before it goes online, and once the
weekly free allowance is spent it shows the Conduit Plus paywall instead.

On iPhone, both drive views are landscape. The screen turns to landscape first and the drive
view comes up already turned; either landscape side works. Closing the drive view turns the
screen back to portrait. iPad and Mac do not rotate.

If the app goes offline, the drive view closes: when you stop it with the floating button, when
the first connection fails, when the app goes to the background with **Background Publishing**
off, or when the week's free time runs out without Conduit Plus.

## Safety

!!! warning "STOP is not an emergency stop"
    STOP in the drive view stops Conduit's commands. It cannot stop a robot whose controller
    keeps the last command, and it does nothing when the network is gone. Keep the robot's own
    emergency stop within reach.

- Mobile robots: run `conduit_teleop`. Its watchdog forwards velocity commands while the newest
  `/joy` is younger than 0.5 s. When Joy goes stale, for example because the phone dropped off
  Wi-Fi, it publishes zero velocity at 10 Hz for 1 s and then stays silent until Joy resumes (it is
  also silent before the first Joy), so the robot stops without the watchdog fighting Nav2.
- Arms: releasing the clutch sends zero twists at once. If the link is lost, Servo stops on its
  command timeout (0.5 s with the overlay). Conduit stamps every twist, the zero ones included, on
  the robot's clock, which it reads from the profile's Joint states topic, so the stop does not
  depend on the phone's clock being right. HOLD stays off until that clock is known
  ([time sync](robots-arm.md#host-setup)). A [named-pose](robots-arm.md#named-poses) move is
  planned and run by `move_group` on the host, and nothing in Conduit stops it: not HOLD, not
  closing the arm view, not a lost link. HOLD does not move the arm until the move has ended.
  Keep the arm's own emergency stop within reach.

## When something is wrong

| What you see | What to check |
| --- | --- |
| No topics discovered | Distribution (Humble vs Jazzy and later), domain ID, DDS unicast peers, the profile's connection |
| "No data — check Distribution / QoS" | The topic exists but nothing arrives: a type mismatch from the wrong Distribution, or QoS |
| "No TF `<map frame>` → `<base frame>`" (for example "No TF map → base_footprint") | The map → base transform is not published; the map and scan still show. It appears once the map has arrived |
| "Unsupported encoding: X" | The camera publishes an encoding Conduit does not draw. It draws JPEG and PNG `CompressedImage`, and `Image` in rgb8, bgr8, rgba8, bgra8 and mono8 |
| "Disconnected" in the mobile drive view, "Connecting…" in the arm view's status line | The link is down; Conduit reconnects with backoff. Driving needs a fresh touch afterwards, and HOLD a fresh press |
| "Robot link lost: … Retrying…" in the profile editor's Discovery section | The link is down ("Router connection lost", "No data from the robot" or "Robot publishers left the graph"); Conduit reconnects with backoff |
| Red **STALE** over the camera | No camera frame for 0.5 s. The last image stays, dimmed, until frames come back; in the mobile drive view the camera chip turns red too |
| Camera at 15 fps, or "Paused — device is hot" / "Camera paused: the device is too hot" | The iPhone is hot: the camera is drawn at 15 fps when it is seriously hot and stops drawing when it is critically hot. Control is never slowed down |

## Demo video

A demo video of a Kachaka driven from the iPhone and a MoveIt Servo arm following the phone will
be added here.

<!-- The video embed goes here once it is recorded, in the same form as the demo videos in README.md. Then reword the sentence above to "The video below shows …". -->
