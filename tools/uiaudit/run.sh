#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/uiaudit/run.sh -- static UI audit of the Settings sources: word buttons (Back/Forward/Up/Apply), developer values (hex, ratios,
# internal names) and doubled controls. Counter-proof: a doctored copy with the old patterns must be red.
#   bash tools/uiaudit/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
out=$(python3 -I tools/uiaudit/audit.py .); rc=$?
echo "$out" | grep FINDING
[ $rc -eq 0 ] && ok "no UI audit findings in the Settings sources" || bad "audit findings: $(echo "$out" | tail -1)"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
mkdir -p "$D/kernel/user" "$D/locale/de" "$D/locale/en"
cp kernel/user/settings.fi kernel/user/navview.fi "$D/kernel/user/"; cp locale/de/messages "$D/locale/de/"; cp locale/en/messages "$D/locale/en/"
cat >> "$D/kernel/user/settings.fi" <<'X'
fn old_a() {
    let n_b1: usize = fuiscene.button_main(right, msg.get((&k_b_uber[0 as usize]) as u64), K_B1)
    let n_ea: usize = fuiscene.entry(right, K_EA, 0, (&e_akzent[0 as usize]) as u64)
    let _n_lk: usize = fuiscene.label_wrap(right, (&l_kon[0 as usize]) as u64, 2)
    let n_csh: usize = fuiscene.choice(left, chtext(K_CSH, 1), K_CSH)
}
X
python3 -I tools/uiaudit/audit.py "$D" > "$D/old.txt"; orc=$?
[ $orc -ne 0 ] && [ "$(grep -c FINDING "$D/old.txt")" -ge 4 ] && ok "counter-proof: old patterns are red ($(tail -1 "$D/old.txt"))" || bad "counter-proof stayed green"
if [ -n "${UIAUDIT_SHOT:-}" ]; then
    MOCK="${UIAUDIT_MOCK:-/root/jarvis/data/projects_kb/orientos/reports/mockups/hpf-personalization.png}"
    sc=$(python3 -I tools/uiaudit/ssim.py "$UIAUDIT_SHOT" "$MOCK" 20,4,1022,738 --min=0.95); src=$?
    [ $src -eq 0 ] && ok "mockup match: $sc" || bad "mockup match: $sc"
fi
echo "$pass/$fail OK/FAIL"; [ $fail -eq 0 ]
