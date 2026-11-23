#!/usr/bin/env bats
# pair.sh --demo, hidden until Conduit 3.0: on the container path (a Mac or a
# Linux PC without ROS 2) the demo joins the router container's graph; a Linux
# PC with ROS 2 pairs as usual and adds the demo robots to its graph.
# container.bats covers the router container itself.

bats_require_minimum_version 1.5.0
load helpers

ROUTE='1.1.1.1 via 192.168.1.1 dev wlp130s0f0 src 192.168.1.85 uid 1000'
LAN_ADDR='3: wlp130s0f0    inet 192.168.1.85/24 scope global wlp130s0f0'
GOOD_CHECKIN='CHECKIN phone_ip=192.168.1.50 node=conduit_node namespace=conduit device=iPhone app_version=3.0.0'
LYRICAL_IMAGE='ghcr.io/youtalk/conduit-demo:lyrical-0.1.0'
JAZZY_IMAGE='ghcr.io/youtalk/conduit-demo:jazzy-0.1.0'
ROUTER_IMAGE='ghcr.io/youtalk/conduit-router:lyrical-0.1.0'
ZENOH_CLIENT='ZENOH_CONFIG_OVERRIDE=mode="client";connect/endpoints=["tcp/127.0.0.1:7447"]'

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

@test "--demo is in the help" {
  run main --help
  [ "$status" -eq 0 ]
  has "--demo"
}

@test "macOS uses the default route's address" {
  on_macos
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "&host=192.168.1.73&port=7447&checkin=192.168.1.73%3A7449&"
}

@test "Linux without ROS 2 starts the router, then the demo on the router's graph" {
  no_ros
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  called "run -d --name conduit-router --restart unless-stopped -p 7447:7447 -p 7449:7449 $ROUTER_IMAGE"
  called "pull $LYRICAL_IMAGE"
  called "run -d --name conduit-demo --network container:conduit-router -e RMW_IMPLEMENTATION=rmw_zenoh_cpp -e ROS_DOMAIN_ID=0 -e $ZENOH_CLIENT $LYRICAL_IMAGE join"
  # The listener runs in the router container.
  grep -q '^exec -i conduit-router python3 -u -c ' "$DOCKER_STUB/calls"
  has "iPhone checked in."
  lacks "checked in from"
  has "The demo robots are starting on the router's graph."
  has "Connected to iPhone."
  has "Add robot"
  has "docker stop -t 30 conduit-demo && docker stop conduit-router"
}

@test "the demo link is Zenoh, Lyrical, domain 0, the chosen ports" {
  no_ros
  taken 7447 7449
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "https://conduit.direct/pair#v=1&transport=zenoh&distro=lyrical&domain=0&host=192.168.1.85&port=7448&checkin=192.168.1.85%3A7450&token="
}

@test "a stopped conduit-demo container is replaced" {
  no_ros
  echo "false $LYRICAL_IMAGE bridge" > "$DOCKER_STUB/container"
  echo "exited 0" > "$DOCKER_STUB/status"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  called "rm conduit-demo"
  grep -q "^run -d --name conduit-demo --network container:conduit-router .* $LYRICAL_IMAGE join\$" "$DOCKER_STUB/calls"
}

@test "a running standalone demo from an earlier version stops the container path" {
  no_ros
  echo "true $LYRICAL_IMAGE bridge" > "$DOCKER_STUB/container"
  echo "running 0" > "$DOCKER_STUB/status"
  run main --demo --no-qr
  [ "$status" -eq 1 ]
  has "from an earlier version of this script"
  has "docker stop -t 30 conduit-demo"
  not_called '^run \|^rm '
}

@test "a demo running on the router's graph is reused" {
  no_ros
  echo "$ROUTER_IMAGE" > "$DOCKER_STUB/images"
  echo "true $ROUTER_IMAGE bridge" > "$(router_dir)/container"
  echo "running 0" > "$(router_dir)/status"
  printf '%s\n' '7447 0.0.0.0:7447' '7449 0.0.0.0:7449' > "$(router_dir)/ports"
  echo "Started Zenoh router with id 0123456789abcdef" > "$(router_dir)/logs"
  echo "true $LYRICAL_IMAGE container:id-conduit-router" > "$DOCKER_STUB/container"
  echo "running 0" > "$DOCKER_STUB/status"
  printf '%s\n' RMW_IMPLEMENTATION=rmw_zenoh_cpp ROS_DOMAIN_ID=0 > "$DOCKER_STUB/env"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  not_called '^run '
  not_called '^rm '
  has "The demo robots are already running on the router's graph"
  has "Add robot"
}

@test "CONDUIT_DEMO_IMAGE overrides the image, which is not pulled when present" {
  no_ros
  export CONDUIT_DEMO_IMAGE=conduit-demo:lyrical-dev
  echo conduit-demo:lyrical-dev > "$DOCKER_STUB/images"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  grep -q "^run -d --name conduit-demo .* conduit-demo:lyrical-dev join\$" "$DOCKER_STUB/calls"
  not_called '^pull conduit-demo'
}

@test "/opt/ros with one distribution is sourced and paired natively" {
  unset ROS_DISTRO
  ros_setup jazzy
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "https://conduit.direct/pair#v=1&transport=zenoh&distro=jazzy&domain=123&host=192.168.1.85&port=7447&checkin=192.168.1.85%3A7449&token="
  has "Connected to iPhone."
  lacks "Which ROS 2"
  grep -q " $JAZZY_IMAGE join\$" "$DOCKER_STUB/calls"
}

@test "/opt/ros with two distributions asks which" {
  unset ROS_DISTRO
  ros_setup jazzy
  ros_setup kilted
  echo 1 > "$PAIR_TTY"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "Which ROS 2"
  has "1) jazzy"
  has "2) kilted"
  has "&distro=jazzy&"
}

@test "the native path starts the demo in join mode with this PC's RMW and domain" {
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  called "run -d --name conduit-demo --network host -e RMW_IMPLEMENTATION=rmw_zenoh_cpp -e ROS_DOMAIN_ID=123 -e $ZENOH_CLIENT $JAZZY_IMAGE join"
  # The flag is the answer: no question at all.
  lacks "[y/N]"
  lacks "[Y/n]"
  # The phone pairs with this PC, as without --demo.
  has "https://conduit.direct/pair#v=1&transport=zenoh&distro=jazzy&domain=123&host=192.168.1.85&port=7447&checkin=192.168.1.85%3A7449&token="
  has "iPhone checked in from 192.168.1.50."
  has "Connected to iPhone."
  has "Add robot"
  has "docker stop -t 30 conduit-demo"
  # The demo starts before the QR code.
  output="${output%%https://conduit.direct/pair#*}"
  has "demo robots"
}

@test "the native path passes CycloneDDS's configuration to the demo" {
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  echo '<CycloneDDS/>' > "$BATS_TEST_TMPDIR/cyclone.xml"
  export CYCLONEDDS_URI="file://$BATS_TEST_TMPDIR/cyclone.xml"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  called "run -d --name conduit-demo --network host -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp -e ROS_DOMAIN_ID=123 -e CYCLONEDDS_URI=file://$BATS_TEST_TMPDIR/cyclone.xml -v $BATS_TEST_TMPDIR/cyclone.xml:$BATS_TEST_TMPDIR/cyclone.xml:ro $JAZZY_IMAGE join"
}

@test "the native path runs Fast DDS as rmw_fastrtps_cpp, over UDP only" {
  export RMW_IMPLEMENTATION=rmw_fastrtps_dynamic_cpp
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  called "run -d --name conduit-demo --network host -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp -e ROS_DOMAIN_ID=123 -e FASTDDS_BUILTIN_TRANSPORTS=UDPv4 $JAZZY_IMAGE join"
}

@test "the native path with no RMW set runs the demo on Fast DDS over UDP only" {
  unset RMW_IMPLEMENTATION
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  called "run -d --name conduit-demo --network host -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp -e ROS_DOMAIN_ID=123 -e FASTDDS_BUILTIN_TRANSPORTS=UDPv4 $JAZZY_IMAGE join"
}

@test "only Fast DDS limits the demo's transports" {
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  grep -q "^run .* join\$" "$DOCKER_STUB/calls"
  not_called FASTDDS_BUILTIN_TRANSPORTS
  rm -f "$DOCKER_STUB/calls" "$DOCKER_STUB/container"
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  grep -q "^run .* join\$" "$DOCKER_STUB/calls"
  not_called FASTDDS_BUILTIN_TRANSPORTS
}

@test "a conflict logged as the container exits is listed in full" {
  echo 3 > "$DOCKER_STUB/join_exit"
  printf '%s\n' 'CONFLICT /map' \
    'check_conflicts: this graph already uses 1 name(s) of the Conduit Robots demo' > "$DOCKER_STUB/join_log"
  # The first log read happens before the name check has printed anything.
  echo "starting" > "$DOCKER_STUB/logs_first"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "already uses these names of the demo robots:"
  has "  /map"
  has "The demo robots were not added"
}

@test "a conflict skips the demo and pairing continues" {
  echo 3 > "$DOCKER_STUB/join_exit"
  printf '%s\n' 'CONFLICT /map' 'CONFLICT /odom' \
    'check_conflicts: this graph already uses 2 name(s) of the Conduit Robots demo' > "$DOCKER_STUB/join_log"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "  /map"
  has "  /odom"
  has "The demo robots were not added"
  called "rm conduit-demo"
  has "Connected to iPhone."
  lacks "Add robot"
}

@test "a joined demo whose name check never ends is removed and pairing continues" {
  touch "$DOCKER_STUB/never_ready"
  PAIR_DEMO_START_SECONDS=2 run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "did not finish within 2 seconds"
  has "The demo robots were not added"
  called "rm -f conduit-demo"
  [ ! -e "$DOCKER_STUB/container" ]
  lacks "Add robot"
  has "Connected to iPhone."
}

@test "a join docker run that does not finish is force-removed and pairing continues" {
  touch "$DOCKER_STUB/run_hang"
  PAIR_DOCKER_RUN_SECONDS=2 run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "did not finish within 2 seconds"
  has "The demo robots were not added"
  called "rm -f conduit-demo"
  [ ! -e "$DOCKER_STUB/container" ]
  has "Connected to iPhone."
}

@test "a demo that cannot join the graph is skipped and pairing continues" {
  echo 1 > "$DOCKER_STUB/join_exit"
  echo 'check_conflicts: cannot join the ROS 2 graph: no router' > "$DOCKER_STUB/join_log"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "cannot join the ROS 2 graph: no router"
  has "The demo robots were not added"
  has "Connected to iPhone."
}

@test "the native path without Docker pairs without the demo" {
  echo denied > "$DOCKER_STUB/info"
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "docker group"
  has "The demo robots were not added"
  has "Connected to iPhone."
}

# joined_demo DOMAIN: a joined demo (Jazzy image, Zenoh) runs on domain DOMAIN.
joined_demo() {
  echo "true $JAZZY_IMAGE host" > "$DOCKER_STUB/container"
  echo "running 0" > "$DOCKER_STUB/status"
  printf '%s\n' RMW_IMPLEMENTATION=rmw_zenoh_cpp "ROS_DOMAIN_ID=$1" > "$DOCKER_STUB/env"
}

@test "a joined demo's next steps say to stop it before starting a robot here" {
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "Connected to iPhone."
  has "checked this PC's ROS 2 names once, when it started"
  has "Stop the demo (docker stop -t 30 conduit-demo) before you start your own robot on this PC."
  # Printed once, by the next steps.
  [ "$(grep -c 'docker stop -t 30 conduit-demo' <<< "$output")" -eq 2 ]
}

@test "the container path's next steps do not ask to stop the demo first" {
  no_ros
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "docker stop -t 30 conduit-demo && docker stop conduit-router"
  lacks "before you start your own robot"
}

@test "a joined demo left running when no data arrives (exit 2) gets the stop hint" {
  stub_ros2 '/conduit/conduit_node' 'frame_id: map'
  run main --demo --no-qr
  [ "$status" -eq 2 ]
  lacks "Add robot"
  has "The demo keeps running (container conduit-demo). To stop it: docker stop -t 30 conduit-demo"
}

@test "a demo left running when the listener goes away (exit 2) gets the stop hint" {
  no_ros
  cat > "$STUBS/python3" << 'STUB'
#!/usr/bin/env bash
echo "PORT=$5"
STUB
  run main --demo --no-qr
  [ "$status" -eq 2 ]
  lacks "Add robot"
  has "The demo keeps running (container conduit-demo). To stop it: docker stop -t 30 conduit-demo"
}

# sigint_trappable: 0 when a shell here can trap SIGINT. One started with
# SIGINT ignored (bats run in the background) cannot, so Ctrl-C never reaches
# the script's trap.
sigint_trappable() {
  local status=0
  (
    trap 'exit 7' INT
    sh -c 'kill -INT $PPID'
    sleep 1
  ) || status=$?
  [ "$status" -eq 7 ]
}

@test "a demo left running at Ctrl-C (exit 130) gets the stop hint" {
  if ! sigint_trappable; then skip "SIGINT is ignored in this shell (bats run in the background)"; fi
  no_ros
  # The listener reports its port, then the user presses Ctrl-C. If SIGINT
  # cannot reach the script, the listener ends and the run exits 2 instead.
  cat > "$STUBS/python3" << 'STUB'
#!/usr/bin/env bash
echo "PORT=$5"
kill -INT "$PPID"
exec sleep 5 > /dev/null 2>&1
STUB
  run main --demo --no-qr
  [ "$status" -eq 130 ]
  lacks "Add robot"
  has "The demo keeps running (container conduit-demo). To stop it: docker stop -t 30 conduit-demo"
}

@test "no stop hint when the demo this run started was removed" {
  echo 3 > "$DOCKER_STUB/join_exit"
  echo 'CONFLICT /map' > "$DOCKER_STUB/join_log"
  stub_ros2 '/conduit/conduit_node' 'frame_id: map'
  run main --demo --no-qr
  [ "$status" -eq 2 ]
  lacks "To stop it"
}

@test "a running joined demo is reused on the native path" {
  joined_demo 123
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  not_called '^run '
  not_called '^rm '
  has "already running"
  has "Connected to iPhone."
  has "Add robot"
}

@test "a joined demo on another domain is not reused" {
  joined_demo 0
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  not_called '^run '
  not_called '^rm '
  has "docker stop -t 30 conduit-demo"
  has "The demo robots were not added"
  lacks "Add robot"
  has "Connected to iPhone."
}

@test "Humble skips the demo" {
  export ROS_DISTRO=humble
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  has "Humble"
  not_called '^run '
  has "Connected to iPhone."
}

@test "Rolling uses the Lyrical image" {
  export ROS_DISTRO=rolling
  run main --demo --no-qr
  [ "$status" -eq 0 ]
  grep -q " $LYRICAL_IMAGE join\$" "$DOCKER_STUB/calls"
  has "&distro=rolling&"
}
