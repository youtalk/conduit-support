# Docker Testing Environment for iOS ROS 2 IMU Publisher

This directory contains Docker configuration for testing the iOS ROS 2 IMU publisher with ROS 2 Jazzy and Humble using rmw_zenoh_cpp.

## Overview

A unified Dockerfile supports both ROS 2 distributions via build arguments:
- **ros-jazzy**: ROS 2 Jazzy with rmw_zenoh_cpp
- **ros-humble**: ROS 2 Humble with rmw_zenoh_cpp

Each container provides:
- rmw_zenoh_cpp from apt packages
- Zenoh router (rmw_zenohd) running on port 7447
- Utility scripts for testing and verification

**Note:** Only run ONE container at a time since they share the same port (7447).

## Dockerfile Architecture

The unified `Dockerfile` uses `ARG ROS_DISTRO` to select the ROS distribution at build time:

```dockerfile
ARG ROS_DISTRO=jazzy
FROM ros:${ROS_DISTRO}
```

This allows building both Humble and Jazzy images from a single Dockerfile.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   macOS Host                        │
│                                                     │
│  ┌─────────────────┐      ┌──────────────────────┐│
│  │ iOS Simulator   │      │  Docker Container    ││
│  │                 │      │  (ROS Jazzy)         ││
│  │  iOS App        │      │                      ││
│  │  (Mock IMU)     │      │  rmw_zenohd          ││
│  │                 │      │  (port 7447)         ││
│  │  Zenoh Client   │◄────►│  Zenoh Router        ││
│  │                 │      │                      ││
│  │  localhost      │      │  ROS 2 Subscriber    ││
│  │  -> host.       │      │  (ros2 topic echo)   ││
│  │  docker.        │      │                      ││
│  │  internal       │      │                      ││
│  └─────────────────┘      └──────────────────────┘│
│                                                     │
│  Network: Bridge (macOS ←→ Docker)                 │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Docker Desktop** (required)
   - Download from: https://www.docker.com/products/docker-desktop
   - Available for Mac, Windows, and Linux
   - Install and start Docker Desktop
   - Verify installation: `docker --version`

2. **Xcode** (already installed)
   - Version 26.1 or later
   - Command Line Tools installed

3. **iOS Simulator** (already available)
   - Any iOS 16+ simulator

## Quick Start (10 Minutes)

### 1. Install Docker Desktop (if not installed)

```bash
# Download and install Docker Desktop
# Visit: https://www.docker.com/products/docker-desktop
# After installation, start Docker Desktop

# Verify Docker is running
docker --version
docker ps
```

### 2. Build and Start Container

```bash
cd support/docker

# Build both Docker images (first time: ~10-15 minutes each)
docker compose build

# Start Jazzy container (for Jazzy testing)
docker compose up ros-jazzy -d

# OR Start Humble container (for Humble testing)
docker compose up ros-humble -d

# Verify container is running
docker compose ps

# Check logs
docker compose logs -f
```

**Important:** Only run ONE container at a time. To switch between distros:
```bash
# Stop current container
docker compose down

# Start the other distro
docker compose up ros-humble -d   # or ros-jazzy
```

#### Configuring ROS_DOMAIN_ID

The Docker container supports configurable ROS 2 domain ID (0-255). The domain ID must match between the container and iOS app.

**Method 1: Using .env file (recommended for persistent configuration)**
```bash
# Copy example file
cp .env.example .env

# Edit .env and set your domain ID
echo "ROS_DOMAIN_ID=5" > .env

# Start container (will use domain ID from .env)
docker compose up ros-jazzy -d
```

**Method 2: Command-line override (one-time use)**
```bash
# Start with custom domain ID
ROS_DOMAIN_ID=5 docker compose up ros-jazzy -d
```

**Method 3: Export environment variable (affects all commands in current shell)**
```bash
# Set domain ID for current shell session
export ROS_DOMAIN_ID=5

# Start container
docker compose up ros-jazzy -d
```

**Important:**
- Domain ID must match between Docker container and iOS app
- Valid range: 0-255
- Default is 0 if not specified
- Topics will only be visible when domain IDs match on both sides

You should see output like:
```
========================================
ROS 2 Jazzy + rmw_zenoh_cpp Container   (or Humble)
========================================
ROS_DISTRO: jazzy
RMW_IMPLEMENTATION: rmw_zenoh_cpp
ROS_DOMAIN_ID: 0
Container IP: 172.17.0.2
Zenoh router port: 7447

Starting rmw_zenohd router...
```

### 3. Get Container IP Address

```bash
# For Jazzy container:
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ros_jazzy_zenoh

# For Humble container:
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ros_humble_zenoh
```

**Example output:** `172.17.0.2`

### 4. Configure iOS App

Edit `Config/Config.plist`:

```xml
<key>router_locator</key>
<string>tcp/172.17.0.2:7447</string>

<key>rate_hz</key>
<integer>100</integer>
```

**Important:**
- Use the container IP from step 3, not `localhost`
- Select matching wire mode in iOS app UI (Humble or Jazzy toggle)

### 5. Build and Run iOS Simulator

```bash
# Open Xcode project
open Conduit.xcodeproj

# Or use xcodebuild command line
```

In Xcode:
1. Select **iPhone 17 Pro (Simulator)** as target
2. Click **Run** (⌘R)
3. Wait for simulator to launch
4. Tap **"Connect & Publish"** button in app

### 6. Verify Data Flow

Open a new terminal and run:

```bash
# Terminal 2: Echo IMU messages
docker exec -it ros_jazzy_zenoh /usr/local/bin/echo-imu.sh
```

You should see IMU messages streaming:
```yaml
header:
  stamp:
    sec: 1699564823
    nanosec: 123456789
  frame_id: ios_imu
orientation:
  x: 0.0
  y: 0.0
  z: 0.049979169
  w: 0.998750260
# ...
```

### 7. Check Publishing Rate

```bash
# Terminal 3: Check rate
docker exec -it ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && source /ros2_ws/install/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic hz /ios/imu"
```

**Expected:** `average rate: 100.000`

## Docker Commands Reference

### Container Management

```bash
# Start Jazzy container
docker compose up ros-jazzy -d

# Start Humble container
docker compose up ros-humble -d

# Stop all containers
docker compose down

# Restart specific container
docker compose restart ros-jazzy  # or ros-humble

# View logs
docker compose logs -f ros-jazzy  # or ros-humble

# Check status
docker compose ps
```

### ROS 2 Commands in Container

**For Jazzy:**
```bash
# List all topics
docker exec -it ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic list"

# Echo IMU topic
docker exec -it ros_jazzy_zenoh /usr/local/bin/echo-imu.sh

# Check topic info
docker exec -it ros_jazzy_zenoh /usr/local/bin/check-topics.sh

# Interactive bash session
docker exec -it ros_jazzy_zenoh bash
```

**For Humble:**
```bash
# List all topics
docker exec -it ros_humble_zenoh bash -c "source /opt/ros/humble/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic list"

# Echo IMU topic
docker exec -it ros_humble_zenoh /usr/local/bin/echo-imu.sh

# Check topic info
docker exec -it ros_humble_zenoh /usr/local/bin/check-topics.sh

# Interactive bash session
docker exec -it ros_humble_zenoh bash
```

### Inside Container

Once inside the container:

```bash
# Environment is already set up
ros2 topic list
ros2 topic echo /ios/imu
ros2 topic hz /ios/imu
ros2 topic info /ios/imu -v
ros2 topic bw /ios/imu
```

## Network Configuration

### iOS Simulator → Docker Container

The iOS Simulator can access the Docker container using the container's bridge network IP address.

**Key Points:**
- iOS Simulator runs in a separate network namespace
- Use Docker container's bridge IP (e.g., `172.17.0.2`)
- Do NOT use `localhost` or `127.0.0.1`
- Port 7447 is exposed from container to host

### Getting Container IP

```bash
# Method 1: Docker inspect
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ros_jazzy_zenoh

# Method 2: Inside container
docker exec -it ros_jazzy_zenoh hostname -I

# Method 3: Docker network inspect
docker network inspect bridge | grep -A 5 ros_jazzy_zenoh
```

### Testing Network Connectivity

From the host terminal:

```bash
# Test if port 7447 is reachable
nc -zv 172.17.0.2 7447

# Or use telnet
telnet 172.17.0.2 7447
```

## Troubleshooting

### Problem: Container Won't Start

**Symptoms:**
- `docker compose up` fails
- Container exits immediately

**Solutions:**
```bash
# Check logs
docker compose logs

# Rebuild image
docker compose build --no-cache

# Check Docker Desktop is running
open -a Docker
```

### Problem: iOS App Can't Connect

**Symptoms:**
- App shows "Connection failed"
- Timeout errors

**Solutions:**
1. Verify container is running:
   ```bash
   docker compose ps
   ```

2. Check container IP:
   ```bash
   docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ros_jazzy_zenoh
   ```

3. Test connectivity from host:
   ```bash
   nc -zv <container-ip> 7447
   ```

4. Verify Config.plist has correct IP

5. Check firewall settings on the host system

### Problem: Topics Not Visible or Domain Mismatch

**Symptoms:**
- `ros2 topic list` doesn't show iOS topics
- Topics appear in one domain but not another
- App connects but topics don't appear

**Solutions:**
1. Verify domain ID in container:
   ```bash
   docker exec -it ros_jazzy_zenoh bash -c "echo \$ROS_DOMAIN_ID"
   ```

2. Check domain ID in iOS app:
   - Open Settings in the app
   - Verify "Domain ID" field matches container

3. Restart container with matching domain ID:
   ```bash
   # Stop container
   docker compose down

   # Start with matching domain ID
   ROS_DOMAIN_ID=5 docker compose up ros-jazzy -d
   ```

4. Verify both sides use the same domain:
   ```bash
   # In container
   docker exec -it ros_jazzy_zenoh bash
   echo "Container domain: $ROS_DOMAIN_ID"

   # Check if topics appear
   ros2 topic list
   ```

**Important:** ROS 2 uses domain IDs for network isolation. Topics will only be visible when both publisher (iOS app) and subscriber (Docker container) use the same domain ID (0-255).

### Problem: No Messages on Topic

**Symptoms:**
- `ros2 topic echo /ios/imu` shows nothing
- App says "Publishing" but no data

**Solutions:**
1. Check topic exists:
   ```bash
   docker exec -it ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && source /ros2_ws/install/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic list | grep imu"
   ```

2. Verify domain IDs match:
   - Check container: `docker exec -it ros_jazzy_zenoh bash -c "echo \$ROS_DOMAIN_ID"`
   - Check app: Open Settings → verify Domain ID field matches

3. Verify wire mode:
   - Config.plist should have `wire_mode` set to `jazzy`

4. Check app logs in Xcode console:
   - Look for "Running in simulator - using mock data"
   - Look for "Started publishing at 100 Hz"

5. Restart both app and container:
   ```bash
   docker compose restart
   ```

### Problem: Build Fails

**Symptoms:**
- `docker compose build` fails
- rmw_zenoh build errors

**Solutions:**
```bash
# Clean everything and rebuild
docker compose down -v
docker system prune -a
docker compose build --no-cache
```

### Problem: Low Publishing Rate

**Symptoms:**
- `ros2 topic hz` shows < 95 Hz

**Solutions:**
1. Check host CPU usage
2. Reduce load on simulator
3. Verify network latency
4. Check Config.plist rate_hz setting

## Testing Checklist

- [ ] Docker Desktop installed and running
- [ ] Container built successfully
- [ ] Container is running (docker compose ps)
- [ ] Container IP obtained
- [ ] ROS_DOMAIN_ID configured (in .env or environment variable)
- [ ] Domain ID matches between container and iOS app
- [ ] Config.plist updated with container IP
- [ ] iOS Simulator app built and running
- [ ] App shows "Running in simulator - using mock data"
- [ ] App shows "Publishing" status
- [ ] `ros2 topic list` shows `/ios/imu`
- [ ] `ros2 topic echo /ios/imu` receives messages
- [ ] Messages have correct format
- [ ] Publishing rate is ~100 Hz
- [ ] Sequence numbers are monotonic
- [ ] Timestamps are UNIX epoch

## Performance Metrics

Expected performance:

| Metric | Expected | Typical |
|--------|----------|---------|
| Container startup | < 5 sec | 2-3 sec |
| App connection time | < 2 sec | < 1 sec |
| Publishing rate | 100 Hz ±5% | 100.0 Hz |
| Message latency | < 10 ms | 3-5 ms |
| Container CPU | < 5% | 2-3% |
| Container memory | < 500 MB | 350 MB |

## Cleanup

```bash
# Stop and remove container
docker compose down

# Remove image
docker rmi docker_ros-jazzy

# Clean up all Docker resources
docker system prune -a --volumes
```

## Advanced Usage

### Custom Router Configuration

Edit `docker compose.yml` to add custom Zenoh router configuration:

```yaml
services:
  ros-jazzy:
    volumes:
      - ./zenoh-config.json:/etc/zenoh/zenoh-config.json
    environment:
      - ZENOH_ROUTER_CONFIG=/etc/zenoh/zenoh-config.json
```

### Running Both Distros Simultaneously

To test Humble and Jazzy at the same time (different ports):

1. Edit `docker-compose.yml` to use different ports:
```yaml
services:
  ros-jazzy:
    ports:
      - "7447:7447"  # Keep default

  ros-humble:
    ports:
      - "7448:7447"  # Use different host port
```

2. Start both:
```bash
docker compose up -d
```

3. Configure iOS app to connect to appropriate port:
   - Jazzy: `tcp/172.17.0.x:7447`
   - Humble: `tcp/172.17.0.y:7448`

### Persistent Logs

```yaml
services:
  ros-jazzy:
    volumes:
      - ./logs:/var/log/ros
```

## Next Steps

After successful Docker testing:
1. Test with physical iOS device
2. Test with native ROS 2 installation (non-Docker)
3. Deploy to production environment
4. Implement monitoring and alerts

## Reference

- Docker Documentation: https://docs.docker.com
- ROS 2 Jazzy: https://docs.ros.org/en/jazzy/
- rmw_zenoh: https://github.com/ros2/rmw_zenoh
