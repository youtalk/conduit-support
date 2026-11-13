# Conduit Robots demo: a TurtleBot3 on Nav2's loopback simulator with a camera drawn
# from the map, and a Panda in Gazebo with wrist and head cameras, MoveIt Servo and move_group,
# behind their own Zenoh router or on a PC's ROS 2 graph. One Dockerfile for every
# distribution the demo is offered on (jazzy, kilted, lyrical: the same package names;
# Gazebo Harmonic, Ionic and Jetty come with each one's ros_gz). Built from the repository
# root (docker/demo/README.md):
#   docker build -f docker/demo/Dockerfile --build-arg ROS_DISTRO=lyrical -t conduit-demo:lyrical-dev .
# Run (see docker/demo/entrypoint.sh for the modes):
#   docker run --rm -p 7447:7447 conduit-demo:lyrical-dev standalone   # both robots
#   docker run --rm --network host -e RMW_IMPLEMENTATION -e ROS_DOMAIN_ID \
#     -e ZENOH_CONFIG_OVERRIDE='mode="client";connect/endpoints=["tcp/127.0.0.1:7447"]' \
#     conduit-demo:lyrical-dev join   # both robots on this PC's graph (exit 3: a name clash)
#   docker run --rm -p 7447:7447 conduit-demo:lyrical-dev mobile       # the TurtleBot3
#   docker run --rm -p 7447:7447 conduit-demo:lyrical-dev arm          # the Panda
# Gazebo renders the wrist camera without a GPU (Mesa llvmpipe); `gpu:=true` raises the
# camera to 640 x 480 at 15 Hz with full visuals for a container with a GPU.
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
    ros-${ROS_DISTRO}-xacro \
    ros-${ROS_DISTRO}-ros-gz-sim \
    ros-${ROS_DISTRO}-ros-gz-bridge \
    ros-${ROS_DISTRO}-gz-ros2-control \
    ros-${ROS_DISTRO}-controller-manager \
    ros-${ROS_DISTRO}-joint-state-broadcaster \
    ros-${ROS_DISTRO}-joint-trajectory-controller \
    ros-${ROS_DISTRO}-parallel-gripper-controller \
    ros-${ROS_DISTRO}-moveit-servo \
    ros-${ROS_DISTRO}-moveit-ros-move-group \
    ros-${ROS_DISTRO}-moveit-planners-ompl \
    ros-${ROS_DISTRO}-moveit-simple-controller-manager \
    ros-${ROS_DISTRO}-moveit-kinematics \
    ros-${ROS_DISTRO}-moveit-configs-utils \
    ros-${ROS_DISTRO}-moveit-resources-panda-moveit-config \
    ros-${ROS_DISTRO}-moveit-resources-panda-description \
    ros-${ROS_DISTRO}-launch-param-builder \
    python3-numpy \
    libegl-mesa0 \
    libgl1-mesa-dri \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ros2_ws
COPY ros/conduit_teleop src/conduit_teleop
COPY ros/conduit_demo src/conduit_demo
RUN . /opt/ros/${ROS_DISTRO}/setup.sh \
    && colcon build --event-handlers console_direct- \
    && rm -rf build log

ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp
# Gazebo's own transport finds its peers by multicast. On the host network (join) it would
# reach a Gazebo the PC runs; a partition of its own keeps the demo's Gazebo to itself.
# On a Docker bridge network it would reach the Gazebo of another demo container on the
# same host (the second one's world then fails to start); the loopback interface keeps it
# inside the container (inside the host on the host network).
ENV GZ_PARTITION=conduit_demo
ENV GZ_IP=127.0.0.1
COPY docker/demo/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["standalone"]
# ros2 launch, PID 1 after the entrypoint, shuts its nodes down on SIGINT (Ctrl-C) but
# ignores SIGTERM, so `docker stop` would wait out its timeout and kill everything.
STOPSIGNAL SIGINT
