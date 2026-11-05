#!/usr/bin/env bats

load helpers

setup() {
  load_script
  make_fixture
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  PATH="$STUBS:$PATH"
  export PATH
  PAIR_FORCE_VIA=""
  PAIR_TTY="$BATS_TEST_TMPDIR/tty"
  : > "$PAIR_TTY"
  export PAIR_TTY
}

# stub_ip ROUTE_OUTPUT ADDR_OUTPUT: fake `ip route get` / `ip addr show`.
stub_ip() {
  printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/route.out"
  printf '%s\n' "$2" > "$BATS_TEST_TMPDIR/addr.out"
  cat > "$STUBS/ip" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *route*) cat "$BATS_TEST_TMPDIR/route.out" ;;
  *addr*) cat "$BATS_TEST_TMPDIR/addr.out" ;;
esac
STUB
  chmod +x "$STUBS/ip"
}

ROUTE='1.1.1.1 via 192.168.1.1 dev wlp130s0f0 src 192.168.1.85 uid 1000'
ADDRS='1: lo    inet 127.0.0.1/8 scope host lo
2: enp3s0    inet 10.0.0.7/24 brd 10.0.0.255 scope global enp3s0
3: wlp130s0f0    inet 192.168.1.85/24 brd 192.168.1.255 scope global dynamic wlp130s0f0
4: docker0    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
5: br-1a2b3c    inet 172.18.0.1/16 scope global br-1a2b3c
6: veth12ab    inet 172.19.0.1/16 scope global veth12ab
7: virbr0    inet 192.168.122.1/24 scope global virbr0
8: cni0    inet 10.244.0.1/24 scope global cni0
9: flannel.1    inet 10.244.1.0/32 scope global flannel.1
10: tailscale0    inet 100.101.102.103/32 scope global tailscale0'

@test "parses ip route get" {
  run parse_route_get <<< "$ROUTE"
  [ "$status" -eq 0 ]
  [ "$output" = "192.168.1.85 wlp130s0f0" ]
}

@test "parses ip addr show" {
  run parse_addr_show <<< "$ADDRS"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "lo 127.0.0.1" ]]
  [[ "$output" == *"wlp130s0f0 192.168.1.85"* ]]
  [[ "$output" == *"tailscale0 100.101.102.103"* ]]
}

@test "default route first" {
  stub_ip "$ROUTE" "$ADDRS"
  run lan_candidates
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "wlp130s0f0 192.168.1.85" ]
  [ "${lines[1]}" = "enp3s0 10.0.0.7" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "container bridges are ignored" {
  stub_ip "$ROUTE" "$ADDRS"
  run lan_candidates
  [[ "$output" != *docker0* ]]
  [[ "$output" != *br-* ]]
  [[ "$output" != *veth* ]]
  [[ "$output" != *virbr* ]]
  [[ "$output" != *cni* ]]
  [[ "$output" != *flannel* ]]
  [[ "$output" != *"lo "* ]]
}

@test "tailscale is separate" {
  stub_ip "$ROUTE" "$ADDRS"
  run lan_candidates
  [[ "$output" != *100.101.102.103* ]]
  run tailscale_address
  [ "$status" -eq 0 ]
  [ "$output" = "100.101.102.103" ]
}

@test "tailscale_address prefers the tailscale command" {
  stub_ip "$ROUTE" "$ADDRS"
  printf '#!/usr/bin/env bash\necho 100.64.0.9\n' > "$STUBS/tailscale"
  chmod +x "$STUBS/tailscale"
  run tailscale_address
  [ "$output" = "100.64.0.9" ]
}

@test "tailscale_address is empty without tailscale" {
  stub_ip "$ROUTE" "$(grep -v tailscale0 <<< "$ADDRS")"
  run tailscale_address
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--tailscale without tailscale fails" {
  stub_ip "$ROUTE" "$(grep -v tailscale0 <<< "$ADDRS")"
  PAIR_FORCE_VIA=tailscale
  run pick_address
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tailscale"* ]]
}

@test "single candidate needs no question" {
  stub_ip "$ROUTE" '3: wlp130s0f0    inet 192.168.1.85/24 scope global wlp130s0f0'
  pick_address
  [ "$PAIR_HOST" = "192.168.1.85" ]
  [ "$PAIR_VIA" = lan ]
}

@test "--lan with several candidates asks and honors the answer" {
  stub_ip "$ROUTE" "$ADDRS"
  PAIR_FORCE_VIA=lan
  echo 2 > "$PAIR_TTY"
  pick_address 2> /dev/null
  [ "$PAIR_HOST" = "10.0.0.7" ]
  [ "$PAIR_VIA" = lan ]
}

@test "--tailscale uses the tailscale address" {
  stub_ip "$ROUTE" "$ADDRS"
  PAIR_FORCE_VIA=tailscale
  pick_address
  [ "$PAIR_HOST" = "100.101.102.103" ]
  [ "$PAIR_VIA" = tailscale ]
}

@test "LAN and Tailscale both present asks which one" {
  stub_ip "$ROUTE" "$ADDRS"
  echo 3 > "$PAIR_TTY"
  pick_address 2> /dev/null
  [ "$PAIR_HOST" = "100.101.102.103" ]
  [ "$PAIR_VIA" = tailscale ]
}

@test "only Tailscale available is used without a question" {
  stub_ip "" '10: tailscale0    inet 100.101.102.103/32 scope global tailscale0'
  pick_address
  [ "$PAIR_VIA" = tailscale ]
  [ "$PAIR_HOST" = "100.101.102.103" ]
}

@test "no address at all fails" {
  stub_ip "" ''
  run pick_address
  [ "$status" -eq 1 ]
}
