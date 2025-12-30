# Frequently Asked Questions

## Setup & Configuration

### How do I connect Conduit to my ROS 2 system?

1. Start the Zenoh router on your ROS 2 system:
   ```bash
   source /opt/ros/jazzy/setup.bash
   export RMW_IMPLEMENTATION=rmw_zenoh_cpp
   ros2 run rmw_zenoh_cpp rmw_zenohd
   ```

2. Find your ROS 2 system's IP address:
   ```bash
   ip addr show  # Linux
   ifconfig      # macOS
   ```

3. In Conduit app:
   - Tap Settings (gear icon)
   - Enter Router Address (e.g., `192.168.1.100`)
   - Enter Router Port (default: `7447`)
   - Tap Save

4. Enable sensors and tap Play

### Which ROS 2 versions are supported?

Conduit supports:
- **ROS 2 Humble** (Ubuntu 22.04)
- **ROS 2 Jazzy** (Ubuntu 24.04)

Both versions require rmw_zenoh_cpp middleware. The app auto-detects which version you're using.

### Why can't I see my topics in `ros2 topic list`?

**Check these common issues:**

1. **Zenoh router not running**:
   ```bash
   # Start router
   ros2 run rmw_zenoh_cpp rmw_zenohd
   ```

2. **Wrong RMW implementation**:
   ```bash
   # Verify RMW setting
   echo $RMW_IMPLEMENTATION
   # Should output: rmw_zenoh_cpp
   ```

3. **Network connectivity**: Ensure iPhone and ROS 2 system are on the same network

4. **Firewall blocking port 7447**: Check firewall settings on ROS 2 system

### What's the difference between Humble and Jazzy wire modes?

- **Jazzy**: Uses type hash in key expressions (RIHS01_...)
- **Humble**: Uses "TypeHashNotSupported" instead of type hash
- **Auto-detect**: App queries Zenoh admin space to determine version (recommended)

Use "Auto-detect" unless you're experiencing specific compatibility issues.

### Can I use Conduit without a ROS 2 system?

Yes, for testing:
- The iOS Simulator generates mock sensor data
- You can verify app functionality without ROS 2
- However, you won't be able to receive data without a Zenoh router

For production use, you need:
- ROS 2 Humble or Jazzy
- rmw_zenoh_cpp middleware
- Zenoh router running

### Which sensors work on which platforms?

| Platform | Available Sensors |
|----------|-------------------|
| **iOS/iPadOS** | All 11 sensors (IMU, GPS, Camera, LiDAR*, Magnetometer, Barometer, Battery, Thermal, Proximity†, Illuminance, Game Controller) |
| **visionOS** | Camera, IMU, Game Controller |
| **tvOS** | Game Controller only |
| **macOS** | Camera, Battery, Game Controller |

*LiDAR requires iPhone 12 Pro or newer, iPad Pro 2020+, Vision Pro
†Proximity sensor only on iPhone (not iPad)

### How do I enable background mode?

1. Tap Settings → Enable "Background Mode"
2. Grant location permission if using GPS

**Limitations:**
- GPS background tracking not supported (privacy constraints)
- Camera and LiDAR stop in background (iOS restrictions)
- Only IMU, GPS (foreground), Magnetometer, Barometer, Battery, Thermal continue in background

### What are the premium features?

**Free features:**
- IMU, GPS, Magnetometer, Barometer, Battery, Thermal, Proximity, Illuminance
- Front camera
- Background processing mode (basic)

**Premium features** (In-App Purchase):
- **LiDAR sensor** - Point cloud depth sensing
- **Multi-camera** - Wide, ultra-wide, telephoto cameras
- **Game Controller** - Bluetooth controller input

### How do I verify data is being published?

On your ROS 2 system:

```bash
# Check if topic appears
ros2 topic list | grep ios

# Echo data from IMU sensor
ros2 topic echo /ios/imu

# Check publish rate
ros2 topic hz /ios/imu

# View topic info
ros2 topic info /ios/imu --verbose
```

### Why is my sensor showing "Not Available"?

**Common reasons:**

1. **Hardware limitation**: Device doesn't have that sensor
   - LiDAR: iPhone 12 Pro+ only
   - Barometer: iPhone 6+ only
   - Proximity: iPhone only (not iPad)

2. **Platform limitation**:
   - visionOS: No GPS (indoor device)
   - tvOS: Only Game Controller
   - macOS: No IMU/GPS/Magnetometer

3. **Permission denied**: Grant permission in Settings → Privacy

4. **Runtime unavailable**:
   - Game Controller: No controller connected
   - Location: Location services disabled

### Can I use multiple cameras simultaneously?

Yes! Conduit supports multi-camera streaming:

1. Tap the Camera sensor row
2. Select multiple cameras (front, wide, ultra-wide, telephoto)
3. Each camera publishes to separate topic:
   - `/ios/camera/front/compressed`
   - `/ios/camera/wide/compressed`
   - `/ios/camera/ultrawide/compressed`
   - `/ios/camera/telephoto/compressed`

**Note:** Wide, ultra-wide, and telephoto cameras require Premium unlock.

### How do I change the publishing rate?

1. Tap the gear icon ⚙️ next to any sensor
2. Adjust "Rate (Hz)" slider
3. Configure QoS settings if needed
4. Tap Save

Different sensors have different maximum rates (see Supported Sensors table).

### Does Conduit work offline?

No. Conduit requires network connectivity to:
- Connect to Zenoh router on your local network
- Publish sensor data to ROS 2 topics

However, **no internet is required** - only local network between your iOS device and ROS 2 system.

### How do I reset app settings?

1. Delete and reinstall the app, OR
2. iOS Settings → Conduit → Reset (if available)

This will clear:
- Saved router address
- Sensor configurations
- Premium purchase status is preserved (linked to Apple ID)

### Is my data sent to the cloud?

**No.** All sensor data:
- Stays on your local network
- Sent only to your configured Zenoh router
- Never uploaded to external servers
- Never shared with third parties

Firebase Analytics collects anonymous app usage statistics only (opt-out available in iOS Settings).

See our [Privacy Policy](https://www.youtalk.jp/conduit/#privacy-policy) for details.
