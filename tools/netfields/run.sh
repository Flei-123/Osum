#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
shift || true
CASES=${*:-fixed1 fixed2 dhcp1}
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for c in $CASES; do
  case "$c" in
    fixed1) SC=1; RES=1280x800; CONF='modus=fest\nip=192.168.7.42\nmaske=255.255.255.0\ngateway=192.168.7.1\ndns=192.168.7.53\n' ;;
    fixed2) SC=2; RES=2560x1600; CONF='modus=fest\nip=192.168.7.42\nmaske=255.255.255.0\ngateway=192.168.7.1\ndns=192.168.7.53\n' ;;
    dhcp1)  SC=1; RES=1280x800; CONF='modus=dhcp\n' ;;
    *) echo "unknown case $c"; exit 2 ;;
  esac
  D="$OUT/$c"; mkdir -p "$D"
  printf "$CONF" > "$D/network.conf"
  DREH="$D-drehbuch.txt"
  {
    echo "warte 12"
    echo "klick 24,$(( ${RES#*x} - 20 ))"; echo "warte 4"
    echo "klickauf start_Settings"; echo "warte 12"
    echo "foto 00-settings"
    echo "klickauf srecttabd"; echo "warte 3"
    echo "foto 01-network"
  } > "$DREH"
  export DESIGNBUILD="$D-build"
  AUDIT_MKFS_EXTRA="/etc/network.conf=$D/network.conf@0644" \
    bash tools/design/audit.sh "$D" accel=kvm uitrace=yes halt=300 res=$RES uiscale="$SC" drehbuch="$DREH" > "$D.log" 2>&1
  rm -rf "$D-build" "$DREH"
  unset DESIGNBUILD
  echo "== $c"
  S="$D/serial.txt"
  case "$c" in
    fixed*)
      grep -aq 'settings: net fields ip=192.168.7.42 mask=255.255.255.0 gw=192.168.7.1 dns=192.168.7.53' "$S" && ok "$c: fields filled from /etc/network.conf" || bad "$c: fields not filled"
      ;;
    dhcp*)
      grep -aq 'settings: net fields' "$S" && bad "$c: fields filled in automatic mode" || ok "$c: automatic mode leaves fields alone"
      grep -aq 'settings: live dns=10.0.2.3' "$S" && ok "$c: DNS field shows the live resolver" || bad "$c: DNS field has no live resolver"
      ;;
  esac
  grep -aiq 'panic\|exception' "$S" && bad "$c: panic" || ok "$c: no panic"
done
echo "NETFIELDS: $pass ok, $fail fail"
[ "$fail" = 0 ]
