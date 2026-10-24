#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wd/run.sh -- W-D round (17.10.2026): corner radius 8, subtle hover, idle lock choices, tray i18n.
#
#   bash tools/wd/run.sh        (seconds, no QEMU)
#
# A  r1001  window/menu/popup radius is 8 (Windows 11): osum.shape, tageslicht preset, fUi token R_LARGE
# B  r1002  hover layer is subtle: model.py distance 5..18 levels for every scheme/mode (tools/theme/hover.py)
# C  lock   idle lock: choices Never/1/2/5/10/15/30, default 600 s, persisted key, idlelock re-reads the file
# D  i18n   no raw message key in the tray popup: every key used in the source exists in every language
# Every section has a COUNTER-PROOF against the tree before this round ($WD_OLD): it must be red.
set -uo pipefail
cd "$(dirname "$0")/../.."
OLD=${WD_OLD:-e51d63cb}     # main before the W-D round
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { [ "$2" = "$3" ] && ok "$1 ($2)" || bad "$1: got '$2', want '$3'"; }
old() { git show "$OLD:$1" 2>/dev/null; }
val() { grep -a "^$2=" | head -1 | cut -d= -f2; }     # val <file> <key> via stdin

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

echo "== A. corner radius 8 (r1001) =="
is "osum.shape radius_window" "$(val x radius_window < assets/shapes/osum.shape)" 8
is "osum.shape radius_panel"  "$(val x radius_panel  < assets/shapes/osum.shape)" 8
is "modern.shape radius_window" "$(val x radius_window < assets/shapes/modern.shape)" 8
is "COUNTER-PROOF old modern.shape radius_window was" "$(old assets/shapes/modern.shape | val x radius_window)" 10
is "tageslicht preset radius" "$(val x radius < assets/themes/tageslicht.preset)" 8
if bash tools/tokens/run.sh > "$T/tok.txt" 2>&1; then ok "tokens gate (R_LARGE = 8 = osum radius_window, order small < medium <= large) $(tail -1 "$T/tok.txt")"; else bad "tokens gate"; tail -5 "$T/tok.txt"; fi
# counter-proof: the OLD tree says 12 -> the same assertion must be red
is "COUNTER-PROOF old osum.shape radius_window was" "$(old assets/shapes/osum.shape | val x radius_window)" 12
is "COUNTER-PROOF old preset radius was" "$(old assets/themes/tageslicht.preset | val x radius)" 12
mkdir -p "$T/oldlib"; cp -r lib/. "$T/oldlib/"; old lib/fui/tokens.fi > "$T/oldlib/fui/tokens.fi"
if FIRNLIB="$T/oldlib" vendor/firn/bin/firnc --profile=app tools/tokens/host.fi -o "$T/oldhost" > "$T/ob.log" 2>&1 \
   && "$T/oldhost" > "$T/oldrows.txt" && ! python3 -I tools/tokens/check.py "$T/oldrows.txt" > "$T/oc.txt" 2>&1; then
    ok "COUNTER-PROOF old tokens.fi is red against the new check ($(grep -c FAIL "$T/oc.txt") fail)"
else bad "COUNTER-PROOF old tokens.fi should be red"; fi

echo "== B. subtle hover (r1002) =="
if python3 -I tools/theme/hover.py > "$T/h.txt" 2>&1; then ok "hover distance in range: $(tail -1 "$T/h.txt")"; else bad "hover"; grep FAIL "$T/h.txt" | head -5; fi
old tools/theme/model.py > "$T/old_model.py"
if python3 -I tools/theme/hover.py "$T/old_model.py" > "$T/ho.txt" 2>&1; then bad "COUNTER-PROOF old model should be red"; else ok "COUNTER-PROOF old model is red ($(grep -c FAIL "$T/ho.txt") cases, e.g. $(grep FAIL "$T/ho.txt" | head -1 | cut -c7-80))"; fi
python3 -I tools/theme/model.py table assets/schemes/*.scheme > "$T/w_new.txt" 2>&1
is "contrast pairings still all fine (model.py table, rows with failures)" "$(awk -F'|' '$6+0>0' "$T/w_new.txt" | wc -l)" 0

echo "== C. idle lock =="
FIRNLIB="$PWD/lib" vendor/firn/bin/firnc --profile=app tools/lockidle/host.fi -o "$T/li" > "$T/li.log" 2>&1 && "$T/li" > "$T/li.txt" || { bad "lockidle host build/run"; tail -3 "$T/li.log"; }
r() { awk -v g="$1" -v a="$2" '$1==g && $2==a {print $3}' "$T/li.txt"; }
is "choice seconds never/1/2/5/10/15/30" "$(for l in 0 1 2 3 4 5 6; do r 1 $l; done | tr '\n' ' ')" "0 60 120 300 600 900 1800 "
is "out-of-range choice reads as never" "$(r 1 7)" 0
is "stored 0 shows 'never'" "$(r 2 0)" 0
is "stored 60 shows level 1" "$(r 2 60)" 1
is "stored 240 (script value) shows level 3 (5 min), not 'never'" "$(r 2 240)" 3
is "stored 600 shows level 4" "$(r 2 600)" 4
is "stored 25 is not 'never'" "$(r 2 25)" 1
is "stored 1800 shows level 6" "$(r 2 1800)" 6
is "choice count" "$(r 3 0)" 7
is "default seconds" "$(r 3 1)" 600
is "schema default of lock.idle" "$(grep -a -A1 '^setting lock.idle' etc/settings.schema | grep -a default | tr -s ' ' | cut -d' ' -f3)" 600
is "image default sperre.conf" "$(grep -ao 'echo 0 || echo [0-9]*' tools/usbimg/build.sh | head -1 | grep -ao '[0-9]*$')" 600
for l in de en; do
    n=$(grep -a '^settings.lock.choices' locale/$l/messages | head -1 | sed 's/^[^=]*= *//' | awk -F'\\\\n' '{print NF}')
    is "settings page offers 7 choices ($l)" "$n" 7
done
grep -aq 'lockidle.secs_of' kernel/user/settings.fi && grep -aq 'lockidle.level_of' kernel/user/settings.fi && ok "settings.fi uses fui.lockidle (write + read back)" || bad "settings.fi does not use fui.lockidle"
grep -aq 'idle limit now' kernel/user/idlelock.fi && ok "idlelock re-reads the limit (change takes effect without re-login)" || bad "idlelock does not re-read the limit"
# counter-proof: the old files fail the same assertions
is "COUNTER-PROOF old schema default was" "$(old etc/settings.schema | grep -a -A1 '^setting lock.idle' | grep -a default | tr -s ' ' | cut -d' ' -f3)" 300
is "COUNTER-PROOF old settings page choices (de) were" "$(old locale/de/messages | grep -a '^settings.lock.choices' | head -1 | sed 's/^[^=]*= *//' | awk -F'\\\\n' '{print NF}')" 5
old kernel/user/idlelock.fi | grep -aq 'idle limit now' && bad "COUNTER-PROOF old idlelock should not re-read" || ok "COUNTER-PROOF old idlelock read the limit only once"

echo "== D. i18n: no raw key in the UI =="
if python3 -I tools/i18nlint/check.py > "$T/i18n.txt" 2>&1; then ok "$(tail -1 "$T/i18n.txt")"; else bad "i18nlint"; head -5 "$T/i18n.txt"; fi
for k in tray.mute tray.more tray.none tray.unmute tray.net tray.sound tray.nonet tray.open tray.settings tray.quit; do
    grep -aq "^$k = " locale/de/messages && grep -aq "^$k = " locale/en/messages || bad "$k missing in a table"
done
# counter-proof: old locale tables + the same sources -> the lint must find the missing tray keys
mkdir -p "$T/oldtree/locale/de" "$T/oldtree/locale/en" "$T/oldtree/kernel/user"
old locale/de/messages > "$T/oldtree/locale/de/messages"; old locale/en/messages > "$T/oldtree/locale/en/messages"
cp kernel/user/traypop.fi "$T/oldtree/kernel/user/"
if python3 -I tools/i18nlint/check.py "$T/oldtree" > "$T/i18nold.txt" 2>&1; then bad "COUNTER-PROOF old tables should be red"; else ok "COUNTER-PROOF old tables: $(grep -c '^FAIL' "$T/i18nold.txt") raw keys found (e.g. $(grep '^FAIL' "$T/i18nold.txt" | head -1 | cut -c7-30))"; fi

echo
echo "wd: $pass ok, $fail fail"
[ "$fail" = 0 ]
