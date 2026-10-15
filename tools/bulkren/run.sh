#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bulkren/run.sh -- D3: MASS RENAME (lib/bulkren/plan.fi + kernel/user/expakt.fi mass_* +
# the explorer dialog), MEASURED.
#
#   bash tools/bulkren/run.sh [stage ...]      (stages: host guest build; default all; use heavy)
#
# host   the plan engine against tools/bulkren/plan.fi (pattern, counter, find/replace, case,
#        conflicts) + MUTATION control: a lib with the zero padding broken must turn it red
# guest  /bin/massren (the same engine as the explorer dialog) in a QEMU guest on real files:
#        pattern + counter keep the CONTENT, a chain (1->2, 2->3, 3->4) overwrites nothing, a
#        conflict (taken name / two files one name) renames NOTHING, --undo brings the names back
# build  the explorer (dialog, preview, apply) compiles + links and the locale key exists in both languages
# DOES NOT MEASURE: the pixels of the dialog, clicks (UI gate: not written yet), case-insensitive disks.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
STAGES=${*:-host guest build}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

stage_host() {
    echo "== stage host =="
    $FIRNC tools/bulkren/plan.fi -o "$T/plan" 2> "$T/p.err" && ok "plan test builds" || { bad "plan test build"; head -5 "$T/p.err"; return; }
    "$T/plan" > "$T/plan.txt" 2>&1
    local n1 n2; n1=$(grep -c '^OK' "$T/plan.txt"); n2=$(grep -c '^FAIL' "$T/plan.txt")
    sed -n 's/^FAIL /  FAIL  plan: /p' "$T/plan.txt"
    [ "$n2" = 0 ] && [ "$n1" -ge 38 ] && ok "plan engine: $n1 checks OK, 0 FAIL" || bad "plan engine ($n1 ok, $n2 fail)"
    pass=$((pass+n1))
    # mutation: zero padding broken (width ignored) must be red
    mkdir -p "$T/lib-mut"
    for d in lib/*; do [ "$(basename "$d")" = bulkren ] || ln -s "$ROOT/$d" "$T/lib-mut/$(basename "$d")"; done
    mkdir -p "$T/lib-mut/bulkren"
    sed 's/    var pad: u64 = 0/    var pad: u64 = 0\n    let _w: u64 = width/; s/        pad = width - d/        pad = 0/' lib/bulkren/plan.fi > "$T/lib-mut/bulkren/plan.fi"
    if FIRNLIB="$T/lib-mut" $FIRNC tools/bulkren/plan.fi -o "$T/plan-mut" 2>/dev/null; then
        local m; m=$("$T/plan-mut" 2>&1 | grep -c '^FAIL')
        [ "$m" -gt 0 ] && ok "mutation (no zero padding) -> $m red checks" || bad "mutation stayed green"
    else
        bad "mutation build failed"
    fi
}

stage_guest() {
    echo "== stage guest =="
    bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
    mkdir -p "$T/bin"
    local PROGS="sh ls cat echo massren"
    bash tools/sync/build.sh "$T/bin" 0 $PROGS > "$T/b.txt" 2>&1 \
        && ok "massren + tools build" || { bad "guest programs build"; head -15 "$T/b.txt"; return; }
    ./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 \
        && ok "kernel builds" || { bad "kernel build"; return; }
    local f
    for f in a b c d e g h; do printf 'content-%s\n' "$f" > "$T/f$f"; done
    cat > "$T/s.sh" <<'EOS'
echo ==S1==
massren /t/d1 [N]_[C][E] a.txt b.txt c.png
ls /t/d1
cat /t/d1/a_1.txt
cat /t/d1/c_3.png
echo ==S2==
massren /t/d2 '[C][E]|||2,1,1' 1.jpg 2.jpg 3.jpg
ls /t/d2
cat /t/d2/2.jpg
cat /t/d2/3.jpg
cat /t/d2/4.jpg
echo ==S3==
massren /t/d3 y.txt x1.txt x2.txt
ls /t/d3
echo ==S4==
massren /t/d3 y.txt x1.txt
ls /t/d3
cat /t/d3/y.txt
echo ==S5==
massren /t/d4 [N]_[C][E] a.txt b.txt --undo
ls /t/d4
cat /t/d4/a.txt
echo ==S6==
massren /t/d5 '[N][E]|IMG|Holiday||u' IMG-1.png IMG-2.png
ls /t/d5
echo ==END==
EOS
    python3 tools/osum/mkfs.py build "$T/d.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /t/d1/ /t/d2/ /t/d3/ /t/d4/ /t/d5/ \
        $(for p in $PROGS; do echo "/bin/$p=$T/bin/$p.elf"; done) \
        "/t/s.sh=$T/s.sh" \
        "/t/d1/a.txt=$T/fa" "/t/d1/b.txt=$T/fb" "/t/d1/c.png=$T/fc" \
        "/t/d2/1.jpg=$T/fa" "/t/d2/2.jpg=$T/fb" "/t/d2/3.jpg=$T/fc" \
        "/t/d3/x1.txt=$T/fd" "/t/d3/x2.txt=$T/fe" "/t/d3/y.txt=$T/fg" \
        "/t/d4/a.txt=$T/fa" "/t/d4/b.txt=$T/fb" \
        "/t/d5/IMG-1.png=$T/fa" "/t/d5/IMG-2.png=$T/fb" > "$T/mkfs.txt" 2>&1 || tail -3 "$T/mkfs.txt"
    local ACC=tcg; [ -e /dev/kvm ] && ACC=kvm
    timeout 200 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k0.img" -m 512 \
        -append "osum vfs nokbd script=sh /t/s.sh;exit" \
        -serial "file:$T/o.txt" -display none -no-reboot \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/o.txt" > "$T/o.klar"
    part() { awk -v a="==$1==" -v b="==$2==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/o.klar" | grep -v '^massren: preview'; }
    pv() { awk -v a="==$1==" -v b="==$2==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/o.klar" | grep -a '^massren: preview'; }
    has()    { printf '%s\n' "$1" | grep -qF -- "$2" && ok "$3" || bad "$3 -- '$2' missing"; }
    hasnot() { printf '%s\n' "$1" | grep -qF -- "$2" && bad "$3 -- '$2' is there" || ok "$3"; }
    local s1 s2 s3 s4 s5 s6
    s1=$(part S1 S2); s2=$(part S2 S3); s3=$(part S3 S4); s4=$(part S4 S5); s5=$(part S5 S6); s6=$(part S6 END)
    has "$s1" "apply rc=0" "S1 pattern+counter: apply rc=0"
    has "$s1" "a_1.txt" "S1: a.txt -> a_1.txt"; has "$s1" "b_2.txt" "S1: b.txt -> b_2.txt"; has "$s1" "c_3.png" "S1: c.png -> c_3.png (extension kept)"
    has "$s1" "content-a" "S1: content of a.txt survives the rename"; has "$s1" "content-c" "S1: content of c.png survives"
    hasnot "$s1" "b.txt" "S1: the old name b.txt is gone"
    has "$s2" "apply rc=0" "S2 chain 1->2,2->3,3->4: apply rc=0"
    has "$s2" "2.jpg" "S2: 2.jpg there"; has "$s2" "4.jpg" "S2: 4.jpg there"; hasnot "$s2" "1.jpg" "S2: 1.jpg is gone"
    has "$s2" "content-a" "S2: old 1.jpg (content-a) is now 2.jpg"; has "$s2" "content-c" "S2: old 3.jpg (content-c) is now 4.jpg"
    hasnot "$s2" ".bren~" "S2: no parking name left behind"
    hasnot "$s3" "apply rc=0" "S3 two files one name: refused"
    has "$s3" "stop rc=" "S3: the plan stops before anything is renamed"
    has "$s3" "x1.txt" "S3: x1.txt untouched"; has "$s3" "x2.txt" "S3: x2.txt untouched"
    has "$s4" "apply rc=" "S4 taken name y.txt: a rename was tried"
    hasnot "$s4" "apply rc=0" "S4: refused (rc != 0)"
    has "$s4" "content-g" "S4: the existing y.txt kept ITS content (nothing overwritten)"
    has "$s4" "x1.txt" "S4: x1.txt is still there"
    has "$s5" "undo rc=0" "S5 --undo: undo rc=0"
    has "$s5" "content-a" "S5: after undo a.txt has its content again"
    hasnot "$s5" "a_1" "S5: the new names are gone after undo"
    has "$s6" "HOLIDAY-1.PNG" "S6 find/replace + upper case: IMG-1.png -> HOLIDAY-1.PNG"
    hasnot "$s6" "IMG" "S6: the old text is gone"
}

stage_build() {
    echo "== stage build =="
    mkdir -p "$T/bin2"
    bash tools/sync/build.sh "$T/bin2" 0 explorer > "$T/e.txt" 2>&1 && [ -s "$T/bin2/explorer.elf" ] \
        && ok "explorer (rename-several dialog, preview, apply) compiles + links" || { bad "explorer build"; head -10 "$T/e.txt"; }
    grep -q '^explorer.massren = ' locale/de/messages && grep -q '^explorer.massren = ' locale/en/messages \
        && ok "locale key explorer.massren in de + en" || bad "locale key missing"
    grep -q 'was == 13' kernel/user/explorer.fi && grep -q 'was == 14' kernel/user/explorer.fi \
        && ok "explorer handles dialog codes 13 (rule) and 14 (confirm)" || bad "explorer dialog codes missing"
}

for s in $STAGES; do "stage_$s"; done
echo "BULKREN: $pass passed, $fail failed"
[ "$fail" = 0 ]
