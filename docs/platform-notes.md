# Platform notes

Conduit runs on iPhone and iPad (iOS and iPadOS 16 or later) and on Mac (macOS 13 or later, as a Mac Catalyst app). The sensors you can use depend on the device. For every topic, message type and rate, see [Sensors and topics](sensors.md).

## Sensors by platform

| Sensor | iPhone | iPad | Mac |
|---|---|---|---|
| IMU | ✅ | ✅ | ❌ |
| Magnetic Field | ✅ | ✅ | ❌ |
| Barometer | ✅ | ✅ | ❌ |
| Illuminance | ✅ | ✅ | ❌ |
| GPS | ✅ | ✅ | ❌ |
| Proximity | ✅ | ❌ | ❌ |
| Device Pose (Conduit 3) | ✅ | ✅ | ❌ |
| Camera | ✅ | ✅ | ✅ built-in camera only |
| LiDAR | ✅ iPhone 12 Pro and later Pro models | ✅ iPad Pro (2020 and later) | ❌ |
| Microphone | ✅ | ✅ | ✅ |
| Battery | ✅ | ✅ | ✅ |
| Thermal | ✅ | ✅ | ✅ |
| Game Controller | ✅ | ✅ | ✅ |

A sensor the device does not have shows as **Not Available**. Tap it to see the reason.

## iPhone

iPhone has all 13 sensors.

- **LiDAR** needs an iPhone 12 Pro or a later Pro model.
- **Cameras**: the front camera and the back cameras your model has (Wide, Ultra Wide, Telephoto). While LiDAR is on, only the Wide camera streams, because ARKit provides only that camera.
- **Illuminance** is estimated from the camera's exposure, so it cannot run together with a camera stream, LiDAR or Device Pose.
- **Device Pose** (Conduit 3) uses ARKit world tracking and publishes only while tracking is normal.

## iPad

iPad has every sensor except Proximity.

- **LiDAR** needs an iPad Pro (2020 or later).
- **GPS**: iPad models without cellular have no GPS receiver. Location then comes from Wi-Fi and is less accurate.
- **Cameras**: an iPad with Center Stage shows its front camera once, as the front camera.

## Mac (Mac Catalyst)

On a Mac, Conduit can use:

- **Camera**: the built-in FaceTime HD camera. External cameras and Continuity Camera are not listed.
- **Microphone**
- **Battery**: on a Mac with a battery.
- **Thermal**
- **Game Controller**

Macs have no motion sensors, GPS, barometer or LiDAR, so those sensors show as **Not Available**.

In [Robots](robots.md) (Conduit 3), the robot arm view only watches on a Mac; moving the arm needs an iPhone or iPad.

## Background publishing

Settings → Publishing → **Background Publishing** keeps sensors publishing after you leave the app. It needs the Background Mode In-App Purchase.

- Camera and LiDAR stop in the background (iOS restriction).
- The other sensors keep publishing until iOS suspends the app, which it can do at any time.

Keep Conduit in the foreground when you need data for a long time. See [Known issues](known-issues.md).

## Network

- **Zenoh** works over any network that can reach the router over TCP, including a Tailscale tailnet.
- **DDS** needs the device and the ROS 2 host on the same LAN. On iPhone and iPad, select **en0 (WiFi)** as the network interface (Settings → Discovery).

See [Transports](transports.md).
