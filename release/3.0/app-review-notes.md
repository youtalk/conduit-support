# Conduit 3.0 — notes for App Review

Conduit is a developer tool for ROS 2, the robotics framework. It needs a ROS 2 computer on the
same network; there is no account and no server.

## New in 3.0: Robots

The robot button in the toolbar (iPhone, iPad and Mac) opens the Robots list of robot profiles.
Opening a profile subscribes to the robot's camera, map, odometry, battery and diagnostics on the
ROS 2 network and shows them in a drive view:

- Mobile robots: the user drives with an on-screen virtual joystick, a game controller or a
  hardware keyboard. Conduit sends standard ROS 2 joystick messages; the robot's own software
  turns them into motion. On the full-screen map the user can also set a navigation goal, which
  Conduit sends as a standard ROS 2 pose message.
- Robot arms (iPhone and iPad): the arm view is over the robot's wrist camera. While the user
  holds the on-screen HOLD button, Conduit converts the device's motion (ARKit world tracking)
  into velocity commands for MoveIt Servo. A pose menu lists the arm poses that the robot's
  MoveIt configuration defines (the group states of its SRDF); picking one asks the robot's
  MoveIt (`move_group`) to move the arm there. The menu appears only when the robot publishes its
  SRDF. The Mac has no ARKit world tracking, so on Mac the arm view only shows the wrist camera,
  the Servo status and diagnostics.

The drive views follow how the device is held. On iPhone, landscape shows the two-handed layout
and portrait the one-handed layout; on iPad the arm view always uses the two-handed layout.

Releasing the drive controls stops the commands. The app tells users that Conduit is not an
emergency stop and that the robot's own stop must stay within reach.

<!-- TODO(owner): keep the next paragraph out of the submission until the video is embedded at
     https://conduit.youtalk.jp/robots/#demo-video (docs/robots.md, "Demo video"). -->
A demo video of both, recorded with a Kachaka robot and the MoveIt Servo simulation of a
Franka Panda arm, is at https://conduit.youtalk.jp/robots/#demo-video.

Without a ROS 2 computer the Robots list shows "No robots yet". In the profile editor, the Start
button goes online and fills the profile in from the robot; topic names can also be typed by
hand. All sensor publishing and recording features work without a robot.

The camera is used for the existing camera sensors and, with ARKit, for the Device Pose sensor
and arm teleoperation (motion tracking). Sensor and robot data go only to the ROS 2 host the user
configures.

## Conduit Plus

- Every feature, including Robots, is free for 5 hours of use each week on each device. Time
  counts only while a ROS 2 subscriber receives Conduit's data, a recording runs, or a drive view
  is connected to a robot, and on iPhone and iPad only while Conduit is in the foreground. The
  week starts on Monday at 00:00 local time. The time left shows as a dial around the Start
  button and in Settings → Conduit Plus.
- Conduit Plus (Monthly, Yearly or Lifetime) removes the limit. Lifetime is not offered while a
  subscription is active. Restore Purchases is on the paywall and in Settings → Conduit Plus.
- When the free time runs out, Conduit stops safely: a control the user is holding gets up to
  5 more minutes to be released, robots are sent stop commands, a running recording is closed,
  and then the paywall opens.
- The five former in-app purchases (Back Cameras, LiDAR, Game Controller, Background Mode,
  Recording Export) are removed from sale with this version. Anyone who bought one of them gets
  Conduit Plus forever ("Founder"), so no purchased functionality is taken away.
- An offer code for Conduit Plus Monthly is provided in the review information so the
  unlimited plan can be tested. <!-- TODO(owner): put the offer code in App Store Connect's
  review information before submitting. -->
