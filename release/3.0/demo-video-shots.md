# Conduit 3.0 demo video — shot list

Target length 3:00, landscape 1080p, screen recording plus a second camera on the robot.
Captions in English; no music under the voice-over.

| # | length | shot | what must be visible |
| --- | --- | --- | --- |
| 1 | 0:10 | Title over the Robots tab on iPhone | "Conduit 3.0 — Robots" |
| 2 | 0:15 | Profile editor: + → Mobile robot → topic lists fill from discovery | discovered Kachaka topics, a slot filled automatically |
| 3 | 0:10 | Open → the screen turns to landscape and the drive view comes up | camera, chips, mini map, stick, Slow / Fast, STOP |
| 4 | 0:20 | Split screen: phone HUD and the Kachaka driving forward, back, turning; Slow, then Fast | the robot moves the way the stick points |
| 5 | 0:10 | STOP mid-drive, then lifting the finger | the robot stops; "STOP is not an emergency stop" on screen |
| 6 | 0:10 | Mini map tapped → full map with LaserScan on the walls | robot marker and scan |
| 7 | 0:10 | A game controller drives; the on-screen joystick stays visible | controller in hand, robot moving |
| 8 | 0:10 | iPad: camera with map, status and diagnostics tiles | tile layout |
| 9 | 0:15 | Arm profile Open → landscape arm view over the wrist camera, Align | status chip and line, pose buttons, Align, Joints, gear, gripper arc, HOLD |
| 10 | 0:20 | Split screen: phone held in landscape with HOLD pressed, Panda simulation following | end effector moves with the phone; release stops it |
| 11 | 0:10 | Gripper arc dragged, then Open / Close | fingers open and close in the simulation; the readout's percentage |
| 12 | 0:10 | A pose button tapped | spinner and "Moving to …", the arm moving, then the button's checkmark |
| 13 | 0:10 | Joint limit reached | "Halted: joint bound" on the chip |
| 14 | 0:10 | Settings → Conduit Plus row | "Free: 5 hours of use every week" |
| 15 | 0:10 | End card | conduit.youtalk.jp/robots |

Recording setup: Kachaka with `ros2 launch conduit_teleop kachaka.launch.py` on the host that
drives it; the Panda from the robot harness (`docker/compose-robot-harness.yml --profile arm`)
shown in RViz full screen on the desktop host. The harness does not start `move_group`, so for
shot 12 also run a `move_group` for the Panda that publishes the SRDF, and
`ros2 launch conduit_teleop named_pose.launch.py planning_group:=panda_arm`. Upload the result to the site under
`docs/robots.md` → "Demo video" in the same form as the existing demo videos.
