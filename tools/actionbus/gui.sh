#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/actionbus/gui.sh -- ROUND ACTION-BUS-3 ON A SCREEN.
#
#   bash tools/actionbus/gui.sh [workdir]
#
# tools/actionbus/run.sh measures the bus without a screen. What needs
# one is measured here, in a real Osum guest with the window server:
#
#   1. AB-008b, the foreign-window layer: a LINUX WAYLAND PROGRAM
#      (tools/actionbus/wlkeys.c, libwayland-client, unchanged by us for
#      the bus) runs on wayd; a wrapper manifest makes actions of its
#      WINDOW -- keys, typed text, a click, the close box. What the
#      program itself received is its own log, not ours.
#      GEGENPROBEN: a wrapper that names the SETTINGS window is refused by
#      the kernel (not a foreign program); an agent's key press needs the
#      dry run first and then a human yes; a window that is not open is
#      an honest error.
#   2. AB-005b / AB-006: the settings window as a client of the bus --
#      the page "System" lists all 14 settings through settings.list, a
#      harmless value is set by clicking (display.brightness reaches the
#      KERNEL, DG_BRIGHT), a critical one asks and is done only after
#      "Yes, change it"; the lock time is read through the bus; the page
#      "App rights" lists rules, the dry-run-first client and the
#      counts, and "Allow Jarvis the display for 1 hour" adds a timed
#      grant. Photos of both pages.
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
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD/bin"
WLB=${WLBUILD:-/root/wl-build}
PROGS="sh ls cat echo sleep orientbus act settingsd settings wayd"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'
    echo "ACTBUS-GUI: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "ACTBUS-GUI: $pass passed, $fail failed"; exit 1
fi
if [ -f "$WLB/musl-root/lib/libwayland-client.a" ] && musl-gcc -static -O2 -nostartfiles \
        -T tools/foreign/osum.ld -Wl,--build-id=none -D_GNU_SOURCE \
        -I"$WLB/musl-root/include" -o "$TMPD/wlkeys" \
        tools/foreign/start.s tools/foreign/osum_main.c tools/actionbus/wlkeys.c \
        "$WLB/wayland-1.21.0/gen/xdg-shell-protocol.c" \
        -L"$WLB/musl-root/lib" -lwayland-client -lffi 2>"$TMPD/wl.txt"; then
    ok "wlkeys: a Wayland program, libwayland-client + xdg-shell, static musl"
else
    bad "wlkeys does not build (needs $WLB, docs/RUNDE-WAYLAND.md 9)"
    grep -v 'GNU-stack\|deprecated' "$TMPD/wl.txt" | head -5 | sed 's/^/        /'
    echo "ACTBUS-GUI: $pass passed, $fail failed"; exit 1
fi

# the wrapper manifest for the Wayland program -- written like one the
# community would ship: it names the WINDOW, and what the keys mean
cat > "$TMPD/viewer.actions" <<'EOF'
manifest 1
app viewer
title "Fake Viewer (a Linux Wayland program)"
for window "Fake Viewer*"
action viewer.next write "Next picture (the space key in its window)"
  adapter keys space
action viewer.search write "Search: Ctrl+F, the text, Enter"
  arg text string required "What to search for"
  adapter keys ctrl+f {text} enter
action viewer.play write "The play button (a click at 40,30 in its window)"
  adapter ui click 40 30
action viewer.close write "Close the window (its close box)"
  adapter ui close
EOF
# GEGENPROBE: a wrapper that tries to steer the SETTINGS window
cat > "$TMPD/trap.actions" <<'EOF'
manifest 1
app trap
title "A wrapper that names the settings window"
for window "Einstellungen*"
action trap.click write "Click into the settings window"
  adapter ui click 300 300
action trap.type write "Type into the settings window"
  adapter keys y enter
EOF
cat > "$TMPD/ghost.actions" <<'EOF'
manifest 1
app ghost
for window "No Such Window*"
action ghost.poke write "A window that is not open"
  adapter keys space
EOF
python3 tools/actionbus/manifest.py check --wrapper "$TMPD/viewer.actions" > "$TMPD/lint.txt" 2>&1 \
    && ok "host reader takes the window wrapper ($(head -1 "$TMPD/lint.txt" | cut -d' ' -f3-))" \
    || bad "host reader refuses the window wrapper: $(cat "$TMPD/lint.txt")"
printf '# /etc/sperre.conf -- gui test\nleerlauf=300\n' > "$TMPD/sperre.conf"
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=de\n' > "$TMPD/locale.conf"
printf 'modus=fest\nip=10.0.2.15\nmaske=255.255.255.0\ngateway=10.0.2.2\n' > "$TMPD/network.conf"

cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
settingsd serve 0 &
sleep 1
wayd /tmp/wayland-0 2000000000 &
sleep 1
wlkeys /tmp/wayland-0 300 &
sleep 4
echo ==G-LIST==
act list
echo ==G-DRY==
act call viewer.next --dry
echo ==G-NEXT==
act call viewer.next
echo ==G-SEARCH==
act call viewer.search text=moon
echo ==G-CLICK==
act call viewer.play
echo ==G-AGENT==
act call viewer.next --as jarvis
act call viewer.next --dry --as jarvis
act call viewer.next --as jarvis
act confirm last
echo ==G-GHOST==
act call ghost.poke
echo ==G-SETWIN==
settings debug page=11 &
sleep 6
act call trap.click
act call trap.type
echo ==G-WAIT==
sleep 60
echo ==G-RIGHTS==
sleep 30
echo ==G-SCREEN==
sleep 25
echo ==G-NET==
sleep 35
echo ==G-NETDONE==
cat /etc/network.conf
echo ==G-CLOSE==
act call viewer.close
sleep 3
echo ==G-LOG==
cat /tmp/wlkeys.log
echo ==G-JOURNAL==
cat /var/log/settings.journal
echo ==G-STAT==
act stat
act rights
act stop
echo ==FERTIG==
EOS

A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/ /apps/
   "/etc/settings.schema=etc/settings.schema"
   "/etc/actions.d/settings.actions=etc/actions.d/settings.actions"
   "/etc/actions.d/viewer.actions=$TMPD/viewer.actions"
   "/etc/actions.d/trap.actions=$TMPD/trap.actions"
   "/etc/actions.d/ghost.actions=$TMPD/ghost.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/etc/sperre.conf=$TMPD/sperre.conf" "/etc/theme.conf=$TMPD/theme.conf"
   "/etc/passwd=$TMPD/passwd" "/etc/locale.conf=$TMPD/locale.conf"
   "/etc/network.conf=$TMPD/network.conf"
   "/etc/uitrace=$TMPD/locale.conf"
   /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/
   "/usr/share/locale/de/messages=locale/de/messages"
   "/usr/share/locale/en/messages=locale/en/messages"
   "/bin/wlkeys=$TMPD/wlkeys" "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
A+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "ACTBUS-GUI: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot: window server, bus, wayd, a Linux Wayland program =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 400 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
waitfor() { # marker seconds
    local i=0
    while [ $i -lt $(( $2 * 5 )) ]; do
        grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
shot() { python3 tools/gfx/screenshot.py "$SOCK" "$1" 5 > /dev/null 2>&1; }
klick() { # x y
    python3 tools/themestore/click.py "$1,$2" > "$TMPD/k.txt" 2>/dev/null
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/k.txt" > /dev/null 2>&1
    sleep 1.5
}
tippe() { # text (lower-case letters, digits)
    local t=$1 i c
    : > "$TMPD/t.txt"
    for ((i = 0; i < ${#t}; i++)); do c=${t:i:1}; echo "sendkey $c" >> "$TMPD/t.txt"; done
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/t.txt" 0.15 > /dev/null 2>&1
    sleep 1
}
# the rectangle `name` from the settings window: "ax ay w h"
rect() {
    tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | grep -a "settings: rect name=$1 " | tail -1 \
      | sed -E 's/.* w=([0-9]+) h=([0-9]+) ax=([0-9]+) ay=([0-9]+).*/\3 \4 \1 \2/'
}
mid() { # name -> "x y" (the middle)
    local r; r=$(rect "$1"); [ -z "$r" ] && return 1
    set -- $r; echo "$(( $1 + $3 / 2 )) $(( $2 + $4 / 2 ))"
}

if waitfor "==G-WAIT==" 120; then
    ok "the script reached the settings part"
    sleep 4
    shot "$TMPD/1-system.ppm"
    # --- the page System: set display.brightness (row 0, selected) to 30
    if E=$(mid sent) && S=$(mid sset); then
        klick $E; tippe 30; klick $S
        sleep 2
        # --- a critical one: net.wifi.enabled is row 7 (display 3, sound 2,
        # lock 1, locale 1); the row height comes from the table itself
        read tx ty tw th <<< "$(rect stab)"
        rh=$(tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | grep -ao 'settings: rowh=[0-9]*' | tail -1 | tr -dc '0-9')
        rh=${rh:-20}
        # the head is one row + 4, then row 7, in its middle
        klick $(( tx + 40 )) $(( ty + rh + 4 + 7 * rh + rh / 2 ))
        klick $E
        for i in 1 2 3 4 5 6; do echo "sendkey backspace" ; done > "$TMPD/bs.txt"
        python3 tools/wm/monitor.py "$SOCK" "$TMPD/bs.txt" 0.1 > /dev/null 2>&1
        tippe false; klick $S
        sleep 2
        shot "$TMPD/2-ask.ppm"
        klick $(mid sconf)
        sleep 2
        shot "$TMPD/3-done.ppm"
    else
        bad "the System page did not report its controls"
    fi
else
    bad "the script did not reach the settings part"
fi
# ONE window from here on: the pages are switched by clicking their tab
# (the window reports every tab as "taba", "tabb", ...), like a person
if waitfor "==G-RIGHTS==" 120; then
    sleep 1
    T=$(mid tabm) && klick $T || bad "the settings window did not report its tabs"
    sleep 4
    shot "$TMPD/4-rights.ppm"
    J=$(mid rjar) && { klick $J; sleep 2; shot "$TMPD/5-granted.ppm"; } || bad "the rights page did not report its controls"
fi
# AB-005c: the page Bildschirm sets the brightness through the bus, the
# page Netz switches to DHCP through the bus -- critical, so it asks, and
# "Ja, ändern" on that page answers
if waitfor "==G-SCREEN==" 60; then
    T=$(mid tabb) && klick $T
    sleep 5
    shot "$TMPD/5b-screen.ppm"
    # the brightness as it stands; "Übernehmen" sends it
    if A2=$(mid dapply); then
        klick $A2; sleep 2
    else
        bad "the page Bildschirm did not report its controls"
    fi
fi
if waitfor "==G-NET==" 60; then
    T=$(mid tabd) && klick $T
    sleep 5
    if M=$(mid nmode) && N=$(mid napply) && C=$(mid nconf); then
        # the choice opens its list below itself; item 0 is "über DHCP"
        read mx my mw mh <<< "$(rect nmode)"
        klick $M; klick $(( mx + 40 )) $(( my + mh + 12 )); sleep 1
        klick $N; sleep 2
        shot "$TMPD/6-netask.ppm"
        klick $C; sleep 2
        shot "$TMPD/7-netdone.ppm"
    else
        bad "the page Netz did not report its controls"
    fi
fi
waitfor "==FERTIG==" 150 || note "no FERTIG before the time limit"
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"
G="$TMPD/ser.klar"
for q in "$TMPD"/*.ppm; do
    [ -s "$q" ] && python3 -c "from PIL import Image; Image.open('$q').save('${q%.ppm}.png')" 2>/dev/null
done

echo "== 3. the foreign-window layer (AB-008b) =="
has "$G" "wlkeys: window up 200x120" "the Linux Wayland program opened its window on wayd"
has "$G" "wlkeys: seat caps=3" "... and got keyboard and pointer from the seat"
part "$G" G-LIST G-DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "viewer.next write" "the wrapper's actions are in the catalogue"
part "$G" G-DRY G-NEXT > "$TMPD/p.txt"
has "$TMPD/p.txt" "would=keys space -> window" "a dry run names the key and the window it would go to"
has "$TMPD/p.txt" "[Fake Viewer]" "... the window found by its title"
part "$G" G-NEXT G-SEARCH > "$TMPD/p.txt"
has "$TMPD/p.txt" "sent=1" "viewer.next: one key sent into the window"
part "$G" G-SEARCH G-CLICK > "$TMPD/p.txt"
has "$TMPD/p.txt" "sent=6" "viewer.search: ctrl+f, the 4 letters of the argument, enter"
part "$G" G-CLICK G-AGENT > "$TMPD/p.txt"
has "$TMPD/p.txt" "adapter=ui" "viewer.play: a click through the ui adapter"
part "$G" G-AGENT G-GHOST > "$TMPD/p.txt"
has "$TMPD/p.txt" "err dry_run_first viewer.next" "Jarvis' key press without a dry run is refused (shipped policy: dryfirst jarvis)"
has "$TMPD/p.txt" "confirm " "... after the dry run it is parked for the human"
part "$G" G-GHOST G-SETWIN > "$TMPD/p.txt"
has "$TMPD/p.txt" "err window_not_found ghost" "a window that is not open: an honest error"
part "$G" G-SETWIN G-WAIT > "$TMPD/p.txt"
n=$(grep -ac 'err adapter_failed window' "$TMPD/p.txt")
[ "$n" -ge 2 ] && ok "GEGENPROBE: a wrapper naming the SETTINGS window is refused -- click and keys ($n refusals)" \
    || bad "the settings window could be steered ($n refusals)"
part "$G" G-LOG G-JOURNAL > "$TMPD/log.txt"
grep -qaE '^wlkeys: key=57 state=1' "$TMPD/log.txt" && ok "the PROGRAM received space (evdev 57) -- its own log" || bad "no space in the program's log"
grep -qaE '^wlkeys: key=29 state=1' "$TMPD/log.txt" && grep -qaE '^wlkeys: key=33 state=1' "$TMPD/log.txt" \
    && ok "... Ctrl (29) + F (33)" || bad "no ctrl+f in the program's log"
# m o o n = 50 24 24 49, then enter 28
python3 - "$TMPD/log.txt" <<'PY' && ok "... 'moon' as m,o,o,n and then Enter, in that order" || bad "the typed text is not m o o n enter in order"
import re, sys
keys = [int(m.group(1)) for m in re.finditer(r'^wlkeys: key=(\d+) state=1', open(sys.argv[1]).read(), re.M)]
want = [50, 24, 24, 49, 28]
s = ",".join(map(str, keys)); w = ",".join(map(str, want))
sys.exit(0 if w in s else 1)
PY
grep -qaE '^wlkeys: button=272 state=1 x=40 y=30' "$TMPD/log.txt" && ok "the click arrived as BTN_LEFT at 40,30 in the program" || bad "no click at 40,30 in the program's log"
n57=$(grep -ac '^wlkeys: key=57 state=1' "$TMPD/log.txt")
[ "$n57" = 2 ] && ok "space arrived exactly twice (user + Jarvis after the yes), nothing extra" || bad "space arrived $n57 times (want 2)"
has "$TMPD/log.txt" "wlkeys: close" "viewer.close: the program got xdg_toplevel.close and ended itself"
grep -qaE 'panic|EXCEPTION|#PF|#GP' "$G" && bad "a panic or exception" || ok "no panic, no exception"

echo "== 4. the settings window on the bus (AB-005b, AB-006) =="
has "$G" "settings: lock via bus value=300" "the lock time is read through the bus (lock.idle)"
grep -qaE 'settings: bus page=system rows=14' "$G" && ok "page System: 14 settings through settings.list" || bad "page System: $(grep -a 'settings: bus page=system' "$G" | tail -1)"
has "$G" "settingsd: display brightness k=60 rc=0" "Set 30 on display.brightness reaches the KERNEL (DG_BRIGHT 60)"
grep -qa 'settings: bus answer rc=2 line=\[confirm' "$G" && ok "a critical setting (net.wifi.enabled) is asked, even from the window" || bad "no confirmation asked for the critical setting"
grep -qa 'settings: bus answer rc=0 line=\[ok\]' "$G" && ok "after 'Yes, change it' it is done" || bad "the yes did not go through"
part "$G" G-JOURNAL G-STAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=user key=display.brightness" "the journal: the window changed display.brightness as the user"
has "$TMPD/p.txt" "key=net.wifi.enabled old=true new=false" "... and net.wifi.enabled, after the yes"
grep -qaE 'settings: rights rules=[0-9]+ clients=[1-9][0-9]* dryfirst=1 rc=0' "$G" \
    && ok "page App rights: $(grep -aoE 'settings: rights rules=[0-9]+ clients=[0-9]+ dryfirst=1' "$G" | tail -1)" \
    || bad "page App rights: $(grep -a 'settings: rights rules' "$G" | tail -1)"
grep -qa 'settings: rights answer rc=0 line=\[ok\]' "$G" && ok "'Allow Jarvis the display for 1 hour' -- the grant is given" || bad "the Jarvis button did nothing"
part "$G" G-STAT FERTIG > "$TMPD/p.txt"
grep -qaE 'rule [0-9]+ allow jarvis settings.display.\* write left=3[0-9]{3}' "$TMPD/p.txt" \
    && ok "... it is a timed rule with about an hour left" || bad "no timed Jarvis rule in 'act rights'"
echo "== 5. the other pages through the bus (AB-005c) =="
grep -qa 'settings: page set key=display.brightness' "$G" && ok "page Bildschirm: 'Übernehmen' sends display.brightness over the bus" || bad "the page Bildschirm did not use the bus"
n_k=$(grep -ac 'settingsd: display brightness k=' "$G")
[ "$n_k" -ge 2 ] && ok "... and settingsd set the kernel ($(grep -a 'settingsd: display brightness k=' "$G" | tail -1 | cut -c1-60))" || bad "settingsd did not set the brightness from the page ($n_k)"
grep -qa 'settings: page set key=net.dhcp' "$G" && ok "page Netz: DHCP goes over the bus (net.dhcp)" || bad "the page Netz did not use the bus"
n_ask=$(grep -ac 'settings: bus answer rc=2 line=\[confirm' "$G")
[ "$n_ask" -ge 2 ] && ok "... net.dhcp is critical: the page Netz asks as well" || bad "the page Netz was not asked ($n_ask questions)"
has "$G" "settingsd: dhcp started pid=" "after 'Ja, ändern' on the page Netz settingsd starts DHCP"
part "$G" G-NETDONE G-CLOSE > "$TMPD/p.txt"
has "$TMPD/p.txt" "modus=dhcp" "/etc/network.conf says modus=dhcp"
has "$TMPD/p.txt" "ip=10.0.2.15" "... and keeps the other lines"
part "$G" G-JOURNAL G-STAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "key=net.dhcp old=false new=true" "the journal has the DHCP change (so it can be undone)"
for f in 1-system 2-ask 3-done 4-rights 5-granted 5b-screen 6-netask 7-netdone; do
    [ -s "$TMPD/$f.png" ] && ok "photo: $TMPD/$f.png" || bad "no photo $f"
done
echo "ACTBUS-GUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
