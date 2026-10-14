#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvviewer/th.sh -- test-host stack control for the GUI gate (tools/fvviewer/gui.sh).
#
#   th.sh <statedir> up <relay-port> [<tls-port>]   start relay (+ socat TLS terminator "localhost"), then host
#   th.sh <statedir> host-kill                      kill ONLY the Rust test host (the relay stays)
#   th.sh <statedir> host-start                     start the host again (same HOME => same ID)
#   th.sh <statedir> down                           stop everything
#   th.sh <statedir> id                             print the host ID (9 or 10 digits)
#
# The state dir holds: home/ (host config, keeps the ID), relay.cjs, logs, pids. Needs node, socat, openssl,
# FV_BIN (Rust binary, default /root/abbilder/fv-testhost/freeviewer) and the freeviewer repo (FVV_RUST_REPO).
set -uo pipefail
S=${1:?statedir}; CMD=${2:?command}; shift 2
FVBIN=${FV_BIN:-/root/abbilder/fv-testhost/freeviewer}
FVREPO=${FVV_RUST_REPO:-/root/projects/freeviewer}
TLSTERM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tlsterm.py"
PW=${FV_TH_PASSWORD:-testpass123}
mkdir -p "$S/home"
host_start() {
    # an old host process must be gone (its ID stays registered at the relay, that is fine)
    ( cd "$S"; HOME="$S/home" FV_RELAY="ws://127.0.0.1:$(cat "$S/relay.port")/fv/ws" FV_ALLOW_INSECURE_RELAY=1 \
        FV_TESTHOST=1 FV_AUTOCONFIRM=1 FV_PASSWORD="$PW" FV_TESTHOST_LOG="$S/input.log" \
        nohup "$FVBIN" --headless >>"$S/host.log" 2>&1 & echo $! > "$S/host.pid" ) >/dev/null 2>&1 </dev/null
    for _ in $(seq 1 100); do
        id=$(grep -oE '^ID [0-9]{9,10}' "$S/host.log" | tail -1 | cut -d' ' -f2)
        [ -n "$id" ] && { echo "$id" > "$S/id"; return 0; }
        sleep 0.2
    done
    return 1
}
case "$CMD" in
up)
    RP=${1:?relay port}; TP=${2:-}
    echo "$RP" > "$S/relay.port"
    cp "$FVREPO/relay/relay.js" "$S/relay.cjs"
    # relay.js requires its helper modules (client IP, request auth) next to it
    for m in clientip.js reqauth.js; do [ -f "$FVREPO/relay/$m" ] && cp "$FVREPO/relay/$m" "$S/$m"; done
    ( cd "$S"; FV_PORT="$RP" FV_DATA="$S/hosts.json" nohup node "$S/relay.cjs" >"$S/relay.log" 2>&1 & echo $! > "$S/relay.pid" ) >/dev/null 2>&1 </dev/null
    for _ in $(seq 1 50); do curl -fsS "http://127.0.0.1:$RP/fv/health" >/dev/null 2>&1 && break; sleep 0.1; done
    curl -fsS "http://127.0.0.1:$RP/fv/health" >/dev/null || { echo "relay did not start"; exit 1; }
    if [ -n "$TP" ]; then
        # test CA + server certificate for "localhost" (ECDSA P-256, SHA-256); the guest trusts only this CA file
        python3 -I "$(dirname "$TLSTERM")/mkcerts.py" "$S" || { echo "mkcerts failed"; exit 1; }
        ( nohup python3 -I "$TLSTERM" "$TP" "$RP" "$S/chain.pem" "$S/srv.key" >"$S/socat.log" 2>&1 & echo $! > "$S/socat.pid" ) >/dev/null 2>&1 </dev/null
        sleep 0.5
    fi
    host_start || { echo "host did not register"; tail -5 "$S/host.log"; exit 1; }
    cat "$S/id" ;;
host-kill)
    [ -f "$S/host.pid" ] && kill "$(cat "$S/host.pid")" 2>/dev/null
    sleep 0.3
    echo killed ;;
host-start) host_start && cat "$S/id" ;;
id) cat "$S/id" ;;
down)
    for f in host relay socat; do [ -f "$S/$f.pid" ] && kill "$(cat "$S/$f.pid")" 2>/dev/null; done
    exit 0 ;;
*) echo "unknown command $CMD" >&2; exit 2 ;;
esac
