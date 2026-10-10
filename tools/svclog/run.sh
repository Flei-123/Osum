#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/svclog/run.sh -- SERVICE OUTPUT MUST NOT LAND IN THE TERMINAL WINDOW.
#
#   /root/jarvis/bin/heavy bash tools/svclog/run.sh
#
# Dell photo: the terminal window (`sh`) kept filling with `fetch: ...` lines. Cause: `ota` (desktop service) starts
# `/bin/fetch` with `elf.spawn`; `file.inherit_std` swapped the log terminal against the CONSOLE (= the terminal window).
# Fix: services get a service log terminal (kgui.desk_spawn_svc) that the swap does not touch.
#
# Machine: the stick's (tools/design/eh6.sh) with /bin/ota, /bin/fetch and an /etc/ota.conf that points at a name which
# cannot be resolved (no network card) -> `ota` runs `fetch` over and over. The cells of the terminal window are dumped to
# the serial line (`termdump`: `wm: termzeile N [text]`).
#   1. FIX      : the serial line carries the `fetch` output, the cells of the window do NOT.
#   2. CONTROL  : boot word `svccon` (old behaviour): the same `fetch` text IS in the cells.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"
printf 'quelle=https://nonexistent.invalid\nauto=ja\nabstand=30\n' > "$TMPD/ota.conf"
head -c 32 /dev/zero | tr '\0' 'k' > "$TMPD/key.pub"   # any 32 octets: ota only needs A trusted key to start searching
export EH_MKFS_EXTRA="/var/ /var/log/ /etc/ota.conf=$TMPD/ota.conf@0644 /system/ /system/schluessel.pub=$TMPD/key.pub@0644"
printf 'warte 60\n' > "$TMPD/script.txt"
PROGS="desktop taskbar settings launcher explorer netview edit sh echo ls cat ps dhcp host ping ota"

run() { # $1 = name, $2 = extra boot words
    bash tools/design/eh6.sh "$TMPD/$1" accel=kvm "progs=$PROGS" "extra=termdump $2" drehbuch="$TMPD/script.txt" \
        > "$TMPD/$1.log" 2>&1
}
cells() { # all rows of all dumps, one text
    grep -a 'wm: termzeile' "$1/serial.txt" | sed 's/^wm: termzeile [0-9]* \[//; s/\]\s*$//' | sort -u
}

echo "== 1. fix (service log) =="
run fix ""
S="$TMPD/fix/serial.txt"
grep -aq 'desk: svclog tty=' "$S" && ok "the service log terminal was set up" || bad "no 'desk: svclog tty=' line"
grep -aq 'termzeile' "$S" && ok "terminal cells were dumped" || bad "no terminal dump"
F=$(grep -ac '^fetch:' "$S"); [ "$F" -gt 0 ] && ok "fetch output is on the serial line ($F lines)" || bad "no fetch line on the serial line"
cells "$TMPD/fix" > "$TMPD/fix.cells"
n=$(grep -ac 'fetch:' "$TMPD/fix.cells"); [ "$n" = 0 ] && ok "the terminal window shows no 'fetch:' line" || bad "terminal window shows $n 'fetch:' rows"

echo "== 2. control (svccon = old behaviour) =="
run con "svccon"
S="$TMPD/con/serial.txt"
cells "$TMPD/con" > "$TMPD/con.cells"
n=$(grep -ac 'fetch:' "$TMPD/con.cells"); [ "$n" -gt 0 ] && ok "control: the terminal window shows $n 'fetch:' rows" || bad "control: no 'fetch:' row in the window (the test measures nothing)"

echo "== $pass ok, $fail fail =="
[ "$fail" = 0 ]
