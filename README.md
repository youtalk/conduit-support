<div align="center">

<img src="images/app_icon.png" width="128" height="128" alt="Conduit App Icon">

# Conduit

**Transform your Apple devices into ROS 2 sensor publishers**

Stream real-time sensor data directly to your robotics system via Zenoh — no bridge required.

[![Download on App Store](https://img.shields.io/badge/Download-App%20Store-blue?style=for-the-badge&logo=apple)](https://apps.apple.com/jp/app/conduit-powered-by-ros/id6757171237?l=en-US)
[![ROS 2](https://img.shields.io/badge/ROS%202-Humble%20|%20Jazzy%20|%20Kilted%20|%20Rolling-green?style=for-the-badge)](https://ros.org)

</div>

---

## Demo Videos

<table>
<tr>
<td align="center">
<a href="https://www.youtube.com/watch?v=d28sQYQlpYY">
<img src="https://img.youtube.com/vi/d28sQYQlpYY/0.jpg" width="280" alt="Demo 1">
</a>
</td>
<td align="center">
<a href="https://www.youtube.com/watch?v=ObnJOpGvpzI">
<img src="https://img.youtube.com/vi/ObnJOpGvpzI/0.jpg" width="280" alt="Demo 2">
</a>
</td>
<td align="center">
<a href="https://www.youtube.com/watch?v=2myDfnNBuuk">
<img src="https://img.youtube.com/vi/2myDfnNBuuk/0.jpg" width="280" alt="Demo 3">
</a>
</td>
</tr>
</table>

---

## Features

| Platform | Sensors |
|----------|---------|
| iOS/iPadOS 16+ | All 12 sensors |
| visionOS 1+ | Camera, IMU, Game Controller |
| macOS 13+ | Camera, Battery, Game Controller |

### 12 Sensor Types

**Motion**: IMU (100Hz) · Magnetometer (100Hz) · GPS (1Hz) · Proximity (10Hz)

**Perception**: Camera (15Hz) · LiDAR (10Hz)

**Environment**: Barometer (10Hz) · Illuminance (10Hz) · Temperature (1Hz)

**Input**: Game Controller (50Hz) · Microphone

**Status**: Battery (1Hz)

---

## Screenshots

<!-- Add screenshots to images/ directory and uncomment below:
<table>
<tr>
<td><img src="images/screenshot_main.png" width="200" alt="Main UI"></td>
<td><img src="images/screenshot_settings.png" width="200" alt="Settings"></td>
<td><img src="images/screenshot_publishing.png" width="200" alt="Publishing"></td>
<td><img src="images/screenshot_ros2.png" width="400" alt="ROS 2 Terminal"></td>
</tr>
</table>
-->

*Coming soon*

---

## Quick Start

1. **Download** from [App Store](https://apps.apple.com/jp/app/conduit-powered-by-ros/id6757171237?l=en-US)
2. **Start Zenoh Router** on your ROS 2 system
3. **Configure** Router Address in Settings (e.g., `tcp/192.168.1.100:7447`)
4. **Enable** sensors you want to stream
5. **Tap Play** and verify with `ros2 topic echo /ios/imu`

---

## Zenoh Router (Docker)

### Quick Start (Pre-built Image)

```bash
# ROS 2 Jazzy
docker run -d -p 7447:7447 --name ros_jazzy_zenoh ghcr.io/youtalk/conduit-support:jazzy

# ROS 2 Humble
docker run -d -p 7447:7447 --name ros_humble_zenoh ghcr.io/youtalk/conduit-support:humble
```

### Using Docker Compose

```bash
git clone https://github.com/youtalk/conduit-support.git
cd conduit-support/docker

# Start Jazzy router
docker compose up ros-jazzy -d

# Start Humble router
docker compose up ros-humble -d

# Stop
docker compose down
```

### Verify Connection

```bash
# Check topics
docker exec ros_jazzy_zenoh bash -c \
  "source /opt/ros/jazzy/setup.bash && ros2 topic list"

# Echo IMU data
docker exec ros_jazzy_zenoh bash -c \
  "source /opt/ros/jazzy/setup.bash && ros2 topic echo /ios/imu"
```

### Configure Conduit App

1. Find your Mac's IP address: `ifconfig | grep inet`
2. In Conduit Settings, set Router Address to: `tcp/<YOUR_IP>:7447`
3. Tap Play to connect

---

## Documentation

- [FAQ](docs/FAQ.md) - Frequently asked questions
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Platform Notes](docs/PLATFORM_NOTES.md) - Platform-specific information
- [Known Issues](docs/KNOWN_ISSUES.md) - Current limitations and workarounds

---

## Support

- [Report Bug / Request Feature](https://github.com/youtalk/conduit-support/issues/new/choose)
- [Community Discussions](https://github.com/youtalk/conduit-support/discussions)

---

## Links

- [App Website](https://www.youtalk.jp/conduit)
- [Source Code](https://github.com/youtalk/conduit)
- [Privacy Policy](https://www.youtalk.jp/conduit/#privacy-policy)

---

**Developer**: [Yutaka Kondo](https://www.linkedin.com/in/youtalk) — Autoware maintainer and robotics engineer at TIER IV
