#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xfer/run.sh -- the transfer service (clipboard, primary selection, drag payload): one service, typed lazy items.
#
#   bash tools/xfer/run.sh [workdir]
#
# 1. console: tools/xfer/guest.sh runs inside the guest through /bin/xclip; tools/xfer/check.py judges the serial output
#    (round trips 100 B .. 2 MiB with FNV sums, lazy handover counted by offers/fills, mime negotiation, custom mime types,
#    primary vs clipboard, ring of 20, file lists, drag slot next to the notification ring, no segment leak)
# 2. COUNTER-PROBES: three mutated copies of the tree must turn exactly the checks red that they should
#    (no segment adoption, no lazy handover, no release of evicted segments)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
if [ -n "${1:-}" ]; then
    OUT=$1
else
    OUT=$(mktemp -d)
    trap 'rm -rf "$OUT"' EXIT
fi
mkdir -p "$OUT"
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "XFER: skipped, no qemu"; exit 0; }
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

PROGS="sh echo ls cat sleep xclip"

boot_tree() { # tree out
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" mager=yes shot=no progs="$PROGS" \
        xfile="/xfer.sh=$ROOT/tools/xfer/guest.sh" script="sh /xfer.sh" ) > "$2.log" 2>&1
}

expect() { # serial check-name state
    local line
    line=$(python3 "$ROOT/tools/xfer/check.py" "$1" | grep -a "^CHECK $2 " | head -1)
    case "$3:$line" in
        ok:*" ok "*) ok "$2" ;;
        fail:*" fail "*) ok "counter-probe: $2 turns red" ;;
        *) bad "$2 -- expected $3, got: ${line:-missing}" ;;
    esac
}

echo "== 1. the service, end to end in the guest =="
boot_tree "$ROOT" "$OUT/main" || { bad "build/run failed"; tail -n 15 "$OUT/main.log"; }
S="$OUT/main/serial.txt"
[ -s "$S" ] && grep -aq "kernel: done" "$S" && ok "guest script ran to the end" || bad "guest script did not finish"
python3 "$ROOT/tools/xfer/check.py" "$S" > "$OUT/main.checks" 2>&1
while read -r _ name state note; do
    if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
done < "$OUT/main.checks"
[ "$(wc -l < "$OUT/main.checks")" -ge 30 ] && ok "all check groups reported" || bad "check groups missing"

echo
echo "== 2. COUNTER-PROBES: mutated trees =="
mutant() { # name file sed-expression expected-red-checks...
    local name=$1 file=$2 expr=$3
    shift 3
    local T="$OUT/mut-$name"
    mkdir -p "$T"
    tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$T" -xf -
    sed -i "$expr" "$T/$file"
    if cmp -s "$T/$file" "$ROOT/$file"; then bad "mutant $name: the sed expression changed nothing"; rm -rf "$T"; return; fi
    ( cd "$T" && ALLTAGBUILD="$OUT/mut-$name.build" bash tools/alltag/build.sh "$OUT/mut-$name-run" mager=yes shot=no progs="$PROGS" \
        xfile="/xfer.sh=$ROOT/tools/xfer/guest.sh" script="sh /xfer.sh" ) > "$OUT/mut-$name.log" 2>&1
    local MS="$OUT/mut-$name-run/serial.txt"
    [ -s "$MS" ] && ok "mutant $name booted" || { bad "mutant $name did not boot"; rm -rf "$T"; return; }
    local c
    for c in "$@"; do expect "$MS" "$c" fail; done
    rm -rf "$T" "$OUT/mut-$name.build"
}
mutant noadopt kernel/bus/bus.fi 's/seg_set(state, id, G_OWNER, ADOPT_PID)/seg_set(state, id, G_OWNER, seg_at(state, id, G_OWNER))/' \
    roundtrip_1048576 roundtrip_2097152
mutant eagerlazy kernel/bus/slots.fi 's/if (bus.item_get(a, bus.I_PRIO) & bit) == 0 {/if false {/' \
    lazy_fill_on_paste lazy_data_exact
mutant norelease kernel/bus/slots.fi 's/        bus.seg_release(state, seg1 - 1)/        let _z: u64 = seg1/' \
    eviction_frees_segments no_segment_leak

echo
echo "== 3. real programs: file manager <-> xclip, image viewer <-> xclip, editor -> terminal =="
has() { grep -qaE -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- missing: $2"; }
hasnt() { grep -qaE -- "$2" "$1" 2>/dev/null && bad "$3 -- present: $2" || ok "$3"; }
python3 "$ROOT/tools/xfer/mkpng.py" "$OUT/png"

capture() { # tree out progs extra drehscript imgfiles
    ( cd "$1" && bash "$ROOT/tools/xfer/$5" > "$2.dreh" &&
      DESIGNBUILD="$2.build" bash tools/design/capture.sh "$2" res=1280x800 uitrace=yes progs="$3" extra="$4" \
        imgfiles="$6" drehbuch="$2.dreh" ) > "$2.log" 2>&1
}

FILES_PROGS="desktop taskbar launcher settings theme explorer sh echo ls cat runbox xclip sleep"
capture "$ROOT" "$OUT/files" "$FILES_PROGS" 'nostart wigapp=/bin/explorer' dreh-files.sh ""
F="$OUT/files/serial.txt"
has "$F" "explorer: clip n=8 schnitt=0 rc=0" "explorer: Ctrl+A, Ctrl+C put 8 paths on the bus"
has "$F" "xclip: types mask=16 have=16" "the bus holds a text/uri-list (type bit 16), nothing else"
has "$F" "xclip: uris n=8" "another program reads the same 8 paths back from the list"
has "$F" "xclip: uri /data/beta.txt" "the paths are decoded"
has "$F" "xclip: puturis n=" "another program puts a one-file list on the clipboard"
has "$F" "explorer: paste n=1 sprung=0 pos=0 rc=0" "Ctrl+V in the file manager pastes what the OTHER program put (1 file, not its own 8)"
disk_same() { # image
    python3 "$ROOT/tools/xfer/disk.py" sum "$1" /data/beta.txt /data/bilder/beta.txt > "$1.sum" 2>&1
    local a b
    a=$(grep -a "^file /data/beta.txt" "$1.sum" | grep -o "sha=.*")
    b=$(grep -a "^file /data/bilder/beta.txt" "$1.sum" | grep -o "sha=.*")
    [ -n "$a" ] && [ "$a" = "$b" ]
}
disk_same "$OUT/files/disk.img" && ok "the host finds /data/bilder/beta.txt in the image with the same content" || bad "the pasted file is missing or differs"

capture "$ROOT" "$OUT/image" "desktop taskbar launcher explorer viewer sh echo runbox xclip sleep" 'nostart wigapp=/bin/viewer,/a.png' dreh-image.sh \
    "/a.png=$OUT/png/a.png@0644 /b.png=$OUT/png/b.png@0644"
I="$OUT/image/serial.txt"
has "$I" "viewer: clip offer 0" "viewer: Ctrl+C offers the picture"
has "$I" "xclip: stat offers=1 fills=0" "nothing was encoded at copy time (offers=1 fills=0)"
has "$I" "xclip: stat offers=1 fills=1" "encoded when another program pasted (fills=1)"
N=$(grep -ao "viewer: clip filled [0-9]*" "$I" | head -1 | grep -o "[0-9]*$")
G=$(grep -ao "xclip: getfile n=[0-9]*" "$I" | head -1 | grep -o "[0-9]*$")
[ -n "$N" ] && [ "${N:-0}" -gt 0 ] && [ "$N" = "$G" ] && ok "the paster received exactly what the viewer encoded ($N octets)" || bad "encoded $N, received $G"
python3 "$ROOT/tools/xfer/disk.py" png "$OUT/image/disk.img" /out.png "$OUT/png/a.png" 2>/dev/null | grep -q "^png same size=96x64" \
    && ok "the file written from the clipboard is a PNG with the pixels of the picture" || bad "pasted PNG differs"
has "$I" "viewer: clip paste 248 w=40 h=30" "viewer: Ctrl+V opens the picture another program put there"

capture_term() { # tree out
    ( cd "$1" && DESIGNBUILD="$2.build" bash tools/design/eh6.sh "$2" accel=kvm moreprogs="nedit xclip runbox" \
        xfile="/note.sh=$ROOT/tools/xfer/note.sh" drehbuch="$ROOT/tools/xfer/dreh-term.txt" ) > "$2.log" 2>&1
}
capture_term "$ROOT" "$OUT/term"
T="$OUT/term/serial.txt"
has "$T" "wm: tpaste t=" "a paste was asked for in the terminal"
grep -aE "wm: termzeile [0-9]+ \[XFER-NEDIT-TO-TERM\]" "$T" >/dev/null && ok "the shell in the terminal ran the line copied in the editor (output row XFER-NEDIT-TO-TERM)" \
    || bad "the editor's text did not arrive in the terminal"

echo
echo "== 4. COUNTER-PROBE for the file manager: it ignores the clipboard when pasting =="
T2="$OUT/mut-explorer"
mkdir -p "$T2"; tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$T2" -xf -
sed -i 's/        let _l: u64 = expakt.load_from_bus()/        let _l: u64 = 0/' "$T2/kernel/user/explorer.fi"
if cmp -s "$T2/kernel/user/explorer.fi" "$ROOT/kernel/user/explorer.fi"; then bad "explorer mutant: the sed expression changed nothing"; else
    capture "$T2" "$OUT/files-mut" "$FILES_PROGS" 'nostart wigapp=/bin/explorer' dreh-files.sh ""
    hasnt "$OUT/files-mut/serial.txt" "explorer: paste n=1 sprung=0 pos=0 rc=0" "mutant: without the bus the paste is NOT the other program's one file"
fi
rm -rf "$T2"

echo
echo "XFER: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
