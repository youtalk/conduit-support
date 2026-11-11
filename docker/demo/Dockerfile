# Conduit Robots demo: a TurtleBot3 on Nav2's loopback simulator with a camera drawn
# from the map, behind its own Zenoh router. Built from the repository root:
#   docker build -f docker/demo/Dockerfile -t conduit-demo:lyrical-dev .
# Run (the router listens on 7447 inside the container):
#   docker run --rm -p 7447:7447 conduit-demo:lyrical-dev mobile
ARG ROS_DISTRO=lyrical
FROM ros:${ROS_DISTRO}

ARG ROS_DISTRO
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-rmw-zenoh-cpp \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
    ros-${ROS_DISTRO}-rmw-fastrtps-cpp \
    ros-${ROS_DISTRO}-navigation2 \
    ros-${ROS_DISTRO}-nav2-bringup \
    ros-${ROS_DISTRO}-nav2-loopback-sim \
    ros-${ROS_DISTRO}-nav2-minimal-tb3-sim \
    ros-${ROS_DISTRO}-robot-state-publisher \
    ros-${ROS_DISTRO}-teleop-twist-joy \
    ros-${ROS_DISTRO}-tf2-ros \
    ros-${ROS_DISTRO}-tf2-ros-py \
    python3-numpy \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ros2_ws
COPY ros/conduit_teleop src/conduit_teleop
COPY ros/conduit_demo src/conduit_demo
RUN . /opt/ros/${ROS_DISTRO}/setup.sh \
    && colcon build --event-handlers console_direct- \
    && rm -rf build log

ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp
COPY docker/demo/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["mobile"]
# ros2 launch, PID 1 after the entrypoint, shuts its nodes down on SIGINT (Ctrl-C) but
# ignores SIGTERM, so `docker stop` would wait out its timeout and kill everything.
STOPSIGNAL SIGINT
