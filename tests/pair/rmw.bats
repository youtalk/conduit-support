#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup() {
  load_script
  make_fixture
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CYCLONEDDS_URI ROS_STATIC_PEERS FASTRTPS_DEFAULT_PROFILES_FILE
  PAIR_DOMAIN=123
}

@test "CycloneDDS peer file and export" {
  PAIR_RMW=cyclonedds PAIR_DISTRO=jazzy
  run --separate-stderr host_peer_config 192.168.1.50
  [ "$status" -eq 0 ]
  f="$HOME/.config/conduit/cyclonedds-peer.xml"
  grep -q '<CycloneDDS><Domain id="any"><Discovery><Peers><Peer address="192.168.1.50"/></Peers></Discovery></Domain></CycloneDDS>' "$f"
  [ "$output" = "export CYCLONEDDS_URI='file://$f'" ]
}

@test "existing CYCLONEDDS_URI is kept" {
  PAIR_RMW=cyclonedds PAIR_DISTRO=jazzy
  CYCLONEDDS_URI=file:///etc/my.xml run --separate-stderr host_peer_config 192.168.1.50
  [ "$output" = "export CYCLONEDDS_URI='file:///etc/my.xml,file://$HOME/.config/conduit/cyclonedds-peer.xml'" ]
}

@test "ROS_STATIC_PEERS is set" {
  PAIR_RMW=fastdds PAIR_DISTRO=jazzy
  run --separate-stderr host_peer_config 192.168.1.50
  [ "$output" = "export ROS_STATIC_PEERS='192.168.1.50'" ]
}

@test "ROS_STATIC_PEERS is appended" {
  PAIR_RMW=fastdds PAIR_DISTRO=jazzy
  ROS_STATIC_PEERS=10.0.0.2 run --separate-stderr host_peer_config 192.168.1.50
  [ "$output" = "export ROS_STATIC_PEERS='10.0.0.2;192.168.1.50'" ]
}

@test "Humble Fast DDS profile" {
  PAIR_RMW=fastdds PAIR_DISTRO=humble
  run --separate-stderr host_peer_config 192.168.1.50
  f="$HOME/.config/conduit/fastdds-peer.xml"
  grep -q '192.168.1.50' "$f"
  grep -q '239.255.0.1' "$f"
  grep -q '38150' "$f"
  grep -q 'initialPeersList' "$f"
  [ "$output" = "export FASTRTPS_DEFAULT_PROFILES_FILE='$f'" ]
}

@test "existing Humble profile is not merged" {
  PAIR_RMW=fastdds PAIR_DISTRO=humble
  FASTRTPS_DEFAULT_PROFILES_FILE=/etc/mine.xml run --separate-stderr host_peer_config 192.168.1.50
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"/etc/mine.xml"* ]]
  [[ "$stderr" == *"192.168.1.50"* ]]
  [ ! -e "$HOME/.config/conduit/fastdds-peer.xml" ]
}

@test "Zenoh needs nothing" {
  PAIR_RMW=zenoh PAIR_DISTRO=jazzy
  run host_peer_config 192.168.1.50
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$HOME/.config/conduit" ]
}

@test "Tailscale with DDS prints the switch" {
  PAIR_DISTRO=kilted
  run tailscale_needs_zenoh
  [[ "$output" == *"export RMW_IMPLEMENTATION=rmw_zenoh_cpp"* ]]
  [[ "$output" == *"ros2 run rmw_zenoh_cpp rmw_zenohd"* ]]
  [[ "$output" == *"sudo apt install ros-kilted-rmw-zenoh-cpp"* ]]
}

@test "Fast DDS warning" {
  PAIR_DISTRO=jazzy
  run fastdds_warning
  [[ "$output" == *"sudo apt install ros-jazzy-rmw-cyclonedds-cpp"* ]]
  [[ "$output" == *"  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"* ]]
}

@test "router check" {
  port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
  run zenoh_router_listening "$port"
  [ "$status" -eq 1 ]
  python3 -m http.server "$port" --bind 127.0.0.1 > /dev/null 2>&1 &
  pid=$!
  for _ in $(seq 50); do zenoh_router_listening "$port" && break; sleep 0.1; done
  run zenoh_router_listening "$port"
  kill "$pid"
  [ "$status" -eq 0 ]
}

@test "bashrc block is appended" {
  f="$BATS_TEST_TMPDIR/bashrc"
  echo 'alias a=b' > "$f"
  bashrc_with_block "$f" "export X='1'"
  grep -q 'alias a=b' "$f"
  [ "$(grep -c '# >>> conduit pairing >>>' "$f")" -eq 1 ]
  grep -q "export X='1'" "$f"
}

@test "bashrc block is replaced" {
  f="$BATS_TEST_TMPDIR/bashrc"
  echo 'alias a=b' > "$f"
  bashrc_with_block "$f" "export X='1'"
  bashrc_with_block "$f" "export X='2'"
  echo 'alias c=d' >> "$f"
  bashrc_with_block "$f" "export X='3'"
  [ "$(grep -c '# >>> conduit pairing >>>' "$f")" -eq 1 ]
  [ "$(grep -c '# <<< conduit pairing <<<' "$f")" -eq 1 ]
  grep -q "export X='3'" "$f"
  ! grep -q "X='1'" "$f"
  grep -q 'alias a=b' "$f"
  grep -q 'alias c=d' "$f"
}

@test "single quotes in export values are escaped" {
  PAIR_RMW=fastdds PAIR_DISTRO=jazzy
  ROS_STATIC_PEERS="it's" run --separate-stderr host_peer_config 192.168.1.50
  [ "$output" = "export ROS_STATIC_PEERS='it'\\''s;192.168.1.50'" ]
  eval "$output"
  [ "$ROS_STATIC_PEERS" = "it's;192.168.1.50" ]
}

@test "export_line round-trips quotes and ampersands through eval" {
  [ "$(export_line V "a'&b")" = "export V='a'\\''&b'" ]
  for value in "it's" 'a&b' "a'&b" "'&'" '&&' "file:///tmp/it's & co/peer.xml" "x'\\''y"; do
    line="$(export_line CONDUIT_ROUND_TRIP "$value")"
    unset CONDUIT_ROUND_TRIP
    eval "$line"
    [ "$CONDUIT_ROUND_TRIP" = "$value" ]
  done
}

@test "quote in HOME is escaped in the CycloneDDS export" {
  PAIR_RMW=cyclonedds PAIR_DISTRO=jazzy
  HOME="$BATS_TEST_TMPDIR/o'home"
  mkdir -p "$HOME"
  run --separate-stderr host_peer_config 192.168.1.50
  eval "$output"
  [ "$CYCLONEDDS_URI" = "file://$HOME/.config/conduit/cyclonedds-peer.xml" ]
}

@test "bashrc with a begin marker but no end marker is left untouched" {
  f="$BATS_TEST_TMPDIR/bashrc"
  printf '%s\n' 'alias a=b' '# >>> conduit pairing >>>' "export X='1'" 'alias c=d' > "$f"
  cp "$f" "$BATS_TEST_TMPDIR/before"
  run --separate-stderr bashrc_with_block "$f" "export X='2'"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$f"* ]]
  cmp "$f" "$BATS_TEST_TMPDIR/before"
}

@test "bashrc is left unchanged when the temp file cannot be made" {
  f="$BATS_TEST_TMPDIR/bashrc"
  echo 'alias a=b' > "$f"
  cp "$f" "$BATS_TEST_TMPDIR/before"
  # A failing mktemp (macOS's ignores a TMPDIR that does not exist), called
  # without `run`, which needs mktemp itself.
  mkdir -p "$BATS_TEST_TMPDIR/nomktemp"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/nomktemp/mktemp"
  chmod +x "$BATS_TEST_TMPDIR/nomktemp/mktemp"
  status=0
  PATH="$BATS_TEST_TMPDIR/nomktemp:$PATH" bashrc_with_block "$f" "export X='1'" 2> /dev/null || status=$?
  [ "$status" -eq 1 ]
  cmp "$f" "$BATS_TEST_TMPDIR/before"
}

@test "bashrc that cannot be written returns 1" {
  f="$BATS_TEST_TMPDIR/bashrc"
  mkdir "$f" "$BATS_TEST_TMPDIR/t"
  TMPDIR="$BATS_TEST_TMPDIR/t" run --separate-stderr bashrc_with_block "$f" "export X='1'"
  [ "$status" -eq 1 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/t")" ]
}

@test "peer file that cannot be written prints no export" {
  local rmw
  : > "$HOME/.config"
  for rmw in cyclonedds:jazzy fastdds:humble; do
    PAIR_RMW=${rmw%%:*} PAIR_DISTRO=${rmw##*:}
    run --separate-stderr host_peer_config 192.168.1.50
    [ "$status" -ne 0 ]
    [ -z "$output" ]
  done
}

@test "conduit peer file already in CYCLONEDDS_URI is not added again" {
  PAIR_RMW=cyclonedds PAIR_DISTRO=jazzy
  f="$HOME/.config/conduit/cyclonedds-peer.xml"
  CYCLONEDDS_URI="file:///etc/my.xml,file://$f" run --separate-stderr host_peer_config 192.168.1.50
  [ "$output" = "export CYCLONEDDS_URI='file:///etc/my.xml,file://$f'" ]
}

@test "phone already in ROS_STATIC_PEERS is not added again" {
  PAIR_RMW=fastdds PAIR_DISTRO=jazzy
  ROS_STATIC_PEERS='10.0.0.2;192.168.1.50' run --separate-stderr host_peer_config 192.168.1.50
  [ "$output" = "export ROS_STATIC_PEERS='10.0.0.2;192.168.1.50'" ]
  ROS_STATIC_PEERS='192.168.1.5' run --separate-stderr host_peer_config 192.168.1.50
  [ "$output" = "export ROS_STATIC_PEERS='192.168.1.5;192.168.1.50'" ]
}

@test "install commands use dnf on RHEL and Fedora" {
  PAIR_OS=rhel PAIR_DISTRO=humble
  run fastdds_warning
  [[ "$output" == *"sudo dnf install ros-humble-rmw-cyclonedds-cpp"* ]]
  [[ "$output" != *"apt"* ]]
  run tailscale_needs_zenoh
  [[ "$output" == *"sudo dnf install ros-humble-rmw-zenoh-cpp"* ]]
  [[ "$output" != *"apt"* ]]
}

