#!/usr/bin/env bash
set -uo pipefail
WD=${1:?workdir}
DEST=${PREFIX_DEST:-/opt/pfx}
ROOT=$WD/root
OUT=$ROOT$DEST
WINE_DLLS=/usr/lib/wine
rm -rf "$OUT"
mkdir -p "$OUT"
(cd /tmp && timeout 900 bwrap --bind "$ROOT" / --proc /proc --dev /dev --tmpfs /tmp --bind "$OUT" /tmp/pfx \
    --setenv WINEPREFIX /tmp/pfx --setenv WINEDEBUG -all --setenv HOME /root --setenv XDG_RUNTIME_DIR /tmp \
    --setenv PATH /usr/bin:/bin:/usr/sbin:/sbin \
    sh -c '/usr/bin/wine64 wineboot --init; /usr/bin/wineserver -w') > "$WD/prefix.log" 2>&1 || exit 1
[ -f "$OUT/drive_c/windows/system32/ws2_32.dll" ] || { echo "MKPREFIX: prefix incomplete"; exit 1; }
SERVICES_TIMEOUT_MS_HEX=${SERVICES_TIMEOUT_MS_HEX:-000493e0}
printf '\n[System\\\\ControlSet001\\\\Control] %s\n"ServicesPipeTimeout"=dword:%s\n"WaitToKillServiceTimeout"="120000"\n' "$(date +%s)" "$SERVICES_TIMEOUT_MS_HEX" >> "$OUT/system.reg"
linked=0
for arch in x86_64-windows i386-windows; do
    for dir in system32 syswow64; do
        [ "$arch$dir" = x86_64-windowssyswow64 ] && continue
        [ "$arch$dir" = i386-windowssystem32 ] && continue
        for f in "$OUT/drive_c/windows/$dir"/*; do
            [ -f "$f" ] && [ ! -L "$f" ] || continue
            src=$ROOT$WINE_DLLS/$arch/$(basename "$f")
            if [ -f "$src" ] && cmp -s "$f" "$src"; then
                ln -sf "$WINE_DLLS/$arch/$(basename "$f")" "$f"
                linked=$((linked + 1))
            fi
        done
    done
done
echo "MKPREFIX: $linked files linked, $(du -sh "$OUT" | cut -f1) left in $OUT"
