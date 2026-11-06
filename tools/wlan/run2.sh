#!/usr/bin/env bash
#
# Usage:  bash tools/wlan/run2.sh [--quick]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${OUT:-/tmp/wlan2-run}
mkdir -p "$OUT" .probe
QUICK=${1:-}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

LAEUFE=40
if [ "$QUICK" = "--quick" ]; then LAEUFE=8; fi

# =====================================================================
echo "== 1. der Messplatz =="
# =====================================================================

$FIRNC tools/wlan/oracle.fi -o .probe/worakel 2> "$OUT/orakel.err" \
    && ok "tools/wlan/oracle.fi builds against lib/crypto/, lib/wlan/ and the new files" \
    || { bad "tools/wlan/oracle.fi cannot be built"; head -20 "$OUT/orakel.err"; }

if [ ! -x .probe/worakel ]; then
    echo "WLAN2: nothing goes on without the oracle."
    echo "WLAN2: $pass Zusagen, $((fail+1)) FEHLER"
    exit 1
fi

python3 -c 'import cryptography' 2>/dev/null \
    && ok "the peer has its crypto library (python-cryptography = OpenSSL, NOT lib/crypto/)" \
    || bad "python3-cryptography missing -- without it the peer cannot compute independently"

# =====================================================================
echo "== 2. the peer calibrates itself on a REAL capture =="
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
echo "== 3. Osum's supplicant against the peer (S2 and S4) =="
# =====================================================================

ORAKEL=./.probe/worakel python3 tools/wlan/handschlag.py \
    --laeufe=$LAEUFE > "$OUT/hs.txt" 2>&1
grep -E '^  (OK|FAIL)' "$OUT/hs.txt" || true
HG=$(grep -c '^  OK' "$OUT/hs.txt" || true)
HF=$(grep -c '^  FAIL' "$OUT/hs.txt" || true)
pass=$((pass+HG))
fail=$((fail+HF))

# =====================================================================
echo "== 4. the seam to the hardware =="
# =====================================================================
#

R=$(printf 'device 08413a01aabbccddeeff112233445566778899aa0000cafebabe\n' \
    | ./.probe/worakel)
case "$R" in
  "vorher=1 gesd=26 empf=26 same=1 ztx=1 zrx=1")
    ok "the seam: a frame goes through the board and comes back UNCHANGED, the counters match" ;;
  *)
    bad "the seam returns '$R' instead of the expected line" ;;
esac
case "$R" in
  vorher=1*)
    ok "a device WITHOUT a board returns -1 instead of jumping through a null pointer" ;;
  *)
    bad "a device without a board does something other than refuse" ;;
esac

# =====================================================================
echo "== 4b. the whole path, and what happens when someone lies (T4) =="
# =====================================================================
#

ORAKEL=./.probe/worakel python3 tools/wlan/e2e_path.py > "$OUT/e2e_path.txt" 2>&1
grep -E '^  (OK|FAIL)' "$OUT/e2e_path.txt" || true
WG=$(grep -c '^  OK' "$OUT/e2e_path.txt" || true)
WF=$(grep -c '^  FAIL' "$OUT/e2e_path.txt" || true)
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
    ok "all $1 USB ids give the right family AND the right plain name (and what does not exist stays unknown)"
else
    bad "only ${1:-0} of ${2:-?} USB ids match"
    grep '^FAIL' "$OUT/chip.txt" | head -10
fi

if bash tools/structure/srcview.sh kernel/usb/usb.fi | grep -q 'wifi-usb: '; then
    ok "kernel/usb/usb.fi reports a recognized stick as 'wifi-usb: <Name> (<vid>:<pid>), kein Treiber'"
else
    bad "the report line is missing in kernel/usb/usb.fi"
fi
if bash tools/structure/srcview.sh kernel/usb/usb.fi | grep -q 'DRV_WLAN\|wlan_start'; then
    bad "kernel/usb/usb.fi binds a WLAN driver that does not exist"
else
    ok "kernel/usb/usb.fi binds NO WLAN driver: the line names, it does not claim"
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
echo "== 6. what this round can NOT do, measured =="
# =====================================================================

if grep -rqn 'fn sae_\|dragonfly\|hunting' --include=*.fi lib/wlan/ 2>/dev/null; then
    bad "SAE was started without any test vectors"
else
    ok "SAE is NOT built -- rationale in docs/WLAN.md"
fi

KOMMENTARFREI=$({ cat lib/wlan/*.fi; bash tools/structure/srcview.sh kernel/usb/usb.fi; } 2>/dev/null | sed 's|//.*||')
if printf '%s' "$KOMMENTARFREI" | grep -q 'fn fw_download\|fn firmware_laden\|DRV_WLAN'; then
    bad "WLAN firmware is loaded somewhere -- so there is a driver docs/WLAN.md does not know"
else
    ok "no USB WLAN driver and no firmware in the source: it is named, not claimed"
fi

Z=$(cat lib/wlan/device.fi lib/wlan/testdevice.fi lib/wlan/connect.fi \
        lib/wlan/usbchip.fi kernel/user/wlan.fi 2>/dev/null | wc -l)
ok "the new files of this round in lines: $Z in lib/wlan/ and kernel/user/wlan.fi"

echo
echo "WLAN2: $pass Zusagen, $fail Fehler"
[ "$fail" = "0" ] || exit 1
exit 0
