#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

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
        bad "firnc$stufe: the kernel cannot be built"
        sed 's/^/        /' "$TMPD/b$stufe.log" | head -10
        continue
    fi

    KOPF=$(python3 - "$IMG" <<'PY'
import struct, sys
daten = open(sys.argv[1], 'rb').read()
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
        bad "firnc$stufe: no Multiboot header in the first 8 KiB"
        continue
    fi
    OFF=$1; MAGIE=$2; FLAGS=$3; SUMME=$4; MODUS=$5; TIEFE=$8
    if [ "$OFF" -lt 8192 ]; then
        ok "firnc$stufe: Multiboot header at octet $OFF (limit 8192)"
    else
        bad "firnc$stufe: Multiboot header at octet $OFF -- too far back"
    fi
    gleich "firnc$stufe: Magie" "$MAGIE" "0x1badb002"
    gleich "firnc$stufe: Pruefsumme geht auf" "$SUMME" "0"
    gleich "firnc$stufe: Flags" "$FLAGS" "0x7"
    if [ $(( $(printf '%d' "$FLAGS") & 4 )) -ne 0 ]; then
        ok "firnc$stufe: bit 2 set -- the kernel requires a screen"
    else
        bad "firnc$stufe: bit 2 missing -- a UEFI loader assumes text mode"
    fi
    gleich "firnc$stufe: mode_type = linearer Rahmenpuffer" "$MODUS" "0"
    gleich "firnc$stufe: 32 Bit je Bildpunkt" "$TIEFE" "32"

    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        OUT="$TMPD/o$stufe.txt"
        rc=0
        timeout 90 $QEMU_X86 -kernel "$IMG" -m 128 \
            -append "osum nokbd nosched noproc nofs noring3" \
            -serial "file:$OUT" -display none -no-reboot \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 || rc=$?
        [ "$rc" -eq 21 ] && ok "firnc$stufe: -kernel bootet weiterhin (21)" \
                         || bad "firnc$stufe: -kernel ends with $rc, expected 21"
        grep -qa '^mb: flags=' "$OUT" \
            && ok "firnc$stufe: the kernel reports the loader flags" \
            || bad "firnc$stufe: no flag report from the loader"
        grep -qa '^mmap: ' "$OUT" \
            && ok "firnc$stufe: the memory map arrives" \
            || bad "firnc$stufe: no memory map"
    else
        echo "  (qemu missing -- the start attempt is skipped)"
    fi
done

echo
echo "BOOT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
