# Known issues & limitations

Current limitations and known issues in Conduit.

## Privacy & policy constraints

### Background GPS tracking not supported

**Status**: Limitation of the current release

**Reason**: Conduit does not ask for "Always" location permission, and iOS can suspend an app in the background at any time.

**Current behavior**:

- GPS publishes while Conduit is in the foreground
- With Settings → Publishing → **Background Publishing** off, GPS stops when you leave the app
- With **Background Publishing** on, GPS may keep publishing for a while, but iOS can suspend Conduit at any time, so do not rely on it for a long track

**Workaround**:

- Keep the app in the foreground during GPS data collection

---

## Platform limitations

### macOS: No IMU/GPS sensors

**Status**: Hardware limitation

**Reason**: Macs have no accelerometer, gyroscope, magnetometer, barometer, ambient light sensor, GPS, proximity sensor or LiDAR that Conduit can read.

**Available on Mac (Mac Catalyst)**: Camera, Microphone, Battery, Thermal and Game Controller. IMU, Magnetometer, Barometer, Illuminance, GPS, Proximity, LiDAR and Device Pose are not available.

**Use case**: Mac camera, microphone and game controller input, and development/testing. See [Platform notes](platform-notes.md).

---

## iOS restrictions

### Camera/LiDAR stop in background

**Status**: iOS system restriction

**Reason**: iOS doesn't allow camera/ARKit usage in background. Camera and LiDAR stop even with **Background Publishing** on. The Microphone also stops in the background in the current release.

**Workaround**: Keep app in foreground when using Camera, LiDAR or Microphone

### Proximity sensor only on iPhone

**Status**: Hardware limitation

**Reason**: iPads don't have proximity sensors.

**Workaround**: Use iPhone for proximity sensing, or use LiDAR for distance measurement

---

## Performance & stability

### Multiple cameras may cause memory warnings

**Status**: Known issue

**Behavior**: Enabling 3-4 cameras simultaneously may trigger iOS memory warnings.

**Mitigation**:

- On a memory warning, Conduit stops all cameras and LiDAR
- Reduce number of active cameras
- Lower the camera's **Resolution** in its settings

**Workaround**: Enable only cameras you need

### High frame rate may cause thermal throttling

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

## Network & connectivity

### Initial connection can be slow

**Status**: Normal behavior

**Reason**: Opening the Zenoh session or DDS participant and creating a publisher for each sensor can take a few seconds. Conduit retries each initial connect up to 3 times before it reports "Connection Failed".

**Workaround**: Wait for "Publishing" state before expecting data

### Connection lost not always detected immediately

**Status**: Known limitation

**Reason**: A router or host that goes away is noticed only when a send fails.

**Behavior**: Data can stop for a while before Conduit notices. Once a send fails, Conduit reconnects in the background: it retries after 1, 2, 4, 8 and 16 seconds, then every 30 seconds, with no limit. If the device loses its network entirely, Conduit stops publishing and shows **Connection Lost**.

**Workaround**: Wait for the next retry, or stop and start publishing. See [Connection drops and reconnects](troubleshooting.md#connection-drops-and-reconnects).

---

## Wire format compatibility

### rmw_zenoh_cpp version sensitivity

**Status**: By design

**Reason**: Wire format changes between rmw_zenoh_cpp versions.

**Mitigation**:

- Settings → Distribution: Humble, or Jazzy / Kilted / Lyrical / Rolling (one shared wire format)

**Known compatible versions**:

- ROS 2 Humble: rmw_zenoh_cpp (Humble release)
- ROS 2 Jazzy: rmw_zenoh_cpp (Jazzy release)
- ROS 2 Kilted: rmw_zenoh_cpp (Kilted release)
- ROS 2 Lyrical: rmw_zenoh_cpp (Lyrical release)
- ROS 2 Rolling: rmw_zenoh_cpp (Rolling)

**Workaround**: Set Distribution to match the host.

---

## DDS transport

### Camera/LiDAR fragmentation loss on DDS over WiFi

**Status**: Known limitation

**Reason**: Large RTPS messages (>1400 bytes — camera, LiDAR, CameraInfo with large K matrices) are split into UDP fragments. Consumer WiFi often drops or reorders fragments, especially over multicast.

**Mitigation**:

- Add peers in Settings → **Discovery** → **Peers**, and add the iPhone's address as a peer on the host. With peers, Conduit sends over unicast on top of multicast.
- Reduce camera resolution, or turn on LiDAR point cloud compression.
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

### Disconnect delay on DDS

**Status**: Expected behavior

**Reason**: Closing the DDS publishers and the DDS participant takes some time.

**Behavior**: After you press Stop, it can take a few seconds before the app fully releases the domain. No action is needed.

### DDS requires WiFi — no cellular fallback

**Status**: By design

**Reason**: DDS discovery binds to a specific network interface (`en0` on iOS). Cellular or VPN interfaces are not supported; multicast/unicast discovery requires the device and the ROS 2 host to be on the same LAN.

**Workaround**: Use the Zenoh transport if you need to cross networks, for example over Tailscale (see [Connect with a QR code](pair.md)) or with a router address you can reach.

---

## Premium features

### Premium purchase required for some sensors

**Status**: By design (business model)

**Free**:

- IMU, GPS, Magnetometer, Barometer, Illuminance, Proximity, Battery, Thermal, **Microphone**
- Front camera
- **MCAP recording** to the device

**One-time In-App Purchases**:

- **Back Cameras** — Wide, Ultra Wide and Telephoto cameras in one purchase
- **LiDAR**
- **Game Controller**
- **Background Mode** — keep publishing while the app is in the background
- **Recording Export** — export and share recorded `.mcap` files

### Premium purchases not syncing

**Status**: Rare issue

**Reason**: App Store receipt verification delay.

**Solutions**:

1. Restart app
2. Restore purchases (Settings → Premium Features → Restore Purchases)
3. Verify Apple ID is correct

---

## Workaround summary

| Issue | Workaround |
|-------|------------|
| Background GPS | Keep app in foreground |
| macOS no IMU / GPS | Use iPhone/iPad |
| Camera background | Keep app in foreground |
| Memory warnings | Reduce active sensors |
| Thermal throttling | Lower rates, fewer sensors |
| Connection slow | Wait for "Publishing" |
| Connection drops | Wait for the automatic reconnect |
| DDS fragmentation loss on WiFi | Add discovery peers on both sides; lower camera resolution or compress LiDAR |
| CameraInfo QoS mismatch | Subscriber: `--qos-reliability best_effort --qos-durability transient_local` |
| DDS disconnect delay | Expected behavior — no user action required |
| DDS over WAN / cellular | Use Zenoh transport with a public router instead |

---

## Reporting new issues

Found a bug not listed here? **[Create an issue](https://github.com/youtalk/conduit-support/issues/new/choose)** with:

- Platform and OS version
- Sensor type affected
- Steps to reproduce
- Expected vs actual behavior

## Feature requests

Want a new feature? **[Request it here](https://github.com/youtalk/conduit-support/issues/new?template=feature_request.yml)**

We prioritize based on:

- User impact
- Technical feasibility
- Platform constraints
- Development resources
