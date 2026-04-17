# Troubleshooting Guide

Common issues and solutions for Conduit.

> **Which transport are you using?** Check Settings → Transport in the Conduit app. Zenoh and DDS have different failure modes. Zenoh issues are under "## Connection Issues" and "## Topic Issues" below; DDS-specific issues are in "## DDS Transport Issues" near the bottom of this page.

## Connection Issues

### "Connection Failed: Timeout"

**Problem**: App cannot reach the Zenoh router.

**Solutions:**

1. **Verify router is running**:
   ```bash
   # On ROS 2 system
   ps aux | grep rmw_zenohd

   # If not running, start it
   source /opt/ros/jazzy/setup.bash
   export RMW_IMPLEMENTATION=rmw_zenoh_cpp
   ros2 run rmw_zenoh_cpp rmw_zenohd
   ```

2. **Check IP address**:
   ```bash
   # Get your ROS 2 system's IP
   ip addr show | grep "inet "  # Linux
   ifconfig | grep "inet "      # macOS
   ```
   - Update router address in app Settings

3. **Verify same network**: iPhone and ROS 2 system must be on same WiFi/LAN

4. **Test connectivity**:
   ```bash
   # From iPhone, ping ROS 2 system
   # Or from ROS 2 system, ping iPhone
   ping <device-ip>
   ```

### "Connection Refused"

**Problem**: Router is not listening on port 7447.

**Solutions:**

1. **Check router is running**: See "Timeout" solutions above

2. **Verify port**:
   ```bash
   # Check if port 7447 is listening
   netstat -an | grep 7447
   lsof -i :7447
   ```

3. **Check firewall**:
   ```bash
   # Ubuntu/Linux
   sudo ufw status
   sudo ufw allow 7447/tcp

   # macOS
   # System Settings → Network → Firewall → Allow port 7447
   ```

4. **Try different port**: If 7447 is blocked, configure router with different port

### "Network Unreachable"

**Problem**: No network connectivity.

**Solutions:**

1. **Enable WiFi** on iPhone: Settings → WiFi

2. **Connect to same network** as ROS 2 system

3. **Check router running**: iPhone → Settings → WiFi → (i) → Router address

4. **Restart network**:
   - Toggle WiFi off/on
   - Restart iPhone
   - Restart router

## Topic Issues

### Topic doesn't appear in `ros2 topic list`

**Problem**: Conduit is publishing but topic is invisible.

**Solutions:**

1. **Verify domain IDs match** (most common issue):
   ```bash
   # Check ROS 2 system domain ID
   echo $ROS_DOMAIN_ID

   # Check Docker container domain ID
   docker exec ros_jazzy_zenoh bash -c "echo \$ROS_DOMAIN_ID"
   ```
   - Domain ID in app Settings must match ROS_DOMAIN_ID on host
   - Valid range: 0-232 (RTPS specification limit)
   - Default is 0 if not set

2. **Verify RMW_IMPLEMENTATION**:
   ```bash
   echo $RMW_IMPLEMENTATION
   # Must be: rmw_zenoh_cpp
   ```

3. **Check wire mode**:
   - App Settings → Wire Mode should match your ROS 2 version
   - Try "Auto-detect" first

4. **Restart Zenoh router**:
   ```bash
   # Kill existing router
   pkill rmw_zenohd

   # Restart with correct domain ID
   export ROS_DOMAIN_ID=0  # Match app's domain ID
   ros2 run rmw_zenoh_cpp rmw_zenohd
   ```

5. **Check app connection state**: Should show "Publishing"

### Topic appears but `ros2 topic echo` shows no data

**Problem**: Topic exists but no messages received.

**Solutions:**

1. **Verify sensor is publishing**:
   - Check message count in app (should be increasing)
   - Rate should be > 0 Hz

2. **Check QoS compatibility**:
   - App uses: Reliability=BestEffort, History=KeepLast(10) by default
   - Try adjusting in sensor settings

3. **Restart app**: Stop and restart publishing

4. **Check wire format**:
   - Ensure wire mode matches your ROS 2 version
   - Try switching between Humble/Jazzy modes

## Sensor Issues

### "Camera Permission Denied"

**Solutions:**

1. **Grant permission**:
   - iOS Settings → Privacy & Security → Camera
   - Find "Conduit" and enable

2. **Restart app** after granting permission

### "LiDAR Not Available"

**Reasons:**

1. **Device doesn't have LiDAR**:
   - Required: iPhone 12 Pro, iPhone 13 Pro, iPhone 14 Pro, iPhone 15 Pro
   - iPad Pro 2020 or newer
   - Apple Vision Pro

2. **Camera permission required**: LiDAR uses ARKit which requires camera access

3. **Premium unlock required**: LiDAR is a premium feature

### "Microphone Permission Denied"

**Solutions:**

1. **Grant permission**:
   - iOS Settings → Privacy & Security → Microphone
   - Find "Conduit" and enable

2. **Restart app** after granting permission

### "GPS Location Services Disabled"

**Solutions:**

1. **Enable location services**:
   - iOS Settings → Privacy & Security → Location Services → ON

2. **Grant app permission**:
   - iOS Settings → Privacy & Security → Location Services → Conduit
   - Select "While Using the App"

3. **Restart app**

### Sensor shows 0 Hz rate

**Problem**: Sensor enabled but not publishing data.

**Solutions:**

1. **Check connection state**: Must show "Publishing"

2. **Verify sensor permission**: Check iOS Settings → Privacy

3. **Try different sensor**: Test if other sensors work

4. **Restart publishing**: Stop and start again

5. **Check logs**: Look for error messages in app

## Platform-Specific Issues

### visionOS: No GPS Sensor

**Expected behavior**: Vision Pro doesn't have GPS hardware (indoor device).

**Workaround**: Use WiFi positioning if available, or use iPhone/iPad for GPS data.

### tvOS: Most Sensors Unavailable

**Expected behavior**: Apple TV only has Game Controller support.

**Reason**: Apple TV is a stationary device without motion/location sensors.

### macOS: IMU Not Available

**Expected behavior**: Macs don't have accelerometer/gyroscope.

**Workaround**: Use iPhone/iPad for IMU data.

### Simulator: Mock Data Only

**Expected behavior**: Simulator generates synthetic sensor data.

**Note**: Useful for development/testing, but not real sensor readings.

### `ros2 topic echo /conduit/audio` fails with "unknown type"

**Problem**: `audio_common_msgs` package is not installed on the ROS 2 system.

**Solutions:**

1. **Use the pre-built Docker image** (includes audio_common_msgs):
   ```bash
   docker run -d -p 7447:7447 --name ros_jazzy_zenoh ghcr.io/youtalk/conduit-support:jazzy
   docker exec ros_jazzy_zenoh bash -c \
     "source /opt/ros/jazzy/setup.bash && \
      source /ros2_ws/install/setup.bash && \
      export RMW_IMPLEMENTATION=rmw_zenoh_cpp && \
      ros2 topic echo /conduit/audio audio_common_msgs/msg/AudioData"
   ```

2. **Install on native ROS 2**:
   ```bash
   sudo apt install ros-jazzy-audio-common   # Jazzy
   sudo apt install ros-humble-audio-common  # Humble
   ```

3. **Build from source** if apt package is unavailable:
   ```bash
   cd ~/ros2_ws/src
   git clone --branch ros2 --depth 1 https://github.com/ros-drivers/audio_common.git
   cd ~/ros2_ws && colcon build --packages-select audio_common_msgs
   source install/setup.bash
   ```

## Performance Issues

### High battery drain

**Causes:**

1. **Too many sensors enabled**: Disable unused sensors

2. **High publishing rates**: Reduce rate for non-critical sensors

3. **Camera/LiDAR active**: These consume significant power

**Solutions:**

- Enable only sensors you need
- Reduce rates (e.g., GPS 1Hz instead of 10Hz)
- Disable camera when not needed

### App becomes unresponsive

**Solutions:**

1. **Memory warning**: iOS killed background sensors
   - Check Console logs
   - Reduce number of active sensors

2. **Network issues**: Connection lost
   - Verify router still running
   - Check WiFi signal strength

3. **Restart app**: Force quit and relaunch

## Data Issues

### Data rate lower than configured

**Possible reasons:**

1. **Hardware limitation**: Some sensors have max rates
   - IMU: 100 Hz max
   - Camera: 30 Hz max
   - GPS: 1-10 Hz typical

2. **Network congestion**: Local network can't handle bandwidth

3. **CPU load**: iOS throttling due to thermal/battery

**Solutions:**

- Reduce rates for non-critical sensors
- Reduce number of active sensors
- Check network bandwidth

### Timestamps seem incorrect

**Check:**

1. **System time**: Ensure iOS device clock is accurate

2. **Timezone**: ROS 2 uses UTC, iOS uses local time

3. **Timestamp source**: Verify using correct time source (system vs sensor)

## DDS Transport Issues

### No topics appear when using DDS

**Problem:** App shows "Publishing" but `ros2 topic list` on the ROS 2 host returns nothing.

**Solutions:**

1. **Verify RMW implementation:**
   ```bash
   echo $RMW_IMPLEMENTATION
   # Must be: rmw_cyclonedds_cpp
   ```

2. **Check domain IDs match** (0-232 valid range for DDS/RTPS):
   ```bash
   echo $ROS_DOMAIN_ID
   ```
   Must match the Domain ID field in Conduit Settings.

3. **Verify network interface binding on iOS:**
   - Conduit Settings → Transport → DDS → Network Interface must be `en0` (WiFi).
   - Leaving this as "auto" frequently fails because iOS may select a cellular or VPN interface.

4. **Multicast blocked by WiFi AP:**
   - Many consumer access points enable "AP isolation" or drop multicast.
   - Workaround: switch Discovery Mode to **Unicast** and add the ROS 2 host IP to the Unicast Peers list in Settings.

5. **Firewall on ROS 2 host:**
   - DDS uses UDP ports starting at `7400 + 250 * domain_id` (for domain 0: 7400, 7401, 7410, 7411).
   - Allow UDP on those ports, or disable the firewall for the test LAN.

### Topics appear but `ros2 topic echo` shows no data (DDS)

**Problem:** Discovery works but data does not flow.

**Solutions:**

1. **QoS mismatch:** Conduit uses BestEffort reliability for high-rate sensors (IMU, camera). If your subscriber requests Reliable, it will not match. Use `--qos-profile sensor_data` or `--qos-reliability best_effort` on the subscriber:
   ```bash
   ros2 topic echo /conduit/imu --qos-reliability best_effort
   ```

2. **CameraInfo reliability:** CameraInfo uses BestEffort with TransientLocal (`latchedBestEffort`). Standard `image_transport` subscribers expect Reliable — override the subscriber QoS.

3. **Large messages (Camera, LiDAR):** Use Unicast discovery. Multicast reassembly of fragmented RTPS data over consumer WiFi is unreliable — see KNOWN_ISSUES.md.

### Disconnect takes several seconds (DDS)

**Problem:** Pressing Stop in the app causes a 2-5 second delay before "Publishing" clears.

**Expected behavior:** DDS disconnect is serialized to avoid an iOS-specific participant-delete deadlock. See KNOWN_ISSUES.md.

### iOS cannot reach the ROS 2 host (DDS over LAN)

**Problem:** `ping` from iOS to host works, but DDS discovery fails.

**Solutions:**
- Confirm both devices are on the same subnet; DDS default transport is UDP, which does not cross routers without configuration.
- Corporate networks often block multicast and inter-client UDP. Use a dedicated test LAN or phone hotspot.
- On macOS Docker Desktop, the Docker container **cannot** receive DDS from iOS because Docker Desktop does not provide true host networking. Run the subscriber on Linux, a Parallels VM, or natively on macOS instead.

## Getting More Help

If your issue isn't listed here:

1. **Check** [Known Issues](KNOWN_ISSUES.md)
2. **Search** [existing issues](https://github.com/youtalk/conduit-support/issues)
3. **Ask in** [Discussions](https://github.com/youtalk/conduit-support/discussions)
4. **Create** [new issue](https://github.com/youtalk/conduit-support/issues/new/choose) with details
