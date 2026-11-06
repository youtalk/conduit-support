# Troubleshooting guide

Common issues and solutions for Conduit.

> **Connecting for the first time?** Use [Connect with a QR code](pair.md). The script checks the ROS 2 PC (RMW, router, firewall, peers), fills in Conduit's settings, and prints what to fix when the iPhone does not check in.

> **Which transport are you using?** Check Settings → Transport in the Conduit app. Zenoh and DDS have different failure modes. Zenoh issues are under "Connection issues" and "Topic issues" below; DDS-specific issues are in "DDS transport issues" at the bottom of this page.

## Connection issues

### "Connection Failed: Timeout"

**Problem**: App cannot reach the Zenoh router.

**Solutions:**

1. **Verify router is running**:
   ```bash
   # On ROS 2 system
   ps aux | grep rmw_zenohd

   # If not running, start it
   source /opt/ros/lyrical/setup.bash   # or your distro
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

4. **Allow Local Network access**: iOS Settings → Privacy & Security → Local Network → Conduit must be on.

5. **Test connectivity**:
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

### Connection drops and reconnects

**Problem**: Data stops for a while during a session, then comes back on its own.

**What Conduit does:** When a send fails (for example, the router restarts or Wi-Fi drops briefly), Conduit keeps running and reconnects in the background. It retries after 1, 2, 4, 8 and 16 seconds, then every 30 seconds, with no limit. Sends never block the app: while the network is stalled, Conduit drops the oldest queued messages instead of freezing. When the device loses its network entirely, Conduit stops publishing and shows **Connection Lost**.

**Solutions:**

1. **Wait**: after a router restart, data usually resumes at the next retry.
2. **Check the router or host**: if data does not come back, see ["Connection Failed: Timeout"](#connection-failed-timeout) above.
3. **Check Wi-Fi signal**: weak Wi-Fi causes repeated drops, especially with camera or LiDAR.
4. **Restart publishing**: stop and start again in the app.

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

## Topic issues

### Topic doesn't appear in `ros2 topic list`

**Problem**: Conduit is publishing but topic is invisible.

**Solutions:**

1. **Verify domain IDs match** (most common issue):
   ```bash
   # Check ROS 2 system domain ID
   echo $ROS_DOMAIN_ID

   # Check Docker container domain ID
   docker exec ros_lyrical_zenoh bash -c "echo \$ROS_DOMAIN_ID"
   ```
   - Domain ID in app Settings must match ROS_DOMAIN_ID on host
   - Valid range: 0-232 (RTPS specification limit)
   - Default is 0 if not set

2. **Verify RMW_IMPLEMENTATION**:
   ```bash
   echo $RMW_IMPLEMENTATION
   # Zenoh transport: rmw_zenoh_cpp
   # DDS transport:   rmw_cyclonedds_cpp (see "DDS transport issues" below)
   ```

3. **Check the Distribution setting**:
   - Set Settings → Distribution to match your host (Humble vs Jazzy and later)

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

1. **Check for "Waiting for subscriber"**:
   - If the sensor row says Waiting for subscriber, Settings → Publishing → **Publish only when subscribed** is on and no subscription matches the topic. The message count and rate in the next item do not apply to a waiting row.
   - See [Why does a sensor say "Waiting for subscriber"?](faq.md#why-does-a-sensor-say-waiting-for-subscriber)

2. **Verify sensor is publishing**:
   - Check message count in app (should be increasing)
   - Rate should be > 0 Hz

3. **Check QoS compatibility**:
   - App uses: Reliability=BestEffort, History=KeepLast(10) by default
   - Game Controller (`sensor_msgs/Joy`) is Reliable by default
   - Subscribe with `--qos-reliability best_effort`, or change the sensor's QoS in its settings

4. **Restart app**: Stop and restart publishing

5. **Check the Distribution setting**:
   - Set Settings → Distribution to match your host (Humble vs Jazzy and later)

## Sensor issues

### "Camera Permission Denied"

**Solutions:**

1. **Grant permission**:
   - iOS Settings → Privacy & Security → Camera
   - Find "Conduit" and enable

2. **Restart app** after granting permission

### "LiDAR Not Available"

**Reasons:**

1. **Device doesn't have LiDAR**:
   - iPhone: iPhone 12 Pro or later Pro models
   - iPad: iPad Pro (2020 or later)
   - Mac: not available

2. **Camera permission required**: LiDAR uses ARKit which requires camera access

3. **Purchase required**: LiDAR is a one-time In-App Purchase

4. **Another camera is on**: ARKit gives only the wide camera, so turning on the front, ultra-wide or telephoto camera turns LiDAR off

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

## Platform-specific issues

### macOS: IMU not available

**Expected behavior**: On Mac, Conduit offers only Camera, Microphone, Battery, Thermal and Game Controller. IMU, Magnetometer, Barometer, Illuminance, GPS, Proximity, LiDAR and Device Pose are not available.

**Workaround**: Use an iPhone or iPad for those sensors. See [Platform notes](platform-notes.md).

### Simulator: mock data only

**Expected behavior**: Simulator generates synthetic sensor data.

**Note**: Useful for development/testing, but not real sensor readings.

### `ros2 topic echo /conduit/audio` fails with "unknown type"

**Problem**: `audio_common_msgs` package is not installed on the ROS 2 system.

**Solutions:**

1. **Use the pre-built Docker image** (includes audio_common_msgs):
   ```bash
   docker run -d -p 7447:7447 --name ros_lyrical_zenoh ghcr.io/youtalk/conduit-support:lyrical
   docker exec ros_lyrical_zenoh bash -c \
     "source /opt/ros/lyrical/setup.bash && \
      source /ros2_ws/install/setup.bash && \
      export RMW_IMPLEMENTATION=rmw_zenoh_cpp && \
      ros2 topic echo /conduit/audio audio_common_msgs/msg/AudioData"
   ```

2. **Install on native ROS 2**:
   ```bash
   sudo apt install ros-lyrical-audio-common  # Lyrical
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

## Performance issues

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
   - See [Connection drops and reconnects](#connection-drops-and-reconnects)

3. **Restart app**: Force quit and relaunch

## Data issues

### Data rate lower than configured

**Possible reasons:**

1. **Hardware limitation**: Each sensor has a maximum rate, and the device may not reach it
   - IMU, Magnetometer: 100 Hz max
   - Camera, LiDAR: 60 Hz max (30 Hz default); higher resolutions lower the achievable rate
   - GPS: 10 Hz max (1 Hz default); the GPS hardware may update less often
   - See [Sensors and topics](sensors.md) for every sensor

2. **Network congestion**: Local network can't handle bandwidth

3. **CPU load**: iOS throttling due to thermal/battery

**Solutions:**

- Reduce rates for non-critical sensors
- Reduce number of active sensors
- Check network bandwidth

### Timestamps seem incorrect

**Check:**

1. **System time**: `header.stamp` is wall-clock time (seconds since the Unix epoch, like ROS time on the host). Ensure the iOS device clock is set automatically (iOS Settings → General → Date & Time → Set Automatically), and that the host's clock is synchronized too.

2. **AR-derived topics**: LiDAR point clouds, depth images, Device Pose (Conduit 3) and the camera images in LiDAR mode carry the ARKit frame's capture time, not the publish time. Messages from the same frame share an identical stamp.

3. **Comparing with `ros2 topic delay`**: a large or negative delay usually means the two clocks differ, not that the data is late.

## DDS transport issues

### No topics appear when using DDS

**Problem:** App shows "Publishing" but `ros2 topic list` on the ROS 2 host returns nothing.

**Solutions:**

0. **Restart the cached `ros2` daemon first** — if you changed `RMW_IMPLEMENTATION`, `ROS_DOMAIN_ID`, or `CYCLONEDDS_URI` in this shell, the daemon is still running with the old context and will lie to you. Run `ros2 daemon stop` before any of the checks below. See [`ros2` CLI shows stale topics after changing `RMW_IMPLEMENTATION` or `CYCLONEDDS_URI`](#ros2-cli-shows-stale-topics-after-changing-rmw_implementation-or-cyclonedds_uri) for the full failure mode.

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
   - Conduit Settings → **Discovery** → **Network Interface** must be **en0 (WiFi)** on iPhone and iPad (the default).
   - "auto" can fail because iOS may select a cellular or VPN interface.

4. **Multicast blocked by WiFi AP:**
   - Many consumer access points enable "AP isolation" or drop multicast.
   - Workaround: add peers on both sides. In Conduit, Settings → **Discovery** → **Peers**: add the ROS 2 host's IP address. On the host, add the iPhone's address (shown as **This Device** on the same page) to the `Peers` list in `CYCLONEDDS_URI`. With peers, Conduit uses unicast on top of multicast.
   - The [QR code script](pair.md) can add the iPhone as a peer on the host for you.

5. **Firewall on ROS 2 host:**
   - DDS uses UDP ports starting at `7400 + 250 * domain_id` (for domain 0: 7400, 7401, 7410, 7411).
   - Allow UDP on those ports, or disable the firewall for the test LAN.

### `ros2` CLI shows stale topics after changing `RMW_IMPLEMENTATION` or `CYCLONEDDS_URI`

**Problem:** You switched transports (e.g. Zenoh → DDS) or updated `CYCLONEDDS_URI` (peers, interface, tracing), but `ros2 topic list` keeps returning the previous transport's results or an empty list.

**Cause:** The `ros2` CLI talks to a long-lived background daemon (`_ros2_daemon`). The daemon is started with whatever `RMW_IMPLEMENTATION` / DDS config was in effect at first launch and caches its RMW context — later env-var changes in your shell are ignored until the daemon is restarted.

**Fix:** Stop the daemon, then let the next CLI invocation start a fresh one in the new environment:

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=123
export CYCLONEDDS_URI='<CycloneDDS>…</CycloneDDS>'

ros2 daemon stop
ros2 daemon start          # optional — `ros2 topic list` will also autostart it
ros2 topic list
```

Any time you change `RMW_IMPLEMENTATION`, `ROS_DOMAIN_ID`, `CYCLONEDDS_URI`, or the Peer list, re-run `ros2 daemon stop` before the next command. This also applies when switching back to `rmw_zenoh_cpp`.

### Topics appear but `ros2 topic echo` shows no data (DDS)

**Problem:** Discovery works but data does not flow.

**Solutions:**

1. **QoS mismatch:** Conduit uses BestEffort reliability for high-rate sensors (IMU, camera). If your subscriber requests Reliable, it will not match. Use `--qos-profile sensor_data` or `--qos-reliability best_effort` on the subscriber:
   ```bash
   ros2 topic echo /conduit/imu --qos-reliability best_effort
   ```

2. **CameraInfo reliability:** CameraInfo uses BestEffort with TransientLocal (`latchedBestEffort`). Standard `image_transport` subscribers expect Reliable — override the subscriber QoS.

3. **Large messages (Camera, LiDAR):** Add peers (Settings → **Discovery** → **Peers**) so data also goes over unicast. Fragmented RTPS data over consumer Wi-Fi multicast is unreliable — see [known-issues.md](known-issues.md).

4. **"Waiting for subscriber" on the sensor row:** **Publish only when subscribed** (Settings → Publishing) is on and no subscription matches the topic. Check the subscriber's QoS (best effort, see item 1), or turn the setting off. See [On-demand capture](on-demand-capture.md).

### Disconnect takes several seconds (DDS)

**Problem:** After you press Stop, it can take a few seconds before "Publishing" clears.

**Expected behavior:** Closing the DDS publishers and participant can take a moment. No action is needed. See [known-issues.md](known-issues.md).

### iOS cannot reach the ROS 2 host (DDS over LAN)

**Problem:** `ping` from iOS to host works, but DDS discovery fails.

**Solutions:**

- Confirm both devices are on the same subnet; DDS default transport is UDP, which does not cross routers without configuration.
- Corporate networks often block multicast and inter-client UDP. Use a dedicated test LAN or phone hotspot.
- On macOS Docker Desktop, the Docker container **cannot** receive DDS from iOS because Docker Desktop does not provide true host networking. Run the subscriber on Linux, a Parallels VM, or natively on macOS instead.

## Getting more help

If your issue isn't listed here:

1. **Check** [Known Issues](known-issues.md)
2. **Search** [existing issues](https://github.com/youtalk/conduit-support/issues)
3. **Ask in** [Discussions](https://github.com/youtalk/conduit-support/discussions)
4. **Create** [new issue](https://github.com/youtalk/conduit-support/issues/new/choose) with details
