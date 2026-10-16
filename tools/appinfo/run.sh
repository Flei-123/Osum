#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/appinfo/run.sh -- r919: THE APP INFO PAGE OF SETTINGS ("Apps"), clicked in a real guest (QEMU).
#
#   /root/jarvis/bin/heavy bash tools/appinfo/run.sh [workdir]
#
# The guest has three apps with a manifest (alpha: net+notify+mic, spinner: notify, gone: net). A script in the guest
# loads the table (`apprights load`), starts `apprights burn spin spinner` (a live app:spinner task), opens Settings
# on page 18 and then, every 3 s, prints /etc/apprights.conf and `apprights list` ("==T<n>=="). The host clicks like a
# person (rects `apl?`, `apr?`, `apsp`, `apun`, ... from the serial log) and reads what changed:
#   1. the list shows the three apps with mask/ceiling from the table
#   2. detail of alpha: switches exist ONLY for declared rights (net, mic, notify); no rect for camera / fs.home
#   3. clicking `net` -> /etc/apprights.conf gets "alpha net"; notify -> both; net again -> only notify
#      (GEGENPROBE before the first click: the conf has no alpha line)
#   4. GEGENPROBE ceiling: `apprights set alpha camera` is refused and the conf is unchanged
#   5. force stop: killed=1 on the live spinner, killed=0 on the second click
#   6. uninstall asks twice (first click only arms; no uninstall line), the second runs `opk remove`, the app is gone
#   7. "Clear data", "Energy mode", "Pause" are drawn but do nothing (no action line, nothing changes)
#   8. the sidebar (19 entries) ends inside the window at 1280x800 and at 1024x576
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=${1:-$(mktemp -d)}
[ -z "${1:-}" ] && trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin" "$TMPD/bd"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh ls cat echo sleep apprights opk settings"
echo "== 1. build =="
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "programs build"
else bad "programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'; echo "APPINFO: $pass passed, $fail failed"; exit 1; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "kernel builds"
else bad "kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; echo "APPINFO: $pass passed, $fail failed"; exit 1; fi

printf 'name=alpha\nperm=net,notify,mic\nnet=real\n' > "$TMPD/bd/alpha.info"
printf 'name=spinner\nperm=notify\n' > "$TMPD/bd/spinner.info"
printf 'name=gone\nperm=net\nnet=real\n' > "$TMPD/bd/gone.info"
# a real generation (plan + store), so `opk remove` works like on an installed system; the seen file marks the safe
# rights as already offered, so `apprights load` grants nothing (mask=0 at the start)
HA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; HS=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; HG=cccccccccccccccccccccccccccccccc
printf '00000001\n' > "$TMPD/bd/AKTUELL"
printf 'alpha\t%s\nspinner\t%s\ngone\t%s\n' "$HA" "$HS" "$HG" > "$TMPD/bd/PLAN"
printf 'alpha net notify\nspinner notify\ngone net\n' > "$TMPD/bd/seen"
printf 'leerlauf=300\n' > "$TMPD/sperre.conf"
printf 'scheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=de\n' > "$TMPD/locale.conf"

# the guest script of the main run: ticks every ~3 s
{
  echo "apprights load"
  echo "apprights burn spin spinner &"
  echo "sleep 2"
  echo "settings debug page=18 &"
  for i in $(seq 1 60); do
      echo "echo ==T$i=="; echo "cat /etc/apprights.conf"; echo "apprights list"; echo "ls /apps"; echo "sleep 3"
  done
  echo "echo ==G-CEIL=="
  echo "apprights set alpha camera"
  echo "cat /etc/apprights.conf"
  echo "echo ==FERTIG=="
} > "$TMPD/g.sh"
# the guest script of the short-window run: only the sidebar
{ echo "settings debug page=0 &"; for i in $(seq 1 12); do echo "echo ==S$i=="; echo "sleep 3"; done; echo "echo ==FERTIG=="; } > "$TMPD/g2.sh"

mkimg() { # out.img script
  local A=(build "$1" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
     /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /var/ /var/log/ /etc/ /apps/ /data/
     "/etc/sperre.conf=$TMPD/sperre.conf" "/etc/theme.conf=$TMPD/theme.conf" "/etc/passwd=$TMPD/passwd"
     "/etc/apprights.seen=$TMPD/bd/seen" /system/generations/ /system/generations/1/
     "/system/AKTUELL=$TMPD/bd/AKTUELL" "/system/generations/1/PLAN=$TMPD/bd/PLAN" /store/
     "/etc/locale.conf=$TMPD/locale.conf" "/etc/uitrace=$TMPD/locale.conf"
     /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/
     "/usr/share/locale/de/messages=locale/de/messages" "/usr/share/locale/en/messages=locale/en/messages"
     "/t/g.sh=$2")
  [ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
  [ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
  A+=(/etc/schemas/)
  for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
  for a in alpha spinner gone; do A+=("/apps/$a.osp/" "/apps/$a.osp/INFO=$TMPD/bd/$a.info"); done
  A+=("/store/${HA:0:20}/" "/store/${HA:0:20}/INFO=$TMPD/bd/alpha.info" "/store/${HS:0:20}/" "/store/${HS:0:20}/INFO=$TMPD/bd/spinner.info"
      "/store/${HG:0:20}/" "/store/${HG:0:20}/INFO=$TMPD/bd/gone.info")
  for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
  python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1
}
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
boot() { # img serial sock res
  local X=${4%x*} Y=${4#*x}
  timeout 500 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx fbres=$4 disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$2" -display none -no-reboot \
    -device "VGA,edid=on,xres=$X,yres=$Y,vgamem_mb=32" \
    -monitor "unix:$3,server,nowait" \
    -drive "file=$1,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
  QPID=$!
}
clean() { tr -cd '\11\12\15\40-\176' < "$1"; }
SER="$TMPD/ser.txt"
waitfor() { # marker secs
  local i=0
  while [ $i -lt $(( $2 * 5 )) ]; do
    clean "$SER" 2>/dev/null | grep -qaF -- "$1" && return 0
    kill -0 "$QPID" 2>/dev/null || return 1
    sleep 0.2; i=$((i + 1))
  done
  return 1
}
SOCK="$TMPD/mon.sock"
klick() { python3 tools/themestore/click.py "$1,$2" > "$TMPD/k.txt" 2>/dev/null; python3 tools/wm/monitor.py "$SOCK" "$TMPD/k.txt" > /dev/null 2>&1; sleep 1.5; }
rect() { clean "$SER" | grep -a "settings: rect name=$1 " | tail -1 | sed -E 's/.* w=([0-9]+) h=([0-9]+) ax=([0-9]+) ay=([0-9]+).*/\3 \4 \1 \2/'; }
mid() { local r; r=$(rect "$1"); [ -z "$r" ] && return 1; set -- $r; echo "$(( $1 + $3 / 2 )) $(( $2 + $4 / 2 ))"; }
click_on() { local m; m=$(mid "$1") || return 1; klick $m; }
ticks() { clean "$SER" | grep -ac '^==T[0-9]*=='; }
# wait until two further ticks have printed (the first may have started before the click)
after_click() { local n; n=$(ticks); local i=0; while [ $i -lt 120 ]; do [ "$(ticks)" -ge $((n + 2)) ] && return 0; kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.5; i=$((i+1)); done; return 1; }
last_tick() { clean "$SER" | awk '/^==T[0-9]+==/{b=""} {b=b $0 "\n"} END{printf "%s", b}' ; }
# the text between the last two tick markers (a complete tick)
full_tick() { clean "$SER" | awk '/^==T[0-9]+==/{ if (cur != "") prev=cur; cur="" } {cur=cur $0 "\n"} END{printf "%s", prev}'; }
conf_line() { full_tick | grep -a "^$1 " | head -1; }
shot() { python3 tools/gfx/screenshot.py "$SOCK" "$1" 5 > /dev/null 2>&1; }

echo "== 2. image + boot 1280x800 =="
mkimg "$TMPD/d.img" "$TMPD/g.sh" && ok "disk image" || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; echo "APPINFO: $pass passed, $fail failed"; exit 1; }
rm -f "$SOCK" "$SER"; boot "$TMPD/d.img" "$SER" "$SOCK" 1280x800
if waitfor "settings: apps list n=" 180; then ok "Settings opened on the page Apps"; else
  bad "Settings did not report the page Apps"; clean "$SER" | tail -15 | sed 's/^/        /'; kill "$QPID" 2>/dev/null
  echo "APPINFO: $pass passed, $fail failed"; exit 1; fi
sleep 4
S=$(clean "$SER")
echo "$S" | grep -aE 'settings: apps (list|row)' | sed 's/^/        /' | head -6
n=$(echo "$S" | grep -ac 'settings: apps row ')
[ "$n" -ge 3 ] && ok "list shows 3 apps ($n rows)" || bad "list rows ($n)"
echo "$S" | grep -aq 'apps row alpha mask=0 ceil=21' && ok "alpha: mask 0, ceiling 21 (net+notify+mic) from the table" || bad "alpha row"
echo "$S" | grep -aq 'apps row spinner mask=0 ceil=16' && ok "spinner: ceiling 16 (notify)" || bad "spinner row"
echo "$S" | grep -aq 'apps row gone mask=0 ceil=4' && ok "gone: ceiling 4 (net)" || bad "gone row"
# which letter is which: rows come in table order
idx_of() { clean "$SER" | grep -a 'settings: apps row ' | awk -v n="$1" '!seen[$4]++ {i++; if ($4==n) {print i-1; exit}}'; }
letter_of() { printf "\\x$(printf %x $((97 + $1)))"; }
IA=$(idx_of alpha); IS=$(idx_of spinner); IG=$(idx_of gone)
echo "        rows: alpha=$IA spinner=$IS gone=$IG"
shot "$TMPD/1-list.ppm"
# --- sidebar: 19 tab rects, the last one inside the screen (1280x800)
nt=$(echo "$S" | grep -ac 'settings: rect name=tab[a-s] ')
[ "$nt" -ge 19 ] && ok "19 sidebar entries reported" || bad "sidebar entries ($nt)"
r=$(rect tabs); if [ -n "$r" ]; then set -- $r; bottom=$(( $2 + $4 )); [ "$bottom" -le 800 ] && ok "1280x800: last sidebar entry ends at y=$bottom <= 800" || bad "1280x800: last sidebar entry ends at y=$bottom (> 800)"; else bad "tab s rect"; fi

echo "== 3. alpha: detail and switches =="
[ "$(conf_line alpha)" = "" ] && ok "GEGENPROBE: before any click the conf has no alpha line" || bad "alpha line before the click: $(conf_line alpha)"
L=$(letter_of "$IA")
click_on "apl$L" && sleep 2 || bad "row button apl$L not reported"
waitfor "settings: apps detail alpha mask=0 ceil=21" 20 && ok "detail of alpha opened" || bad "detail of alpha"
for t in apra aprc apre; do [ -n "$(rect $t)" ] && ok "switch $t (declared) is there" || bad "switch $t missing"; done
for t in aprb aprd aprf aprh; do [ -z "$(rect $t)" ] && ok "no switch $t (not declared: camera/fs.home/clipboard/location)" || bad "switch $t exists but is above the ceiling"; done
for t in apsp apun apcl apen appa apbk; do [ -n "$(rect $t)" ] && ok "control $t reported" || bad "control $t missing"; done
shot "$TMPD/2-detail.ppm"
click_on aprc
waitfor "apps set alpha mask=4 rc=0" 20 && ok "net switch: kernel table mask=4, rc=0" || bad "net switch"
after_click
cl=$(conf_line alpha); [ "$cl" = "alpha net" ] && ok "conf now has 'alpha net'" || bad "conf after net: '$cl'"
click_on apre; waitfor "apps set alpha mask=20 rc=0" 20 && ok "notify switch: mask=20" || bad "notify switch"
after_click
cl=$(conf_line alpha); echo "$cl" | grep -aq 'net' && echo "$cl" | grep -aq 'notify' && ok "conf has net and notify ('$cl')" || bad "conf after notify: '$cl'"
click_on aprc; waitfor "apps set alpha mask=16 rc=0" 20 && ok "net switched off again: mask=16" || bad "net off"
after_click
cl=$(conf_line alpha); [ "$cl" = "alpha notify" ] && ok "conf back to 'alpha notify'" || bad "conf after net off: '$cl'"
shot "$TMPD/3-switched.ppm"

echo "== 4. inert controls =="
before=$(clean "$SER" | grep -ac 'settings: apps \(set\|stop\|uninstall\) ')
click_on apcl; click_on apen; click_on appa
after=$(clean "$SER" | grep -ac 'settings: apps \(set\|stop\|uninstall\) ')
[ "$before" = "$after" ] && ok "Clear data / Energy mode / Pause: greyed out, no action ran" || bad "a greyed-out control acted ($before -> $after)"

echo "== 5. force stop =="
click_on apbk; sleep 1
L=$(letter_of "$IS"); click_on "apl$L"; waitfor "settings: apps detail spinner" 20 && ok "detail of spinner" || bad "detail of spinner"
click_on apsp; waitfor "settings: apps stop spinner rc=0 killed=" 20
clean "$SER" | grep -aq 'apps stop spinner rc=0 killed=1' && ok "force stop killed the live app:spinner task (killed=1)" || bad "force stop: $(clean "$SER" | grep -a 'apps stop spinner' | head -1)"
click_on apsp; sleep 2
clean "$SER" | grep -a 'apps stop spinner' | tail -1 | grep -aq 'killed=0' && ok "second force stop: killed=0 (nothing left)" || bad "second force stop"

echo "== 6. uninstall =="
click_on apbk; sleep 1
L=$(letter_of "$IG"); click_on "apl$L"; waitfor "settings: apps detail gone" 20 && ok "detail of gone" || bad "detail of gone"
click_on apun; sleep 2
clean "$SER" | grep -aq 'settings: apps uninstall' && bad "uninstall ran on the FIRST click" || ok "GEGENPROBE: the first click only arms (no uninstall line)"
clean "$SER" | grep -aq 'apps detail gone .* arm=1' && ok "armed (arm=1)" || bad "arm state"
click_on apun; waitfor "settings: apps uninstall gone rc=" 30
clean "$SER" | grep -aq 'settings: apps uninstall gone rc=0' && ok "second click: opk remove gone, rc=0" || bad "uninstall: $(clean "$SER" | grep -a 'apps uninstall' | head -1)"
sleep 3
last=$(clean "$SER" | grep -a 'settings: apps list n=' | tail -1)
echo "        $last"
echo "$last" | grep -aq 'n=2' && ok "list is back with 2 apps" || bad "list after uninstall: $last"
sleep 4
ft=$(full_tick)
{ echo "$ft" | grep -aq 'spinner.osp' && ! echo "$ft" | grep -aq 'gone.osp'; } && ok "/apps/gone.osp is gone from the disk, the others stay" || bad "ls /apps after uninstall: $(echo "$ft" | grep -a 'osp' | head -1)"

echo "== 7. ceiling from the shell =="
waitfor "==FERTIG==" 400 || true
clean "$SER" | awk '/==G-CEIL==/{f=1;next} /==FERTIG==/{f=0} f' > "$TMPD/ceil.txt"
grep -aqi 'ceiling' "$TMPD/ceil.txt" && ok "GEGENPROBE: 'apprights set alpha camera' refused (above the manifest ceiling)" || bad "ceiling refusal: $(head -3 "$TMPD/ceil.txt")"
grep -aq '^alpha notify' "$TMPD/ceil.txt" && ok "conf unchanged after the refusal" || bad "conf after refusal: $(cat "$TMPD/ceil.txt" | head -3)"
c=$(clean "$SER" | grep -acE 'ABSTURZ|EXCEPTION|PANIC'); [ "$c" = 0 ] && ok "no crash lines" || bad "crash lines: $c"
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null

echo "== 8. short window 1024x576 =="
mkimg "$TMPD/d2.img" "$TMPD/g2.sh" && ok "disk image 2" || bad "mkfs 2"
rm -f "$SOCK" "$SER"; boot "$TMPD/d2.img" "$SER" "$SOCK" 1024x576
if waitfor "settings: rect name=tabs " 150; then
  sleep 3
  r=$(rect tabs); set -- $r; bottom=$(( $2 + $4 ))
  [ "$bottom" -le 576 ] && ok "1024x576: last sidebar entry ends at y=$bottom <= 576" || bad "1024x576: last sidebar entry ends at y=$bottom (> 576)"
  r=$(rect taba); set -- $r; [ -n "$r" ] && [ "$4" -ge 17 ] && ok "entries stay readable (height $4 >= 17)" || bad "entry height '$4'"
else bad "settings did not come up at 1024x576"; fi
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
echo "APPINFO: $pass passed, $fail failed"
[ "$fail" = 0 ]
