#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/build-kernel.sh -- EIN Kernelabbild, aus dem Repo heraus.
#
# Bis hierher hat jeder Testlaeufer unter tools/ den Kernel selbst gebaut,
# und jeder tat es mit denselben zehn Zeilen. Das ging, solange nur die
# Laeufer bauten. Seit OrientOS diesen Kernel als seine Grundlage benutzt
# (vendor/osum dort), braucht es EINE Stelle, die sagt, wie ein Abbild
# entsteht -- sonst baut das andere Repo etwas leicht anderes und misst
# etwas leicht anderes.
#
#   ./tools/build-kernel.sh AUSGABE [--stufe 0|1] [--gui on|off]
#                                  [--ohne-tunnel]
#
# RUNDE SERVERBUILD: --gui off BAUT OSUM ALS SERVERBETRIEBSSYSTEM.
# `kernel/drivers/gfx/fb.fi`, `wm.fi`, `wig.fi`, `font.fi`, `ttf.fi`, `tile.fi`,
# `vmode.fi`, `ansi.fi`, `ps2m.fi`, `kgui.fi` und `sysgui.fi` werden
# dabei NICHT UEBERSETZT -- sie liegen nicht im Baum, aus dem der
# Uebersetzer liest. An der Stelle von `kernel/drivers/gfx/gfx.fi` (der Naht, ueber
# die der uebrige Kernel die Grafik erreicht) steht `kernel/drivers/gfx/gfx-aus.fi`
# mit denselben 37 Symbolen und leeren Rumpfen. Kein `#ifdef`, kein
# Schalter zur Laufzeit, keine tote Verzweigung im Abbild.
#
# Die Vorgabe steht in `tools/config` (gui=on) und laesst sich mit
# OSUM_GUI in der Umgebung oder mit --gui auf der Befehlszeile
# ueberschreiben, in dieser Reihenfolge: Befehlszeile > Umgebung >
# tools/config > eingebaut.
#
# --ohne-tunnel baut den Kern mit `kernel/wg-aus.fi` statt `kernel/wg.fi`:
# ohne WireGuard, ohne die Krypto darunter, ohne Notaus. Das ist die
# Fassung fuer eine Auslieferung, die das Paket `vpn` nicht anbietet --
# der Tunnel ist darin nicht abgeschaltet, sondern NICHT VORHANDEN. Der
# Groessenunterschied zwischen beiden Abbildern ist der Preis des
# Tunnels und steht in docs/TUNNEL-PAKETE.md.
#
# Ergebnis: AUSGABE ist ein Multiboot-Abbild (ELF32-Huelle, damit sowohl
# `qemu-system-x86_64 -kernel` als auch ein Multiboot-Lader wie Limine es
# nimmt). Daneben liegt AUSGABE.elf, die ungewandelte ELF64-Fassung mit
# den Symbolen -- die braucht, wer einen Rueckverfolger schreibt.
#
# --stufe waehlt den Uebersetzer: 0 = firnc0 (Rust), 1 = firnc1 (Firn).
# Beide muessen dasselbe Abbild bauen koennen; genau das misst ./test.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

AUS=${1:-}
if [[ -z $AUS ]]; then
    sed -n '2,20p' "$0"
    exit 1
fi
shift

STUFE=0

# --------------------------------------------------- die Baukonfiguration
#
# Reihenfolge: eingebaut < tools/config < Umgebung < Befehlszeile. Wer
# `gui=off` in `tools/config` schreibt, baut das ganze Repo als Server;
# wer `--gui off` schreibt, baut EIN Abbild so.
GUI=on
TUNNEL=on
if [[ -f tools/config ]]; then
    while IFS='=' read -r k v; do
        k=${k%%#*}; k=${k// /}; v=${v%%#*}; v=${v// /}
        [[ -z $k ]] && continue
        case "$k" in
            gui) GUI=$v ;;
            tunnel) TUNNEL=$v ;;
        esac
    done < tools/config
fi
[[ -n ${OSUM_GUI:-} ]] && GUI=$OSUM_GUI
[[ -n ${OSUM_TUNNEL:-} ]] && TUNNEL=$OSUM_TUNNEL

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ohne-tunnel) TUNNEL=off; shift ;;
        --gui) GUI=$2; shift 2 ;;
        --stufe) STUFE=$2; shift 2 ;;
        *) echo "unbekannte Option: $1" >&2; exit 1 ;;
    esac
done
case "$GUI" in on|off) ;; *) echo "--gui nimmt on oder off, nicht '$GUI'" >&2; exit 1 ;; esac
case "$TUNNEL" in on|off) ;; *) echo "tunnel nimmt on oder off, nicht '$TUNNEL'" >&2; exit 1 ;; esac
OHNE_TUNNEL=0
[[ $TUNNEL == off ]] && OHNE_TUNNEL=1

export FIRNLIB="$ROOT/lib"
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen" >&2; exit 1; }

if [[ $STUFE == 0 ]]; then
    FIRNC="$ROOT/vendor/firn/bin/firnc"
else
    FIRNC="$ROOT/vendor/firn/bin/firnc1"
fi
[[ -x $FIRNC ]] || { echo "Uebersetzer fehlt: $FIRNC" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Die fuenf Assemblerdateien. Was in ihnen steht, kann eine Sprache nicht
# ausdruecken: der Multiboot-Kopf, der Sprung in den langen Modus, die
# Einsprungpunkte der Unterbrechungen, der Kontextwechsel, der
# Trampolinsprung der anderen Prozessoren -- und seit Runde K12 der
# Weltwechsel in eine Gastmaschine samt den Gaesten selbst (hv.s).
for f in boot isr switch smp hv; do
    as --64 -o "$TMP/$f.o" "kernel/arch/x86_64/$f.s" || exit 1
done

# Firn uebersetzt von `kmain.fi` aus den ganzen Baum. Um eine Datei
# WEGZULASSEN, wird der Kernbaum kopiert und `wg.fi` durch den Stummel
# ersetzt -- das Abbild entsteht dann ohne eine Zeile des Tunnels.
# IMMER aus der Kopie uebersetzen, auch mit Tunnel. Sonst waeren die
# beiden Abbilder auf verschiedenen Wegen entstanden, und der
# Groessenunterschied in docs/TUNNEL-PAKETE.md waere nicht mehr allein
# der Tunnel -- eine Gegenprobe hat genau das gezeigt: derselbe Kern,
# einmal direkt und einmal aus /tmp uebersetzt, ergibt ein anderes
# Abbild. Gleicher Weg fuer beide, dann ist die Differenz der Inhalt.
cp -a kernel "$TMP/kernel" || exit 1
if [[ $OHNE_TUNNEL == 1 ]]; then
    cp -f kernel/wg-aus.fi "$TMP/kernel/wg.fi" || exit 1
fi
rm -f "$TMP/kernel/wg-aus.fi"

# RUNDE SERVERBUILD: DERSELBE GRIFF, EINE ETAGE GROESSER. Nicht eine
# Datei wird ersetzt, sondern elf werden GELOESCHT und die zwoelfte
# (`gfx.fi`, die Naht) durch ihre Leerfassung ersetzt. Danach steht im
# Baum, aus dem firnc liest, keine Zeile Grafik mehr -- und weil kein
# anderes Modul `fb.` oder `wm.` schreibt (Runde SERVERBUILD hat die
# 745 Stellen auf 0 gebracht), uebersetzt der Rest unveraendert.
# MERGE-2 18 (customres): `dispsave.fi` ist die ZWOELFTE. Sie liest und
# schreibt /system/BILDMODUS und ruft dafuer 37-mal `vmode.` und `fb.` --
# sie GEHOERT der Grafik, genau wie die elf davor, und muss beim
# GUI-losen Bau ebenfalls verschwinden. `tools/server/count.py` hat es
# gemeldet: 37 Stellen ausserhalb der Naht. Der Weg dorthin fuer den
# uebrigen Kern sind die zwei Tueren `gfx.disp_poll` und
# `gfx.disp_restore`.
# RUNDE STRUKTUR: die Liste traegt jetzt PFADE statt nackter Namen.
# Vier der zwoelf Dateien sind Treiber und liegen seit dieser Runde
# unter kernel/drivers/ (fb, font, vmode = die Grafikkarte; ps2m =
# das Zeigegeraet). Die anderen acht sind kein Treiber -- ein
# Fensterserver, ein Fensterbaum, ein Schriftrasterer, eine
# Terminalemulation -- und bleiben, wo sie waren.
#
# `rm -f` schweigt ueber eine Datei, die es nicht gibt. Ein Pfad,
# der hier ins Leere zeigt, wuerde also NICHT auffallen: der Bau
# liefe durch und das Abbild traegt die Grafik, die es nicht tragen
# soll. Darum wird jeder Pfad geprueft, bevor er geloescht wird.
GFX_DATEIEN="wm.fi wig.fi ttf.fi tile.fi ansi.fi kgui.fi sysgui.fi dispsave.fi
             drivers/gfx/fb.fi drivers/gfx/font.fi drivers/gfx/vmode.fi
             drivers/input/ps2m.fi"
if [[ $GUI == off ]]; then
    for f in $GFX_DATEIEN; do
        [[ -f "$TMP/kernel/$f" ]] || {
            echo "--gui off: kernel/$f gibt es nicht (verschoben?)" >&2; exit 1; }
        rm -f "$TMP/kernel/$f" || exit 1
    done
    cp -f kernel/drivers/gfx/gfx-aus.fi "$TMP/kernel/drivers/gfx/gfx.fi" || exit 1
fi
rm -f "$TMP/kernel/drivers/gfx/gfx-aus.fi"
KDIR="$TMP/kernel"

"$FIRNC" -o "$TMP/k.o" "$KDIR/kmain.fi" || exit 1
"$FIRNC" -o "$TMP/uprog.o" "$KDIR/uprog.fi" || exit 1

# firnc0 stellt jedem Symbol `_F0.` voran, firnc1 `_F1.`
# (docs/SELF_HOSTING.md im Firn-Repo).
P="_F${STUFE}."
ld -n -T kernel/kernel.ld \
    --defsym=KERNEL_MAIN="${P}kernel_main" \
    --defsym=KERNEL_TRAP="${P}trap__entry" \
    --defsym=KERNEL_SYSCALL="${P}sys__entry" \
    --defsym=KERNEL_TASK_MAIN="${P}tasks__main" \
    --defsym=KERNEL_USER_START="${P}proc__user_start" \
    --defsym=KERNEL_AP_MAIN="${P}smp__ap_main" \
    --defsym=USER_MAIN="${P}u_enter" \
    -o "$TMP/osum.elf" "$TMP/boot.o" "$TMP/isr.o" "$TMP/switch.o" \
    "$TMP/smp.o" "$TMP/hv.o" "$TMP/k.o" "$TMP/uprog.o" 2> >(grep -vE \
        'GNU-stack|deprecated|LOAD segment with RWX' >&2) || exit 1

mkdir -p "$(dirname "$AUS")"
cp -f "$TMP/osum.elf" "$AUS.elf"
objcopy -O elf32-i386 "$TMP/osum.elf" "$AUS" || exit 1
echo "$AUS ($(stat -c%s "$AUS") Oktette, Stufe $STUFE, gui=$GUI, tunnel=$TUNNEL)"
