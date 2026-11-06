---
title: Sensors and topics
description: Every Conduit sensor with its ROS 2 topic, message type, default rate, frames and QoS.
---

# Sensors and topics

This page lists what Conduit publishes. Topic names use the default namespace `conduit`; if you change **Namespace** in Settings, replace `/conduit` with yours.

## Sensors

| Sensor | Topic | Message type | Default rate | Max rate | Platforms |
|---|---|---|---|---|---|
| IMU | `/conduit/imu` | `sensor_msgs/msg/Imu` | 100 Hz | 100 Hz | iPhone, iPad |
| Magnetic Field | `/conduit/magnetic_field` | `sensor_msgs/msg/MagneticField` | 100 Hz | 100 Hz | iPhone, iPad |
| Barometer | `/conduit/barometer` | `sensor_msgs/msg/FluidPressure` | 10 Hz | 10 Hz | iPhone, iPad |
| Illuminance | `/conduit/illuminance` | `sensor_msgs/msg/Illuminance` | 10 Hz | 10 Hz | iPhone, iPad |
| GPS | `/conduit/fix` | `sensor_msgs/msg/NavSatFix` | 1 Hz | 10 Hz | iPhone, iPad |
| Proximity | `/conduit/range` | `sensor_msgs/msg/Range` | 10 Hz | 10 Hz | iPhone |
| Device Pose (Conduit 3) | `/conduit/pose` and `/tf` | `geometry_msgs/msg/PoseStamped` | 60 Hz | 60 Hz | iPhone, iPad |
| Camera | `/conduit/camera/<camera>/image_raw/compressed` | `sensor_msgs/msg/CompressedImage` | 30 Hz | 60 Hz | iPhone, iPad, Mac |
| LiDAR | `/conduit/points` | `sensor_msgs/msg/PointCloud2` | 30 Hz | 60 Hz | iPhone Pro, iPad Pro |
| Microphone | `/conduit/audio` | `audio_common_msgs/msg/AudioData` | 16 Hz | 16 Hz | iPhone, iPad, Mac |
| Battery | `/conduit/battery_state` | `sensor_msgs/msg/BatteryState` | 1 Hz | 10 Hz | iPhone, iPad, Mac |
| Thermal | `/conduit/temperature` | `sensor_msgs/msg/Temperature` | 1 Hz | 10 Hz | iPhone, iPad, Mac |
| Game Controller | `/conduit/joy` | `sensor_msgs/msg/Joy` | 50 Hz | 60 Hz | iPhone, iPad, Mac |

Every sensor is off until you turn it on. To change a sensor's rate or QoS, stop publishing and tap the settings button under its toggle. See [Platform notes](platform-notes.md) for which devices have which sensors.

Notes on some sensors:

- **IMU** follows REP-145: `linear_acceleration` includes gravity (+9.81 m/s² on the up axis at rest), and `orientation` is relative to ENU with magnetic east. Conduit does not correct for magnetic declination; correct it on the host if you need true north (for example with `magnetic_declination_radians` in `navsat_transform_node`).
- **Illuminance** is estimated from the camera's exposure. It uses the camera, so it cannot run together with a camera stream, LiDAR or Device Pose; Conduit asks before it turns the other one off.
- **Thermal** is an estimate from the system thermal state (nominal, fair, serious, critical), not a temperature sensor reading.
- **Proximity** is a near/far reading from the sensor at the top of the iPhone's screen.
- **Microphone** sends 16 kHz, mono, 16-bit signed little-endian samples, 1024 samples per message. `AudioData` has no header. See the [FAQ](faq.md#microphone) for how to receive it.
- **Game Controller** uses the layout of the ROS 2 `joy` package's `game_controller_node`. See [Teleoperation](teleop.md#joy-layout).
- **Device Pose** (Conduit 3) uses ARKit world tracking. It publishes only while tracking is normal. It cannot run together with Illuminance or with a camera stream, except the wide camera while LiDAR is on.

## Camera topics

Each camera publishes on its own topics under `/conduit/camera/<camera>/`:

| Camera | `<camera>` | Optical frame |
|---|---|---|
| Front | `front` | `camera_front_optical_frame` |
| Wide (back) | `wide` | `camera_back_optical_frame` |
| Ultra Wide (back) | `ultrawide` | `camera_ultrawide_optical_frame` |
| Telephoto (back) | `telephoto` | `camera_telephoto_optical_frame` |

You see only the cameras your device has. You can turn on several at once. The front camera is free; the back cameras need the Back Cameras In-App Purchase. On a Mac, Conduit uses the built-in FaceTime HD camera only.

Each camera's settings sheet has:

- **Output**: **Compressed** publishes JPEG images on `image_raw/compressed` (`sensor_msgs/msg/CompressedImage`). **Raw** publishes uncompressed `bgra8` images on `image_raw` (`sensor_msgs/msg/Image`). Raw images are much larger, so use them on a fast network.
- **Resolution**: QVGA (320 × 240), VGA (640 × 480, the default), 720p (1280 × 720) or 1080p (1920 × 1080). The image is rotated to match the **Mounting** setting.
- **JPEG Quality**: 10 to 100 %, 80 % by default (Compressed only).
- **Rate** and **QoS**.

Each camera also publishes `camera_info` (`sensor_msgs/msg/CameraInfo`) for the published image size. Conduit uses the camera's calibration when iOS provides it, and otherwise estimates the intrinsics from the field of view. `camera_info` is latched, so a subscriber that joins late still receives it.

Higher resolutions and quality settings can lower the achieved frame rate.

## LiDAR

LiDAR needs an iPhone 12 Pro or later Pro model, or an iPad Pro (2020 or later), and the LiDAR In-App Purchase. It uses ARKit, which provides only the wide back camera: while LiDAR is on, only the wide camera streams, and turning on another camera turns LiDAR off (Conduit asks first).

The LiDAR settings sheet has an **Output** setting:

| Output | Publishes |
|---|---|
| **Point Cloud** (default) | `/conduit/points` (`sensor_msgs/msg/PointCloud2`, fields `x`, `y`, `z`, in `lidar_link`) |
| **Depth** | `/conduit/camera/wide/depth/image_raw` (`sensor_msgs/msg/Image`, `16UC1`, millimeters, `0` = no depth) and `/conduit/camera/wide/depth/camera_info` |
| **Both** | All of the above |

The depth image is aligned with the wide camera and uses `camera_back_optical_frame`. With the wide camera also on, LiDAR mode takes the color image from ARKit and publishes it on `/conduit/camera/wide/image_raw/compressed` with `/conduit/camera/wide/camera_info`. In LiDAR mode the color image is always compressed; the camera's resolution, JPEG quality and rate settings still apply.

Messages from the same ARKit frame carry the same `header.stamp`, the time ARKit captured the frame. Match a color image with its depth image by equal stamps. See [Capture an RGB and depth pair](on-demand-capture.md#capture-an-rgb-and-depth-pair).

The depth topics use the LiDAR sensor's QoS, which is best effort by default. Nodes that subscribe reliably, such as `depth_image_proc`, need the LiDAR QoS set to **Reliable**, or a best-effort QoS override on the subscriber.

### Point cloud compression

With **Enable Compression** on, Conduit publishes `/conduit/points/compressed` (`point_cloud_interfaces/msg/CompressedPointCloud2`) **instead of** `/conduit/points`. Formats:

- **Draco**: lossy, best compression ratio.
- **Zstd** (default): lossless, good balance of speed and ratio.
- **Zlib**: lossless.

**Level** goes from 1 to 9 (default 5). Higher levels compress more and take longer.

## Frames and TF

Conduit publishes the transforms between its frames on `/tf_static` (`tf2_msgs/msg/TFMessage`). It is a global topic, not under the namespace. It is latched (reliable, transient local), so tools that start later, such as RViz, still receive it.

All frames are children of `conduit_base_link`:

- `conduit_base_link`: x forward (where the back camera looks), y left, z up (REP-103). The origin is at the IMU.
- `imu_link`, `magnetometer_link`, `barometer_link`, `thermal_link`, `battery_link`: at the origin, same axes.
- `gps_link`, `microphone_link`, `illuminance_link`: same axes as `conduit_base_link`.
- `lidar_link`: same axes as `conduit_base_link`, at the wide camera. `/conduit/points` is in this frame.
- `proximity_link`: x points out of the screen, because `sensor_msgs/Range` measures along x.
- `camera_back_optical_frame`, `camera_ultrawide_optical_frame`, `camera_telephoto_optical_frame`, `camera_front_optical_frame`: optical frames (x right, y down, z forward) in the published image.

Sensor offsets are approximate, based on an iPhone 14 Pro.

The **Mounting** setting (Settings → ROS 2 Node) says how the device is held. In both options the back camera faces forward (+x):

- **Portrait**: top of the phone up.
- **Landscape**: top of the phone to the left.

Pick the one that matches how the device is mounted on your robot. Mounting changes the frames, the IMU axes and the image rotation together. You cannot change it while publishing or recording.

### Device Pose frames (Conduit 3)

Device Pose publishes `conduit_base_link` in `conduit_odom` on `/conduit/pose` and on `/tf` (a global topic). `conduit_odom` is gravity aligned with z up; its origin and yaw are the device pose when the ARKit session started. A pose carries the stamp of the ARKit frame it came from, so it shares the stamp with color and depth images from the same frame. Not every image has a pose: poses pause while tracking is not normal.

## QoS defaults

| Topics | Reliability | Durability | History |
|---|---|---|---|
| Sensor topics | Best effort | Volatile | Keep last 10 |
| `/conduit/joy` | Reliable | Volatile | Keep last 10 |
| `camera_info` (camera without LiDAR) | Best effort | Transient local | Keep last 1 |
| `/tf_static` | Reliable | Transient local | Keep last 1 |

You can change **Reliability** (Best Effort / Reliable) and **History Depth** (1 to 100) per sensor. A subscriber that asks for reliable delivery does not receive a best-effort topic; subscribe with best effort (`qos_profile_sensor_data` in rclpy, `--qos-reliability best_effort` with `ros2 topic`), or set the sensor to Reliable.

The Game Controller is reliable by default because `joy` consumers such as `teleop_twist_joy` subscribe reliably.

To send data only while a subscriber is connected, turn on **Publish only when subscribed**. See [On-demand capture](on-demand-capture.md).

## Namespace and node name

Settings → ROS 2 Node:

- **Node Name**: `conduit_node` by default.
- **Namespace**: `conduit` by default. Every sensor topic is under it, for example `/conduit/imu`. `/tf_static` and `/tf` are always global.
