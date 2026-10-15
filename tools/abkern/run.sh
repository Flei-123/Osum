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
esp_conf() { mcopy -i "$ESP" ::/limine.conf - 2>/dev/null; }
esp_put()  { mcopy -o -i "$ESP" "$1" ::/limine.conf; }

# the ESP config of a run: MODE two = `default_entry: 2` and two entries (slot A, slot B),
# MODE none = one entry and no default_entry line. The script rides in the command line of
# every entry (`initsh script=...`), so whichever slot the loader picks runs it.
conf_write() { # file script mode
    local cl="osum vfs nokbd nosched noproc nofs noring3 initsh script=$2"
    {
        echo "timeout: 0"
        [ "$3" = two ] && echo "default_entry: 2"
        echo "verbose: yes"
        echo
        echo "/OrientOS A"
        echo "    protocol: multiboot1"
        echo "    path: boot():/osum.mb"
        echo "    cmdline: $cl"
        if [ "$3" = two ]; then
            echo
            echo "/OrientOS B"
            echo "    protocol: multiboot1"
            echo "    path: boot():/osum.mb"
            echo "    cmdline: $cl"
        fi
    } > "$1"
}
# boot the installed disk through OVMF + Limine with that ESP config (oneshot.sh must not rewrite it)
lauf() { # name script mode
    conf_write "$OUT/$1.conf" "$2" "$3"
    esp_put "$OUT/$1.conf" || { echo "mcopy failed" >&2; return 1; }
    esp_conf > "$OUT/$1.before"
    ESP_KEEP=1 OUT="$OUT" bash tools/install/oneshot.sh "$1" platte "$2" 600 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    esp_conf > "$OUT/$1.after"
    cat "$OUT/$1.rc" 2>/dev/null
}

echo "== 1. build + install =="
printf 'gen=00000001 vor=00000000 v=02 ok=0\n' > "$OUT/erp"
[ "$(stat -c%s "$OUT/erp")" = 36 ] && ok "trial seed is 36 octets" || bad "seed size"
bash tools/install/pakete.sh "$OUT" > "$OUT/pak.log" 2>&1 && ok "base packages built (/quelle1: generation 0 needs /system/AKTUELL)" || bad "pakete.sh"
EXTRA="/erpseed=$OUT/erp" bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built" || { tail -20 "$OUT/build.log"; bad "build.sh"; }
rm -f "$OUT/ziel.img"
head -c $((96 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 > /dev/null 2>&1
gleich "install onto empty disk" "$(cat "$OUT/inst.rc" 2>/dev/null)" "21"

echo
echo "== 2. no trial: the ESP stays untouched =="
rc=$(lauf n1 "opk install /quelle1/hallo-1.opk;cp /erpseed /system/ERPROBUNG;exit" two)
gleich "boot 1 (arms the trial file)" "$rc" "21"
hat "$OUT/n1.txt" "ab: keine erprobung" "no trial file yet -> kernel does nothing"
hatnicht "$OUT/n1.txt" "ab: esp:" "no ESP access without a failed trial"
grep -qa '^default_entry: 2' "$OUT/n1.after" && ok "default_entry is still 2" || bad "ESP changed without a trial"

echo
echo "== 3. trial used up: kernel flips the loader back to slot A =="
rc=$(lauf f1 "exit" two)
gleich "boot 2 (3rd attempt)" "$rc" "21"
hat "$OUT/f1.txt" "ab: ERPROBUNG gescheitert, zurueck auf 0" "generation rolled back"
hat "$OUT/f1.txt" "ab: esp: default_entry set to 1" "kernel reports the flip"
grep -qa '^default_entry: 1' "$OUT/f1.after" && ok "ESP now reads default_entry: 1" || bad "ESP not flipped"
cmp -s <(sed 's/^default_entry: 2/default_entry: 1/' "$OUT/f1.before") "$OUT/f1.after" \
    && ok "only that one byte changed, the rest of the config is identical" || bad "config differs elsewhere"
mdir -i "$ESP" :: > /dev/null 2>&1 && ok "ESP FAT is still readable after the write" || bad "ESP FAT damaged"

echo
echo "== 4. counter-proof: confirmed generation -> no flip =="
rc=$(lauf c1 "exit" two)
gleich "boot 3" "$rc" "21"
hat "$OUT/c1.txt" "ab: gen=0 bestaetigt" "nothing in trial any more"
hatnicht "$OUT/c1.txt" "ab: esp:" "no ESP access"
grep -qa '^default_entry: 2' "$OUT/c1.after" && ok "ESP stays at default_entry: 2" || bad "flipped without a failed trial"

echo
echo "== 5. ESP config without default_entry =="
rc=$(lauf z1 "cp /erpseed /system/ERPROBUNG;exit" none)
rc=$(lauf z2 "exit" none)
hat "$OUT/z2.txt" "ab: ERPROBUNG gescheitert, zurueck auf 0" "rollback happens again"
hat "$OUT/z2.txt" "ab: esp: no default_entry" "kernel says there is no default_entry line"
cmp -s "$OUT/z2.before" "$OUT/z2.after" && ok "config untouched" || bad "config was modified"

echo
echo "abkern: $pass/$fail OK/FAIL"
[ "$fail" = 0 ]
