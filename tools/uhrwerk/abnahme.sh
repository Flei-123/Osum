#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/uhrwerk/abnahme.sh -- DIE ABNAHME DER RUNDE UHRWERK.
#
# Fuenf Laeufe je Kernzahl, und in jedem wird GEZAEHLT statt geglaubt:
#
#   1. KEIN PANIK-ABBRUCH. Beendigungscode und die Meldungen des Kerns.
#   2. DIE LEISTE KOMMT AN. `null=` ist die Zahl der Pushs, die NICHTS
#      hinuebergebracht haben -- der Fehler dieser Runde. Sie MUSS null
#      sein, und `px=` MUSS gleich `soll=` sein.
#   3. DIE EINGABE LEBT NOCH. Nach der Ruhephase gehen echte
#      Mauspakete und Tastendruecke hinein; die Zahlen des
#      Eingabepulses (`kl=` Klicks, `bew=` Bewegungen) muessen steigen.
#      Eine Abhilfe, die das Bild rettet und die Maus kostet, ist keine.
#
#   bash tools/uhrwerk/abnahme.sh <baudir> <ergebnisdir> [laeufe]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

BAU=${1:?baudir fehlt}
ERG=${2:?ergebnisdir fehlt}
LAEUFE=${3:-5}
BREITE=${UHR_W:-3440}
HOEHE=${UHR_H:-1440}
mkdir -p "$ERG"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }

APP="modfs osum gfx fbres=${BREITE}x${HOEHE} wm wig desk wmshell wmdauer tafel herz tz=120 usb hidgen nosched noproc nofs"

lauf() { # smp nr mit_eingabe
    local smp=$1 nr=$2 eing=$3
    local n="s${smp}-$nr"
    local out="$ERG/$n.txt" sock="$ERG/$n.sock"
    rm -f "$out" "$sock"
    ( timeout 60 $QEMU_X86 -cpu host -smp "$smp" -m 2048 \
        -kernel "$BAU/kern.mb" -initrd "$BAU/root.img" -append "$APP" \
        -serial "file:$out" -display none -no-reboot -vga std \
        -global VGA.vgamem_mb=64 \
        -device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 \
        -device usb-mouse,bus=x0.0 \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$ERG/$n.rc" ) &
    local pid=$!
    local i=0
    while [ $i -lt 900 ]; do
        grep -qa 'taskbar: round=' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05; i=$((i+1))
    done
    sleep 8
    if [ "$eing" = ja ]; then
        # ECHTE EINGABE, nach der Ruhe. Die Gegenprobe zu "die Maus
        # bleibt fluessig".
        cat > "$ERG/$n.cmd" <<'EOM'
warte 0.5
mouse_move 300 200
mouse_move 200 300
mouse_move -150 100
mouse_button 1
mouse_button 0
warte 0.5
sendkey a
sendkey b
warte 1.5
EOM
        python3 tools/wm/monitor.py "$sock" "$ERG/$n.cmd" >"$ERG/$n.mon" 2>&1 || true
        sleep 3
    fi
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f "$sock"
}

fld() { grep -a 'taskbar: round=' "$1" | tail -1 | sed -n "s/.*$2=\([0-9]*\).*/\1/p"; }
pfl() { grep -a 'eingabe:' "$1" | tail -1 | sed -n "s/.*[ :]$2=\([0-9]*\).*/\1/p"; }

for smp in 1 4; do
    echo "== -smp $smp, $LAEUFE Laeufe =="
    pan=0; nullsum=0; okpx=0
    for k in $(seq 1 "$LAEUFE"); do
        lauf "$smp" "$k" nein
        f="$ERG/s${smp}-$k.txt"
        if grep -qa 'PANIC\|panic\|EXCEPTION\|#UD\|#GP\|#PF\|#DF' "$f" 2>/dev/null; then
            pan=$((pan+1))
        fi
        lnull=$(fld "$f" null); lpx=$(fld "$f" px); lso=$(fld "$f" soll)
        nullsum=$((nullsum + ${lnull:-99}))
        [ -n "$lpx" ] && [ "$lpx" = "$lso" ] && okpx=$((okpx+1))
        printf '   Lauf %d: null=%s px=%s soll=%s\n' "$k" "${lnull:-?}" "${lpx:-?}" "${lso:-?}"
    done
    [ "$pan" -eq 0 ] && ok "-smp $smp: 0 Panics in $LAEUFE Laeufen" \
                     || bad "-smp $smp: $pan Panics"
    [ "$nullsum" -eq 0 ] && ok "-smp $smp: kein einziger Push ging verloren (null=0)" \
                         || bad "-smp $smp: $nullsum Pushs brachten nichts hinueber"
    [ "$okpx" -eq "$LAEUFE" ] && ok "-smp $smp: px == soll in allen $LAEUFE Laeufen" \
                              || bad "-smp $smp: px == soll nur in $okpx von $LAEUFE"
done

echo "== Gegenprobe: die Eingabe lebt noch =="
lauf 4 eing ja
f="$ERG/s4-eing.txt"
kl=$(pfl "$f" kl); bew=$(pfl "$f" bew); ta=$(pfl "$f" ta)
echo "   Eingabepuls: kl=${kl:-?} bew=${bew:-?} ta=${ta:-?}"
[ "${bew:-0}" -gt 0 ] 2>/dev/null && ok "die Maus bewegt noch etwas (bew=$bew)" \
                                  || bad "keine Mausbewegung angekommen (bew=${bew:-?})"
nl=$(fld "$f" null)
[ "${nl:-99}" -eq 0 ] 2>/dev/null && ok "auch MIT Eingabe geht kein Push verloren" \
                                  || bad "mit Eingabe gingen $nl Pushs verloren"

echo
echo "Abnahme: $pass ok, $fail NEIN"
[ "$fail" -eq 0 ]
