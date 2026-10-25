#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

dd if=/dev/zero of="$D/blank.img" bs=1M count=0 seek=16 2>/dev/null
cat > "$D/plan.txt" <<PLAN
marke ---- system disk: every button is off ----
foto a_system
ziel diskbtn init
warte 2
marke ---- the second disk ----
ziel disknav 1
warte 3
foto b_blank
ziel diskbtn init
warte 2
tippe /dev/hda
taste ret
warte 6
foto c_wrong
ziel diskbtn init
warte 2
tippe /dev/hdb
taste ret
warte 8
foto d_init
ziel diskbtn create
warte 2
tippe 8
taste ret
warte 2
tippe /dev/hdb
taste ret
warte 8
ziel diskbtn create
warte 2
tippe 4
taste ret
warte 2
tippe /dev/hdb
taste ret
warte 8
foto e_two
ziel diskrow 0
warte 2
ziel diskbtn format
warte 2
tippe /dev/hdb
taste ret
warte 8
foto f_format
ziel diskrow 1
warte 2
ziel diskbtn delete
warte 2
tippe /dev/hdb
taste ret
warte 8
foto g_delete
PLAN

echo "== 1. /bin/disks: buttons, typed confirmation, system disk refused =="
bash tools/toolbench/build.sh "$D/win" app=/bin/disks progs="disks diskctl explorer sh echo ls cat mount" second="$D/blank.img" \
    extra="vfs nopart wighalt=240" wait=12 last=330 accel=kvm plan="$D/plan.txt" > "$D/win.log" 2>&1
W="$D/win/serial.txt"
grep -a "ZIEL NICHT\|unbekannt" "$D/win/plan.log" | head -5
[ -n "${1:-}" ] && { mkdir -p "$1"; cp "$D/win/plan.log" "$D/win/serial.txt" "$D/win.log" "$D"/win/*.png "$1/" 2>/dev/null; }
grep -qa '^disks: allow disk=/dev/hda init=0 new=0 format=0 delete=0' "$W" && ok "system disk: init, new, format, delete are all off" || bad "system disk is not locked in the window"
grep -qa '^disks: allow disk=/dev/hdb init=1 new=0 format=0 delete=0' "$W" && ok "blank second disk: only init is on" || bad "hdb blank state"
ACTS=$(grep -a '^disks: act ' "$W")
echo "$ACTS" | sed 's/^/        /'
[ "$(echo "$ACTS" | head -1)" = "disks: act init rc=3" ] && ok "counter-proof: a wrong typed name is refused (rc 3), the disk stays blank" || bad "wrong confirmation was not refused"
echo "$ACTS" | sed -n 2p | grep -q 'act init rc=0' && ok "init with the right typed name works after the refusal (so the refusal wrote nothing)" || bad "init"
[ "$(echo "$ACTS" | grep -c 'act create rc=0')" = 2 ] && ok "two partitions created through the window" || bad "create"
echo "$ACTS" | grep -q 'act format rc=0' && ok "format of a chosen partition" || bad "format"
echo "$ACTS" | grep -q 'act delete rc=0' && ok "delete of a chosen partition" || bad "delete"
[ "$(echo "$ACTS" | wc -l)" = 6 ] && ok "exactly six actions ran: the click on the locked system disk started none" || bad "action count $(echo "$ACTS" | wc -l)"
grep -qa '^disks: allow disk=/dev/hdb init=0 new=1 format=0 delete=0' "$W" && ok "after init: new is on, format/delete wait for a chosen row" || bad "state after init"
grep -qa '^disks: allow disk=/dev/hdb init=0 new=1 format=1 delete=1' "$W" && ok "a chosen row turns format and delete on" || bad "row selection"
if [ -s "$D/win/second.img" ]; then
    python3 tools/disks/wcheck.py vm "$D/win/second.img" "[(2048, 16384, 'ofs', 'data')]" 16384 drift > "$D/v.txt" 2>&1
    grep -a FAIL "$D/v.txt" | head -4
    tail -1 "$D/v.txt" | grep -q ' 0 failed' && ok "host check of the disk the window wrote: $(tail -1 "$D/v.txt")" || bad "host check of the written disk"
else
    bad "no second.img"
fi
tail -c 512 "$D/win/disk.img" | grep -qa 'EFI PART' && bad "THE SYSTEM DISK GOT A GPT" || ok "the system disk has no GPT at its end"
mkdir -p docs/shots/disks
cp "$D/win/e_two.png" docs/shots/disks/disks-write.png 2>/dev/null || true
echo "DISKS-WIN: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
