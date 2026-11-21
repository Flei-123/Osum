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

mkdir -p "$TMPD/apps"
cp -a assets/apps/settings.osp assets/apps/launcher.osp assets/apps/taskmgr.osp "$TMPD/apps/"
make_bundle() { # make_bundle <dir> <name> <policy>
    cp -a assets/apps/trashbin.osp "$TMPD/apps/$1.osp"
    printf 'name=%s\ninfo=Test app\nkeys=%s\nrevision=1\nautostart=%s\n' "$2" "$1" "$3" > "$TMPD/apps/$1.osp/INFO"
}
make_bundle zed Zed default-on
make_bundle yak Yak default-off
printf 'alpha\nbeta\n' > "$TMPD/list"
printf 'alpha=off\nbeta=on\n' > "$TMPD/seed.conf"
printf 'warte 18\n' > "$TMPD/wait.txt"
cat > "$TMPD/click.txt" <<'S'
warteauf 'launcher: ready' || 120
warte 6
taste meta_l
warte 6
tippe autostart
warte 4
taste ret
warteauf 'settings: autostart page entries=' || 60
warte 6
foto 00-page
klickauf srectasw0
warteauf 'settings: autostart alpha=' || 30
warte 3
foto 01-toggled
klickauf srectasw0
warteauf 'settings: autostart alpha=on' || 30
warte 3
S

git worktree add --detach "$TMPD/mut" HEAD > /dev/null 2>&1 || { echo "FAIL  mutant worktree"; exit 1; }
python3 -I - "$TMPD/mut" <<'PY'
import sys
p = sys.argv[1] + "/kernel/user/autostartrun.fi"
s = open(p).read()
old = "return model.should_start(name, octets.cstr_len(name))"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "return name != 0"))
PY

run_tree() { # run_tree <tree> <name> <script> [conf]
    local etc="/etc/wmplug.autostart=$TMPD/list@0644"
    [ -n "${4:-}" ] && etc="$etc /etc/autostart.conf=$4@0644"
    ( cd "$1" && APPS_DIR="$TMPD/apps" EH_ETC_EXTRA="$etc" DESIGNBUILD="$TMPD/build-$2" \
        bash tools/design/eh6.sh "$TMPD/$2" res=1280x800 accel=kvm tafel=nein drehbuch="$3" > "$TMPD/$2.log" 2>&1 )
}
echo "== three runs in parallel: seeded off, clicks, mutant =="
run_tree "$ROOT" seed "$TMPD/wait.txt" "$TMPD/seed.conf" &
P1=$!
run_tree "$ROOT" click "$TMPD/click.txt" &
P2=$!
run_tree "$TMPD/mut" mut "$TMPD/wait.txt" "$TMPD/seed.conf" &
P3=$!
wait $P1 $P2 $P3
if [ -n "${AUTOSTARTUI_SHOTS:-}" ]; then mkdir -p "$AUTOSTARTUI_SHOTS"; for n in seed click mut; do cp "$TMPD/$n/serial.txt" "$AUTOSTARTUI_SHOTS/$n.serial.txt" 2>/dev/null; cp "$TMPD/$n"/*.ppm "$AUTOSTARTUI_SHOTS/" 2>/dev/null; done; fi

started() { grep -a "^desktop: autostart \[$2" "$TMPD/$1/serial.txt" | head -1; }
for n in seed click mut; do
    [ -s "$TMPD/$n/serial.txt" ] || bad "$n: no serial output: $(tail -3 "$TMPD/$n.log" | tr '\n' ' ')"
done

echo "== state file decides at boot =="
[ -n "$(started seed beta)" ] && ok "seeded on: 'beta' is started" || bad "seeded on: 'beta' was not started"
[ -z "$(started seed alpha)" ] && ok "seeded off: 'alpha' is not started" || bad "seeded off: 'alpha' was started"
[ -n "$(started click alpha)" ] && [ -n "$(started click beta)" ] && ok "no state file: both list entries start" || bad "no state file: list entries missing"
[ -n "$(started mut alpha)" ] && ok "mutant without the check starts 'alpha' despite the state file" || bad "mutant did not start 'alpha' -- the test is blind"

echo "== settings page: one source, toggles write it =="
S="$TMPD/click/serial.txt"
grep -aq 'launcher: settings page=[0-9]* pid=' "$S" && ok "search hit 'autostart' starts Settings" || bad "no Settings start from the search"
entries=$(grep -a 'settings: autostart page entries=' "$S" | head -1 | sed 's/.*entries=//')
[ "${entries:-0}" -ge 3 ] && ok "the page lists the registry ($entries entries: list + package)" || bad "page entries=${entries:-none}"
grep -aq 'settings: rect name=asw0 ' "$S" && ok "toggle rectangles are reported" || bad "no rectangle for the first toggle"
grep -aq 'settings: autostart alpha=off' "$S" && ok "click 1: 'alpha' turned off and saved to the shared state file" || bad "click 1 did not turn 'alpha' off"
grep -aq 'settings: autostart alpha=on' "$S" && ok "click 2: 'alpha' turned on again" || bad "click 2 did not turn 'alpha' on"
for f in 00-page 01-toggled; do [ -s "$TMPD/click/$f.ppm" ] || bad "missing picture $f"; done
if [ -s "$TMPD/click/00-page.ppm" ] && [ -s "$TMPD/click/01-toggled.ppm" ]; then
    n=$(python3 -I tools/menualive/check.py diff "$TMPD/click/00-page.ppm" "$TMPD/click/01-toggled.ppm" 0 0 1280 800 | sed 's/changed=//')
    [ "${n:-0}" -gt 20 ] && ok "the toggle changed the picture ($n pixels)" || bad "toggle changed ${n:-0} pixels"
fi
grep -aq 'panic\|#PF\|program died' "$S" && bad "a program died" || ok "no panic or dead program"
echo
echo "AUTOSTARTUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
