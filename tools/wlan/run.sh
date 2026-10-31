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
# Verwendung:  bash tools/wlan/run.sh [--schnell]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${OUT:-/tmp/wlan-run}
mkdir -p "$OUT" .probe
SCHNELL=${1:-}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# =====================================================================
echo "== 0. der Messplatz: dieselben Quelltexte, die der Kern bindet =="
# =====================================================================

if command -v qemu-system-x86_64 > /dev/null 2>&1; then
    WIFIDEV=$(qemu-system-x86_64 -device help 2>&1 \
        | sed -n '/Network devices/,/^$/p' \
        | grep -icE 'wifi|802\.11|wlan|iwl|mt79|ath[0-9]' || true)
    if [ "$WIFIDEV" = "0" ]; then
        ok "QEMU $(qemu-system-x86_64 --version | head -1 | awk '{print $4}') hat 0 WLAN-Geraete -- dieser Abschnitt kann und darf kein QEMU starten"
    else
        bad "QEMU meldet $WIFIDEV WLAN-Geraete -- dann gehoert docs/WLAN-BEFUND.md Abschnitt 5 neu geschrieben"
    fi
else
    ok "kein QEMU vorhanden -- fuer diesen Abschnitt ohne Belang"
fi

$FIRNC tools/wlan/oracle.fi -o .probe/worakel 2> "$OUT/orakel.err" \
    && ok "tools/wlan/oracle.fi baut gegen lib/crypto/ und lib/wlan/ (dieselben Dateien wie der Kern)" \
    || { bad "tools/wlan/oracle.fi laesst sich nicht bauen"; head -20 "$OUT/orakel.err"; }

if [ ! -x .probe/worakel ]; then
    echo "WLAN: ohne Orakel geht nichts weiter."
    echo "WLAN: $pass Zusagen, $((fail+1)) Fehler"
    exit 1
fi

if [ "$(echo 'quatsch' | ./.probe/worakel)" = "FAIL" ]; then
    ok "das Orakel lehnt eine unbekannte Zeile ab (es sagt nicht zu allem ja)"
else
    bad "das Orakel antwortet auch auf Unsinn -- dann sagt kein FAIL etwas aus"
fi

if [ -f tools/wlan/mitschnitt.txt ]; then
    N=$(grep -c '^beacon ' tools/wlan/mitschnitt.txt)
    E=$(grep -c '^eapol' tools/wlan/mitschnitt.txt)
    D=$(grep -c '^daten ' tools/wlan/mitschnitt.txt)
    ok "die Aufzeichnung liegt bei: $N Beacons, $E Handschlagnachrichten, $D verschluesselte Rahmen aus einem echten WPA2-Netz"
else
    bad "tools/wlan/mitschnitt.txt fehlt"
fi

# =====================================================================
echo
echo "== 1..8. die Rechnung gegen Normen, OpenSSL und die Aufzeichnung =="
# =====================================================================
python3 tools/wlan/vektoren.py $SCHNELL 2>&1 | tee "$OUT/vektoren.txt"
VRC=${PIPESTATUS[0]}
VP=$(grep -c '^  OK    ' "$OUT/vektoren.txt" || true)
VF=$(grep -c '^  FAIL  ' "$OUT/vektoren.txt" || true)
pass=$((pass + VP))
fail=$((fail + VF))

# =====================================================================
echo
echo "== 9. der Fuzz-Lauf: verstuemmelte Rahmen unter valgrind =="
# =====================================================================
python3 tools/wlan/fuzz.py $SCHNELL 2>&1 | tee "$OUT/fuzz.txt"
FP=$(grep -c '^  OK    ' "$OUT/fuzz.txt" || true)
FF=$(grep -c '^  FAIL  ' "$OUT/fuzz.txt" || true)
pass=$((pass + FP))
fail=$((fail + FF))

# =====================================================================
echo
echo "== 10. was diese Runde NICHT kann, gemessen =="
# =====================================================================
#
#     tab_line(0x8086, 0x2723, 0x00) // Wi-Fi 6 AX200
#
WLTAB=$(grep -rhn 'tab_line(0x8086, *0x\(2723\|2725\|[Aa]0[Ff]0\)' --include=*.fi kernel/ 2>/dev/null || true)
WLBOUND=$(printf '%s\n' "$WLTAB" | grep -v '0x00)' | grep -c 'tab_line' || true)
WLNAMED=$(printf '%s\n' "$WLTAB" | grep -c 'tab_line' || true)
if [ "$WLBOUND" != "0" ]; then
    bad "eine WLAN-PCI-Nummer haengt an einem Treiber -- dann gibt es einen, den docs/WLAN-BEFUND.md nicht kennt"
else
    ok "keine WLAN-PCI-Nummer ist an einen Treiber gebunden ($WLNAMED benannt, alle mit Treiber 0x00): es gibt KEINEN Treiber, so wie docs/WLAN-BEFUND.md sagt"
fi
if [ "$WLNAMED" -ge 3 ]; then
    ok "Punkt 1 der Fortsetzungsliste ist auf merge6 erledigt: AX200/AX201/AX210 werden mit Namen gemeldet statt still zu bleiben"
else
    bad "die WLAN-Karten werden nicht mehr benannt -- Punkt 1 der Fortsetzungsliste ist verlorengegangen"
fi
if grep -rqn 'fn sae_\|dragonfly\|hunting' --include=*.fi lib/wlan/ 2>/dev/null; then
    bad "SAE ist angefangen worden, ohne dass es Testvektoren gibt"
else
    ok "SAE ist NICHT gebaut -- Begruendung in docs/WLAN-BEFUND.md Abschnitt 6"
fi
if grep -rqn 'TKIP wird\|fn tkip' --include=*.fi lib/wlan/ 2>/dev/null; then
    bad "TKIP ist umgesetzt worden -- es ist gebrochen und gehoert nicht hierher"
else
    ok "TKIP und WEP sind NICHT umgesetzt, nur erkannt und abgelehnt"
fi

Z=$(cat lib/wlan/*.fi lib/crypto/sha1.fi lib/crypto/aes.fi | wc -l)
ok "die Runde in Zeilen: $Z in lib/wlan/ und den zwei neuen lib/crypto/-Dateien"

# =====================================================================
echo
echo "== 11. RUNDE WLAN-3: der GANZE Weg gegen das simulierte Geraet =="
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
        echo "  (WLAN_FW nicht gesetzt: echte Firmware nicht geprueft)"
    fi
    AP=$(grep -c '^  OK    ' "$OUT/ar9271.txt" || true)
    AF=$(grep -c '^  FAIL  ' "$OUT/ar9271.txt" || true)
    pass=$((pass + AP))
    fail=$((fail + AF))
else
    bad "tools/wlan/ar9271.fi laesst sich nicht bauen"
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
