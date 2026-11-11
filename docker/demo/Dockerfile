# Conduit Robots demo: a TurtleBot3 on Nav2's loopback simulator with a camera drawn
# from the map, and a Panda in Gazebo with a wrist camera, MoveIt Servo and move_group,
# behind their own Zenoh router. Built from the repository root:
#   docker build -f docker/demo/Dockerfile -t conduit-demo:lyrical-dev .
# Run (the router listens on 7447 inside the container):
#   docker run --rm -p 7447:7447 conduit-demo:lyrical-dev mobile   # the TurtleBot3
#   docker run --rm -p 7447:7447 conduit-demo:lyrical-dev arm      # the Panda
#   docker run --rm -p 7447:7447 conduit-demo:lyrical-dev all      # both
# Gazebo renders the wrist camera without a GPU (Mesa llvmpipe); `arm gpu:=true` raises
# the camera to 640 x 480 at 15 Hz with full visuals for a container with a GPU.
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
COPY docker/demo/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["mobile"]
# ros2 launch, PID 1 after the entrypoint, shuts its nodes down on SIGINT (Ctrl-C) but
# ignores SIGTERM, so `docker stop` would wait out its timeout and kill everything.
STOPSIGNAL SIGINT
