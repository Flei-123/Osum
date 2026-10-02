#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/a11y/scene.sh -- FUI-ALL: THE ACCESSIBILITY TREE OF A WINDOW THAT
# fUi PAINTS (kernel/user/fuiscene.fi), MEASURED.
#
#   bash tools/a11y/scene.sh [workdir]
#
# tools/a11y/run.sh measures the tree wlib makes from its own widget list.
# A window painted by fUi's scene tree has ONE canvas widget in wlib's list,
# so fuiscene describes its own nodes (wlib.ax_set_hooks). This script boots
# the scene demo (tabs, field, main button, label), reads its tree over the
# bus like a screen reader would, and presses a button THROUGH the tree:
#
#   1. the nodes are there: tab, field with its text, button, label --
#      with role, name, place;
#   2. a press goes to the program: the demo's counter label changes
#      ("Klicks: 0" -> "Klicks: 1") and the next read says so;
#   3. a tab is refused like in a wlib window (the kernel presses buttons
#      and check boxes only).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep orientbus act axd scenedemo"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'
    echo "A11Y-SCENE: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "A11Y-SCENE: $pass passed, $fail failed"; exit 1
fi

cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
/apps/scenedemo.prog/start &
sleep 4
echo ==S-STATUS==
act call a11y.status
echo ==S-TREE==
act call a11y.tree window=Szenenbaum
echo ==S-PRESS==
act call a11y.press name=Klick! window=Szenenbaum
sleep 3
act call a11y.press name=Klick! window=Szenenbaum
sleep 3
act call a11y.press action=scene.click window=Szenenbaum
sleep 3
echo ==S-TREE2==
act call a11y.tree window=Szenenbaum
echo ==S-TAB==
act call a11y.press name=Zwei window=Szenenbaum
sleep 3
echo ==S-TREE3==
act call a11y.tree window=Szenenbaum
echo ==S-END==
act stop
echo ==FERTIG==
EOS

A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/ /apps/ /apps/scenedemo.prog/
   "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/apps/scenedemo.prog/start=$TMPD/bin/scenedemo.elf"
   "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
A+=("/etc/theme.conf=$TMPD/theme.conf" /etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "A11Y-SCENE: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
i=0
while [ $i -lt 1000 ]; do
    grep -qaF -- "==FERTIG==" "$TMPD/ser.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.3; i=$((i + 1))
done
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"
perl -0pi -e 's/wm: fen i=[^\n]*? tka=\d+\r?\n//g' "$TMPD/ser.klar"
G="$TMPD/ser.klar"

echo "== 3. the tree of a scene window =="
part "$G" S-TREE S-PRESS > "$TMPD/p.txt"
has "$TMPD/p.txt" '=window win' "the window node is there"
has "$TMPD/p.txt" '"Szenenbaum"' "... named by its title"
grep -qaF '"Klick!" act=scene.click' "$TMPD/p.txt" && ok "the main button carries its bus action scene.click (fuiscene.ax_action)" || bad "no act=scene.click on the main button"
grep -qaE '=button .*"Klick!"' "$TMPD/p.txt" && ok "the main button: role button, name Klick!" || bad "no button Klick!: $(head -8 "$TMPD/p.txt" | tr '\n' '|')"
grep -qaE '=tab .*"Eins"' "$TMPD/p.txt" && ok "the tabs: role tab, name Eins" || bad "no tab Eins"
grep -qaE '=tab .*"Zwei"' "$TMPD/p.txt" && ok "... and Zwei" || bad "no tab Zwei"
grep -qaE '=entry .*"Hallo"' "$TMPD/p.txt" && ok "the field: role entry, its text is the name" || bad "no entry Hallo"
grep -qaF '"Klicks: 0"' "$TMPD/p.txt" && ok "the label: role label, 'Klicks: 0'" || bad "no label Klicks: 0"

echo "== 4. a press through the tree reaches the program =="
part "$G" S-TREE2 S-TAB > "$TMPD/p.txt"
grep -qaF '"Klicks: 3"' "$TMPD/p.txt" && ok "two presses by name and one by bus action (action=scene.click) -> the label says 'Klicks: 3'" || bad "label after three presses: $(grep -a 'Klicks' "$TMPD/p.txt" | head -2)"
part "$G" S-TAB S-TREE3 > "$TMPD/p.txt"
grep -qaF 'err no_such_control' "$TMPD/p.txt" && ok "a tab is not pressable through the tree (only buttons and check boxes), same as in a wlib window" || bad "tab press: $(grep -a 'err' "$TMPD/p.txt" | head -1)"
part "$G" S-TREE3 S-END > "$TMPD/p.txt"
grep -qaE '=tab .*selected.*"Eins"' "$TMPD/p.txt" && ok "... and the page did not change" || bad "tab Eins is not selected any more"

echo
echo "A11Y-SCENE: $pass passed, $fail failed   (workdir $TMPD)"
[ "$fail" -eq 0 ] || exit 1
exit 0
