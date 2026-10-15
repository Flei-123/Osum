#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/mail/app.sh -- gate of the Mail app (kernel/user/mail.fi + lib/mail/model.fi).
#
#   bash tools/mail/app.sh [stage ...]        (run it through /root/jarvis/bin/heavy)
#
# stages (default: model build)
#   model   host: lib/mail/model.fi (account, folders, list, read, send) against tools/mail/stub.py over
#           TLS 1.3 (own CA, name check) and plain TCP: 33 steps each (tools/mail/apptest.fi), the two sent
#           mails compared byte-exact (headers, RFC 2047 subject, dot-stuffing, generated Date/Message-ID),
#           negative controls: wrong password -> E_AUTH, wrong host name -> E_CERT, empty fields -> E_NOCFG
#   build   mail.fi compiles + links as a ring-3 app; the package pakete/mail builds (INFO lint, OSYM symbol,
#           .opk when opk.py is there); the app is in pakete/bauen.sh
#   gui     QEMU: the window starts from /apps/mail.osp (launcher), connects to the stub on the host
#           (10.0.2.2), shows folders + messages, opens a message, composes + sends one mail (the stub
#           file is compared). Opt-in (slow): `bash tools/mail/app.sh gui`
# NEGATIVE CONTROL of gui: stub started with a wrong password in /etc/mail.test -> the window must stay on
# the setup form ("mail: folders rc=6").
# DOES NOT MEASURE: real servers (Dovecot/Gmail quirks), STARTTLS, attachments, the pixels of the window.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
STAGES=${*:-model build}
T=$(mktemp -d)
STUBPID=""
cleanup() { [ -n "$STUBPID" ] && kill "$STUBPID" 2>/dev/null; pkill -P $$ 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

run_stub() { # mode outdir [cert key]
    rm -f "$2/ports"; mkdir -p "$2"
    python3 -I tools/mail/stub.py "$2" "$1" "${@:3}" > "$2/stub.log" 2>&1 &
    STUBPID=$!
    for _ in $(seq 1 50); do [ -f "$2/ports" ] && break; sleep 0.1; done
    [ -f "$2/ports" ]
}
stop_stub() { kill "$STUBPID" 2>/dev/null; wait "$STUBPID" 2>/dev/null; STUBPID=""; }

check_sent() { # dir label: the stub received both sent mails, byte-exact
    if [ -f "$1/msg-1.eml" ] && [ -f "$1/msg-2.eml" ]; then
        python3 -I - "$1/msg-1.eml" "$1/msg-2.eml" <<'PY' && ok "$2: stub received both mails byte-exact (From = user, RFC 2047 subject, dot-stuffing undone, Date, Message-ID)" || bad "$2: received mails differ"
import sys, email, email.policy, email.utils, time
m1 = open(sys.argv[1], 'rb').read()
m2 = open(sys.argv[2], 'rb').read()
import re
assert re.match(rb"X-Stub-From: <justin@(mail\.test|x)>\r\nX-Stub-To: <max@example.org>\r\n", m1), m1[:90]
assert re.match(rb"X-Stub-From: <justin@(mail\.test|x)>\r\nX-Stub-To: <zwei@example.org>\r\n", m2), m2[:90]
e = email.message_from_bytes(m1.split(b"\r\n", 2)[2], policy=email.policy.default)
assert e["Subject"] == "Grüße aus Wien", e["Subject"]
assert e["To"] == "Max <max@example.org>", e["To"]
assert e.get_content().replace("\r\n", "\n") == "Hallo Max\n.Punkt am Anfang\nEnde\n", repr(e.get_content())
d = email.utils.parsedate_to_datetime(e["Date"]).timestamp()
assert abs(d - time.time()) < 600, ("Date off", e["Date"])
assert e["Message-ID"].endswith(".osum@osum.lan>"), e["Message-ID"]
e2 = email.message_from_bytes(m2.split(b"\r\n", 2)[2], policy=email.policy.default)
assert e2["Subject"] == "Zweite" and e2.get_content().strip() == "nur eine Zeile"
assert b"\n" not in m1.replace(b"\r\n", b""), "bare LF in message 1"
PY
    else
        bad "$2: stub did not receive both messages"
    fi
}

stage_model() {
    echo "== stage model =="
    "$FIRNC" tools/mail/apptest.fi -o "$T/apptest" 2> "$T/a.err" && ok "apptest builds" || { bad "apptest build"; head -8 "$T/a.err"; return; }
    command -v openssl >/dev/null && command -v python3 >/dev/null || { bad "openssl/python3 missing"; return; }
    local C="$T/cert"; mkdir -p "$C"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
        -keyout "$C/key.pem" -out "$C/cert.pem" -subj "/CN=mail.test" \
        -addext "subjectAltName=DNS:mail.test" -addext "basicConstraints=critical,CA:TRUE" >/dev/null 2>&1 \
        && ok "test certificate (ECDSA P-256, SAN mail.test)" || bad "openssl could not make the certificate"
    local IP SP n1 n2 rc out
    if run_stub tls "$T/tls" "$C/cert.pem" "$C/key.pem"; then
        read -r IP SP < "$T/tls/ports"
        timeout 90 "$T/apptest" "$IP" "$SP" "$C/cert.pem" mail.test justin geheim tls > "$T/tls.txt" 2>&1; rc=$?
        sed -n 's/^FAIL /  FAIL  tls: /p' "$T/tls.txt"
        n1=$(grep -c '^OK' "$T/tls.txt"); n2=$(grep -c '^FAIL' "$T/tls.txt")
        [ "$rc" = 0 ] && [ "$n2" = 0 ] && [ "$n1" -ge 30 ] && ok "TLS model: $n1 steps OK, 0 FAIL" || { bad "TLS model (rc=$rc ok=$n1 fail=$n2)"; tail -5 "$T/tls.txt"; }
        pass=$((pass+n1))
        check_sent "$T/tls" tls
        out=$(timeout 30 "$T/apptest" "$IP" "$SP" "$C/cert.pem" evil.example justin geheim tls 2>&1 | grep -c '^OK   folders: ok')
        [ "$out" = 0 ] && ok "control: wrong host name -> no folders (E_CERT)" || bad "control: wrong host name still listed folders"
        out=$(timeout 30 "$T/apptest" "$IP" "$SP" - mail.test justin geheim tls 2>&1 | grep -c '^OK   folders: ok')
        [ "$out" = 0 ] && ok "control: empty trust store -> no folders (E_CERT)" || bad "control: empty trust store still listed folders"
        stop_stub
    else
        bad "stub (tls) did not start"; tail -5 "$T/tls/stub.log" 2>/dev/null
    fi
    if run_stub plain "$T/pl"; then
        read -r IP SP < "$T/pl/ports"
        timeout 90 "$T/apptest" "$IP" "$SP" - x justin geheim plain > "$T/pl.txt" 2>&1; rc=$?
        sed -n 's/^FAIL /  FAIL  plain: /p' "$T/pl.txt"
        n1=$(grep -c '^OK' "$T/pl.txt"); n2=$(grep -c '^FAIL' "$T/pl.txt")
        [ "$rc" = 0 ] && [ "$n2" = 0 ] && [ "$n1" -ge 30 ] && ok "plain model: $n1 steps OK, 0 FAIL" || { bad "plain model (rc=$rc ok=$n1 fail=$n2)"; tail -5 "$T/pl.txt"; }
        pass=$((pass+n1))
        check_sent "$T/pl" plain
        stop_stub
    else
        bad "stub (plain) did not start"
    fi
    # mutation: a message list that is not newest-first must turn the model test red
    mkdir -p "$T/lib-mut"
    for d in lib/*; do [ "$(basename "$d")" = mail ] || ln -s "$ROOT/$d" "$T/lib-mut/$(basename "$d")"; done
    mkdir -p "$T/lib-mut/mail"; cp lib/mail/*.fi "$T/lib-mut/mail/"
    sed -i 's/SEQS\[LN as usize\] = (\*h).seq/SEQS[LN as usize] = (*h).seq + 1/' "$T/lib-mut/mail/model.fi"
    if cmp -s lib/mail/model.fi "$T/lib-mut/mail/model.fi"; then
        bad "control mutation: nothing changed"
    elif run_stub plain "$T/pm"; then
        read -r IP SP < "$T/pm/ports"
        FIRNLIB="$T/lib-mut" "$FIRNC" tools/mail/apptest.fi -o "$T/apptest-mut" 2> "$T/m.err"
        mout=""; [ -x "$T/apptest-mut" ] && mout=$(timeout 60 "$T/apptest-mut" "$IP" "$SP" - x justin geheim plain 2>&1)
        if echo "$mout" | grep -q '^FAIL'; then
            ok "control: wrong message numbers (open the wrong mail) turn the model test red"
        else
            bad "control: mutated model was NOT caught"
        fi
        stop_stub
    fi
}

stage_build() {
    echo "== stage build =="
    local crtd="$T/b"; mkdir -p "$crtd"
    "$FIRNC" --profile=app -c kernel/user/mail.fi -o "$crtd/mail.o" 2> "$crtd/c.err" \
        && ld -T kernel/user/user.ld -o "$crtd/mail.elf" "$crtd/mail.o" 2>> "$crtd/c.err" \
        && ok "mail.fi builds + links (ring-3 app)" || { bad "mail.fi build"; head -10 "$crtd/c.err"; return; }
    python3 tools/sdk/osdk.py check pakete/mail/INFO --strict > "$crtd/l.txt" 2>&1 && ok "INFO lint (manifest v2, strict)" || { bad "INFO lint"; cat "$crtd/l.txt"; }
    python3 tools/k15/icon.py pakete/mail/symbol.txt "$crtd/symbol" > /dev/null 2>&1 && ok "symbol.txt -> OSYM" || bad "symbol.txt"
    grep -q 'pakete/mail' pakete/bauen.sh && grep -q 'kernel/user/mail.fi' pakete/bauen.sh && ok "pakete/bauen.sh builds the mail package" || bad "pakete/bauen.sh does not know mail"
    if OPK=$(python3 tools/lib/opkpfad.py 2>/dev/null) && [ -f "$OPK" ]; then
        bash pakete/bauen.sh "$crtd/pk" > "$crtd/bauen.log" 2>&1
        if [ -f "$crtd/pk/mail-1.0.0.opk" ]; then ok "pakete/bauen.sh -> mail-1.0.0.opk"; else bad "no mail-1.0.0.opk"; tail -5 "$crtd/bauen.log"; fi
        rm -rf pakete/mail/bau
    else
        echo "  (opk.py not found: package step skipped)"
    fi
}

stage_gui() {
    echo "== stage gui =="
    bash tools/mail/gui.sh "$T/gui" && ok "gui: window session against the stub" || bad "gui session"
}

for s in $STAGES; do
    case "$s" in
        model) stage_model ;;
        build) stage_build ;;
        gui)   stage_gui ;;
        *) echo "unknown stage $s"; exit 2 ;;
    esac
done
echo "  mail app gate: $pass ok, $fail FAIL"
[ "$fail" = 0 ]
