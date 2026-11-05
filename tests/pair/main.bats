#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

ROUTE='1.1.1.1 via 192.168.1.1 dev wlp130s0f0 src 192.168.1.85 uid 1000'
LAN_ADDR='3: wlp130s0f0    inet 192.168.1.85/24 scope global wlp130s0f0'
TS_ADDR='10: tailscale0    inet 100.101.102.103/32 scope global tailscale0'
GOOD_CHECKIN='CHECKIN phone_ip=192.168.1.50 node=conduit_node namespace=conduit device=iPhone app_version=3.0.0'

setup() {
  load_script
  make_fixture
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CYCLONEDDS_URI ROS_STATIC_PEERS FASTRTPS_DEFAULT_PROFILES_FILE PAIR_FORCE_VIA
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
}

stub_ip() {
  printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/route.out"
  printf '%s\n' "$2" > "$BATS_TEST_TMPDIR/addr.out"
  cat > "$STUBS/ip" << STUB
#!/usr/bin/env bash
case "\$*" in
  *route*) cat "$BATS_TEST_TMPDIR/route.out" ;;
  *addr*) cat "$BATS_TEST_TMPDIR/addr.out" ;;
esac
STUB
  chmod +x "$STUBS/ip"
}

# stub_listener LINE: python3 stand-in for the check-in listener. It reports
# the port it was asked for, prints LINE, then waits for the script to exit.
stub_listener() {
  printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/checkin.out"
  cat > "$STUBS/python3" << STUB
#!/usr/bin/env bash
echo "\$\$" > "$BATS_TEST_TMPDIR/listener.pid"
echo "PORT=\$5"
cat "$BATS_TEST_TMPDIR/checkin.out"
exec cat > /dev/null
STUB
  chmod +x "$STUBS/python3"
}

# stub_ros2 NODES ECHO: fake `ros2 node list` / `ros2 topic echo`. Records the
# peer variables each call saw.
stub_ros2() {
  printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/nodes.out"
  printf '%s\n' "$2" > "$BATS_TEST_TMPDIR/echo.out"
  cat > "$STUBS/ros2" << STUB
#!/usr/bin/env bash
echo "\$* CYCLONEDDS_URI=\${CYCLONEDDS_URI:-} ROS_STATIC_PEERS=\${ROS_STATIC_PEERS:-}" >> "$BATS_TEST_TMPDIR/ros2.log"
case "\$*" in
  "node list --help") echo "  --spin-time SPIN_TIME" ;;
  "node list"*) cat "$BATS_TEST_TMPDIR/nodes.out" ;;
  "topic echo"*) cat "$BATS_TEST_TMPDIR/echo.out" ;;
esac
STUB
  chmod +x "$STUBS/ros2"
}

@test "--help exits 0" {
  run main --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--tailscale"* ]]
  [[ "$output" == *"--checkin-port"* ]]
  [[ "$output" == *"--link-style"* ]]
  [[ "$output" == *"--no-qr"* ]]
}

@test "unknown flag exits 1" {
  run main --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"--bogus"* ]]
}

@test "bad --link-style and --checkin-port exit 1" {
  run main --link-style ftp
  [ "$status" -eq 1 ]
  run main --checkin-port abc
  [ "$status" -eq 1 ]
  run main --checkin-port
  [ "$status" -eq 1 ]
}

@test "unsupported exits 1" {
  PAIR_UNAME=Darwin run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ubuntu only"* ]]
}

@test "no terminal exits 1 before any prompt" {
  PAIR_TTY="$BATS_TEST_TMPDIR/missing/tty" run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"This script needs a terminal for its questions; run it in an interactive shell."* ]]
  [[ "$output" != *"Which address"* ]]
}

@test "Tailscale with DDS exits 1" {
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  stub_ip "$ROUTE" "$LAN_ADDR"$'\n'"$TS_ADDR"
  run main --tailscale --no-qr
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tailscale works with Zenoh only"* ]]
  [[ "$output" != *"conduit.youtalk.jp/pair"* ]]
}

@test "happy path Zenoh" {
  run main --no-qr
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://conduit.youtalk.jp/pair#v=1&transport=zenoh&distro=jazzy&domain=123&host=192.168.1.85&port=7447&checkin=192.168.1.85%3A7449&token="* ]]
  [[ "$output" == *"Tap Start in Conduit."* ]]
  [[ "$output" == *"Connected to iPhone."* ]]
  [ ! -e "$HOME/.config/conduit" ]
}

@test "Zenoh waits for the router" {
  zenoh_router_listening() {
    [[ -e "$BATS_TEST_TMPDIR/router" ]] && return 0
    touch "$BATS_TEST_TMPDIR/router"
    return 1
  }
  run main --no-qr
  [ "$status" -eq 0 ]
  [ "$(grep -c 'ros2 run rmw_zenoh_cpp rmw_zenohd' <<< "$output")" -eq 1 ]
}

@test "--tailscale and --checkin-port and --link-style custom" {
  stub_ip "$ROUTE" "$LAN_ADDR"$'\n'"$TS_ADDR"
  run main --tailscale --checkin-port 8123 --link-style custom --no-qr
  [ "$status" -eq 0 ]
  [[ "$output" == *"conduit://pair#v=1&transport=zenoh&distro=jazzy&domain=123&host=100.101.102.103&port=7447&checkin=100.101.102.103%3A8123&token="* ]]
}

@test "no data exits 2 with causes" {
  stub_ros2 '/conduit/conduit_node' 'frame_id: map'
  run main --no-qr
  [ "$status" -eq 2 ]
  [[ "$output" != *"Connected to"* ]]
  [[ "$output" == *"no message arrived on /tf_static"* ]]
}

@test "listener exits before a check-in exits 2" {
  cat > "$STUBS/python3" << 'STUB'
#!/usr/bin/env bash
echo "PORT=$5"
STUB
  run main --no-qr
  [ "$status" -eq 2 ]
}

@test "happy path CycloneDDS applies host peers in this process" {
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  echo 'alias a=b' > "$HOME/.bashrc"
  run main --no-qr
  [ "$status" -eq 0 ]
  f="$HOME/.config/conduit/cyclonedds-peer.xml"
  grep -q '192.168.1.50' "$f"
  [[ "$output" == *"export CYCLONEDDS_URI='file://$f'"* ]]
  [[ "$output" == *"ros2 daemon stop"* ]]
  [[ "$output" != *"port=7447"* ]]
  [[ "$output" == *"Connected to iPhone."* ]]
  grep -q "node list .*CYCLONEDDS_URI=file://$f" "$BATS_TEST_TMPDIR/ros2.log"
  grep -q "topic echo .*CYCLONEDDS_URI=file://$f" "$BATS_TEST_TMPDIR/ros2.log"
  # ~/.bashrc is left alone without a y.
  [ "$(cat "$HOME/.bashrc")" = 'alias a=b' ]
}

@test "bashrc block is added on y" {
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  echo y > "$PAIR_TTY"
  run main --no-qr
  [ "$status" -eq 0 ]
  grep -q '# >>> conduit pairing >>>' "$HOME/.bashrc"
  grep -q "export CYCLONEDDS_URI='file://$HOME/.config/conduit/cyclonedds-peer.xml'" "$HOME/.bashrc"
}

@test "optional host peers are only offered" {
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  HOST_PEERS_REQUIRED_CYCLONEDDS=false
  run main --no-qr
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/conduit/cyclonedds-peer.xml" ]
  [[ "$output" == *"[y/N]"* ]]
}

@test "Fast DDS declined exits 1" {
  unset RMW_IMPLEMENTATION
  echo n > "$PAIR_TTY"
  run main --no-qr
  [ "$status" -eq 1 ]
  [[ "$output" == *"CycloneDDS is recommended"* ]]
  [[ "$output" != *"conduit.youtalk.jp/pair"* ]]
}

@test "Fast DDS continues by default with ROS_STATIC_PEERS" {
  unset RMW_IMPLEMENTATION
  run main --no-qr
  [ "$status" -eq 0 ]
  [[ "$output" == *"transport=dds"* ]]
  [[ "$output" == *"export ROS_STATIC_PEERS='192.168.1.50'"* ]]
  grep -q "node list .*ROS_STATIC_PEERS=192.168.1.50" "$BATS_TEST_TMPDIR/ros2.log"
}

@test "check-in listener is stopped on exit" {
  run main --no-qr
  [ "$status" -eq 0 ]
  pid=$(cat "$BATS_TEST_TMPDIR/listener.pid")
  ! kill -0 "$pid" 2> /dev/null
}

@test "real check-in listener end to end" {
  rm "$STUBS/python3"
  port=$(python3 -c 'import socket;s=socket.socket();s.bind(("0.0.0.0",0));print(s.getsockname()[1])')
  out="$BATS_TEST_TMPDIR/main.out"
  (main --no-qr --checkin-port "$port") > "$out" 2>&1 &
  pid=$!
  for _ in $(seq 100); do grep -q 'Waiting for Conduit' "$out" && break; sleep 0.1; done
  token=$(sed -n 's/.*&token=\([^&]*\)&.*/\1/p' "$out")
  reply=$(python3 - "$port" "$token" << 'PY'
import json, socket, sys
req = {"app_version": "3.0 beta", "device": "My iPhone", "namespace": "conduit",
       "node": "conduit_node", "token": sys.argv[2]}
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5) as s:
    s.sendall(json.dumps(req).encode() + b"\n")
    print(s.makefile().readline().strip())
PY
)
  wait "$pid" && status=0 || status=$?
  [ "$reply" = '{"ok":true}' ]
  [ "$status" -eq 0 ]
  grep -q 'My iPhone checked in from 127.0.0.1.' "$out"
  grep -q 'Connected to My iPhone.' "$out"
}
