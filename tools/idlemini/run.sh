#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/idlemini/run.sh -- IDLE WAKE-UPS OF JARVIS MINI (hidden) AND THE BUS BROKER (W-B2, r1087, 18.10.2026).
#
#   [BASE=<rev>] bash tools/idlemini/run.sh
#
# VirtualBox (z16, 3 vCPU, ps 62 s apart): jarvismini 9.8 % of a core, pid 3 8.5 %. pid 3 is the first process the desktop start spawns:
# the bus broker /bin/orientbus. Causes: the hidden box woke 40x/s (sleep 25 ms + wlib's own 40 ms idle sleep + a full scene pump
# every round); the broker woke 10x/s (bus_wait 100 ms) with nothing to do. Every timer wake was charged about one 10 ms tick.
# Fix: hidden box = bus_wait(500 ms) in the kernel + scene pump once a second; idle broker = bus_wait(1000 ms) when no timer is pending.
#
# Method: the machine of tools/jarvismini boot E (real autostart `hotkey` + `jmini --hidden --as-app`, link mode without a helper),
# no serial debug. Two `cat /proc/apps` 30 s apart: the wakeups column of app:jarvismini (blocked->ready transitions) is exact, no
# tick luck. Then two `ps`: ticks of pid 3 (broker) and of jarvismini. Two trees at once: HEAD and BASE (default HEAD~1).
#   1. app:jarvismini wakes < 6 per second hidden (before: ~40-55);
#   2. the broker (pid 3) and jarvismini together use < 2 % of the core;
#   3. COUNTER-PROOF: the BASE tree wakes at least 3x as often and uses more ticks;
#   4. the hotkey still works: Ctrl+Alt+J shows the box (window pixels differ) within 3 s -- checked by tools/jarvismini + tools/hotkey gates.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
BT=$TMPD/base
cleanup() { git worktree remove --force "$BT" >/dev/null 2>&1; rm -rf "$TMPD"; kill $(jobs -p) 2>/dev/null; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
BASEREV=${BASE:-HEAD~1}
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
git worktree add --detach "$BT" "$BASEREV" >/dev/null 2>&1 || { echo "base worktree failed"; exit 1; }
( cd "$BT" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 )
mkdir -p "$TMPD/new" "$TMPD/old"

cat > "$TMPD/dreh.txt" <<'EOF'
# hidden box + broker idle: /proc/apps twice (30 s apart), then ps twice
warteauf 'launcher: ready' || 120
warte 25
klick 300,200
warte 1
tippe cat /proc/apps
taste ret
warte 30
tippe cat /proc/apps
taste ret
warte 8
tippe ps
taste ret
warte 30
tippe ps
taste ret
warte 8
EOF
printf 'server osum.test\n' > "$TMPD/jarvismini.conf"
printf 'hotkey\njmini --hidden --as-app\n' > "$TMPD/autostart"
printf 'jarvismini window.float,hotkey,net\n' > "$TMPD/rights.yes"
MORE="orientbus act wmplug hotkeyd jarvismini apprights"

run_tree() { # <tree> <out>
    ( cd "$1"
      { cat etc/wmplug.conf; printf '\njmini rechte=0x001 prog=/bin/jarvismini\n'; } > "$2.wmplug.conf"
      EH_APPEND=rtcutc APPS="fetch" EH_MKFS_EXTRA="/etc/jarvismini.conf=$TMPD/jarvismini.conf@0644 /etc/hotkeys.conf=etc/hotkeys.conf@0644 /etc/wmplug.conf=$2.wmplug.conf@0644 /etc/wmplug.autostart=$TMPD/autostart@0644 /etc/actions.d/jarvismini.actions=etc/actions.d/jarvismini.actions@0644 /apps/ /apps/jarvismini.osp/ /apps/jarvismini.osp/INFO=pakete/jarvismini/INFO@0644 /apps/jarvismini.osp/start@/bin/jarvismini /etc/apprights.conf=$TMPD/rights.yes@0644" \
      DESIGNBUILD="$2/build" bash tools/design/eh6.sh "$2/o" res=1280x800 accel=kvm netz=ja "moreprogs=$MORE" extra=wmplug \
        drehbuch="$TMPD/dreh.txt" > "$2/o.log" 2>&1 )
}
run_tree "$ROOT" "$TMPD/new" &
run_tree "$BT" "$TMPD/old" &
wait

# python: wakeups/s of app jarvismini from the first/last /proc/apps dump; ticks of pid 3 and jarvismini from the first/last ps dump
cat > "$TMPD/m.py" <<'EOF'
import re, sys
def dumps(path):
    out, cur = [], []
    for l in open(path, errors="replace"):
        m = re.match(r"wm: termzeile (\d+) \[(.*)\]\s*$", l)
        if m:
            cur.append(m.group(2))
        elif cur:
            out.append(cur); cur = []
    if cur:
        out.append(cur)
    return out
ds = dumps(sys.argv[1])
apps = []
for d in ds:
    if any(x.startswith("# app cpu_ticks") for x in d):
        row = [x.split() for x in d if x.startswith("jarvismini ")]
        if row and (not apps or apps[-1] != row[0]):
            apps.append(row[0])
pss = []
for d in ds:
    if any("PID PPID STATE" in x for x in d):
        t = {}
        for x in d:
            m = re.match(r"\s*(\d+)\s+(\d+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(\d+)\s+real\s*(\S*)", x)
            if m:
                t[int(m.group(1))] = (m.group(4), int(m.group(6)), m.group(7))
        if len(t) >= 5 and (not pss or pss[-1] != t):
            pss.append(t)
if len(apps) < 2 or len(pss) < 2:
    print("wps=-1 wt=-1 b3=-1 bj=-1 (apps dumps %d, ps dumps %d)" % (len(apps), len(pss)))
    sys.exit(0)
dw = int(apps[-1][2]) - int(apps[0][2]); dt = int(apps[-1][1]) - int(apps[0][1])
a, b = pss[0], pss[-1]
span = sum(max(0, b[k][1] - a[k][1]) for k in b if k in a)
g3 = b[3][1] - a[3][1] if 3 in a and 3 in b else -1
gj = sum(b[k][1] - a[k][1] for k in b if k in a and b[k][2] == "jarvismini")
print("wakeups=%d jmticks=%d b3=%.2f bj=%.2f span=%d" % (dw, dt, 100.0 * g3 / span, 100.0 * gj / span, span))
EOF
for t in new old; do
    python3 "$TMPD/m.py" "$TMPD/$t/o/serial.txt" > "$TMPD/$t.res" 2>&1
    echo "== $t: $(cat "$TMPD/$t.res")"
    grep -a 'desk: orientbus pid' "$TMPD/$t/o/serial.txt" | head -1 | sed 's/^/        /'
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP"; cp "$TMPD/$t/o/serial.txt" "$KEEP/$t.serial.txt"; }
done
val() { sed -n "s/.*$2=\([-0-9.]*\).*/\1/p" "$TMPD/$1.res" | head -1; }
nw=$(val new wakeups); ow=$(val old wakeups); nb=$(val new b3); ob=$(val old b3); nj=$(val new bj); oj=$(val old bj)
# the two /proc/apps dumps are ~38 s apart (5 s dump grid): use 30 as the nominal span
awk -v w="${nw:--1}" 'BEGIN{exit !(w >= 0 && w / 30.0 < 6)}' && ok "hidden Mini: $nw wake-ups in ~30 s = $(awk -v w="$nw" 'BEGIN{printf "%.1f", w/30.0}') /s (limit 6/s)" \
    || bad "hidden Mini: ${nw:-?} wake-ups in ~30 s (limit 6/s)"
awk -v b="${nb:--1}" -v j="${nj:--1}" 'BEGIN{exit !(b >= 0 && j >= 0 && b + j < 2)}' && ok "broker (pid 3) $nb % + Mini $nj % of the core (limit 2 %)" \
    || bad "broker (pid 3) ${nb:-?} % + Mini ${nj:-?} % of the core (limit 2 %)"
awk -v n="${nw:-0}" -v o="${ow:-0}" 'BEGIN{exit !(o >= 3 * n && o > 20)}' && ok "COUNTER-PROOF: tree $BASEREV woke $ow times (now $nw)" \
    || bad "COUNTER-PROOF: tree $BASEREV woke $ow times, now $nw -- the check does not see the change"
echo; echo "IDLEMINI: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
