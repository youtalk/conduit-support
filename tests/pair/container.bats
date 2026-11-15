#!/usr/bin/env bats
# pair.sh's container path: a Mac, a Linux PC without ROS 2, or --container
# pairs with a Zenoh router in Docker (conduit-router) and waits for Conduit's
# node and /tf_static through `docker exec`. demo.bats covers --demo on top.

bats_require_minimum_version 1.5.0
load helpers

ROUTE='1.1.1.1 via 192.168.1.1 dev wlp130s0f0 src 192.168.1.85 uid 1000'
LAN_ADDR='3: wlp130s0f0    inet 192.168.1.85/24 scope global wlp130s0f0'
GOOD_CHECKIN='CHECKIN phone_ip=192.168.1.50 node=conduit_node namespace=conduit device=iPhone app_version=3.0.0'
ROUTER_IMAGE='ghcr.io/youtalk/conduit-router:lyrical-0.1.0'

setup() {
  load_script
  make_fixture
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CYCLONEDDS_URI ROS_STATIC_PEERS FASTRTPS_DEFAULT_PROFILES_FILE PAIR_FORCE_VIA CONDUIT_DEMO_IMAGE CONDUIT_ROUTER_IMAGE
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  PATH="$STUBS:$PATH"
  export PATH
  export PAIR_TTY="$BATS_TEST_TMPDIR/tty"
  : > "$PAIR_TTY"
  export RMW_IMPLEMENTATION=rmw_zenoh_cpp ROS_DOMAIN_ID=123
  zenoh_router_listening() { return 0; }
  stub_ip "$ROUTE" "$LAN_ADDR"
  stub_listener "$GOOD_CHECKIN"
  stub_ros2 '/conduit/conduit_node' 'frame_id: conduit_base_link'
  stub_docker
  # tcp_open HOST PORT: 127.0.0.1 accepts on the ports listed in
  # $BATS_TEST_TMPDIR/taken (see `taken`); a LAN address accepts unless
  # $BATS_TEST_TMPDIR/lan_blocked exists.
  : > "$BATS_TEST_TMPDIR/taken"
  tcp_open() {
    if [[ "$1" == 127.0.0.1 ]]; then
      grep -qxF "$2" "$BATS_TEST_TMPDIR/taken"
    else
      [[ ! -e "$BATS_TEST_TMPDIR/lan_blocked" ]]
    fi
  }
}

taken() { printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/taken"; }

no_ros() {
  rm -rf "$CONDUIT_PAIR_ROOT/opt/ros"
  unset ROS_DISTRO RMW_IMPLEMENTATION ROS_DOMAIN_ID
}

on_macos() {
  no_ros
  export PAIR_UNAME=Darwin
  stub_macos_net en0 192.168.1.73
}

# ros_setup DISTRO: an /opt/ros/DISTRO/setup.bash that sets what a real one does.
ros_setup() {
  mkdir -p "$CONDUIT_PAIR_ROOT/opt/ros/$1"
  printf 'export ROS_DISTRO=%s\n' "$1" > "$CONDUIT_PAIR_ROOT/opt/ros/$1/setup.bash"
}

docker_calls() { cat "$DOCKER_STUB/calls" 2> /dev/null || true; }

@test "--demo is not in the help" {
  run main --help
  [ "$status" -eq 0 ]
  lacks "--demo"
}

router_run() {
  echo "run -d --name conduit-router --restart unless-stopped -p $1:7447 -p $2:7449 ${3:-$ROUTER_IMAGE}"
}

# running_router IMAGE ROUTER CHECKIN: a router container already runs.
running_router() {
  echo "$1" >> "$DOCKER_STUB/images"
  echo "true $1 bridge" > "$(router_dir)/container"
  echo "running 0" > "$(router_dir)/status"
  printf '%s\n' "7447 0.0.0.0:$2" "7447 [::]:$2" "7449 0.0.0.0:$3" > "$(router_dir)/ports"
  echo "Started Zenoh router with id 0123456789abcdef" > "$(router_dir)/logs"
}

@test "macOS takes the container path without --demo" {
  on_macos
  run main --no-qr
  [ "$status" -eq 0 ]
  called "$(router_run 7447 7449)"
  has "https://conduit.direct/pair#v=1&transport=zenoh&distro=lyrical&domain=0&host=192.168.1.73&port=7447&checkin=192.168.1.73%3A7449&token="
  has "Connected to iPhone."
  not_called conduit-demo
  lacks "Add robot"
}

@test "Linux without ROS 2 asks, downloads the router image and pairs with it" {
  no_ros
  run main --no-qr
  [ "$status" -eq 0 ]
  has "Start a Zenoh router for the iPhone in Docker (container conduit-router, downloads $ROUTER_IMAGE, about 1 GB)? [Y/n]"
  called "pull $ROUTER_IMAGE"
  called "$(router_run 7447 7449)"
  grep -q '^exec -i conduit-router python3 -u -c ' "$DOCKER_STUB/calls"
  has "iPhone checked in."
  lacks "checked in from"
  has "Connected to iPhone."
}

@test "declining the router stops before Docker changes anything" {
  no_ros
  echo n > "$PAIR_TTY"
  run main --no-qr
  [ "$status" -eq 1 ]
  has "https://docs.ros.org/en/lyrical/Get-Started/Installation.html"
  not_called '^pull \|^run '
  lacks "conduit.direct/pair"
}

@test "a router image already here is not downloaded again" {
  no_ros
  echo "$ROUTER_IMAGE" > "$DOCKER_STUB/images"
  run main --no-qr
  [ "$status" -eq 0 ]
  has "Start a Zenoh router for the iPhone in Docker (container conduit-router)? [Y/n]"
  not_called '^pull '
  called "$(router_run 7447 7449)"
}

@test "the node and data checks run in the router container" {
  no_ros
  run main --no-qr
  [ "$status" -eq 0 ]
  grep -q '^exec conduit-router with-ros ros2 node list --no-daemon --spin-time 3$' "$DOCKER_STUB/calls"
  grep -q '^exec conduit-router with-ros timeout -k 5 20 ros2 topic echo --qos-durability transient_local --qos-reliability reliable /tf_static tf2_msgs/msg/TFMessage$' "$DOCKER_STUB/calls"
}

@test "the next steps say how to use the router and stop it" {
  no_ros
  run main --no-qr
  [ "$status" -eq 0 ]
  has "The Zenoh router keeps running in Docker (container conduit-router, port 7447)"
  has "your own ROS 2 Lyrical containers"
  has "They need ros-lyrical-rmw-zenoh-cpp, which the ros:lyrical image does not have:"
  has "docker run --rm -it --network container:conduit-router -e RMW_IMPLEMENTATION=rmw_zenoh_cpp ros:lyrical bash -c 'apt-get update && apt-get install -y ros-lyrical-rmw-zenoh-cpp && source /opt/ros/lyrical/setup.bash && exec bash'"
  has "export ZENOH_CONFIG_OVERRIDE='connect/endpoints=[\"tcp/192.168.1.85:7447\"]'"
  has "docker exec -it conduit-router with-ros ros2 topic echo /conduit/imu"
  has "To stop the router: docker stop conduit-router"
  # Printed once.
  [ "$(grep -c 'docker stop conduit-router' <<< "$output")" -eq 1 ]
}

@test "no data on /tf_static exits 2 with the container path's causes and the stop hint" {
  no_ros
  stub_ros2 '/conduit/conduit_node' 'frame_id: map'
  run main --no-qr
  [ "$status" -eq 2 ]
  has "Conduit is on the router, but no message arrived on /tf_static"
  has "must be Lyrical"
  lacks "ufw"
  has "The Zenoh router keeps running (container conduit-router). To stop it: docker stop conduit-router"
}

@test "--distro jazzy uses the Jazzy router" {
  no_ros
  run main --distro jazzy --no-qr
  [ "$status" -eq 0 ]
  called "$(router_run 7447 7449 ghcr.io/youtalk/conduit-router:jazzy-0.1.0)"
  has "&distro=jazzy&domain=0&"
  has "ros:jazzy bash -c 'apt-get update && apt-get install -y ros-jazzy-rmw-zenoh-cpp && source /opt/ros/jazzy/setup.bash && exec bash'"
}

@test "--distro rolling uses the Lyrical router" {
  no_ros
  run main --distro rolling --no-qr
  [ "$status" -eq 0 ]
  called "$(router_run 7447 7449)"
  has "&distro=lyrical&"
}

@test "Humble and Kilted have no router container" {
  no_ros
  for distro in humble kilted; do
    run main --distro "$distro" --no-qr
    [ "$status" -eq 1 ]
    has "Jazzy or Lyrical"
  done
  [ -z "$(docker_calls)" ]
}

@test "an unknown --distro is refused" {
  run main --distro foxy --no-qr
  [ "$status" -eq 1 ]
  has "--distro must be"
}

@test "--distro with this PC's own ROS 2 says to add --container" {
  run main --distro lyrical --no-qr
  [ "$status" -eq 1 ]
  has "Add --container"
  [ -z "$(docker_calls)" ]
}

@test "--container uses the router even with ROS 2 on this PC" {
  run main --container --no-qr
  [ "$status" -eq 0 ]
  called "$(router_run 7447 7449)"
  has "&distro=lyrical&domain=0&"
  # This PC's ros2 is never asked: every ros2 call went through docker exec.
  [ "$(grep -c '' "$BATS_TEST_TMPDIR/ros2.log")" -eq "$(grep -c 'with-ros' "$DOCKER_STUB/calls")" ]
}

@test "ROS 2 installed but not sourced still says how to source it" {
  unset ROS_DISTRO
  ros_setup jazzy
  run main --no-qr
  [ "$status" -eq 1 ]
  has "installed but not sourced"
  [ -z "$(docker_calls)" ]
}

@test "the help lists --container and --distro" {
  run main --help
  [ "$status" -eq 0 ]
  has "--container"
  has "--distro D"
}

@test "the router port moves to 7448 when 7447 is taken" {
  no_ros
  taken 7447
  run main --no-qr
  [ "$status" -eq 0 ]
  called "$(router_run 7448 7449)"
  has "&port=7448&checkin=192.168.1.85%3A7449&"
  has "port 7448"
}

@test "the check-in port moves when 7449 is taken" {
  no_ros
  taken 7449
  run main --no-qr
  [ "$status" -eq 0 ]
  called "$(router_run 7447 7450)"
  has "&port=7447&checkin=192.168.1.85%3A7450&"
}

@test "the router and check-in ports never share one port" {
  no_ros
  taken 7447 7448
  run main --no-qr
  [ "$status" -eq 0 ]
  called "$(router_run 7449 7450)"
}

@test "no free port stops before the container" {
  no_ros
  taken 7447 7448 7449 7450 7451 7452 7453 7454 7455 7456 7457
  run main --no-qr
  [ "$status" -eq 1 ]
  has "7447-7457"
  not_called '^run '
}

@test "a running router is reused with its ports, without asking" {
  no_ros
  running_router "$ROUTER_IMAGE" 7451 7452
  run main --no-qr
  [ "$status" -eq 0 ]
  not_called '^run '
  not_called '^rm '
  lacks "[Y/n]"
  has "already running"
  has "&port=7451&checkin=192.168.1.85%3A7452&"
}

@test "a router of another image stops the container path" {
  no_ros
  running_router conduit-router:old 7447 7449
  run main --no-qr
  [ "$status" -eq 1 ]
  has "conduit-router:old"
  has "docker stop conduit-router"
  not_called '^run \|^rm '
}

@test "a stopped router container is replaced" {
  no_ros
  echo "false $ROUTER_IMAGE bridge" > "$(router_dir)/container"
  echo "exited 0" > "$(router_dir)/status"
  run main --no-qr
  [ "$status" -eq 0 ]
  called "rm conduit-router"
  called "$(router_run 7447 7449)"
}

@test "a port published on 127.0.0.1 only is reported before the QR" {
  no_ros
  touch "$BATS_TEST_TMPDIR/lan_blocked"
  run main --no-qr
  [ "$status" -eq 0 ]
  output="${output%%https://conduit.direct/pair#*}"
  has "could not connect to the router at 192.168.1.85:7447"
  has "127.0.0.1 only"
}

@test "a router container that does not start is reported" {
  no_ros
  echo "Bind for 0.0.0.0:7447 failed: port is already allocated" > "$(router_dir)/run_error"
  run main --no-qr
  [ "$status" -eq 1 ]
  has "port is already allocated"
  lacks "conduit.direct/pair"
}

@test "a router container that exits is reported with its log" {
  no_ros
  echo "rmw_zenohd: cannot bind 7447" > "$(router_dir)/crash_log"
  run main --no-qr
  [ "$status" -eq 1 ]
  has "The router container stopped"
  has "rmw_zenohd: cannot bind 7447"
  lacks "conduit.direct/pair"
}

@test "a reused router that never starts stops the wait and stays" {
  no_ros
  running_router "$ROUTER_IMAGE" 7447 7449
  echo "starting" > "$(router_dir)/logs"
  PAIR_ROUTER_START_SECONDS=2 run main --no-qr
  [ "$status" -eq 1 ]
  has "did not start within 2 seconds"
  lacks "conduit.direct/pair"
  not_called '^rm'
  has "docker stop conduit-router"
}

@test "a router this run started that never starts is removed" {
  no_ros
  touch "$(router_dir)/never_ready"
  PAIR_ROUTER_START_SECONDS=2 run main --no-qr
  [ "$status" -eq 1 ]
  has "did not start within 2 seconds"
  has "Removed the router container"
  called "rm -f conduit-router"
  [ ! -e "$(router_dir)/container" ]
  lacks "To stop it"
}

@test "a docker run that does not finish is force-removed" {
  no_ros
  touch "$(router_dir)/run_hang"
  PAIR_DOCKER_RUN_SECONDS=2 run main --no-qr
  [ "$status" -eq 1 ]
  has "did not finish within 2 seconds"
  called "rm -f conduit-router"
  [ ! -e "$(router_dir)/container" ]
}

@test "CONDUIT_ROUTER_IMAGE overrides the image" {
  no_ros
  export CONDUIT_ROUTER_IMAGE=conduit-router:lyrical-dev
  echo conduit-router:lyrical-dev > "$DOCKER_STUB/images"
  run main --no-qr
  [ "$status" -eq 0 ]
  called "$(router_run 7447 7449 conduit-router:lyrical-dev)"
  not_called '^pull '
}

@test "the QR code is drawn in the router container" {
  ! command -v qrencode > /dev/null || skip "qrencode draws it here"
  no_ros
  run main
  [ "$status" -eq 0 ]
  grep -q '^exec -i conduit-router python3 - https://conduit.direct/pair#v=1&transport=zenoh&distro=lyrical&' "$DOCKER_STUB/calls"
  has "Scan the QR"
}

@test "Docker Desktop not running offers to start it" {
  on_macos
  mkdir -p "$CONDUIT_PAIR_ROOT/Applications/Docker.app"
  echo down > "$DOCKER_STUB/info"
  stub_open
  run main --no-qr
  [ "$status" -eq 0 ]
  has "Docker Desktop is not running. Start it now? [Y/n]"
  called "open -a Docker"
  has "https://conduit.direct/pair#"
}

@test "Docker Desktop declined exits 1" {
  on_macos
  mkdir -p "$CONDUIT_PAIR_ROOT/Applications/Docker.app"
  echo down > "$DOCKER_STUB/info"
  stub_open
  echo n > "$PAIR_TTY"
  run main --no-qr
  [ "$status" -eq 1 ]
  has "Start Docker Desktop"
  not_called '^open '
}

@test "the Docker daemon refusing the user explains the docker group" {
  no_ros
  echo denied > "$DOCKER_STUB/info"
  run main --no-qr
  [ "$status" -eq 1 ]
  has "docker group"
  has "sudo usermod -aG docker"
  lacks "conduit.direct/pair"
}

@test "a Docker daemon that is not running is reported" {
  no_ros
  echo down > "$DOCKER_STUB/info"
  run main --no-qr
  [ "$status" -eq 1 ]
  has "sudo systemctl start docker"
}

@test "no Docker says how to install it, or ROS 2" {
  no_ros
  command() { [[ "$*" != "-v docker" ]] || return 1; builtin command "$@"; }
  run main --no-qr
  [ "$status" -eq 1 ]
  has "https://docs.docker.com/engine/install/"
  has "https://docs.ros.org/en/lyrical/Get-Started/Installation.html"
  lacks "conduit.direct/pair"
}

@test "no Docker on a Mac says to install Docker Desktop" {
  on_macos
  command() { [[ "$*" != "-v docker" ]] || return 1; builtin command "$@"; }
  run main --no-qr
  [ "$status" -eq 1 ]
  has "install Docker Desktop"
}
