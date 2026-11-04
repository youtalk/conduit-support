#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup() {
  load_script
  make_fixture
}

@test "not Linux" {
  PAIR_UNAME=Darwin run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ubuntu"* ]]
  [[ "$output" == *"other systems are planned"* ]]
}

@test "not Ubuntu" {
  echo 'ID=fedora' > "$CONDUIT_PAIR_ROOT/etc/os-release"
  run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ubuntu"* ]]
  [[ "$output" == *"other systems are planned"* ]]
}

@test "WSL is detected from /proc/version" {
  echo 'Linux version 5.15 (microsoft-standard-WSL2)' > "$CONDUIT_PAIR_ROOT/proc/version"
  run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"WSL is not supported yet"* ]]
}

@test "WSL is detected from WSL_DISTRO_NAME" {
  WSL_DISTRO_NAME=Ubuntu run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"WSL is not supported yet"* ]]
}

@test "container is detected" {
  touch "$CONDUIT_PAIR_ROOT/.dockerenv"
  run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"containers are not supported yet"* ]]
}

@test "container is detected from .containerenv" {
  touch "$CONDUIT_PAIR_ROOT/run/.containerenv"
  run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"containers are not supported yet"* ]]
}

@test "container is detected from cgroup" {
  local word
  for word in docker containerd kubepods lxc; do
    echo "12:cpu:/$word/abc" > "$CONDUIT_PAIR_ROOT/proc/1/cgroup"
    run check_environment
    [ "$status" -eq 1 ]
    [[ "$output" == *"containers are not supported yet"* ]]
  done
}

@test "ROS 2 missing" {
  rm -rf "$CONDUIT_PAIR_ROOT/opt/ros"
  unset ROS_DISTRO
  run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"https://docs.ros.org/en/lyrical/Get-Started/Installation.html"* ]]
}

@test "ROS 2 not sourced" {
  unset ROS_DISTRO
  run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"source /opt/ros/jazzy/setup.bash"* ]]
}

@test "unsupported distro" {
  ROS_DISTRO=iron run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"iron"* ]]
  [[ "$output" == *"not supported"* ]]
}

@test "unsupported RMW" {
  RMW_IMPLEMENTATION=rmw_connextdds run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"rmw_connextdds"* ]]
  [[ "$output" == *"not supported"* ]]
}

@test "domain out of range" {
  ROS_DOMAIN_ID=300 run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"ROS_DOMAIN_ID"* ]]
}

@test "domain that is not a number" {
  ROS_DOMAIN_ID=abc run check_environment
  [ "$status" -eq 1 ]
}

@test "reads the environment" {
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ROS_DOMAIN_ID=123
  check_environment
  [ "$PAIR_DISTRO" = jazzy ]
  [ "$PAIR_RMW" = cyclonedds ]
  [ "$PAIR_DOMAIN" = 123 ]
}

@test "defaults are fastdds and domain 0" {
  check_environment
  [ "$PAIR_RMW" = fastdds ]
  [ "$PAIR_DOMAIN" = 0 ]
}

@test "RMW names map to transports" {
  RMW_IMPLEMENTATION=rmw_zenoh_cpp check_environment
  [ "$PAIR_RMW" = zenoh ]
  RMW_IMPLEMENTATION=rmw_fastrtps_cpp check_environment
  [ "$PAIR_RMW" = fastdds ]
  RMW_IMPLEMENTATION=rmw_fastrtps_dynamic_cpp check_environment
  [ "$PAIR_RMW" = fastdds ]
}

@test "ask_yes_no honors answers and defaults" {
  export PAIR_TTY="$BATS_TEST_TMPDIR/tty"
  echo y > "$PAIR_TTY"; run ask_yes_no "ok?" n; [ "$status" -eq 0 ]
  echo n > "$PAIR_TTY"; run ask_yes_no "ok?" y; [ "$status" -eq 1 ]
  echo > "$PAIR_TTY";   run ask_yes_no "ok?" y; [ "$status" -eq 0 ]
  echo > "$PAIR_TTY";   run ask_yes_no "ok?" n; [ "$status" -eq 1 ]
}

@test "choose echoes a 1-based index and falls back to the default" {
  export PAIR_TTY="$BATS_TEST_TMPDIR/tty"
  echo 2 > "$PAIR_TTY"; run --separate-stderr choose "which?" 1 a b c
  [ "$output" = 2 ]
  echo > "$PAIR_TTY";   run --separate-stderr choose "which?" 3 a b c
  [ "$output" = 3 ]
  echo 9 > "$PAIR_TTY"; run --separate-stderr choose "which?" 1 a b c
  [ "$output" = 1 ]
}
