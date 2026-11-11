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
  [[ "$output" == *"Ubuntu, RHEL and Fedora only"* ]]
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
  [[ "$output" != *"conduit.direct/pair"* ]]
}

@test "happy path Zenoh" {
  run main --no-qr
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://conduit.direct/pair#v=1&transport=zenoh&distro=jazzy&domain=123&host=192.168.1.85&port=7447&checkin=192.168.1.85%3A7449&token="* ]]
  [[ "$output" == *"Tap Start in Conduit."* ]]
  [[ "$output" == *"Connected to iPhone."* ]]
  [ ! -e "$HOME/.config/conduit" ]
}

@test "Zenoh waits for the router when the user starts it" {
  zenoh_router_listening() {
    [[ -e "$BATS_TEST_TMPDIR/router" ]] && return 0
    touch "$BATS_TEST_TMPDIR/router"
    return 1
  }
  echo n > "$PAIR_TTY"
  run main --no-qr
  [ "$status" -eq 0 ]
  [ "$(grep -c 'ros2 run rmw_zenoh_cpp rmw_zenohd' <<< "$output")" -eq 1 ]
  [[ "$output" == *"Waiting for it on port 7447... (Ctrl+C to quit)"* ]]
  [[ "$output" != *"Started the Zenoh router"* ]]
}

# stub_zenohd BODY: an rmw_zenohd under a fake rmw_zenoh_cpp prefix that runs BODY.
stub_zenohd() {
  local exe="$BATS_TEST_TMPDIR/zenoh/lib/rmw_zenoh_cpp/rmw_zenohd"
  mkdir -p "${exe%/*}"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$exe"
  chmod +x "$exe"
  cat > "$STUBS/ros2" << STUB
#!/usr/bin/env bash
case "\$*" in
  "pkg prefix rmw_zenoh_cpp") echo "$BATS_TEST_TMPDIR/zenoh" ;;
  "node list --help") echo "  --spin-time SPIN_TIME" ;;
  "node list"*) echo /conduit/conduit_node ;;
  "topic echo"*) echo "frame_id: conduit_base_link" ;;
esac
STUB
  chmod +x "$STUBS/ros2"
}

teardown() {
  if [[ -e "$BATS_TEST_TMPDIR/zenohd.pid" ]]; then
    kill "$(cat "$BATS_TEST_TMPDIR/zenohd.pid")" 2> /dev/null || true
  fi
}

@test "Zenoh starts the router in the background by default" {
  zenoh_router_listening() { [[ -e "$BATS_TEST_TMPDIR/router" ]]; }
  stub_zenohd "echo \$\$ > '$BATS_TEST_TMPDIR/zenohd.pid'; echo 'router up'; touch '$BATS_TEST_TMPDIR/router'; exec sleep 30"
  unset XDG_CACHE_HOME
  run main --no-qr
  [ "$status" -eq 0 ]
  [[ "$output" == *"Start it now in the background? [Y/n]"* ]]
  [[ "$output" == *"Started the Zenoh router (PID $(cat "$BATS_TEST_TMPDIR/zenohd.pid"))."* ]]
  [[ "$output" == *"Log:  $HOME/.cache/conduit/rmw_zenohd.log"* ]]
  [[ "$output" == *"Stop: kill $(cat "$BATS_TEST_TMPDIR/zenohd.pid")"* ]]
  [[ "$output" == *"Connected to iPhone."* ]]
  # Still running after the script ended, detached from it.
  kill -0 "$(cat "$BATS_TEST_TMPDIR/zenohd.pid")"
  grep -q 'router up' "$HOME/.cache/conduit/rmw_zenohd.log"
}

@test "a router that does not start reports its log" {
  zenoh_router_listening() { return 1; }
  stub_zenohd "echo 'address already in use' >&2; exit 1"
  run start_zenoh_router 7447
  [ "$status" -eq 1 ]
  [[ "$output" == *"The Zenoh router did not start."* ]]
  [[ "$output" == *"  address already in use"* ]]
}

@test "no rmw_zenohd in the sourced ROS 2" {
  run start_zenoh_router 7447
  [ "$status" -eq 1 ]
  [[ "$output" == *"rmw_zenohd was not found"* ]]
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

@test "bashrc that cannot be written is reported" {
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  mkdir "$HOME/.bashrc"
  echo y > "$PAIR_TTY"
  run main --no-qr
  [ "$status" -eq 0 ]
  [[ "$output" != *"Added to ~/.bashrc"* ]]
  [[ "$output" == *"Could not update ~/.bashrc"* ]]
}

@test "peer file that cannot be written is reported, not exported" {
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  : > "$HOME/.config"
  echo y > "$PAIR_TTY"
  run main --no-qr
  [[ "$output" == *"Could not write $HOME/.config/conduit"* ]]
  [[ "$output" != *"export CYCLONEDDS_URI="* ]]
  [[ "$output" != *"Add this to ~/.bashrc?"* ]]
  [ ! -e "$HOME/.bashrc" ]
  ! grep -q "CYCLONEDDS_URI=file://" "$BATS_TEST_TMPDIR/ros2.log"
}

@test "localhost-only discovery stops before the link" {
  export RMW_IMPLEMENTATION=rmw_fastrtps_cpp ROS_LOCALHOST_ONLY=1
  run main --no-qr
  [ "$status" -eq 1 ]
  [[ "$output" == *"unset ROS_LOCALHOST_ONLY"* ]]
  [[ "$output" != *"conduit.direct/pair"* ]]
}

@test "--no-qr asks to open the link, not to scan" {
  run main --no-qr
  [[ "$output" == *"Open the link on the iPhone"* ]]
  [[ "$output" != *"Scan the QR"* ]]
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
  [[ "$output" != *"conduit.direct/pair"* ]]
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
