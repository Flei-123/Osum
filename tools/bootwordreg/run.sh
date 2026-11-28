#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/summary.sh
. tools/lib/pidkill.sh
. tools/lib/tmpdir.sh

TMPD=$(mktemp -d)
osum_tmp_guard "" "$TMPD"
summary_begin BOOTWORDREG
trap 'summary_guard; rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

BASE_WORDS="osum nokbd noproc nofs noring3 modedump"

fresh_copy() {
    rm -rf "$TMPD/t"
    mkdir -p "$TMPD/t"
    cp -r kernel "$TMPD/t/kernel"
    cp -r tools "$TMPD/t/tools"
}

expect_fail() {
    local label=$1 needle=$2 out
    out=$(cd "$TMPD/t" && python3 -I tools/bootwordreg/check.py 2>&1)
    if [ $? -ne 0 ] && echo "$out" | grep -q "$needle"; then ok "$label"; else bad "$label: $out"; fi
}

boot_modes() {
    local kernel=$1 words=$2 log="$TMPD/serial.txt" pid i
    rm -f "$log"
    $QEMU_X86 -kernel "$kernel" -m 256 -smp 2 -append "$BASE_WORDS $words" \
        -serial "file:$log" -display none -no-reboot >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 1 300); do
        grep -aq '^boot: modes' "$log" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    osum_kill_tree "$pid"
    wait "$pid" 2>/dev/null
    grep -a '^boot: modes' "$log" | head -1
}

echo "== 1. registry tables are consistent =="
out=$(python3 -I tools/bootwordreg/check.py 2>&1)
[ $? -eq 0 ] && ok "$out" || bad "$out"

echo "== 2. unknown words are reported =="
out=$(python3 -I tools/bootwordreg/check.py --unknown "osum nofdlock trap=de bogusword" 2>&1)
if [ $? -ne 0 ] && echo "$out" | grep -q "UNKNOWN word: bogusword" && ! echo "$out" | grep -q "UNKNOWN word: nofdlock\|UNKNOWN word: trap=de"; then
    ok "bogusword is reported, registered and handwritten words are known"
else
    bad "unknown word check: $out"
fi

echo "== 3. counter-proofs on a broken copy =="
fresh_copy
sed -i 's/^const COUNT: u64 = 4/const COUNT: u64 = 5/' "$TMPD/t/kernel/lib/modes/words_idle.fi"
expect_fail "a wrong COUNT is caught" "words_idle.fi"
fresh_copy
sed -i 's/static mut names: \[u8; 43\]/static mut names: [u8; 42]/' "$TMPD/t/kernel/lib/modes/words_idle.fi"
expect_fail "a hand-counted blob size that is off by one is caught" "declared 42 bytes"
fresh_copy
sed -i 's/^const M_NOKICKLOOP: u64 = 1333/const M_NOKICKLOOP: u64 = 1332/' "$TMPD/t/kernel/lib/modes/words_idle.fi"
expect_fail "two words on one bit are caught" "bit 1332"
fresh_copy
sed -i '/bootword.parse(state, cmd, (&words_diag.names/d' "$TMPD/t/kernel/init/bootwords.fi"
expect_fail "a group missing from the registry is caught" "words_diag"
fresh_copy
printf 'fn extra_word(state: u64, cmd: u64) {\n    var w_x: [u8; 10] = "nohaltpoll\\0"\n    if cmdword.find(cmd, (&w_x[0]) as u64, 9) != 0 {\n    }\n}\n' >> "$TMPD/t/kernel/init/bootmisc.fi"
expect_fail "a registered word that is handwritten again is caught" "still handwritten"

echo "== 4. every registered word reaches the bit map =="
KERNEL=${KERNEL:-}
if [ -z "$KERNEL" ]; then
    KERNEL="$TMPD/osum.mb"
    /root/jarvis/bin/heavy bash tools/build-kernel.sh "$KERNEL" --stufe 0 >"$TMPD/build.log" 2>&1 || { bad "kernel build failed"; tail -5 "$TMPD/build.log"; }
fi
words=$(python3 -I tools/bootwordreg/check.py --words)
base=$(boot_modes "$KERNEL" "")
all=$(boot_modes "$KERNEL" "$words")
bogus=$(boot_modes "$KERNEL" "bogusword")
[ -n "$base" ] && [ -n "$all" ] && ok "kernel boots with and without the registered words" || bad "no 'boot: modes' line (base='$base' all='$all')"
[ "$base" = "$bogus" ] && ok "an unknown word changes no bit" || bad "unknown word changed the bit map"
expected=$(python3 -I - "$base" <<'PY'
import re, sys
from pathlib import Path
words = [int(w, 16) for w in sys.argv[1].split()[2:]]
for path in sorted(Path("kernel/lib/modes").glob("words_*.fi")):
    text = path.read_text()
    consts = dict(re.findall(r"^const (M_\w+): u64 = (\d+)", text, re.M))
    listed = re.search(r"static mut bits: \[u64; \d+\] = \[(.*)\]", text).group(1).split(",")
    for name in (item.strip() for item in listed):
        bit = int(consts[name])
        words[bit // 64] |= 1 << (bit % 64)
print(" ".join("0x%x" % w for w in words))
PY
)
got=$(echo "$all" | sed 's/^boot: modes //; s/ *$//')
[ "$got" = "$expected" ] && ok "registered words set exactly their bits: $got" || bad "bit map differs: got '$got' expected '$expected'"

echo "== 5. same bit map as the previous kernel =="
if [ -n "${OLD_KERNEL:-}" ]; then
    old=$(boot_modes "$OLD_KERNEL" "$words")
    [ "$old" = "$all" ] && ok "old and new kernel agree on every registered word" || bad "old '$old' vs new '$all'"
else
    ok "OLD_KERNEL not set, comparison skipped"
fi

echo "== 6. /proc/bootwords shows the registry and the live state =="
listing=$(KERNEL="$KERNEL" BW_WORDS="nohaltpoll nofdlock bogusword" bash tools/bootwordreg/proc.sh 2>&1)
echo "$listing" | grep -q "^nofdlock flag default=off now=on bit=1311" && ok "nofdlock listed and on" || bad "nofdlock line missing: $(echo "$listing" | head -3)"
echo "$listing" | grep -q "^nohaltpoll flag default=off now=on bit=1334" && ok "nohaltpoll listed and on" || bad "nohaltpoll line missing"
echo "$listing" | grep -q "^nokickloop flag default=off now=off bit=1333" && ok "nokickloop listed and off" || bad "nokickloop line missing"
echo "$listing" | grep -q "^idlespin flag default=off now=off bit=1325 test" && ok "idlespin is marked as a test word" || bad "idlespin test marker missing"
echo "$listing" | grep -q "bogusword" && bad "an unknown word shows up in the registry" || ok "unknown word is not in the registry listing"

summary_emit "$pass" "$fail" 16
