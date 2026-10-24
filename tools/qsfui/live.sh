#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/qsfui/live.sh -- brightness slider applies the value while the button is still held.
# Counter-proof: /etc/qsnolive (old behaviour) must produce no `qs: live` line before release.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cat > "$TMPD/dreh.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 5
taste meta_l-a
warteauf 'qs: open' || 30
warte 2
halteauf hellspur
warte 3
foto 01-held
loslassen
warte 3
EOF
run_case() {
    local name=$1; shift
    D="$TMPD/$name"
    for try in 1 2; do
        rm -rf "$D"
        bash tools/design/eh6.sh "$D" res=1280x800 uiscale=1 mode=dark accel=kvm drehbuch="$TMPD/dreh.txt" "$@" > "$TMPD/$name.log" 2>&1
        grep -aq 'qs: open ' "$D/serial.txt" 2>/dev/null && break
        tail -n 12 "$TMPD/$name.log"
    done
}
live_before_release() {
    local S=$1
    local l r
    l=$(grep -an 'qs: live hell=' "$S" | head -1 | cut -d: -f1)
    r=$(grep -an 'qs: hell auf =' "$S" | head -1 | cut -d: -f1)
    [ -n "$l" ] && { [ -z "$r" ] || [ "$l" -lt "$r" ]; }
}
: > "$TMPD/flag"
run_case live
if live_before_release "$TMPD/live/serial.txt"; then ok "brightness applied while the button is held"; else bad "no live apply before release"; fi
run_case nolive xfile=/etc/qsnolive="$TMPD/flag"
if live_before_release "$TMPD/nolive/serial.txt"; then bad "counter-proof: live line present with /etc/qsnolive"; else ok "counter-proof: no live line with /etc/qsnolive"; fi
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
