#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvviewer/gui.sh -- GUI gate of the FreeViewer window app (kernel/user/fvviewer.fi) in QEMU.
#
#   bash tools/fvviewer/gui.sh [stage ...]        (run it through /root/jarvis/bin/heavy)
#
# stages (default: plain tls tlsold wprobe opk)
#   plain    ws:// to a local relay + Rust test host: window, type ID + password, picture pixel probe,
#            click + keys in the test host log, clipboard echo, host kill/start => reconnect, fps/latency
#   tls      the same over wss:// (socat TLS terminator, own test CA /etc/fvviewer-ca.pem)
#   tlsold   wss:// with the OLD lib/fv/client.fi ($GUI_OLD_REV, default 4f0aa6ec): informational counter-test
#            of the "tls_read closes the socket on timeout" finding; never fails the gate
#   opk      the window starts FROM THE INSTALLED PACKAGE: the image has NO /bin/fvviewer and no hand-copied
#            /apps/fvviewer.osp; the signed fvviewer-1.0.0.opk is installed with the host tool (opk.py installieren)
#            into a root tree, and store/ + apps/ + generation 1 of that tree are put into the image. Then the
#            launcher starts /apps/fvviewer.osp/start and the same session checks as plain run
#   wprobe   `fvviewer -w 000000001` against the REAL relay (freeviewer.fleitec.com) from the guest
# The real Windows host is never touched; everything runs on 127.0.0.1 / the guest at 10.0.2.2.
# Env: GUI_BUILD=<dir> keeps the build cache (default: mktemp, removed at exit), GUI_RES (default 1280x800).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
STAGES=${*:-plain tls tlsold wprobe opk}
D=$(mktemp -d); trap 'for s in "$D"/*/th; do bash tools/fvviewer/th.sh "$s" down 2>/dev/null; done; [ -n "${CLIENT_BAK:-}" ] && cp "$CLIENT_BAK" lib/fv/client.fi; pkill -P $$ 2>/dev/null; rm -rf "$D"; [ -n "${GUI_BUILD:-}" ] || rm -rf "$BUILD"' EXIT
BUILD=${GUI_BUILD:-$D/build}
mkdir -p "$BUILD"
RES=${GUI_RES:-1280x800}
OLD_REV=${GUI_OLD_REV:-4f0aa6ec}
BASEPORT=$(( 21000 + ($$ % 1500) * 2 ))
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
PW=testpass123
export DRIVE_TIPPE_GAP=${DRIVE_TIPPE_GAP:-0.3}

gui_stage() { # name tls(0|1) oldclient(0|1) [pkg(0|1)]
    local name=$1 tls=$2 old=$3 pkg=${4:-0}
    local O="$D/$name"; mkdir -p "$O/th"
    local RP=$BASEPORT TP=$((BASEPORT+1)); BASEPORT=$((BASEPORT+2))
    local ID
    ID=$(bash tools/fvviewer/th.sh "$O/th" up "$RP" "$([ "$tls" = 1 ] && echo "$TP")") || { bad "$name: test host stack did not start"; return; }
    echo "== stage $name: relay $RP$([ "$tls" = 1 ] && echo " tls $TP") host id $ID =="
    if [ "$tls" = 1 ]; then
        echo "10.0.2.2 $TP tls" > "$O/fvviewer.test"; cp "$O/th/ca.pem" "$O/ca.pem"
    else
        echo "10.0.2.2 $RP" > "$O/fvviewer.test"; : > "$O/ca.pem"
    fi
    local B=$BUILD
    if [ "$old" = 1 ]; then
        B="$BUILD-old"; rm -rf "$B"; cp -a "$BUILD" "$B"; rm -f "$B/fvviewer.elf"
        CLIENT_BAK="$D/client.fi.bak"; cp lib/fv/client.fi "$CLIENT_BAK"
        git show "$OLD_REV:lib/fv/client.fi" > lib/fv/client.fi
    else
        rm -f "$B/fvviewer.elf"
    fi
    local TH="bash $ROOT/tools/fvviewer/th.sh $O/th"
    local HEAD="" MORE=fvviewer EXTRA_APPS="/apps/ /apps/fvviewer.osp/ /apps/fvviewer.osp/INFO=pakete/fvviewer/INFO@0644 /apps/fvviewer.osp/start@/bin/fvviewer"
    if [ "$pkg" = 1 ]; then
        local P="$O/pkg"; mkdir -p "$P"
        bash pakete/bauen.sh "$P/pk" > "$P/bauen.log" 2>&1 && [ -f "$P/pk/fvviewer-1.0.0.opk" ] || { bad "$name: pakete/bauen.sh"; tail -3 "$P/bauen.log"; bash tools/fvviewer/th.sh "$O/th" down; return; }
        bash tools/install/pakete.sh "$P" > "$P/pak.log" 2>&1 && python3 tools/update/signpak.py "$P/geheim.key" "$P/pk/fvviewer-1.0.0.opk" > /dev/null \
            || { bad "$name: signing the package"; tail -3 "$P/pak.log"; bash tools/fvviewer/th.sh "$O/th" down; return; }
        MORE=opk
        # Install the package into a root tree with the host tool (same format the on-device `opk` reads and
        # writes, see tools/module/run.sh step 10), then put store/ apps/ and the generation into the image.
        # Typing `opk install` into the desktop terminal lost keys under load (r43), so nothing is typed.
        local OPKPY W="$P/wurzel"; OPKPY=${OPK:-$(python3 tools/lib/opkpfad.py)}
        rm -rf "$W"; mkdir -p "$W"
        python3 "$OPKPY" installieren --wurzel "$W" "$P/pk/fvviewer-1.0.0.opk" --schluessel "$P/schluessel.pub" > "$P/hostinst.log" 2>&1 \
            || { bad "$name: host-side opk install"; tail -3 "$P/hostinst.log"; bash tools/fvviewer/th.sh "$O/th" down; return; }
        EXTRA_APPS="/apps/ /system/ /store/ /tmp/ /system/schluessel.pub=$P/schluessel.pub"
        local x
        for x in $(cd "$W" && find store apps system/generations -type d | sort); do EXTRA_APPS="$EXTRA_APPS /$x/"; done
        for x in $(cd "$W" && find store apps system/generations system/AKTUELL -type f | sort); do
            EXTRA_APPS="$EXTRA_APPS /$x=$W/$x"
        done
    fi
    cat > "$O/script.txt" <<EOF
warteauf 'launcher: ready' || 90
warte 4
$HEAD
taste meta_l
warte 2
foto 05-launcher
klickauf start_FreeViewer
warteauf 'fvviewer: rect name=go' || 60
warte 2
warte 1
klickauf fvrectid
warte 2
klickauf fvrectid
warte 1
tippe $ID
warte 2
klickauf fvrectpw
warte 2
klickauf fvrectpw
warte 1
tippe $PW
warte 1
foto 10-form
klickauf fvrectgo
warteauf 'fvviewer: state live' || 120
warte 9
foto 20-live
klickauf fvpt25x50
foto 29-click-fast
warte 0.5
foto 31-click-1s
warte 1
foto 32-click-2s
warte 2
foto 30-click
taste a
warte 0.5
taste ret
warte 0.5
taste ctrl-c
warte 3
marke 'fvviewer: state live'
extern $TH host-kill
warte 3
foto 35-host-gone
extern $TH host-start
warteneu 'fvviewer: state live' || 120
warte 6
foto 40-reconnected
EOF
    DESIGNBUILD="$B" EH_APPEND=rtcutc EH_APP_PROGS=fvviewer EH_MKFS_EXTRA="/etc/fvviewer.test=$O/fvviewer.test@0644 /etc/fvviewer-ca.pem=$O/ca.pem@0644 $EXTRA_APPS" \
        timeout 1500 bash tools/design/eh6.sh "$O/out" "res=$RES" accel=kvm netz=ja moreprogs=$MORE tafel=nein "drehbuch=$O/script.txt" > "$O/eh6.log" 2>&1
    [ "$old" = 1 ] && { cp "$CLIENT_BAK" lib/fv/client.fi; CLIENT_BAK=""; }
    if [ "$pkg" = 1 ]; then
        grep -aq 'launcher: start /apps/fvviewer.osp/start' "$O/out/serial.txt" && ok "$name: launcher started /apps/fvviewer.osp/start (from the installed package)" \
            || bad "$name: launcher never started /apps/fvviewer.osp/start"
        python3 tools/osum/mkfs.py list "$O/out/disk.img" 2>/dev/null | grep -aq 'bin/fvviewer' && bad "$name: image already has /bin/fvviewer (not a package test)" || ok "$name: image has no /bin/fvviewer"
    fi
    # the launcher sometimes drops the Return key on a loaded host: the app never started -> caller retries
    if ! grep -aq 'fvviewer: test mode on' "$O/out/serial.txt" 2>/dev/null; then
        echo "  (fvviewer did not start in the guest, retry)"; bash tools/fvviewer/th.sh "$O/th" down; return 7
    fi
    grep -a 'FEHLGESCHLAGEN\|NICHT DA\|Traceback' "$O/eh6.log" | head -5
    local mode=$name; [ "$name" = tlsold ] && mode=tlsidle
    python3 -I tools/fvviewer/gui_check.py "$O/out" "$O/th" "$mode" | tee "$O/check.txt"
    local nf; nf=$(grep -c '^  FAIL' "$O/check.txt")
    if [ "$name" = tlsold ]; then
        echo "  INFO  tlsold (old client.fi $OLD_REV): $nf failed check(s); lost lines: $(grep -ac 'fvviewer: lost err=' "$O/out/serial.txt"), live: $(grep -ac 'fvviewer: state live' "$O/out/serial.txt")"
    elif [ "$nf" = 0 ]; then ok "stage $name"; else bad "stage $name ($nf failed checks)"; fi
    if [ -n "${GUI_KEEP:-}" ]; then mkdir -p "$GUI_KEEP/$name"; cp "$O"/out/*.ppm "$O"/out/serial.txt "$O"/th/input.log "$O"/th/host.log "$O"/script.txt "$O"/eh6.log "$O"/check.txt "$GUI_KEEP/$name/" 2>/dev/null; fi
    bash tools/fvviewer/th.sh "$O/th" down
}

wprobe() {
    local O="$D/wprobe"; mkdir -p "$O"
    echo "== stage wprobe: fvviewer -w 000000001 against the real relay =="
    HWNET_PROGS="sh ls cat echo dhcp" bash tools/hwnet/build.sh "$O/s0" 0 > "$O/b0.txt" 2>&1 || { bad "wprobe: kernel/userland build"; tail -5 "$O/b0.txt"; return; }
    vendor/firn/bin/firnc -c --profile=app -o "$O/fvv.o" kernel/user/fvviewer.fi > "$O/fvv.err" 2>&1 \
        && ld -T kernel/user/user.ld -o "$O/fvv.elf" "$O/fvv.o" 2>>"$O/fvv.err" && strip --strip-all "$O/fvv.elf" \
        || { bad "wprobe: fvviewer build"; head -5 "$O/fvv.err"; return; }
    printf 'nameserver 10.0.2.3\n' > "$O/resolv.conf"
    python3 tools/hwnet/mkroots.py "$O/roots.pem" > "$O/roots.log" 2>&1 || { bad "wprobe: roots.pem"; return; }
    python3 tools/osum/mkfs.py build "$O/disk.img" 32768 /bin/ \
        /bin/sh="$O/s0/sh.elf" /bin/ls="$O/s0/ls.elf" /bin/cat="$O/s0/cat.elf" /bin/echo="$O/s0/echo.elf" \
        /bin/dhcp="$O/s0/dhcp.elf" /bin/fvviewer="$O/fvv.elf" /etc/ /etc/ssl/ "/etc/ssl/roots.pem=$O/roots.pem@0644" "/etc/resolv.conf=$O/resolv.conf@0644" > "$O/mkfs.txt" 2>&1 \
        || { bad "wprobe: mkfs"; tail -3 "$O/mkfs.txt"; return; }
    timeout 240 qemu-system-x86_64 -accel kvm -cpu host -kernel "$O/s0/k.mb" -m 512 \
        -append "osum nokbd nosched noproc nofs modfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=dhcp;fvviewer -w 000000001;exit" \
        -serial "file:$O/vm.txt" -display none -no-reboot \
        -drive "file=$O/disk.img,format=raw,if=ide,index=0" -netdev user,id=n0 -device e1000,netdev=n0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    [ -n "${GUI_KEEP:-}" ] && { mkdir -p "$GUI_KEEP/wprobe"; cp "$O/vm.txt" "$GUI_KEEP/wprobe/"; }
    grep -a 'WSS:' "$O/vm.txt" | head -8 | sed 's/^/        /'
    if grep -aq 'WSS: tls + websocket upgrade ok' "$O/vm.txt" && grep -aq 'WSS: relay error\|WSS: paired' "$O/vm.txt"; then
        ok "wprobe: DNS + TLS 1.3 + ws upgrade against the real relay, relay answered for id 000000001"
    else
        bad "wprobe: no relay answer -- tail: $(grep -a 'WSS:' "$O/vm.txt" | tail -3 | tr '\n' '|')"
    fi
}

retry() { local t; for t in 1 2 3; do "$@"; [ $? != 7 ] && return 0; done; bad "$2: app never started in the guest (3 tries)"; }
for s in $STAGES; do
    case "$s" in
        plain)   retry gui_stage plain 0 0 ;;
        tls)     retry gui_stage tls 1 0 ;;
        opk)     retry gui_stage opk 0 0 1 ;;
        tlsold)  retry gui_stage tlsold 1 1 ;;
        wprobe)  wprobe ;;
        *) echo "unknown stage $s"; exit 2 ;;
    esac
done
echo "GUI GATE: $pass ok, $fail failed"
[ "$fail" = 0 ]
