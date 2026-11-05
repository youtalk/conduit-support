load helpers

setup() { load_script; }

DDS='https://conduit.direct/pair#v=1&transport=dds&distro=jazzy&domain=123&host=192.168.1.85&checkin=192.168.1.85%3A7449&token=Zk3q9cA1bT0x&name=youtalk-desktop'
ZENOH='https://conduit.direct/pair#v=1&transport=zenoh&distro=lyrical&domain=0&host=100.101.102.103&port=7447&checkin=100.101.102.103%3A7449&token=Zk3q9cA1bT0x&name=robot%20pc'

@test "golden DDS link" {
  run build_link https dds jazzy 123 192.168.1.85 "" 192.168.1.85:7449 Zk3q9cA1bT0x youtalk-desktop
  [ "$status" -eq 0 ]
  [ "$output" = "$DDS" ]
}

@test "golden Zenoh link" {
  run build_link https zenoh lyrical 0 100.101.102.103 7447 100.101.102.103:7449 Zk3q9cA1bT0x "robot pc"
  [ "$status" -eq 0 ]
  [ "$output" = "$ZENOH" ]
}

@test "custom style" {
  run build_link custom dds jazzy 123 192.168.1.85 "" 192.168.1.85:7449 Zk3q9cA1bT0x youtalk-desktop
  [ "$output" = "conduit://pair#${DDS#*#}" ]
}

@test "name is cut to 64" {
  long="$(printf 'a%.0s' {1..80})"
  run build_link https dds jazzy 123 10.0.0.1 "" 10.0.0.1:7449 Zk3q9cA1bT0x "$long"
  [ "${output##*name=}" = "$(printf 'a%.0s' {1..64})" ]
}

@test "link is printed even with --no-qr" {
  run show_link "$DDS" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Or open this link on the iPhone:"* ]]
  [[ "$output" == *"$DDS"* ]]
  [[ "$output" != *"█"* ]]
}

@test "qrencode is preferred when installed" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho STUB\n' > "$BATS_TEST_TMPDIR/bin/qrencode"
  chmod +x "$BATS_TEST_TMPDIR/bin/qrencode"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run show_link "$DDS" 0
  [[ "$output" == *STUB* ]]
  [[ "$output" == *"$DDS"* ]]
}
