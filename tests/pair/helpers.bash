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
#   calls      every call, one line each
# and per container in a directory of its own, `cdir NAME`: $DOCKER_STUB itself
# for conduit-demo, $DOCKER_STUB/c/NAME for any other (conduit-router):
#   container  "<running> <image> <network mode>" of the container, if any
#   status     "<status> <exit code>" of that container
#   env        its environment, NAME=VALUE lines (docker run -e adds)
#   ports      "<container port> <host address>:<host port>" lines (docker port)
#   logs       its log
#   logs_first when present, the next `docker logs` prints it instead of the
#              log and removes it (a log read before the container exited)
#   join_exit  how `docker run ... join` ends: 0 (no conflicts), or that exit
#              status with join_log as the log
#   run_error  when present, `docker run` fails with this message
#   crash_log  when present, a router container exits at once with this log
#   never_ready  when present, the container runs but never logs its router
#              (router) or its name check's result (join)
#   run_hang   when present, `docker run` creates the running container and
#              then never returns
# `docker inspect --format {{.Id}}` answers id-NAME.
stub_docker() {
  export DOCKER_STUB="$BATS_TEST_TMPDIR/docker"
  mkdir -p "$DOCKER_STUB/c/conduit-router"
  echo ok > "$DOCKER_STUB/info"
  : > "$DOCKER_STUB/images"
  echo 0 > "$DOCKER_STUB/join_exit"
  cat > "$STUBS/docker" << 'STUB'
#!/usr/bin/env bash
d="$DOCKER_STUB"
printf '%s\n' "$*" >> "$d/calls"
cdir() {
  if [ "$1" = conduit-demo ]; then echo "$d"; else mkdir -p "$d/c/$1" && echo "$d/c/$1"; fi
}
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
    c="$(cdir "$4")"
    if [ ! -e "$c/container" ]; then
      echo "Error: No such object: $4" >&2
      exit 1
    fi
    case "$3" in
      *State.Status*) cat "$c/status" ;;
      *Config.Env*) cat "$c/env" 2> /dev/null ;;
      *.Id*) echo "id-$4" ;;
      *) cat "$c/container" ;;
    esac
    ;;
  port)
    c="$(cdir "$2")"
    awk -v p="${3%/tcp}" '$1 == p { print $2 }' "$c/ports" 2> /dev/null
    ;;
  logs)
    c="$(cdir "$2")"
    if [ -e "$c/logs_first" ]; then
      cat "$c/logs_first"
      rm -f "$c/logs_first"
    else
      cat "$c/logs" 2> /dev/null
    fi
    ;;
  rm)
    if [ "$2" = -f ]; then name="$3"; else name="$2"; fi
    c="$(cdir "$name")"
    if [ "$2" != -f ] && grep -q '^true ' "$c/container" 2> /dev/null; then
      echo "Error response from daemon: cannot remove container: container is running: stop the container before removing or force remove" >&2
      exit 1
    fi
    rm -f "$c/container" "$c/status" "$c/ports" "$c/logs" "$c/env"
    ;;
  exec)
    shift
    while [ "${1#-}" != "$1" ]; do shift; done
    shift
    [ "$1" != with-ros ] || shift
    exec "$@"
    ;;
  run)
    shift
    net=default
    name=""
    ports=""
    env=""
    while [ "${1#-}" != "$1" ]; do
      case "$1" in
        -p) ports="$ports${2#*:} 0.0.0.0:${2%%:*}
"; shift ;;
        --network) net="$2"; shift ;;
        -e) env="$env$2
"; shift ;;
        --name) name="$2"; shift ;;
        -v | --restart) shift ;;
      esac
      shift
    done
    image="$1"
    mode="${2:-}"
    c="$(cdir "$name")"
    printf '%s' "$ports" > "$c/ports"
    printf '%s' "$env" > "$c/env"
    if [ -e "$c/run_error" ]; then
      cat "$c/run_error" >&2
      exit 125
    fi
    echo "true $image $net" > "$c/container"
    echo "running 0" > "$c/status"
    if [ -e "$c/run_hang" ]; then
      echo "starting" > "$c/logs"
      exec sleep 30
    elif [ -e "$c/never_ready" ]; then
      echo "starting" > "$c/logs"
    elif [ "$mode" != join ] && [ -e "$c/crash_log" ]; then
      echo "false $image $net" > "$c/container"
      echo "exited 1" > "$c/status"
      cat "$c/crash_log" > "$c/logs"
    elif [ "$mode" != join ]; then
      echo "Started Zenoh router with id 0123456789abcdef" > "$c/logs"
    elif [ "$(cat "$d/join_exit")" = 0 ]; then
      echo "check_conflicts: no conflicts (12 topics, 30 services, 0 actions, 4 frames)" > "$c/logs"
    else
      echo "false $image $net" > "$c/container"
      echo "exited $(cat "$d/join_exit")" > "$c/status"
      cat "$d/join_log" > "$c/logs"
    fi
    echo 0123456789abcdef
    ;;
esac
STUB
  chmod +x "$STUBS/docker"
}

# ROUTER: the router container's state directory in the fake docker.
router_dir() { echo "$DOCKER_STUB/c/conduit-router"; }

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
