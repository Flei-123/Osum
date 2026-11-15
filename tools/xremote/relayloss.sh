#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HOSTBIN=${XR_HOST:-/root/jarvis/data/staff_wt/orientos/fv-host/target/x86_64-unknown-linux-musl/release/freeviewer-host}
OLDBIN=${XR_OLD_HOST:-/root/jarvis/data/orientos-xremote/v2/freeviewer-host}
LIBS=${XR_LIBS_DIR:-/root/fxhp/fx-root}
RELAYDIR=${XR_RELAY:-/root/projects/freeviewer/relay}
NODEPATH=${XR_LIBS:-/root/jarvis/node_modules}
LDMUSL=$LIBS/lib/ld-musl-x86_64.so.1
LIBDIR=$LIBS/usr/lib
PORT=$((18000 + $$ % 1000))
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
chk() { if [ "$1" = 1 ]; then ok "$2"; else bad "$2"; fi; }
for f in "$HOSTBIN" "$LDMUSL" "$RELAYDIR/relay.js"; do
    [ -e "$f" ] || { echo "RELAYLOSS: skipped, $f missing"; exit 0; }
done
command -v node >/dev/null 2>&1 || { echo "RELAYLOSS: skipped, node missing"; exit 0; }
T=$(mktemp -d)
RP=""; HP=""
cleanup() {
    [ -n "$HP" ] && kill -9 "$HP" 2>/dev/null
    [ -n "$RP" ] && { kill -CONT "$RP" 2>/dev/null; kill -9 "$RP" 2>/dev/null; }
    rm -rf "$T"
}
trap cleanup EXIT
mkdir -p "$T/relay" "$T/home/.config/freeviewer"
printf '%s' "$(printf 'cd%.0s' $(seq 1 32))" > "$T/home/.config/freeviewer/identity.txt"
cp "$RELAYDIR"/*.js "$T/relay/"
start_relay() {
    (cd "$T/relay" && NODE_PATH="$NODEPATH" FV_PORT=$PORT FV_DATA="$T/relay/hosts.json" FV_BUCH=0 exec node relay.js >> "$T/relay.log" 2>&1) &
    RP=$!
    sleep 2
}
kill_relay() { kill -CONT "$RP" 2>/dev/null; kill -9 "$RP" 2>/dev/null; wait "$RP" 2>/dev/null; RP=""; }
start_host() {
    local bin=$1; shift
    printf 'TESTPW12' > "$T/pw"
    (cd "$T" && HOME="$T/home" FV_RETRY_SEK=1 FV_PING_SEK=2 FV_STILL_SEK=6 FV_ALLOW_INSECURE_RELAY=1 FV_NOP2P=1 "$@" \
        "$LDMUSL" --library-path "$LIBDIR" "$bin" --password-file "$T/pw" --state-file "$T/state" --home "$T/home" --no-p2p \
        --relay "ws://127.0.0.1:$PORT/fv/ws" --insecure-relay >> "$T/host.log" 2>&1) &
    HP=$!
}
stop_host() { kill -9 "$HP" 2>/dev/null; wait "$HP" 2>/dev/null; HP=""; rm -f "$T/state"; }
state_id() { sed -n 's/^id=//p' "$T/state" 2>/dev/null | head -1; }
online() {
    local id; id=$(state_id)
    [ -n "$id" ] || id=$(cat "$T/lastid" 2>/dev/null)
    curl -s -m 3 "http://127.0.0.1:$PORT/fv/online?ids=$id" 2>/dev/null | grep -q '"online":true' && echo 1 || echo 0
}
wait_for() {
    local cmd=$1 max=$2 i=0
    while [ $i -lt "$max" ]; do
        [ "$(eval "$cmd")" = 1 ] && return 0
        sleep 1; i=$((i + 1))
    done
    return 1
}
is_ready() { [ -n "$(state_id)" ] && [ "$(online)" = 1 ] && echo 1 || echo 0; }
is_offline() { [ -z "$(state_id)" ] && [ -s "$T/state" ] && echo 1 || echo 0; }
is_alive() { kill -0 "$HP" 2>/dev/null && echo 1 || echo 0; }

echo "== 1. baseline =="
start_relay
kill -0 "$RP" 2>/dev/null && ok "relay up on port $PORT" || bad "relay did not start"
start_host "$HOSTBIN"
wait_for is_ready 40 && ok "host registered, relay says online" || bad "host never became ready: $(tail -n 3 "$T/host.log" | tr '\n' ';')"
state_id > "$T/lastid"
ID=$(cat "$T/lastid")
echo "$ID" | grep -qE '^[0-9]+$' && ok "host has ID $ID" || bad "no host ID"

echo "== 2. relay killed hard, then back =="
kill_relay
wait_for is_offline 25 && ok "host drops the ID and reports offline after the relay died" || bad "host still claims ready: $(cat "$T/state" 2>/dev/null | tr '\n' ';')"
[ "$(is_alive)" = 1 ] && ok "host process keeps running" || bad "host process died"
HPID=$HP
start_relay
wait_for is_ready 40 && ok "host re-registers on its own, relay says online again" || bad "host did not come back: $(tail -n 3 "$T/host.log" | tr '\n' ';')"
[ "$HP" = "$HPID" ] && [ "$(is_alive)" = 1 ] && ok "same host process, no restart needed" || bad "host process changed"

echo "== 3. silent line (relay frozen, TCP stays open) =="
kill -STOP "$RP"
wait_for is_offline 30 && ok "silent relay: host notices within the heartbeat window and goes offline" || bad "silent relay: host still says ready: $(cat "$T/state" 2>/dev/null | tr '\n' ';')"
kill -CONT "$RP"
wait_for is_ready 40 && ok "relay thawed: host is online again" || bad "host did not recover after thaw"
kill_relay
start_relay
wait_for is_ready 40 && ok "relay restarted after freeze: host online again" || bad "host did not recover after restart"

echo "== 4. counter-probe: heartbeat switched off =="
stop_host
start_host "$HOSTBIN" env FV_PING_SEK=100000 FV_STILL_SEK=100000
wait_for is_ready 40 && ok "control host without heartbeat registers" || bad "control host never ready"
kill -STOP "$RP"
sleep 15
[ -n "$(state_id)" ] && ok "without heartbeat the frozen line is NOT noticed (this is the failure the gate catches)" || bad "counter-probe: host noticed the freeze without a heartbeat"
kill -CONT "$RP"
stop_host

echo "== 5. watchdog flags =="
start_host "$HOSTBIN" env FV_STALL_SEK=1 FV_DEAD_SEK=2
wait_for is_ready 40 && ok "host with tight watchdog limits stays ready while its runtime is healthy" || bad "tight watchdog host not ready"
sleep 8
[ "$(is_alive)" = 1 ] && [ -n "$(state_id)" ] && ok "healthy runtime is never aborted by the watchdog" || bad "watchdog killed a healthy host"
stop_host

echo
echo "RELAYLOSS: $pass ok, $fail fail"
[ "$fail" = 0 ]
