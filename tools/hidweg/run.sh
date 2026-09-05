#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hidweg/run.sh -- WARUM AUF JUSTINS BRETT KEINE EINGABE ANKAM.
#
#   bash tools/hidweg/run.sh
#
# ======================================================================
# DIE AUSGANGSLAGE, UND SIE IST EINE MESSUNG UND KEINE VERMUTUNG
# ======================================================================
#
# Am 03.09.2026 hat Justin das USB-Abbild a37098b9 auf echter Hardware
# gestartet (AMD-Brett, zwei xHCI-Regler, NVIDIA GA106, Ultrabreitbild)
# und die USB-Diagnose fotografiert. Darauf steht:
#
#     usbleg: gut=2 schlecht=0
#     usb: hc1 ... id=1022:149c ... strom=8/8 verbunden=2 frei=2
#     usb: port=3 ... id=046d:c08b class=03:01:02 driver=mouse
#     usb: port=4 ... id=046d:c336 class=03:01:01 driver=kbd
#     usb: devices=2 kbd=1 mouse=1 ... events=36 irqs=23
#
# Uebernahme, Anschlussstrom, Aufzaehlung, Bindung, Meldung -- ALLES
# GEHT. Und im Schreibtisch bewegte sich der Zeiger trotzdem nicht.
#
# ======================================================================
# WAS DIESE RUNDE GEFUNDEN HAT: DREI FEHLER, ALLE OBERHALB DES TREIBERS
# ======================================================================
#
# 1. DER SCHREIBTISCH HAT AUFGEHOERT. `kgui.wait_wm` wartete auf die
#    Shell im Terminalfenster in einer Schleife mit HARTER RUNDENGRENZE
#    (20000). Danach kehrte sie zurueck, `surface` kehrte zurueck, der
#    Kern lief durch bis `kernel: done`. Das Bild blieb stehen, aber
#    NIEMAND rief mehr `wm.poll`. GEMESSEN, mit genau der
#    Kommandozeile von Menue 4: der Schreibtisch lebte 9,4 SEKUNDEN.
#
# 2. DIE UNTERBRECHUNGEN WAREN AUS. Der Ausflug nach Ring 3
#    (`arch/x86_64/user.fi`, Runde 59) geht ueber `sysretq` hinaus und
#    ueber `leave_user` zurueck -- ohne `sysret`, also aus einem
#    SYSCALL heraus, und `syscall` loescht IF ueber IA32_FMASK.
#    Niemand setzte es wieder. GEMESSEN, Stufe fuer Stufe:
#
#        nach hv.stage    if=1
#        nach ring3       if=0
#
#    Von da an: kein Zeitgeber, keine Taste, keine Maus. `ps2m.init`
#    half nicht -- es stellt nur wieder her, was es vorfand.
#
# 3. NIEMAND FRAGTE NACH. Der Schreibtisch verliess sich vollstaendig
#    auf die Meldung. Ein Regler, dessen Meldung nicht ankommt (auf
#    Justins Brett `hc0`: `events=50 irqs=0`), ist damit stumm.
#
# ======================================================================
# WAS HIER GEMESSEN WIRD
# ======================================================================
#
#   1. DIE GEGENPROBE ZUERST. Ohne `wmdauer` endet der Schreibtisch --
#      `wm: sh exit=...4073709551614` (das ist -2, die Rundengrenze)
#      steht im Mitschnitt, und die Sekunden bis dahin werden gezaehlt.
#      Ein Fehler, dessen Gegenprobe nicht faellt, ist keiner.
#   2. MIT `wmdauer` steht diese Zeile NICHT da, und die Maschine laeuft
#      noch, wenn der Laeufer sie abraeumt.
#   3. DER EINGABEPULS. Der Kern schreibt alle fuenf Sekunden eine Zeile
#      INS TERMINALFENSTER und auf die Leitung. Daran wird gemessen:
#      `if=1` (Unterbrechungen an), `mk=` waechst (der Zeitgeber
#      schlaegt), `irq=` waechst (die Meldung kommt an).
#   4. ECHTE EINGABE. Ueber den QEMU-Monitor gehen Tasten, Bewegungen
#      und ein Klick in die laufende Maschine. `bew=`, `pk=`, `xy=`,
#      `wm=` und `kl=` MUESSEN sich bewegen.
#   5. DIE GEGENPROBE ZUR MELDUNG. Mit `usbnoirq` bleibt der Vektor
#      maskiert: `irq=` steht still -- und die Eingabe kommt TROTZDEM
#      an, ueber die Abfrage in der Schleife. Das ist der Nachweis,
#      dass Punkt 3 der Reparatur wirklich traegt und nicht nur
#      danebensteht.
#   6. ZWEI REGLER, HID AM ZWEITEN. Wie auf Justins Brett.
#   7. DIE RANGFOLGE DER SCHNITTSTELLEN, an einem GEBAUTEN
#      Konfigurationsdeskriptor: Verbrauchersteuerung zuerst,
#      Boot-Tastatur danach -- genommen werden MUSS die zweite.
#      QEMU hat kein zusammengesetztes HID-Geraet; ohne diesen Test
#      waere die Auswahl eine Behauptung.
#   8. DIE MELDEART je Regler steht im Bericht (`melde=msi-x|msi|intx`).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2 (erwartet $3)"; fi; }
gt()  { if [ -n "$2" ] && [ -n "$3" ] && [ "$2" -gt "$3" ] 2>/dev/null
        then ok "$1: $2 > $3"; else bad "$1: $2, sollte groesser als $3 sein"; fi; }
hat() { grep -qa -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qa -- "$2" "$1" && bad "$3 -- '$2' steht da und darf nicht" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "HIDWEG: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
if ! qemu-system-x86_64 -device help 2>&1 | grep -q 'qemu-xhci'; then
    echo "HIDWEG: uebersprungen, dieses QEMU kennt qemu-xhci nicht"; exit 0
fi

echo "== 1. bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh faellt"; exit 1; }
bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/b0.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "der Kern baut nicht"; sed 's/^/        /' "$TMPD/b0.log" | head -12; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
rc=0
for p in $PROGS; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || {
        bad "firnc uebersetzt $p.fi nicht"; sed 's/^/        /' "$TMPD/e$p" | head -5; rc=1; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld faellt bei $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ $rc -eq 0 ] && ok "$(echo $PROGS | wc -w) Programme fuer Ring 3 gebaut"
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py faellt"
printf '# taskbar.conf\nedge=0\nheight=28\nwidth=100\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/root.img" 16384 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer" /etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "das Wurzelabbild steht ($(stat -c%s "$TMPD/root.img") Oktette)" \
    || { bad "mkfs.py faellt"; tail -3 "$TMPD/mkfs.txt"; }

# Zwei Regler, HID am ZWEITEN -- die Aufstellung von Justins Brett.
ZWEI="-device qemu-xhci,id=x0 -device nec-usb-xhci,id=x1 -device usb-kbd,bus=x1.0 -device usb-mouse,bus=x1.0"

cat > "$TMPD/befehle" <<'EOM'
warte 2.0
sendkey a
sendkey b
sendkey c
warte 1.0
mouse_move 60 0
mouse_move 60 0
mouse_move 0 60
mouse_move 0 60
mouse_move 40 20
warte 1.0
mouse_button 1
mouse_button 0
warte 2.0
EOM

# Ein Lauf. Wartet auf die Marke, speist dann Maus und Tastatur ein und
# raeumt nach `sek` Sekunden ab. Der Beendigungscode sagt, ob die
# Maschine von sich aus fertig war (21) oder abgeraeumt wurde (124).
lauf() { # name kommandozeile marke sek [mit-eingabe]
    local name=$1 app=$2 marke=$3 sek=$4 eingabe=${5:-ja}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock" "$TMPD/$name.rc"
    ( timeout "$sek" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 1024 -append "$app" \
        -serial "file:$out" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" -initrd "$TMPD/root.img" \
        $ZWEI -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
      echo $? > "$TMPD/$name.rc" ) &
    local pid=$! i=0
    while [ $i -lt 2000 ]; do
        grep -qaE "$marke" "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05; i=$((i+1))
    done
    if [ "$eingabe" = ja ]; then
        python3 tools/wm/monitor.py "$sock" "$TMPD/befehle" > "$TMPD/$name.mon" 2>&1
    fi
    wait "$pid" 2>/dev/null
    rm -f "$sock"
    RC=$(cat "$TMPD/$name.rc" 2>/dev/null || echo 99)
}

# Ein Feld aus der LETZTEN Pulszeile.
feld() { # datei name
    grep -a '^eingabe:' "$1" | tail -1 | sed -n "s/.*[ :]$2=\([0-9]*\).*/\1/p"
}
feld1() { # datei name -- aus der ersten VOLLSTAENDIGEN Pulszeile
    # RUNDE HIDPUNKTE: `sh=` IST DAS LETZTE FELD DER ZEILE, und dass hier
    # danach gefiltert wird, ist keine Vorsicht auf Vorrat. Der Laeufer
    # wartet jetzt auf die erste Pulszeile und liest die Datei in dem
    # Augenblick, in dem sie geschrieben wird -- die erste Zeile ist
    # dann oft halb da. `irq=` steht vorne und war zu lesen, `mk=` und
    # `xy=` stehen hinten und waren leer, und ein leerer Vergleichswert
    # laesst jede Zusage darauf fallen. Gemessen: "der Zeitgeber
    # schlaegt (mk): 4217, sollte groesser als  sein".
    grep -a '^eingabe:' "$1" | grep -a 'sh=' | head -1 \
        | sed -n "s/.*[ :]$2=\([0-9]*\).*/\1/p"
}

BASE="modfs osum gfx wm wig desk wmshell usb hidgen nosched noproc nofs"

echo
echo "== 2. DIE GEGENPROBE: ohne wmdauer hoert der Schreibtisch auf =="
t0=$(date +%s%N)
lauf alt "$BASE" '^wm: sh exit' 150 nein
t1=$(date +%s%N)
hat "$TMPD/alt.txt" 'wm: sh exit=' \
    "ohne wmdauer HOERT der Schreibtisch auf (wm: sh exit=)"
is "und der Kern laeuft danach durch bis zum Ende" "$RC" 21
hat "$TMPD/alt.txt" 'kernel: done' "der Kern ist wirklich fertig -- das Bild ist ein Standbild"
echo "       (Lebensdauer bis zum Aufgeben: $(( (t1-t0)/1000000000 )) s)"

echo
echo "== 3. MIT wmdauer laeuft er weiter, und die Meldungen kommen an =="
# RUNDE HIDPUNKTE: DIE MARKE IST JETZT DIE ERSTE PULSZEILE UND NICHT
# MEHR DAS TERMINALFENSTER, und das ist die Reparatur eines Wettlaufs im
# LAEUFER, nicht im Kern.
#
# Die drei Zusagen weiter unten vergleichen die LETZTE Pulszeile mit der
# ERSTEN ("irq steigt", "ber steigt", "der Zeiger bewegt sich"). Das
# Terminalfenster steht aber lange VOR dem ersten Puls (der haengt an
# den Marken, alle fuenf Sekunden). Wurde die elf Sekunden lange
# Befehlsfolge in dieser Luecke abgearbeitet, stand in der ERSTEN
# Pulszeile bereits `ber=13 irq=47 xy=799,539` -- und dieselbe Zahl kann
# nicht groesser als sie selbst sein.
#
# Gemessen an BEIDEN Kernen, dem dieser Runde und dem davor (HEAD ohne
# die Aenderungen): erste und letzte Zeile identisch. Es ist also die
# Zeitlage der Maschine und keine Regression -- deshalb wird hier die
# Marke verschoben und nicht die Zusage aufgeweicht.
lauf neu "$BASE wmdauer" '^eingabe:' 45
hatnicht "$TMPD/neu.txt" 'wm: sh exit' "mit wmdauer gibt der Schreibtisch NICHT auf"
is "die Maschine lief noch, als der Laeufer sie abraeumte" "$RC" 124
hat "$TMPD/neu.txt" 'wm: dauer' "der Dauerbetrieb steht im Mitschnitt"
N=$(grep -ac '^eingabe:' "$TMPD/neu.txt")
gt "Pulszeilen im Mitschnitt" "$N" 2
is "die Unterbrechungen sind AN (if)" "$(feld "$TMPD/neu.txt" if)" 1
gt "der Zeitgeber schlaegt (mk)" "$(feld "$TMPD/neu.txt" mk)" "$(feld1 "$TMPD/neu.txt" mk)"
gt "die xHCI-Meldung kommt an (irq)" "$(feld "$TMPD/neu.txt" irq)" "$(feld1 "$TMPD/neu.txt" irq)"

echo
echo "== 4. und die Eingabe kommt oben an =="
gt "HID-Berichte (ber)" "$(feld "$TMPD/neu.txt" ber)" "$(feld1 "$TMPD/neu.txt" ber)"
gt "Mausbewegungen aus den Berichten (bew)" "$(feld "$TMPD/neu.txt" bew)" 0
gt "Pakete beim Zeiger (pk)" "$(feld "$TMPD/neu.txt" pk)" 0
gt "vom Fensterserver abgeholt (wm)" "$(feld "$TMPD/neu.txt" wm)" 1
gt "Klicks im Fensterserver (kl)" "$(feld "$TMPD/neu.txt" kl)" 0
A=$(grep -a '^eingabe:' "$TMPD/neu.txt" | head -1 | sed -n 's/.* xy=\([0-9,]*\).*/\1/p')
B=$(grep -a '^eingabe:' "$TMPD/neu.txt" | tail -1 | sed -n 's/.* xy=\([0-9,]*\).*/\1/p')
if [ -n "$A" ] && [ "$A" != "$B" ]; then ok "der Zeiger ist gewandert: $A -> $B"
else bad "der Zeiger steht still: $A -> $B"; fi

echo
echo "== 5. GEGENPROBE zur Meldung: mit usbnoirq traegt die Abfrage =="
lauf poll "$BASE wmdauer usbnoirq" '^wm: term win=' 45
is "der Vektor bleibt maskiert -- irq steht still" \
    "$(feld "$TMPD/poll.txt" irq)" "$(feld1 "$TMPD/poll.txt" irq)"
gt "und die Maus kommt TROTZDEM an (bew)" "$(feld "$TMPD/poll.txt" bew)" 0
gt "und der Klick auch (kl)" "$(feld "$TMPD/poll.txt" kl)" 0

echo
echo "== 6. zwei Regler, HID am zweiten -- wie auf Justins Brett =="
D=$(grep -a '^usb: devices=' "$TMPD/neu.txt" | tail -1)
is "Geraete am behaltenen Regler" "$(echo "$D" | sed -n 's/usb: devices=\([0-9]*\).*/\1/p')" 2
is "Tastatur"                      "$(echo "$D" | sed -n 's/.*kbd=\([0-9]*\).*/\1/p')" 1
is "Maus"                          "$(echo "$D" | sed -n 's/.*mouse=\([0-9]*\).*/\1/p')" 1
hat "$TMPD/neu.txt" 'driver=kbd'   "die Tastatur ist gebunden"
hat "$TMPD/neu.txt" 'driver=mouse' "die Maus ist gebunden"
is "beide Regler melden ihre Meldeart" \
    "$(grep -ac 'usb: hc[0-9] melde=' "$TMPD/neu.txt")" 2

echo
echo "== 7. die Rangfolge der Schnittstellen (gebauter Deskriptor) =="
R=$(grep -a 'usb: rang ok=' "$TMPD/neu.txt" | tail -1)
is "Zusagen der Rangfolge" "$(echo "$R" | sed -n 's/.*ok=\([0-9]*\).*/\1/p')" 6
hat "$TMPD/neu.txt" 'usb: rang ok=6 / 6' \
    "die Boot-Tastatur gewinnt gegen die Verbrauchersteuerung desselben Geraets"

echo
echo "HIDWEG: $pass gehalten, $fail gefallen"
[ "$fail" -eq 0 ]
