# Conduit Support

Welcome to Conduit support! Get help, report bugs, and request features.

## 🆘 How to Get Support

### 🐛 Bug Reports & Feature Requests
**[Create an Issue](https://github.com/youtalk/conduit-support/issues/new/choose)**

Use our issue templates for:
- **Bug Report**: Report app crashes, sensor issues, or unexpected behavior
- **Feature Request**: Suggest new features or improvements
- **Connection Issue**: Network/router connection problems
- **Support Question**: General questions about setup or usage

### 💬 Community Discussions
**[Start a Discussion](https://github.com/youtalk/conduit-support/discussions)**

Join our community for:
- **Q&A**: Ask questions and get answers
- **Setup Help**: Get assistance with configuration
- **Show and Tell**: Share your robotics projects using Conduit
- **General**: General discussions about ROS 2 and robotics

## 📚 Documentation

Quick reference guides:
- **[FAQ](docs/FAQ.md)** - Frequently asked questions
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Platform Notes](docs/PLATFORM_NOTES.md)** - Platform-specific information
- **[Known Issues](docs/KNOWN_ISSUES.md)** - Current limitations and workarounds

## 🐳 Zenoh Router (For Testing)

Run a ROS 2 + rmw_zenoh_cpp router to test Conduit connectivity.

### Quick Start (Pre-built Image)

```bash
# ROS 2 Jazzy
docker run -d -p 7447:7447 --name ros_jazzy_zenoh ghcr.io/youtalk/conduit-support:jazzy

# ROS 2 Humble
docker run -d -p 7447:7447 --name ros_humble_zenoh ghcr.io/youtalk/conduit-support:humble
```

### Using Docker Compose

```bash
git clone https://github.com/youtalk/conduit-support.git
cd conduit-support/docker

# Start Jazzy router
docker compose up ros-jazzy -d

# Start Humble router
docker compose up ros-humble -d

# Stop
docker compose down
```

### Verify Connection

```bash
# Check topics
docker exec ros_jazzy_zenoh bash -c \
  "source /opt/ros/jazzy/setup.bash && ros2 topic list"

# Echo IMU data
docker exec ros_jazzy_zenoh bash -c \
  "source /opt/ros/jazzy/setup.bash && ros2 topic echo /ios/imu"
```

### Configure Conduit App

1. Find your Mac's IP address: `ifconfig | grep inet`
2. In Conduit Settings, set Router Address to: `tcp/<YOUR_IP>:7447`
3. Tap Play to connect

## 🔗 Links

- **App Website**: [youtalk.jp/conduit](https://www.youtalk.jp/conduit)
- **Main Repository**: [github.com/youtalk/conduit](https://github.com/youtalk/conduit)
- **Privacy Policy**: [youtalk.jp/conduit/#-privacy-policy](https://www.youtalk.jp/conduit/#-privacy-policy)

## 👨‍💻 Developer Contact

- **Developer**: Yutaka Kondo (youtalk)
- **LinkedIn**: [linkedin.com/in/youtalk](https://www.linkedin.com/in/youtalk)
- **Website**: [youtalk.jp](https://youtalk.jp)

---

**Note**: This repository is dedicated to support. For source code, see [Conduit](https://github.com/youtalk/conduit).
