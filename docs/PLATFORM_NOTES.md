# Platform-Specific Notes

Information about sensor availability and limitations on different Apple platforms.

## iOS / iPadOS

**Supported Sensors**: All 12 sensors

| Sensor | iPhone | iPad | Notes |
|--------|--------|------|-------|
| IMU | ✅ | ✅ | All iOS devices |
| GPS | ✅ | ✅ | WiFi/Cellular required |
| Magnetic Field | ✅ | ✅ | Built-in compass |
| Proximity | ✅ | ❌ | iPhone only |
| Camera | ✅ | ✅ | Multiple cameras on Pro models |
| LiDAR | ✅* | ✅* | Pro models 2020+ |
| Microphone | ✅ | ✅ | 16 kHz, mono, S16LE |
| Battery | ✅ | ✅ | All devices |
| Thermal | ✅ | ✅ | All devices |
| Barometer | ✅ | ✅ | iPhone 6+, all iPads |
| Illuminance | ✅ | ✅ | Via camera ambient light sensor |
| Game Controller | ✅ | ✅ | MFi controllers via Bluetooth |

*LiDAR availability:
- iPhone: 12 Pro, 13 Pro, 14 Pro, 15 Pro series
- iPad: Pro 11" (2020+), Pro 12.9" (2020+)

**Background Mode**:
- ✅ IMU, Magnetometer, Barometer, Battery, Thermal
- ✅ GPS (foreground only - "When In Use" permission)
- ❌ Camera, LiDAR, Microphone (iOS restriction)
- ⚠️ Background processing mode available for continuous streaming

---

## visionOS (Apple Vision Pro)

**Supported Sensors**: Camera, IMU, Game Controller

| Sensor | Available | Notes |
|--------|-----------|-------|
| IMU | ✅ | Head motion tracking |
| GPS | ❌ | Indoor device |
| Magnetic Field | ⚠️ | May be available (untested) |
| Proximity | ❌ | Not applicable |
| Camera | ✅ | Multiple cameras available |
| LiDAR | ✅ | Depth sensing via cameras |
| Microphone | ❌ | Not available on visionOS |
| Battery | ✅ | Battery status |
| Thermal | ✅ | Thermal state |
| Barometer | ❌ | Not available |
| Illuminance | ⚠️ | May be via camera (untested) |
| Game Controller | ✅ | Bluetooth controllers |

**Future Features** (not yet implemented):
- Hand tracking → sensor_msgs/Joy or custom message
- Eye tracking → custom message type
- Spatial mapping → sensor_msgs/PointCloud2

**Limitations**:
- No GPS (Vision Pro is designed for indoor use)
- Different camera configuration than iPhone/iPad
- Spatial computing features not yet exposed

---

## tvOS (Apple TV)

**Supported Sensors**: Game Controller only

| Sensor | Available | Notes |
|--------|-----------|-------|
| Game Controller | ✅ | Siri Remote + MFi controllers |
| Microphone | ❌ | Not available on tvOS |
| All others | ❌ | Apple TV is stationary without sensors |

**Use Cases for tvOS**:
- Remote robot control using Siri Remote or game controller
- Button input for ROS 2 teleop
- Testing controller input without iOS device

**Limitations**:
- No motion sensors (Apple TV doesn't move)
- No location sensors (stationary device)
- No camera (no camera hardware)

---

## macOS (Mac Catalyst)

**Supported Sensors**: Camera, Battery, Game Controller (limited)

| Sensor | Available | Notes |
|--------|-----------|-------|
| IMU | ❌ | Macs don't have accelerometer |
| GPS | ❌ | Desktop device |
| Magnetic Field | ❌ | No magnetometer |
| Proximity | ❌ | Not applicable |
| Camera | ✅ | FaceTime HD Camera |
| LiDAR | ❌ | No LiDAR on Macs |
| Microphone | ❌ | Not available on macOS |
| Battery | ✅ | MacBook only |
| Thermal | ✅ | CPU temperature |
| Barometer | ❌ | Not available |
| Illuminance | ⚠️ | May be via ambient light sensor |
| Game Controller | ✅ | Bluetooth controllers |

**Limitations**:
- No motion sensors (desktop device)
- Single camera (FaceTime HD)
- WiFi positioning only (no GPS)

**Use Cases**:
- Development and testing
- Camera streaming from Mac
- Game controller input testing

---

## iOS Simulator

**Behavior**: All sensors generate **mock data** for testing.

**Mock Data Characteristics**:
- IMU: Sine wave patterns
- GPS: Fixed location with small variations
- Camera: Colored test patterns
- Battery: Simulated charging cycles
- All others: Realistic but synthetic values

**Purpose**:
- App development without ROS 2
- UI/UX testing
- Feature verification before device testing

**Limitations**:
- Not real sensor readings
- Cannot test actual hardware behavior
- Network connectivity required for ROS 2 integration

---

## Comparison Table

| Feature | iOS | visionOS | tvOS | macOS |
|---------|-----|----------|------|-------|
| Motion Sensors | ✅ Full | ✅ IMU only | ❌ | ❌ |
| Location | ✅ GPS | ❌ | ❌ | ⚠️ WiFi only |
| Cameras | ✅ Multi | ✅ Multi | ❌ | ✅ Single |
| LiDAR | ✅* | ✅ | ❌ | ❌ |
| Microphone | ✅ | ❌ | ❌ | ❌ |
| Environmental | ✅ Full | ⚠️ Limited | ❌ | ⚠️ Limited |
| Game Controller | ✅ | ✅ | ✅ | ✅ |
| Background Mode | ✅ | ⚠️ | N/A | N/A |

*Pro models only

---

## Platform-Specific Recommendations

### iOS/iPadOS
**Best for**: Full sensor suite, mobile robotics, outdoor use
**Recommended**: Primary platform for production use

### visionOS
**Best for**: Spatial computing, AR research, camera/depth sensing
**Note**: Indoor use only (no GPS)

### tvOS
**Best for**: Robot remote control, game controller input
**Note**: Very limited sensor availability

### macOS
**Best for**: Development, testing, stationary camera
**Note**: Limited sensor set, development purposes mainly
