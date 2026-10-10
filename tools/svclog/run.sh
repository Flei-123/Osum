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
#   3. FILE     : the same output ALSO lands in /var/log/ota.log (read back from the disk image with mkfs.py cat).
#   4. ROTATION : boot word `svclogmax=300`: the file stays <= 300 octets, the older part is in ota.log.1.
#   5. CONTROL  : boot word `svclogmax=0` (files off): no /var/log/ota.log at all, the serial line is unchanged.
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

fcat() { # $1 = run name, $2 = path in the image; prints the file (nothing when it does not exist)
    # mkfs.py prints "no such path" on stdout and exits 1 for a missing file: that must read as an empty file
    local f="$TMPD/fcat.$$"
    if python3 tools/osum/mkfs.py cat "$TMPD/$1/disk.img" "$2" > "$f" 2> /dev/null; then tr -d '\000' < "$f"; fi
    rm -f "$f"
}

echo "== 3. file (/var/log/ota.log) =="
fcat fix /var/log/ota.log > "$TMPD/fix.ota.log"
[ -s "$TMPD/fix.ota.log" ] && ok "/var/log/ota.log exists ($(stat -c%s "$TMPD/fix.ota.log") octets)" || bad "no /var/log/ota.log"
n=$(grep -ac '^fetch:' "$TMPD/fix.ota.log"); [ "$n" -gt 0 ] && ok "the file holds the fetch lines ($n)" || bad "no fetch line in /var/log/ota.log"
# every fetch line of the file must also be on the serial line (the file is a copy, not a different text)
miss=0
while IFS= read -r line; do
    grep -aqF -- "$line" "$TMPD/fix/serial.txt" || miss=$((miss+1))
done < <(grep -a '^fetch:' "$TMPD/fix.ota.log" | tr -d '\r' | sort -u | head -20)
[ "$miss" = 0 ] && ok "file lines are on the serial line too (serial output kept)" || bad "$miss file line(s) missing on the serial line"
grep -aq 'desk: svclog tty=' "$TMPD/fix/serial.txt" && ok "serial line still has the log terminal setup" || bad "serial lost the setup line"

echo "== 4. rotation (svclogmax=300) =="
run rot "svclogmax=300"
fcat rot /var/log/ota.log > "$TMPD/rot.log"
fcat rot /var/log/ota.log.1 > "$TMPD/rot.log.1"
a=$(stat -c%s "$TMPD/rot.log"); b=$(stat -c%s "$TMPD/rot.log.1")
[ "$a" -gt 0 ] && [ "$a" -le 300 ] && ok "ota.log is $a octets (limit 300)" || bad "ota.log is $a octets (limit 300)"
[ "$b" -gt 0 ] && [ "$b" -le 300 ] && ok "ota.log.1 is $b octets (rotated, limit 300)" || bad "ota.log.1 is $b octets (expected 1..300)"
grep -aq 'fetch:' "$TMPD/rot.log.1" && ok "the rotated file holds fetch lines" || bad "no fetch line in ota.log.1"

echo "== 5. control (svclogmax=0 = files off) =="
run off "svclogmax=0"
fcat off /var/log/ota.log > "$TMPD/off.log"
[ -s "$TMPD/off.log" ] && bad "files off, yet /var/log/ota.log has $(stat -c%s "$TMPD/off.log") octets (the test measures nothing)" || ok "files off: no /var/log/ota.log"
F=$(grep -ac '^fetch:' "$TMPD/off/serial.txt"); [ "$F" -gt 0 ] && ok "files off: the serial line still carries fetch ($F lines)" || bad "files off: serial lost the fetch lines"

echo "== $pass ok, $fail fail =="
[ "$fail" = 0 ]
