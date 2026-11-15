#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
cleanup() { git worktree remove --force "$TMPD/mut" > /dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

make_bundle() {
    local d="$TMPD/apps/$1.osp"
    cp -a assets/apps/trashbin.osp "$d"
    sed -i -e "s|^name=.*|name=$2|" -e "s|^info=.*|info=$3|" -e "s|^keys=.*|keys=$4|" -e "s|^id=.*|id=com.test.$1|" "$d/INFO"
    printf '%s\n' "$5" > "$d/start.txt"
}

mkdir -p "$TMPD/apps"
for keep in explorer settings taskmgr; do cp -a assets/apps/$keep.osp "$TMPD/apps/"; done
make_bundle terminal "Terminal" "A command prompt with a shell" "terminal,shell" /bin/edit
make_bundle teamlist "Teamlist" "Lists teams" "team" /bin/edit
printf 'use=teamlist:5\n' > "$TMPD/startuse.conf"
HOUR=$(( $(date +%s) / 3600 ))
printf 'u terminal 2000 %s\nq te terminal 2000 %s\n' "$HOUR" "$HOUR" > "$TMPD/learn.on"
printf 'off\n' > "$TMPD/learn.off"

echo "== mutant tree: launcher never reloads the learn file =="
git worktree add --detach "$TMPD/mut" HEAD > /dev/null 2>&1 || { bad "mutant worktree"; echo "SETTINGSSEARCH: $pass passed, $fail failed"; exit 1; }
python3 -I - "$TMPD/mut" <<'PY'
import re, sys
p = sys.argv[1] + "/kernel/user/startlearn.fi"
s = open(p).read()
m = re.search(r"fn sync\(\) \{.*?\n}\n", s, re.S)
assert m
s = s[:m.start()] + "fn sync() {\n    ensure_loaded()\n}\n" + s[m.end():]
open(p, "w").write(s)
PY

run_tree() { # run_tree <tree> <name> <script> [seed]
    local home=""
    [ -n "${4:-}" ] && home="/users/justin/config/startlearn=$4@0644"
    ( cd "$1" && APPS_DIR="$TMPD/apps" EH_ETC_EXTRA="/etc/startuse.conf=$TMPD/startuse.conf@0644" EH_HOME_EXTRA="$home" \
        DESIGNBUILD="$TMPD/build-$2" bash tools/design/eh6.sh "$TMPD/$2" res=1920x1080 accel=kvm tafel=nein \
        drehbuch="$ROOT/tools/settingssearch/$3" > "$TMPD/$2.log" 2>&1 )
}
echo "== four runs in parallel: real, mutant, seeded on, seeded off =="
run_tree "$ROOT" new script.txt &
P1=$!
run_tree "$TMPD/mut" old script.txt &
P2=$!
run_tree "$ROOT" seedon seed.txt "$TMPD/learn.on" &
P3=$!
run_tree "$ROOT" seedoff seed.txt "$TMPD/learn.off" &
P4=$!
wait $P1 $P2 $P3 $P4

if [ -n "${SETTINGSSEARCH_SHOTS:-}" ]; then mkdir -p "$SETTINGSSEARCH_SHOTS"; cp "$TMPD"/new/*.ppm "$SETTINGSSEARCH_SHOTS/" 2>/dev/null; for n in new old seedon seedoff; do cp "$TMPD/$n/serial.txt" "$SETTINGSSEARCH_SHOTS/$n.serial.txt" 2>/dev/null; done; fi
best() { # best <run> <marker> <nth> <query>
    python3 -I tools/settingssearch/check.py "$TMPD/$1/serial.txt" "$2" "$3" "$4" | sed -n 's/^best=//p'
}
for n in new old seedon seedoff; do
    [ -s "$TMPD/$n/serial.txt" ] || bad "$n: no serial output: $(tail -3 "$TMPD/$n.log" | tr '\n' ' ')"
done

N="$TMPD/new/serial.txt"
echo "== Settings > Search: reset and switch =="
USE='launcher: use \[terminal'
[ "$(best new . 0 te)" = "Teamlist" ] && ok "baseline: 'te' goes to Teamlist (most used)" || bad "baseline: 'te' best is '$(best new . 0 te)'"
[ "$(best new "$USE" 2 te)" = "Terminal" ] && ok "after two picks: 'te' goes to Terminal" || bad "after two picks: best is '$(best new "$USE" 2 te)'"
grep -aq 'settings: nav route=settings://privacy/search' "$N" && ok "the sidebar opens settings://privacy/search" || bad "page not opened"
grep -aq 'settings: rect name=srln ' "$N" && grep -aq 'settings: rect name=srrs ' "$N" && ok "switch and reset button are on screen" || bad "rects srln/srrs missing"
grep -aq 'settings: search history 0' "$N" && ok "the reset click reached the page" || bad "reset click not seen"
[ "$(best new 'settings: search history 0' 1 te)" = "Teamlist" ] && ok "reset: the running launcher forgot the pick ('te' -> Teamlist)" \
    || bad "reset: best is '$(best new 'settings: search history 0' 1 te)'"
[ "$(best new "$USE" 4 te)" = "Terminal" ] && ok "learned again after the reset" || bad "relearn: best is '$(best new "$USE" 4 te)'"
grep -aq 'settings: search learn=off' "$N" && ok "the switch click turned learning off" || bad "switch off not seen"
[ "$(best new 'settings: search learn=off' 1 te)" = "Teamlist" ] && ok "learning off: the running launcher ignores the history" \
    || bad "learning off: best is '$(best new 'settings: search learn=off' 1 te)'"
python3 -I - "$N" <<'PY' && ok "the second click turned learning on again" || bad "learning never came back on"
import sys
lines = [l for l in open(sys.argv[1], errors="replace") if l.startswith("settings: search learn=")]
off = [i for i, l in enumerate(lines) if l.strip().endswith("learn=off")]
sys.exit(0 if off and any(l.strip().endswith("learn=on") for l in lines[off[0] + 1:]) else 1)
PY

echo "== persistence: the launcher starts from the file on disk =="
[ "$(best seedon . 0 te)" = "Terminal" ] && ok "seeded history: 'te' goes to Terminal at the first search" || bad "seeded on: best is '$(best seedon . 0 te)'"
[ "$(best seedoff . 0 te)" = "Teamlist" ] && ok "seeded 'off': 'te' stays on Teamlist" || bad "seeded off: best is '$(best seedoff . 0 te)'"
grep -aq 'settings: search learn=' "$TMPD/seedon/serial.txt" && bad "seed run opened Settings by accident" || ok "seed runs never opened Settings"

echo "== counter-proof: launcher without reload =="
O="$TMPD/old/serial.txt"
[ "$(best old 'settings: search history 0' 1 te)" = "Terminal" ] && ok "mutant: after reset the launcher still ranks Terminal" \
    || bad "mutant: best after reset is '$(best old 'settings: search history 0' 1 te)' -- the test is blind"
[ "$(best old 'settings: search learn=off' 1 te)" = "Terminal" ] && ok "mutant: with learning off the launcher still ranks Terminal" \
    || bad "mutant: best after off is '$(best old 'settings: search learn=off' 1 te)' -- the test is blind"

echo
echo "SETTINGSSEARCH: $pass passed, $fail failed"
[ "$fail" = 0 ]
