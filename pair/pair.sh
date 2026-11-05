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

# Draw the QR for LINK (or write a PBM with --pbm). Embedded encoder: a trimmed
# copy of Nayuki's qrcodegen.py, Python 3 standard library only.
py_qr() {
  python3 - "$@" <<'PY'
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
    elif command -v python3 > /dev/null 2>&1; then
      py_qr "$link"
    else
      warn "python3 not found: skipping the QR code."
    fi
  fi
  say "Or open this link on the iPhone:"
  say "$link"
}

# Embedded check-in listener. Python 3 standard library only. It runs as a
# coprocess (see start_checkin), so the code travels as an argument, not stdin.
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
    # The coprocess stdin is a pipe from the script; EOF means the script is gone.
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

# start_checkin TOKEN PORT: run the listener as the CHECKIN coprocess and set
# PAIR_CHECKIN_PORT to the port it bound. Its output is read through a copy of
# the coprocess fd (PAIR_CHECKIN_FD): bash closes CHECKIN[0] once the
# listener exits, and the copy keeps what it wrote before that readable.
start_checkin() {
  local token="$1" port="$2" line
  command -v python3 > /dev/null 2>&1 || die 1 "python3 is required to receive the iPhone's check-in."
  coproc CHECKIN { exec python3 -u -c "$CHECKIN_PY" "$token" "$port"; }
  exec {PAIR_CHECKIN_FD}<&"${CHECKIN[0]}"
  trap stop_checkin EXIT
  read -r line <&"$PAIR_CHECKIN_FD" || die 1 "The check-in listener did not start."
  [[ "$line" =~ ^PORT=([0-9]+)$ ]] || die 1 "The check-in listener did not report a port."
  PAIR_CHECKIN_PORT="${BASH_REMATCH[1]}"
}

stop_checkin() {
  if [[ -n "${CHECKIN_PID:-}" ]]; then
    kill "$CHECKIN_PID" 2> /dev/null || true
    wait "$CHECKIN_PID" 2> /dev/null || true
    CHECKIN_PID=""
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
  say "  sudo apt install ros-${PAIR_DISTRO}-rmw-cyclonedds-cpp"
  say "  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
}

tailscale_needs_zenoh() {
  say "Tailscale works with Zenoh only. To switch this shell to Zenoh:"
  say "  export RMW_IMPLEMENTATION=rmw_zenoh_cpp"
  say "  ros2 run rmw_zenoh_cpp rmw_zenohd    # in another terminal"
  say "If rmw_zenoh_cpp is missing:"
  say "  sudo apt install ros-${PAIR_DISTRO}-rmw-zenoh-cpp"
  say "Then run this script again in that shell."
}

# export_line NAME VALUE: a single-quoted export line that survives any value.
export_line() {
  local q="'" esc="'\\''"
  printf "export %s='%s'\n" "$1" "${2//"$q"/"$esc"}"
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
  local status=()
  {
    # Unbuffered so the first message reaches grep at once; --foreground keeps
    # ros2 in this terminal's process group so Ctrl-C ends the wait.
    PYTHONUNBUFFERED=1 timeout --foreground "$1" ros2 topic echo --qos-durability transient_local --qos-reliability reliable \
      /tf_static tf2_msgs/msg/TFMessage 2> /dev/null | grep -q -m1 'frame_id: conduit_base_link'
    status=("${PIPESTATUS[@]}")
  } || true
  return "${status[1]}"
}

ufw_enabled() {
  grep -Eq '^[[:space:]]*ENABLED[[:space:]]*=[[:space:]]*yes' "$(env_root)/etc/ufw/ufw.conf" 2> /dev/null
}

# causes STAGE (no_checkin|no_node|no_data): what to check, firewall first.
causes() {
  local stage="$1" dds_port=$((7400 + 250 * PAIR_DOMAIN))
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
  local link_style=https no_qr=0 checkin_port="$PAIR_DEFAULT_CHECKIN_PORT"
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

  token="$(new_token)"
  start_checkin "$token" "$checkin_port"
  link="$(build_link "$link_style" "$transport" "$PAIR_DISTRO" "$PAIR_DOMAIN" "$PAIR_HOST" "$port" \
    "$PAIR_HOST:$PAIR_CHECKIN_PORT" "$token" "$(hostname)")"
  show_link "$link" "$no_qr"
  if ((no_qr)); then
    say "Open the link on the iPhone. Waiting for Conduit to check in..."
  else
    say "Scan the QR with the iPhone's Camera app. Waiting for Conduit to check in..."
  fi
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
  exit 0
}

[[ "${CONDUIT_PAIR_SOURCED:-0}" == 1 ]] || main "$@"
