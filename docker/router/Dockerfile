# Conduit's Zenoh router: rmw_zenohd for an iPhone and the user's own ROS 2
# containers on a PC without ROS 2. pair.sh starts it as `conduit-router` with the
# router port (7447) and its check-in port (7449) published (docker/router/README.md).
# Built from the repository root:
#   docker build -f docker/router/Dockerfile --build-arg ROS_DISTRO=lyrical -t conduit-router:lyrical-dev .
# Run:
#   docker run -d --name conduit-router -p 7447:7447 conduit-router:lyrical-dev
#   docker exec -it conduit-router with-ros ros2 topic list
# Offered for jazzy and lyrical (Rolling PCs use lyrical).
ARG ROS_DISTRO=lyrical

# audio_common_msgs (Conduit's microphone topic) has no binary package: build it
# here, with the build tools, and copy only its install space.
FROM ros:${ROS_DISTRO}-ros-base AS build
ARG ROS_DISTRO
SHELL ["/bin/bash", "-c"]
RUN git clone --branch ros2 --depth 1 https://github.com/ros-drivers/audio_common.git /tmp/audio_common && \
    mkdir -p /ws/src && cp -r /tmp/audio_common/audio_common_msgs /ws/src/ && \
    cd /ws && source "/opt/ros/${ROS_DISTRO}/setup.bash" && \
    colcon build --merge-install --install-base /opt/conduit --packages-select audio_common_msgs

FROM ros:${ROS_DISTRO}-ros-core
ARG ROS_DISTRO
ENV DEBIAN_FRONTEND=noninteractive

# rmw_zenoh_cpp for the router and the CLI; tf2_msgs for pair.sh's /tf_static
# check; point_cloud_interfaces for Conduit's compressed LiDAR topic.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-rmw-zenoh-cpp \
    ros-${ROS_DISTRO}-tf2-msgs \
    ros-${ROS_DISTRO}-point-cloud-interfaces \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/conduit /opt/conduit
COPY docker/router/with-ros /usr/local/bin/with-ros
COPY docker/router/entrypoint.sh /entrypoint.sh

ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp
EXPOSE 7447/tcp
# rmw_zenohd ends cleanly on SIGINT.
STOPSIGNAL SIGINT
ENTRYPOINT ["/entrypoint.sh"]
CMD ["router"]
