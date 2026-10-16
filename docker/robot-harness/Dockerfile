# Conduit robot harness (ROS 2 Jazzy): a fake mobile robot behind conduit_teleop,
# MoveIt Servo Panda on mock hardware with a gripper action server, and
# conduit_gate_probe. Built from the repository root:
#   docker build -f docker/robot-harness/Dockerfile -t conduit-robot-harness:jazzy .
# Linux hosts only (host networking for DDS).
ARG ROS_DISTRO=jazzy
FROM ros:${ROS_DISTRO}

ARG ROS_DISTRO
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
    ros-${ROS_DISTRO}-rmw-zenoh-cpp \
    ros-${ROS_DISTRO}-teleop-twist-joy \
    ros-${ROS_DISTRO}-tf2-ros \
    ros-${ROS_DISTRO}-xacro \
    ros-${ROS_DISTRO}-moveit-servo \
    ros-${ROS_DISTRO}-moveit-configs-utils \
    ros-${ROS_DISTRO}-moveit-resources-panda-moveit-config \
    ros-${ROS_DISTRO}-launch-param-builder \
    ros-${ROS_DISTRO}-ros2-control \
    ros-${ROS_DISTRO}-ros2-controllers \
    ros-${ROS_DISTRO}-control-msgs \
    ros-${ROS_DISTRO}-robot-state-publisher \
    python3-numpy \
    python3-pil \
    python3-pytest \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ros2_ws
COPY ros/conduit_teleop src/conduit_teleop
COPY ros/conduit_robot_harness src/conduit_robot_harness
COPY ros/conduit_gate_probe src/conduit_gate_probe
RUN . /opt/ros/${ROS_DISTRO}/setup.sh && colcon build

COPY docker/robot-harness/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
