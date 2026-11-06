# Frequently asked questions

## Setup & configuration

### How do I connect with a QR code?

Requires Conduit 2.6.0 or later.

Run one command on your ROS 2 PC:

```bash
curl -fsSL https://conduit.direct/pair.sh | bash
```

The script checks the PC's ROS 2 setup, shows a QR code, and waits. Scan the code with the iPhone's Camera app, and Conduit fills in the connection settings. This is the easiest way to connect, for Zenoh and for DDS. See [Connect with a QR code](pair.md) for the requirements and for what to do when nothing happens after the scan.

The manual steps below still work if you prefer them or cannot run the script.

### Which transport should I use: Zenoh or DDS?

Conduit supports two transports. Choose based on your ROS 2 middleware:

| | Zenoh | DDS (CycloneDDS) |
|---|---|---|
| **RMW** | rmw_zenoh_cpp | rmw_cyclonedds_cpp |
| **Router required** | Yes (rmw_zenohd) | No |
| **Network** | TCP to the router | Multicast on the LAN, plus unicast to any peers you add |
| **Distros** | Humble, Jazzy, Kilted, Lyrical, Rolling | Humble, Jazzy, Kilted, Lyrical, Rolling |
| **Setup** | Enter the router address in Settings | Optional peers in Settings → **Discovery** |

**Recommendation:** Use **Zenoh** if you already have rmw_zenoh_cpp set up. Use **DDS** if your stack uses rmw_cyclonedds_cpp and you don't want to run a router.

See [transports.md](transports.md) for a deeper side-by-side comparison and network-requirements reference.

### I used Conduit 1.x — what changed in 2.0?

**Transport choice:** 2.0 adds DDS (CycloneDDS) alongside Zenoh. Your Zenoh router setup keeps working. Pick DDS in Settings → Transport.

**Supported distros:** Kilted and Rolling joined Humble and Jazzy in 2.0; Lyrical joined in 2.3.0 and is the default for new installs.

### How do I connect via Zenoh?

The [QR code](pair.md) fills in these settings for you. To set them by hand:

1. Start the Zenoh router on your ROS 2 system:
   ```bash
   source /opt/ros/lyrical/setup.bash   # or your distro
   export RMW_IMPLEMENTATION=rmw_zenoh_cpp
   export ROS_DOMAIN_ID=0  # Set domain ID (0-232, default: 0)
   ros2 run rmw_zenoh_cpp rmw_zenohd
   ```

2. Find your ROS 2 system's IP address:
   ```bash
   ip addr show  # Linux
   ifconfig      # macOS
   ipconfig      # Windows
   ```

3. In the Conduit app:
   - Tap Settings (gear icon)
   - Transport: **Zenoh**
   - Enter Router Address (e.g., `192.168.1.100`)
   - Enter Router Port (default: `7447`)
   - Enter Domain ID (must match ROS_DOMAIN_ID on host)
   - Distribution: your host's ROS 2 release (Lyrical by default)
   - Tap **Done**. Settings are saved as you change them.

4. Enable sensors and tap Play

**Important:** Domain ID must match between the app and ROS 2 system. Valid range: 0-232 (RTPS specification limit).

### How do I connect via DDS?

The [QR code](pair.md) fills in these settings for you and can add the iPhone as a peer on the PC. To set them by hand:

1. On your ROS 2 system:
   ```bash
   source /opt/ros/lyrical/setup.bash   # or your distro
   export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
   export ROS_DOMAIN_ID=0  # Valid range: 0-232

   # Restart the cached ros2 daemon so it picks up the new RMW.
   # Skip this on a fresh shell where the daemon hasn't started yet.
   ros2 daemon stop
   ros2 daemon start          # optional — `ros2 topic list` autostarts it

   ros2 topic list  # Verify the RMW is active (no topics expected yet)
   ```

   **Re-run `ros2 daemon stop` whenever you change `RMW_IMPLEMENTATION`, `ROS_DOMAIN_ID`, `CYCLONEDDS_URI`, or the unicast peer list.** The daemon caches the first context it saw and silently ignores later env-var changes — symptoms include `ros2 topic list` showing topics from the wrong domain, missing the iOS topics entirely, or "topic exists but no data". See [troubleshooting.md](troubleshooting.md#ros2-cli-shows-stale-topics-after-changing-rmw_implementation-or-cyclonedds_uri).

2. In the Conduit app:
   - Tap Settings → Transport: **DDS**
   - Domain ID: must match `ROS_DOMAIN_ID`
   - Distribution: your host's ROS 2 release (Lyrical by default)
   - Tap **Discovery**. On the **DDS Discovery** page:
     - **Peers:** add the ROS 2 host's IP address. Without peers, Conduit uses multicast discovery only. With peers, it uses unicast to the peers on top of multicast.
     - **Network Interface:** **en0 (WiFi)** on iPhone and iPad (the default).
     - **This Device** shows the iPhone's address. Add it as a peer on the ROS 2 host too, in `CYCLONEDDS_URI` (see [Transports](transports.md)).
   - Tap **Done**. Settings are saved as you change them; discovery changes apply the next time you tap Start.

3. Enable sensors and tap Play

**Important:**

- Domain ID must match between the app and ROS 2 system. Valid range: **0-232** (DDS RTPS limit).
- On iPhone and iPad, keep the network interface on **en0 (WiFi)**. "auto" can pick a cellular or VPN interface.
- Many Wi-Fi networks drop multicast. If discovery fails, add peers on both sides.

### Which ROS 2 versions are supported?

Conduit supports:

- **ROS 2 Humble** (Ubuntu 22.04) - No type hash
- **ROS 2 Jazzy** (Ubuntu 24.04) - RIHS01 type hash
- **ROS 2 Kilted** (Ubuntu 24.04) - RIHS01 type hash
- **ROS 2 Lyrical** (Ubuntu 26.04) - RIHS01 type hash
- **ROS 2 Rolling** - RIHS01 type hash

Supported RMW implementations:

- **rmw_zenoh_cpp** — via the Zenoh transport
- **rmw_cyclonedds_cpp** — via the DDS transport. Use the version that ships with your distro. Conduit embeds CycloneDDS 11.0.1.

Set Settings → Distribution to match the host for either transport.

The default RMW on every one of these distros is Fast DDS (`rmw_fastrtps_cpp`), so set `RMW_IMPLEMENTATION` explicitly. A Fast DDS host can discover Conduit over DDS, but may drop or delay high-rate topics such as the camera and LiDAR.

### Why can't I see my topics in `ros2 topic list`?

**Check these common issues:**

1. **Domain IDs don't match** (most common):
   ```bash
   # Check domain ID on ROS 2 system
   echo $ROS_DOMAIN_ID
   ```
   - Domain ID in app Settings must match ROS_DOMAIN_ID on host
   - Default is 0 if not set
   - Valid range: 0-232 (RTPS specification limit)

2. **Zenoh router not running**:
   ```bash
   # Start router with matching domain ID
   export ROS_DOMAIN_ID=0
   ros2 run rmw_zenoh_cpp rmw_zenohd
   ```

3. **Wrong RMW implementation**:
   ```bash
   # Verify RMW setting
   echo $RMW_IMPLEMENTATION
   # Zenoh transport: rmw_zenoh_cpp
   # DDS transport:   rmw_cyclonedds_cpp
   ```
   After changing it, run `ros2 daemon stop` so the CLI picks up the new value.

4. **Network connectivity**: Ensure iPhone and ROS 2 system are on the same network

5. **Firewall on the ROS 2 system**: allow TCP 7447 for Zenoh, or the DDS UDP ports (`7400 + 250 × domain` and up) for DDS.

6. **Distribution mismatch**: Settings → Distribution must match the host (Humble vs Jazzy and later).

The [QR code script](pair.md) checks most of these on the host for you.

### What does the Distribution setting change?

- **Humble**: key expressions carry `TypeHashNotSupported` instead of a type hash.
- **Jazzy, Kilted, Lyrical, Rolling**: key expressions carry the RIHS01 type hash. These four share one wire format, so any of them works with any of these hosts.

Pick the release your host runs; there is no automatic detection.

### Can I use Conduit without a ROS 2 system?

Yes. **Record mode** works with no network at all. Choose **Record** next to the play button and Conduit writes the sensors to an `.mcap` file on the device. See [MCAP recording](#mcap-recording).

To receive live data, you need a ROS 2 system (Humble, Jazzy, Kilted, Lyrical, or Rolling) with **one** of the supported transports:

- **Zenoh:** `rmw_zenoh_cpp` middleware and a running Zenoh router (`rmw_zenohd`).
- **DDS:** `rmw_cyclonedds_cpp` middleware on the same LAN as your iPhone or iPad — no router required.

### Which sensors work on which platforms?

- **iPhone:** all 13 sensors. LiDAR needs a Pro model from iPhone 12 Pro on.
- **iPad:** every sensor except Proximity. LiDAR needs an iPad Pro (2020 or later).
- **Mac (Mac Catalyst):** Camera, Microphone, Battery, Thermal and Game Controller only.

Device Pose (Conduit 3) runs on iPhone and iPad only, and only while ARKit tracking is normal.

See [Platform notes](platform-notes.md) for details per platform, and [Sensors and topics](sensors.md) for every topic, message type, rate and frame.

### How do I enable background mode?

Turn on Settings → Publishing → **Background Publishing**. It needs the Background Mode In-App Purchase; until you buy it, the toggle shows a lock.

What happens when you leave the app:

- **Background Publishing off:** Conduit stops publishing.
- **Background Publishing on:** Camera and LiDAR stop (iOS does not allow them in the background). The other sensors keep publishing until iOS suspends the app, which it can do at any time.

Keep Conduit in the foreground when you need data for a long time, for example a long GPS track. See [Known issues](known-issues.md).

### What are the premium features?

**Free:**

- IMU, GPS, Magnetometer, Barometer, Illuminance, Proximity, Battery, Thermal, **Microphone**
- Front camera
- **MCAP recording** to the device

**One-time In-App Purchases:**

- **Back Cameras** — Wide, Ultra Wide and Telephoto cameras in one purchase (the front camera stays free)
- **LiDAR** — point cloud and depth (iPhone Pro / iPad Pro)
- **Game Controller** — MFi / Bluetooth controller input as `sensor_msgs/Joy`
- **Background Mode** — keep publishing supported sensors while the app is in the background
- **Recording Export** — export and share recorded `.mcap` files to other apps and devices

Settings → **Premium Features** shows what you have unlocked and has **Restore Purchases**.

### How do I verify data is being published?

On your ROS 2 system:

```bash
# Check if topic appears
ros2 topic list | grep conduit

# Echo data from IMU sensor
ros2 topic echo /conduit/imu

# Check publish rate
ros2 topic hz /conduit/imu

# View topic info
ros2 topic info /conduit/imu --verbose
```

### Why does a sensor say "Waiting for subscriber"?

Requires Conduit 2.4.0 or later.

**Publish only when subscribed** (Settings → Publishing) is on, and none of that sensor's topics has a ROS 2 subscriber. The sensor is still running; Conduit just sends nothing until a subscriber appears. The row shows its normal rate again as soon as one connects. See [On-demand capture](on-demand-capture.md) for how the setting works.

If you expected data, check:

1. **Is anything subscribed?** For example, run `ros2 topic echo /conduit/imu` on the host.
2. **Subscriber QoS.** Sensor topics default to best effort. On DDS, a subscriber that requests reliable delivery does not match them. Subscribe with `--qos-reliability best_effort` (or `qos_profile_sensor_data` in rclpy), or set the sensor's QoS to Reliable in its settings.
3. **Domain ID and Distribution.** `ROS_DOMAIN_ID` on the host must match the Domain ID in Conduit, and Settings → Distribution must match your host (Humble vs Jazzy and later).
4. **Want continuous publishing?** Turn off Settings → Publishing → **Publish only when subscribed**. It is off by default.

### Why is my sensor showing "Not Available"?

**Common reasons:**

1. **Hardware limitation**: Device doesn't have that sensor
   - LiDAR: iPhone 12 Pro or later Pro models, iPad Pro (2020 or later)
   - Proximity: iPhone only (not iPad)

2. **Platform limitation**:
   - Mac: only Camera, Microphone, Battery, Thermal and Game Controller. See [Which sensors work on which platforms?](#which-sensors-work-on-which-platforms)

3. **Permission denied**: Grant permission in iOS Settings → Privacy & Security

4. **Runtime unavailable**:
   - Game Controller: No controller connected
   - Location: Location services disabled

### Can I use multiple cameras simultaneously?

Yes. Each camera has its own row:

1. Turn on the cameras you want (front, wide, ultra-wide, telephoto)
2. Each camera publishes to its own topics (default namespace `conduit`):
   - `/conduit/camera/front/image_raw/compressed`
   - `/conduit/camera/wide/image_raw/compressed`
   - `/conduit/camera/ultrawide/image_raw/compressed`
   - `/conduit/camera/telephoto/image_raw/compressed`

   These are the default compressed outputs. With the camera's output set to raw, the image goes to `.../image_raw` instead. Each camera also publishes `/conduit/camera/<camera>/camera_info`.

**Notes:**

- The wide, ultra-wide and telephoto cameras need the Back Cameras purchase. The front camera is free.
- LiDAR uses ARKit, which gives only the wide camera. While LiDAR is on, only the wide camera streams; turning on another camera turns LiDAR off. LiDAR can also publish `/conduit/camera/wide/depth/image_raw`, aligned with the wide camera.

### How do I change the publishing rate?

1. Stop publishing. The settings button appears under each sensor's toggle.
2. Tap the settings button (sliders icon) under the sensor's toggle
3. Pick a rate from **Rate (Hz)**
4. Change the QoS settings if needed
5. Tap **Save**

Each sensor has its own maximum rate, shown in the sheet. See [Sensors and topics](sensors.md) for the default and maximum rates.

---

## Microphone

### What ROS 2 message type does the Microphone sensor use?

The Microphone sensor publishes `audio_common_msgs/msg/AudioData` messages.

**Audio parameters:**

- **Sample rate**: 16,000 Hz
- **Channels**: 1 (mono)
- **Format**: S16LE (signed 16-bit little-endian PCM)
- **Samples per message**: 1024
- **Publish rate**: ~15.6 messages/sec

**Default topic**: `/conduit/audio` (configurable via namespace in Settings)

### How do I receive Microphone data on ROS 2?

You need the `audio_common_msgs` package installed on your ROS 2 system.

**Using Docker (easiest):**
```bash
# The pre-built Docker image already includes audio_common_msgs
docker run -d -p 7447:7447 --name ros_lyrical_zenoh ghcr.io/youtalk/conduit-support:lyrical

# Echo audio messages
docker exec ros_lyrical_zenoh bash -c \
  "source /opt/ros/lyrical/setup.bash && \
   source /ros2_ws/install/setup.bash && \
   export RMW_IMPLEMENTATION=rmw_zenoh_cpp && \
   ros2 topic echo /conduit/audio audio_common_msgs/msg/AudioData"
```

**Using a native ROS 2 installation:**
```bash
# Install audio_common (includes audio_common_msgs)
sudo apt install ros-lyrical-audio-common  # Lyrical
sudo apt install ros-jazzy-audio-common   # Jazzy
sudo apt install ros-humble-audio-common  # Humble

# Or build from source
mkdir -p ~/ros2_ws/src && cd ~/ros2_ws/src
git clone --branch ros2 --depth 1 https://github.com/ros-drivers/audio_common.git
cd ~/ros2_ws
rosdep install --from-paths src --ignore-src -r -y
colcon build --packages-select audio_common_msgs
source install/setup.bash
```

**Verify the topic:**
```bash
# Check topic exists
ros2 topic list | grep audio

# Echo messages
ros2 topic echo /conduit/audio audio_common_msgs/msg/AudioData

# Check publish rate (~15-16 Hz)
ros2 topic hz /conduit/audio

# Inspect message type
ros2 topic info /conduit/audio --verbose
```

### How do I play back the audio data in Python?

```python
import rclpy
from rclpy.node import Node
from audio_common_msgs.msg import AudioData
import numpy as np
import sounddevice as sd

class AudioPlayer(Node):
    def __init__(self):
        super().__init__('audio_player')
        self.subscription = self.create_subscription(
            AudioData,
            '/conduit/audio',
            self.audio_callback,
            10)
        self.sample_rate = 16000

    def audio_callback(self, msg):
        # Convert bytes to int16 numpy array
        samples = np.frombuffer(bytes(msg.data), dtype=np.int16)
        # Normalize to float32 [-1.0, 1.0]
        audio = samples.astype(np.float32) / 32768.0
        # Play audio (non-blocking)
        sd.play(audio, self.sample_rate)

def main():
    rclpy.init()
    player = AudioPlayer()
    rclpy.spin(player)

if __name__ == '__main__':
    main()
```

### Does the Microphone sensor work in the background?

No. In the current release the microphone stops when Conduit goes to the background, even with Background Publishing on.

Keep the app in the foreground when using the Microphone sensor.

---

## MCAP recording

### How does MCAP recording work?

Choose **Record** or **Both** next to the play button, then tap play. Conduit writes every topic it produces to an `.mcap` file on the device, as the same XCDR v1 bytes it sends to ROS 2. The schemas are embedded in the file, so any MCAP reader (Foxglove, Lichtblick, `ros2 bag play`, the `mcap` CLI) opens it without external `.msg` files.

- **Publish:** live to ROS 2 only.
- **Record:** to a file only. Needs no network and no ROS 2 system.
- **Both:** live to ROS 2 and to a file.

Recording is free. Recordings stay on the device; Conduit never uploads them. Open them from the folder button next to Settings in the toolbar, where you can delete them. To export a recording through the share sheet (Files, AirDrop, mail, …), you need the Recording Export purchase. Without it, recordings are kept in the app's private storage and the share button shows a lock.

### Can I record while publishing live to ROS 2?

Yes. Choose **Both**. Recording is a sink on the same publish path, not a separate pipeline — every message you send to ROS 2 is also written to the file.

### How do I replay an MCAP file?

```bash
# Foxglove Studio: File → Open → select the .mcap

# ros2 bag (Jazzy / Kilted / Lyrical / Rolling — bundled mcap_storage_plugin):
ros2 bag play recording.mcap

# Humble: install ros-humble-rosbag2-storage-mcap first
sudo apt install ros-humble-rosbag2-storage-mcap
ros2 bag play recording.mcap --storage mcap
```

### Do I need a purchase to record?

No. Recording to the device is free, and the Record and Both modes are always available. Only exporting a recording out of the app needs the one-time Recording Export purchase (see [premium features](#what-are-the-premium-features)).

---

### Does Conduit work offline?

Partly:

- **Record** mode works with no network at all.
- **Publish** and **Both** need a local network between your iPhone or iPad and the ROS 2 system (or a Zenoh router you can reach).

**No internet is required** for either.

### How do I reset app settings?

Delete and reinstall the app. This clears:

- Connection settings (router address, peers, Domain ID, Distribution)
- Sensor configurations
- Recordings stored on the device

Purchases are tied to your Apple ID. After reinstalling, tap Settings → Premium Features → **Restore Purchases**.

To see the setup tour again without resetting anything, tap Settings → About & Help → **Replay Onboarding**.

### Is my data sent to the cloud?

**No.** All sensor data:

- Stays on your local network (or your Tailscale tailnet, if you use one)
- Goes only to the ROS 2 host or Zenoh router you configure
- Is never uploaded to external servers
- Is never shared with third parties

Firebase Analytics collects anonymous app usage statistics only, with no sensor values. To turn it off, open Settings → About & Help → Privacy and turn off **Send Usage Statistics**.

See our [Privacy Policy](privacy.md) for details.
