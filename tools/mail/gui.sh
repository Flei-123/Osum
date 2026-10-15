#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/mail/gui.sh <outdir> -- QEMU GUI session of the Mail window (called by tools/mail/app.sh gui).
#
# Stage A (tls): the launcher starts /apps/mail.osp/start, the account is pre-filled from /etc/mail.test
# (10.0.2.2 = the host, stub.py over TLS 1.3, test CA /etc/mail-ca.pem, name mail.test), "Verbinden" ->
# folders (2) + INBOX list (3), click a row -> the message is read, "Neu" -> To / Subject / text typed ->
# "Senden" -> the stub received the mail. Stage B (plain, wrong password): the window must stay on the
# setup form ("folders rc=6", no "list"). Run through /root/jarvis/bin/heavy.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:?outdir}
mkdir -p "$OUT"
RES=${GUI_RES:-1280x800}
BUILD=$(mktemp -d)
STUBPID=""
trap '[ -n "$STUBPID" ] && kill "$STUBPID" 2>/dev/null; rm -rf "$BUILD"; pkill -P $$ 2>/dev/null' EXIT
rc_all=0
bad() { echo "  FAIL  gui: $1"; rc_all=1; }
ok()  { echo "  OK    gui: $1"; }

if [ -z "${DRIVE_TIPPE_GAP:-}" ]; then
    LOAD1=$(cut -d. -f1 /proc/loadavg)
    if [ "$LOAD1" -ge 40 ]; then DRIVE_TIPPE_GAP=0.8; elif [ "$LOAD1" -ge 20 ]; then DRIVE_TIPPE_GAP=0.5; else DRIVE_TIPPE_GAP=0.3; fi
fi
export DRIVE_TIPPE_GAP

start_stub() { # mode dir [cert key]
    rm -f "$2/ports"; mkdir -p "$2"
    python3 -I tools/mail/stub.py "$2" "$1" "${@:3}" > "$2/stub.log" 2>&1 &
    STUBPID=$!
    for _ in $(seq 1 50); do [ -f "$2/ports" ] && break; sleep 0.1; done
    [ -f "$2/ports" ]
}
stop_stub() { [ -n "$STUBPID" ] && kill "$STUBPID" 2>/dev/null; wait "$STUBPID" 2>/dev/null; STUBPID=""; }

# one QEMU run: name mode(tls|plain) password script-body
run_guest() {
    local name=$1 mode=$2 pw=$3 body=$4
    local O="$OUT/$name"; mkdir -p "$O"
    local C="$O/cert"; mkdir -p "$C"
    if [ "$mode" = tls ]; then
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
            -keyout "$C/key.pem" -out "$C/cert.pem" -subj "/CN=mail.test" \
            -addext "subjectAltName=DNS:mail.test" -addext "basicConstraints=critical,CA:TRUE" >/dev/null 2>&1 || { bad "$name: certificate"; return 1; }
        start_stub tls "$O/stub" "$C/cert.pem" "$C/key.pem" || { bad "$name: stub"; return 1; }
        cp "$C/cert.pem" "$O/ca.pem"
    else
        start_stub plain "$O/stub" || { bad "$name: stub"; return 1; }
        : > "$O/ca.pem"
    fi
    local IPORT SPORT; read -r IPORT SPORT < "$O/stub/ports"
    echo "10.0.2.2 $IPORT $SPORT $mode justin $pw mail.test" > "$O/mail.test"
    cat > "$O/script.txt" <<SCR
warteauf 'launcher: ready' || 90
warte 4
taste meta_l
warte 2
foto 05-launcher
klickauf start_Mail
warteaufmuss 'mail: rect name=go' || 60
warte 2
foto 10-setup
klickauf mailrectgo
$body
SCR
    local EXTRA="/apps/ /apps/mail.osp/ /apps/mail.osp/INFO=pakete/mail/INFO@0644 /apps/mail.osp/start@/bin/mail"
    DESIGNBUILD="$BUILD" EH_APPEND=rtcutc EH_APP_PROGS=mail EH_MKFS_EXTRA="/etc/mail.test=$O/mail.test@0644 /etc/mail-ca.pem=$O/ca.pem@0644 $EXTRA" \
        timeout 1500 bash tools/design/eh6.sh "$O/out" "res=$RES" accel=kvm netz=ja moreprogs=mail tafel=nein "drehbuch=$O/script.txt" > "$O/eh6.log" 2>&1
    stop_stub
    grep -a 'FEHLGESCHLAGEN\|NICHT DA\|Traceback' "$O/eh6.log" | head -5
    grep -aq 'mail: test mode on' "$O/out/serial.txt" 2>/dev/null || { echo "  (mail did not start in the guest)"; return 7; }
    return 0
}

S="$OUT/serial-check"
want() { # name file regex
    grep -aqE "$3" "$2" && ok "$1" || bad "$1 (no line /$3/)"
}

# ---------------------------------------------------------------- stage A
TXT_TO="max@example.org"; TXT_SUBJ="Gruss"; TXT_BODY="Hallo aus OrientOS"
BODY_A=$(cat <<SCR
warteaufmuss 'mail: folders rc=0 n=2' || 120
warteaufmuss 'mail: list rc=0 n=3' || 90
warte 3
foto 20-main
klickauf mailpt50x40
warteaufmuss 'mail: read rc=0' || 90
warte 3
foto 30-read
klickauf mailrectnew
warteaufmuss 'mail: state compose' || 30
warte 2
klickauf mailrectto
warte 2
klickauf mailrectto
warte 1
tippe $TXT_TO
warte 1
klickauf mailrectsubj
warte 1
klickauf mailrectsubj
warte 1
tippe $TXT_SUBJ
warte 1
klickauf mailrecttxt
warte 1
klickauf mailrecttxt
warte 1
tippe $TXT_BODY
warte 1
foto 40-compose
klickauf mailrectsend
warteaufmuss 'mail: send rc=' || 120
warte 3
foto 50-sent
SCR
)
attempt=0
while :; do
    attempt=$((attempt+1))
    run_guest A tls geheim "$BODY_A"; r=$?
    if [ $r = 7 ] && [ $attempt -lt 3 ]; then echo "  (retry $attempt)"; continue; fi
    [ $r = 0 ] || { bad "A: guest run (rc=$r)"; break; }
    SER="$OUT/A/out/serial.txt"
    # typing guard: the guest drops keys under load -> wrong run, retry
    first=$(grep -a -m1 'mail: send start' "$SER" 2>/dev/null)
    want_len="to_len=${#TXT_TO} subj_len=${#TXT_SUBJ} body_len=${#TXT_BODY}"
    case "$first" in
        *"$want_len"*) ;;
        *) if [ $attempt -lt 3 ]; then echo "  (typing check failed: '${first:-no send line}', wanted $want_len; retry)"; continue; fi
           bad "A: typing check ($first)" ;;
    esac
    want "A: setup form shown"            "$SER" 'mail: state setup'
    want "A: TLS login + 2 folders"       "$SER" 'mail: folders rc=0 n=2'
    want "A: INBOX list has 3 messages"   "$SER" 'mail: list rc=0 n=3'
    want "A: main view shown"             "$SER" 'mail: state main'
    want "A: a clicked row was read"      "$SER" 'mail: read rc=0 len=[1-9][0-9]+'
    want "A: compose view shown"          "$SER" 'mail: state compose'
    want "A: mail sent (SMTP rc 0)"       "$SER" 'mail: send rc=0'
    if [ -f "$OUT/A/stub/msg-1.eml" ]; then
        python3 -I - "$OUT/A/stub/msg-1.eml" "$TXT_TO" "$TXT_SUBJ" "$TXT_BODY" <<'PY' && ok "A: the stub received the typed mail (To, Subject, body)" || bad "A: stub mail differs"
import sys, email, email.policy
raw = open(sys.argv[1], 'rb').read()
e = email.message_from_bytes(raw.split(b"\r\n", 2)[2], policy=email.policy.default)
assert sys.argv[2] in e["To"], e["To"]
assert e["Subject"] == sys.argv[3], e["Subject"]
assert e.get_content().strip() == sys.argv[4], repr(e.get_content())
PY
    else
        bad "A: the stub got no mail"
    fi
    break
done

# ---------------------------------------------------------------- stage B (negative control)
attempt=0
while :; do
    attempt=$((attempt+1))
    run_guest B plain falsch "warteaufmuss 'mail: folders rc=' || 120
warte 4
foto 20-after"; r=$?
    if [ $r = 7 ] && [ $attempt -lt 3 ]; then echo "  (retry $attempt)"; continue; fi
    [ $r = 0 ] || { bad "B: guest run (rc=$r)"; break; }
    SER="$OUT/B/out/serial.txt"
    want "B (control): wrong password -> E_AUTH (rc=6)" "$SER" 'mail: folders rc=6'
    grep -aq 'mail: list rc=' "$SER" && bad "B (control): list was loaded despite the wrong password" || ok "B (control): no list after a refused login"
    grep -aq 'mail: state main' "$SER" && bad "B (control): window left the setup form" || ok "B (control): window stays on the setup form"
    break
done
exit $rc_all
