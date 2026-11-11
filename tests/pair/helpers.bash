# Shared bats helpers: source the script without running main and build a
# fixture root that looks like a supported native Ubuntu + ROS 2 host.

SCRIPT="${BATS_TEST_DIRNAME}/../../pair/pair.sh"

load_script() {
  export CONDUIT_PAIR_SOURCED=1
  # shellcheck disable=SC1090
  source "$SCRIPT"
}

# Assertions that fail a test from anywhere in its body: bats misses a failing
# `! cmd` there, and a failing `[[ ]]` too under bash 3.2 (macOS).
has() { [[ "$output" == *"$1"* ]]; }
lacks() { [[ "$output" != *"$1"* ]]; }

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
  # The test machine's own Tailscale must not answer; a test that needs one
  # stubs it again.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/rosbin/tailscale"
  chmod +x "$BATS_TEST_TMPDIR/rosbin/tailscale"
  PATH="$BATS_TEST_TMPDIR/rosbin:$PATH"
  export PATH
}

# stub_ip ROUTE ADDR: fake `ip route get` / `ip addr show` output.
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

# stub_macos_net IFACE ADDR: fake macOS `route -n get default` (default route
# on IFACE) and `ipconfig getifaddr IFACE` (ADDR).
stub_macos_net() {
  cat > "$STUBS/route" << STUB
#!/usr/bin/env bash
[[ "\$*" == "-n get default" ]] || exit 1
printf '   route to: default\ndestination: default\n       mask: default\n    gateway: 192.168.1.1\n  interface: %s\n' "$1"
STUB
  cat > "$STUBS/ipconfig" << STUB
#!/usr/bin/env bash
[[ "\$*" == "getifaddr $1" ]] || exit 1
echo "$2"
STUB
  chmod +x "$STUBS/route" "$STUBS/ipconfig"
}

# stub_docker: a fake docker CLI (call stub_open after it for macOS `open`).
# Its state is in $DOCKER_STUB:
#   info       ok, down (no daemon) or denied (the daemon refuses this user)
#   images     the image references present, one per line (docker pull adds)
#   container  "<running> <image> <network mode>" of the one container, if any
#   status     "<status> <exit code>" of that container
#   env        its environment, NAME=VALUE lines (docker run -e adds)
#   ports      "<container port> <host address>:<host port>" lines (docker port)
#   logs       its log
#   join_exit  how `docker run ... join` ends: 0 (no conflicts), or that exit
#              status with join_log as the log
#   run_error  when present, `docker run` fails with this message
#   crash_log  when present, a standalone container exits at once with this log
#   calls      every call, one line each
stub_docker() {
  export DOCKER_STUB="$BATS_TEST_TMPDIR/docker"
  mkdir -p "$DOCKER_STUB"
  echo ok > "$DOCKER_STUB/info"
  : > "$DOCKER_STUB/images"
  echo 0 > "$DOCKER_STUB/join_exit"
  cat > "$STUBS/docker" << 'STUB'
#!/usr/bin/env bash
d="$DOCKER_STUB"
printf '%s\n' "$*" >> "$d/calls"
case "$1" in
  info)
    case "$(cat "$d/info")" in
      ok) echo "Server Version: 29.0.0" ;;
      denied)
        echo "permission denied while trying to connect to the docker API at unix:///var/run/docker.sock" >&2
        exit 1
        ;;
      *)
        echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" >&2
        exit 1
        ;;
    esac
    ;;
  image) grep -qxF -- "$3" "$d/images" ;;
  pull)
    echo "$2" >> "$d/images"
    echo "Status: Downloaded newer image for $2"
    ;;
  inspect)
    if [ ! -e "$d/container" ]; then
      echo "Error: No such object: $4" >&2
      exit 1
    fi
    case "$3" in
      *State.Status*) cat "$d/status" ;;
      *Config.Env*) cat "$d/env" 2> /dev/null ;;
      *) cat "$d/container" ;;
    esac
    ;;
  port) awk -v p="${3%/tcp}" '$1 == p { print $2 }' "$d/ports" ;;
  logs) cat "$d/logs" 2> /dev/null ;;
  rm) rm -f "$d/container" "$d/status" "$d/ports" "$d/logs" "$d/env" ;;
  exec)
    shift 3
    exec "$@"
    ;;
  run)
    shift
    net=default
    : > "$d/ports"
    : > "$d/env"
    while [ $# -gt 2 ]; do
      case "$1" in
        -p) echo "${2#*:} 0.0.0.0:${2%%:*}" >> "$d/ports"; shift ;;
        --network) net="$2"; shift ;;
        -e) echo "$2" >> "$d/env"; shift ;;
        --name | -v) shift ;;
      esac
      shift
    done
    if [ -e "$d/run_error" ]; then
      cat "$d/run_error" >&2
      exit 125
    fi
    echo "true $1 $net" > "$d/container"
    echo "running 0" > "$d/status"
    if [ "$2" != join ] && [ -e "$d/crash_log" ]; then
      echo "false $1 $net" > "$d/container"
      echo "exited 1" > "$d/status"
      cat "$d/crash_log" > "$d/logs"
    elif [ "$2" != join ]; then
      echo "Started Zenoh router with id 0123456789abcdef" > "$d/logs"
    elif [ "$(cat "$d/join_exit")" = 0 ]; then
      echo "check_conflicts: no conflicts (12 topics, 30 services, 0 actions, 4 frames)" > "$d/logs"
    else
      echo "false $1 $net" > "$d/container"
      echo "exited $(cat "$d/join_exit")" > "$d/status"
      cat "$d/join_log" > "$d/logs"
    fi
    echo 0123456789abcdef
    ;;
esac
STUB
  chmod +x "$STUBS/docker"
}

# called LINE: the fake docker got exactly LINE. not_called PATTERN: no call
# matched the grep PATTERN.
called() { grep -qxF -- "$1" "$DOCKER_STUB/calls"; }
not_called() { ! grep -q -- "$1" "$DOCKER_STUB/calls" 2> /dev/null; }

# stub_open: fake macOS `open`; `open -a Docker` starts the fake Docker daemon.
stub_open() {
  cat > "$STUBS/open" << 'STUB'
#!/usr/bin/env bash
printf 'open %s\n' "$*" >> "$DOCKER_STUB/calls"
[ "$*" != "-a Docker" ] || echo ok > "$DOCKER_STUB/info"
STUB
  chmod +x "$STUBS/open"
}
