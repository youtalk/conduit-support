# Conduit 3.0 demo video — shot list

Target length 3:00, landscape 1080p, screen recording plus a second camera on the robot.
Captions in English; no music under the voice-over.

| # | length | shot | what must be visible |
| --- | --- | --- | --- |
| 1 | 0:10 | Title over the iPhone main screen; the robot button in the toolbar opens the Robots list | "Conduit 3.0 — Robots" |
| 2 | 0:15 | Profile editor: + → Mobile robot → Start under the "Discover your robot" tip → the fields fill in | discovered Kachaka topics and frames filled in, a field's list of discovered topics |
| 3 | 0:10 | Open with the phone held in landscape: the drive view comes up as it is held | camera, chips, mini map, stick, gear |
| 4 | 0:20 | Split screen: phone HUD and the Kachaka driving forward, back, turning; the gear's Max speed raised from 50% to 100% | the robot moves the way the stick points, faster after the change |
| 5 | 0:10 | Lifting the finger mid-drive | the robot stops; caption "Conduit is not an emergency stop" |
| 6 | 0:10 | Mini map tapped → full map with LaserScan on the walls; Set goal, then a drag on the map | robot marker and scan, the goal arrow |
| 7 | 0:10 | A game controller drives; the on-screen joystick stays visible | controller in hand, the "Game controller" chip, robot moving |
| 8 | 0:10 | iPad: camera with Map, Status and Diagnostics tiles | tile layout |
| 9 | 0:15 | Arm profile Open → arm view over the wrist camera, Align | status chips and line, pose menu next to Align, gear, gripper arc, HOLD |
| 10 | 0:20 | Split screen: phone held in landscape with HOLD pressed, Panda simulation following | end effector moves with the phone; release stops it |
| 11 | 0:10 | Gripper arc dragged, then tapped to open and close | fingers open and close in the simulation; the readout's percentage |
| 12 | 0:10 | The pose menu opened and a pose picked | the SRDF's poses with the current one checked, then the button's spinner and "Moving to …", the arm moving, then the teal button showing the new pose |
| 13 | 0:10 | Joint limit reached | "Halted: joint bound" on the chip |
| 14 | 0:10 | The free plan's dial around the Start button, then Settings → Conduit Plus | the dial; "Free: 5 hours of use every week. Conduit Plus removes the limit." |
| 15 | 0:10 | End card | conduit.youtalk.jp/robots |

Recording setup: Kachaka with `ros2 launch conduit_teleop kachaka.launch.py` on the host that
drives it, and a Kachaka profile whose **Goal pose** is the topic Kachaka takes goals on (shot 6).
The Panda from the robot harness (`docker/compose-robot-harness.yml --profile arm`) is shown in
RViz full screen on the desktop host. The harness does not start `move_group`, so for shot 12
also run a `move_group` for the Panda that publishes the SRDF (`/robot_description_semantic`) and
serves `/move_action`, next to the harness's Servo. The pose menu appears once the SRDF arrives
and lists the group states of the Panda's arm group, spelled as in its SRDF. Record on an account
without Conduit Plus so the dial shows (shot 14). Upload the result to the site under
`docs/robots.md` → "Demo video" in the same form as the existing demo videos.

<!-- TODO(owner): the video URL goes into docs/robots.md ("Demo video") and the App Review
     notes once the video is uploaded. -->
