---
title: Robots
description: Watch a ROS 2 robot's camera, map and diagnostics on your iPhone, and drive it.
---

# Robots

Conduit 3.0 subscribes as well as publishes. A **robot profile** says which topics hold the
robot's camera, map, odometry, battery and diagnostics, and where Conduit sends its commands.
**Open** shows the drive view:

- **Mobile robots** — camera, map with the robot's pose and LaserScan, status and
  diagnostics; drive with the on-screen stick, a game controller or the Mac keyboard. Conduit
  sends `sensor_msgs/Joy`; [`conduit_teleop`](robots-mobile.md) turns it into `cmd_vel`.
- **Robot arms** — hold the clutch and move the iPhone: a [MoveIt Servo](robots-arm.md) arm
  follows, while the screen shows the wrist camera, the gripper and the joints.

## What you need

- A ROS 2 host (Humble, Jazzy, Kilted, Lyrical or Rolling) reachable over Zenoh or DDS with the
  same settings Conduit already uses for publishing: **Settings → Transport, Domain,
  Distribution**. One connection serves the whole app.
- On the host: `conduit_teleop` for mobile robots, the Servo overlay and time sync for arms.

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

A profile remembers the connection it was made with. If the app's settings differ, the Robots
list and the drive view say so ("Profile expects DDS · domain 123 · Jazzy"). Under each robot
the list also shows whether the app is **Offline**, how many of the profile's topics are live
("3 of 5 topics live"), or, for an arm, "Servo not found".

## Open

The floating button is the app's only online switch. **Open** on an offline app starts it in
Publish mode with the sensors you have enabled (none is fine). Closing the drive view stops
everything the drive view started; the FAB keeps running until you stop it.

## Safety

!!! warning "STOP is not an emergency stop"
    STOP in the drive view stops Conduit's commands. It cannot stop a robot whose controller
    keeps the last command, and it does nothing when the network is gone. Keep the robot's own
    emergency stop within reach.

- Mobile robots: run `conduit_teleop`. Its watchdog forwards velocity commands while the newest
  `/joy` is younger than 0.5 s. When Joy goes stale, for example because the phone dropped off
  Wi-Fi, it publishes zero velocity at 10 Hz for 1 s and then stays silent until Joy resumes (it is
  also silent before the first Joy), so the robot stops without the watchdog fighting Nav2.
- Arms: Servo halts on its own command timeout; releasing the clutch sends zero twists at once.

## When something is wrong

| What you see | What to check |
| --- | --- |
| No topics discovered | Distribution (Humble vs Jazzy and later), domain ID, DDS unicast peers, the profile's connection |
| "No data — check Distribution / QoS" | The topic exists but nothing arrives: a type mismatch from the wrong Distribution, or QoS |
| "No TF map → base_link" | The map → base transform is not published; the map and scan still show |
| "Unsupported encoding: X" | The camera publishes an encoding Conduit does not draw. It draws JPEG and PNG `CompressedImage`, and `Image` in rgb8, bgr8, rgba8, bgra8 and mono8 |
| "Robot link lost: … Retrying…" | The link is down ("Router connection lost", "No data from the robot" or "Robot publishers left the graph"); Conduit reconnects with backoff, and driving needs a fresh touch afterwards |
| "Disconnected" | The link is down; Conduit reconnects with backoff and needs a fresh touch to drive |
| Camera at 15 fps, or "Paused — device is hot" | The iPhone is hot: the camera is drawn at 15 fps when it is seriously hot and stops drawing when it is critically hot. Control is never slowed down |

## Demo video

The video below shows a Kachaka driven from the iPhone and the MoveIt Servo Panda simulation
following the phone.

<!-- The video embed goes here once it is recorded, in the same form as the demo videos in README.md. -->
