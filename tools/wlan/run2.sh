#!/usr/bin/env bash
#
# Verwendung:  bash tools/wlan/run2.sh [--schnell]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${OUT:-/tmp/wlan2-run}
mkdir -p "$OUT" .probe
SCHNELL=${1:-}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

LAEUFE=40
if [ "$SCHNELL" = "--schnell" ]; then LAEUFE=8; fi

# =====================================================================
echo "== 1. der Messplatz =="
# =====================================================================

$FIRNC tools/wlan/oracle.fi -o .probe/worakel 2> "$OUT/orakel.err" \
    && ok "tools/wlan/oracle.fi baut gegen lib/crypto/, lib/wlan/ und die neuen Dateien" \
    || { bad "tools/wlan/oracle.fi laesst sich nicht bauen"; head -20 "$OUT/orakel.err"; }

if [ ! -x .probe/worakel ]; then
    echo "WLAN2: ohne Orakel geht nichts weiter."
    echo "WLAN2: $pass Zusagen, $((fail+1)) FEHLER"
    exit 1
fi

python3 -c 'import cryptography' 2>/dev/null \
    && ok "die Gegenstelle hat ihre Kryptobibliothek (python-cryptography = OpenSSL, NICHT lib/crypto/)" \
    || bad "python3-cryptography fehlt -- ohne sie kann die Gegenstelle nicht unabhaengig rechnen"

# =====================================================================
echo "== 2. die Gegenstelle eicht sich an einer ECHTEN Aufzeichnung =="
# =====================================================================
#

python3 tools/wlan/gegenstelle.py --selbsttest tools/wlan/mitschnitt.txt \
    > "$OUT/eich.txt" 2>&1
EG=$(grep -c '^  OK' "$OUT/eich.txt" || true)
EF=$(grep -c '^  FAIL' "$OUT/eich.txt" || true)
sed -n 's/^  OK    /  OK    /p' "$OUT/eich.txt"
pass=$((pass+EG))
if [ "$EF" != "0" ]; then
    fail=$((fail+EF))
    grep '^  FAIL' "$OUT/eich.txt"
fi

# =====================================================================
echo "== 3. Osums Supplicant gegen die Gegenstelle (S2 und S4) =="
# =====================================================================

ORAKEL=./.probe/worakel python3 tools/wlan/handschlag.py \
    --laeufe=$LAEUFE > "$OUT/hs.txt" 2>&1
grep -E '^  (OK|FAIL)' "$OUT/hs.txt" || true
HG=$(grep -c '^  OK' "$OUT/hs.txt" || true)
HF=$(grep -c '^  FAIL' "$OUT/hs.txt" || true)
pass=$((pass+HG))
fail=$((fail+HF))

# =====================================================================
echo "== 4. die Naht zum Blech =="
# =====================================================================
#

R=$(printf 'geraet 08413a01aabbccddeeff112233445566778899aa0000cafebabe\n' \
    | ./.probe/worakel)
case "$R" in
  "vorher=1 gesd=26 empf=26 same=1 ztx=1 zrx=1")
    ok "die Naht: ein Rahmen geht durch die Tafel und kommt UNVERAENDERT zurueck, die Zaehler stimmen" ;;
  *)
    bad "die Naht liefert '$R' statt der erwarteten Zeile" ;;
esac
case "$R" in
  vorher=1*)
    ok "ein Geraet OHNE Tafel gibt -1, statt in einen Nullzeiger zu springen" ;;
  *)
    bad "ein Geraet ohne Tafel tut etwas anderes als abzulehnen" ;;
esac

# =====================================================================
echo "== 4b. der ganze Weg, und was passiert, wenn jemand luegt (T4) =="
# =====================================================================
#

ORAKEL=./.probe/worakel python3 tools/wlan/weg.py > "$OUT/weg.txt" 2>&1
grep -E '^  (OK|FAIL)' "$OUT/weg.txt" || true
WG=$(grep -c '^  OK' "$OUT/weg.txt" || true)
WF=$(grep -c '^  FAIL' "$OUT/weg.txt" || true)
pass=$((pass+WG))
fail=$((fail+WF))

# =====================================================================
echo "== 5. welcher USB-Stick steckt da? =="
# =====================================================================
#

python3 - > "$OUT/chip.txt" <<'PY'
import subprocess
# (vid, pid, erwartete Familie, erwarteter Klarname)
FAELLE = [
    (0x0BDA, 0x8179, "Realtek",  "Realtek RTL8188EU"),
    (0x0BDA, 0x8812, "Realtek",  "Realtek RTL8812AU"),
    (0x0BDA, 0xC821, "Realtek",  "Realtek RTL8821CU"),
    (0x0BDA, 0x8176, "Realtek",  "Realtek RTL8192CU"),
    (0x2357, 0x0101, "Realtek",  "Realtek RTL8812AU"),
    (0x0846, 0x9052, "Realtek",  "Realtek RTL8812AU"),
    (0x7392, 0x7811, "Realtek",  "Realtek RTL8192CU"),
    (0x0E8D, 0x7601, "MediaTek", "MediaTek MT7601U"),
    (0x0E8D, 0x7612, "MediaTek", "MediaTek MT7612U"),
    (0x0E8D, 0x7961, "MediaTek", "MediaTek MT7921AU"),
    (0x148F, 0x5370, "Ralink",   "Ralink RT5370"),
    (0x0CF3, 0x9271, "Atheros",  "Atheros AR9271"),
    (0x0A5C, 0xBD1D, "Broadcom", "Broadcom BCM43xx"),
    # und die Gegenprobe: was es nicht gibt, bleibt unbekannt
    (0x1234, 0x5678, "unbekannt", "WLAN-Stick (?)"),
    (0x0BDA, 0x0001, "unbekannt", "WLAN-Stick (?)"),
]
ein = "".join("usbchip %d %d\n" % (v, p) for v, p, _, _ in FAELLE)
aus = subprocess.run(['./.probe/worakel'], input=ein.encode(),
                     stdout=subprocess.PIPE).stdout.decode().strip().split("\n")
gut = 0
for (vid, pid, fam, name), zeile in zip(FAELLE, aus):
    soll = "%s %s" % (fam, name)
    if zeile == soll:
        gut += 1
    else:
        print("FAIL %04x:%04x -> '%s' statt '%s'" % (vid, pid, zeile, soll))
print("GUT %d von %d" % (gut, len(FAELLE)))
PY
CG=$(sed -n 's/^GUT \([0-9]*\) von \([0-9]*\)/\1 \2/p' "$OUT/chip.txt")
set -- $CG
if [ "${1:-0}" = "${2:-1}" ]; then
    ok "alle $1 USB-Nummern ergeben die richtige Familie UND den richtigen Klarnamen (und was es nicht gibt, bleibt unbekannt)"
else
    bad "nur ${1:-0} von ${2:-?} USB-Nummern stimmen"
    grep '^FAIL' "$OUT/chip.txt" | head -10
fi

if grep -q 'wifi-usb: ' kernel/usb/usb.fi; then
    ok "kernel/usb/usb.fi meldet einen erkannten Stick als 'wifi-usb: <Name> (<vid>:<pid>), kein Treiber'"
else
    bad "die Meldezeile fehlt in kernel/usb/usb.fi"
fi
if grep -q 'DRV_WLAN\|wlan_start' kernel/usb/usb.fi; then
    bad "kernel/usb/usb.fi bindet einen WLAN-Treiber, den es nicht gibt"
else
    ok "kernel/usb/usb.fi bindet KEINEN WLAN-Treiber: die Zeile benennt, sie behauptet nicht"
fi

# =====================================================================
echo "== 5b. /bin/wlan, wirklich gelaufen =="
# =====================================================================
#

bash tools/wlan/prog.sh "$OUT/prog" > "$OUT/prog.txt" 2>&1
grep -E '^  (OK|FAIL)' "$OUT/prog.txt" || true
PG=$(grep -c '^  OK' "$OUT/prog.txt" || true)
PF=$(grep -c '^  FAIL' "$OUT/prog.txt" || true)
pass=$((pass+PG))
fail=$((fail+PF))

# =====================================================================
echo "== 6. was diese Runde NICHT kann, gemessen =="
# =====================================================================

if grep -rqn 'fn sae_\|dragonfly\|hunting' --include=*.fi lib/wlan/ 2>/dev/null; then
    bad "SAE ist angefangen worden, ohne dass es Testvektoren gibt"
else
    ok "SAE ist NICHT gebaut -- Begruendung in docs/WLAN.md"
fi

KOMMENTARFREI=$(cat lib/wlan/*.fi kernel/usb/usb.fi 2>/dev/null | sed 's|//.*||')
if printf '%s' "$KOMMENTARFREI" | grep -q 'fn fw_download\|fn firmware_laden\|DRV_WLAN'; then
    bad "irgendwo wird WLAN-Firmware geladen -- dann gibt es einen Treiber, den docs/WLAN.md nicht kennt"
else
    ok "kein USB-WLAN-Treiber und keine Firmware im Quelltext: es wird benannt, nicht behauptet"
fi

Z=$(cat lib/wlan/device.fi lib/wlan/testdevice.fi lib/wlan/connect.fi \
        lib/wlan/usbchip.fi kernel/user/wlan.fi 2>/dev/null | wc -l)
ok "die neuen Dateien dieser Runde in Zeilen: $Z in lib/wlan/ und kernel/user/wlan.fi"

echo
echo "WLAN2: $pass Zusagen, $fail Fehler"
[ "$fail" = "0" ] || exit 1
exit 0
