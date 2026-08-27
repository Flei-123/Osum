#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/boot/run.sh -- DER BEWEIS, DASS DER MULTIBOOT-KOPF EINEN
# BILDSCHIRM VERLANGT -- UND WARUM DAS DER UEFI-PFAD IST.
#
# Osum startet ueber Multiboot. Bis zu dieser Runde stand im Kopf
# `MB_FLAGS = 0x3`: ausgerichtete Module und Speicherkarte, sonst nichts.
# Ein Lader liest daraus, dass der Kern keinen Bildschirmwunsch hat, und
# nimmt den TEXTMODUS an.
#
# Unter UEFI gibt es keinen Textmodus. Ein Multiboot-Lader, der unter
# UEFI laeuft (Limine), bricht deshalb mit
#
#     PANIC: multiboot1: Cannot use text mode with UEFI.
#
# ab -- gemessen, bevor diese Runde den Kopf geaendert hat. Mit Bit 2 und
# `mode_type = 0` verlangt der Kern einen LINEAREN RAHMENPUFFER, den die
# Firmware setzen kann, und dasselbe Abbild bootet ueber BIOS UND ueber
# UEFI.
#
# WAS HIER GEMESSEN WIRD:
#
#   1. Der Kopf steht in den ersten 8 KiB des Abbilds, die Pruefsumme
#      stimmt (Magie + Flags + Pruefsumme = 0 modulo 2^32).
#   2. Bit 2 ist gesetzt und `mode_type` ist 0 -- linearer Rahmenpuffer,
#      keine Vorgabe fuer Breite und Hoehe.
#   3. Der Kern startet weiterhin ueber `qemu-system-x86_64 -kernel`, und
#      er meldet die Flags, die der Lader ihm gegeben hat.
#   4. Die Gegenprobe: derselbe Kern, aus BEIDEN Uebersetzern, mit
#      demselben Kopf.
#
# Der Boot ueber eine ECHTE UEFI-Firmware wird nicht hier gemessen,
# sondern dort, wo der Lader und das Abbild zu Hause sind: in OrientOS
# (`tests/step-25-osum-uefi.sh`). Dieses Repo baut einen Kern, kein ISO.
#
# Verwendung:  bash tools/boot/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

gleich() { # name gemessen erwartet
    if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2, erwartet $3"; fi
}

for stufe in 0 1; do
    IMG="$TMPD/osum$stufe.mb"
    if ! bash tools/build-kernel.sh "$IMG" --stufe "$stufe" > "$TMPD/b$stufe.log" 2>&1; then
        bad "firnc$stufe: der Kernel laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/b$stufe.log" | head -10
        continue
    fi

    # Den Kopf im ABBILD suchen, nicht in der Quelle: gemessen wird, was
    # ein Lader vorfindet.
    KOPF=$(python3 - "$IMG" <<'PY'
import struct, sys
daten = open(sys.argv[1], 'rb').read()
# Multiboot 1: die Magie liegt 4-fach ausgerichtet in den ersten 8192
# Oktetten (Spezifikation 3.1.1).
for off in range(0, min(len(daten), 8192) - 48, 4):
    if daten[off:off+4] == b'\x02\xb0\xad\x1b':
        f = struct.unpack_from('<9I', daten, off)
        magie, flags, pruef = f[0], f[1], f[2]
        modus, breite, hoehe, tiefe = struct.unpack_from('<4I', daten, off+32)
        print(off, hex(magie), hex(flags),
              (magie + flags + pruef) & 0xFFFFFFFF, modus, breite, hoehe, tiefe)
        break
else:
    print("-1")
PY
)
    set -- $KOPF
    if [ "$1" = "-1" ]; then
        bad "firnc$stufe: kein Multiboot-Kopf in den ersten 8 KiB"
        continue
    fi
    OFF=$1; MAGIE=$2; FLAGS=$3; SUMME=$4; MODUS=$5; TIEFE=$8
    if [ "$OFF" -lt 8192 ]; then
        ok "firnc$stufe: Multiboot-Kopf bei Oktett $OFF (Grenze 8192)"
    else
        bad "firnc$stufe: Multiboot-Kopf bei Oktett $OFF -- zu weit hinten"
    fi
    gleich "firnc$stufe: Magie" "$MAGIE" "0x1badb002"
    gleich "firnc$stufe: Pruefsumme geht auf" "$SUMME" "0"
    gleich "firnc$stufe: Flags" "$FLAGS" "0x7"
    if [ $(( $(printf '%d' "$FLAGS") & 4 )) -ne 0 ]; then
        ok "firnc$stufe: Bit 2 gesetzt -- der Kern verlangt einen Bildschirm"
    else
        bad "firnc$stufe: Bit 2 fehlt -- ein UEFI-Lader nimmt Textmodus an"
    fi
    gleich "firnc$stufe: mode_type = linearer Rahmenpuffer" "$MODUS" "0"
    gleich "firnc$stufe: 32 Bit je Bildpunkt" "$TIEFE" "32"

    # Der alte Weg muss weitergehen. Ein Kopf, der UEFI erlaubt, aber den
    # bisherigen Start kaputtmacht, waere kein Fortschritt.
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        OUT="$TMPD/o$stufe.txt"
        rc=0
        timeout 90 qemu-system-x86_64 -kernel "$IMG" -m 128 \
            -append "osum nokbd nosched noproc nofs noring3" \
            -serial "file:$OUT" -display none -no-reboot \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 || rc=$?
        [ "$rc" -eq 21 ] && ok "firnc$stufe: -kernel bootet weiterhin (21)" \
                         || bad "firnc$stufe: -kernel endet mit $rc, erwartet 21"
        grep -qa '^mb: flags=' "$OUT" \
            && ok "firnc$stufe: der Kern meldet die Flags des Laders" \
            || bad "firnc$stufe: keine Flagmeldung des Laders"
        grep -qa '^mmap: ' "$OUT" \
            && ok "firnc$stufe: die Speicherkarte kommt an" \
            || bad "firnc$stufe: keine Speicherkarte"
    else
        echo "  (qemu fehlt -- der Startversuch wird uebersprungen)"
    fi
done

echo
echo "BOOT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
