<div align="center">

<a href="https://apps.apple.com/app/id6757171237">
<img src="images/app_icon.png" width="128" height="128" alt="Download Conduit on the App Store">
</a>

# Conduit

</div>

**Transform your Apple devices into ROS 2 sensor publishers**

Stream real-time sensor data directly to your robotics system via **Zenoh** or **DDS** — pick the transport that matches your ROS 2 setup. No bridge, no `rcl` / `rclcpp`, no CMake on a non-Linux host.
Used cumulatively by **10,000+ ROS 2 developers worldwide** — peaked at **#4 in the App Store's Developer Tools category** (Japan) since January 2026.

[![ROS 2](https://img.shields.io/badge/ROS%202-Humble%20|%20Jazzy%20|%20Kilted%20|%20Rolling-22314E?style=for-the-badge)](https://docs.ros.org)
[![Built on swift-ros2](https://img.shields.io/badge/Built%20on-swift--ros2%200.6.0-orange?style=for-the-badge&logo=swift)](https://github.com/youtalk/swift-ros2)

---

## Demo Videos

<table>
<tr>
<td align="center" width="33%">
<a href="https://www.youtube.com/watch?v=d28sQYQlpYY">
<img src="https://img.youtube.com/vi/d28sQYQlpYY/0.jpg" width="280" alt="Teleoperation Demo"><br>
<b>Teleoperation</b>
</a><br>
<sub>Control robots using Game Controller sensor via ROS 2 joy messages</sub>
</td>
<td align="center" width="33%">
<a href="https://www.youtube.com/watch?v=ObnJOpGvpzI">
<img src="https://img.youtube.com/vi/ObnJOpGvpzI/0.jpg" width="280" alt="Camera & LiDAR Demo"><br>
<b>Camera & LiDAR</b>
</a><br>
<sub>Stream iPhone camera images and LiDAR point clouds to ROS 2</sub>
</td>
<td align="center" width="33%">
<a href="https://www.youtube.com/watch?v=2myDfnNBuuk">
<img src="https://img.youtube.com/vi/2myDfnNBuuk/0.jpg" width="280" alt="Onboarding Demo"><br>
<b>Getting Started</b>
</a><br>
<sub>Step-by-step guide to connect Conduit with your ROS 2 system</sub>
</td>
</tr>
</table>

---

## Built on swift-ros2

All ROS 2 wire work — Zenoh / DDS FFI, XCDR v1 codec, Humble/Jazzy/Kilted/Rolling wire codecs, the publisher/subscription API — is delegated to [**swift-ros2**](https://github.com/youtalk/swift-ros2), a native Swift client library for ROS 2 that was extracted from Conduit and now ships independently.

swift-ros2 covers every consumer device OS that runs Swift: **iOS / iPadOS / macOS / Mac Catalyst / visionOS** (pre-built xcframeworks via SwiftPM), plus **Linux** (Ubuntu 22.04 / 24.04, x86_64 + aarch64), **Windows** (x86_64), and **Android** (arm64-v8a + x86_64) via source build. By worldwide market share, that's roughly 90%+ of identifiable consumer devices — phones, tablets, laptops, headsets, SBCs — all able to publish and subscribe through the same SwiftPM-resolvable package.

If you want to wire your own Swift app into a ROS 2 graph (rather than use Conduit as a black-box sensor publisher), [swift-ros2](https://github.com/youtalk/swift-ros2) is the SDK underneath this app.

---

## Features

| Platform | Sensors |
|----------|---------|
| iOS / iPadOS 16+ | All 12 sensors |
| visionOS 1+ | Camera, IMU, Game Controller |
| macOS 13+ (Mac Catalyst) | Camera, Battery, Game Controller |

### Transports

| Transport | ROS 2 RMW | Bridge required | Best for |
|-----------|-----------|-----------------|----------|
| **Zenoh** | `rmw_zenoh_cpp` | Yes (Zenoh router) | Cross-subnet, WAN, corporate networks |
| **DDS**   | `rmw_cyclonedds_cpp` | No (direct) | Same-LAN, standard ROS 2 |

See [TRANSPORTS.md](docs/TRANSPORTS.md) for a detailed comparison.

### 12 Sensor Types

- **Motion**: IMU (100Hz) · Magnetometer (100Hz) · GPS (1Hz) · Proximity (10Hz)
- **Perception**: Camera (15Hz) · LiDAR (10Hz)
- **Environment**: Barometer (10Hz) · Illuminance (10Hz) · Temperature (1Hz)
- **Input**: Game Controller (50Hz) · Microphone
- **Status**: Battery (1Hz)

---

## Screenshots

### Sensor Tabs

<table>
<tr>
<td align="center" width="25%">
<img src="images/motion-enabled.png" width="180" alt="Motion Sensors"><br>
<b>Motion</b><br>
<sub>IMU, GPS, Magnetometer, Proximity</sub>
</td>
<td align="center" width="25%">
<img src="images/perception-enabled.png" width="180" alt="Perception Sensors"><br>
<b>Perception</b><br>
<sub>Camera, LiDAR</sub>
</td>
<td align="center" width="25%">
<img src="images/status-enabled.png" width="180" alt="Status Sensors"><br>
<b>Status</b><br>
<sub>Battery, Thermal, Barometer, etc.</sub>
</td>
<td align="center" width="25%">
<img src="images/settings.png" width="180" alt="Settings"><br>
<b>Settings</b><br>
<sub>Router, Node, ROS 2 Distribution</sub>
</td>
</tr>
</table>

### Getting Started

<table>
<tr>
<td align="center" width="25%">
<img src="images/onboarding1.png" width="180" alt="Step 1: Start Router"><br>
<b>1. Start Zenoh Router</b><br>
<sub>Run rmw_zenohd on your ROS 2 system</sub>
</td>
<td align="center" width="25%">
<img src="images/onboarding2.png" width="180" alt="Step 2: Connect"><br>
<b>2. Connect to Router</b><br>
<sub>Enter IP address and port</sub>
</td>
<td align="center" width="25%">
<img src="images/onboarding3.png" width="180" alt="Step 3: Publish"><br>
<b>3. Start Publishing</b><br>
<sub>Select sensors and stream to ROS 2</sub>
</td>
</tr>
</table>

---

## Quick Start

1. **Download** from the [App Store](https://apps.apple.com/app/id6757171237)
2. **Choose your transport** — see [TRANSPORTS.md](docs/TRANSPORTS.md)

### Quick Start — Zenoh

1. Start the Zenoh router on your ROS 2 system:
   ```bash
   source /opt/ros/jazzy/setup.bash
   export RMW_IMPLEMENTATION=rmw_zenoh_cpp
   export ROS_DOMAIN_ID=0  # Valid range: 0-232
   ros2 run rmw_zenoh_cpp rmw_zenohd
   ```
2. In the Conduit app: Settings → Transport: **Zenoh**, enter the host IP and port `7447`, set Domain ID to match.
3. Enable sensors and tap Play.
4. Verify: `ros2 topic echo /conduit/imu`

### Quick Start — DDS

1. On your ROS 2 host:
   ```bash
   source /opt/ros/jazzy/setup.bash
   export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
   export ROS_DOMAIN_ID=0  # Valid range: 0-232
   ros2 topic list
   ```
2. In the Conduit app: Settings → Transport: **DDS**, Discovery Mode: **Hybrid**, add the host IP to Unicast Peers, Network Interface: `en0`, set Domain ID to match.
3. Enable sensors and tap Play.
4. Verify: `ros2 topic echo /conduit/imu --qos-reliability best_effort`

---

## Docker Test Environments

### Zenoh Router (Docker)

Pre-built images on ghcr.io:
```bash
# ROS 2 Jazzy
docker run -d -p 7447:7447 --name ros_jazzy_zenoh ghcr.io/youtalk/conduit-support:jazzy
# ROS 2 Humble
docker run -d -p 7447:7447 --name ros_humble_zenoh ghcr.io/youtalk/conduit-support:humble
```

Or with Docker Compose:
```bash
git clone https://github.com/youtalk/conduit-support.git
cd conduit-support/docker

# Default domain ID (0)
docker compose up ros-jazzy -d

# Custom domain ID via .env (recommended for persistence)
echo "ROS_DOMAIN_ID=5" > .env
docker compose up ros-jazzy -d

# Or override per-invocation
ROS_DOMAIN_ID=5 docker compose up ros-jazzy -d

# Stop
docker compose down
```

### DDS Subscriber (Docker, Linux only)

> **macOS note:** Docker Desktop on macOS does not provide true host networking, so the container cannot receive DDS traffic from an iOS device on the same LAN. On macOS, run your DDS subscriber natively or in a Parallels/UTM VM.

```bash
cd conduit-support/docker
echo "ROS_DOMAIN_ID=0" > .env
docker compose -f compose-dds.yml up -d

# Verify
docker exec -it ros_jazzy_dds bash
source /opt/ros/jazzy/setup.bash
ros2 topic list
ros2 topic echo /conduit/imu --qos-reliability best_effort
```

See [docker/README.md](docker/README.md) for the complete Docker guide.

---

## Documentation

- [Transports](docs/TRANSPORTS.md) — Zenoh vs DDS comparison and when to use each
- [FAQ](docs/FAQ.md) — Frequently asked questions
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) — Common issues and solutions
- [Platform Notes](docs/PLATFORM_NOTES.md) — Platform-specific information
- [Known Issues](docs/KNOWN_ISSUES.md) — Current limitations and workarounds
- [Privacy Policy](PRIVACY.md) — Data handling, sensor permissions, analytics

---

## Support

- [Report Bug / Request Feature](https://github.com/youtalk/conduit-support/issues/new/choose)
- [Community Discussions](https://github.com/youtalk/conduit-support/discussions)

---

## Links

- [App Website](https://www.youtalk.jp/conduit)
- [Source Code](https://github.com/youtalk/conduit)
- [swift-ros2 (underlying ROS 2 client library)](https://github.com/youtalk/swift-ros2)
- [Privacy Policy](PRIVACY.md)
