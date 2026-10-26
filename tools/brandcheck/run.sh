#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
SCAN="python3 -I $ROOT/tools/brandcheck/scan.py"
PATTERN='orientos|xoffi|orient os'
MODE=${1:-all}
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $*"; }
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

static_scan() {
    echo "== 1. product name only from the brand files =="
    if $SCAN > "$TMPD/hits.txt" 2> "$TMPD/count.txt"; then
        ok "no hard-coded product name outside tools/brandcheck/allow.txt"
    else
        bad "$(tail -1 "$TMPD/count.txt")"
        cut -c1-170 "$TMPD/hits.txt" | head -${BRANDCHECK_SHOW:-40}
        $SCAN --summary 2>/dev/null | head -15 | sed 's/^/        /'
    fi
}

make_tree() {
    local t=$1
    mkdir -p "$t/kernel" "$t/locale/de" "$t/tools/x"
    printf 'var x = 1\n' > "$t/kernel/a.fi"
    printf 'key=value\n' > "$t/locale/de/messages"
    printf '#!/bin/sh\necho hi\n' > "$t/tools/x/run.sh"
    : > "$t/allow.txt"
}

counter_proof() {
    echo "== 2. counter-proof: the scanner must catch planted hits =="
    local t=$TMPD/tree
    make_tree "$t"
    $SCAN --root "$t" --allow "$t/allow.txt" > /dev/null 2>&1 && ok "clean tree passes" || bad "clean tree reported"
    printf 'var s = "OrientOS"\n' > "$t/kernel/a.fi"
    $SCAN --root "$t" --allow "$t/allow.txt" > /dev/null 2>&1 && bad "planted OrientOS in kernel not caught" || ok "planted OrientOS in kernel caught"
    printf 'var x = 1\n' > "$t/kernel/a.fi"
    printf 'installer.title=Install XoffiOS\n' > "$t/locale/de/messages"
    $SCAN --root "$t" --allow "$t/allow.txt" > /dev/null 2>&1 && bad "planted XoffiOS in locale not caught" || ok "planted XoffiOS in locale caught"
    printf 'key=value\n' > "$t/locale/de/messages"
    printf 'echo "/EFI/orientos"\n' >> "$t/tools/x/run.sh"
    $SCAN --root "$t" --allow "$t/allow.txt" > /dev/null 2>&1 && bad "planted lower-case slug in tools not caught" || ok "planted lower-case slug in tools caught"
    printf 'tools/x/*\torientos\tcounter-proof reason\n' > "$t/allow.txt"
    $SCAN --root "$t" --allow "$t/allow.txt" > /dev/null 2>&1 && ok "allowlisted line passes" || bad "allowlisted line still reported"
    printf 'tools/x/*\torientos\n' > "$t/allow.txt"
    $SCAN --root "$t" --allow "$t/allow.txt" > /dev/null 2>&1 && bad "allow entry without reason accepted" || ok "allow entry without reason refused"
    : > "$t/allow.txt"
    printf '#!/bin/sh\n# OrientOS history note\n' > "$t/tools/x/run.sh"
    $SCAN --root "$t" --allow "$t/allow.txt" > /dev/null 2>&1 && ok "comment-only line passes by default" || bad "comment-only line reported"
    $SCAN --root "$t" --allow "$t/allow.txt" --comments > /dev/null 2>&1 && bad "--comments did not report the comment line" || ok "--comments reports the comment line"
}

artifact_hits() {
    local dir=$1 f
    : > "$TMPD/art.txt"
    for f in "$dir"/*; do
        [ -f "$f" ] || continue
        strings -a -n 5 "$f" | grep -iE "$PATTERN" | sed "s|^|$(basename "$f"): |" >> "$TMPD/art.txt"
    done
    if [ -s tools/brandcheck/allow-artifacts.txt ]; then
        grep -v '^#' tools/brandcheck/allow-artifacts.txt | cut -f1 | grep -v '^$' > "$TMPD/art-allow.txt"
        grep -viFf "$TMPD/art-allow.txt" "$TMPD/art.txt" > "$TMPD/art-left.txt" || true
    else
        cp "$TMPD/art.txt" "$TMPD/art-left.txt"
    fi
    [ ! -s "$TMPD/art-left.txt" ]
}

build_proof() {
    echo "== 3. build with brand TestMarke: no trace of the default brands in the artifacts =="
    local out=${BRANDCHECK_OUT:-$TMPD/build}
    mkdir -p "$out"
    if [ -z "${BRANDCHECK_OUT:-}" ]; then
        export OSUM_MARKE_PRODUKT=TestMarke OSUM_MARKE_KURZ=tmarke OSUM_MARKE_WEB=https://tmarke.example
        if ! IMAGE_ID=brandcheck bash tools/usbimg/build.sh "$out" > "$TMPD/build.log" 2>&1; then
            bad "image build failed: $(tail -3 "$TMPD/build.log" | tr '\n' ' ')"
            return
        fi
    fi
    ok "image built with brand TestMarke"
    local img=$out/testmarke-usb.img
    [ -f "$img" ] && ok "image file is testmarke-usb.img" || bad "image file name not derived from the brand: $(ls "$out" | head -5 | tr '\n' ' ')"
    [ "$(strings -a "$img" | grep -c 'TestMarke')" -gt 0 ] && ok "image carries the brand TestMarke (positive control)" || bad "image does not contain TestMarke"
    grep -q 'TestMarke' "$out/limine.conf" && ok "limine config carries TestMarke (positive control)" || bad "limine.conf does not contain TestMarke"
    if artifact_hits "$out"; then
        ok "no OrientOS / XoffiOS string in kernel, image, limine config and rendered locale"
    else
        bad "$(wc -l < "$TMPD/art-left.txt") artifact strings still name a default brand"
        sort "$TMPD/art-left.txt" | uniq -c | sort -nr | head -${BRANDCHECK_SHOW:-40} | cut -c1-170
    fi
    printf 'planted XoffiOS marker\n' > "$out/planted.txt"
    artifact_hits "$out" && bad "planted XoffiOS in the artifacts not caught" || ok "planted XoffiOS in the artifacts caught"
    rm -f "$out/planted.txt"
    [ -z "${BRANDCHECK_OUT:-}" ] && rm -f "$out"/*.img
}

case "$MODE" in
    static) static_scan ;;
    counter) counter_proof ;;
    build) build_proof ;;
    all) static_scan; counter_proof; build_proof ;;
    *) echo "usage: run.sh [static|counter|build|all]"; exit 2 ;;
esac
echo
echo "brandcheck: $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
