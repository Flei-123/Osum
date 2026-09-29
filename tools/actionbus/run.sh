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
PROGS="sh ls cat echo sleep mkdir orientbus notes act"
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
EOF
python3 tools/actionbus/manifest.py check "$TMPD/etc/actions.d/evil.actions" > "$TMPD/lint2.txt" 2>&1 \
    && bad "host reader takes a foreign namespace" \
    || ok "host reader refuses a foreign namespace ($(sed 's/.*line [0-9]*: //' "$TMPD/lint2.txt"))"

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "ACTIONBUS: skipped, qemu missing"; echo "ACTIONBUS: $pass passed, $fail failed"; exit 0; }

image() { # <image> <script> [novarlog]
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
fi

echo "ACTIONBUS: $pass passed, $fail failed"
[ "$fail" = 0 ]
