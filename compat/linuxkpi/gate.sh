#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
FETCH=compat/linuxkpi/fetch.sh
PACK=compat/linuxkpi/pack.sh
MK="python3 -I tools/drvstore/mkpkg.py"
NEEDLE='linuxkpi|lkpi|Linux version|vermagic=|\.modinfo'

tracked=$(git ls-files third_party kernel/linuxkpi '*.ko' | wc -l)
[ "$tracked" -eq 0 ] && ok "repo tracks no Linux source, shim or .ko" || bad "repo tracks $tracked Linux files"

leaks=$(grep -rIl -iE 'linuxkpi|lkpi' kernel boot lib module tools/build-kernel.sh tools/mkfsfi tools/sync tools/module 2>/dev/null | wc -l)
[ "$leaks" -eq 0 ] && ok "no kernel/boot/lib/module/image-build file references linuxkpi" || bad "$leaks image-side files reference linuxkpi"

if [ -n "${LINUXKPI_IMAGE:-}" ]; then IMG="$LINUXKPI_IMAGE"
else
    IMG="$D/std.img"
    ./tools/build-kernel.sh "$IMG" --stufe 0 > "$D/k.txt" 2>&1 || { bad "standard kernel image builds"; tail -3 "$D/k.txt"; }
fi
scan() { grep -qaE -- "$NEEDLE" "$1"; }
if [ -s "$IMG" ]; then
    scan "$IMG" && bad "standard image contains linuxkpi/Linux marker" || ok "standard image contains no linuxkpi/Linux object"
    cp "$IMG" "$D/dirty.img"; printf 'lkpi_shim_marker vermagic=6.12.101' >> "$D/dirty.img"
    scan "$D/dirty.img" && ok "counter-proof: injected linuxkpi marker detected" || bad "counter-proof: marker not detected"
fi

printf 'x' > "$D/bad.tar.xz"
LINUXKPI_TARBALL="$D/bad.tar.xz" bash $FETCH bochs "$D/f1" >/dev/null 2>&1; [ $? -eq 3 ] && ok "fetch: tarball with wrong sha256 rejected" || bad "fetch: wrong tarball accepted"
bash $FETCH bochs "$(pwd)/compat/linuxkpi/out" >/dev/null 2>&1; [ $? -eq 2 ] && ok "fetch: output inside repo refused" || bad "fetch: repo output accepted"
bash $FETCH nosuch "$D/f2" >/dev/null 2>&1; [ $? -eq 2 ] && ok "fetch: unknown driver refused" || bad "fetch: unknown driver accepted"
mkdir -p "$D/f3"; touch "$D/f3/x"; bash $FETCH bochs "$D/f3" >/dev/null 2>&1; [ $? -eq 2 ] && ok "fetch: non-empty output refused" || bad "fetch: non-empty output accepted"

printf 'OSUMMOD-kpi' > "$D/linuxkpi.omod"; printf 'OSUMMOD-drv' > "$D/drv.omod"; printf 'fwdata' > "$D/bochs.bin"
pkg=$(bash $PACK bochs "$D/linuxkpi.omod" "$D/drv.omod" "$D/out" "$D/bochs.bin" 2>/dev/null)
[ -n "$pkg" ] && [ "$($MK check "$pkg")" = OK ] && ok "pack: signed store package passes mkpkg check" || bad "pack: package invalid"
for f in linuxkpi.omod drv.omod SOURCES.txt driver.inf driver.inf.sig bochs.bin; do [ -e "$pkg/$f" ] && ok "pack: $f in package" || bad "pack: $f missing"; done
grep -q '^license=GPL-2.0-or-later' "$pkg/SOURCES.txt" && grep -q '^linux_version=6.12.101' "$pkg/SOURCES.txt" && ok "pack: manifest carries source, version, license" || bad "pack: manifest incomplete"
grep -q '^fw=bochs.bin:' "$pkg/driver.inf" && ok "pack: firmware hash in signed manifest" || bad "pack: firmware hash missing"
printf 'z' >> "$pkg/driver.inf.sig"; flip=$($MK check "$pkg" 2>&1 || true)
cp "$pkg/driver.inf.sig" "$D/sig"; head -c 64 "$D/sig" | tr '\000-\377' '\001-\377\000' > "$pkg/driver.inf.sig"
($MK check "$pkg" 2>&1 || true) | grep -q INVALID && ok "counter-proof: tampered signature rejected" || bad "tampered signature accepted"

echo "LINUXKPI: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
