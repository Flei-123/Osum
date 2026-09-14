#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/acpiev/taste.sh -- DIE EINSCHALTTASTE, WIRKLICH GEDRUECKT.
#
# `system_powerdown` am QEMU-Monitor IST der Druck auf die
# Einschalttaste: QEMU setzt PWRBTN_STS in PM1a_STS und zieht den SCI.
# Was danach passiert, ist Sache des Gastes -- und genau das wird hier
# gemessen.
#
# Aufruf:  bash tools/acpiev/taste.sh KERNEL AUSGABE [warte_s] [append...]
set -uo pipefail
K=${1:?kernel}
OUT=${2:?ausgabe}
WARTE=${3:-12}
shift 3 2>/dev/null || shift $# 
APPEND=${*:-osum acpiev evdump}

MON=$(mktemp -u /tmp/acpiev-mon.XXXXXX)
rm -f "$OUT" "$OUT.rc"

qemu-system-x86_64 -accel kvm -kernel "$K" -m 256 \
    -append "$APPEND" \
    -serial "file:$OUT" -display none -no-reboot \
    -monitor "unix:$MON,server,nowait" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
QPID=$!

# Warten, bis der Kern aufgesetzt hat. NICHT blind schlafen: auf die
# Zeile warten, die sagt, dass die Ereignisse stehen -- sonst misst man
# auf einer schnellen Maschine etwas anderes als auf einer langsamen.
for _ in $(seq 1 300); do
    grep -qa 'acpiev: ready=' "$OUT" 2>/dev/null && break
    kill -0 $QPID 2>/dev/null || break
    sleep 0.1
done
sleep 2

# DER DRUCK.
python3 - "$MON" <<'PY'
import socket, sys, time, os
pfad = sys.argv[1]
# WARTEN, BIS DER ANSCHLUSS DA IST. `server,nowait` legt ihn an, sobald
# QEMU so weit ist -- das kann nach dem Start des Kerns sein. Wer hier
# blind verbindet, bekommt ECONNREFUSED und misst nichts.
for _ in range(200):
    if os.path.exists(pfad):
        break
    time.sleep(0.05)
letzt = None
for versuch in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect(pfad)
        time.sleep(0.4)
        s.sendall(b"system_powerdown\n")
        time.sleep(0.6)
        s.close()
        print("Monitor: system_powerdown gesendet")
        sys.exit(0)
    except Exception as e:
        letzt = e
        time.sleep(0.25)
print("Monitor: %s" % letzt, file=sys.stderr)
sys.exit(1)
PY

# Dem Gast Zeit geben zu reagieren.
for _ in $(seq 1 $((WARTE * 10))); do
    kill -0 $QPID 2>/dev/null || break
    sleep 0.1
done

kill $QPID 2>/dev/null
wait $QPID 2>/dev/null
echo $? > "$OUT.rc"
rm -f "$MON"
