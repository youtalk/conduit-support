# Shared bats helpers: source the script without running main and build a
# fixture root that looks like a supported native Ubuntu + ROS 2 host.

SCRIPT="${BATS_TEST_DIRNAME}/../../pair/pair.sh"

load_script() {
  export CONDUIT_PAIR_SOURCED=1
  # shellcheck disable=SC1090
  source "$SCRIPT"
}

make_fixture() {
  export CONDUIT_PAIR_ROOT="$BATS_TEST_TMPDIR/root"
  rm -rf "$CONDUIT_PAIR_ROOT"
  mkdir -p "$CONDUIT_PAIR_ROOT/etc" "$CONDUIT_PAIR_ROOT/proc/1" \
    "$CONDUIT_PAIR_ROOT/run" "$CONDUIT_PAIR_ROOT/opt/ros/jazzy"
  echo 'ID=ubuntu' > "$CONDUIT_PAIR_ROOT/etc/os-release"
  echo 'Linux version 6.8.0 (buildd@ubuntu)' > "$CONDUIT_PAIR_ROOT/proc/version"
  echo '0::/init.scope' > "$CONDUIT_PAIR_ROOT/proc/1/cgroup"
  touch "$CONDUIT_PAIR_ROOT/opt/ros/jazzy/setup.bash"
  export PAIR_UNAME=Linux
  unset WSL_DISTRO_NAME RMW_IMPLEMENTATION ROS_DOMAIN_ID
  unset ROS_LOCALHOST_ONLY ROS_AUTOMATIC_DISCOVERY_RANGE
  export ROS_DISTRO=jazzy
  # A sourced ROS 2 puts ros2 on PATH; tests that need its output stub it again.
  mkdir -p "$BATS_TEST_TMPDIR/rosbin"
  printf '#!/usr/bin/env bash\n' > "$BATS_TEST_TMPDIR/rosbin/ros2"
  chmod +x "$BATS_TEST_TMPDIR/rosbin/ros2"
  PATH="$BATS_TEST_TMPDIR/rosbin:$PATH"
  export PATH
}
