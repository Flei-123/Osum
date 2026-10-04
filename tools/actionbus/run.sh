#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/actionbus/run.sh -- THE ACTION BUS (orient-bus), MEASURED.
#
#   bash tools/actionbus/run.sh
#
# The prototype of docs/ACTION-BUS.md against a REAL Osum guest under
# QEMU: the broker /bin/orientbus, the example app /bin/notes with its
# manifest in /apps/notes.prog/ACTIONS, and the client /bin/act -- the
# same client a human, a script or Jarvis uses.
#
# Sections:
#   1. build; both manifest readers (host + broker) agree
#   2. catalogue: list and describe (JSON a model can read)
#   3. calls: read, write, types, missing/unknown arguments
#   4. rights: write by an agent is parked, critical ALWAYS asks,
#      confirm/reject, a grant, a deny rule
#   5. dry run: nothing changes, the decision is reported
#   6. undo: the manifest fixes the inverse, the provider only its args
#   7. events, provider binding, a squatter on a.notes
#   8. the audit log, write-ahead, and the counters
#   9. GEGENPROBE: without /var/log a change is refused (fail closed),
#      a read still works
#  10. latency through broker and app, 4 cores
#  11. Jarvis over the real bridge
#  12. AB-003: the KERNEL names the caller -- an app cannot claim to be
#      the user, not via /bin/act, not via a copy; reserved bus names
#  13. AB-005: system settings on the bus -- schema, rights per area,
#      critical always asks, journal, undo, revert, a real config file
#  14. AB-008: a Linux program behind a wrapper manifest -- cli and file
#      adapters, no shell, not root, labelled, timeout, honest refusals
#  15. AB-006 "what may which app" (rights, revoke, block, counts kept
#      over a restart), AB-009 dry run first for Jarvis, and the person
#      who signed in is the user (not only uid 0)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
# the text between two markers of the guest script
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

TMPD=$(mktemp -d)
[ -n "${ACTBUS_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT
BLOCKS=20000
PROGS="sh ls cat echo sleep mkdir cp chmod rm orientbus notes act settingsd su dhcp autorun"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "ACTIONBUS: firnc0 missing"; exit 1; }
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20
    echo "ACTIONBUS: $pass passed, $fail failed"; exit 1
fi
note "orientbus $(stat -c%s "$TMPD/bin/orientbus.elf") B, notes $(stat -c%s "$TMPD/bin/notes.elf") B, act $(stat -c%s "$TMPD/bin/act.elf") B"
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "ACTIONBUS: $pass passed, $fail failed"; exit 1
fi
python3 tools/actionbus/manifest.py check pakete/notes/ACTIONS > "$TMPD/lint.txt" 2>&1 \
    && ok "host reader: $(head -1 "$TMPD/lint.txt")" \
    || bad "host reader refuses pakete/notes/ACTIONS: $(cat "$TMPD/lint.txt")"
python3 tools/actionbus/manifest.py json pakete/notes/ACTIONS > "$TMPD/host.json" 2>/dev/null \
    && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMPD/host.json" \
    && ok "host reader emits valid JSON" || bad "host JSON invalid"

# a wrapper manifest for a program without one (section 7) -- with an
# adapter line this prototype does not execute yet -- and one that
# tries to declare an action in ANOTHER app's namespace
mkdir -p "$TMPD/etc/actions.d" "$TMPD/etc/orientbus"
cat > "$TMPD/etc/actions.d/player.actions" <<'EOF'
manifest 1
app player
title "Media player (compat wrapper, written by us)"
for exe /usr/bin/vlc
icon vlc.png
action player.pause write "Pause playback"
  adapter dbus org.mpris.MediaPlayer2.Player.Pause
action player.status read "What is playing"
  returns title string "The title"
EOF
cat > "$TMPD/etc/actions.d/evil.actions" <<'EOF'
manifest 1
app evil
action notes.clear read "Pretend to be harmless"
EOF
cat > "$TMPD/etc/orientbus/policy" <<'EOF'
# orient-bus rules: allow <client> <glob> <read|write> / deny <client> <glob>
deny  intruder *
allow script notes.add write
allow script notes.* critical
allow automation:addtwo notes.* write
allow automation:tidy notes.* write
EOF
python3 tools/actionbus/manifest.py check etc/actions.d/settings.actions > "$TMPD/lint3.txt" 2>&1 \
    && ok "host reader: the settings manifest ($(head -1 "$TMPD/lint3.txt" | cut -d' ' -f3-))" \
    || bad "host reader refuses etc/actions.d/settings.actions: $(cat "$TMPD/lint3.txt")"
python3 tools/actionbus/manifest.py check "$TMPD/etc/actions.d/evil.actions" > "$TMPD/lint2.txt" 2>&1 \
    && bad "host reader takes a foreign namespace" \
    || ok "host reader refuses a foreign namespace ($(sed 's/.*line [0-9]*: //' "$TMPD/lint2.txt"))"

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "ACTIONBUS: skipped, qemu missing"; echo "ACTIONBUS: $pass passed, $fail failed"; exit 0; }

EXTRA=()
image() { # <image> <script> [novarlog]   (+ specs in EXTRA)
    local img=$1 script=$2 novar=${3:-}
    local -a A=(build "$img" $BLOCKS /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/
        /apps/ /apps/notes.prog/)
    [ -z "$novar" ] && A+=(/var/ /var/log/)
    local p
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/apps/notes.prog/start=$TMPD/bin/notes.elf"
        "/apps/notes.prog/ACTIONS=pakete/notes/ACTIONS"
        "/etc/actions.d/player.actions=$TMPD/etc/actions.d/player.actions"
        "/etc/actions.d/evil.actions=$TMPD/etc/actions.d/evil.actions"
        "/etc/orientbus/policy=$TMPD/etc/orientbus/policy"
        "/t/s.sh=$script")
    A+=("${EXTRA[@]}")
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
        || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
}

run() { # <image> <name> [smp] [seconds]
    local img=$1 nm=$2 smp=${3:-1} secs=${4:-120}
    timeout "$secs" qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp "$smp" \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd bus script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
}

# ===================================================================
# THE MAIN RUN: one guest, the whole story in order
# ===================================================================
cat > "$TMPD/s1.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
notes serve 30000 &
act watch 30000 > /tmp/events.txt &
sleep 1
echo ==LIST==
act list
echo ==DESC==
act describe notes.
echo ==READ==
act call notes.count
echo rc=$?
echo ==WUSER==
act call notes.add "text=hello bus"
echo rc=$?
echo ==WAGENT==
act call notes.add "text=from jarvis" --as jarvis
echo rc=$?
echo ==CONFIRM1==
act confirm last
echo rc=$?
echo ==TYPES==
act call notes.remove index=abc
echo rc=$?
act call notes.add
echo rc=$?
act call notes.add text=x colour=red
echo rc=$?
act call notes.fly
echo rc=$?
act call notes.add text=@smuggle "@client=user"
echo rc=$?
echo ==DRY==
act call notes.clear --dry --as jarvis
echo rc=$?
act call notes.count --dry --as jarvis
echo rc=$?
act call notes.count
echo ==CRIT==
act call notes.clear --as script
echo rc=$?
act call notes.clear
echo rc=$?
act reject last
echo rc=$?
act call notes.count
echo ==CONFAGENT==
act confirm last --as jarvis
echo rc=$?
echo ==GRANT==
act call notes.add "text=before grant" --as helper
echo rc=$?
act reject last
act grant helper notes.* write 60 --as jarvis
echo rc=$?
act grant helper notes.* write 60
echo rc=$?
act call notes.add "text=with grant" --as helper
echo rc=$?
act call notes.add "text=script note" --as script
echo rc=$?
echo ==DENY==
act call notes.count --as intruder
echo rc=$?
echo ==UNDO==
act call notes.list
act undo --as helper
echo rc=$?
act undo --as helper
echo rc=$?
act call notes.list
echo ==COMPAT==
act call player.pause
echo rc=$?
act call player.status
echo rc=$?
echo ==SQUAT==
notes serve 100
echo rc=$?
echo ==STAT==
act stat
echo ==LOG==
cat /var/log/orientbus.log
sleep 2
echo ==EVENTS==
cat /tmp/events.txt
echo ==BENCH==
act bench 2000
echo ==STOP==
act stop --as jarvis
echo rc=$?
act stop
echo ==FERTIG==
EOS
image "$TMPD/A.img" "$TMPD/s1.sh"
T0=$(date +%s%N)
run "$TMPD/A.img" a 1 150
T1=$(date +%s%N)
A="$TMPD/a.klar"
note "guest run: $(( (T1-T0)/1000000 )) ms, accel=$OSUM_QEMU_ACCEL"
if ! grep -qa '==FERTIG==' "$A"; then
    bad "the guest script did not reach its end"; tail -30 "$A" | sed 's/^/        /'
fi

echo "== 2. the catalogue =="
has "$A" "orientbus: ready apps=2 actions=8 rejected_manifests=1" "broker: 2 apps (notes + a wrapper), 8 actions/events, 1 manifest refused"
part "$A" LIST DESC > "$TMPD/list.txt"
has "$TMPD/list.txt" "notes.add write Add a note at the end of the list" "list: action, level, description"
has "$TMPD/list.txt" "notes.clear critical" "list: the critical action says so"
has "$TMPD/list.txt" "event notes.changed" "list: the event"
has "$TMPD/list.txt" "player.pause write Pause playback (not running)" "list: a wrapper whose program is not running says so"
hasnot "$TMPD/list.txt" "Pretend to be harmless" "the manifest that reached into another app's namespace is not in the catalogue"
has "$A" "evil.actions line 3: name outside the app's own namespace" "... and the broker says why"
has "$A" "unknown word (line skipped)" "an unknown word (adapter) is skipped, not fatal"
part "$A" DESC READ | grep -a '^{"bus"' | head -1 > "$TMPD/desc.json"
if python3 - "$TMPD/desc.json" "$TMPD/host.json" > "$TMPD/json.txt" 2>&1 <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
h = json.load(open(sys.argv[2]))
assert d["bus"] == "orient-bus" and d["version"] == 1
names = [a["name"] for a in d["actions"]]
assert names == ["notes.add", "notes.remove", "notes.count", "notes.list", "notes.clear"], names
add = d["actions"][0]
assert add["level"] == "write" and add["dry_run"] and add["undo"] == "notes.remove"
assert add["available"] is True
assert add["args"] == [{"name": "text", "type": "string", "required": True,
                        "description": "The text of the note, one line"}], add["args"]
clear = d["actions"][4]
assert clear["needs_confirmation"] is True
assert [e["name"] for e in d["events"]] == ["notes.changed"]
# the two readers of one format agree on everything they both state
for a, b in zip(d["actions"], h["actions"]):
    for k in ("name", "level", "description", "dry_run", "undo", "needs_confirmation"):
        assert a[k] == b[k], (a["name"], k, a[k], b[k])
    assert [(x["name"], x["type"], x["required"]) for x in a["args"]] == \
           [(x["name"], x["type"], x["required"]) for x in b["args"]], a["name"]
    assert [(x["name"], x["type"]) for x in a["returns"]] == \
           [(x["name"], x["type"]) for x in b["returns"]], a["name"]
print("json ok, %d actions, %d octets" % (len(d["actions"]), len(open(sys.argv[1]).read())))
PY
then ok "describe: valid JSON, types/levels/undo/available right, host and broker agree ($(cat "$TMPD/json.txt"))"
else bad "describe JSON: $(tail -3 "$TMPD/json.txt")"; head -c 600 "$TMPD/desc.json" | sed 's/^/        /'; fi

echo "== 3. calls =="
part "$A" READ WUSER > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=0" "read: notes.count answers 0"
has "$TMPD/p.txt" "rc=0" "read: exit code 0"
part "$A" WUSER WAGENT > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=1" "write by the user: done at once"
has "$TMPD/p.txt" "undo=available" "the reply says it can be undone"
part "$A" TYPES DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "err bad_arg wrong type index" "an int argument with letters is refused"
has "$TMPD/p.txt" "err missing_arg text" "a missing required argument is refused"
has "$TMPD/p.txt" "err bad_arg unknown colour" "an undeclared argument is refused"
has "$TMPD/p.txt" "err unknown_action notes.fly" "an undeclared action is refused"
has "$TMPD/p.txt" "act: arguments are key=value, not: @client=user" "a meta line cannot be smuggled in as an argument"

echo "== 4. rights =="
part "$A" WAGENT CONFIRM1 > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm 1 notes.add" "write by an agent without a grant: parked, number 1"
has "$TMPD/p.txt" "rc=2" "... exit code 2 = confirmation needed"
part "$A" CONFIRM1 TYPES > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=2" "confirm: the parked call runs"
part "$A" CRIT CONFAGENT > "$TMPD/p.txt"
n_conf=$(grep -ac '^confirm [0-9]* notes.clear' "$TMPD/p.txt")
[ "$n_conf" = 2 ] && ok "critical asks EVERY time -- even a client with an 'allow ... critical' rule and the user himself (2 of 2)" \
                  || bad "critical: $n_conf confirmations instead of 2"
has "$TMPD/p.txt" "rejected" "reject: said no"
has "$TMPD/p.txt" "count=2" "... and nothing was deleted"
part "$A" CONFAGENT GRANT > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied only the user may confirm" "an agent cannot confirm its own (or any) request"
part "$A" GRANT DENY > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied only the user may grant" "an agent cannot grant rights"
has "$TMPD/p.txt" "ok" "the user grants helper notes.* write for 60 s"
has "$TMPD/p.txt" "count=3" "with the grant the agent 'helper' writes directly"
has "$TMPD/p.txt" "count=4" "the policy file's 'allow script notes.add write' works the same way"
part "$A" DENY UNDO > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied notes.count" "a deny rule refuses even a read"

echo "== 5. dry run =="
part "$A" DRY CRIT > "$TMPD/p.txt"
has "$TMPD/p.txt" "would_delete=2" "dry run of a critical action: the app says what WOULD happen"
has "$TMPD/p.txt" "decision=allow" "dry run without app simulation: the broker answers"
hasnot "$TMPD/p.txt" "confirm " "a dry run never parks anything"
has "$TMPD/p.txt" "count=2" "... and afterwards still 2 notes"

echo "== 6. undo =="
part "$A" UNDO COMPAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "note.3=with grant" "before: note 3 is helper's"
n_list=$(grep -ac '^note\.' "$TMPD/p.txt")
has "$TMPD/p.txt" "err nothing_to_undo" "the second undo finds nothing (one change, one undo)"
tail -8 "$TMPD/p.txt" | grep -qa 'with grant' && bad "undo: helper's note still there" \
    || ok "undo removed exactly helper's note (via the manifest's notes.remove)"
tail -8 "$TMPD/p.txt" | grep -qa 'script note' && ok "... and left the script's note alone" \
    || bad "undo removed the wrong note"

echo "== 7. events, binding, squatting =="
has "$A" "orientbus: provider notes bound to pid=" "the provider's pid is bound by a ping the KERNEL routed"
part "$A" EVENTS BENCH > "$TMPD/ev.txt"
n_ev=$(grep -ac 'EVENT event notes.changed @app=notes count=' "$TMPD/ev.txt")
[ "${n_ev:-0}" -ge 5 ] && ok "act watch saw $n_ev notes.changed events" || bad "events: ${n_ev:-0}"
has "$TMPD/ev.txt" "EVENT event bus.confirm_needed" "a parked call is announced for a dialog"
part "$A" SQUAT STAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "notes: a.notes is taken" "a second 'notes' cannot take over a.notes"
part "$A" COMPAT SQUAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "err app_not_running player" "a wrapper action whose program is not there fails cleanly"
has "$TMPD/p.txt" "rc=1" "... with exit code 1"

echo "== 8. audit log and counters =="
part "$A" LOG EVENTS > "$TMPD/log.txt"
n_log=$(grep -ac '^t=' "$TMPD/log.txt")
[ "${n_log:-0}" -ge 20 ] && ok "audit log: $n_log lines" || bad "audit log: ${n_log:-0} lines"
has "$TMPD/log.txt" "client=jarvis verb=call action=notes.add decision=ask result=confirm" "the log shows the parked agent call"
has "$TMPD/log.txt" "client=intruder verb=call action=notes.count decision=deny result=err" "... the denied one"
has "$TMPD/log.txt" "verb=undo action=notes.remove decision=allow result=ok" "... the undo"
has "$TMPD/log.txt" "decision=allow result=forwarded dry=0" "... and the write-ahead line before each change"
has "$TMPD/log.txt" "verb=reject" "... and the rejection"
part "$A" STAT LOG > "$TMPD/p.txt"
has "$TMPD/p.txt" "denied=" "act stat answers"
grep -qa '^foreign_replies=0' "$TMPD/p.txt" && ok "no reply from a foreign pid was accepted" || bad "foreign replies"
has "$TMPD/p.txt" "log_failures=0" "no log line was lost"
grep -qa '^lazy_entries=[1-9]' "$TMPD/p.txt" && ok "allowed reads went through the audit buffer ($(grep -a '^lazy_entries=' "$TMPD/p.txt"))" || bad "no buffered read entries"
has "$TMPD/log.txt" "client=user verb=call action=notes.count decision=allow result=ok" "... and still reached the file"

part "$A" STOP FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied only the user may stop" "an agent cannot stop the broker"
has "$A" "notes: orient-bus is gone" "after 'act stop' the provider ends by itself"

echo "== 9. GEGENPROBE: no audit log, no change =="
cat > "$TMPD/s2.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
notes serve 30000 &
sleep 1
echo ==G1==
act call notes.add "text=unlogged"
echo rc=$?
act call notes.count
echo rc=$?
act stop
echo ==FERTIG==
EOS
image "$TMPD/B.img" "$TMPD/s2.sh" novarlog
run "$TMPD/B.img" b 1 60
B="$TMPD/b.klar"
part "$B" G1 FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "err audit_unavailable notes.add" "without /var/log the write is refused"
has "$TMPD/p.txt" "count=0" "... nothing was written, and a read still works"

echo "== 10. latency =="
L=$(grep -a 'act: bench calls=' "$A" | tail -1)
note "1 core: $L"
us=$(echo "$L" | sed -n 's/.*us_per_call=\([0-9]*\).*/\1/p')
fl=$(echo "$L" | sed -n 's/.* failed=\([0-9]*\).*/\1/p')
[ "${fl:-1}" = 0 ] && ok "2000 round trips client -> broker -> app -> broker -> client, 0 failed" || bad "bench failed=${fl:-?}"
[ -n "$us" ] && [ "$us" -le 2000 ] && ok "mean round trip ${us} us (limit 2000 us; 10 ms ticks over 2000 calls)" || bad "round trip ${us:-?} us (limit 2000)"
cat > "$TMPD/s3.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
notes serve 30000 &
sleep 1
act bench 3000
act bench 3000
act stop
echo ==FERTIG==
EOS
image "$TMPD/C.img" "$TMPD/s3.sh"
run "$TMPD/C.img" c 4 90
L4=$(grep -a 'act: bench calls=' "$TMPD/c.klar" | tail -1)
note "4 cores: $L4"
[ "$(grep -a 'act: bench calls=3000' "$TMPD/c.klar" | grep -ac 'failed=0')" = 2 ] \
    && ok "4 cores: 2 x 3000 round trips, 0 failed" || bad "4 cores: $(grep -a 'act: bench' "$TMPD/c.klar" | tr '\n' ' ')"
grep -qaE 'panic|EXCEPTION' "$TMPD/c.klar" "$A" && bad "a panic or exception in a guest" || ok "no panic, no exception"
us4=$(echo "$L4" | sed -n 's/.*us_per_call=\([0-9]*\).*/\1/p')
echo "ACTIONBUS-LATENCY us_1core=${us:-?} us_4core=${us4:-?}"

# ===================================================================
echo "== 12. AB-003: attested caller identity =="
# ===================================================================
# /apps/evil.prog is an app bundle whose "start" is a shell: everything
# it runs -- /bin/act, a COPY of act in /tmp -- is app:evil for the
# kernel, whatever it claims with --as.
cat > "$TMPD/evil.sh" <<'EOS'
echo ==E-WHO==
act whoami --as user
echo ==E-WRITE==
act call notes.add "text=evil" --as user
echo rc=$?
echo ==E-CONFIRM==
act confirm last --as user
echo rc=$?
echo ==E-GRANT==
act grant app:evil notes.* write 60
echo rc=$?
echo ==E-COPY==
cp /bin/act /tmp/a2
chmod 755 /tmp/a2
/tmp/a2 whoami --as user
echo ==E-SQUAT==
act claim a.notes2
echo rc=$?
act claim a.evil
echo rc=$?
act claim orient.bus2
echo rc=$?
act claim r.1
echo rc=$?
echo ==E-PROC==
cat /proc/self/status
echo ==E-END==
EOS
cat > "$TMPD/s4.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
notes serve 30000 &
sleep 1
echo ==WHO==
act whoami
act whoami --as jarvis
echo ==EVIL==
/apps/evil.prog/start /t/evil.sh
echo ==OSP==
/apps/evil2.osp/start /t/who.sh
echo ==SYSB==
/apps/tool.osp/start /t/who.sh
echo ==CHAIN==
/apps/tool.osp/start /t/chain.sh
echo ==AFTER==
act call notes.list
act claim a.notes2
act claim orient.probe
echo ==STAT==
act stat
echo ==LOG==
cat /var/log/orientbus.log
act stop
echo ==FERTIG==
EOS
echo "act whoami --as user" > "$TMPD/who.sh"
echo "/apps/evil.prog/start /t/who.sh" > "$TMPD/chain.sh"
echo "shipped with the image" > "$TMPD/SYSTEM"
EXTRA=(/apps/evil.prog/ "/apps/evil.prog/start=$TMPD/bin/sh.elf" "/t/evil.sh=$TMPD/evil.sh"
       /apps/evil2.osp/ "/apps/evil2.osp/start=$TMPD/bin/sh.elf"
       /apps/tool.osp/ "/apps/tool.osp/start=$TMPD/bin/sh.elf" "/apps/tool.osp/SYSTEM=$TMPD/SYSTEM"
       "/t/who.sh=$TMPD/who.sh" "/t/chain.sh=$TMPD/chain.sh")
image "$TMPD/D.img" "$TMPD/s4.sh"
EXTRA=()
run "$TMPD/D.img" d 1 90
D="$TMPD/d.klar"
grep -qa '==FERTIG==' "$D" || { bad "identity guest did not finish"; tail -20 "$D" | sed 's/^/        /'; }
part "$D" WHO EVIL > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=user" "a process of the user without a label is 'user'"
has "$TMPD/p.txt" "attested=no" "... and the broker says it only took the default"
grep -qa 'client=jarvis' "$TMPD/p.txt" && ok "an unlabelled process may still NARROW itself (--as jarvis)" || bad "--as jarvis from the user's shell"
part "$D" E-WHO E-WRITE > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=app:evil" "an app saying --as user is app:evil for the broker"
has "$TMPD/p.txt" "origin=app:evil" "... because the KERNEL says so (origin from /apps/evil.prog)"
has "$TMPD/p.txt" "attested=yes" "... attested, not claimed"
part "$D" E-WRITE E-CONFIRM > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm 1 notes.add" "the app's write is parked for the user, not done"
part "$D" E-CONFIRM E-GRANT > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied only the user may confirm" "the app cannot confirm its own request, not even with --as user"
part "$D" E-GRANT E-COPY > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied only the user may grant" "... nor grant itself rights"
part "$D" E-COPY E-SQUAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=app:evil" "a COPY of act run by the app is still app:evil (the label is sticky)"
part "$D" E-SQUAT E-PROC > "$TMPD/p.txt"
has "$TMPD/p.txt" "act: claim refused a.notes2" "the app cannot take another app's provider name"
has "$TMPD/p.txt" "act: claimed ok a.evil" "... but its own"
has "$TMPD/p.txt" "act: claim refused orient.bus2" "an app cannot take an orient.* name"
has "$TMPD/p.txt" "act: claim refused r.1" "nobody can take another process's reply box"
has "$D" 'bus: reserved name "a.notes2" refused' "the kernel says so on the console"
part "$D" E-PROC E-END > "$TMPD/p.txt"
has "$TMPD/p.txt" "Origin: app:evil" "/proc/<pid>/status shows the origin"
part "$D" OSP SYSB > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=app:evil2" "an installed-style bundle (/apps/evil2.osp) is app:evil2"
part "$D" SYSB CHAIN > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=user" "a bundle the image ships (root-owned SYSTEM marker) acts as the user"
has "$TMPD/p.txt" "attested=no" "... it has no label"
part "$D" CHAIN AFTER > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=app:evil" "an app started FROM a system bundle (like the terminal) still gets its own label"
part "$D" AFTER STAT > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "note.1=evil" "the app's note was never written"
has "$TMPD/p.txt" "act: claimed ok a.notes2" "the user's own process may take a free a.* name"
has "$TMPD/p.txt" "act: claimed ok orient.probe" "... and, as root without a label, an orient.* name"
part "$D" STAT LOG > "$TMPD/p.txt"
grep -qa '^claims_ignored=[1-9]' "$TMPD/p.txt" && ok "the broker counted the ignored claims ($(grep -a '^claims_ignored=' "$TMPD/p.txt"))" || bad "claims_ignored"
has "$TMPD/p.txt" "foreign_providers=0" "no provider with a foreign origin"
part "$D" LOG FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=app:evil verb=call action=notes.add decision=ask result=confirm" "the audit log names app:evil, not 'user'"
hasnot "$TMPD/p.txt" "client=user verb=call action=notes.add decision=allow result=forwarded" "no write by 'user' happened in this run"

# ===================================================================
echo "== 13./14. settings on the bus, a Linux program behind adapters =="
# ===================================================================
if musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none \
        -o "$TMPD/fakeplayer" tools/foreign/start.s tools/foreign/osum_main.c \
        tools/actionbus/fakeplayer.c 2>"$TMPD/fp.txt"; then
    ok "fakeplayer: a plain POSIX C program, built as a static Linux binary (musl)"
else
    bad "fakeplayer does not build: $(grep -v 'GNU-stack' "$TMPD/fp.txt" | head -3)"
fi
cat > "$TMPD/fplayer.actions" <<'EOF'
manifest 1
app media
title "Media player (Linux program, wrapper by the community)"
for exe /opt/linux/fakeplayer
action media.status read "What is playing"
  adapter cli /opt/linux/fakeplayer status
  returns state string "playing, paused or stopped"
action media.pause write "Pause playback"
  adapter cli /opt/linux/fakeplayer pause
  undo media.play
action media.play write "Resume playback"
  adapter cli /opt/linux/fakeplayer play
action media.volume write "Set the volume"
  arg level int required "0..100"
  adapter cli /opt/linux/fakeplayer volume {level}
action media.title write "Name what is playing"
  arg text string required "Any text"
  adapter cli /opt/linux/fakeplayer title {text}
action media.echo read "Show the arguments the program receives"
  arg text string required "Any text"
  adapter cli /opt/linux/fakeplayer argv {text}
action media.hang read "A program that never answers"
  adapter cli /opt/linux/fakeplayer hang
action media.eq read "The equaliser preset, from the program's config file"
  adapter file /var/player/player.conf eq
action media.set_eq write "Choose the equaliser preset"
  arg preset string required "flat, rock or voice"
  adapter file /var/player/player.conf eq
action media.next write "Next track, by a key press in its window"
  adapter keys ctrl+right
EOF
cat > "$TMPD/gimp.actions" <<'EOF'
manifest 1
app gimp
title "GIMP (not installed here)"
for exe /opt/linux/gimp
action gimp.open write "Open a picture"
  adapter cli /opt/linux/gimp {path}
  arg path string required "The picture"
EOF
cat > "$TMPD/nativead.actions" <<'EOF'
manifest 1
app sneaky
action sneaky.run write "A native app may not hide an adapter"
  adapter cli /bin/sh -c x
EOF
printf '# /etc/sperre.conf -- test copy\nleerlauf=300\n' > "$TMPD/sperre.conf"
# DAILY-DRIVER: update.auto / update.channel are `store /etc/ota.conf auto|kanal`
printf '# /etc/ota.conf -- test copy\nquelle=https://example.invalid/aktuell\nabstand=3600\nauto=false\nkanal=stable\n' > "$TMPD/ota.conf"
printf 'schema 1\nsetting display.brightness int 0..100 dangerous "typo in the risk"\n' > "$TMPD/bad.schema"
python3 tools/actionbus/manifest.py check --wrapper "$TMPD/fplayer.actions" > "$TMPD/lint4.txt" 2>&1 \
    && ok "host reader takes the wrapper manifest ($(head -1 "$TMPD/lint4.txt" | cut -d' ' -f3-))" \
    || bad "host reader refuses the wrapper: $(cat "$TMPD/lint4.txt")"
python3 tools/actionbus/manifest.py check "$TMPD/fplayer.actions" > "$TMPD/lint5.txt" 2>&1 \
    && bad "host reader takes adapters in a NATIVE manifest" \
    || ok "host reader refuses adapters outside a wrapper manifest"
cat > "$TMPD/s5.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
settingsd serve 30000 &
sleep 1
echo ==S-CHECK==
settingsd check /etc/settings.schema
settingsd check /t/bad.schema
echo ==S-LIST==
act call settings.list area=display
echo ==S-DESC==
act describe settings.set
echo ==S-GET==
act call settings.get key=lock.idle
echo ==S-SETUSER==
act call settings.set key=display.brightness value=40
echo rc=$?
echo ==S-BADVAL==
act call settings.set key=display.brightness value=140
echo rc=$?
act call settings.set key=display.scale value=110
echo rc=$?
act call settings.set key=no.such value=1
echo rc=$?
echo ==S-AGENT==
act call settings.set key=display.brightness value=30 --as jarvis
echo rc=$?
act reject last
echo ==S-GRANT==
act grant jarvis settings.display.* write 60
act call settings.set key=display.brightness value=30 --as jarvis
echo rc=$?
act call settings.set key=sound.volume value=10 --as jarvis
echo rc=$?
act reject last
echo ==S-CRIT==
act call settings.set key=update.auto value=true --as jarvis
echo rc=$?
act reject last
act call settings.set key=update.auto value=true
echo rc=$?
act confirm last
echo rc=$?
echo ==S-DRY==
act call settings.set key=net.wifi.enabled value=false --dry --as jarvis
echo rc=$?
echo ==S-STORE==
act call settings.set key=lock.idle value=900
cat /etc/sperre.conf
echo ==S-UPD==
act call settings.update.status
act call settings.update.check --dry
act call settings.update.install --dry --as jarvis
act call settings.update.rollback --as jarvis
act reject last
act call settings.set key=update.channel value=test
act confirm last
cat /etc/ota.conf
act call settings.get key=update.channel
act call settings.set key=update.channel value=beta
echo ==S-HIST==
act call settings.history
echo ==S-UNDO==
act undo --as jarvis
echo rc=$?
act call settings.get key=display.brightness
echo ==S-REVERT==
act call settings.revert key=lock.idle change=4
echo rc=$?
cat /etc/sperre.conf
act call settings.revert key=display.brightness change=2
echo rc=$?
echo ==S-DB==
cat /etc/settings.db
echo ==S-JOURNAL==
cat /var/log/settings.journal
echo ==C-LIST==
act list
echo ==C-DESC==
act describe media.
echo ==C-STATUS==
act call media.status
echo ==C-RAW==
cat /tmp/orientbus.adapter.out
echo ==C-PAUSE==
act call media.pause
echo rc=$?
act call media.status
echo ==C-AGENT==
act call media.volume level=20 --as jarvis
echo rc=$?
act confirm last
act call media.status
echo ==C-INJECT==
act call media.echo "text=a b;rm -rf /"
echo ==C-DRY==
act call media.title text=hello --dry
act call media.status
echo ==C-FILE==
act call media.set_eq preset=rock
act call media.eq
cat /var/player/player.conf
echo ==C-UNDO==
act undo
act call media.status
echo ==C-KEYS==
act call media.next
echo rc=$?
echo ==C-GONE==
act call gimp.open path=/x.png
echo rc=$?
echo ==C-HANG==
act call media.hang
echo rc=$?
echo ==C-STAT==
act stat
echo ==C-LOG==
cat /var/log/orientbus.log
act stop
echo ==FERTIG==
EOS
EXTRA=("/etc/settings.schema=etc/settings.schema"
       "/etc/actions.d/settings.actions=etc/actions.d/settings.actions"
       "/etc/actions.d/fplayer.actions=$TMPD/fplayer.actions"
       "/etc/actions.d/gimp.actions=$TMPD/gimp.actions"
       /apps/sneaky.osp/ "/apps/sneaky.osp/ACTIONS=$TMPD/nativead.actions"
       "/etc/sperre.conf=$TMPD/sperre.conf" "/etc/ota.conf=$TMPD/ota.conf" "/t/bad.schema=$TMPD/bad.schema"
       /opt/ /opt/linux/ "/opt/linux/fakeplayer=$TMPD/fakeplayer"
       /var/player/@755:65534:65534)
image "$TMPD/E.img" "$TMPD/s5.sh"
EXTRA=()
run "$TMPD/E.img" e 1 150
E="$TMPD/e.klar"
grep -qa '==FERTIG==' "$E" || { bad "settings/compat guest did not finish"; tail -20 "$E" | sed 's/^/        /'; }
echo "  -- 13. settings"
has "$E" "orientbus: provider settings bound" "settingsd is a provider like any app (bound by the kernel-routed ping)"
part "$E" S-CHECK S-LIST > "$TMPD/p.txt"
has "$TMPD/p.txt" "settingsd: schema ok keys=14" "the shipped schema: 14 settings"
has "$TMPD/p.txt" "risk must be harmless or critical" "a broken schema is refused, with the reason"
part "$E" S-LIST S-DESC > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=3" "settings.list area=display: 3 settings"
has "$TMPD/p.txt" "display.brightness=80" "... with the default value"
has "$TMPD/p.txt" "display.brightness.type=int 0..100 harmless" "... type, range and risk"
has "$TMPD/p.txt" "display.brightness.text=Screen brightness in percent" "... and the description"
part "$E" S-DESC S-GET > "$TMPD/p.txt"
has "$TMPD/p.txt" '"keyed":"settings.schema"' "describe tells an agent that the key decides"
part "$E" S-GET S-SETUSER > "$TMPD/p.txt"
has "$TMPD/p.txt" "value=300" "lock.idle is read from the real /etc/sperre.conf"
part "$E" S-SETUSER S-BADVAL > "$TMPD/p.txt"
has "$TMPD/p.txt" "old=80" "the user changes a harmless setting at once (old=80)"
has "$TMPD/p.txt" "change=1" "... journalled as change 1"
part "$E" S-BADVAL S-AGENT > "$TMPD/p.txt"
has "$TMPD/p.txt" "err bad_value display.brightness out of range" "140 for 0..100 is refused -- by the broker, before the provider"
has "$TMPD/p.txt" "err bad_value display.scale not one of the words" "an enum value outside the list is refused"
has "$TMPD/p.txt" "err unknown_setting no.such" "an unknown key is refused"
part "$E" S-AGENT S-GRANT > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm 1 settings.display.brightness" "an agent's change is parked, and the rights name is the KEY"
part "$E" S-GRANT S-CRIT > "$TMPD/p.txt"
has "$TMPD/p.txt" "old=40" "with 'grant jarvis settings.display.* write 60' Jarvis sets display.brightness"
has "$TMPD/p.txt" "confirm 2 settings.sound.volume" "... but the grant is per AREA: sound.volume still asks"
part "$E" S-CRIT S-DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm 3 settings.update.auto" "a critical setting asks Jarvis"
has "$TMPD/p.txt" "level=critical" "... at level critical (from the schema's risk)"
has "$TMPD/p.txt" "confirm 4 settings.update.auto" "... and asks the USER too -- critical always asks"
has "$TMPD/p.txt" "change=3" "after the user's yes it is done"
part "$E" S-DRY S-STORE > "$TMPD/p.txt"
has "$TMPD/p.txt" "would=net.wifi.enabled from true to false" "a dry run of a critical change says what WOULD happen and changes nothing"
part "$E" S-STORE S-UPD > "$TMPD/p.txt"
has "$TMPD/p.txt" "leerlauf=900" "lock.idle lands in /etc/sperre.conf, where sperrwache reads it"
has "$TMPD/p.txt" "# /etc/sperre.conf -- test copy" "... and the file's other lines stay"
part "$E" S-UPD S-HIST > "$TMPD/p.txt"
has "$TMPD/p.txt" "here=0" "DAILY-DRIVER: settings.update.status answers (here=0: no ota.stand yet)"
has "$TMPD/p.txt" "phase=ruhe" "... phase ruhe by default"
has "$TMPD/p.txt" "channel=stable" "... channel from /etc/ota.conf"
has "$TMPD/p.txt" "busy=0" "... and nothing running"
has "$TMPD/p.txt" "would=search" "a dry run of update.check says what it would run and starts nothing"
has "$TMPD/p.txt" "would=apply" "... update.install the same"
has "$TMPD/p.txt" "confirm 5 settings.update.rollback" "update.rollback is critical: an agent's call is parked"
has "$TMPD/p.txt" "kanal=test" "update.channel lands in /etc/ota.conf, where ota reads it"
has "$TMPD/p.txt" "auto=true" "... update.auto (set to true in section S-CRIT) went into the same file"
has "$TMPD/p.txt" "abstand=3600" "... and the file's other lines stay"
has "$TMPD/p.txt" "value=test" "settings.get reads the channel from that file"
has "$TMPD/p.txt" "err bad_value update.channel not one of the words" "beta is not a channel any more (stable, test)"
part "$E" S-HIST S-UNDO > "$TMPD/p.txt"
has "$TMPD/p.txt" "change.2=display.brightness 40 -> 30 by jarvis" "settings.history: number, key, old, new, who"
part "$E" S-UNDO S-REVERT > "$TMPD/p.txt"
has "$TMPD/p.txt" "value=40" "act undo --as jarvis puts Jarvis' change back (the manifest's undo settings.set)"
part "$E" S-REVERT S-DB > "$TMPD/p.txt"
has "$TMPD/p.txt" "leerlauf=300" "settings.revert of change 4 writes the old value back into the file"
has "$TMPD/p.txt" "err changed_since display.brightness" "a revert of a value changed since is refused -- nothing is silently thrown away"
part "$E" S-DB S-JOURNAL > "$TMPD/p.txt"
has "$TMPD/p.txt" "display.brightness=40" "/etc/settings.db holds the stored value"
part "$E" S-JOURNAL C-LIST > "$TMPD/p.txt"
has "$TMPD/p.txt" "verb=set client=jarvis key=display.brightness old=40 new=30" "the journal names who changed what from what to what"
has "$TMPD/p.txt" "verb=revert client=user key=lock.idle old=900 new=300" "... and the revert"
part "$E" C-LOG FERTIG > "$TMPD/log.txt"
has "$TMPD/log.txt" "client=jarvis verb=call action=settings.update.auto decision=ask result=confirm" "the bus log names the key of the parked change"
echo "  -- 14. compat adapters"
has "$E" "sneaky.osp/ACTIONS line 4: adapters are for wrapper manifests" "a native app's manifest may not carry an adapter"
part "$E" C-LIST C-DESC > "$TMPD/p.txt"
has "$TMPD/p.txt" "gimp.open write Open a picture (not running)" "a wrapper whose program is not installed says so"
hasnot "$TMPD/p.txt" "media.status read What is playing (not running)" "... the installed one is available"
part "$E" C-DESC C-STATUS > "$TMPD/p.txt"
has "$TMPD/p.txt" '"adapter":"cli","reliability":"good"' "describe: adapter and reliability for an agent"
has "$TMPD/p.txt" '"adapter":"keys","reliability":"low"' "... a key-press adapter is marked low"
part "$E" C-STATUS C-RAW > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=stopped" "the Linux program answers through the cli adapter"
has "$TMPD/p.txt" "uid=65534" "... it ran as uid 65534, NOT as root (the broker is root)"
has "$TMPD/p.txt" "origin=compat:media" "... and the kernel labels it compat:media"
has "$TMPD/p.txt" "adapter=cli" "... the reply says which adapter"
part "$E" C-PAUSE C-AGENT > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=paused" "media.pause through the adapter changes the program's state"
part "$E" C-AGENT C-INJECT > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm 7 media.volume" "an agent's write to a wrapped program is parked like any other"
has "$TMPD/p.txt" "volume=20" "... and runs after the user's yes"
part "$E" C-INJECT C-DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "argc=3" "NO SHELL: 'a b;rm -rf /' reaches the program as ONE argument"
has "$TMPD/p.txt" "arg1=a b;rm -rf /" "... unchanged"
part "$E" C-DRY C-FILE > "$TMPD/p.txt"
has "$TMPD/p.txt" "would=/opt/linux/fakeplayer title hello" "a dry run shows the exact command and runs nothing"
has "$TMPD/p.txt" "title=nothing" "... the title is unchanged"
part "$E" C-FILE C-UNDO > "$TMPD/p.txt"
has "$TMPD/p.txt" "value=rock" "the file adapter writes and reads the program's config file"
has "$TMPD/p.txt" "eq=rock" "... the file holds eq=rock"
part "$E" C-UNDO C-KEYS > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=playing" "act undo runs the manifest's inverse (pause -> play) through the adapter"
part "$E" C-KEYS C-GONE > "$TMPD/p.txt"
has "$TMPD/p.txt" "err adapter_unsupported keys" "a key-press adapter is refused honestly (no key injection for foreign programs yet)"
part "$E" C-GONE C-HANG > "$TMPD/p.txt"
has "$TMPD/p.txt" "err app_not_running gimp" "a wrapped program that is not installed: app_not_running"
part "$E" C-HANG C-STAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "err adapter_failed exit=timeout" "a program that hangs is killed after 5 s, the broker keeps serving"
part "$E" C-STAT C-LOG > "$TMPD/p.txt"
grep -qa '^adapter_runs=[1-9]' "$TMPD/p.txt" && ok "the broker counted $(grep -a '^adapter_runs=' "$TMPD/p.txt")" || bad "adapter_runs"
has "$TMPD/log.txt" "client=user verb=call action=media.pause decision=allow result=forwarded" "the audit log has the write-ahead line of the adapter call"
grep -qaE 'panic|EXCEPTION' "$E" && bad "a panic or exception in the settings/compat guest" || ok "no panic, no exception"

# ===================================================================
echo "== 15. AB-006 what may which app, AB-009 dry run first, the signed-in user =="
# ===================================================================
if musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none \
        -o "$TMPD/setsess" tools/foreign/start.s tools/foreign/osum_main.c \
        tools/actionbus/setsess.c 2>"$TMPD/ss.txt"; then
    ok "setsess (test aid: the one kernel call glogin makes) builds"
else
    bad "setsess does not build: $(grep -v 'GNU-stack' "$TMPD/ss.txt" | head -3)"
fi
cat > "$TMPD/policy15" <<'EOF'
# section 15
deny  intruder *
allow script notes.add write
dryfirst jarvis
EOF
printf 'root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/:/bin/sh\nmara:x:1001:1001:Mara:/:/bin/sh\n' > "$TMPD/passwd15"
printf 'root:x:0:\njustin:x:1000:\nmara:x:1001:\n' > "$TMPD/group15"
cat > "$TMPD/s15.sh" <<'EOS'
orientbus serve 60000 &
sleep -m 300
notes serve 60000 &
sleep 1
echo ==R-WHO==
act whoami --as jarvis
echo ==R-NODRY==
act call notes.add text=plan-a --as jarvis
echo rc=$?
echo ==R-DRY==
act call notes.add text=plan-a --dry --as jarvis
echo rc=$?
echo ==R-REAL==
act call notes.add text=plan-a --as jarvis
echo rc=$?
echo ==R-AGAIN==
act call notes.add text=plan-a --as jarvis
echo rc=$?
echo ==R-OTHER==
act call notes.add text=plan-b --dry --as jarvis
act call notes.add text=plan-c --as jarvis
echo rc=$?
echo ==R-READ==
act call notes.count --as jarvis
echo rc=$?
echo ==R-USER==
act call notes.add text=by-hand
echo rc=$?
echo ==R-GRANT==
act grant jarvis notes.* write
cat /etc/orientbus/policy
act grant app:evil notes.count read 600
echo ==R-RIGHTS==
act rights
echo ==R-JRIGHTS==
act rights --as jarvis
echo ==R-JREVOKE==
act revoke 1 --as jarvis
echo rc=$?
act block jarvis notes.* --as jarvis
echo rc=$?
echo ==R-REVOKE==
act revoke jarvis notes.*
cat /etc/orientbus/policy
echo ==R-BLOCK==
act block app:evil notes.*
cat /etc/orientbus/policy
act call notes.count --as app:evil
echo rc=$?
echo ==R-SESS==
act call notes.add text=from-agent --as script2
act reject last
act call notes.add text=from-agent2 --as script2
su justin /bin/act confirm last
echo rc=$?
setsess 1000
su mara /bin/act confirm last
echo rc=$?
su justin /bin/act confirm last
echo rc=$?
su justin /bin/act rights
echo ==R-STAT==
act stat
act stop
echo ==FERTIG==
EOS
# the SECOND boot of the same disk: the broker starts again, reads the
# policy the first boot changed and seeds its counts from the audit log
cat > "$TMPD/s15b.sh" <<'EOS'
orientbus serve 20000 &
sleep -m 500
echo ==R-RESTART==
act rights
act stop
echo ==FERTIG==
EOS
EXTRA=("/etc/passwd=$TMPD/passwd15" "/etc/group=$TMPD/group15"
       "/bin/setsess=$TMPD/setsess" "/t/s2.sh=$TMPD/s15b.sh")
cp -f "$TMPD/etc/orientbus/policy" "$TMPD/policy.orig"
cp -f "$TMPD/policy15" "$TMPD/etc/orientbus/policy"
image "$TMPD/R.img" "$TMPD/s15.sh"
cp -f "$TMPD/policy.orig" "$TMPD/etc/orientbus/policy"
EXTRA=()
run "$TMPD/R.img" r 1 180
R="$TMPD/r.klar"
timeout 120 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd bus script=sh /t/s2.sh;exit" \
    -serial "file:$TMPD/r2.txt" -display none -no-reboot \
    -drive "file=$TMPD/R.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/r2.txt" > "$TMPD/r2.klar" 2>/dev/null || true
R2="$TMPD/r2.klar"
grep -qa '==FERTIG==' "$R" || { bad "section-15 guest did not finish"; tail -20 "$R" | sed 's/^/        /'; }
part "$R" R-WHO R-NODRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "dry_first=yes" "AB-009: whoami tells Jarvis it must dry-run first"
part "$R" R-NODRY R-DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "err dry_run_first notes.add" "a Jarvis change without a dry run is refused -- before anyone is asked"
part "$R" R-DRY R-REAL > "$TMPD/p.txt"
has "$TMPD/p.txt" "dry=1" "the dry run answers (and is noted)"
part "$R" R-REAL R-AGAIN > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm 1 notes.add" "the same call after its dry run goes on -- parked for the user as usual"
part "$R" R-AGAIN R-OTHER > "$TMPD/p.txt"
has "$TMPD/p.txt" "err dry_run_first" "one dry run pays for ONE call: the next identical call is refused again"
part "$R" R-OTHER R-READ > "$TMPD/p.txt"
has "$TMPD/p.txt" "err dry_run_first" "a dry run of plan-b does not pay for plan-c (the arguments count)"
part "$R" R-READ R-USER > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=" "reads need no dry run"
part "$R" R-USER R-GRANT > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=1" "the user is not under dryfirst"
part "$R" R-GRANT R-RIGHTS > "$TMPD/p.txt"
has "$TMPD/p.txt" "allow jarvis notes.* write" "a grant without seconds is permanent: it is written into /etc/orientbus/policy"
part "$R" R-RIGHTS R-JRIGHTS > "$TMPD/p.txt"
has "$TMPD/p.txt" "rule 1 deny intruder * permanent" "rights: the deny rule from the file, marked permanent"
has "$TMPD/p.txt" "rule 2 allow script notes.add write permanent" "rights: an allow rule from the file"
has "$TMPD/p.txt" "allow jarvis notes.* write permanent" "rights: the new permanent grant"
grep -qaE 'allow app:evil notes.count read left=(59[0-9]|600)' "$TMPD/p.txt" \
    && ok "rights: a timed grant with the seconds left ($(grep -aoE 'left=[0-9]+' "$TMPD/p.txt" | head -1))" \
    || bad "rights: no timed grant with seconds left"
has "$TMPD/p.txt" "dryfirst jarvis" "rights: the dry-run-first clients"
grep -qaE '^client jarvis reads=[1-9][0-9]* changes=0 asked=1 refused=3 dry=2' "$TMPD/p.txt" \
    && ok "rights: Jarvis' counts are exact ($(grep -a '^client jarvis' "$TMPD/p.txt"))" \
    || bad "rights: Jarvis' counts: $(grep -a '^client jarvis' "$TMPD/p.txt")"
grep -qaE '^client user reads=[0-9]+ changes=1 ' "$TMPD/p.txt" \
    && ok "rights: the user's change is counted" || bad "rights: user counts: $(grep -a '^client user' "$TMPD/p.txt")"
part "$R" R-JRIGHTS R-JREVOKE > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "intruder" "a client that is not the user sees only its own rules"
has "$TMPD/p.txt" "allow jarvis notes.* write" "... Jarvis sees its own grant"
part "$R" R-JREVOKE R-REVOKE > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied only the user may revoke" "Jarvis cannot revoke a rule"
has "$TMPD/p.txt" "err denied only the user may block" "... nor block anybody"
part "$R" R-REVOKE R-BLOCK > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok" "the user revokes Jarvis' permanent grant"
hasnot "$TMPD/p.txt" "allow jarvis notes.* write" "... and it is gone from /etc/orientbus/policy"
has "$TMPD/p.txt" "dryfirst jarvis" "... every other line of the file stays"
part "$R" R-BLOCK R-SESS > "$TMPD/p.txt"
has "$TMPD/p.txt" "deny app:evil notes.*" "block writes a permanent deny rule into the policy"
has "$TMPD/p.txt" "err denied notes.count" "... and the app is refused at once, even a read it had a grant for"
part "$R" R-SESS R-STAT > "$TMPD/p.txt"
grep -qa 'err denied only the user may confirm' "$TMPD/p.txt" \
    && ok "without a session, a uid-1000 process is not the user (as before)" || bad "uid 1000 confirmed without a session"
has "$TMPD/p.txt" "setsess: rc=0 who=1000" "the session is entered in the kernel (as glogin does)"
n_den=$(grep -ac 'err denied only the user may confirm' "$TMPD/p.txt")
[ "$n_den" -ge 2 ] && ok "another person (mara, uid 1001) is still not the user" || bad "mara could confirm ($n_den refusals)"
grep -qa 'index=2' "$TMPD/p.txt" \
    && ok "the person who signed in (justin, uid 1000) confirms -- the real device's case" \
    || bad "justin could not confirm in his own session"
has "$TMPD/p.txt" "rule " "... and sees all rules on the page"
part "$R" R-STAT R-RESTART > "$TMPD/p.txt"
has "$TMPD/p.txt" "dry_run_first=3" "stat counts the refused undry changes"
part "$R2" R-RESTART FERTIG > "$TMPD/p.txt"
has "$R2" "orientbus: counts seeded from" "after a reboot the broker seeds the counts from the audit log ($(grep -ao 'seeded from [0-9]* log lines' "$R2" | head -1))"
grep -qaE '^client jarvis reads=[1-9][0-9]* changes=0 asked=1 refused=3 dry=2' "$TMPD/p.txt" \
    && ok "... and they are the same numbers after the restart" \
    || bad "counts after restart: $(grep -a '^client jarvis' "$TMPD/p.txt")"
has "$TMPD/p.txt" "rule 1 deny intruder * permanent" "... the permanent rules come back from the file"
has "$TMPD/p.txt" "deny app:evil notes.* permanent" "... including the block"
hasnot "$TMPD/p.txt" "allow jarvis notes.* write" "... and the revoked grant stays revoked"
grep -qaE 'panic|EXCEPTION' "$R" "$R2" && bad "a panic or exception in the section-15 guests" || ok "no panic, no exception"

# ===================================================================
# ===================================================================
echo "== 16. AB-005c: sound, language and DHCP where they really live =="
# ===================================================================
# A guest WITH a sound card (intel-hda) and the session of justin: the
# bus reads and writes the card (sound.volume/sound.mute), the language
# lands in justin's own /users/justin/config/locale (handed to him), and
# net.dhcp is modus= in /etc/network.conf. GEGENPROBEN: without a
# session the language stays in the database; "fixed" without an ip= is
# refused; undo gives the language back.
printf 'modus=fest\nip=10.0.2.15\nmaske=255.255.255.0\ngateway=10.0.2.2\n' > "$TMPD/net16"
cat > "$TMPD/s16.sh" <<'EOS'
mkdir /users
mkdir /users/justin
orientbus serve 60000 &
sleep -m 300
settingsd serve 60000 &
sleep 1
echo ==V-VOL==
act call settings.set key=sound.volume value=35
act call settings.get key=sound.volume
act call settings.set key=sound.mute value=true
act call settings.get key=sound.mute
act call settings.set key=sound.mute value=false
echo ==V-NOSESS==
act call settings.set key=locale.language value=en
act call settings.get key=locale.language
cat /etc/settings.db
echo ==V-LANG==
setsess 1000
act call settings.set key=locale.language value=de
cat /users/justin/config/locale
echo ==V-OWN==
su justin /bin/chmod 600 /users/justin/config/locale
echo rc=$?
su mara /bin/chmod 666 /users/justin/config/locale
echo rc=$?
echo ==V-GET==
act call settings.get key=locale.language
echo ==V-UNDO==
act undo
cat /users/justin/config/locale
echo ==V-DGET==
act call settings.get key=net.dhcp
echo ==V-DSET==
act call settings.set key=net.dhcp value=true
act confirm last
cat /etc/network.conf
act call settings.get key=net.dhcp
echo ==V-DOFF==
act call settings.set key=net.dhcp value=false
act confirm last
cat /etc/network.conf
echo ==V-NOIP==
echo modus=dhcp > /etc/network.conf
act call settings.set key=net.dhcp value=false
act confirm last
cat /etc/network.conf
echo ==V-DB==
cat /etc/settings.db
act stop
echo ==FERTIG==
EOS
EXTRA=("/etc/passwd=$TMPD/passwd15" "/etc/group=$TMPD/group15"
       "/bin/setsess=$TMPD/setsess" "/etc/network.conf=$TMPD/net16"
       "/etc/settings.schema=etc/settings.schema"
       "/etc/actions.d/settings.actions=etc/actions.d/settings.actions")
image "$TMPD/V.img" "$TMPD/s16.sh"
EXTRA=()
timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd bus audio nosounds script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/v.txt" -display none -no-reboot \
    -audiodev "wav,id=snd0,path=$TMPD/v.wav" \
    -device intel-hda -device hda-duplex,audiodev=snd0 \
    -drive "file=$TMPD/V.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/v.txt" > "$TMPD/v.klar" 2>/dev/null || true
V="$TMPD/v.klar"
grep -qa '==FERTIG==' "$V" || { bad "section-16 guest did not finish"; tail -20 "$V" | sed 's/^/        /'; }
part "$V" V-VOL V-NOSESS > "$TMPD/p.txt"
has "$TMPD/p.txt" "settingsd: sound card volume=35 rc=0" "sound.volume goes to the sound card (SYS_AUDSET), not into a file"
has "$TMPD/p.txt" "value=35" "... and settings.get reads it back FROM the card"
has "$TMPD/p.txt" "value=true" "sound.mute: set and read back through the card"
part "$V" V-NOSESS V-LANG > "$TMPD/p.txt"
has "$TMPD/p.txt" "locale.language=en" "GEGENPROBE: without a session the language stays in /etc/settings.db"
part "$V" V-LANG V-UNDO > "$TMPD/p.txt"
has "$TMPD/p.txt" "settingsd: language for uid=1000 ok=1" "with justin's session settingsd writes HIS choice"
grep -qaE '^de$' "$TMPD/p.txt" && ok "... into /users/justin/config/locale (the file msg.fi reads first)" || bad "no 'de' in /users/justin/config/locale"
has "$TMPD/p.txt" "settingsd: chown rc=0" "... handed to him (chown)"
part "$V" V-OWN V-GET > "$TMPD/p.txt"
grep -qa '^rc=0' "$TMPD/p.txt" && ok "... his file: justin may chmod it (only the owner may)" || bad "justin cannot chmod his own locale file: $(tr '\n' '|' < "$TMPD/p.txt")"
grep -qaE '^rc=[1-9]' "$TMPD/p.txt" && ok "GEGENPROBE: mara may not" || bad "mara could chmod justin's file"
part "$V" V-GET V-UNDO > "$TMPD/p.txt"
has "$TMPD/p.txt" "value=de" "settings.get reads the language from his file"
part "$V" V-UNDO V-DGET > "$TMPD/p.txt"
grep -qaE '^en$' "$TMPD/p.txt" && ok "undo writes the old language back into his file" || bad "undo: $(tr '\n' '|' < "$TMPD/p.txt" | cut -c1-200)"
part "$V" V-DGET V-DSET > "$TMPD/p.txt"
has "$TMPD/p.txt" "value=false" "net.dhcp is read from /etc/network.conf (modus=fest -> false)"
part "$V" V-DSET V-DOFF > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm " "net.dhcp is critical: the user is asked too"
has "$TMPD/p.txt" "modus=dhcp" "after the yes: modus=dhcp in /etc/network.conf"
has "$TMPD/p.txt" "ip=10.0.2.15" "... every other line of the file stays"
has "$TMPD/p.txt" "settingsd: dhcp started pid=" "... and /bin/dhcp is started (as the page did)"
part "$V" V-DOFF V-NOIP > "$TMPD/p.txt"
has "$TMPD/p.txt" "modus=fest" "back to the fixed address that is written there"
part "$V" V-NOIP V-DB > "$TMPD/p.txt"
has "$TMPD/p.txt" "net.dhcp=false refused, no ip=" "GEGENPROBE: 'fixed' without an address is refused"
has "$TMPD/p.txt" "modus=dhcp" "... and the file is untouched"
part "$V" V-DB FERTIG > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "sound.volume" "the volume never went into /etc/settings.db"
hasnot "$TMPD/p.txt" "net.dhcp" "... nor net.dhcp"
grep -qaE 'panic|EXCEPTION' "$V" && bad "a panic or exception in the section-16 guest" || ok "no panic, no exception (section 16)"

# ===================================================================
echo "== 17. AB-002: the bus blocks -- an idle broker does not run =="
# ===================================================================
# Before this round the broker and settingsd turned once per tick (and
# yielded in between) while nothing happened. Now they wait in the
# kernel (BUS_RECV with a wait, S_POLL) and are woken by the delivery.
# Measured: how often the scheduler ran each of them in 5 idle seconds
# (/proc/<pid>/status Runs:). The wait is capped at 100 ms for their
# timers, so the ceiling is ~50 wakes; the old loop was ~500.
# And a call still gets through at once (the latency of section 10).
cat > "$TMPD/s17.sh" <<'EOS'
orientbus serve 0 &
B=$!
sleep -m 300
settingsd serve 0 &
S=$!
notes serve 0 &
sleep 2
echo ==I-A==
cat /proc/$B/status
cat /proc/$S/status
sleep 5
echo ==I-B==
cat /proc/$B/status
cat /proc/$S/status
echo ==I-CALL==
act call settings.get key=lock.idle
act bench 500
act stop
echo ==FERTIG==
EOS
EXTRA=("/etc/settings.schema=etc/settings.schema"
       "/etc/actions.d/settings.actions=etc/actions.d/settings.actions")
image "$TMPD/I.img" "$TMPD/s17.sh"
EXTRA=()
run "$TMPD/I.img" i 1 90
I="$TMPD/i.klar"
grep -qa '==FERTIG==' "$I" || { bad "section-17 guest did not finish"; tail -20 "$I" | sed 's/^/        /'; }
python3 - "$I" <<'PY' > "$TMPD/idle.txt"
import re, sys
t = open(sys.argv[1], errors="replace").read()
def runs(a, b):
    seg = t.split("==%s==" % a, 1)[1].split("==%s==" % b, 1)[0]
    return [int(x) for x in re.findall(r"Runs:\s*(\d+)", seg)]
a = runs("I-A", "I-B"); b = runs("I-B", "I-CALL")
if len(a) == 2 and len(b) == 2:
    print("broker=%d settingsd=%d" % (b[0] - a[0], b[1] - a[1]))
else:
    print("none")
PY
IDLE=$(cat "$TMPD/idle.txt")
note "scheduler runs in 5 idle seconds: $IDLE"
db=$(echo "$IDLE" | sed -n 's/broker=\([0-9]*\).*/\1/p'); ds=$(echo "$IDLE" | sed -n 's/.*settingsd=\([0-9]*\).*/\1/p')
[ -n "$db" ] && [ "$db" -le 80 ] && ok "the idle broker ran $db times in 5 s (<= 80; the old loop slept 10 ms per turn: up to 500)" || bad "idle broker runs: ${db:-?}"
[ -n "$ds" ] && [ "$ds" -le 80 ] && ok "idle settingsd ran $ds times in 5 s (<= 80)" || bad "idle settingsd runs: ${ds:-?}"
part "$I" I-CALL FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "value=300" "after the idle wait a call is answered (the delivery woke them)"
Li=$(grep -a 'act: bench calls=500' "$TMPD/p.txt" | tail -1)
usi=$(echo "$Li" | sed -n 's/.*us_per_call=\([0-9]*\).*/\1/p')
[ -n "$usi" ] && [ "$usi" -le 2000 ] && ok "blocking receive: 500 round trips at ${usi} us each (limit 2000)" || bad "bench after idle: ${Li:-none}"
echo "ACTIONBUS-IDLE $IDLE us_blocking=${usi:-?}"
grep -qaE 'panic|EXCEPTION' "$I" && bad "a panic or exception in the section-17 guest" || ok "no panic, no exception (section 17)"

# ===================================================================
echo "== 18. AB-018: the catalogue is read again without a restart =="
# ===================================================================
# An app appears (its wrapper manifest is copied into /etc/actions.d),
# `act reload` reads the catalogue again: the new app is callable, the
# provider of notes stays bound, an undo record from before still works;
# the manifest is removed, the next reload and it is gone. opk calls the
# same reload after it rebuilt /apps (kernel/user/opk.fi, bus_reload).
cat > "$TMPD/extra.actions" <<'EOM'
manifest 1
app extra
title "An app installed while the broker runs"
for exe /bin/echo
action extra.hello write "Say hello"
  adapter cli /bin/echo hello-from-extra
EOM
cat > "$TMPD/s18.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
notes serve 0 &
sleep 1
echo ==L-BEFORE==
act list
act call notes.add text=before-reload
echo ==L-DENY==
act reload --as jarvis
echo rc=$?
echo ==L-ADD==
cp /t/extra.actions /etc/actions.d/extra.actions
act reload
echo rc=$?
act list
act call extra.hello
echo ==L-KEEP==
act call notes.count
act undo
act call notes.count
echo ==L-DEL==
rm /etc/actions.d/extra.actions
act reload
act call extra.hello
echo ==L-STAT==
act stat
act stop
echo ==FERTIG==
EOS
EXTRA=("/t/extra.actions=$TMPD/extra.actions")
image "$TMPD/L.img" "$TMPD/s18.sh"
EXTRA=()
run "$TMPD/L.img" l 1 90
L="$TMPD/l.klar"
grep -qa '==FERTIG==' "$L" || { bad "section-18 guest did not finish"; tail -20 "$L" | sed 's/^/        /'; }
part "$L" L-BEFORE L-DENY > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "extra.hello" "before: extra is not in the catalogue"
part "$L" L-DENY L-ADD > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied only the user may reload" "only the user may reload (Jarvis may not)"
part "$L" L-ADD L-KEEP > "$TMPD/p.txt"
grep -qaE '^apps=[0-9]+' "$TMPD/p.txt" && ok "reload answers ($(grep -a '^apps=' "$TMPD/p.txt" | head -1), $(grep -a '^apps_was=' "$TMPD/p.txt" | head -1))" || bad "no reload answer"
has "$TMPD/p.txt" "extra.hello write" "after the reload the new app is in the catalogue"
has "$TMPD/p.txt" "hello-from-extra" "... and callable (its adapter ran)"
has "$L" "orientbus: reloaded apps=" "the broker says so on its log line"
part "$L" L-KEEP L-DEL > "$TMPD/p.txt"
grep -qaE '^count=1$' "$TMPD/p.txt" && ok "the provider of notes stays bound across the reload (count=1)" || bad "notes after the reload: $(tr '\n' '|' < "$TMPD/p.txt" | cut -c1-200)"
grep -qaE '^count=0$' "$TMPD/p.txt" && ok "the undo record from before the reload still works (count=0)" || bad "undo after the reload did not work"
part "$L" L-DEL L-STAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "err unknown_action extra.hello" "a removed manifest is gone after the next reload"
grep -qaE 'panic|EXCEPTION' "$L" && bad "a panic or exception in the section-18 guest" || ok "no panic, no exception (section 18)"

# ===================================================================
echo "== 19. AB-012: the audit log rotates, and the user can read it =="
# ===================================================================
# A policy with `auditmax 3000`: thirty notes are added (thirty audit
# lines of ~150 octets), so the log passes 3000 octets ONCE and rotates -- the
# older lines go to /var/log/orientbus.log.1, the new log begins with a
# line that says so. `act audit 5` gives the last five lines, to the user
# only. A second boot of the same disk seeds the counts from BOTH files:
# the user's thirty changes are still thirty.
cat > "$TMPD/policy19" <<'EOM'
# section 19
auditmax 3000
EOM
{
echo 'orientbus serve 0 &'
echo 'sleep -m 300'
echo 'notes serve 0 &'
echo 'sleep 1'
for i in $(seq 1 30); do echo "act call notes.add text=line-$i"; done
echo 'echo ==A-FILES=='
echo 'ls /var/log'
echo 'cat /var/log/orientbus.log'
echo 'echo ==A-READ=='
echo 'act audit 5'
echo 'echo ==A-DENY=='
echo 'act audit --as jarvis'
echo 'echo ==A-RIGHTS=='
echo 'act rights'
echo 'act stop'
echo 'echo ==FERTIG=='
} > "$TMPD/s19.sh"
cat > "$TMPD/s19b.sh" <<'EOS'
orientbus serve 20000 &
sleep -m 500
echo ==A-RESTART==
act rights
act stop
echo ==FERTIG==
EOS
cp -f "$TMPD/etc/orientbus/policy" "$TMPD/policy.orig"
cp -f "$TMPD/policy19" "$TMPD/etc/orientbus/policy"
EXTRA=("/t/s2.sh=$TMPD/s19b.sh")
image "$TMPD/A19.img" "$TMPD/s19.sh"
EXTRA=()
cp -f "$TMPD/policy.orig" "$TMPD/etc/orientbus/policy"
run "$TMPD/A19.img" a19 1 120
A19="$TMPD/a19.klar"
timeout 90 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd bus script=sh /t/s2.sh;exit" \
    -serial "file:$TMPD/a19b.txt" -display none -no-reboot \
    -drive "file=$TMPD/A19.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/a19b.txt" > "$TMPD/a19b.klar" 2>/dev/null || true
A19B="$TMPD/a19b.klar"
grep -qa '==FERTIG==' "$A19" || { bad "section-19 guest did not finish"; tail -20 "$A19" | sed 's/^/        /'; }
has "$A19" "orientbus: audit log rotated at" "the log rotated when it passed auditmax ($(grep -ao 'audit log rotated at [0-9]*' "$A19" | head -1))"
part "$A19" A-FILES A-READ > "$TMPD/p.txt"
has "$TMPD/p.txt" "orientbus.log.1" "the older generation is /var/log/orientbus.log.1"
has "$TMPD/p.txt" "# rotated: the older lines are in /var/log/orientbus.log.1" "the new log begins with a line that says so"
part "$A19" A-READ A-DENY > "$TMPD/p.txt"
has "$TMPD/p.txt" "rotations=1" "act audit: it rotated once"
has "$TMPD/p.txt" "auditmax=3000" "... at the size from the policy"
nl=$(grep -ac 'client=' "$TMPD/p.txt")
[ "$nl" = 5 ] && ok "act audit 5: exactly five log lines" || bad "act audit 5 gave $nl lines"
has "$TMPD/p.txt" "notes.add" "... the latest calls"
part "$A19" A-DENY A-RIGHTS > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied only the user may read" "GEGENPROBE: Jarvis may not read the audit log"
part "$A19" A-RIGHTS FERTIG > "$TMPD/p.txt"
grep -qaE '^client user reads=[0-9]+ changes=30 ' "$TMPD/p.txt" && ok "the user's thirty changes are counted" || bad "user counts: $(grep -a '^client user' "$TMPD/p.txt")"
grep -qa '==FERTIG==' "$A19B" || bad "section-19 second boot did not finish"
grep -qaE 'counts seeded from [0-9]+ log lines' "$A19B" && ok "the second boot seeds from both files ($(grep -aoE 'seeded from [0-9]+ log lines' "$A19B" | head -1))" || bad "no seeding on the second boot"
part "$A19B" A-RESTART FERTIG > "$TMPD/p.txt"
grep -qaE '^client user reads=[0-9]+ changes=30 ' "$TMPD/p.txt" && ok "... and after the restart they are still thirty (the older generation included)" || bad "user counts after restart: $(grep -a '^client user' "$TMPD/p.txt")"
# (a line older than the ONE kept generation is gone for good -- the
# counts after a restart are those of the two files; docs section 12)
grep -qaE 'panic|EXCEPTION' "$A19" "$A19B" && bad "a panic or exception in the section-19 guests" || ok "no panic, no exception (section 19)"

echo "== 20. AB-015 who hears which event, AB-019 adapters at the same time =="
# ===================================================================
# AB-015: nothing is published on orient.evt any more; a listener says
# `subscribe [glob]` and the broker SENDS it each event it may hear:
# the user everything, `bus.*` only the user, an event marked `private`
# nobody but the user (and the app), everybody else what a deny rule
# does not keep away -- asked again for every event.
# AB-019: an adapter call does not hold the broker. Two programs that
# hang run at the same time; meanwhile a read of another app is
# answered at once, and the catalogue is not re-read under a running job.
sed 's/^event notes.changed .*/&\n  private/' pakete/notes/ACTIONS > "$TMPD/np.actions"
cat > "$TMPD/s20.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
notes serve 0 &
sleep -m 500
act watch 0 > /tmp/ev_u.txt &
act watch 0 --as jarvis > /tmp/ev_j.txt &
act watch 0 notes.* --as helper > /tmp/ev_h.txt &
act watch 0 bus.* --as jarvis > /tmp/ev_jb.txt &
sleep 1
echo ==V-A==
act call notes.add "text=one"
act call notes.add "text=two" --as jarvis
act block helper notes.*
act call notes.add "text=three"
echo ==V-PRIV==
cp /t/np.actions /apps/notes.prog/ACTIONS
act reload
act call notes.add "text=four"
sleep 1
echo ==V-STAT==
act stat
echo ==V-ADAPT==
act call media.hang > /tmp/h1.txt &
act call media.hang > /tmp/h2.txt &
sleep -m 800
act bench 50
act call media.status
act reload
echo rc=$?
act stat
sleep 7
echo ==V-HANG==
cat /tmp/h1.txt
cat /tmp/h2.txt
act stat
act stop
sleep 1
echo ==V-EVU==
cat /tmp/ev_u.txt
echo ==V-EVJ==
cat /tmp/ev_j.txt
echo ==V-EVH==
cat /tmp/ev_h.txt
echo ==V-EVJB==
cat /tmp/ev_jb.txt
echo ==FERTIG==
EOS
EXTRA=("/etc/actions.d/fplayer.actions=$TMPD/fplayer.actions"
       /opt/ /opt/linux/ "/opt/linux/fakeplayer=$TMPD/fakeplayer"
       /var/player/@755:65534:65534 "/t/np.actions=$TMPD/np.actions")
image "$TMPD/V.img" "$TMPD/s20.sh"
EXTRA=()
run "$TMPD/V.img" v 1 120
V="$TMPD/v.klar"
grep -qa '==FERTIG==' "$V" || { bad "section-20 guest did not finish"; tail -20 "$V" | sed 's/^/        /'; }
part "$V" V-EVU V-EVJ > "$TMPD/eu.txt"; part "$V" V-EVJ V-EVH > "$TMPD/ej.txt"
part "$V" V-EVH V-EVJB > "$TMPD/eh.txt"; part "$V" V-EVJB FERTIG > "$TMPD/ejb.txt"
has "$TMPD/eu.txt" "notes.changed @app=notes count=1" "the user hears the app's event"
has "$TMPD/eu.txt" "event bus.confirm_needed" "... and the broker's own (a parked call)"
has "$TMPD/eu.txt" "notes.changed @app=notes count=3" "... and a private event"
has "$TMPD/ej.txt" "notes.changed @app=notes count=1" "Jarvis hears an ordinary app event it may read"
hasnot "$TMPD/ej.txt" "bus.confirm_needed" "Jarvis does NOT hear bus.confirm_needed (who wants to change what: the user only)"
hasnot "$TMPD/ej.txt" "count=3" "Jarvis does NOT hear an event marked private"
hasnot "$TMPD/ejb.txt" "EVENT" "subscribing to bus.* as Jarvis yields nothing"
has "$TMPD/eh.txt" "notes.changed @app=notes count=1" "helper hears notes.changed before the block"
hasnot "$TMPD/eh.txt" "count=2" "after 'act block helper notes.*' it hears nothing more -- at once, same subscription"
part "$V" V-STAT V-ADAPT > "$TMPD/p.txt"
grep -qaE 'events_withheld=[1-9]' "$TMPD/p.txt" && ok "the broker counts what it kept back ($(grep -aoE 'events_withheld=[0-9]+' "$TMPD/p.txt"))" || bad "events_withheld not counted"
has "$TMPD/p.txt" "subscriptions=4" "four listeners subscribed"
part "$V" V-ADAPT V-HANG > "$TMPD/p.txt"
Lb=$(grep -a 'act: bench calls=50' "$TMPD/p.txt" | tail -1)
tb=$(echo "$Lb" | sed -n 's/.*ticks=\([0-9]*\).*/\1/p'); fb=$(echo "$Lb" | sed -n 's/.*failed=\([0-9]*\).*/\1/p')
[ -n "$tb" ] && [ "$tb" -le 50 ] && [ "${fb:-1}" = 0 ] && ok "while two programs hang, 50 reads of notes take $tb ticks (<= 50; before AB-019 the broker stood 5 s)" || bad "bench during hangs: ${Lb:-none}"
has "$TMPD/p.txt" "state=" "... and another adapter call (media.status) is answered meanwhile"
has "$TMPD/p.txt" "err busy" "the catalogue is not re-read under a running program"
grep -qaE 'adapters_at_once=[2-4]' "$TMPD/p.txt" && ok "adapter programs ran at the same time ($(grep -aoE 'adapters_at_once=[0-9]+' "$TMPD/p.txt" | tail -1): two hanging + media.status)" || bad "adapters at once: $(grep -aoE 'adapters_at_once=[0-9]+' "$TMPD/p.txt" | tail -1)"
part "$V" V-HANG V-EVU > "$TMPD/p.txt"
n_to=$(grep -ac 'err adapter_failed exit=timeout' "$TMPD/p.txt")
[ "$n_to" = 2 ] && ok "both hanging programs are killed after 5 s and their callers answered" || bad "hang answers: $n_to"
echo "ACTIONBUS-EVENTS $(grep -aoE 'events_withheld=[0-9]+' "$V" | tail -1) $(grep -aoE 'adapters_at_once=[0-9]+' "$V" | tail -1) ticks50=${tb:-?}"
grep -qaE 'panic|EXCEPTION' "$V" && bad "a panic or exception in the section-20 guest" || ok "no panic, no exception (section 20)"

# ===================================================================
echo "== 21. AB-011 automations, as a client of the bus =="
# ===================================================================
# An automation is a file; each run labels itself automation:<name> in
# the kernel before its first call, so the broker decides every step for
# that client: a rule lets addtwo and tidy write notes, sneak has none
# and its critical step is parked; the log names each. tidy runs on the
# event notes.changed and keeps at most three notes; tick runs every
# second. A file with a bad name is refused.
mkdir -p "$TMPD/auto"
cat > "$TMPD/auto/addtwo.auto" <<'EOF'
automation 1
name addtwo
title "Two notes, by hand"
trigger manual
step notes.add text=auto-a
step notes.add text=auto-b
EOF
cat > "$TMPD/auto/tidy.auto" <<'EOF'
automation 1
name tidy
title "Keep at most three notes"
trigger event notes.changed
step notes.count
if count > 3
step notes.remove index=1
EOF
cat > "$TMPD/auto/sneak.auto" <<'EOF'
automation 1
name sneak
trigger manual
step notes.clear
EOF
cat > "$TMPD/auto/tick.auto" <<'EOF'
automation 1
name tick
trigger every 1
step notes.count
EOF
cat > "$TMPD/auto/bad.auto" <<'EOF'
automation 1
name Bad Name
trigger manual
step notes.count
EOF
cat > "$TMPD/s21.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
notes serve 0 &
sleep -m 500
echo ==U-LIST==
autorun list
echo ==U-DRY==
autorun run addtwo --dry
act call notes.count
echo ==U-RUN==
autorun run addtwo
echo rc=$?
act call notes.count
echo ==U-SNEAK==
autorun run sneak
echo rc=$?
act call notes.count
echo ==U-SERVE==
autorun serve 900 > /tmp/serve.txt &
sleep 1
act call notes.add text=c
act call notes.add text=d
act call notes.add text=e
sleep 5
echo ==U-COUNT==
act call notes.count
sleep 4
echo ==U-OUT==
cat /tmp/serve.txt
echo ==U-LOG==
cat /var/log/orientbus.log
act stop
echo ==FERTIG==
EOS
EXTRA=(/etc/automations/)
for f in addtwo tidy sneak tick bad; do EXTRA+=("/etc/automations/$f.auto=$TMPD/auto/$f.auto"); done
image "$TMPD/U.img" "$TMPD/s21.sh"
EXTRA=()
run "$TMPD/U.img" u 1 120
U="$TMPD/u.klar"
grep -qa '==FERTIG==' "$U" || { bad "section-21 guest did not finish"; tail -20 "$U" | sed 's/^/        /'; }
part "$U" U-LIST U-DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "addtwo manual steps=2" "autorun list: a manual automation"
has "$TMPD/p.txt" "tidy event notes.changed steps=2" "... one on an event"
has "$TMPD/p.txt" "tick every 1s steps=1" "... one on a timer"
has "$TMPD/p.txt" "autorun: refused: /etc/automations/bad.auto" "a file with a bad name is refused"
part "$U" U-DRY U-RUN > "$TMPD/p.txt"
has "$TMPD/p.txt" "autorun: done addtwo steps=2" "a dry run goes through every step (each sent with @dry=1)"
has "$TMPD/p.txt" "count=0" "... and changes nothing"
part "$U" U-RUN U-SNEAK > "$TMPD/p.txt"
has "$TMPD/p.txt" "autorun: done addtwo steps=2" "a manual run does its steps"
has "$TMPD/p.txt" "count=2" "... two notes"
part "$U" U-SNEAK U-SERVE > "$TMPD/p.txt"
has "$TMPD/p.txt" "autorun: parked for a confirmation, stop" "an automation without a rule is parked like any client (notes.clear)"
has "$TMPD/p.txt" "rc=2" "... exit code 2"
has "$TMPD/p.txt" "count=2" "... and nothing was cleared"
part "$U" U-COUNT U-OUT > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=3" "tidy ran on notes.changed and kept three notes (5 -> 3)"
part "$U" U-OUT U-LOG > "$TMPD/p.txt"
has "$TMPD/p.txt" "autorun: tidy triggered by notes.changed" "the trigger loop names the event"
n_t=$(grep -ac 'autorun: tick triggered by timer' "$TMPD/p.txt")
[ "$n_t" -ge 4 ] && ok "the timer ran tick $n_t times in ~9 s" || bad "tick ran $n_t times"
part "$U" U-LOG FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=automation:addtwo" "the audit log names the automation (kernel label), not the user"
has "$TMPD/p.txt" "client=automation:sneak" "... also the one that was parked"
has "$TMPD/p.txt" "client=automation:tidy verb=call action=notes.remove decision=allow" "tidy's removals are in the log under its own name"
grep -qa 'autorun: already labelled' "$U" && bad "a run could not label itself" || ok "every run labelled itself in the kernel"
echo "ACTIONBUS-AUTOMATIONS tick_runs=$n_t"
grep -qaE 'panic|EXCEPTION' "$U" && bad "a panic or exception in the section-21 guest" || ok "no panic, no exception (section 21)"

# ===================================================================
echo "== 11. Jarvis is a client: the real bridge, the real client =="
# ===================================================================
# The JARVIS server side is tools/bridge/peer.py (TLS 1.3, Ed25519 login,
# the same wire the live server speaks). It sends `befehl` jobs; jarvisd
# on the guest runs /bin/act -- the permission list allows exactly that
# one program. No other door: the broker sees client=jarvis and applies
# the same table as for everyone.
NS=actbus-$$; V0=ab0-$$; V1=abh1
QPORT=$(( 17000 + ($$ % 400) * 2 )); BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.0.2; HOST_IP=10.9.0.1; SRVPORT=8443
if ! command -v ip >/dev/null || ! ip netns add "$NS" 2>/dev/null \
   || ! python3 -c 'import cryptography' 2>/dev/null; then
    note "skipped: needs ip netns, python3-cryptography"
else
    ip netns del "$NS" 2>/dev/null
    BRPID=""; SRVPID=""
    wire_down() {
        [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; BRPID=""
        [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; SRVPID=""
        ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
    }
    trap 'wire_down; [ -n "${ACTBUS_KEEP:-}" ] || rm -rf "$TMPD"' EXIT
    W="$TMPD/w0"
    if BRIDGE_PROGS="sh ls cat echo chmod jsig jarvisctl sleep orientbus notes act" \
        bash tools/bridge/build.sh "$W" 0 > "$TMPD/bb.txt" 2>&1; then
        ok "bridge image: kernel + jarvisd + orientbus/notes/act"
    else
        bad "bridge image does not build"; tail -5 "$TMPD/bb.txt" | sed 's/^/        /'
    fi
    python3 tools/hwnet/mkcerts.py "$TMPD/certs" jarvis.test > /dev/null 2>&1
    gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null
    cat > "$TMPD/jperm.conf" <<CONF
server          = $HOST_IP:$SRVPORT
servername      = jarvis.test
roots           = /etc/ssl/roots.pem
commands        = yes
command_allowed = /bin/act
screenshot      = no
sysinfo         = yes
max_output      = 16384
CONF
    cat > "$TMPD/sj.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
notes serve 30000 &
sleep 1
jarvisd -1 -t 60000
echo ==JLOG==
cat /var/log/orientbus.log
act stop
echo ==FERTIG==
EOS
    python3 tools/osum/mkfs.py build "$TMPD/J.img" 16384 \
        /bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ /tmp/ /t/ \
        /apps/ /apps/notes.prog/ $(cat "$W/spec.txt" | tr ' ' '\n' | grep '=') \
        "/etc/jarvis/permissions.conf=$TMPD/jperm.conf" \
        "/etc/ssl/roots.pem=$TMPD/certs/ca.pem" \
        "/apps/notes.prog/start=$W/notes.elf" \
        "/apps/notes.prog/ACTIONS=pakete/notes/ACTIONS" \
        "/t/s.sh=$TMPD/sj.sh" > "$TMPD/mkfsj.txt" 2>&1 \
        || { bad "mkfs for the bridge image"; tail -3 "$TMPD/mkfsj.txt"; }
    # what Jarvis sends -- six words at most per command (jarvisd's rule)
    cat > "$TMPD/jobs.txt" <<'JOBS'
befehl|/bin/act describe notes.add|
befehl|/bin/act call notes.add text=from-jarvis --as jarvis|
befehl|/bin/act call notes.clear --dry --as jarvis|
befehl|/bin/act call notes.clear --as jarvis|
befehl|/bin/act call notes.count --as jarvis|
befehl|/bin/sh -c act|
befehl|/bin/act whoami --as user|
befehl|/bin/act call notes.add text=j2 --as user|
JOBS
    ip link del "$V0" 2>/dev/null
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add $HOST_IP/24 dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
    "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!
    sleep 0.4
    ip netns exec "$NS" python3 tools/bridge/peer.py \
        --cert "$TMPD/certs/good.pem" --key "$TMPD/certs/good.key" \
        --port "$SRVPORT" --auftraege "$TMPD/jobs.txt" --aus "$TMPD/g" \
        --wartezeit 90 > "$TMPD/g.stderr" 2>&1 & SRVPID=$!
    sleep 0.8
    timeout 200 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -kernel "$W/k.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 bus nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/j.txt" -display none -no-reboot \
        -drive "file=$TMPD/J.img,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cc" -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    [ -n "$SRVPID" ] && wait "$SRVPID" 2>/dev/null; SRVPID=""
    wire_down
    tr -cd '\11\12\15\40-\176' < "$TMPD/j.txt" > "$TMPD/j.klar"
    G="$TMPD/g"
    has "$G" "ANGEMELDET" "the JARVIS side signed the device in (TLS 1.3 + Ed25519)"
    st_of() { grep -a "^ANTWORT $1 " "$G" | head -1 | awk '{print $4}'; }
    [ "$(st_of 1)" = ok ] && ok "Jarvis: describe ran" || bad "describe: $(grep -a '^ANTWORT 1 ' "$G")"
    grep -qa '"name":"notes.add"' "$G.1.bin" 2>/dev/null \
        && ok "Jarvis got the typed catalogue (JSON) through the bridge" || bad "no catalogue in the bridge answer"
    has "$G.2.bin" "confirm 1 notes.add" "Jarvis writing without a grant: parked for the user, like any agent"
    has "$G.3.bin" "would_delete=0" "Jarvis dry-runs a critical action"
    has "$G.4.bin" "confirm 2 notes.clear" "Jarvis cannot run a critical action without a human yes"
    has "$G.5.bin" "count=0" "Jarvis reads directly"
    [ "$(st_of 6)" = nein ] && ok "the bridge refuses any other program (/bin/sh): /bin/act is the only door" \
                           || bad "sh via bridge: $(grep -a '^ANTWORT 6 ' "$G")"
    part "$TMPD/j.klar" JLOG FERTIG > "$TMPD/jl.txt"
    has "$TMPD/jl.txt" "client=jarvis verb=call action=notes.add decision=ask result=confirm" "the device's audit log names Jarvis"
    grep -a 'client=jarvis verb=call action=notes.clear decision=allow' "$TMPD/jl.txt" | grep -qa 'dry=0' \
        && bad "the log shows a critical action allowed for Jarvis" \
        || ok "... and no critical action allowed for it (only its dry run)"
    has "$TMPD/jl.txt" "client=jarvis verb=call action=notes.clear decision=allow result=ok dry=1" "... the dry run is logged as such"
    # AB-003: the bridge marks what it runs; --as user changes nothing
    has "$G.7.bin" "client=jarvis" "AB-003: a Jarvis command saying --as user is still jarvis"
    has "$G.7.bin" "origin=jarvis" "... because jarvisd labelled it in the kernel"
    has "$G.8.bin" "confirm 3 notes.add" "... so its write as 'user' is parked like any Jarvis write"
fi

echo "ACTIONBUS: $pass passed, $fail failed"
[ "$fail" = 0 ]
