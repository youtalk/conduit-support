# Known Issues & Limitations

Current limitations and known issues in Conduit.

## Privacy & Policy Constraints

### Background GPS Tracking Not Supported

**Status**: By design (privacy policy)

**Reason**: Apple requires "Always" location permission for background GPS tracking, which conflicts with our privacy-first approach.

**Current Behavior**:
- GPS data available while app is active (foreground)
- GPS stops when app enters background

**Workaround**:
- Keep app in foreground during GPS data collection
- Use background processing mode with other sensors

**Future**: No plans to change (privacy policy constraint)

---

## Platform Limitations

### visionOS: No GPS Sensor

**Status**: Hardware limitation

**Reason**: Apple Vision Pro is designed for indoor use without GPS hardware.

**Workaround**:
- Use WiFi positioning if available
- Pair with iPhone for GPS data
- Use visual odometry from cameras

### visionOS: Hand/Eye Tracking Not Implemented

**Status**: Feature not yet implemented

**Planned**: Future update will add:
- Hand tracking → sensor_msgs/Joy or custom message type
- Eye gaze tracking → geometry_msgs/PointStamped

**Current Workaround**: Use camera data for spatial tracking

### tvOS: Only Game Controller Supported

**Status**: Hardware limitation

**Reason**: Apple TV has no motion, location, or camera hardware.

**Use Case**: Limited to robot remote control via Siri Remote or MFi controllers

### macOS: No IMU/GPS Sensors

**Status**: Hardware limitation

**Reason**: Desktop Macs don't have accelerometer/gyroscope or GPS.

**Use Case**: macOS version mainly for development/testing and stationary camera use

---

## iOS Restrictions

### Camera/LiDAR Stop in Background

**Status**: iOS system restriction

**Reason**: iOS doesn't allow camera/ARKit usage in background.

**Workaround**: Keep app in foreground when using Camera or LiDAR sensors

### Proximity Sensor Only on iPhone

**Status**: Hardware limitation

**Reason**: iPads don't have proximity sensors.

**Workaround**: Use iPhone for proximity sensing, or use LiDAR for distance measurement

---

## Performance & Stability

### Multiple Cameras May Cause Memory Warnings

**Status**: Known issue

**Behavior**: Enabling 3-4 cameras simultaneously may trigger iOS memory warnings.

**Mitigation**:
- App automatically stops high-memory sensors on warning
- Reduce number of active cameras
- Lower camera resolution in settings

**Workaround**: Enable only cameras you need

### High Frame Rate May Cause Thermal Throttling

**Status**: Expected behavior

**Reason**: Continuous 100 Hz IMU + multi-camera can heat device.

**Mitigation**:
- iOS will throttle CPU/GPU when too hot
- Rates may automatically decrease

**Workaround**:
- Reduce publishing rates
- Disable unused sensors
- Allow device to cool between sessions

---

## Network & Connectivity

### Initial Connection Can Be Slow

**Status**: Normal behavior

**Reason**: Zenoh session establishment + version detection takes 2-5 seconds.

**Workaround**: Wait for "Publishing" state before expecting data

### Connection Lost Not Always Detected Immediately

**Status**: Known limitation

**Reason**: Zenoh uses keep-alive packets with timeout.

**Behavior**: May take 10-30 seconds to detect router failure.

**Workaround**: App will auto-detect after 3 consecutive publish failures

---

## Wire Format Compatibility

### rmw_zenoh_cpp Version Sensitivity

**Status**: By design

**Reason**: Wire format changes between rmw_zenoh_cpp versions.

**Mitigation**:
- Auto-detect mode handles most cases
- Manual Humble/Jazzy selection available

**Known Compatible Versions**:
- ROS 2 Humble: rmw_zenoh_cpp (Humble release)
- ROS 2 Jazzy: rmw_zenoh_cpp (Jazzy release)

**Workaround**: Use matching ROS 2 version and wire mode setting

---

## DDS Transport

### Camera/LiDAR fragmentation loss on DDS over WiFi

**Status**: Known limitation

**Reason**: Large RTPS messages (>1400 bytes — camera, LiDAR, CameraInfo with large K matrices) are split into UDP fragments. Consumer WiFi often drops or reorders fragments, especially over multicast.

**Mitigation**:
- Use **Unicast** or **Hybrid** discovery mode (Settings → Transport → DDS → Discovery Mode).
- Reduce camera resolution or LiDAR point density.
- Use wired Ethernet on the ROS 2 host if possible.

### CameraInfo requires BestEffort subscriber QoS

**Status**: By design

**Reason**: CameraInfo publishes with `BestEffort + TransientLocal` QoS (`latchedBestEffort`) to match DDS behavior on iOS. Standard `image_transport` subscribers default to `Reliable`, which does not match.

**Workaround**: Override the subscriber QoS:
```bash
ros2 topic echo /conduit/camera/front/camera_info \
  --qos-reliability best_effort \
  --qos-durability transient_local
```

### Disconnect delay on DDS (up to ~5 seconds)

**Status**: Workaround in place

**Reason**: DDS participant deletion is serialized on iOS to avoid a platform-specific deadlock in CycloneDDS's teardown path.

**Behavior**: Pressing Stop in the app can take 2-5 seconds to fully release the domain. This is intentional and safe.

### DDS requires WiFi — no cellular fallback

**Status**: By design

**Reason**: DDS discovery binds to a specific network interface (`en0` on iOS). Cellular or VPN interfaces are not supported; multicast/unicast discovery requires the device and the ROS 2 host to be on the same LAN.

**Workaround**: Use Zenoh transport with a public router address if cross-network/WAN operation is required.

---

## Premium Features

### Premium Purchase Required for Some Sensors

**Status**: By design (business model)

**Free Sensors**:
- IMU, GPS, Magnetic Field, Proximity, Barometer, Illuminance, Battery, Thermal, **Microphone**
- Front camera

**Premium Sensors / Features** (one-time In-App Purchase per item):
- LiDAR
- Wide / Ultra-wide / Telephoto cameras
- Game Controller
- **Background mode** — keep publishing while the app is backgrounded
- **MCAP Recording** — record live topics to a local `.mcap` file

### Premium Purchases Not Syncing

**Status**: Rare issue

**Reason**: App Store receipt verification delay.

**Solutions**:
1. Restart app
2. Restore purchases (Settings → Restore Purchases)
3. Verify Apple ID is correct

---

## Workaround Summary

| Issue | Workaround |
|-------|------------|
| Background GPS | Keep app in foreground |
| visionOS no GPS | Use iPhone/iPad |
| tvOS limited sensors | Use for Game Controller only |
| macOS no IMU | Use iPhone/iPad |
| Camera background | Keep app in foreground |
| Memory warnings | Reduce active sensors |
| Thermal throttling | Lower rates, fewer sensors |
| Connection slow | Wait 5 seconds for establishment |
| DDS fragmentation loss on WiFi | Use Unicast or Hybrid discovery; lower camera/LiDAR resolution |
| CameraInfo QoS mismatch | Subscriber: `--qos-reliability best_effort --qos-durability transient_local` |
| DDS disconnect delay | Expected behavior — no user action required |
| DDS over WAN / cellular | Use Zenoh transport with a public router instead |

---

## Reporting New Issues

Found a bug not listed here? **[Create an issue](https://github.com/youtalk/conduit-support/issues/new/choose)** with:
- Platform and OS version
- Sensor type affected
- Steps to reproduce
- Expected vs actual behavior

## Feature Requests

Want a new feature? **[Request it here](https://github.com/youtalk/conduit-support/issues/new?template=feature_request.yml)**

We prioritize based on:
- User impact
- Technical feasibility
- Platform constraints
- Development resources
