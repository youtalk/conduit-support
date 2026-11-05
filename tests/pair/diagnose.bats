#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup() {
  load_script
  make_fixture
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  PATH="$STUBS:$PATH"
  export PATH
  PAIR_DOMAIN=123
  PAIR_DISTRO=jazzy
  PAIR_CHECKIN_PORT=7449
  PAIR_VIA=lan
}

ufw_on() {
  mkdir -p "$CONDUIT_PAIR_ROOT/etc/ufw"
  printf 'IPV6=yes\nENABLED=yes\n' > "$CONDUIT_PAIR_ROOT/etc/ufw/ufw.conf"
}

# stub_ros2 NODES ECHO: fake `ros2 node list` / `ros2 topic echo` output.
# ROS2_NO_SPIN_TIME=1 makes `ros2 node list --help` omit --spin-time.
stub_ros2() {
  printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/nodes.out"
  printf '%s\n' "$2" > "$BATS_TEST_TMPDIR/echo.out"
  cat > "$STUBS/ros2" << STUB
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/ros2.log"
case "\$*" in
  "node list --help") [[ "\${ROS2_NO_SPIN_TIME:-0}" == 1 ]] || echo "  --spin-time SPIN_TIME" ;;
  "node list"*) cat "$BATS_TEST_TMPDIR/nodes.out" ;;
  "topic echo"*) cat "$BATS_TEST_TMPDIR/echo.out"; sleep "\${ROS2_ECHO_SLEEP:-0}" ;;
  "daemon stop") ;;
esac
STUB
  chmod +x "$STUBS/ros2"
}

@test "ufw state" {
  run ufw_enabled
  [ "$status" -ne 0 ]
  mkdir -p "$CONDUIT_PAIR_ROOT/etc/ufw"
  echo 'ENABLED=no' > "$CONDUIT_PAIR_ROOT/etc/ufw/ufw.conf"
  run ufw_enabled
  [ "$status" -ne 0 ]
  ufw_on
  run ufw_enabled
  [ "$status" -eq 0 ]
}

@test "no_checkin causes with ufw on (Zenoh)" {
  ufw_on
  PAIR_RMW=zenoh
  run causes no_checkin
  [ "$status" -eq 0 ]
  [[ "$output" == *"sudo ufw allow 7449/tcp"* ]]
  [[ "$output" == *"sudo ufw allow 7447/tcp"* ]]
  [[ "$output" != *"/udp"* ]]
  [[ "$output" == *"same Wi-Fi"* ]]
  [[ "$output" == *"isolat"* ]]
  [[ "$output" == *"Local Network"* ]]
}

@test "no_checkin over Tailscale asks for the tailnet" {
  PAIR_RMW=zenoh PAIR_VIA=tailscale
  run causes no_checkin
  [[ "$output" == *"Tailscale app"* ]]
  [[ "$output" == *"tailnet"* ]]
  [[ "$output" != *"same Wi-Fi"* ]]
}

@test "ufw lines come first and only when ufw is on" {
  PAIR_RMW=zenoh
  run causes no_checkin
  [[ "$output" != *"sudo ufw"* ]]
  ufw_on
  run causes no_checkin
  ufw_line=$(grep -n 'sudo ufw allow' <<< "$output" | head -n1 | cut -d: -f1)
  wifi_line=$(grep -n 'same Wi-Fi' <<< "$output" | head -n1 | cut -d: -f1)
  ((ufw_line < wifi_line))
}

@test "no_node causes" {
  ufw_on
  PAIR_RMW=zenoh
  run causes no_node
  [[ "$output" == *"Did you tap Start"* ]]
  [[ "$output" == *"ros2 run rmw_zenoh_cpp rmw_zenohd"* ]]
  [[ "$output" == *"sudo ufw allow 7447/tcp"* ]]
  [[ "$output" != *"7449/tcp"* ]]
}

@test "no_data causes for DDS (domain 123)" {
  ufw_on
  PAIR_RMW=cyclonedds
  run causes no_data
  [[ "$output" == *"sudo ufw allow 38150:38399/udp"* ]]
  [[ "$output" != *"7447/tcp"* ]]
  [[ "$output" == *"export"* ]]
  [[ "$output" != *"Fast DDS"* ]]
}

@test "no_data causes for Fast DDS add the Fast DDS note" {
  PAIR_RMW=fastdds
  run causes no_data
  [[ "$output" == *"Fast DDS"* ]]
  [[ "$output" == *"rmw_cyclonedds_cpp"* ]]
}

@test "DDS port range for domain 0" {
  ufw_on
  PAIR_RMW=cyclonedds PAIR_DOMAIN=0
  run causes no_node
  [[ "$output" == *"sudo ufw allow 7400:7649/udp"* ]]
}

@test "wait_for_node finds the node" {
  stub_ros2 $'/other\n/conduit/conduit_node' ''
  run wait_for_node conduit_node conduit 10
  [ "$status" -eq 0 ]
  [ "$(grep -c 'Tap Start in Conduit.' <<< "$output")" -eq 1 ]
  grep -q -- 'node list --no-daemon --spin-time 3' "$BATS_TEST_TMPDIR/ros2.log"
}

@test "wait_for_node with an empty namespace" {
  stub_ros2 '/conduit_node' ''
  run wait_for_node conduit_node "" 10
  [ "$status" -eq 0 ]
}

@test "wait_for_node times out" {
  stub_ros2 '/conduit/other_node' ''
  run wait_for_node conduit_node conduit 1
  [ "$status" -eq 1 ]
  [ "$(grep -c 'Tap Start in Conduit.' <<< "$output")" -eq 1 ]
}

@test "wait_for_node without --spin-time stops the daemon" {
  stub_ros2 '/conduit/conduit_node' ''
  ROS2_NO_SPIN_TIME=1 run wait_for_node conduit_node conduit 10
  [ "$status" -eq 0 ]
  grep -qx 'daemon stop' "$BATS_TEST_TMPDIR/ros2.log"
  grep -qx 'node list' "$BATS_TEST_TMPDIR/ros2.log"
  ! grep -q -- '--spin-time 3' "$BATS_TEST_TMPDIR/ros2.log"
}

@test "wait_for_data sees conduit_base_link" {
  stub_ros2 '' $'transforms:\n- header:\n    frame_id: conduit_base_link'
  run wait_for_data 5
  [ "$status" -eq 0 ]
  grep -q -- 'topic echo --qos-durability transient_local --qos-reliability reliable /tf_static tf2_msgs/msg/TFMessage' "$BATS_TEST_TMPDIR/ros2.log"
}

@test "wait_for_data fails without the frame" {
  stub_ros2 '' 'frame_id: map'
  run wait_for_data 5
  [ "$status" -ne 0 ]
}

@test "wait_for_data times out" {
  stub_ros2 '' ''
  ROS2_ECHO_SLEEP=10 run wait_for_data 1
  [ "$status" -ne 0 ]
}

@test "check-in values may contain spaces" {
  parse_checkin 'CHECKIN phone_ip=192.168.1.50 node=my node namespace=my ns device=My iPhone app_version=3.0 beta'
  [ "$PAIR_PHONE_IP" = 192.168.1.50 ]
  [ "$PAIR_NODE" = "my node" ]
  [ "$PAIR_NAMESPACE" = "my ns" ]
  [ "$PAIR_DEVICE" = "My iPhone" ]
}

@test "check-in with an empty namespace" {
  parse_checkin 'CHECKIN phone_ip=192.168.1.50 node=conduit_node namespace= device=iPhone app_version=3.0.0'
  [ "$PAIR_NODE" = conduit_node ]
  [ -z "$PAIR_NAMESPACE" ]
  [ "$PAIR_DEVICE" = iPhone ]
}

@test "malformed check-in is rejected" {
  run parse_checkin 'CHECKIN node=conduit_node'
  [ "$status" -eq 1 ]
  run parse_checkin 'garbage'
  [ "$status" -eq 1 ]
}

@test "wait_checkin returns 1 when the listener is gone" {
  exec {PAIR_CHECKIN_FD}< <(echo 'HINT other')
  run wait_checkin
  [ "$status" -eq 1 ]
}

@test "wait_checkin skips junk, shows the hint and parses spaces" {
  PAIR_RMW=zenoh
  exec {PAIR_CHECKIN_FD}< <(printf '%s\n' 'junk' 'HINT no_checkin' \
    'CHECKIN phone_ip=192.168.1.50 node=conduit_node namespace=conduit device=My iPhone app_version=3.0 beta')
  wait_checkin > "$BATS_TEST_TMPDIR/out"
  grep -q 'Local Network' "$BATS_TEST_TMPDIR/out"
  [ "$PAIR_PHONE_IP" = 192.168.1.50 ]
  [ "$PAIR_DEVICE" = "My iPhone" ]
  [ "$PAIR_NAMESPACE" = conduit ]
}
