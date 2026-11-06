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
  [[ "$output" == *"Ubuntu, RHEL and Fedora"* ]]
  [[ "$output" == *"other systems are planned"* ]]
}

@test "unsupported Linux distributions" {
  local release
  for release in 'ID=debian' $'ID=linuxmint\nID_LIKE="ubuntu debian"' 'ID=arch' $'ID=opensuse-tumbleweed\nID_LIKE="opensuse suse"'; do
    printf '%s\n' "$release" > "$CONDUIT_PAIR_ROOT/etc/os-release"
    run check_environment
    [ "$status" -eq 1 ]
    [[ "$output" == *"Ubuntu, RHEL and Fedora"* ]]
    [[ "$output" == *"other systems are planned"* ]]
  done
}

@test "no os-release" {
  rm "$CONDUIT_PAIR_ROOT/etc/os-release"
  run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"other systems are planned"* ]]
}

@test "Ubuntu is ubuntu" {
  check_platform
  [ "$PAIR_OS" = ubuntu ]
}

@test "RHEL, Fedora and RHEL rebuilds are rhel" {
  local release
  for release in 'ID="rhel"' 'ID=fedora' $'ID="rocky"\nID_LIKE="rhel centos fedora"' \
    $'ID="almalinux"\nID_LIKE="rhel centos fedora"' $'ID="centos"\nID_LIKE="rhel fedora"'; do
    printf '%s\n' "$release" > "$CONDUIT_PAIR_ROOT/etc/os-release"
    unset PAIR_OS
    check_platform
    [ "$PAIR_OS" = rhel ]
    check_environment
  done
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

@test "PAIR_ALLOW_CONTAINER=1 lets the CI smoke tests run in a container" {
  touch "$CONDUIT_PAIR_ROOT/.dockerenv"
  PAIR_ALLOW_CONTAINER=1 check_environment
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

@test "ROS 2 not sourced, zsh user" {
  unset ROS_DISTRO
  touch "$CONDUIT_PAIR_ROOT/opt/ros/jazzy/setup.zsh"
  SHELL=/usr/bin/zsh run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"source /opt/ros/jazzy/setup.zsh"* ]]
}

@test "ROS 2 not sourced, zsh user without setup.zsh" {
  unset ROS_DISTRO
  SHELL=/usr/bin/zsh run check_environment
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

@test "choose accepts leading zeros" {
  export PAIR_TTY="$BATS_TEST_TMPDIR/tty"
  echo 08 > "$PAIR_TTY"; run --separate-stderr choose "which?" 1 a b c d e f g h i
  [ "$status" -eq 0 ]
  [ "$output" = 8 ]
  echo 09 > "$PAIR_TTY"; run --separate-stderr choose "which?" 1 a b c
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
}

@test "ROS_DISTRO set but ros2 missing" {
  rm "$BATS_TEST_TMPDIR/rosbin/ros2"
  run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"source /opt/ros/jazzy/setup.bash"* ]]
}

@test "ROS_LOCALHOST_ONLY=1 stops DDS on Humble" {
  local rmw
  for rmw in rmw_cyclonedds_cpp rmw_fastrtps_cpp; do
    ROS_DISTRO=humble RMW_IMPLEMENTATION=$rmw ROS_LOCALHOST_ONLY=1 run check_environment
    [ "$status" -eq 1 ]
    [[ "$output" == *"discovery is limited to this PC"* ]]
    [[ "$output" == *"  unset ROS_LOCALHOST_ONLY"* ]]
  done
}

@test "ROS_LOCALHOST_ONLY=1 stops Fast DDS on Jazzy" {
  ROS_LOCALHOST_ONLY=1 run check_environment
  [ "$status" -eq 1 ]
  [[ "$output" == *"  unset ROS_LOCALHOST_ONLY"* ]]
}

@test "ROS_LOCALHOST_ONLY=1 keeps CycloneDDS peers on Jazzy and is gone from Kilted" {
  # Jazzy maps it to the LOCALHOST range, which keeps the CYCLONEDDS_URI peers;
  # Kilted and later ignore it.
  RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ROS_LOCALHOST_ONLY=1 check_environment
  ROS_DISTRO=kilted ROS_LOCALHOST_ONLY=1 check_environment
}

@test "ROS_AUTOMATIC_DISCOVERY_RANGE=OFF stops DDS" {
  local rmw
  for rmw in rmw_cyclonedds_cpp rmw_fastrtps_cpp; do
    RMW_IMPLEMENTATION=$rmw ROS_AUTOMATIC_DISCOVERY_RANGE=OFF run check_environment
    [ "$status" -eq 1 ]
    [[ "$output" == *"discovery is limited to this PC"* ]]
    [[ "$output" == *"  export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET"* ]]
  done
}

@test "LOCALHOST range keeps static peers, Humble ignores the range, Zenoh is unaffected" {
  RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST check_environment
  ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST check_environment
  ROS_DISTRO=humble ROS_AUTOMATIC_DISCOVERY_RANGE=OFF check_environment
  RMW_IMPLEMENTATION=rmw_zenoh_cpp ROS_AUTOMATIC_DISCOVERY_RANGE=OFF ROS_LOCALHOST_ONLY=1 check_environment
  [ "$PAIR_RMW" = zenoh ]
}
