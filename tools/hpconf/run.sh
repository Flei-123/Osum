#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
CONF=assets/jarvis/rechte-hp.conf
BUILD=tools/usbimg/build.sh
need() { python3 -I tools/hpconf/check.py "$1" "$BUILD"; }
need "$CONF" > "$T/a.txt" 2>&1 && ok "HP bridge config: act/svc allowed and shipped, mini config readable, no secrets readable" || { bad "HP bridge config"; cat "$T/a.txt"; }
grep -v 'command_allowed = /bin/act' "$CONF" > "$T/noact.conf"
need "$T/noact.conf" > /dev/null 2>&1 && bad "counter-proof: missing /bin/act not caught" || ok "counter-proof: missing /bin/act is caught"
{ cat "$CONF"; echo 'read            = /etc/shadow'; } > "$T/shadow.conf"
need "$T/shadow.conf" > /dev/null 2>&1 && bad "counter-proof: readable /etc/shadow not caught" || ok "counter-proof: readable /etc/shadow is caught"
{ cat "$CONF"; echo 'command_sub_allowed = /bin/drvctl remove'; } > "$T/inst.conf"
need "$T/inst.conf" > /dev/null 2>&1 && bad "counter-proof: drvctl remove allowed not caught" || ok "counter-proof: drvctl remove allowed is caught"
grep -v 'command_sub_allowed = /bin/drvctl' "$CONF" > "$T/nosub.conf"
need "$T/nosub.conf" > /dev/null 2>&1 && bad "counter-proof: drvctl without sub rules not caught" || ok "counter-proof: drvctl without sub rules is caught"
need_dev() { python3 -I tools/hpconf/check.py "$1" "$BUILD" --dev; }
DEVCONF=assets/jarvis/rechte-hp-dev.conf
need_dev "$DEVCONF" > "$T/d.txt" 2>&1 && ok "dev config passes the HP rules (with --dev)" || { bad "dev config"; cat "$T/d.txt"; }
need "$DEVCONF" > /dev/null 2>&1 && bad "counter-proof: dev config accepted as the normal HP config" || ok "counter-proof: devmode in the normal HP config is caught"
{ cat "$CONF"; echo 'devmode = yes'; } > "$T/dm.conf"
need "$T/dm.conf" > /dev/null 2>&1 && bad "counter-proof: devmode in rechte-hp.conf not caught" || ok "counter-proof: devmode in rechte-hp.conf is caught"
DD=$(diff "$CONF" "$DEVCONF" || true)
[ "$(printf '%s\n' "$DD" | grep -c '^[<>]')" = 5 ] && printf '%s\n' "$DD" | grep '^>' | tr -d ' ' | sort | tr '\n' ' ' | grep -q '>devmode=yes >input=yes >screenshot=always' && ok "dev config = HP config plus devmode/screenshot/input only" || bad "dev config drifted from rechte-hp.conf"
grep -q "JM_AUTOSTART='jmini --as-app'" "$BUILD" && grep -q 'HP_STICK:-0}" = 1 \] && \[ "${JM_HIDDEN' "$BUILD" && ok "HP stick autostarts the Mini visible (JM_HIDDEN=1 keeps it hidden)" || bad "HP autostart rule missing"
echo "HPCONF: $pass ok / $fail fail"
[ "$fail" -eq 0 ]
