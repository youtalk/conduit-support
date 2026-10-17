---
title: Robots
description: Watch a ROS 2 robot's camera, map and diagnostics on your iPhone, and drive it.
---

# Robots

Conduit 3.0 subscribes as well as publishes. A **robot profile** says which topics hold the
robot's camera, map, odometry, battery and diagnostics, and where Conduit sends its commands.
**Open** shows the drive view:

- **Mobile robots** — camera, map with the robot's pose and LaserScan, status and
  diagnostics; drive with the on-screen stick, a game controller or a hardware keyboard. Conduit
  sends `sensor_msgs/Joy`; [`conduit_teleop`](robots-mobile.md) turns it into `cmd_vel`.
- **Robot arms** — hold the clutch and move the iPhone: a [MoveIt Servo](robots-arm.md) arm
  follows, while the screen shows the wrist camera, the gripper and the joints.

## What you need

- A ROS 2 host (Humble, Jazzy, Kilted, Lyrical or Rolling) reachable over Zenoh or DDS with the
  same settings Conduit already uses for publishing: **Settings → Transport, Domain,
  Distribution**. One connection serves the whole app.
- On the host: `conduit_teleop` for mobile robots; for arms, MoveIt Servo from Jazzy or later,
  the Servo overlay and time sync.

## Where to find it

- **iPhone:** the **Robots** tab.
- **iPad and Mac:** the **Robots** button in the toolbar, next to Recordings and Settings.

## Create a profile

1. Tap **+**. The editor opens with **Kind** set to **Mobile robot**; switch it to **Arm** for a
   robot arm. Give the robot a name.
2. Under **Discovery**, Conduit lists the topics it finds on the host, filtered by type. A slot
   with exactly one match is filled for you. Discovery needs Conduit online: "Go online to
   discover topics" starts it.
3. If nothing is discovered, type the topic names. Check that the Distribution matches the host
   (Humble vs Jazzy and later), the domain ID, and the DDS unicast peers.
4. Check the frames (**Map frame** and **Base frame** for a mobile robot, **Base frame** and the
   gripper positions for an arm) and tap **Save**.

A profile remembers the connection it was made with. If the app uses a different transport or
domain, or Humble where the profile was made for a later distribution (or the reverse), the
Robots list and the drive view say so ("Profile expects DDS · domain 123 · Jazzy"). Jazzy and
the later distributions share one wire format, so switching between them raises no warning. Under each robot
the list also shows whether the app is **Offline**, how many of the profile's topics are live
("3 of 5 topics live"), or, for an arm, "Servo not found".

## Open

The floating button is the app's only online switch. **Open** on an offline app starts it in
Publish mode with the sensors you have enabled (none is fine). Closing the drive view stops
everything the drive view started; the FAB keeps running until you stop it. If a recording is
running offline, Open asks "Publish & Record?" before it goes online, and once the weekly free
allowance is spent it shows the Conduit Plus paywall instead.

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
  command timeout (0.5 s with the overlay), but only while the host and phone clocks agree: Servo
  compares the twist's stamp with the host clock, so a phone clock that runs ahead keeps the last
  twist alive and the arm can keep moving until the host catches up. Keep the host on chrony and
  the phone on Set Automatically ([time sync](robots-arm.md#host-setup)), and keep the arm's own
  emergency stop within reach.

## When something is wrong

| What you see | What to check |
| --- | --- |
| No topics discovered | Distribution (Humble vs Jazzy and later), domain ID, DDS unicast peers, the profile's connection |
| "No data — check Distribution / QoS" | The topic exists but nothing arrives: a type mismatch from the wrong Distribution, or QoS |
| "No TF `<map frame>` → `<base frame>`" (for example "No TF map → base_footprint") | The map → base transform is not published; the map and scan still show. It appears once the map has arrived |
| "Unsupported encoding: X" | The camera publishes an encoding Conduit does not draw. It draws JPEG and PNG `CompressedImage`, and `Image` in rgb8, bgr8, rgba8, bgra8 and mono8 |
| "Disconnected" in the drive view or the arm view | The link is down; Conduit reconnects with backoff and driving needs a fresh touch afterwards |
| "Robot link lost: … Retrying…" in the profile editor's Discovery section | The link is down ("Router connection lost", "No data from the robot" or "Robot publishers left the graph"); Conduit reconnects with backoff |
| Camera at 15 fps, or "Paused — device is hot" | The iPhone is hot: the camera is drawn at 15 fps when it is seriously hot and stops drawing when it is critically hot. Control is never slowed down |

## Demo video

A demo video of a Kachaka driven from the iPhone and the MoveIt Servo Panda simulation
following the phone will be added here.

<!-- The video embed goes here once it is recorded, in the same form as the demo videos in README.md. Then reword the sentence above to "The video below shows …". -->
