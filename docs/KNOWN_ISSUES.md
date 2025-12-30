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

## Premium Features

### Premium Purchase Required for Some Sensors

**Status**: By design (business model)

**Free Sensors**:
- IMU, GPS, Magnetic Field, Proximity, Barometer, Illuminance, Battery, Thermal
- Front camera

**Premium Sensors**:
- LiDAR
- Wide/Ultra-wide/Telephoto cameras
- Game Controller

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
