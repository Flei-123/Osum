#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -u
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/licenses.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
NOTICES="python3 -I tools/licenses/notices.py"
PASS=0
FAIL=0
check() {
    if "$@" >/dev/null 2>&1; then PASS=$((PASS + 1)); echo "ok   $DESC"; else FAIL=$((FAIL + 1)); echo "FAIL $DESC"; fi
}
refuse() {
    if "$@" >/dev/null 2>&1; then FAIL=$((FAIL + 1)); echo "FAIL $DESC (accepted)"; else PASS=$((PASS + 1)); echo "ok   $DESC"; fi
}
public_specs() {
    printf '%s\n' "/lib/sans.ttf=assets/osum-sans.ttf" "/lib/bold.ttf=assets/osum-sans-bold.ttf" \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/serif.ttf=assets/osum-serif.ttf" "/lib/emoji.ttf=assets/osum-emoji.ttf" \
        "/lib/symbols.ttf=assets/osum-symbols.ttf" "/lib/icons.ttf=assets/osum-icons.ttf" \
        "/lib/ld-musl-x86_64.so.1=assets/musl/ld-musl-x86_64.so.1" "/etc/ssl/roots.pem=$WORK/out/roots.pem" \
        "/usr/share/wayd/keymap-us.xkb=$WORK/out/keymap" "/boot/limine.efi=$WORK/out/limine.efi" "/boot/osum.mb=$WORK/out/osum.mb" \
        "/bin/certus=$WORK/out/certus" "/bin/desktop=$WORK/out/desktop" "--v3" "/lib/"
}
mkdir -p "$WORK/out"
: > "$WORK/out/roots.pem"; : > "$WORK/out/keymap"; : > "$WORK/out/limine.efi"; : > "$WORK/out/osum.mb"; : > "$WORK/out/certus"; : > "$WORK/out/desktop"
DESC="registry lint"; check $NOTICES lint
DESC="package manifests carry license="; check $NOTICES packages
public_specs > "$WORK/public.in"
DESC="public image specs accepted"; check $NOTICES image public "$WORK/out/licenses" "$WORK/public.in"
mkdir -p "$WORK/out/licenses"
$NOTICES image public "$WORK/out/licenses" "$WORK/public.in" >/dev/null 2>&1
N="$WORK/out/licenses/THIRD-PARTY-NOTICES"
for id in "Inter subset" "musl libc" "Limine" "DejaVu" "Certus" "Osum kernel"; do
    DESC="notices name $id"; check grep -q "$id" "$N"
done
DESC="notices omit personal-only busybox"; refuse grep -q "BusyBox" "$N"
DESC="specs ship licence texts"; check grep -q "^/usr/share/licenses/inter/LICENSE-OFL-inter.txt=" "$WORK/out/licenses/specs.txt"
mapfile -t SPECS < "$WORK/out/licenses/specs.txt"
DESC="mkfs builds image with licence folder"; check bash tools/mkfsfi/mkfs.sh build "$WORK/root.img" 4000 --v3 "${SPECS[@]}"
bash tools/mkfsfi/mkfs.sh list "$WORK/root.img" > "$WORK/list.txt" 2>&1
DESC="image lists THIRD-PARTY-NOTICES"; check grep -q "/usr/share/licenses/THIRD-PARTY-NOTICES" "$WORK/list.txt"
DESC="image lists OFL text"; check grep -q "/usr/share/licenses/inter/LICENSE-OFL-inter.txt" "$WORK/list.txt"
try_extra() {
    { cat "$WORK/public.in"; printf '%s\n' "$1"; } > "$WORK/bad.in"
    $NOTICES image public "$WORK/out/bad" "$WORK/bad.in"
}
DESC="counter: unknown .ttf rejected"; refuse try_extra "/lib/evil.ttf=assets/osum-sans.ttf"
DESC="counter: unknown .so rejected"; refuse try_extra "/usr/lib/libfoo.so.1=assets/osum-sans.ttf"
DESC="counter: unknown firmware rejected"; refuse try_extra "/lib/firmware/x/blob.bin=assets/osum-sans.ttf"
DESC="counter: foreign source outside repo rejected"; refuse try_extra "/bin/mystery=/etc/hostname"
DESC="counter: personal-only busybox rejected in public"; refuse try_extra "/bin/busybox=/etc/hostname"
DESC="personal profile accepts busybox"; check bash -c "{ cat '$WORK/public.in'; echo '/bin/busybox=/etc/hostname'; } > '$WORK/p.in'; $NOTICES image personal '$WORK/out/pers' '$WORK/p.in'"
mktree() {
    mkdir -p "$1"
    for entry in "$ROOT"/*; do [ "$(basename "$entry")" = licenses ] || ln -s "$entry" "$1/"; done
    mkdir -p "$1/licenses"
    cp -r "$ROOT/licenses/texts" "$ROOT/licenses/registry.txt" "$1/licenses/"
}
mktree "$WORK/clean"
DESC="control: copied tree lints clean"; check env LICENSES_ROOT="$WORK/clean" $NOTICES lint
mktree "$WORK/bad1"
echo "ghost|Ghost|1|MIT|public|/bin/ghost|licenses/texts/nope.txt|https://x|x" >> "$WORK/bad1/licenses/registry.txt"
DESC="counter: missing licence text fails lint"; refuse env LICENSES_ROOT="$WORK/bad1" $NOTICES lint
mktree "$WORK/bad2"
echo "stub|Stub|1|OFL-1.1|public|/bin/stub|licenses/texts/limine-BSD-2-Clause.txt|https://x|x" >> "$WORK/bad2/licenses/registry.txt"
DESC="counter: reference-only licence text fails lint"; refuse env LICENSES_ROOT="$WORK/bad2" $NOTICES lint
mktree "$WORK/bad3"
rm "$WORK/bad3/pakete"; cp -r "$ROOT/pakete" "$WORK/bad3/pakete"; mkdir -p "$WORK/bad3/pakete/p"; printf 'name=P\n' > "$WORK/bad3/pakete/p/INFO"
DESC="counter: package without license= rejected"; refuse env LICENSES_ROOT="$WORK/bad3" $NOTICES packages
if [ -d /root/stones ]; then
    DESC="personal dev stones fully covered"
    check bash -c ". tools/unterbau/devstones.sh; { devstones_spec /root/stones | tr ' ' '\\n'; printf '%s\\n' /bin/curl=/root/stones/curl /bin/git=/root/stones/git; } > '$WORK/stones.in'; $NOTICES image personal '$WORK/out/stones' '$WORK/stones.in'"
fi
HPLIST=${HP_LISTING:-/root/abbilder/hp-base-6243/liste.txt}
if [ -r "$HPLIST" ]; then DESC="HP image listing fully covered"; check $NOTICES listing personal "$HPLIST"; fi
echo "licenses gate: $PASS ok / $FAIL fail"
[ "$FAIL" = 0 ]
