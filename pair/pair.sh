#!/usr/bin/env bash
# Conduit pairing script: connects an iPhone running Conduit to this ROS 2 PC.
#
#   curl -fsSL https://conduit.direct/pair.sh | bash
#   curl -fsSL https://conduit.direct/pair.sh | bash -s -- --tailscale
#
# Site: https://conduit.direct
#
# The whole body lives in functions and the last line calls main, so bash has
# read the entire script from the pipe before anything runs. Prompts read from
# /dev/tty because stdin is the script itself.
set -euo pipefail

readonly PAIR_INSTALL_URL="https://docs.ros.org/en/lyrical/Get-Started/Installation.html"
readonly PAIR_DEFAULT_CHECKIN_PORT=7449
readonly PAIR_SUPPORTED_DISTROS="humble jazzy kilted lyrical rolling"
# --demo (hidden until Conduit 3.0): the version of the Robots demo images,
# ghcr.io/youtalk/conduit-demo:<distro>-<version>. CONDUIT_DEMO_IMAGE, when set,
# names the image for every distribution instead.
readonly PAIR_DEMO_VERSION=0.1.0

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
  if [[ "$answer" =~ ^[0-9]{1,9}$ ]]; then
    answer=$((10#$answer))
  fi
  if [[ ! "$answer" =~ ^[0-9]+$ ]] || ((answer < 1 || answer > $#)); then
    answer="$default"
  fi
  say "$answer"
}

env_root() { printf '%s' "${CONDUIT_PAIR_ROOT:-}"; }

is_macos() { [[ "${PAIR_UNAME:-$(uname -s)}" == Darwin ]]; }

# os_release_field NAME: the value of NAME in /etc/os-release, without quotes.
os_release_field() {
  local file
  file="$(env_root)/etc/os-release"
  [[ -r "$file" ]] || return 0
  sed -n "s/^$1=//p" "$file" | head -n1 | tr -d '"'
}

# Sets PAIR_OS to ubuntu or rhel (RHEL, Fedora and their rebuilds such as Rocky
# Linux and AlmaLinux: the systems ROS 2 publishes RPM packages for).
check_platform() {
  local os_id like
  PAIR_OS=""
  if [[ "${PAIR_UNAME:-$(uname -s)}" == Linux ]]; then
    os_id="$(os_release_field ID)"
    like=" $(os_release_field ID_LIKE) "
    case "$os_id" in
      ubuntu) PAIR_OS=ubuntu ;;
      rhel | fedora) PAIR_OS=rhel ;;
      *) [[ "$like" != *" rhel "* && "$like" != *" fedora "* ]] || PAIR_OS=rhel ;;
    esac
  fi
  if [[ -z "${PAIR_OS:-}" ]]; then
    die 1 "This script supports Ubuntu, RHEL and Fedora only; other systems are planned."
  fi
}

# install_command PACKAGE: the command that installs PACKAGE on this system.
install_command() {
  if [[ "${PAIR_OS:-ubuntu}" == rhel ]]; then
    printf 'sudo dnf install %s\n' "$1"
  else
    printf 'sudo apt install %s\n' "$1"
  fi
}

check_not_wsl() {
  local root
  root="$(env_root)"
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] ||
    { [[ -r "$root/proc/version" ]] && grep -qi microsoft "$root/proc/version"; }; then
    die 1 "WSL is not supported yet. Run this on a native Ubuntu, RHEL or Fedora PC."
  fi
}

check_not_container() {
  local root
  root="$(env_root)"
  # CI only: the RHEL and Fedora smoke tests run the script in a container.
  [[ "${PAIR_ALLOW_CONTAINER:-0}" != 1 ]] || return 0
  if [[ -e "$root/.dockerenv" || -e "$root/run/.containerenv" ]] ||
    { [[ -r "$root/proc/1/cgroup" ]] &&
      grep -Eq 'docker|containerd|kubepods|lxc' "$root/proc/1/cgroup"; }; then
    die 1 "Running inside a container: containers are not supported yet. Run this on the host."
  fi
}

# shell_setup PATH: the setup file for the user's shell; setup.zsh for zsh when it exists.
shell_setup() {
  local setup="$1"
  if [[ "${SHELL##*/}" == zsh && -e "$(env_root)${setup%.bash}.zsh" ]]; then
    setup="${setup%.bash}.zsh"
  fi
  printf '%s\n' "$setup"
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
  setup="$(shell_setup "/${setup#"$root"/}")"
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

check_ros2_cli() {
  if ! command -v ros2 > /dev/null 2>&1; then
    die 1 "ROS_DISTRO is $ROS_DISTRO, but the ros2 command was not found. Run: source $(shell_setup "/opt/ros/$ROS_DISTRO/setup.bash")  and then run this script again."
  fi
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

# DDS only: stop when discovery cannot leave this PC, so the iPhone can never
# be found. Follows rcl: ROS_LOCALHOST_ONLY=1 counts on Humble and Jazzy only
# (Jazzy turns it into the LOCALHOST range and drops ROS_STATIC_PEERS, but
# keeps the CYCLONEDDS_URI peers), and ROS_AUTOMATIC_DISCOVERY_RANGE exists
# from Jazzy on. The LOCALHOST range still uses the peers this script adds.
# The environment is never changed; the fix is printed.
check_discovery_range() {
  local localhost_only=0 found=() fixes=()
  [[ "$PAIR_RMW" != zenoh ]] || return 0
  if [[ "${ROS_LOCALHOST_ONLY:-}" == 1 && ("$PAIR_DISTRO" == humble || "$PAIR_DISTRO" == jazzy) ]]; then
    localhost_only=1
    if [[ "$PAIR_DISTRO" == humble || "$PAIR_RMW" == fastdds ]]; then
      found+=("ROS_LOCALHOST_ONLY=1")
      fixes+=("unset ROS_LOCALHOST_ONLY")
    fi
  fi
  # On Jazzy, ROS_LOCALHOST_ONLY=1 overrides the range.
  if [[ "$PAIR_DISTRO" != humble && "${ROS_AUTOMATIC_DISCOVERY_RANGE:-}" == OFF ]] &&
    ((!localhost_only || ${#fixes[@]})); then
    found+=("ROS_AUTOMATIC_DISCOVERY_RANGE=OFF")
    fixes+=("export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET")
  fi
  ((${#fixes[@]})) || return 0
  warn "ROS 2 discovery is limited to this PC (${found[*]}), so the iPhone can never be found."
  warn "To fix it in this shell, run:"
  warn "$(printf '  %s\n' "${fixes[@]}")"
  die 1 "and then run this script again."
}

# Sets PAIR_DISTRO, PAIR_RMW and PAIR_DOMAIN, or stops with exit code 1.
check_environment() {
  check_platform
  check_not_wsl
  check_not_container
  check_ros_sourced
  check_distro
  check_ros2_cli
  check_rmw
  check_domain
  check_discovery_range
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

# macOS (--demo only): echoes "iface ip" for the default route's interface.
macos_lan_candidates() {
  local dev addr
  dev="$(route -n get default 2> /dev/null | awk '$1 == "interface:" { print $2; exit }' || true)"
  [[ -n "$dev" ]] || return 0
  addr="$(ipconfig getifaddr "$dev" 2> /dev/null || true)"
  [[ -z "$addr" ]] || say "$dev $addr"
}

# Echoes "iface ip" lines, the default-route address first.
lan_candidates() {
  local src="" dev="" iface ip
  if is_macos; then
    macos_lan_candidates
    return 0
  fi
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

# Percent-encode everything except A-Z a-z 0-9 . _ ~ -
urlencode() {
  local s="$1" out="" c i
  local LC_ALL=C
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [A-Za-z0-9._~-]) out+="$c" ;;
      *) out+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}

# build_link STYLE TRANSPORT DISTRO DOMAIN HOST PORT CHECKIN TOKEN NAME
# STYLE is https|custom; PORT is empty for DDS.
build_link() {
  local style="$1" transport="$2" distro="$3" domain="$4" host="$5" port="$6"
  local checkin="$7" token="$8" name="${9:0:64}" base frag
  if [[ "$style" == custom ]]; then
    base="conduit://pair"
  else
    base="https://conduit.direct/pair"
  fi
  frag="v=1&transport=$(urlencode "$transport")&distro=$(urlencode "$distro")"
  frag+="&domain=$(urlencode "$domain")&host=$(urlencode "$host")"
  [[ -z "$port" ]] || frag+="&port=$(urlencode "$port")"
  frag+="&checkin=$(urlencode "$checkin")&token=$(urlencode "$token")"
  frag+="&name=$(urlencode "$name")"
  printf '%s#%s' "$base" "$frag"
}

# The python3 that runs the embedded Python: this PC's, or on the --demo
# container path the demo container's (a Mac may have no python3).
PAIR_PYTHON=(python3)

have_python() {
  [[ "${PAIR_PYTHON[0]}" != python3 ]] || command -v python3 > /dev/null 2>&1
}

# Draw the QR for LINK (or write a PBM with --pbm). Embedded encoder: a trimmed
# copy of Nayuki's qrcodegen.py, Python 3 standard library only.
py_qr() {
  "${PAIR_PYTHON[@]}" - "$@" <<'PY'
# >>> python:qr
#
# QR Code generator library (Python)
#
# Copyright (c) Project Nayuki. (MIT License)
# https://www.nayuki.io/page/qr-code-generator-library
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
# - The above copyright notice and this permission notice shall be included in
#   all copies or substantial portions of the Software.
# - The Software is provided "as is", without warranty of any kind, express or
#   implied, including but not limited to the warranties of merchantability,
#   fitness for a particular purpose and noninfringement. In no event shall the
#   authors or copyright holders be liable for any claim, damages or other
#   liability, whether in an action of contract, tort or otherwise, arising from,
#   out of or in connection with the Software or the use or other dealings in the
#   Software.
#

import sys
from collections import deque

# QR encoder for this script: byte mode, error correction level M, versions 1-40.
# Trimmed from the library above; the algorithms are unchanged.

# Per-version tables for level M (index 0 is unused).
ECC_PER_BLOCK = (-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28)
NUM_BLOCKS = (-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49)
FORMAT_BITS_M = 0  # The two format-info bits for level M.

MASKS = (
    lambda x, y: (x + y) % 2,
    lambda x, y: y % 2,
    lambda x, y: x % 3,
    lambda x, y: (x + y) % 3,
    lambda x, y: (x // 3 + y // 2) % 2,
    lambda x, y: x * y % 2 + x * y % 3,
    lambda x, y: (x * y % 2 + x * y % 3) % 2,
    lambda x, y: ((x + y) % 2 + x * y % 3) % 2,
)


def raw_modules(ver):
    """Data bits a version holds once the function modules are excluded."""
    result = (16 * ver + 128) * ver + 64
    if ver >= 2:
        n = ver // 7 + 2
        result -= (25 * n - 10) * n - 55
        if ver >= 7:
            result -= 36
    return result


def data_codewords(ver):
    return raw_modules(ver) // 8 - ECC_PER_BLOCK[ver] * NUM_BLOCKS[ver]


def gf_multiply(x, y):
    """Multiply in GF(2^8) modulo 0x11D."""
    z = 0
    for i in reversed(range(8)):
        z = (z << 1) ^ ((z >> 7) * 0x11D)
        z ^= ((y >> i) & 1) * x
    return z


def rs_divisor(degree):
    """Reed-Solomon generator polynomial, highest power first, leading 1 omitted."""
    result = [0] * (degree - 1) + [1]
    root = 1
    for _ in range(degree):
        for j in range(degree):
            result[j] = gf_multiply(result[j], root)
            if j + 1 < degree:
                result[j] ^= result[j + 1]
        root = gf_multiply(root, 2)
    return result


def rs_remainder(data, divisor):
    result = [0] * len(divisor)
    for b in data:
        factor = b ^ result.pop(0)
        result.append(0)
        for i, coef in enumerate(divisor):
            result[i] ^= gf_multiply(coef, factor)
    return result


def add_ecc_and_interleave(data, ver):
    nblocks, ecclen = NUM_BLOCKS[ver], ECC_PER_BLOCK[ver]
    raw = raw_modules(ver) // 8
    nshort, shortlen = nblocks - raw % nblocks, raw // nblocks
    divisor = rs_divisor(ecclen)
    blocks = []
    k = 0
    for i in range(nblocks):
        dat = list(data[k:k + shortlen - ecclen + (0 if i < nshort else 1)])
        k += len(dat)
        ecc = rs_remainder(dat, divisor)
        if i < nshort:
            dat.append(0)  # Padding so short blocks line up; skipped below.
        blocks.append(dat + ecc)
    out = []
    for i in range(len(blocks[0])):
        for j, blk in enumerate(blocks):
            if i != shortlen - ecclen or j >= nshort:
                out.append(blk[i])
    return out


def alignment_positions(ver, size):
    if ver == 1:
        return []
    n = ver // 7 + 2
    step = (ver * 8 + n * 3 + 5) // (n * 4 - 4) * 2
    return [6] + [size - 7 - i * step for i in reversed(range(n - 1))]


def bit(x, i):
    return (x >> i) & 1 != 0


class Grid:
    """The module matrix; True is dark. Function modules are exempt from masking."""

    def __init__(self, ver):
        self.ver = ver
        self.size = ver * 4 + 17
        self.mod = [[False] * self.size for _ in range(self.size)]
        self.fn = [[False] * self.size for _ in range(self.size)]

    def put(self, x, y, dark):
        self.mod[y][x] = dark
        self.fn[y][x] = True

    def draw_function_patterns(self):
        size = self.size
        for i in range(size):  # Timing patterns
            self.put(6, i, i % 2 == 0)
            self.put(i, 6, i % 2 == 0)
        for cx, cy in ((3, 3), (size - 4, 3), (3, size - 4)):  # Finders and separators
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    x, y = cx + dx, cy + dy
                    if 0 <= x < size and 0 <= y < size:
                        self.put(x, y, max(abs(dx), abs(dy)) not in (2, 4))
        pos = alignment_positions(self.ver, size)
        for i, cx in enumerate(pos):
            for j, cy in enumerate(pos):
                if (i, j) in ((0, 0), (0, len(pos) - 1), (len(pos) - 1, 0)):
                    continue
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        self.put(cx + dx, cy + dy, max(abs(dx), abs(dy)) != 1)
        self.draw_format(0)  # Placeholder; redrawn once the mask is chosen.
        if self.ver >= 7:
            rem = self.ver
            for _ in range(12):
                rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
            bits = self.ver << 12 | rem
            for i in range(18):
                a, b = size - 11 + i % 3, i // 3
                self.put(a, b, bit(bits, i))
                self.put(b, a, bit(bits, i))

    def draw_format(self, mask):
        data = FORMAT_BITS_M << 3 | mask
        rem = data
        for _ in range(10):
            rem = (rem << 1) ^ ((rem >> 9) * 0x537)
        bits = (data << 10 | rem) ^ 0x5412
        size = self.size
        for i in range(6):
            self.put(8, i, bit(bits, i))
        self.put(8, 7, bit(bits, 6))
        self.put(8, 8, bit(bits, 7))
        self.put(7, 8, bit(bits, 8))
        for i in range(9, 15):
            self.put(14 - i, 8, bit(bits, i))
        for i in range(8):
            self.put(size - 1 - i, 8, bit(bits, i))
        for i in range(8, 15):
            self.put(8, size - 15 + i, bit(bits, i))
        self.put(8, size - 8, True)

    def draw_codewords(self, data):
        i = 0
        for right in range(self.size - 1, 0, -2):  # Zigzag over column pairs
            if right <= 6:
                right -= 1
            for vert in range(self.size):
                for j in range(2):
                    x = right - j
                    upward = (right + 1) & 2 == 0
                    y = (self.size - 1 - vert) if upward else vert
                    if not self.fn[y][x] and i < len(data) * 8:
                        self.mod[y][x] = bit(data[i >> 3], 7 - (i & 7))
                        i += 1

    def apply_mask(self, mask):
        """XOR the data modules with a mask pattern; applying it twice undoes it."""
        f = MASKS[mask]
        for y in range(self.size):
            for x in range(self.size):
                self.mod[y][x] ^= f(x, y) == 0 and not self.fn[y][x]

    def penalty(self):
        size, mod = self.size, self.mod
        result = 0
        rows = mod
        cols = [[mod[y][x] for y in range(size)] for x in range(size)]
        for line in rows + cols:  # Runs of one color, and finder-like patterns
            color, run = False, 0
            history = deque([0] * 7, 7)
            for cell in line:
                if cell == color:
                    run += 1
                    if run == 5:
                        result += 3
                    elif run > 5:
                        result += 1
                else:
                    self.add_history(run, history)
                    if not color:
                        result += self.count_patterns(history) * 40
                    color, run = cell, 1
            if color:
                self.add_history(run, history)
                run = 0
            run += size
            self.add_history(run, history)
            result += self.count_patterns(history) * 40
        for y in range(size - 1):  # 2x2 blocks of one color
            for x in range(size - 1):
                if mod[y][x] == mod[y][x + 1] == mod[y + 1][x] == mod[y + 1][x + 1]:
                    result += 3
        dark = sum(cell for row in mod for cell in row)
        total = size * size
        result += ((abs(dark * 20 - total * 10) + total - 1) // total - 1) * 10
        return result

    def add_history(self, run, history):
        if history[0] == 0:
            run += self.size  # Light border before the first run
        history.appendleft(run)

    @staticmethod
    def count_patterns(h):
        n = h[1]
        core = n > 0 and h[2] == h[4] == h[5] == n and h[3] == n * 3
        return (core and h[0] >= n * 4 and h[6] >= n) + (core and h[6] >= n * 4 and h[0] >= n)


def encode(data):
    """Return the module matrix (list of rows of bool) for the bytes in data."""
    for ver in range(1, 41):
        count_bits = 8 if ver < 10 else 16
        used = 4 + count_bits + len(data) * 8
        if len(data) < (1 << count_bits) and used <= data_codewords(ver) * 8:
            break
    else:
        raise ValueError("link too long for a QR code")
    bits = [int(c) for c in format(0x4, "04b") + format(len(data), "0%db" % count_bits)]
    bits += [int(c) for byte in data for c in format(byte, "08b")]
    capacity = data_codewords(ver) * 8
    bits += [0] * min(4, capacity - len(bits))
    bits += [0] * (-len(bits) % 8)
    pad = 0xEC
    while len(bits) < capacity:
        bits += [int(c) for c in format(pad, "08b")]
        pad ^= 0xEC ^ 0x11
    words = [int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8)]
    grid = Grid(ver)
    grid.draw_function_patterns()
    grid.draw_codewords(add_ecc_and_interleave(words, ver))
    best, best_penalty = 0, None
    for m in range(8):
        grid.apply_mask(m)
        grid.draw_format(m)
        p = grid.penalty()
        if best_penalty is None or p < best_penalty:
            best, best_penalty = m, p
        grid.apply_mask(m)
    grid.apply_mask(best)
    grid.draw_format(best)
    return grid.mod


def render(link, quiet=2):
    """Module matrix with a quiet zone of `quiet` light modules on every side."""
    mod = encode(link.encode("UTF-8"))
    size = len(mod)
    return [[0 <= x < size and 0 <= y < size and mod[y][x]
             for x in range(-quiet, size + quiet)] for y in range(-quiet, size + quiet)]


def main(argv):
    grid = render(argv[1])
    if "--pbm" in argv[2:]:
        scale = 4
        print("P1")
        print(len(grid[0]) * scale, len(grid) * scale)
        for row in grid:
            line = " ".join("1" if dark else "0" for dark in row for _ in range(scale))
            for _ in range(scale):
                print(line)
        return
    # Light modules are drawn as blocks, like qrencode -t UTF8: a bright code on a dark terminal.
    if len(grid) % 2:
        grid.append([False] * len(grid[0]))
    for y in range(0, len(grid), 2):
        out = []
        for x in range(len(grid[0])):
            top, bottom = not grid[y][x], not grid[y + 1][x]
            out.append("\u2588" if top and bottom else "\u2580" if top else "\u2584" if bottom else " ")
        print("".join(out))


if __name__ == "__main__":
    main(sys.argv)
# <<< python:qr
PY
}

# show_link LINK NO_QR(0|1)
show_link() {
  local link="$1" no_qr="${2:-0}"
  if [[ "$no_qr" != 1 ]]; then
    if command -v qrencode > /dev/null 2>&1; then
      qrencode -t UTF8 "$link"
    elif have_python; then
      py_qr "$link"
    else
      warn "python3 not found: skipping the QR code."
    fi
  fi
  say "Or open this link on the iPhone:"
  say "$link"
}

# Embedded check-in listener. Python 3 standard library only. Its stdin tells
# it when the script is gone (see start_checkin), so the code travels as an
# argument, not stdin.
CHECKIN_PY=""
read -r -d '' CHECKIN_PY << 'PY' || true
# >>> python:checkin
import hmac
import json
import os
import re
import socket
import sys
import threading

TOKEN = sys.argv[1]
PORT = int(sys.argv[2])
HINT_SECONDS = float(os.environ.get("CONDUIT_PAIR_HINT_SECONDS", "120"))
LOCK = threading.Lock()
GOT_CHECKIN = threading.Event()


def emit(line):
    with LOCK:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def safe(value):
    return re.sub(r"[^A-Za-z0-9._/ -]", "_", value)


def handle(conn, peer_ip):
    try:
        conn.settimeout(5)
        data = b""
        while b"\n" not in data and len(data) < 4096:
            chunk = conn.recv(4096 - len(data))
            if not chunk:
                break
            data += chunk
        reply = {"ok": False, "error": "bad_request"}
        try:
            req = json.loads(data.split(b"\n", 1)[0].decode("utf-8"))
            fields = [req[k] for k in ("token", "node", "namespace", "device", "app_version")]
            if all(isinstance(f, str) for f in fields):
                if hmac.compare_digest(fields[0].encode(), TOKEN.encode()):
                    reply = {"ok": True}
                    emit(
                        "CHECKIN phone_ip=%s node=%s namespace=%s device=%s app_version=%s"
                        % (safe(peer_ip), safe(fields[1]), safe(fields[2]), safe(fields[3]), safe(fields[4]))
                    )
                    GOT_CHECKIN.set()
                else:
                    reply = {"ok": False, "error": "bad_token"}
        except (ValueError, KeyError, TypeError, UnicodeDecodeError):
            pass
        conn.sendall((json.dumps(reply, separators=(",", ":")) + "\n").encode())
    except OSError:
        pass
    finally:
        conn.close()


def watch_parent():
    # stdin is a pipe from the script; EOF means the script is gone.
    try:
        while sys.stdin.buffer.read(1024):
            pass
    except OSError:
        pass
    os._exit(0)


def hint_timer():
    if not GOT_CHECKIN.wait(HINT_SECONDS):
        emit("HINT no_checkin")


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("0.0.0.0", PORT))
    except OSError:
        srv.close()
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.bind(("0.0.0.0", 0))
    srv.listen(16)
    emit("PORT=%d" % srv.getsockname()[1])
    threading.Thread(target=watch_parent, daemon=True).start()
    threading.Thread(target=hint_timer, daemon=True).start()
    while True:
        conn, addr = srv.accept()
        threading.Thread(target=handle, args=(conn, addr[0]), daemon=True).start()


if __name__ == "__main__":
    main()
# <<< python:checkin
PY

# start_checkin TOKEN PORT: run the listener in the background and set
# PAIR_CHECKIN_PORT to the port it bound and CHECKIN_PID to its process. Two
# FIFOs connect it, because macOS runs this script with bash 3.2 (no coproc):
# its stdin is fd 8, which only this script holds, so the listener sees EOF
# and exits when the script ends; its output is read from fd 9
# (PAIR_CHECKIN_FD), which reaches EOF once the listener exits.
start_checkin() {
  local token="$1" port="$2" line
  have_python || die 1 "python3 is required to receive the iPhone's check-in."
  if ! PAIR_CHECKIN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/conduit-pair.XXXXXX")" ||
    ! mkfifo "$PAIR_CHECKIN_DIR/in" "$PAIR_CHECKIN_DIR/out"; then
    die 1 "Could not create the check-in listener's FIFOs in ${TMPDIR:-/tmp}."
  fi
  "${PAIR_PYTHON[@]}" -u -c "$CHECKIN_PY" "$token" "$port" < "$PAIR_CHECKIN_DIR/in" > "$PAIR_CHECKIN_DIR/out" &
  CHECKIN_PID=$!
  trap pair_exit EXIT
  # Each open waits for the listener to open the other end.
  exec 8> "$PAIR_CHECKIN_DIR/in" 9< "$PAIR_CHECKIN_DIR/out"
  rm -rf "$PAIR_CHECKIN_DIR"
  PAIR_CHECKIN_DIR=""
  PAIR_CHECKIN_FD=9
  read -r line <&"$PAIR_CHECKIN_FD" || die 1 "The check-in listener did not start."
  [[ "$line" =~ ^PORT=([0-9]+)$ ]] || die 1 "The check-in listener did not report a port."
  PAIR_CHECKIN_PORT="${BASH_REMATCH[1]}"
}

# pair_exit: the EXIT trap. Stops the check-in listener, and says how to stop the
# demo when this run started or used it and ends before its next steps.
pair_exit() {
  stop_checkin
  demo_exit_hint
}

stop_checkin() {
  if [[ -n "${CHECKIN_PID:-}" ]]; then
    kill "$CHECKIN_PID" 2> /dev/null || true
    wait "$CHECKIN_PID" 2> /dev/null || true
    CHECKIN_PID=""
  fi
  if [[ -n "${PAIR_CHECKIN_DIR:-}" ]]; then
    rm -rf "$PAIR_CHECKIN_DIR"
    PAIR_CHECKIN_DIR=""
  fi
}

# parse_checkin LINE: read "CHECKIN key=value ..." from the listener. Values may
# hold spaces but never "=" (the listener replaces it), so each value runs up to
# the next " key=". Sets PAIR_PHONE_IP, PAIR_NODE, PAIR_NAMESPACE and
# PAIR_DEVICE; returns 1 unless the address and the node are present.
parse_checkin() {
  local rest phone="" node="" ns="" device=""
  [[ "$1" == "CHECKIN "* ]] || return 1
  rest="${1#CHECKIN }"
  while [[ "$rest" =~ ^([a-z_]+)=([^=]*)(\ [a-z_]+=.*)?$ ]]; do
    case "${BASH_REMATCH[1]}" in
      phone_ip) phone="${BASH_REMATCH[2]}" ;;
      node) node="${BASH_REMATCH[2]}" ;;
      namespace) ns="${BASH_REMATCH[2]}" ;;
      device) device="${BASH_REMATCH[2]}" ;;
      *) ;;
    esac
    rest="${BASH_REMATCH[3]# }"
    [[ -n "$rest" ]] || break
  done
  [[ -n "$phone" && -n "$node" ]] || return 1
  PAIR_PHONE_IP="$phone"
  PAIR_NODE="$node"
  PAIR_NAMESPACE="$ns"
  PAIR_DEVICE="${device:-the iPhone}"
}

# wait_checkin: block until a valid check-in (see parse_checkin); prints the
# no-check-in causes on HINT. Returns 1 if the listener goes away first.
wait_checkin() {
  local line
  while read -r line <&"$PAIR_CHECKIN_FD"; do
    if parse_checkin "$line"; then
      return 0
    elif [[ "$line" == "HINT no_checkin" ]]; then
      if declare -F causes > /dev/null; then causes no_checkin; fi
    fi
  done
  return 1
}

# Whether the host needs the iPhone as an explicit discovery peer. Both come
# from the Part 1 spike (youtalk/conduit QR pairing plan) and may flip to false.
HOST_PEERS_REQUIRED_CYCLONEDDS=true
HOST_PEERS_REQUIRED_FASTDDS=true

RESTART_NOTE="Restart ROS 2 nodes that were already running, and run 'ros2 daemon stop', so they pick up the iPhone. Run this script again if the iPhone's address changes."

# zenoh_router_listening [PORT]: 0 when 127.0.0.1:PORT accepts a connection.
zenoh_router_listening() {
  local port="${1:-7447}"
  # shellcheck disable=SC2261
  (exec 3<> "/dev/tcp/127.0.0.1/$port") 2> /dev/null
}

# zenoh_router_executable: the rmw_zenohd binary of the sourced ROS 2.
zenoh_router_executable() {
  local prefix exe
  prefix="$(ros2 pkg prefix rmw_zenoh_cpp 2> /dev/null)" || return 1
  exe="$prefix/lib/rmw_zenoh_cpp/rmw_zenohd"
  [[ -x "$exe" ]] || return 1
  printf '%s\n' "$exe"
}

# start_zenoh_router PORT: start rmw_zenohd detached from this terminal, so it
# keeps running after the script ends (the iPhone keeps using it). The binary
# runs directly, not under `ros2 run`, so the PID shown is the router's own.
# 0 once it listens on PORT.
start_zenoh_router() {
  local port="$1" exe log pid i
  if ! exe="$(zenoh_router_executable)"; then
    say "rmw_zenohd was not found in the sourced ROS 2 (package rmw_zenoh_cpp)."
    return 1
  fi
  log="${XDG_CACHE_HOME:-$HOME/.cache}/conduit/rmw_zenohd.log"
  if ! mkdir -p "${log%/*}"; then
    say "Could not create ${log%/*} for the router's log."
    return 1
  fi
  if command -v setsid > /dev/null 2>&1; then
    setsid nohup "$exe" > "$log" 2>&1 < /dev/null &
  else
    nohup "$exe" > "$log" 2>&1 < /dev/null &
  fi
  pid=$!
  for ((i = 0; i < 100; i++)); do
    zenoh_router_listening "$port" && break
    kill -0 "$pid" 2> /dev/null || break
    sleep 0.1
  done
  if ! zenoh_router_listening "$port"; then
    kill "$pid" 2> /dev/null || true
    say "The Zenoh router did not start. The end of its log ($log):"
    tail -n 5 "$log" 2> /dev/null | sed 's/^/  /' || true
    return 1
  fi
  say "Started the Zenoh router (PID $pid). It keeps running after this script ends."
  say "  Log:  $log"
  say "  Stop: kill $pid"
}

fastdds_warning() {
  say "Fast DDS may drop or delay Conduit's high-rate topics (camera, LiDAR) over Wi-Fi. CycloneDDS is recommended:"
  say "  $(install_command "ros-${PAIR_DISTRO}-rmw-cyclonedds-cpp")"
  say "  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
}

tailscale_needs_zenoh() {
  say "Tailscale works with Zenoh only. To switch this shell to Zenoh:"
  say "  export RMW_IMPLEMENTATION=rmw_zenoh_cpp"
  say "  ros2 run rmw_zenoh_cpp rmw_zenohd    # in another terminal"
  say "If rmw_zenoh_cpp is missing:"
  say "  $(install_command "ros-${PAIR_DISTRO}-rmw-zenoh-cpp")"
  say "Then run this script again in that shell."
}

# export_line NAME VALUE: a single-quoted export line that survives any value.
# The substitution is an assignment: bash 3.2 keeps the quotes of a quoted
# replacement inside "${...}".
export_line() {
  local q="'" esc="'\\''" value
  value=${2//$q/$esc}
  printf "export %s='%s'\n" "$1" "$value"
}

# host_peer_config PHONE_IP: write the peer files under ~/.config/conduit and
# print export lines on stdout; notes for the user go to stderr.
host_peer_config() {
  local phone="$1" dir="$HOME/.config/conduit" f
  case "$PAIR_RMW" in
    cyclonedds)
      f="$dir/cyclonedds-peer.xml"
      mkdir -p "$dir" &&
        printf '%s\n' "<CycloneDDS><Domain id=\"any\"><Discovery><Peers><Peer address=\"$phone\"/></Peers></Discovery></Domain></CycloneDDS>" > "$f" ||
        return 1
      # A second run (or a ~/.bashrc block) may already carry the peer file.
      if [[ "${CYCLONEDDS_URI:-}" == *"file://$f"* ]]; then
        export_line CYCLONEDDS_URI "$CYCLONEDDS_URI"
      else
        export_line CYCLONEDDS_URI "${CYCLONEDDS_URI:+$CYCLONEDDS_URI,}file://$f"
      fi
      ;;
    fastdds)
      if [[ "$PAIR_DISTRO" != humble ]]; then
        if [[ ";${ROS_STATIC_PEERS:-};" == *";$phone;"* ]]; then
          export_line ROS_STATIC_PEERS "$ROS_STATIC_PEERS"
        else
          export_line ROS_STATIC_PEERS "${ROS_STATIC_PEERS:+$ROS_STATIC_PEERS;}$phone"
        fi
      elif [[ -n "${FASTRTPS_DEFAULT_PROFILES_FILE:-}" ]]; then
        warn "FASTRTPS_DEFAULT_PROFILES_FILE is already set to $FASTRTPS_DEFAULT_PROFILES_FILE."
        warn "Add these initial peers to its default participant profile by hand:"
        warn "  udpv4 $phone (no port)"
        warn "  udpv4 239.255.0.1 port $((7400 + 250 * PAIR_DOMAIN))"
      else
        f="$dir/fastdds-peer.xml"
        mkdir -p "$dir" || return 1
        cat > "$f" << XML || return 1
<?xml version="1.0" encoding="UTF-8"?>
<profiles xmlns="http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles">
  <participant profile_name="conduit_pairing" is_default_profile="true">
    <rtps>
      <builtin>
        <initialPeersList>
          <locator><udpv4><address>$phone</address></udpv4></locator>
          <locator><udpv4><address>239.255.0.1</address><port>$((7400 + 250 * PAIR_DOMAIN))</port></udpv4></locator>
        </initialPeersList>
      </builtin>
    </rtps>
  </participant>
</profiles>
XML
        export_line FASTRTPS_DEFAULT_PROFILES_FILE "$f"
      fi
      ;;
    *) ;;
  esac
}

# bashrc_with_block FILE EXPORT_LINES: replace or append the pairing block.
# A begin marker without its end marker leaves FILE untouched and returns 1.
bashrc_with_block() {
  local file="$1" lines="$2" begin="# >>> conduit pairing >>>" end="# <<< conduit pairing <<<" tmp
  if [[ -f "$file" ]] &&
    ! awk -v b="$begin" -v e="$end" '$0 == b { open = 1 } $0 == e { open = 0 } END { exit open }' "$file"; then
    warn "$file has '$begin' without '$end'; it was left unchanged. Fix or remove that block and run this script again."
    return 1
  fi
  # Callers run this in an `if`, where set -e is off: check every step, and
  # touch FILE only once the new content is complete.
  tmp="$(mktemp)" || return 1
  {
    [[ ! -f "$file" ]] ||
      awk -v b="$begin" -v e="$end" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$file"
    printf '%s\n%s\n%s\n' "$begin" "$lines" "$end"
  } > "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  cat "$tmp" > "$file" || {
    warn "Could not write $file."
    rm -f "$tmp"
    return 1
  }
  rm -f "$tmp"
}

# wait_for_node NODE NAMESPACE TIMEOUT: 0 once /NAMESPACE/NODE is in the graph.
wait_for_node() {
  local node="$1" ns="$2" timeout="$3" want deadline nodes spin_time=1
  ns="${ns#/}"
  ns="${ns%/}"
  want="/${ns:+$ns/}$node"
  if ! ros2 node list --help 2> /dev/null | grep -q -- '--spin-time'; then
    # Older CLIs: ask the daemon, after a restart so it sees the new peers.
    spin_time=0
    ros2 daemon stop > /dev/null 2>&1 || true
  fi
  say "Tap Start in Conduit."
  deadline=$((SECONDS + timeout))
  while ((SECONDS < deadline)); do
    if ((spin_time)); then
      nodes="$(ros2 node list --no-daemon --spin-time 3 2> /dev/null || true)"
    else
      nodes="$(ros2 node list 2> /dev/null || true)"
    fi
    if grep -qxF -- "$want" <<< "$nodes"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# wait_for_data TIMEOUT: 0 once Conduit's latched /tf_static arrives.
wait_for_data() {
  local status=0
  # grep's status decides, whatever ros2 exits with: pipefail is off for the
  # pipeline. (Not PIPESTATUS: bash 3.2 resets it when a DEBUG trap runs.)
  set +o pipefail
  # Unbuffered so the first message reaches grep at once; --foreground keeps
  # ros2 in this terminal's process group so Ctrl-C ends the wait. -k: under
  # rmw_zenoh_cpp, ros2 may not exit on SIGTERM, so SIGKILL it 5 s later.
  PYTHONUNBUFFERED=1 timeout --foreground -k 5 "$1" ros2 topic echo --qos-durability transient_local --qos-reliability reliable \
    /tf_static tf2_msgs/msg/TFMessage 2> /dev/null | grep -q -m1 'frame_id: conduit_base_link' || status=$?
  set -o pipefail
  return "$status"
}

ufw_enabled() {
  grep -Eq '^[[:space:]]*ENABLED[[:space:]]*=[[:space:]]*yes' "$(env_root)/etc/ufw/ufw.conf" 2> /dev/null
}

# firewalld (RHEL and Fedora) is on when firewall-cmd reports it running.
firewalld_running() {
  command -v firewall-cmd > /dev/null 2>&1 && [[ "$(firewall-cmd --state 2> /dev/null)" == running ]]
}

# causes STAGE (no_checkin|no_node|no_data): what to check, firewall first.
causes() {
  local stage="$1" dds_port=$((7400 + 250 * PAIR_DOMAIN))
  if [[ "${PAIR_DEMO_PATH:-0}" == 1 ]]; then
    demo_causes
    return 0
  fi
  case "$stage" in
    no_checkin) say "No check-in from the iPhone yet. Things to check:" ;;
    no_node) say "Conduit did not appear in the ROS 2 graph. Things to check:" ;;
    no_data) say "Conduit is in the ROS 2 graph, but no message arrived on /tf_static. Things to check:" ;;
    *) ;;
  esac
  if ufw_enabled; then
    say "- The firewall (ufw) is on. Allow Conduit's ports:"
    if [[ "$stage" == no_checkin ]]; then
      say "    sudo ufw allow ${PAIR_CHECKIN_PORT:-$PAIR_DEFAULT_CHECKIN_PORT}/tcp"
    fi
    if [[ "$PAIR_RMW" == zenoh ]]; then
      say "    sudo ufw allow 7447/tcp"
    else
      say "    sudo ufw allow $dds_port:$((dds_port + 249))/udp"
    fi
  fi
  if firewalld_running; then
    say "- The firewall (firewalld) is on. Allow Conduit's ports until the next reboot (add --permanent to keep them):"
    if [[ "$stage" == no_checkin ]]; then
      say "    sudo firewall-cmd --add-port=${PAIR_CHECKIN_PORT:-$PAIR_DEFAULT_CHECKIN_PORT}/tcp"
    fi
    if [[ "$PAIR_RMW" == zenoh ]]; then
      say "    sudo firewall-cmd --add-port=7447/tcp"
    else
      say "    sudo firewall-cmd --add-port=$dds_port-$((dds_port + 249))/udp"
    fi
  fi
  case "$stage" in
    no_checkin)
      if [[ "${PAIR_VIA:-lan}" == tailscale ]]; then
        say "- Open the Tailscale app on the iPhone and connect it to the same tailnet as this PC."
      else
        say "- The iPhone must be on the same Wi-Fi as this PC."
        say "- Guest and office Wi-Fi often isolate clients from each other (client isolation); try another network or a hotspot."
        say "- Allow Local Network access for Conduit: iPhone Settings > Privacy & Security > Local Network."
      fi
      say "- Scan the QR again if Conduit did not open from it."
      ;;
    no_node)
      say "- Did you tap Start in Conduit?"
      if [[ "$PAIR_RMW" == zenoh ]]; then
        say "- The Zenoh router must keep running: ros2 run rmw_zenoh_cpp rmw_zenohd"
      fi
      say "- If the iPhone's address changed, run this script again."
      ;;
    no_data)
      if [[ "$PAIR_RMW" != zenoh ]]; then
        say "- Shells that run ROS 2 nodes need the export line printed above (or a new shell after adding it to ~/.bashrc)."
      fi
      if [[ "$PAIR_RMW" == fastdds ]]; then
        say "- Fast DDS may drop Conduit's messages over Wi-Fi. Switch to CycloneDDS:"
        say "    export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
      fi
      say "- If the iPhone's address changed, run this script again."
      ;;
    *) ;;
  esac
}

# --demo: the Robots demo, hidden until Conduit 3.0 (not in usage).
#
# A Mac, or a Linux PC without ROS 2, takes the demo path: the demo container
# runs its own Zenoh router on published ports, and the iPhone pairs with it
# (Zenoh, Lyrical, domain 0). A Linux PC with ROS 2 pairs as without --demo and
# also starts the demo robots on its own graph (join mode), unless that graph
# already uses one of their names.

readonly PAIR_DEMO_CONTAINER=conduit-demo
# A full demo takes about 20 s to shut down.
readonly PAIR_DEMO_STOP="docker stop -t 30 $PAIR_DEMO_CONTAINER"
readonly PAIR_DOCKER_INSTALL_URL="https://docs.docker.com/engine/install/"
readonly PAIR_DOCKER_DESKTOP_URL="https://docs.docker.com/desktop/setup/install/mac-install/"

# demo_image DISTRO: the demo image for DISTRO (CONDUIT_DEMO_IMAGE overrides it).
demo_image() {
  printf '%s\n' "${CONDUIT_DEMO_IMAGE:-ghcr.io/youtalk/conduit-demo:$1-$PAIR_DEMO_VERSION}"
}

# demo_distro DISTRO: the demo image's distribution for a PC's DISTRO; nothing
# for Humble (its Zenoh wire format and Servo interface do not fit the demo).
demo_distro() {
  case "$1" in
    jazzy | kilted | lyrical) say "$1" ;;
    rolling) say lyrical ;;
    *) ;;
  esac
}

# bounded SECONDS COMMAND...: run COMMAND and stop it after SECONDS; its status,
# or 124 when it had to be stopped. Keeps a stuck Docker from hanging the script.
bounded() {
  local secs="$1" pid ticks=0
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2> /dev/null; do
    if ((ticks >= secs * 10)); then
      kill "$pid" 2> /dev/null || true
      wait "$pid" 2> /dev/null || true
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait "$pid"
}

# tcp_open HOST PORT: 0 when HOST:PORT accepts a TCP connection. Only in a
# subshell of its own (bounded runs it so): the connect is that process, so
# stopping it stops the connect, and nothing else holds the caller's stdout.
tcp_open() {
  exec 2> /dev/null 3<> "/dev/tcp/$1/$2"
}

# free_port FIRST LAST [SKIP]: echoes the first port from FIRST to LAST that
# nothing on this PC accepts connections on and that is not SKIP.
free_port() {
  local port
  for ((port = $1; port <= $2; port++)); do
    if [[ "$port" != "${3:-}" ]] && ! bounded 2 tcp_open 127.0.0.1 "$port"; then
      say "$port"
      return 0
    fi
  done
  return 1
}

docker_desktop_app() { printf '%s\n' "$(env_root)/Applications/Docker.app"; }

# check_docker: sets PAIR_DOCKER to ok, missing, denied (the daemon refuses
# this user) or down (no daemon answers).
check_docker() {
  local err app
  app="$(docker_desktop_app)"
  if ! command -v docker > /dev/null 2>&1; then
    # Docker Desktop puts its CLI on PATH once it has run; the app carries one.
    if [[ -x "$app/Contents/Resources/bin/docker" ]]; then
      PATH="$PATH:$app/Contents/Resources/bin"
    else
      PAIR_DOCKER=missing
      return 0
    fi
  fi
  if err="$(bounded 20 docker info 2>&1 > /dev/null)"; then
    PAIR_DOCKER=ok
  elif [[ "$err" == *"permission denied"* ]]; then
    PAIR_DOCKER=denied
  else
    PAIR_DOCKER=down
  fi
}

# docker_problem: what is wrong with Docker (PAIR_DOCKER) and what to do.
docker_problem() {
  case "$PAIR_DOCKER" in
    missing)
      if is_macos; then
        say "Docker was not found: install Docker Desktop ($PAIR_DOCKER_DESKTOP_URL)"
      else
        say "Docker was not found: install it ($PAIR_DOCKER_INSTALL_URL)"
      fi
      ;;
    denied)
      say "Docker refuses this user: add yourself to the docker group (sudo usermod -aG docker \$USER), then log out and back in"
      ;;
    *)
      if is_macos; then
        say "Docker is not running: start Docker Desktop (or your Docker runtime, such as OrbStack or Colima)"
      else
        say "The Docker daemon is not running: start it (sudo systemctl start docker)"
      fi
      ;;
  esac
}

# demo_docker_ready: Docker works, or the script stops (exit 1) with what to do.
# On a Mac with Docker Desktop installed but not running, offers to start it.
demo_docker_ready() {
  local limit="${PAIR_DOCKER_START_SECONDS:-120}" deadline
  check_docker
  if [[ "$PAIR_DOCKER" == down ]] && is_macos && [[ -d "$(docker_desktop_app)" ]]; then
    ask_yes_no "Docker Desktop is not running. Start it now?" y ||
      die 1 "Start Docker Desktop and run this script again."
    open -a Docker || die 1 "Could not start Docker Desktop. Start it and run this script again."
    say "Waiting for Docker Desktop to start... (Ctrl+C to quit)"
    deadline=$((SECONDS + limit))
    check_docker
    while [[ "$PAIR_DOCKER" != ok ]] && ((SECONDS < deadline)); do
      sleep 2
      check_docker
    done
    [[ "$PAIR_DOCKER" == ok ]] ||
      die 1 "Docker Desktop did not start within $limit seconds. Wait until it runs and run this script again."
  fi
  [[ "$PAIR_DOCKER" != ok ]] || return 0
  if [[ "$PAIR_DOCKER" == missing ]] && ! is_macos; then
    die 1 "$(docker_problem) and run this script again for the demo, or install ROS 2 to pair with this PC: $PAIR_INSTALL_URL"
  fi
  die 1 "$(docker_problem), and run this script again."
}

# demo_container_state: "<running> <image> <network mode>" of the conduit-demo
# container, or nothing when there is none.
demo_container_state() {
  bounded 20 docker inspect --format '{{.State.Running}} {{.Config.Image}} {{.HostConfig.NetworkMode}}' \
    "$PAIR_DEMO_CONTAINER" 2> /dev/null || true
}

# demo_published_port PORT: the host port the demo container publishes PORT on.
demo_published_port() {
  local line
  line="$(bounded 20 docker port "$PAIR_DEMO_CONTAINER" "$1/tcp" 2> /dev/null | head -n1 || true)"
  [[ -z "$line" ]] || say "${line##*:}"
}

# demo_container_env NAME: the value of NAME in the demo container's environment.
demo_container_env() {
  bounded 20 docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$PAIR_DEMO_CONTAINER" 2> /dev/null |
    sed -n "s/^$1=//p" | head -n1 || true
}

# demo_remove: remove a stopped conduit-demo container (never a running one).
demo_remove() {
  bounded 20 docker rm "$PAIR_DEMO_CONTAINER" > /dev/null 2>&1 || true
}

# demo_force_remove: remove the demo container this run started, running or not.
demo_force_remove() {
  bounded 30 docker rm -f "$PAIR_DEMO_CONTAINER" > /dev/null 2>&1 || true
}

# demo_run ARGS...: `docker run ARGS...` for the demo container, stopped after
# PAIR_DOCKER_RUN_SECONDS (60). On failure, sets PAIR_DEMO_RUN_ERROR and
# force-removes what the run may have left (a created container, or one the
# daemon started after the time ran out), unless the name belongs to another
# container.
demo_run() {
  local limit="${PAIR_DOCKER_RUN_SECONDS:-60}" err status=0
  err="$(bounded "$limit" docker run "$@" 2>&1 > /dev/null)" || status=$?
  ((status)) || return 0
  if ((status == 124)); then
    PAIR_DEMO_RUN_ERROR="docker run did not finish within $limit seconds"
  else
    PAIR_DEMO_RUN_ERROR="${err:-docker run failed}"
  fi
  [[ "$err" == *"is already in use"* ]] || demo_force_remove
  return 1
}

# demo_pull IMAGE: 0 once IMAGE is on this PC, downloading it the first time.
demo_pull() {
  if bounded 20 docker image inspect "$1" > /dev/null 2>&1; then
    return 0
  fi
  say "Downloading the demo image $1 (a few GB, only the first time)..."
  docker pull "$1"
}

# demo_logs: the demo container's log (stdout and stderr).
demo_logs() {
  bounded 20 docker logs "$PAIR_DEMO_CONTAINER" 2>&1 || true
}

# demo_wait_router: 0 once the demo container's Zenoh router runs. Docker's
# published port accepts connections before the router inside listens, so the
# log decides. Returns 1 if the container stops or the router never starts.
demo_wait_router() {
  local limit="${PAIR_DEMO_START_SECONDS:-90}" deadline first=1 log
  deadline=$((SECONDS + limit))
  while ((SECONDS < deadline)); do
    log="$(demo_logs)"
    [[ "$log" != *"Started Zenoh router"* ]] || return 0
    if [[ "$(demo_container_state)" != true* ]]; then
      say "The demo container stopped. The end of its log:"
      tail -n 5 <<< "$log" | sed 's/^/  /'
      return 1
    fi
    if ((first)); then say "Waiting for the demo's Zenoh router..."; fi
    first=0
    sleep 1
  done
  say "The demo's Zenoh router did not start within $limit seconds. The end of its log:"
  tail -n 5 <<< "$log" | sed 's/^/  /'
  return 1
}

# demo_causes: why no check-in arrived on the demo path. Docker publishes the
# demo's ports past ufw and firewalld, so they are not listed.
demo_causes() {
  say "No check-in from the iPhone yet. Things to check:"
  if [[ "${PAIR_VIA:-lan}" == tailscale ]]; then
    say "- Open the Tailscale app on the iPhone and connect it to the same tailnet as this PC."
  else
    say "- The iPhone must be on the same Wi-Fi as this PC."
    say "- Guest and office Wi-Fi often isolate clients from each other (client isolation); try another network or a hotspot."
    say "- Allow Local Network access for Conduit: iPhone Settings > Privacy & Security > Local Network."
  fi
  if is_macos; then
    say "- If the macOS firewall is on, let Docker accept incoming connections: System Settings > Network > Firewall > Options."
  fi
  say "- Scan the QR again if Conduit did not open from it."
}

# demo_next_steps [joined]: adding the demo robots in Conduit, and how to stop
# them. `joined`: the demo runs on this PC's graph, whose names it checked only
# when it started.
demo_next_steps() {
  say ""
  say "Next, add the two demo robots in Conduit: Add robot, then Start fills in each profile."
  say "  1. Tap the robot button, then +. Leave Kind on Mobile robot, name it, tap Start, then Save."
  say "  2. Tap + again. Set Kind to Arm, name it, tap Start, then Save."
  say "  3. Open either robot to drive it."
  say "The demo keeps running after this script ends. To stop it:"
  say "  $PAIR_DEMO_STOP"
  if [[ "${1:-}" == joined ]]; then
    say "The demo checked this PC's ROS 2 names once, when it started."
    say "Stop the demo ($PAIR_DEMO_STOP) before you start your own robot on this PC."
  fi
  PAIR_DEMO_HINTED=1
}

# demo_exit_hint: when this run started or used the demo container
# (PAIR_DEMO_IN_USE), the script ends before the next steps and the container
# still runs, says how to stop it.
demo_exit_hint() {
  [[ "${PAIR_DEMO_IN_USE:-0}" == 1 && "${PAIR_DEMO_HINTED:-0}" != 1 ]] || return 0
  PAIR_DEMO_HINTED=1
  if [[ "$(demo_container_state)" == true* ]]; then
    say "The demo keeps running (container $PAIR_DEMO_CONTAINER). To stop it: $PAIR_DEMO_STOP"
  fi
}

# show_pairing LINK NO_QR: the QR code (unless NO_QR) and the link, and what to do.
show_pairing() {
  show_link "$1" "$2"
  if (($2)); then
    say "Open the link on the iPhone. Waiting for Conduit to check in..."
  else
    say "Scan the QR with the iPhone's Camera app. Waiting for Conduit to check in..."
  fi
}

# demo_path LINK_STYLE NO_QR CHECKIN_PORT: pair with the demo container, started
# here or already running (no ROS 2 on this PC). Exits.
demo_path() {
  local link_style="$1" no_qr="$2" first_checkin="$3" image state running="" cimage="" net=""
  local router="" checkin="" token link started=0
  PAIR_DEMO_PATH=1
  PAIR_RMW=zenoh
  PAIR_DOMAIN=0
  check_terminal
  pick_address
  demo_docker_ready

  image="$(demo_image lyrical)"
  state="$(demo_container_state)"
  if [[ -n "$state" ]]; then
    read -r running cimage net <<< "$state"
    if [[ "$running" == true && "$cimage" == "$image" && "$net" != host ]]; then
      router="$(demo_published_port 7447)"
      checkin="$(demo_published_port 7449)"
    fi
    if [[ -n "$router" && -n "$checkin" ]]; then
      say "The demo is already running (container $PAIR_DEMO_CONTAINER); pairing with it."
      PAIR_DEMO_IN_USE=1
    elif [[ "$running" == true ]]; then
      die 1 "Another $PAIR_DEMO_CONTAINER container is running ($cimage). Stop it ($PAIR_DEMO_STOP) and run this script again."
    else
      demo_remove
    fi
  fi
  if [[ -z "$router" || -z "$checkin" ]]; then
    demo_pull "$image" || die 1 "Could not download the demo image $image."
    router="$(free_port 7447 7457)" ||
      die 1 "Ports 7447-7457 are all in use on this PC. Free one and run this script again."
    checkin="$(free_port "$first_checkin" $((first_checkin + 10)) "$router")" ||
      die 1 "Ports $first_checkin-$((first_checkin + 10)) are all in use on this PC. Free one and run this script again."
    say "Starting the demo robots (container $PAIR_DEMO_CONTAINER)..."
    demo_run -d --name "$PAIR_DEMO_CONTAINER" -p "$router:7447" -p "$checkin:7449" "$image" standalone ||
      die 1 "The demo container did not start: $PAIR_DEMO_RUN_ERROR"
    started=1
    PAIR_DEMO_IN_USE=1
  fi
  if ! demo_wait_router; then
    # A container this run started goes; a reused one is the user's to stop.
    if ((started)); then
      demo_force_remove
      say "Removed the demo container this run started."
    elif [[ "$(demo_container_state)" == true* ]]; then
      say "The demo container keeps running. To stop it: $PAIR_DEMO_STOP"
      PAIR_DEMO_HINTED=1
    fi
    exit 1
  fi
  # The iPhone reaches the router at this PC's address, so this PC must too.
  if ! bounded 3 tcp_open "$PAIR_HOST" "$router"; then
    say "This PC could not connect to the demo at $PAIR_HOST:$router, so the iPhone cannot either:"
    say "- Docker may publish the demo's ports on 127.0.0.1 only, as Colima and some OrbStack setups do. Docker Desktop publishes them on every address."
    say "- A firewall may block the port."
  fi

  # The container has python3 for the QR code and the check-in listener.
  PAIR_PYTHON=(docker exec -i "$PAIR_DEMO_CONTAINER" python3)
  token="$(new_token)"
  start_checkin "$token" 7449
  [[ "$PAIR_CHECKIN_PORT" == 7449 ]] ||
    die 1 "Another pairing with the demo is still waiting. Close it and run this script again."
  link="$(build_link "$link_style" zenoh lyrical 0 "$PAIR_HOST" "$router" "$PAIR_HOST:$checkin" "$token" "$(hostname)")"
  show_pairing "$link" "$no_qr"
  wait_checkin || die 2 "The check-in listener stopped before the iPhone checked in."
  # Docker Desktop hides the iPhone's address from the container.
  say "$PAIR_DEVICE checked in."
  demo_next_steps
  exit 0
}

# demo_wait_join: wait for the joined demo's name check. A conflict (exit 3),
# a failure to join (exit 1) or no result within PAIR_DEMO_START_SECONDS (90)
# removes the container and says why; sets PAIR_DEMO_ADDED=1 once the check
# passes.
demo_wait_join() {
  local limit="${PAIR_DEMO_START_SECONDS:-90}" deadline first=1 log state line
  deadline=$((SECONDS + limit))
  while ((SECONDS < deadline)); do
    log="$(demo_logs)"
    if [[ "$log" == *"check_conflicts: no conflicts"* ]]; then
      say "The demo robots are starting on this PC's graph."
      PAIR_DEMO_ADDED=1
      return 0
    fi
    state="$(bounded 20 docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' "$PAIR_DEMO_CONTAINER" 2> /dev/null || true)"
    case "$state" in
      exited* | dead*)
        # The log read above may predate the exit: read the whole of it now.
        log="$(demo_logs)"
        if [[ "${state##* }" == 3 ]]; then
          say "This PC's ROS 2 graph already uses these names of the demo robots:"
          while IFS= read -r line; do
            if [[ "$line" == "CONFLICT "* ]]; then say "  ${line#CONFLICT }"; fi
          done <<< "$log"
          say "The demo robots were not added, so they cannot disturb what runs here."
        else
          say "The demo robots could not join this PC's ROS 2 graph. The end of their log:"
          tail -n 5 <<< "$log" | sed 's/^/  /'
          say "The demo robots were not added."
        fi
        demo_remove
        return 0
        ;;
      *) ;;
    esac
    if ((first)); then say "Checking that this PC's graph does not use the demo's names..."; fi
    first=0
    sleep 1
  done
  say "The demo's name check did not finish within $limit seconds. The end of its log:"
  tail -n 5 <<< "$log" | sed 's/^/  /'
  # demo_join started this container: it goes.
  demo_force_remove
  say "The demo robots were not added (their container was removed)."
}

# demo_join: --demo on a PC with ROS 2. Starts the demo robots on this PC's
# graph: host network, this PC's RMW and domain, and on Zenoh a client of this
# PC's router. Never stops the pairing: a problem skips the demo and says why.
demo_join() {
  local distro image state running="" cimage="" net="" rmw args entry rest
  PAIR_DEMO_ADDED=0
  distro="$(demo_distro "$PAIR_DISTRO")"
  if [[ -z "$distro" ]]; then
    say "The demo robots need ROS 2 Jazzy or later, so they are not added on Humble."
    return 0
  fi
  image="$(demo_image "$distro")"
  case "$PAIR_RMW" in
    zenoh) rmw=rmw_zenoh_cpp ;;
    cyclonedds) rmw=rmw_cyclonedds_cpp ;;
    *) rmw=rmw_fastrtps_cpp ;;
  esac
  check_docker
  if [[ "$PAIR_DOCKER" != ok ]]; then
    say "$(docker_problem)."
    say "The demo robots were not added; run this script again to add them."
    return 0
  fi
  state="$(demo_container_state)"
  if [[ -n "$state" ]]; then
    read -r running cimage net <<< "$state"
    if [[ "$running" == true && "$cimage" == "$image" && "$net" == host &&
      "$(demo_container_env RMW_IMPLEMENTATION)" == "$rmw" &&
      "$(demo_container_env ROS_DOMAIN_ID)" == "$PAIR_DOMAIN" ]]; then
      say "The demo robots are already running on this PC's graph (container $PAIR_DEMO_CONTAINER)."
      PAIR_DEMO_ADDED=1
      PAIR_DEMO_IN_USE=1
      return 0
    elif [[ "$running" == true ]]; then
      say "A $PAIR_DEMO_CONTAINER container is running, but not on this PC's graph with $image."
      say "Stop it ($PAIR_DEMO_STOP) and run this script again to add the demo robots."
      say "The demo robots were not added."
      return 0
    fi
    demo_remove
  fi
  if ! demo_pull "$image"; then
    say "Could not download the demo image $image. The demo robots were not added."
    return 0
  fi
  args=(-d --name "$PAIR_DEMO_CONTAINER" --network host -e "RMW_IMPLEMENTATION=$rmw" -e "ROS_DOMAIN_ID=$PAIR_DOMAIN")
  if [[ "$PAIR_RMW" == zenoh ]]; then
    args+=(-e 'ZENOH_CONFIG_OVERRIDE=mode="client";connect/endpoints=["tcp/127.0.0.1:7447"]')
  elif [[ "$PAIR_RMW" == cyclonedds && -n "${CYCLONEDDS_URI:-}" ]]; then
    args+=(-e "CYCLONEDDS_URI=$CYCLONEDDS_URI")
    # The files it names, at the same paths in the container.
    rest="$CYCLONEDDS_URI,"
    while [[ -n "$rest" ]]; do
      entry="${rest%%,*}"
      rest="${rest#*,}"
      if [[ "$entry" == file://* && -f "${entry#file://}" ]]; then
        args+=(-v "${entry#file://}:${entry#file://}:ro")
      fi
    done
  fi
  args+=("$image" join)
  say "Starting the demo robots on this PC's ROS 2 graph (container $PAIR_DEMO_CONTAINER)..."
  if ! demo_run "${args[@]}"; then
    say "The demo container did not start: $PAIR_DEMO_RUN_ERROR"
    say "The demo robots were not added."
    return 0
  fi
  PAIR_DEMO_IN_USE=1
  demo_wait_join
}

# source_ros SETUP: source a ROS 2 setup.bash into this script. ROS's setup
# scripts read unset variables and run commands that may fail.
source_ros() {
  set +eu +o pipefail
  # shellcheck disable=SC1090
  . "$1"
  set -eu -o pipefail
}

# demo_takes_container_path: --demo picks its path. 0 for the demo path (a Mac,
# or Linux without ROS 2); 1 to pair natively, after sourcing the ROS 2 in
# /opt/ros when this shell has none (asking which when there are several).
demo_takes_container_path() {
  local root setup setups=() names=() idx
  is_macos && return 0
  # Other systems are refused as without --demo.
  [[ "${PAIR_UNAME:-$(uname -s)}" == Linux ]] || return 1
  check_not_wsl
  check_not_container
  [[ -z "${ROS_DISTRO:-}" ]] || return 1
  root="$(env_root)"
  while IFS= read -r setup; do
    [[ -z "$setup" ]] || setups+=("$setup")
  done < <(find "$root/opt/ros" -mindepth 2 -maxdepth 2 -name setup.bash 2> /dev/null | sort)
  ((${#setups[@]})) || return 0
  idx=${#setups[@]}
  if ((idx > 1)); then
    for setup in "${setups[@]}"; do
      setup="${setup%/setup.bash}"
      names+=("${setup##*/}")
    done
    check_terminal
    idx="$(choose "Several ROS 2 distributions are installed. Which ROS 2 should this PC use?" "$idx" "${names[@]}")"
  fi
  setup="${setups[idx - 1]}"
  say "Using ROS 2 from /${setup#"$root"/}."
  source_ros "$setup"
  return 1
}

usage() {
  cat << 'USAGE'
Usage: pair.sh [options]
  (or: curl -fsSL https://conduit.direct/pair.sh | bash -s -- [options])

Pairs an iPhone running Conduit with this ROS 2 PC: shows a QR code, waits for
Conduit to check in, prepares this PC and checks that messages arrive.

Options:
  --lan                 Pair over the local network (skip Tailscale).
  --tailscale           Pair over Tailscale (Zenoh only).
  --checkin-port N      TCP port for the iPhone's check-in (default 7449).
  --link-style S        https (default) or custom (conduit://pair links).
  --no-qr               Print the link only, without the QR code.
  -h, --help            Show this help.

Exit status: 0 connected, 1 not supported or declined, 2 not connected,
130 interrupted.
USAGE
}

# Prompts read the terminal because stdin is the script itself.
check_terminal() {
  if ! { : < "${PAIR_TTY:-/dev/tty}"; } 2> /dev/null; then
    die 1 "This script needs a terminal for its questions; run it in an interactive shell."
  fi
}

new_token() {
  head -c 9 /dev/urandom | base64 | tr '+/' '-_'
}

# DDS: add the iPhone as a discovery peer here and print what other shells need.
apply_host_peers() {
  local required exports
  case "$PAIR_RMW" in
    cyclonedds) required="$HOST_PEERS_REQUIRED_CYCLONEDDS" ;;
    fastdds) required="$HOST_PEERS_REQUIRED_FASTDDS" ;;
    *) return 0 ;;
  esac
  if [[ "$required" != true ]] &&
    ! ask_yes_no "Add the iPhone ($PAIR_PHONE_IP) as a discovery peer on this PC?" n; then
    return 0
  fi
  if ! exports="$(host_peer_config "$PAIR_PHONE_IP")"; then
    warn "Could not write $HOME/.config/conduit, so this PC was not given the iPhone as a discovery peer."
    warn "Check that $HOME/.config is a writable directory and run this script again."
    return 0
  fi
  if [[ -n "$exports" ]]; then
    # The lines are built by export_line, so they are safe to evaluate here.
    eval "$exports"
    say "Shells that run ROS 2 nodes with the iPhone need:"
    say "$exports"
    if ask_yes_no "Add this to ~/.bashrc?" n; then
      if bashrc_with_block "$HOME/.bashrc" "$exports"; then
        say "Added to ~/.bashrc."
      else
        warn "Could not update ~/.bashrc; add the lines above to it by hand."
      fi
    fi
  fi
  say "$RESTART_NOTE"
}

main() {
  local link_style=https no_qr=0 checkin_port="$PAIR_DEFAULT_CHECKIN_PORT" demo=0
  local transport=dds port="" token link
  PAIR_FORCE_VIA=""
  while (($#)); do
    case "$1" in
      --lan) PAIR_FORCE_VIA=lan ;;
      --tailscale) PAIR_FORCE_VIA=tailscale ;;
      --checkin-port)
        if [[ ! "${2:-}" =~ ^[0-9]{1,5}$ ]] || ((10#$2 < 1 || 10#$2 > 65535)); then
          die 1 "--checkin-port needs a port number (1-65535)."
        fi
        checkin_port=$((10#$2))
        shift
        ;;
      --link-style)
        case "${2:-}" in
          https | custom) link_style="$2" ;;
          *) die 1 "--link-style must be https or custom." ;;
        esac
        shift
        ;;
      --no-qr) no_qr=1 ;;
      # Hidden until Conduit 3.0, so it is not in usage.
      --demo) demo=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die 1 "Unknown option: $1"
        ;;
    esac
    shift
  done
  trap 'exit 130' INT
  trap pair_exit EXIT

  if ((demo)) && demo_takes_container_path; then
    demo_path "$link_style" "$no_qr" "$checkin_port"
  fi
  check_environment
  check_terminal
  pick_address

  if [[ "$PAIR_VIA" == tailscale && "$PAIR_RMW" != zenoh ]]; then
    tailscale_needs_zenoh
    exit 1
  fi
  case "$PAIR_RMW" in
    zenoh)
      transport=zenoh
      port=7447
      if ! zenoh_router_listening "$port"; then
        say "The Zenoh router is not running."
        if ! { ask_yes_no "Start it now in the background?" y && start_zenoh_router "$port"; }; then
          say "Start it in another terminal:"
          say "  ros2 run rmw_zenoh_cpp rmw_zenohd"
          say "Waiting for it on port $port... (Ctrl+C to quit)"
          until zenoh_router_listening "$port"; do sleep 1; done
        fi
      fi
      ;;
    fastdds)
      fastdds_warning
      ask_yes_no "Continue with Fast DDS?" y || exit 1
      ;;
    *) ;;
  esac
  # The flag is the answer to "also add the demo robots?", asked before the QR.
  if ((demo)); then
    demo_join
  fi

  token="$(new_token)"
  start_checkin "$token" "$checkin_port"
  link="$(build_link "$link_style" "$transport" "$PAIR_DISTRO" "$PAIR_DOMAIN" "$PAIR_HOST" "$port" \
    "$PAIR_HOST:$PAIR_CHECKIN_PORT" "$token" "$(hostname)")"
  show_pairing "$link" "$no_qr"
  wait_checkin || die 2 "The check-in listener stopped before the iPhone checked in."
  say "$PAIR_DEVICE checked in from $PAIR_PHONE_IP."

  if [[ "$transport" == dds ]]; then
    apply_host_peers
  fi

  if ! wait_for_node "$PAIR_NODE" "$PAIR_NAMESPACE" 300; then
    causes no_node
    exit 2
  fi
  if ! wait_for_data 20; then
    causes no_data
    exit 2
  fi
  say "Connected to $PAIR_DEVICE."
  if [[ "${PAIR_DEMO_ADDED:-0}" == 1 ]]; then
    demo_next_steps joined
  fi
  exit 0
}

[[ "${CONDUIT_PAIR_SOURCED:-0}" == 1 ]] || main "$@"
