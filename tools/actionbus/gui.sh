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
#      the yes in the system's own dialog (SETBROKER2: the window has no
#      yes button; a bus `confirm` of such a request is refused,
#      err use_dialog; NODLG=1 builds the broker without that duty and
#      the gate must turn red); the lock time is read through the bus; the page
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
if [ "${NODLG:-0}" = 1 ]; then
    # GEGENPROBE (r1312): the broker built WITHOUT the dialog duty -- the gate must turn red
    cp -r kernel/user "$TMPD/usrc"
    sed -i 's/if yes \&\& tk_dlg\[(t) as usize\] != 0 \&\& tr_screen {/if false {/' "$TMPD/usrc/orientbus.fi"
    if [ "$(grep -c 'if false {' "$TMPD/usrc/orientbus.fi")" -ge 1 ] \
        && USRC="$TMPD/usrc" bash tools/sync/build.sh "$TMPD/bin" 0 orientbus > "$TMPD/b2.txt" 2>&1; then
        ok "GEGENPROBE NODLG: orientbus built without the dialog duty"
    else
        bad "NODLG: the broker without the duty does not build"
    fi
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
cat > "$TMPD/big.actions" <<'EOF'
manifest 1
app big
for window "No Such Window*"
action big.go write "A long description of an action that has six long arguments, so that the trusted dialog has to cut its text on purpose"
  arg a string required "first"
  arg b string required "second"
  arg c string required "third"
  arg d string required "fourth"
  arg e string required "fifth"
  arg f string required "sixth"
  adapter keys space
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
echo ==G-BIG==
# six long arguments and a long description: the dialog text must stay inside its six lines (r1313)
act call big.go a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb c=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc d=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd e=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee f=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff --as helper
sleep 2
act confirm last
echo ==G-SETWIN==
settings debug page=11 &
sleep 6
act call trap.click
act call trap.type
echo ==G-WAIT==
# the host walks through the settings pages by STATES (gui.sh); this is only the upper bound
sleep 100
sleep 100
echo ==G-NETDONE==
cat /etc/network.conf
echo ==G-USEDLG==
sleep 3
# SETBROKER2: a critical request of the person's own can be answered in the system dialog only; the bus
# `confirm` of a program of theirs (this shell) is refused. The dialog is taken away again with `reject`.
act call settings.set key=net.wifi.enabled value=true
act confirm last
act reject last
sleep 2
echo ==G-TRUST==
act call settings.set key=lock.idle value=600 --as helper
# 16 s and not 8: the 'n' comes from the host (after its waits and a photo);
# on a loaded host it must still arrive before the question is asked again
sleep 16
act call settings.get key=lock.idle
echo ==G-TRUST2==
act call settings.set key=lock.idle value=600 --as helper
sleep 2
act call viewer.search text=jjj
sleep 2
act stat
echo ==G-TRUST3==
sleep 8
act call settings.get key=lock.idle
echo ==G-TRUSTEND==
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
   "/etc/actions.d/big.actions=$TMPD/big.actions"
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
timeout 700 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
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

# SETBROKER2 (r1280): a CRITICAL change from the settings window is answered in the system's trusted dialog
# (real keyboard) -- the window has no "Yes, change it" any more (r1313); a bus `confirm` of such a request is
# refused (err use_dialog, tested by the guest script: G-USEDLG).
#
# r1312: the host side waits for STATES (serial lines of the window, the dialog count, a rectangle that
# exists), never for a fixed time; the guest script only keeps a long fixed sleep for the whole choreography.
dlg_n() { grep -ac 'wm: trusted dialog up no=' "$TMPD/ser.txt"; }
ser_n() { grep -ac -- "$1" "$TMPD/ser.txt"; }
await_n() { # pattern count seconds -- at least `count` lines with the pattern
    local i=0
    while [ $i -lt $(( $3 * 5 )) ]; do
        [ "$(ser_n "$1")" -ge "$2" ] && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
await_mid() { # name seconds -> "x y" of the middle, once the window reports the rectangle
    local i=0 m
    while [ $i -lt $(( $2 * 2 )) ]; do
        m=$(mid "$1") && [ -n "$m" ] && { echo "$m"; return 0; }
        sleep 0.5; i=$((i + 1))
    done
    return 1
}
await_dlg() { # $1 = dialogs shown before; waits for the next one, 25 s
    local i=0
    while [ $i -lt 125 ]; do
        [ "$(dlg_n)" -gt "$1" ] && { sleep 1.5; return 0; }
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
say_yes() { # the real yes on the real keyboard
    echo "sendkey j" > "$TMPD/kjy.txt"
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/kjy.txt" > /dev/null 2>&1
}
# a critical request: wait for the dialog, photograph it, say yes, wait for the page to follow the answer
critical_yes() { # $1 = dialogs before, $2 = photo name, $3 = answers the window must have followed by then
    if await_dlg "$1"; then
        [ -n "$2" ] && shot "$TMPD/$2.ppm"
        say_yes
        await_n 'settings: dialog answered rc=1' "$3" 40 || bad "the window did not follow the dialog's answer ($3)"
    else
        bad "no system dialog came up for the critical request"
    fi
}

if waitfor "==G-WAIT==" 120; then
    ok "the script reached the settings part"
    sleep 4
    shot "$TMPD/1-system.ppm"
    # --- the page System: set display.brightness (row 0, selected) to 30
    if E=$(await_mid sent 30) && S=$(mid sset); then
        klick $E; tippe 30; klick $S
        await_n 'settingsd: display brightness k=60' 1 30 || bad "display.brightness 30 did not reach settingsd"
        # --- a critical one: net.wifi.enabled is row 8 (display 4, sound 2, lock 1, locale 1) and NOT in view
        # (the table shows 8 rows): select row 0 and walk down with the keyboard, like a person
        read tx ty tw th <<< "$(rect stab)"
        rh=$(tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | grep -ao 'settings: rowh=[0-9]*' | tail -1 | tr -dc '0-9')
        rh=${rh:-20}
        klick $(( tx + 40 )) $(( ty + rh + 4 + rh / 2 ))
        for i in 1 2 3 4 5 6 7 8; do echo "sendkey down"; done > "$TMPD/dn.txt"
        python3 tools/wm/monitor.py "$SOCK" "$TMPD/dn.txt" 0.15 > /dev/null 2>&1
        sleep 1
        klick $E
        for i in 1 2 3 4 5 6; do echo "sendkey backspace" ; done > "$TMPD/bs.txt"
        python3 tools/wm/monitor.py "$SOCK" "$TMPD/bs.txt" 0.1 > /dev/null 2>&1
        D0=$(dlg_n)
        tippe false; klick $S
        if await_n 'settings: set key=net.wifi.enabled value=false' 1 20; then
            ok "the keyboard walk selected net.wifi.enabled (row 8, out of view) and the value false went out"
            critical_yes "$D0" 2-ask 1
            shot "$TMPD/3-done.ppm"
        else
            bad "the settings window did not send net.wifi.enabled (got: $(grep -a 'settings: set key=' "$TMPD/ser.txt" | tail -1))"
        fi
    else
        bad "the System page did not report its controls"
    fi
    # ONE window from here on: the pages are switched by clicking their tab
    # (the window reports every tab as "taba", "tabb", ...), like a person
    if T=$(await_mid tabm 10); then
        klick $T
        shot "$TMPD/4-rights.ppm"
        if J=$(await_mid rjar 20); then
            klick $J
            await_n 'settings: rights answer rc=0' 1 20 || bad "the rights page did not answer"
            shot "$TMPD/5-granted.ppm"
        else
            bad "the rights page did not report its controls"
        fi
    else
        bad "the settings window did not report its tabs"
    fi
    # AB-005c: the page Bildschirm sets the brightness through the bus, the page Netz switches to DHCP
    # through the bus -- critical, so it asks and the SYSTEM dialog answers
    T=$(mid tabb) && klick $T
    if A2=$(await_mid dapply 20); then
        shot "$TMPD/5b-screen.ppm"
        B1=$(ser_n 'settings: page set key=display.brightness')
        klick $A2
        await_n 'settings: page set key=display.brightness' $((B1 + 1)) 20 || bad "the page Bildschirm did not send the brightness"
    else
        bad "the page Bildschirm did not report its controls"
    fi
    T=$(mid tabd) && klick $T
    if M=$(await_mid nmode 20) && N=$(await_mid napply 5); then
        # the choice opens its list below itself; item 0 is "über DHCP"
        read mx my mw mh <<< "$(rect nmode)"
        klick $M; klick $(( mx + 40 )) $(( my + mh + 12 )); sleep 1
        D1=$(dlg_n)
        klick $N
        critical_yes "$D1" 6-netask 2
        shot "$TMPD/7-netdone.ppm"
        await_n 'settingsd: dhcp started pid=' 1 30 || bad "settingsd did not start DHCP after the yes"
    else
        bad "the page Netz did not report its controls"
    fi
    # S-009: the page Protokoll -- the audit log of this very run, newest first
    T=$(mid tabn) && klick $T
    await_n 'settings: protocol rows=' 1 20 || bad "the page Protokoll did not read the log"
    shot "$TMPD/8-log.ppm"
    # DAILY-DRIVER: the page Updates (15th tab) -- state over settings.update.status, "Jetzt nach Updates
    # suchen" asks settingsd, which starts `ota` (no server in this run, so the check fails -- what is
    # measured is that the page asks the bus and that settingsd answers)
    T=$(mid tabo) && klick $T
    if S=$(await_mid schk 20); then
        shot "$TMPD/9-update.ppm"
        klick $S; sleep 3
        shot "$TMPD/9a-update.ppm"
        if U=$(await_mid ucheck 10); then
            klick $U; sleep 3
            shot "$TMPD/9b-update.ppm"
        else
            bad "the page Updates did not report its controls"
        fi
    else
        bad "the page Updates has no SYSTEM check button"
    fi
else
    bad "the script did not reach the settings part"
fi
# AB-004: the trusted dialog. Helper (an agent) asks to change the lock time; the window server shows the
# question over everything. "n" on the REAL keyboard rejects it; the second time a program types "jjj" into
# a window first (the dialog stays), then "j" on the real keyboard says yes. The dialogs are counted: the
# guest's use_dialog probe shows one (and takes it away), the helper's request is the next.
if waitfor "==G-USEDLG==" 300; then
    sleep 1
    UB=$(dlg_n)
    if waitfor "==G-TRUST==" 40 && await_dlg $(( UB + 1 )); then
        shot "$TMPD/9-trust.ppm"
        echo "sendkey n" > "$TMPD/kn.txt"
        python3 tools/wm/monitor.py "$SOCK" "$TMPD/kn.txt" > /dev/null 2>&1
    else
        bad "no trusted dialog came up for the helper's change"
    fi
else
    bad "the guest script did not reach the probe of the dialog duty"
fi
if waitfor "==G-TRUST3==" 60; then
    sleep 1
    shot "$TMPD/10-trust-still.ppm"
    echo "sendkey j" > "$TMPD/kj.txt"
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/kj.txt" > /dev/null 2>&1
    sleep 2
    shot "$TMPD/11-trust-done.ppm"
fi
waitfor "==FERTIG==" 200 || note "no FERTIG before the time limit"
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
grep -qaE 'keys: key=57 state=1' "$TMPD/log.txt" && ok "the PROGRAM received space (evdev 57) -- its own log" || bad "no space in the program's log"
grep -qaE 'keys: key=29 state=1' "$TMPD/log.txt" && grep -qaE 'keys: key=33 state=1' "$TMPD/log.txt" \
    && ok "... Ctrl (29) + F (33)" || bad "no ctrl+f in the program's log"
# m o o n = 50 24 24 49, then enter 28
python3 - "$TMPD/log.txt" <<'PY' && ok "... 'moon' as m,o,o,n and then Enter, in that order" || bad "the typed text is not m o o n enter in order"
import re, sys
keys = [int(m.group(1)) for m in re.finditer(r'keys: key=(\d+) state=1', open(sys.argv[1]).read(), re.M)]
want = [50, 24, 24, 49, 28]
s = ",".join(map(str, keys)); w = ",".join(map(str, want))
sys.exit(0 if w in s else 1)
PY
grep -qaE 'keys: button=272 state=1 x=40 y=30' "$TMPD/log.txt" && ok "the click arrived as BTN_LEFT at 40,30 in the program" || bad "no click at 40,30 in the program's log"
n57=$(grep -ac 'keys: key=57 state=1' "$TMPD/log.txt")
[ "$n57" = 2 ] && ok "space arrived exactly twice (user + Jarvis after the yes), nothing extra" || bad "space arrived $n57 times (want 2)"
has "$TMPD/log.txt" "wlkeys: close" "viewer.close: the program got xdg_toplevel.close and ended itself"
grep -qaE 'panic|EXCEPTION|#PF|#GP' "$G" && bad "a panic or exception" || ok "no panic, no exception"

echo "== 4. the settings window on the bus (AB-005b, AB-006) =="
has "$G" "settings: lock via bus value=300" "the lock time is read through the bus (lock.idle)"
grep -qaE 'settings: bus page=system rows=15' "$G" && ok "page System: 15 settings through settings.list" || bad "page System: $(grep -a 'settings: bus page=system' "$G" | tail -1)"
has "$G" "settingsd: display brightness k=60 rc=0" "Set 30 on display.brightness reaches the KERNEL (DG_BRIGHT 60)"
grep -qa 'settings: bus answer rc=2 line=\[confirm' "$G" && ok "a critical setting (net.wifi.enabled) is asked, even from the window" || bad "no confirmation asked for the critical setting"
grep -qa 'settings: bus answer rc=0 line=\[ok\]' "$G" && ok "after 'Yes, change it' it is done" || bad "the yes did not go through"
part "$G" G-JOURNAL G-STAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=user key=display.brightness" "the journal: the window changed display.brightness as the user"
has "$TMPD/p.txt" "key=net.wifi.enabled old=true new=false" "... and net.wifi.enabled, after the yes"
hasnot "$TMPD/p.txt" "key=net.wifi.enabled old=false new=true" "the refused bus confirm changed nothing (no wifi=true in the journal)"
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
has "$G" "settingsd: dhcp started pid=" "after the YES IN THE SYSTEM DIALOG settingsd starts DHCP"
# SETBROKER2 (r1312/r1313): the window has no "Yes, change it" any more; the bus confirm of a critical request
# of the person's own (a program of theirs: the guest shell) is refused, the dialog is the only yes
part "$G" G-USEDLG G-TRUST > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm " "the critical request of the person's own is parked (act call settings.set net.wifi.enabled)"
has "$TMPD/p.txt" "err use_dialog" "SETBROKER2: a bus confirm of it is refused (err use_dialog) -- only the system dialog can say yes"
n_dd=$(grep -ac 'settings: dialog answered rc=1' "$G")
[ "$n_dd" -ge 2 ] && ok "the window followed the dialog's answer and redid its page ($n_dd times: wifi on System, DHCP on Netz)" || bad "the window did not follow the dialog's answer ($n_dd)"
# the dialog text (r1313): six long arguments + a long description stay inside the dialog's six lines
part "$G" G-BIG G-SETWIN > "$TMPD/p.txt"
tl=$(grep -ao 'orientbus: dialog text len=[0-9]* cut=[01]' "$TMPD/p.txt" | tail -1)
[ -n "$tl" ] && ok "the long request got a dialog text: $tl" || bad "no dialog text line for the request with six long arguments"
n_cut=$(grep -ao 'orientbus: dialog text len=[0-9]* cut=1' "$G" | wc -l)
[ "$n_cut" = 0 ] && ok "no dialog text was cut at TR_BYTES (all lines cut=0)" || bad "$n_cut dialog texts were cut at TR_BYTES"
tn=$(echo "$tl" | sed -E 's/.*len=([0-9]+).*/\1/'); tn=${tn:-0}
[ "$tn" -ge 120 ] && [ "$tn" -le 366 ] && ok "... and it fits six lines of 60 columns ($tn octets)" || bad "the dialog text of the long request is $tn octets (want 120..366)"
part "$G" G-NETDONE G-CLOSE > "$TMPD/p.txt"
has "$TMPD/p.txt" "modus=dhcp" "/etc/network.conf says modus=dhcp"
has "$TMPD/p.txt" "ip=10.0.2.15" "... and keeps the other lines"
part "$G" G-JOURNAL G-STAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "key=net.dhcp old=false new=true" "the journal has the DHCP change (so it can be undone)"
grep -qaE 'settings: protocol rows=([5-9]|[1-9][0-9]+) rc=0' "$G" \
    && ok "page Protokoll (S-009): $(grep -aoE 'protocol rows=[0-9]+' "$G" | tail -1) from 'audit 40' over the bus" \
    || bad "page Protokoll: $(grep -a 'settings: protocol' "$G" | tail -1)"
echo "== 6. the trusted dialog (AB-004) =="
n_up=$(grep -ac 'wm: trusted dialog up no=' "$G")
[ "$n_up" -ge 2 ] && ok "the window server showed its own dialog for the agents' requests ($n_up times)" || bad "trusted dialog shown $n_up times"
has "$G" "wm: trusted dialog answer=2" "'n' on the real keyboard rejects"
part "$G" G-TRUST G-TRUST2 > "$TMPD/p.txt"
has "$TMPD/p.txt" "value=300" "... and the lock time stayed 300"
part "$G" G-TRUST2 G-TRUST3 > "$TMPD/p.txt"
has "$TMPD/p.txt" "trusted_dialogs=3" "a program typing 'jjj' into a window did not answer the dialog (still three answers: two yes from the window's critical changes, one no)"
has "$G" "wlkeys: key=36 state=1" "... although the program's 'j' did reach its window"
has "$G" "wm: trusted dialog answer=1" "'j' on the real keyboard says yes"
part "$G" G-TRUST3 G-TRUSTEND > "$TMPD/p.txt"
has "$TMPD/p.txt" "value=600" "... and then the change is done (lock.idle=600)"
part "$G" G-JOURNAL G-STAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "client=helper key=lock.idle" "the journal names the agent that asked, not the person who said yes"
has "$G" "wm: trusted dialog down no=" "a request confirmed with 'act confirm' takes its dialog off the screen"
grep -qaE 'settings: update page here=[0-9]+ phase=[a-z]* channel=[a-z]+ busy=[01]' "$G" \
    && ok "page Updates (DAILY-DRIVER): $(grep -a 'settings: update page' "$G" | tail -1 | cut -c1-90)" \
    || bad "page Updates: no status over settings.update.status ($(grep -a 'settings: update page' "$G" | tail -1))"
grep -qaE 'settings: system update here=[0-9]+ phase=[a-z]* there=[0-9]+ notes=[0-9]+' "$G" \
    && ok "page Updates SYSTEM block: $(grep -a 'settings: system update' "$G" | tail -1 | cut -c1-90)" \
    || bad "page Updates SYSTEM block: no status over settings.update.sysstatus ($(grep -a 'settings: system update' "$G" | tail -1))"
for f in 1-system 2-ask 3-done 4-rights 5-granted 5b-screen 6-netask 7-netdone 8-log 9-update 9-trust 10-trust-still 11-trust-done; do
    [ -s "$TMPD/$f.png" ] && ok "photo: $TMPD/$f.png" || bad "no photo $f"
done
echo "ACTBUS-GUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
