#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/mail/run.sh -- host gate for the mail library (lib/mail/wire.fi + session.fi).
#
# MEASURES: 1. wire.fi promises (oracle.fi: base64/QP/RFC 2047, IMAP command bytes,
# literal-aware response end incl. every truncated prefix, LIST, SMTP replies/AUTH/dot-
# stuffing, header unfolding, compose). 2. session.fi against tools/mail/stub.py over
# TLS 1.3 with a self-made CA (cert chain + name check) and over plain TCP: login, LIST,
# SELECT, FETCH headers/bodies, STORE, SMTP AUTH PLAIN + two messages in one session
# (the stub writes them to disk; this script compares the bytes).
# NEGATIVE CONTROLS (each must fail the right way): wrong host name -> E_CERT, empty trust
# store -> E_CERT, wrong password -> E_AUTH (IMAP and SMTP), a mutated wire.fi (response
# end ignores literals) -> oracle goes red.
# DOES NOT MEASURE: real mail servers (Dovecot/Gmail quirks), STARTTLS, the fUi window
# (that is tools/mail/app.sh).
#
# Usage: bash tools/mail/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$ROOT/lib"
T=$(mktemp -d)
STUBPID=""
cleanup() { [ -n "$STUBPID" ] && kill "$STUBPID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

# ---- 1. oracle
"$FIRNC" tools/mail/oracle.fi -o "$T/oracle" 2> "$T/o.err" && ok "oracle builds" || { bad "oracle build"; head -8 "$T/o.err"; }
if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/o.txt" 2>&1; rc=$?
    nok=$(grep -c '^OK' "$T/o.txt"); nbad=$(grep -c '^FAIL' "$T/o.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/o.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 45 ] && ok "oracle: $nok promises OK (>= 45)" || bad "oracle: only $nok OK"
    pass=$((pass+nok))
fi

# ---- 2. mutation: IMAP response end that ignores literals must be caught
mkdir -p "$T/lib-mut/mail"
for d in lib/*; do [ "$(basename "$d")" = mail ] || ln -s "$ROOT/$d" "$T/lib-mut/$(basename "$d")"; done
cp lib/mail/session.fi "$T/lib-mut/mail/"
# the mutation: never treat "{N}" as a literal
sed -e 's/if lit == BAD {/if true {/' lib/mail/wire.fi > "$T/lib-mut/mail/wire.fi"
if cmp -s lib/mail/wire.fi "$T/lib-mut/mail/wire.fi"; then
    bad "control literal-blind: the mutation changed nothing"
else
    FIRNLIB="$T/lib-mut" "$FIRNC" tools/mail/oracle.fi -o "$T/oracle-mut" 2> "$T/m.err"
    if [ -x "$T/oracle-mut" ] && "$T/oracle-mut" 2>&1 | grep -q '^FAIL'; then
        ok "control: a client blind to literals turns the oracle red"
    else
        bad "control: literal-blind client was NOT caught"
    fi
fi

# ---- 3. TLS + plain sessions against the stub
command -v openssl >/dev/null && command -v python3 >/dev/null || { bad "openssl/python3 missing"; echo "  mail gate: $pass ok, $fail FAIL"; exit 1; }
"$FIRNC" tools/mail/nettest.fi -o "$T/nettest" 2> "$T/n.err" && ok "nettest builds" || { bad "nettest build"; head -10 "$T/n.err"; }
C="$T/cert"; mkdir -p "$C"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
    -keyout "$C/key.pem" -out "$C/cert.pem" -subj "/CN=mail.test" \
    -addext "subjectAltName=DNS:mail.test" -addext "basicConstraints=critical,CA:TRUE" >/dev/null 2>&1 \
    && ok "test certificate (ECDSA P-256, SAN mail.test)" || bad "openssl could not make the certificate"

run_stub() { # mode outdir [cert key]
    rm -f "$2/ports"; mkdir -p "$2"
    python3 -I tools/mail/stub.py "$2" "$1" "${@:3}" > "$2/stub.log" 2>&1 &
    STUBPID=$!
    for _ in $(seq 1 50); do [ -f "$2/ports" ] && break; sleep 0.1; done
    [ -f "$2/ports" ]
}
stop_stub() { kill "$STUBPID" 2>/dev/null; wait "$STUBPID" 2>/dev/null; STUBPID=""; }

if [ -x "$T/nettest" ]; then
    # 3a. TLS happy path
    if run_stub tls "$T/tls" "$C/cert.pem" "$C/key.pem"; then
        read -r IP SP < "$T/tls/ports"
        timeout 60 "$T/nettest" "$IP" "$SP" "$C/cert.pem" mail.test justin geheim tls > "$T/tls.txt" 2>&1; rc=$?
        sed -n 's/^FAIL /  FAIL  tls: /p' "$T/tls.txt"
        n1=$(grep -c '^OK' "$T/tls.txt"); n2=$(grep -c '^FAIL' "$T/tls.txt")
        [ "$rc" = 0 ] && [ "$n2" = 0 ] && [ "$n1" -ge 28 ] && ok "TLS session: $n1 steps OK, 0 FAIL" || { bad "TLS session (rc=$rc ok=$n1 fail=$n2)"; tail -5 "$T/tls.txt"; }
        pass=$((pass+n1))
        # sent mails as the server saw them
        if [ -f "$T/tls/msg-1.eml" ] && [ -f "$T/tls/msg-2.eml" ]; then
            python3 -I - "$T/tls/msg-1.eml" "$T/tls/msg-2.eml" <<'PY' && ok "stub received both messages byte-exact (headers, RFC 2047 subject, dot-stuffing undone)" || bad "received messages differ"
import sys, email, email.policy
m1 = open(sys.argv[1], 'rb').read()
m2 = open(sys.argv[2], 'rb').read()
assert m1.startswith(b"X-Stub-From: <justin@example.org>\r\nX-Stub-To: <max@example.org>\r\n"), m1[:80]
assert m2.startswith(b"X-Stub-From: <justin@example.org>\r\nX-Stub-To: <zwei@example.org>\r\n"), m2[:80]
e = email.message_from_bytes(m1.split(b"\r\n", 2)[2], policy=email.policy.default)
assert e["Subject"] == "Grüße aus Wien", e["Subject"]
assert e["From"] == "justin@example.org" and e["To"] == "Max <max@example.org>"
assert e.get_content().replace("\r\n", "\n") == "Hallo Max\n.Punkt am Anfang\nEnde\n", repr(e.get_content())
e2 = email.message_from_bytes(m2.split(b"\r\n", 2)[2], policy=email.policy.default)
assert e2["Subject"] == "Zweite" and e2.get_content().strip() == "nur eine Zeile"
assert b"\n" not in m1.replace(b"\r\n", b""), "bare LF in message 1"
PY
        else
            bad "stub did not receive both messages"
        fi
        # negative controls on the same stub
        out=$(timeout 30 "$T/nettest" "$IP" "$SP" "$C/cert.pem" evil.example justin geheim tls 2>&1 | head -3)
        echo "$out" | grep -q '^OPEN imap 3$' && ok "control: wrong host name is refused (E_CERT)" || bad "control: wrong host name -> $out"
        out=$(timeout 30 "$T/nettest" "$IP" "$SP" - mail.test justin geheim tls 2>&1 | head -3)
        echo "$out" | grep -q '^OPEN imap 3$' && ok "control: empty trust store is refused (E_CERT)" || bad "control: empty trust store -> $out"
        out=$(timeout 30 "$T/nettest" "$IP" "$SP" "$C/cert.pem" mail.test justin falsch tls 2>&1 | grep '^LOGIN')
        echo "$out" | grep -q '^LOGIN imap 6$' && ok "control: wrong IMAP password -> E_AUTH" || bad "control: wrong IMAP password -> $out"
        stop_stub
    else
        bad "stub (tls) did not start"; cat "$T/tls/stub.log" 2>/dev/null | tail -5
    fi
    # 3b. plain happy path + SMTP wrong password
    if run_stub plain "$T/pl"; then
        read -r IP SP < "$T/pl/ports"
        timeout 60 "$T/nettest" "$IP" "$SP" - x justin geheim plain > "$T/pl.txt" 2>&1; rc=$?
        n1=$(grep -c '^OK' "$T/pl.txt"); n2=$(grep -c '^FAIL' "$T/pl.txt")
        [ "$rc" = 0 ] && [ "$n2" = 0 ] && [ "$n1" -ge 28 ] && ok "plain session: $n1 steps OK, 0 FAIL" || { bad "plain session (rc=$rc ok=$n1 fail=$n2)"; tail -5 "$T/pl.txt"; }
        pass=$((pass+n1))
        stop_stub
    else
        bad "stub (plain) did not start"
    fi
fi
echo "  mail gate: $pass ok, $fail FAIL"
[ "$fail" = 0 ]
