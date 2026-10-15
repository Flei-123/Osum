#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/abkern/run.sh -- r104: KERNEL A/B, option 2 (docs/AB-KERNEL.md).
#
# When the trial attempts of a generation are used up, the KERNEL itself puts
# the boot loader back on slot A: it mounts the ESP of its boot disk and
# rewrites `default_entry: N` in /limine.conf to `default_entry: 1` (one byte).
# Measured on a real installed disk (GPT + FAT32 ESP) under QEMU/KVM.
#
#   bash tools/abkern/run.sh [--keep]
#
# SECTIONS
#   1. build + install onto an empty 96 MiB disk
#   2. no trial: the ESP stays untouched (default_entry: 2 stays 2)
#   3. trial used up: rollback line AND `default_entry: 2` -> 1, rest of the file identical
#   4. counter-proof: confirmed generation -> no flip, config stays at 2
#   5. no default_entry line in the ESP config -> reported, file untouched
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
KEEP=${1:-}
OUT=${OUT:-$(mktemp -d /tmp/abkern-run.XXXXXX)}
export OUT
[ "$KEEP" = "--keep" ] || trap 'rm -rf "$OUT"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
hat() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hatnicht() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present but must not be" || ok "$3"; }

ESP="$OUT/ziel.img@@1048576"
# boot the installed disk WITHOUT the loader (-kernel), so oneshot.sh leaves the
# ESP config alone; `initsh` makes init run the script on a fUi image
lauf() { # name script
    OSUM_EXTRA=initsh OUT="$OUT" bash tools/install/oneshot.sh "$1" roh "$2" 300 \
        > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}
esp_conf() { mcopy -i "$ESP" ::/limine.conf - 2>/dev/null; }
esp_put()  { mcopy -o -i "$ESP" "$1" ::/limine.conf; }

two_entries() { # file  (default_entry: 2 -> slot B)
    {
        echo "timeout: 0"
        echo "default_entry: 2"
        echo "verbose: yes"
        echo
        echo "/OrientOS A"
        echo "    protocol: multiboot1"
        echo "    path: boot():/osum.mb"
        echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3"
        echo
        echo "/OrientOS B"
        echo "    protocol: multiboot1"
        echo "    path: boot():/osum-b.mb"
        echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3"
    } > "$1"
}

echo "== 1. build + install =="
printf 'gen=00000001 vor=00000000 v=02 ok=0\n' > "$OUT/erp"
[ "$(stat -c%s "$OUT/erp")" = 36 ] && ok "trial seed is 36 octets" || bad "seed size"
EXTRA="/erpseed=$OUT/erp" bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built" || { tail -20 "$OUT/build.log"; bad "build.sh"; }
rm -f "$OUT/ziel.img"
head -c $((96 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 > /dev/null 2>&1
gleich "install onto empty disk" "$(cat "$OUT/inst.rc" 2>/dev/null)" "21"
two_entries "$OUT/two.conf"
esp_put "$OUT/two.conf" && ok "ESP config with two entries, default_entry: 2" || bad "mcopy to ESP"
esp_conf | grep -qa '^default_entry: 2' && ok "ESP config reads back with default_entry: 2" || bad "ESP read back"

echo
echo "== 2. no trial: the ESP stays untouched =="
rc=$(lauf n1 "cp /erpseed /system/ERPROBUNG;exit")
gleich "boot 1 (arms the trial file)" "$rc" "21"
hat "$OUT/n1.txt" "ab: keine erprobung" "no trial file yet -> kernel does nothing"
hatnicht "$OUT/n1.txt" "ab: esp:" "no ESP access without a failed trial"
esp_conf | grep -qa '^default_entry: 2' && ok "default_entry is still 2" || bad "ESP changed without a trial"

echo
echo "== 3. trial used up: kernel flips the loader back to slot A =="
esp_conf > "$OUT/before.conf"
rc=$(lauf f1 "exit")
gleich "boot 2 (3rd attempt)" "$rc" "21"
hat "$OUT/f1.txt" "ab: ERPROBUNG gescheitert, zurueck auf 0" "generation rolled back"
hat "$OUT/f1.txt" "ab: esp: default_entry set to 1" "kernel reports the flip"
esp_conf > "$OUT/after.conf"
grep -qa '^default_entry: 1' "$OUT/after.conf" && ok "ESP now reads default_entry: 1" || bad "ESP not flipped"
cmp -s <(sed 's/^default_entry: 2/default_entry: 1/' "$OUT/before.conf") "$OUT/after.conf" \
    && ok "only that one byte changed, the rest of the config is identical" || bad "config differs elsewhere"
mdir -i "$ESP" :: > /dev/null 2>&1 && ok "ESP FAT is still readable after the write" || bad "ESP FAT damaged"

echo
echo "== 4. counter-proof: confirmed generation -> no flip =="
esp_put "$OUT/two.conf"
rc=$(lauf c1 "exit")
gleich "boot 3" "$rc" "21"
hat "$OUT/c1.txt" "ab: gen=0 bestaetigt" "nothing in trial any more"
hatnicht "$OUT/c1.txt" "ab: esp:" "no ESP access"
esp_conf | grep -qa '^default_entry: 2' && ok "ESP stays at default_entry: 2" || bad "flipped without a failed trial"

echo
echo "== 5. ESP config without default_entry =="
{
    echo "timeout: 0"; echo "verbose: yes"; echo
    echo "/OrientOS"; echo "    protocol: multiboot1"; echo "    path: boot():/osum.mb"
    echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3"
} > "$OUT/one.conf"
esp_put "$OUT/one.conf"
rc=$(lauf z1 "cp /erpseed /system/ERPROBUNG;exit")
rc=$(lauf z2 "exit")
hat "$OUT/z2.txt" "ab: ERPROBUNG gescheitert, zurueck auf 0" "rollback happens again"
hat "$OUT/z2.txt" "ab: esp: no default_entry" "kernel says there is no default_entry line"
cmp -s "$OUT/one.conf" <(esp_conf) && ok "config untouched" || bad "config was modified"

echo
echo "abkern: $pass/$fail OK/FAIL"
[ "$fail" = 0 ]
