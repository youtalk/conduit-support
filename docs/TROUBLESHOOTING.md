# Troubleshooting Guide

Common issues and solutions for Conduit.

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

1. **Verify RMW_IMPLEMENTATION**:
   ```bash
   echo $RMW_IMPLEMENTATION
   # Must be: rmw_zenoh_cpp
   ```

2. **Check wire mode**:
   - App Settings → Wire Mode should match your ROS 2 version
   - Try "Auto-detect" first

3. **Restart Zenoh router**:
   ```bash
   # Kill existing router
   pkill rmw_zenohd

   # Restart
   ros2 run rmw_zenoh_cpp rmw_zenohd
   ```

4. **Check app connection state**: Should show "Publishing"

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

## Getting More Help

If your issue isn't listed here:

1. **Check** [Known Issues](KNOWN_ISSUES.md)
2. **Search** [existing issues](https://github.com/youtalk/conduit-support/issues)
3. **Ask in** [Discussions](https://github.com/youtalk/conduit-support/discussions)
4. **Create** [new issue](https://github.com/youtalk/conduit-support/issues/new/choose) with details
