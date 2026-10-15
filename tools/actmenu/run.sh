#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/actmenu/run.sh -- D1: ACTIONS FROM THE ACTION BUS IN THE FILE MANAGER'S
# CONTEXT MENU (Mint/Nemo "Actions", but through the broker).
#
#   bash tools/actmenu/run.sh
#
# 1. host reader: `menu`/`menuext` parse, a broken line is refused
# 2. the explorer builds with the sub menu
# 3. real guest (QEMU): broker + notes + act
#    - `act list --menu file|dir <name>` answers action TAB label TAB level
#    - `menuext` filters by ending, case does not matter (counter-probe:
#      a .txt does not get the image writer)
#    - a picked action is an ordinary `call` (path=...): it lands in the
#      audit log and its undo works (rights/undo come for free)
#    - an action without `menu` is NOT offered (counter-probe)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. host reader =="
M=tools/actionbus/manifest.py
mkdir -p "$TMPD/etc"
cat > "$TMPD/etc/imgtool.actions" <<'EOT'
manifest 1
app imgtool
title "Image tool"
action imgtool.write write "Write an image to a stick"
  arg path string required "The image file"
  menu file "Write to stick"
  menuext img iso
action imgtool.dirsize read "Size of a folder"
  arg path string required "The folder"
  menu dir "Folder size"
action imgtool.hidden read "Not in any menu"
  arg path string required "A path"
EOT
cat > "$TMPD/etc/badmenu.actions" <<'EOT'
manifest 1
app badmenu
action badmenu.x read "x"
  menu nonsense "Nope"
EOT
python3 $M check pakete/notes/ACTIONS "$TMPD/etc/imgtool.actions" > "$TMPD/h1.txt" 2>&1 \
    && ok "host reader takes menu/menuext" || bad "host reader: $(cat "$TMPD/h1.txt")"
python3 $M menu file DISK.IMG "$TMPD/etc/imgtool.actions" pakete/notes/ACTIONS > "$TMPD/h2.txt" 2>&1
has "$TMPD/h2.txt" "imgtool.write	Write to stick	write" "host: .IMG gets the image writer (case-blind)"
has "$TMPD/h2.txt" "notes.addfile	Remember as note	write" "host: notes.addfile is offered for any file"
python3 $M menu file a.txt "$TMPD/etc/imgtool.actions" pakete/notes/ACTIONS > "$TMPD/h3.txt" 2>&1
hasnot "$TMPD/h3.txt" "imgtool.write" "host: a .txt does NOT get the image writer"
python3 $M menu dir d "$TMPD/etc/imgtool.actions" pakete/notes/ACTIONS > "$TMPD/h4.txt" 2>&1
has "$TMPD/h4.txt" "imgtool.dirsize	Folder size	read" "host: a folder gets the folder action"
hasnot "$TMPD/h4.txt" "imgtool.write" "host: a folder does not get the file action"
hasnot "$TMPD/h2.txt" "imgtool.hidden" "host: an action without menu is not offered"
python3 $M check "$TMPD/etc/badmenu.actions" > "$TMPD/h5.txt" 2>&1 \
    && bad "host reader takes a broken menu kind" || ok "host reader refuses a broken menu kind"

echo "== 2. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep mkdir orientbus notes act"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS explorer > "$TMPD/b.txt" 2>&1; then
    ok "programs + explorer build"
else
    bad "build"; head -20 "$TMPD/b.txt" | sed 's/^/        /'
    echo "ACTMENU: $pass passed, $fail failed"; exit 1
fi
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel"; echo "ACTMENU: $pass passed, $fail failed"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "ACTMENU: qemu missing"; echo "ACTMENU: $pass passed, $fail failed"; exit 0; }

echo "== 3. guest =="
cat > "$TMPD/s.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
notes serve 30000 &
sleep 1
echo ==FILE==
act list --menu file readme.txt
echo ==IMG==
act list --menu file Stick.ISO
echo ==DIR==
act list --menu dir /t/some_dir
echo ==SPACE==
act list --menu file my holiday photo.png
echo ==LIST==
act list
echo ==CALL==
act call notes.addfile path=/t/readme.txt
echo rc=$?
act call notes.list
echo ==AUDIT==
act audit 5
echo ==UNDO==
act undo last
act call notes.count
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/ \
    /apps/ /apps/notes.prog/ /var/ /var/log/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    "/apps/notes.prog/start=$TMPD/bin/notes.elf" \
    "/apps/notes.prog/ACTIONS=pakete/notes/ACTIONS" \
    "/etc/actions.d/imgtool.actions=$TMPD/etc/imgtool.actions" \
    "/t/s.sh=$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd bus script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/o.txt" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/o.txt" > "$TMPD/o.klar"
part "$TMPD/o.klar" FILE IMG > "$TMPD/p_file.txt"
part "$TMPD/o.klar" IMG DIR > "$TMPD/p_img.txt"
part "$TMPD/o.klar" DIR SPACE > "$TMPD/p_dir.txt"
part "$TMPD/o.klar" SPACE LIST > "$TMPD/p_space.txt"
part "$TMPD/o.klar" LIST CALL > "$TMPD/p_list.txt"
part "$TMPD/o.klar" CALL AUDIT > "$TMPD/p_call.txt"
part "$TMPD/o.klar" AUDIT UNDO > "$TMPD/p_audit.txt"
part "$TMPD/o.klar" UNDO END > "$TMPD/p_undo.txt"
has "$TMPD/p_file.txt" "notes.addfile	Remember as note	write" "guest: a .txt gets notes.addfile"
hasnot "$TMPD/p_file.txt" "imgtool.write" "guest: a .txt does NOT get the image writer"
hasnot "$TMPD/p_file.txt" "imgtool.hidden" "guest: an action without menu is not offered"
hasnot "$TMPD/p_file.txt" "imgtool.dirsize" "guest: a file does not get the folder action"
has "$TMPD/p_img.txt" "imgtool.write	Write to stick	write" "guest: Stick.ISO gets the image writer (case-blind)"
has "$TMPD/p_dir.txt" "imgtool.dirsize	Folder size	read" "guest: a folder gets the folder action"
has "$TMPD/p_dir.txt" "notes.addfile" "guest: menu any reaches folders too"
hasnot "$TMPD/p_dir.txt" "imgtool.write" "guest: a folder does not get the file action"
has "$TMPD/p_space.txt" "notes.addfile" "guest: a name with spaces works"
hasnot "$TMPD/p_space.txt" "imgtool.write" "guest: ... and still gets filtered by ending"
has "$TMPD/p_list.txt" "notes.addfile write" "guest: plain list still works and shows the new action"
has "$TMPD/p_call.txt" "count=1" "guest: the picked action is an ordinary call"
has "$TMPD/p_call.txt" "/t/readme.txt" "guest: the path arrived as the note"
has "$TMPD/p_audit.txt" "notes.addfile" "guest: the call is in the audit log"
has "$TMPD/p_undo.txt" "count=0" "guest: undo takes the note out again"
echo "ACTMENU: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
