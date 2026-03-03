# Dockerfile for ROS 2 with rmw_zenoh_cpp
# Purpose: Test iOS ROS 2 sensor publisher with iOS Simulator
#
# Build args:
#   ROS_DISTRO: humble or jazzy (default: jazzy)
#
# Usage:
#   docker build --build-arg ROS_DISTRO=humble -t ros-humble-zenoh .
#   docker build --build-arg ROS_DISTRO=jazzy -t ros-jazzy-zenoh .

ARG ROS_DISTRO=jazzy
FROM ros:${ROS_DISTRO}

# Re-declare ARG after FROM (Docker requirement)
ARG ROS_DISTRO

# Set non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=${ROS_DISTRO}

# Install dependencies including rmw_zenoh_cpp from apt
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    python3-pip \
    wget \
    curl \
    net-tools \
    iputils-ping \
    vim \
    ros-${ROS_DISTRO}-rmw-zenoh-cpp \
    ros-${ROS_DISTRO}-point-cloud-interfaces \
    && rm -rf /var/lib/apt/lists/*

# Build audio_common_msgs from source (not available via apt)
WORKDIR /ros2_ws/src
RUN git clone --branch ros2 --depth 1 \
    https://github.com/ros-drivers/audio_common.git /tmp/audio_common && \
    cp -r /tmp/audio_common/audio_common_msgs /ros2_ws/src/ && \
    rm -rf /tmp/audio_common
WORKDIR /ros2_ws
RUN . /opt/ros/${ROS_DISTRO}/setup.sh && \
    colcon build --packages-select audio_common_msgs

# Setup environment
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /root/.bashrc && \
    echo "source /ros2_ws/install/setup.bash" >> /root/.bashrc && \
    echo "export RMW_IMPLEMENTATION=rmw_zenoh_cpp" >> /root/.bashrc

# Set RMW_IMPLEMENTATION
ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp

# Expose Zenoh router port
EXPOSE 7447/tcp

# Copy Zenoh router configuration
RUN mkdir -p /etc/zenoh
COPY zenoh-router.json5 /etc/zenoh/zenoh-router.json5

# Create startup script (uses ROS_DISTRO env var at runtime)
RUN echo '#!/bin/bash\n\
set -e\n\
source /opt/ros/${ROS_DISTRO}/setup.bash\n\
source /ros2_ws/install/setup.bash\n\
export RMW_IMPLEMENTATION=rmw_zenoh_cpp\n\
export ZENOH_ROUTER_CONFIG_URI=/etc/zenoh/zenoh-router.json5\n\
echo ""\n\
echo "========================================"\n\
echo "ROS 2 ${ROS_DISTRO^} + rmw_zenoh_cpp Container"\n\
echo "========================================"\n\
echo "ROS_DISTRO: ${ROS_DISTRO}"\n\
echo "RMW_IMPLEMENTATION: $RMW_IMPLEMENTATION"\n\
echo "ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-0}"\n\
echo "Container IP: $(hostname -I | awk '"'"'{print $1}'"'"')"\n\
echo "Zenoh router port: 7447 (listening on 0.0.0.0)"\n\
echo "Zenoh config: $ZENOH_ROUTER_CONFIG_URI"\n\
echo ""\n\
echo "Starting rmw_zenohd router..."\n\
echo ""\n\
exec ros2 run rmw_zenoh_cpp rmw_zenohd\n\
' > /usr/local/bin/start-router.sh && \
    chmod +x /usr/local/bin/start-router.sh

# Create topic echo script for IMU
RUN echo '#!/bin/bash\n\
source /opt/ros/${ROS_DISTRO}/setup.bash\n\
source /ros2_ws/install/setup.bash\n\
export RMW_IMPLEMENTATION=rmw_zenoh_cpp\n\
echo ""\n\
echo "Echoing /ios/imu topic..."\n\
echo "Press Ctrl+C to stop"\n\
echo ""\n\
ros2 topic echo /ios/imu\n\
' > /usr/local/bin/echo-imu.sh && \
    chmod +x /usr/local/bin/echo-imu.sh

# Create topic echo script for audio
RUN echo '#!/bin/bash\n\
source /opt/ros/${ROS_DISTRO}/setup.bash\n\
source /ros2_ws/install/setup.bash\n\
export RMW_IMPLEMENTATION=rmw_zenoh_cpp\n\
TOPIC=${1:-/conduit/audio}\n\
echo ""\n\
echo "Echoing ${TOPIC} topic (audio_common_msgs/msg/AudioData)..."\n\
echo "Press Ctrl+C to stop"\n\
echo ""\n\
ros2 topic echo ${TOPIC} audio_common_msgs/msg/AudioData\n\
' > /usr/local/bin/echo-audio.sh && \
    chmod +x /usr/local/bin/echo-audio.sh

# Create topic info script
RUN echo '#!/bin/bash\n\
source /opt/ros/${ROS_DISTRO}/setup.bash\n\
source /ros2_ws/install/setup.bash\n\
export RMW_IMPLEMENTATION=rmw_zenoh_cpp\n\
echo ""\n\
echo "=== Available Topics ==="\n\
ros2 topic list\n\
echo ""\n\
for topic in $(ros2 topic list 2>/dev/null | grep -v "^/parameter_events$\\|^/rosout$\\|^/tf_static$"); do\n\
  echo "=== ${topic} ==="\n\
  ros2 topic info ${topic} -v 2>/dev/null || echo "  Info not available"\n\
  echo ""\n\
done\n\
' > /usr/local/bin/check-topics.sh && \
    chmod +x /usr/local/bin/check-topics.sh

WORKDIR /ros2_ws

# Default command: start router
CMD ["/usr/local/bin/start-router.sh"]
