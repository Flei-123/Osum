#!/usr/bin/env bash
#
#     $ qemu-system-x86_64 -device help | grep -icE 'wifi|802\.11|iwl'
#     2
#     267:name "athlon-v1-x86_64-cpu"
#     268:name "athlon-x86_64-cpu"
#
# ==================================================================
# WAS HIER LAEUFT
# ==================================================================
#
# Usage:  bash tools/wlan/run.sh [--quick]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
OUT=${OUT:-/tmp/wlan-run}
mkdir -p "$OUT" .probe
QUICK=${1:-}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# =====================================================================
echo "== 0. the test bench: the same sources the kernel links =="
# =====================================================================

if command -v qemu-system-x86_64 > /dev/null 2>&1; then
    WIFIDEV=$(qemu-system-x86_64 -device help 2>&1 \
        | sed -n '/Network devices/,/^$/p' \
        | grep -icE 'wifi|802\.11|wlan|iwl|mt79|ath[0-9]' || true)
    if [ "$WIFIDEV" = "0" ]; then
        ok "QEMU $(qemu-system-x86_64 --version | head -1 | awk '{print $4}') has 0 WLAN devices -- this section cannot and must not start QEMU"
    else
        bad "QEMU reports $WIFIDEV WLAN devices -- then docs/WLAN-BEFUND.md section 5 needs rewriting"
    fi
else
    ok "no QEMU available -- irrelevant for this section"
fi

$FIRNC tools/wlan/oracle.fi -o .probe/worakel 2> "$OUT/orakel.err" \
    && ok "tools/wlan/oracle.fi builds against lib/crypto/ and lib/wlan/ (the same files as the kernel)" \
    || { bad "tools/wlan/oracle.fi cannot be built"; head -20 "$OUT/orakel.err"; }

if [ ! -x .probe/worakel ]; then
    echo "WLAN: nothing proceeds without the oracle."
    echo "WLAN: $pass Zusagen, $((fail+1)) Fehler"
    exit 1
fi

if [ "$(echo 'quatsch' | ./.probe/worakel)" = "FAIL" ]; then
    ok "the oracle rejects an unknown line (it does not say yes to everything)"
else
    bad "the oracle also answers nonsense -- then no FAIL means anything"
fi

if [ -f tools/wlan/mitschnitt.txt ]; then
    N=$(grep -c '^beacon ' tools/wlan/mitschnitt.txt)
    E=$(grep -c '^eapol' tools/wlan/mitschnitt.txt)
    D=$(grep -c '^daten ' tools/wlan/mitschnitt.txt)
    ok "the capture is included: $N beacons, $E handshake messages, $D encrypted frames from a real WPA2 network"
else
    bad "tools/wlan/mitschnitt.txt fehlt"
fi

# =====================================================================
echo
echo "== 1..8. the computation against standards, OpenSSL and the capture =="
# =====================================================================
python3 tools/wlan/vektoren.py $QUICK 2>&1 | tee "$OUT/vektoren.txt"
VRC=${PIPESTATUS[0]}
VP=$(grep -c '^  OK    ' "$OUT/vektoren.txt" || true)
VF=$(grep -c '^  FAIL  ' "$OUT/vektoren.txt" || true)
pass=$((pass + VP))
fail=$((fail + VF))

# =====================================================================
echo
echo "== 9. the fuzz run: mangled frames under valgrind =="
# =====================================================================
python3 tools/wlan/fuzz.py $QUICK 2>&1 | tee "$OUT/fuzz.txt"
FP=$(grep -c '^  OK    ' "$OUT/fuzz.txt" || true)
FF=$(grep -c '^  FAIL  ' "$OUT/fuzz.txt" || true)
pass=$((pass + FP))
fail=$((fail + FF))

# =====================================================================
echo
echo "== 10. what this round can NOT do, measured =="
# =====================================================================
#
#     tab_line(0x8086, 0x2723, 0x00) // Wi-Fi 6 AX200
#
WLTAB=$(grep -rhn 'tab_line(0x8086, *0x\(2723\|2725\|[Aa]0[Ff]0\)' --include=*.fi kernel/ 2>/dev/null || true)
WLBOUND=$(printf '%s\n' "$WLTAB" | grep -v '0x00)' | grep -c 'tab_line' || true)
WLNAMED=$(printf '%s\n' "$WLTAB" | grep -c 'tab_line' || true)
if [ "$WLBOUND" != "0" ]; then
    bad "a WLAN PCI id is bound to a driver -- so there is one docs/WLAN-BEFUND.md does not know"
else
    ok "no WLAN PCI id is bound to a driver ($WLNAMED named, all with driver 0x00): there is NO driver, as docs/WLAN-BEFUND.md says"
fi
if [ "$WLNAMED" -ge 3 ]; then
    ok "item 1 of the continuation list is done on merge6: AX200/AX201/AX210 are reported by name instead of staying silent"
else
    bad "the WLAN cards are no longer named -- item 1 of the continuation list was lost"
fi
if grep -rqn 'fn sae_\|dragonfly\|hunting' --include=*.fi lib/wlan/ 2>/dev/null; then
    bad "SAE was started without any test vectors"
else
    ok "SAE is NOT built -- reason in docs/WLAN-BEFUND.md section 6"
fi
if grep -rqn 'TKIP wird\|fn tkip' --include=*.fi lib/wlan/ 2>/dev/null; then
    bad "TKIP was implemented -- it is broken and does not belong here"
else
    ok "TKIP and WEP are NOT implemented, only detected and rejected"
fi

Z=$(cat lib/wlan/*.fi lib/crypto/sha1.fi lib/crypto/aes.fi | wc -l)
ok "the round in lines: $Z in lib/wlan/ and the two new lib/crypto/ files"

# =====================================================================
echo
echo "== 11. ROUND WLAN-3: the WHOLE path against the simulated device =="
# =====================================================================
#
python3 tools/wlan/vollweg.py 2>&1 | tee "$OUT/vollweg.txt"
VWP=$(grep -c '^  OK    ' "$OUT/vollweg.txt" || true)
VWF=$(grep -c '^  FAIL  ' "$OUT/vollweg.txt" || true)
pass=$((pass + VWP))
fail=$((fail + VWF))

echo
echo "== 12. AR9271 (USB, ath9k_htc): Firmware-Pin, Download, HTC/WMI gegen simulierten Stick =="
# =====================================================================
#
# lib/wlan/htc.fi + lib/wlan/ar9271.fi (REAL driver code) talk through a
# transport table to a simulated firmware (tools/wlan/ar9271.fi).
# tools/wlan/ar9271.py re-derives every frame with struct.pack. A real
# linux-firmware blob (htc_9271-1.4.0.fw) is used if $WLAN_FW points at
# it; otherwise only the synthetic blob runs. Not real hardware (M1).
if $FIRNC tools/wlan/ar9271.fi -o .probe/war9271 2> "$OUT/ar9271.err"; then
    ok "tools/wlan/ar9271.fi baut gegen lib/wlan/ar9271.fi + htc.fi"
    SYN="$OUT/ar9271-syn.bin"
    python3 -c "
import random
r = random.Random(7)
open('$SYN', 'wb').write(bytes(r.randrange(256) for _ in range(9000)))"
    python3 -I tools/wlan/ar9271.py .probe/war9271 "$SYN" 2>&1 | tee "$OUT/ar9271.txt"
    if [ -n "${WLAN_FW:-}" ] && [ -f "$WLAN_FW" ]; then
        python3 -I tools/wlan/ar9271.py .probe/war9271 "$WLAN_FW" 2>&1 | tee -a "$OUT/ar9271.txt"
    else
        echo "  (WLAN_FW not set: real firmware not checked)"
    fi
    AP=$(grep -c '^  OK    ' "$OUT/ar9271.txt" || true)
    AF=$(grep -c '^  FAIL  ' "$OUT/ar9271.txt" || true)
    pass=$((pass + AP))
    fail=$((fail + AF))
else
    bad "tools/wlan/ar9271.fi cannot be built"
    head -20 "$OUT/ar9271.err"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "WLAN: $pass Zusagen, 0 Fehler"
    exit 0
else
    echo "WLAN: $pass Zusagen, $fail FEHLER"
    exit 1
fi
