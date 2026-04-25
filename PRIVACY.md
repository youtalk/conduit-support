# Privacy Policy

**Last Updated: April 24, 2026**

Conduit is a developer tool that publishes sensor data from Apple devices (iOS / iPadOS / macOS / visionOS) to ROS 2 (Robot Operating System 2) networks. It is built on top of the open-source [swift-ros2](https://github.com/youtalk/swift-ros2) Swift client library, which speaks the ROS 2 wire formats directly over Zenoh or DDS — without any Conduit-operated cloud service in between. This privacy policy explains what data the app collects, how it's used, and your rights.

**Developer**: Yutaka Kondo (youtalk) · [LinkedIn](https://www.linkedin.com/in/youtalk) · [Website](https://youtalk.jp)

## Data Collection

### Sensor Data (User-Controlled)

The app may access and transmit the following sensor data **only when you explicitly enable each sensor**:

- **Motion Data**: Accelerometer, gyroscope, magnetometer readings (IMU)
- **Location Data**: GPS coordinates (only while app is in use)
- **Camera Data**: Images from device cameras
- **Environmental Data**: Barometer, ambient light sensor
- **Device State**: Battery level, thermal state
- **LiDAR Data**: Depth sensing (on supported devices)
- **Game Controller Input**: Button and joystick data
- **Audio Data**: Microphone samples (when the Microphone sensor is enabled)
- **Proximity Data**: Front-facing proximity sensor reading

**Important Notes**:

- All sensor data collection is **opt-in**. Sensors are disabled by default.
- Data is transmitted **only to the Zenoh router or DDS subscriber you configure** (typically on your local network — under your control, not ours).
- **No sensor data is sent to our servers** or any third-party servers. Conduit operates no backend; the app is a wire-level publisher only.
- **Background GPS tracking is not supported** due to privacy constraints. Location data is only collected while the app is active.

### Analytics Data

The app uses Firebase Analytics to collect:

- **Device Information**: Device model, OS version
- **App Usage**: Feature usage, error occurrences
- **Anonymous Identifiers**: Non-personal device identifiers

This data is used solely to improve app functionality and user experience.

## How Data Is Used

**Sensor Data:**

- Transmitted directly to your configured ROS 2 system over Zenoh (`rmw_zenoh_cpp`) or DDS (`rmw_cyclonedds_cpp`)
- Used for robotics development, research, and testing
- Never stored on our servers
- Never shared with third parties

**Analytics Data:**

- Used to identify bugs and improve app performance
- Aggregated and anonymized
- Processed by Google Firebase Analytics (see their [privacy policy](https://firebase.google.com/support/privacy))

## Data Storage and Security

- **Sensor data**: Not stored by the app. Transmitted in real-time to your ROS 2 system.
- **Configuration settings**: Stored locally on your device using iOS Keychain and UserDefaults. The 16-byte ROS 2 publisher GID is generated once and persisted to Keychain so the same publisher identity survives app launches.
- **Network transmission**: Data is sent over your local network to the Zenoh router or DDS subscriber you configure.
- **Firebase Analytics**: Collects anonymous usage statistics. Subject to [Google's Privacy Policy](https://policies.google.com/privacy). You can opt out by disabling analytics in iOS Settings → Privacy → Analytics & Improvements.

## Permissions

| Permission | Purpose | Required |
|---|---|---|
| Camera | Publish camera images to ROS 2 | Optional |
| Microphone | Publish audio samples to ROS 2 | Optional |
| Location (When In Use) | Publish GPS data to ROS 2 | Optional |
| Motion & Fitness | Access IMU sensors | Optional |
| Local Network | Connect to Zenoh router or DDS subscriber on your network | Required |

**Note**: All permissions except Local Network are optional. You can selectively enable only the sensors you need.

## Your Rights

You have the right to:

- **Control sensor access**: Enable/disable any sensor at any time
- **Delete app data**: Uninstall the app to remove all local data
- **Opt out of analytics**: Disable analytics in iOS Settings

## Data Retention

- **Sensor data**: Not retained by the app (transmitted in real-time)
- **Configuration data**: Stored until app is uninstalled
- **Analytics data**: Retained by Firebase per [their retention policy](https://support.google.com/firebase/answer/7029846)

## Policy Updates

We may update this privacy policy from time to time. Changes will be posted on this page with an updated "Last Updated" date.

## Contact

For questions or concerns:

- **LinkedIn**: https://www.linkedin.com/in/youtalk
- **Website**: https://youtalk.jp

**Note**: This app is designed for developers and researchers. It is not intended for children under 13.
