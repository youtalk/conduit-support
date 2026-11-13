---
title: Try Robots with the demo
description: One command gives you a simulated mobile robot and a simulated robot arm to try Conduit's Robots feature, with no robot and no ROS 2 needed.
---

# Try Robots with the demo

!!! info "Coming in Conduit 3"
    Robots is part of Conduit 3, which is not on the App Store yet. The Conduit on the App Store
    today (2.x) publishes sensors but has no robot button. This page describes Robots as it will
    ship in Conduit 3.

You do not need a robot to try [Robots](robots.md). The same command that
[pairs your phone with a QR code](pair.md) can also start two simulated robots on your computer:

- **A mobile robot**: a TurtleBot3 in a small map, with Nav2, a laser scan, a camera view drawn
  from the map, a battery and diagnostics. Drive it with the stick, or send it to a place on the
  map.
- **A robot arm**: a Franka Panda in Gazebo. Hold HOLD and move your phone to move the arm, pick a
  pose (ready, extended, transport) from the pose menu, open and close the gripper with the arc,
  watch the wrist and head cameras, and pick up the cubes on the table.

## What you need

- A Mac, or a Linux PC. On a Mac install [Docker Desktop](https://www.docker.com/products/docker-desktop/);
  on Linux install Docker Engine and add your user to the `docker` group.
- An iPhone with Conduit 3 on the same Wi-Fi as the computer.
- Disk space and patience: the demo images are several GB (5.4 GB for Jazzy and Kilted, 7.3 GB for Lyrical), so the first start downloads for a
  while. Later starts reuse them.

ROS 2 is not needed. If your Linux PC has ROS 2 (Jazzy, Kilted, Lyrical or Rolling), the demo
works there too; see [With ROS 2 on the PC](#with-ros-2-on-the-pc). Humble is not supported for the
demo.

## Start the demo

```bash
curl -fsSL https://conduit.direct/pair.sh | bash
```

On a Mac, or on a Linux PC without ROS 2, the script starts the demo in a Docker container
called `conduit-demo`, with its own Zenoh router inside, and shows the pairing QR code. Scan it
with the iPhone's Camera app, as in [Connect with a QR code](pair.md). On a Mac with Docker
Desktop installed but not running, the script offers to start it.

If Docker is missing, not running, or not usable by your user (on Linux, not in the `docker`
group), the script says so in one line, with what to do, and stops.

Run the script again while the demo is running and it reuses the running demo and shows the
QR code again.

## Add the robots

1. In Conduit, tap the robot button, then **+**. Leave **Kind** on **Mobile robot**, give the
   robot a name and tap **Start**.
2. The topics and frames fill in from the demo. Tap **Save**.
3. Tap **+** again, set **Kind** to **Arm**, name it, tap **Start**, and **Save**. The frames and
   the gripper's values fill in too.
4. Tap **Open** on either robot.

Nothing is typed by hand: the demo uses the usual names of a real robot, so the profiles fill
themselves in. See [Robots](robots.md#create-a-profile).

## What each robot shows

### The mobile robot

- The camera view is drawn from the map, as if seen from the robot, so you see the walls ahead.
- The map shows the robot's pose and the laser scan.
- The stick drives the robot. A map goal sends it to a place on the map and Nav2 plans the
  route; see [Drive a mobile robot](robots-mobile.md).
- The battery and diagnostics chips show live values.

### The robot arm

- Hold **HOLD** and move the phone: the arm's hand follows, through MoveIt Servo. See
  [Teleoperate a robot arm](robots-arm.md).
- The pose menu lists the arm's named poses (ready, extended and transport) and sends the arm
  there.
- The gripper arc opens and closes the fingers, and shows how far they are open.
- The wrist camera shows what the hand sees, and the head camera, above and behind the arm,
  shows the arm, the table and the cubes. Both run at about 10 Hz and 320 x 240 by design. The
  arm moves at normal speed, and no GPU is needed.
- Three small cubes (red, green and blue) and a tray are on a table within reach: try to pick one
  up and put it in the tray.

Both robots report to **Diagnostics**, so the diagnostics view lists both.

## With ROS 2 on the PC

On a Linux PC with ROS 2, the script pairs your phone with that PC as usual and asks whether to add the
demo robots too. If you say yes, the demo joins the PC's own ROS 2 graph, with the PC's RMW and
domain, and the QR code carries the PC's settings. The demo image matches the PC's distribution
(Rolling uses the Lyrical image).

The demo uses the usual names of a real robot, such as `/map`, `/odom`, `/scan`,
`/camera/image_raw` and `/joint_states`, and the usual frames, such as `map`, `odom` and
`base_link`. `/tf`, `/tf_static` and `/diagnostics` are shared and never collide; on `/tf` and
`/tf_static`, frames with the same name do. If your PC's graph already uses one of the demo's
names, for example a robot that already publishes `/map`, the script prints the names that
collide, skips the demo and carries on with pairing.

The demo checks the names once, when it starts. Stop it before you start your own robot on the
same PC (`docker stop -t 30 conduit-demo`, see [Stop the demo](#stop-the-demo)); otherwise both
use the same names.

## Stop the demo

The demo keeps running after the script ends. Stop it with:

```bash
docker stop -t 30 conduit-demo
```

The container takes up to about 20 seconds to shut down. Start it again by running the one-liner.

## Troubleshooting

- **The script says Docker is not running.** Start Docker Desktop (Mac) or the Docker service
  (Linux) and run the script again.
- **The script says the demo's port cannot be reached.** Some Docker runtimes (Colima, some
  OrbStack setups) publish ports on this computer only, and a firewall may block the rest. Use
  Docker Desktop on a Mac, or allow the connections.
- **Conduit never checks in.** See [Connect with a QR code](pair.md#troubleshooting). On a Mac,
  if the macOS firewall is on, let Docker accept incoming connections in System Settings > Network >
  Firewall > Options.
- **"No topics found" right after pairing.** The QR code appears as soon as the demo's router is
  ready, but the robots take about 20 to 30 seconds more to come up. Wait about half a minute and
  tap Start again.
