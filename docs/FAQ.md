# Frequently Asked Questions

## Setup & Configuration

### Which transport should I use: Zenoh or DDS?

Conduit 2.0 supports two transports — choose based on your ROS 2 middleware:

| | Zenoh | DDS (CycloneDDS) |
|---|---|---|
| **RMW** | rmw_zenoh_cpp | rmw_cyclonedds_cpp |
| **Router required** | Yes (rmw_zenohd) | No |
| **Network** | TCP/UDP to router | Multicast or unicast on LAN |
| **Distros** | Humble, Jazzy, Kilted, Rolling | Jazzy, Kilted, Rolling |
| **Setup** | Enter router IP in Settings | Set discovery mode in Settings |

**Recommendation:** Use **Zenoh** if you already have rmw_zenoh_cpp set up. Use **DDS** if your stack uses rmw_cyclonedds_cpp and you want zero-broker operation.

See [TRANSPORTS.md](TRANSPORTS.md) for a deeper side-by-side comparison and network-requirements reference.

### I used Conduit 1.x — what changed in 2.0?

**Topic namespace:** Default is now `/conduit/*` (was `ios/*`). If you have ROS 2 subscribers hardcoded to the old `ios` namespace, either remap in your subscriber or change the app's namespace in Settings.

**Transport choice:** 2.0 adds DDS (CycloneDDS) alongside Zenoh. Existing Zenoh users can keep their current router setup — Zenoh remains fully supported. DDS is opt-in via Settings → Transport.

**Supported distros:** Kilted and Rolling join Humble and Jazzy.

### How do I connect via Zenoh?

1. Start the Zenoh router on your ROS 2 system:
   ```bash
   source /opt/ros/jazzy/setup.bash
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

3. In Conduit app:
   - Tap Settings (gear icon)
   - Enter Router Address (e.g., `192.168.1.100`)
   - Enter Router Port (default: `7447`)
   - Enter Domain ID (must match ROS_DOMAIN_ID on host)
   - Tap Save

4. Enable sensors and tap Play

**Important:** Domain ID must match between the app and ROS 2 system. Valid range: 0-232 (RTPS specification limit).

### How do I connect via DDS?

1. On your ROS 2 system:
   ```bash
   source /opt/ros/jazzy/setup.bash
   export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
   export ROS_DOMAIN_ID=0  # Valid range: 0-232
   ros2 topic list
   ```

2. In the Conduit app:
   - Tap Settings → Transport: **DDS**
   - Discovery Mode: **Hybrid** (recommended) or Unicast
   - Add the ROS 2 host IP to Unicast Peers
   - **Network Interface: `en0`** (required on iOS — do not leave as "auto")
   - Domain ID: must match `ROS_DOMAIN_ID`
   - Tap Save

3. Enable sensors and tap Play

**Important:**
- Domain ID must match between the app and ROS 2 system. Valid range: **0-232** (DDS RTPS limit).
- On iOS, DDS **requires** binding to `en0` (WiFi) — multicast / auto-select often fails.

### Which ROS 2 versions are supported?

Conduit supports:
- **ROS 2 Humble** (Ubuntu 22.04) - No type hash
- **ROS 2 Jazzy** (Ubuntu 24.04) - RIHS01 type hash
- **ROS 2 Kilted** (Ubuntu 24.04) - RIHS01 type hash
- **ROS 2 Rolling** - RIHS01 type hash

Supported RMW implementations:
- **rmw_zenoh_cpp** — via Zenoh transport (the app auto-detects Humble vs Jazzy wire format)
- **rmw_cyclonedds_cpp 0.10.5** — via DDS transport (default RMW on many ROS 2 distributions)

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
   # Should output: rmw_zenoh_cpp
   ```

4. **Network connectivity**: Ensure iPhone and ROS 2 system are on the same network

5. **Firewall blocking port 7447**: Check firewall settings on ROS 2 system

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
- ROS 2 Humble, Jazzy, Kilted, or Rolling
- rmw_zenoh_cpp middleware
- Zenoh router running

### Which sensors work on which platforms?

| Platform | Available Sensors |
|----------|-------------------|
| **iOS/iPadOS** | All 12 sensors (IMU, GPS, Camera, LiDAR*, Magnetometer, Barometer, Battery, Thermal, Proximity†, Illuminance, Microphone, Game Controller) |
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
- IMU, GPS, Magnetometer, Barometer, Battery, Thermal, Proximity, Illuminance, **Microphone**
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
ros2 topic list | grep conduit

# Echo data from IMU sensor
ros2 topic echo /conduit/imu

# Check publish rate
ros2 topic hz /conduit/imu

# View topic info
ros2 topic info /conduit/imu --verbose
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
   - `/conduit/camera/front/compressed`
   - `/conduit/camera/wide/compressed`
   - `/conduit/camera/ultrawide/compressed`
   - `/conduit/camera/telephoto/compressed`

**Note:** Wide, ultra-wide, and telephoto cameras require Premium unlock.

### How do I change the publishing rate?

1. Tap the gear icon ⚙️ next to any sensor
2. Adjust "Rate (Hz)" slider
3. Configure QoS settings if needed
4. Tap Save

Different sensors have different maximum rates (see Supported Sensors table).

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
docker run -d -p 7447:7447 --name ros_jazzy_zenoh ghcr.io/youtalk/conduit-support:jazzy

# Echo audio messages
docker exec ros_jazzy_zenoh bash -c \
  "source /opt/ros/jazzy/setup.bash && \
   source /ros2_ws/install/setup.bash && \
   export RMW_IMPLEMENTATION=rmw_zenoh_cpp && \
   ros2 topic echo /conduit/audio audio_common_msgs/msg/AudioData"
```

**Using a native ROS 2 installation:**
```bash
# Install audio_common (includes audio_common_msgs)
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

No. iOS restricts microphone access to foreground apps only. The microphone stops when the app is backgrounded.

Keep the app in the foreground when using the Microphone sensor.

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
