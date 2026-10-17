#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/explorer3/run.sh -- EXPLORER LIKE WINDOWS 11 (polish night 16/17.10.2026, worker W4).
#
#   /root/jarvis/bin/heavy bash tools/explorer3/run.sh
#
# 1. The root folder "/" hides the kernel mount points (dev, proc, sys): `explorer: modell ... kdirs=N kvis=0`.
#    Counter-proof: `explorer / hidden` (the old behaviour: everything shown) must report kvis == kdirs.
# 2. The drive overview and the pane list no pseudo file system as a drive (`explorer: overview` rows are real drives).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== 1. root folder, default =="
bash tools/toolbench/build.sh "$TMPD/a" app=/bin/explorer,/ wait=12 last=100 shot=root > "$TMPD/a.log" 2>&1
SA="$TMPD/a/serial.txt"
[ -s "$TMPD/a/root.ppm" ] && ok "picture taken" || bad "no picture: $(tail -3 "$TMPD/a.log" | tr '\n' ' ')"
la=$(grep -aE 'explorer: modell n=[0-9]+ .*kdirs=' "$SA" | tail -1)
kd=$(echo "$la" | grep -oE 'kdirs=[0-9]+' | grep -oE '[0-9]+')
kv=$(echo "$la" | grep -oE 'kvis=[0-9]+' | grep -oE '[0-9]+')
[ "${kd:-0}" -ge 1 ] && ok "the root holds the kernel mount points (kdirs=$kd)" || bad "kdirs=${kd:-?} (expected >= 1; the test image has no proc/sys mounts): $la"
[ "${kv:-9}" = 0 ] && ok "none of them is shown (kvis=0)" || bad "kvis=${kv:-?} should be 0: $la"

echo "== 2. root folder, counter-proof (hidden shown = old behaviour) =="
bash tools/toolbench/build.sh "$TMPD/b" app=/bin/explorer,/,hidden wait=12 last=100 shot=root > "$TMPD/b.log" 2>&1
SB="$TMPD/b/serial.txt"
lb=$(grep -aE 'explorer: modell n=[0-9]+ .*kdirs=' "$SB" | tail -1)
kdb=$(echo "$lb" | grep -oE 'kdirs=[0-9]+' | grep -oE '[0-9]+')
kvb=$(echo "$lb" | grep -oE 'kvis=[0-9]+' | grep -oE '[0-9]+')
[ -n "$kdb" ] && [ "${kvb:-x}" = "$kdb" ] && ok "with hidden shown all $kdb are visible (the filter is what hides them)" || bad "counter-proof: $lb"

echo "== 3. no pseudo drive in the pane =="
if grep -aE 'explorer: traeger i=[0-9]+ .*' "$SA" | grep -aqE '/(proc|dev|sys)'; then
    bad "a pseudo file system is listed as a drive"
else
    ok "no /proc /dev /sys drive row"
fi

echo "== 3b. drive label percent (W6): the label built a second time must not double the text =="
pp=$(grep -aE 'explorer: pctprobe ' "$SA" | tail -1 | sed 's/.*pctprobe //' | tr -d '\r')
[ -n "$pp" ] && ok "the pane built its labels and ran the self-check ($pp)" || bad "no 'explorer: pctprobe' line in the serial output"
[ "$pp" = "/ 92%" ] && ok "second build over stale bytes reads '/ 92%' (not '/ 92%92%')" || bad "second build reads '$pp' (expected '/ 92%')"
if grep -aE 'explorer: traeger i=[0-9]+ .*lbl=' "$SA" | grep -aqE 'lbl=.*%.*%'; then
    bad "a real drive label carries two percent signs"
else
    ok "no real drive label has two percent signs"
fi

echo "== 4. file types and drive count: catalog (de + en) and source =="
for k in explorer.type.pdf explorer.type.archive explorer.type.audio explorer.type.video explorer.count.drives explorer.count.drive1; do
    grep -qE "^$k =" locale/de/messages && grep -qE "^$k =" locale/en/messages \
        && ok "catalog key $k in de and en" || bad "catalog key $k missing"
done
for e in .pdf .zip .mp3 .mp4 .ppm; do
    grep -aq -- "\"[^\"]*$e[ \\\\\"]" kernel/user/expmodell.fi \
        && ok "ending $e is a known file type" || bad "ending $e is not in expmodell.fi"
done
# the kinds are told apart: five new words and five new symbols in the model
n=$(grep -acE 'k == [5-8] \{' kernel/user/expmodell.fi)
[ "${n:-0}" -ge 8 ] && ok "kinds 5-8 have a type word and a symbol ($n branches)" || bad "kinds 5-8: only $n branches"

echo "EXPLORER3: $pass passed, $fail failed"
[ "$fail" = 0 ]
