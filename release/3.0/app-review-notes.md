# Conduit 3.0 — notes for App Review

Conduit is a developer tool for ROS 2, the robotics framework. It needs a ROS 2 computer on the
same network; there is no account and no server.

## New in 3.0: Robots

The Robots tab (iPhone) or the Robots toolbar button (iPad, Mac) lists robot profiles. Opening a
profile subscribes to the robot's camera, map, odometry, battery and diagnostics on the ROS 2
network and shows them in a drive view:

- Mobile robots: the user drives with an on-screen virtual joystick, a game controller or a hardware keyboard.
  Conduit sends standard ROS 2 joystick messages; the robot's own software turns them into motion.
- Robot arms: the iPhone arm view is landscape, over the robot's wrist camera. While the user
  holds the on-screen clutch (HOLD), Conduit converts the iPhone's motion (ARKit world tracking)
  into velocity commands for MoveIt Servo. Pose buttons send the name of an arm pose that the
  robot's MoveIt configuration defines; the robot's own software moves the arm there. On iPad and Mac the arm view only shows the camera,
  the joints and the arm's status.

<!-- Keep the next paragraph out of the submission until the video is embedded at
     https://conduit.youtalk.jp/robots/#demo-video (docs/robots.md, "Demo video"). -->
A demo video of both, recorded with a Kachaka robot and the MoveIt Servo simulation of a
Franka Panda arm, is at https://conduit.youtalk.jp/robots/#demo-video.

On iPhone both drive views open in landscape.

Without a ROS 2 computer the Robots tab shows "No robots yet". In the profile editor, "Go online
to discover topics" starts discovery, and topic names can also be typed by hand. All sensor
publishing and recording features work without a robot.

The camera is used for the existing camera sensors and, with ARKit, for the Device Pose sensor
and arm teleoperation (motion tracking). Sensor and robot data go only to the ROS 2 host the user configures.

## Conduit Plus

- Every feature, including Robots, is free for 5 hours of active use each week (time with a
  connected ROS 2 subscriber, a recording, or an open drive view). Conduit Plus (monthly, yearly
  or lifetime) removes the limit.
- The five former in-app purchases (Back Cameras, LiDAR, Game Controller, Background Mode,
  Recording Export) are removed from sale with this version. Anyone who bought one of them gets
  Conduit Plus forever ("Founder"), so no purchased functionality is taken away.
- An offer code for Conduit Plus Monthly is provided in the review information so the
  unlimited plan can be tested.
