#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvviewer/th.sh -- test-host stack control for the GUI gate (tools/fvviewer/gui.sh).
#
#   th.sh <statedir> up <relay-port> [<tls-port>]   start relay (+ socat TLS terminator "localhost"), then host
#   th.sh <statedir> host-kill                      kill ONLY the Rust test host (the relay stays)
#   th.sh <statedir> host-start                     start the host again (same HOME => same ID)
#   th.sh <statedir> down                           stop everything
#   th.sh <statedir> id                             print the 9 digit host ID
#
# The state dir holds: home/ (host config, keeps the ID), relay.cjs, logs, pids. Needs node, socat, openssl,
# FV_BIN (Rust binary, default /root/abbilder/fv-testhost/freeviewer) and the freeviewer repo (FVV_RUST_REPO).
set -uo pipefail
S=${1:?statedir}; CMD=${2:?command}; shift 2
FVBIN=${FV_BIN:-/root/abbilder/fv-testhost/freeviewer}
FVREPO=${FVV_RUST_REPO:-/root/projects/freeviewer}
PW=${FV_TH_PASSWORD:-testpass123}
mkdir -p "$S/home"
host_start() {
    # an old host process must be gone (its ID stays registered at the relay, that is fine)
    ( cd "$S" && HOME="$S/home" FV_RELAY="ws://127.0.0.1:$(cat "$S/relay.port")/fv/ws" FV_ALLOW_INSECURE_RELAY=1 \
        FV_TESTHOST=1 FV_AUTOCONFIRM=1 FV_PASSWORD="$PW" FV_TESTHOST_LOG="$S/input.log" \
        nohup "$FVBIN" --headless >>"$S/host.log" 2>&1 & echo $! > "$S/host.pid" )
    for _ in $(seq 1 100); do
        id=$(grep -oE '^ID [0-9]{9}' "$S/host.log" | tail -1 | cut -d' ' -f2)
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
    ( cd "$S" && FV_PORT="$RP" FV_DATA="$S/hosts.json" nohup node "$S/relay.cjs" >"$S/relay.log" 2>&1 & echo $! > "$S/relay.pid" )
    for _ in $(seq 1 50); do curl -fsS "http://127.0.0.1:$RP/fv/health" >/dev/null 2>&1 && break; sleep 0.1; done
    curl -fsS "http://127.0.0.1:$RP/fv/health" >/dev/null || { echo "relay did not start"; exit 1; }
    if [ -n "$TP" ]; then
        # test CA + server certificate for "localhost" (ECDSA P-256, SHA-256); the guest trusts only this CA file
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3 -subj "/CN=fvv test CA" \
            -keyout "$S/ca.key" -out "$S/ca.pem" 2>/dev/null
        openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -subj "/CN=localhost" \
            -keyout "$S/srv.key" -out "$S/srv.csr" 2>/dev/null
        printf 'subjectAltName=DNS:localhost\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\n' > "$S/ext"
        openssl x509 -req -in "$S/srv.csr" -CA "$S/ca.pem" -CAkey "$S/ca.key" -CAcreateserial -days 2 -sha256 \
            -extfile "$S/ext" -out "$S/srv.pem" 2>/dev/null
        cat "$S/srv.pem" > "$S/chain.pem"
        ( nohup socat OPENSSL-LISTEN:"$TP",reuseaddr,fork,cert="$S/chain.pem",key="$S/srv.key",verify=0 \
            TCP:127.0.0.1:"$RP" >"$S/socat.log" 2>&1 & echo $! > "$S/socat.pid" )
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
