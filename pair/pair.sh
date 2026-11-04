#!/usr/bin/env bash
# Conduit pairing script: connects an iPhone running Conduit to this ROS 2 PC.
#
#   curl -fsSL https://conduit.youtalk.jp/pair.sh | bash
#   curl -fsSL https://conduit.youtalk.jp/pair.sh | bash -s -- --tailscale
#
# Site: https://conduit.youtalk.jp
#
# The whole body lives in functions and the last line calls main, so bash has
# read the entire script from the pipe before anything runs. Prompts read from
# /dev/tty because stdin is the script itself.
# PAIR_* variables are consumed by functions added in later tasks.
# shellcheck disable=SC2034
set -euo pipefail

readonly PAIR_INSTALL_URL="https://docs.ros.org/en/lyrical/Get-Started/Installation.html"
readonly PAIR_DEFAULT_CHECKIN_PORT=7449
readonly PAIR_SUPPORTED_DISTROS="humble jazzy kilted lyrical rolling"

# Exit codes: 0 connected, 1 environment not supported / user declined,
# 2 not connected, 130 interrupted.

say() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

die() {
  local code="$1"
  shift
  warn "$*"
  exit "$code"
}

# Read one line from the terminal (PAIR_TTY overrides /dev/tty for tests).
prompt_line() {
  local answer=""
  read -r answer < "${PAIR_TTY:-/dev/tty}" || true
  printf '%s' "$answer"
}

# ask_yes_no "question" y|n  -> returns 0 for yes
ask_yes_no() {
  local question="$1" default="${2:-n}" hint answer
  if [[ "$default" == y ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf '%s %s ' "$question" "$hint" >&2
  answer="$(prompt_line)"
  answer="${answer:-$default}"
  [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}

# choose "question" default option...  -> echoes the 1-based index chosen
choose() {
  local question="$1" default="$2" i answer
  shift 2
  say "$question" >&2
  for ((i = 1; i <= $#; i++)); do
    say "  $i) ${!i}" >&2
  done
  printf 'Choice [%s]: ' "$default" >&2
  answer="$(prompt_line)"
  answer="${answer:-$default}"
  if [[ ! "$answer" =~ ^[0-9]+$ ]] || ((answer < 1 || answer > $#)); then
    answer="$default"
  fi
  say "$answer"
}

env_root() { printf '%s' "${CONDUIT_PAIR_ROOT:-}"; }

check_platform() {
  local root os_id
  root="$(env_root)"
  if [[ "${PAIR_UNAME:-$(uname -s)}" != Linux ]]; then
    die 1 "This script supports Ubuntu only; other systems are planned."
  fi
  os_id=""
  if [[ -r "$root/etc/os-release" ]]; then
    os_id="$(sed -n 's/^ID=//p' "$root/etc/os-release" | head -n1 | tr -d '"')"
  fi
  if [[ "$os_id" != ubuntu ]]; then
    die 1 "This script supports Ubuntu only; other systems are planned."
  fi
}

check_not_wsl() {
  local root
  root="$(env_root)"
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] ||
    { [[ -r "$root/proc/version" ]] && grep -qi microsoft "$root/proc/version"; }; then
    die 1 "WSL is not supported yet. Run this on a native Ubuntu PC."
  fi
}

check_not_container() {
  local root
  root="$(env_root)"
  if [[ -e "$root/.dockerenv" || -e "$root/run/.containerenv" ]] ||
    { [[ -r "$root/proc/1/cgroup" ]] &&
      grep -Eq 'docker|containerd|kubepods|lxc' "$root/proc/1/cgroup"; }; then
    die 1 "Running inside a container: containers are not supported yet. Run this on the host."
  fi
}

check_ros_sourced() {
  local root setup
  root="$(env_root)"
  if [[ -n "${ROS_DISTRO:-}" ]]; then
    return 0
  fi
  setup="$(find "$root/opt/ros" -maxdepth 2 -name setup.bash 2> /dev/null | sort | head -n1 || true)"
  if [[ -z "$setup" ]]; then
    die 1 "ROS 2 was not found. Install it first: $PAIR_INSTALL_URL"
  fi
  setup="/${setup#"$root"/}"
  die 1 "ROS 2 is installed but not sourced. Run: source $setup  and then run this script again."
}

check_distro() {
  local d
  for d in $PAIR_SUPPORTED_DISTROS; do
    if [[ "$ROS_DISTRO" == "$d" ]]; then
      PAIR_DISTRO="$d"
      return 0
    fi
  done
  die 1 "ROS 2 '$ROS_DISTRO' is not supported. Supported: $PAIR_SUPPORTED_DISTROS."
}

check_rmw() {
  case "${RMW_IMPLEMENTATION:-}" in
    rmw_zenoh_cpp) PAIR_RMW=zenoh ;;
    rmw_cyclonedds_cpp) PAIR_RMW=cyclonedds ;;
    rmw_fastrtps_cpp | rmw_fastrtps_dynamic_cpp | "") PAIR_RMW=fastdds ;;
    *) die 1 "RMW_IMPLEMENTATION=$RMW_IMPLEMENTATION is not supported (use rmw_zenoh_cpp, rmw_cyclonedds_cpp or rmw_fastrtps_cpp)." ;;
  esac
}

check_domain() {
  local domain="${ROS_DOMAIN_ID:-0}"
  if [[ ! "$domain" =~ ^[0-9]+$ ]] || ((10#$domain > 232)); then
    die 1 "ROS_DOMAIN_ID=$domain is out of range (0-232)."
  fi
  PAIR_DOMAIN=$((10#$domain))
}

# Sets PAIR_DISTRO, PAIR_RMW and PAIR_DOMAIN, or stops with exit code 1.
check_environment() {
  check_platform
  check_not_wsl
  check_not_container
  check_ros_sourced
  check_distro
  check_rmw
  check_domain
}

# stdin: `ip route get 1.1.1.1` output. Echoes "src dev".
parse_route_get() {
  awk '{
    for (i = 1; i < NF; i++) {
      if ($i == "src") src = $(i + 1)
      if ($i == "dev") dev = $(i + 1)
    }
    if (src != "" && dev != "") { print src, dev; exit }
  }'
}

# stdin: `ip -4 -o addr show scope global` output. Echoes "iface ip" lines.
parse_addr_show() {
  awk '{
    for (i = 1; i < NF; i++) {
      if ($i == "inet") {
        split($(i + 1), a, "/")
        iface = $2
        sub(/:$/, "", iface)
        print iface, a[1]
        break
      }
    }
  }'
}

# Interfaces that never carry the LAN address the iPhone can reach.
is_ignored_iface() {
  case "$1" in
    lo | docker0 | br-* | veth* | virbr* | cni* | flannel* | tailscale0) return 0 ;;
    *) return 1 ;;
  esac
}

# Echoes "iface ip" lines, the default-route address first.
lan_candidates() {
  local src="" dev="" iface ip
  read -r src dev < <(ip route get 1.1.1.1 2> /dev/null | parse_route_get || true) || true
  if [[ -n "$src" ]] && ! is_ignored_iface "$dev"; then
    say "$dev $src"
  fi
  while read -r iface ip; do
    [[ -n "$iface" ]] || continue
    if is_ignored_iface "$iface" || [[ "$ip" == "$src" ]]; then
      continue
    fi
    say "$iface $ip"
  done < <(ip -4 -o addr show scope global 2> /dev/null | parse_addr_show || true)
}

# Echoes the Tailscale IPv4 address, or nothing.
tailscale_address() {
  local addr=""
  if command -v tailscale > /dev/null 2>&1; then
    addr="$(tailscale ip -4 2> /dev/null | head -n1 || true)"
  fi
  if [[ -z "$addr" ]]; then
    addr="$(ip -4 -o addr show scope global 2> /dev/null | parse_addr_show | awk '$1 == "tailscale0" {print $2; exit}' || true)"
  fi
  if [[ -n "$addr" ]]; then
    say "$addr"
  fi
}

# Sets PAIR_HOST and PAIR_VIA (lan|tailscale). PAIR_FORCE_VIA is lan,
# tailscale or empty (set by main from --lan / --tailscale).
pick_address() {
  local lan ts n idx options=() addrs=() vias=() line
  lan="$(lan_candidates)"
  ts="$(tailscale_address)"

  if [[ "${PAIR_FORCE_VIA:-}" == tailscale ]]; then
    [[ -n "$ts" ]] || die 1 "--tailscale was given but no Tailscale address was found. Start Tailscale (tailscale up) and try again."
    lan=""
  elif [[ "${PAIR_FORCE_VIA:-}" == lan ]]; then
    ts=""
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    options+=("${line#* } (${line%% *}, LAN)")
    addrs+=("${line#* }")
    vias+=(lan)
  done <<< "$lan"
  if [[ -n "$ts" ]]; then
    options+=("$ts (Tailscale)")
    addrs+=("$ts")
    vias+=(tailscale)
  fi

  n=${#addrs[@]}
  if ((n == 0)); then
    die 1 "No usable network address was found. Connect this PC to the same Wi-Fi as the iPhone, or start Tailscale."
  fi
  idx=1
  if ((n > 1)); then
    idx="$(choose "Which address should the iPhone use?" 1 "${options[@]}")"
  fi
  PAIR_HOST="${addrs[idx - 1]}"
  PAIR_VIA="${vias[idx - 1]}"
}

main() {
  check_environment
}

[[ "${CONDUIT_PAIR_SOURCED:-0}" == 1 ]] || main "$@"
