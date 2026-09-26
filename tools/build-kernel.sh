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
#                                  [--ohne-tunnel] [--ohne-bruecke]
#
# RUNDE SERVERBUILD: --gui off BAUT OSUM ALS SERVERBETRIEBSSYSTEM.
# `kernel/fb.fi`, `wm.fi`, `wig.fi`, `font.fi`, `ttf.fi`, `tile.fi`,
# `vmode.fi`, `ansi.fi`, `ps2m.fi`, `kgui.fi` und `sysgui.fi` werden
# dabei NICHT UEBERSETZT -- sie liegen nicht im Baum, aus dem der
# Uebersetzer liest. An der Stelle von `kernel/gfx.fi` (der Naht, ueber
# die der uebrige Kernel die Grafik erreicht) steht `kernel/gfx-aus.fi`
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
OHNE_PS2M=0
# RUNDE BRUECKE: `--ohne-bruecke` baut den Kern mit `kernel/tip-off.fi`
# statt `kernel/tip.fi`. Der Aufruf 1843 ist dann nicht abgeschaltet,
# sondern NICHT VORHANDEN -- der Unterschied zwischen einem Schloss und
# einer Abwesenheit steht im Kopf von `kernel/tip-off.fi`.
OHNE_BRUECKE=0
# RUNDE PROTOKOLL: die Symbol- und Zeilentabelle im Abbild.  Vorgabe an;
# `--ohne-symbole` laesst sie weg (siehe tools/kernel/symtab.py).
SYMBOLE=on

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
# RUNDE FREMDFS: STANDARD IST AN -- die Begruendung steht in
# docs/RUNDE-FREMDFS.md, Abschnitt 10, und sie stuetzt sich auf die
# GEMESSENE Groesse und nicht auf ein Gefuehl.
OHNE_EXT4=${OHNE_EXT4:-0}
OHNE_NTFS=${OHNE_NTFS:-0}
[[ -n ${OSUM_EXT4:-} ]] && [[ $OSUM_EXT4 == off ]] && OHNE_EXT4=1
[[ -n ${OSUM_NTFS:-} ]] && [[ $OSUM_NTFS == off ]] && OHNE_NTFS=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ohne-tunnel) TUNNEL=off; shift ;;
        # RUNDE FREMDFS: die zwei fremden Dateisysteme, einzeln.
        --ohne-ext4) OHNE_EXT4=1; shift ;;
        --ohne-ntfs) OHNE_NTFS=1; shift ;;
        --ohne-fremdfs) OHNE_EXT4=1; OHNE_NTFS=1; shift ;;
        --ohne-ps2m) OHNE_PS2M=1; shift ;;
        --ohne-bruecke) OHNE_BRUECKE=1; shift ;;
        --ohne-symbole) SYMBOLE=off; shift ;;
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
# ROUND FUI-KERNTEXT: fUi's TrueType reader, UNDER A SECOND NAME.
#
# kernel/gfx/fuiink.fi draws the kernel's text with fUi's own
# lib/font/ttf.fi + lib/font/raster.fi. Firn allows ONE module per short
# name in a compilation unit, and `ttf` is taken by kernel/gfx/ttf.fi
# (the kernel's reader, the cache and the fallback rasteriser). So the
# very same file is copied here as `gfx/fuittf.fi` -- byte for byte, from
# the Firn this tree is pinned to (vendor/firn/lib). It is not a second
# version and it is not in the repository: there is nothing to keep in
# step by hand.
FUITTF="$ROOT/vendor/firn/lib/font/ttf.fi"
[[ -f $FUITTF ]] || { echo "fUi-Schriftleser fehlt: $FUITTF" >&2; exit 1; }
if [[ -d "$TMP/kernel/gfx" ]]; then
    cp -f "$FUITTF" "$TMP/kernel/gfx/fuittf.fi" || exit 1
fi

# ================================ RUNDE FASSUNG: WELCHE FASSUNG IST DAS
#
# Der kurze Commit-Hash wird HIER in die Kopie eingesetzt, nicht in den
# Arbeitsbaum -- sonst haette jeder Bau eine Aenderung im Baum zur
# Folge, und `git status` waere nie wieder sauber.
#
# WARUM ES DAS GIBT: am 03.09.2026 hat Justin ein Abbild getestet und
# "kein Unterschied" gemeldet. Ob die Runde darin war, liess sich
# hinterher nur mit Zeitstempeln, Pruefsummen und einem QEMU-Lauf
# klaeren -- der Kern selbst sagte es nicht. Jetzt sagt er es, in der
# ersten Zeile des Startprotokolls und in der Messleiste auf dem
# Schreibtisch.
FASSUNG_HASH=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unbekant")
if git status --porcelain 2>/dev/null | grep -q .; then
    # Ein Baum mit ungesicherten Aenderungen ist NICHT der Commit, auf
    # den der Hash zeigt. Das Pluszeichen sagt das.
    FASSUNG_HASH="${FASSUNG_HASH:0:7}+"
fi
# ================================ RUNDE MARKE: DER NAME UND DIE FASSUNG
#
# Bis hierher stand `osum` in diesem sed fest verdrahtet -- der
# Kurzname des Produkts, in einer Zeile eines Bauskripts. Genau das
# war Justins Beanstandung.
#
# Jetzt macht es `tools/marke-einsetzen.py`: es liest `marke.conf`,
# laesst `OSUM_MARKE_*` aus der Umgebung darueberschlagen (Firns Ersatz
# fuer `option_env!` aus /root/projects/freeviewer/src/brand.rs) und
# setzt beides in die /tmp-Kopie ein -- die sechs Markenfelder in
# `kernel/brand.fi` und die Fassungszeile `<KURZ> <hash>` in
# `kernel/version.fi`. Es BRICHT AB, wenn ein Feld fehlt, leer ist,
# nicht passt oder ein Platzhalter stehenbleibt.
#
# Der Arbeitsbaum wird dabei nicht angefasst; `git status` meldet nach
# einem Bau weiterhin nichts.
python3 "$(dirname "$0")/marke-einsetzen.py" "$TMP" \
    "$(dirname "$0")/../marke.conf" "$FASSUNG_HASH" || {
    echo "die Marke wurde NICHT eingesetzt -- Bau abgebrochen" >&2
    exit 1; }
# GEGENPROBE AM ERGEBNIS, nicht am Werkzeug: steht die Fassungszeile
# wirklich in der Datei, aus der uebersetzt wird?
# (Gesucht statt buchstabiert -- siehe RUNDE O-STRUKTUR weiter unten.)
VERSIONDATEI=$(find "$TMP/kernel" -path "$TMP/kernel/user" -prune -o \
    -path "$TMP/kernel/app" -prune -o -name version.fi -type f -print | head -1)
[[ -n $VERSIONDATEI ]] || { echo "version.fi nicht gefunden" >&2; exit 1; }
grep -q " $FASSUNG_HASH" "$VERSIONDATEI" || {
    echo "die Fassungsnummer wurde NICHT eingesetzt -- Bau abgebrochen" >&2
    exit 1; }
# Und dieselbe Gegenprobe fuer die Marke: kein Feld darf noch ein
# Fragezeichen tragen. (Das Werkzeug prueft es auch; hier steht es
# NOCH EINMAL am Ergebnis, weil eine Pruefung im Werkzeug nur das
# Werkzeug prueft.)
BRANDDATEI=$(find "$TMP/kernel" -path "$TMP/kernel/user" -prune -o \
    -path "$TMP/kernel/app" -prune -o -name brand.fi -type f -print | head -1)
[[ -n $BRANDDATEI ]] || { echo "brand.fi nicht gefunden" >&2; exit 1; }
if grep -qE 'static mut s_[a-z]+: \[u8; [0-9]+\] = "[^"]*\?' \
        "$BRANDDATEI"; then
    echo "in brand.fi steht noch ein Platzhalter -- abgebrochen" >&2
    exit 1
fi
# RUNDE O-STRUKTUR: DIE GEGENFASSUNGEN FINDEN IHR ZIEL, WO ES LIEGT.
#
# Bis hierher stand hier `cp -f kernel/tip-off.fi "$TMP/kernel/tip.fi"`
# -- beide Pfade buchstabiert. Seit die Dateien in Schichten liegen
# (`kernel/ipc/tip.fi`, `kernel/net/wg.fi`, ...) trifft das nicht mehr.
#
# `ersetze <stummel> <ziel>` sucht BEIDE im Kopierbaum, legt den
# Stummel an die Stelle des Ziels und raeumt den Stummel danach weg.
# Es BRICHT AB, wenn eines von beidem fehlt -- ein stiller Fehlschlag
# an dieser Stelle ergaebe ein Abbild, das etwas enthaelt, das es
# nicht enthalten soll.
ersetze() { # $1 = Stummel ohne .fi, $2 = Ziel ohne .fi
    local stummel ziel
    stummel=$(find "$TMP/kernel" -name "$1.fi" -type f | head -1)
    ziel=$(find "$TMP/kernel" -name "$2.fi" -type f | head -1)
    [[ -n $stummel ]] || { echo "Bau: $1.fi nicht gefunden" >&2; return 1; }
    [[ -n $ziel    ]] || { echo "Bau: $2.fi nicht gefunden" >&2; return 1; }
    cp -f "$stummel" "$ziel" || return 1
}
# Und die Gegendatei fliegt IMMER aus dem Baum, aus dem firnc liest --
# sonst uebersetzt der Kern beide und fuehrt zwei Module desselben
# Namens.
weg() { # $1 = Name ohne .fi
    local p
    p=$(find "$TMP/kernel" -name "$1.fi" -type f)
    [[ -n $p ]] && rm -f $p
    return 0
}

if [[ $OHNE_BRUECKE == 1 ]]; then
    ersetze tip-off tip || exit 1
fi
weg tip-off

if [[ $OHNE_TUNNEL == 1 ]]; then
    ersetze wg-aus wg || exit 1
fi
weg wg-aus

# RUNDE FREMDFS: DERSELBE GRIFF FUER DIE ZWEI FREMDEN DATEISYSTEME.
#
# `--ohne-ext4` bzw. `--ohne-ntfs` legt die Leerfassung an die Stelle
# des Treibers. Danach steht im Baum, aus dem firnc liest, keine Zeile
# des jeweiligen Dateisystems mehr -- und weil die Leerfassung
# DIESELBEN Namen exportiert, uebersetzt `vfs.fi` unveraendert.
#
# Was das spart, ist gemessen und steht in docs/RUNDE-FREMDFS.md.
if [[ $OHNE_EXT4 == 1 ]]; then
    ersetze ext4-aus ext4 || exit 1
fi
weg ext4-aus
if [[ $OHNE_NTFS == 1 ]]; then
    ersetze ntfs-aus ntfs || exit 1
fi
weg ntfs-aus

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
# RUNDE O-STRUKTUR, BEFUND (nicht behoben, siehe docs/STRUKTUR.md 5b):
# `zeiger` ist ein Name OHNE DATEI -- die Runde ENGLISCH (337c6cbd)
# hat `kernel/zeiger.fi` nach `kernel/cursor.fi` umbenannt und diese
# Liste nicht mitgezogen. `rm -f` schweigt dazu. Der Eintrag bleibt
# hier UNVERAENDERT stehen, weil diese Runde ordnet und nicht
# repariert; die Pruefung unten MELDET ihn, statt ihn zu verschlucken.
# RUNDE ROADMAP-3: `zeiger` -> `cursor` nachgezogen (die Warnung unten
# hat es jeden Serverbau gemeldet).
# A-039: `vgpu` (drv/gpu/vgpu.fi) is graphics too -- only graphics files
# import it, and the server image never had a single vgpu__ symbol.
GFX_DATEIEN="fb wm wig font ttf tile wmplug vmode ansi ps2m kgui sysgui dispsave cursor vgpu"
if [[ $GUI == off ]]; then
    for f in $GFX_DATEIEN; do
        # RUNDE O-STRUKTUR: `rm -f` SCHWEIGT, wenn die Datei woanders
        # liegt. Zieht jemand `fb.fi` nach `kernel/gfx/fb.fi`, loescht
        # diese Zeile nichts, meldet nichts -- und der Serverbau baeckt
        # die Grafik STILL ins Abbild. Gemessen und bestaetigt am
        # 17.09.2026 (docs/STRUKTUR.md, Abschnitt 5).
        #
        # Also: erst suchen, dann loeschen, und ABBRECHEN, wenn die
        # Datei gar nicht da war. Die Suche findet sie auch in einem
        # Unterordner -- damit bleibt der GUI-lose Bau richtig, wenn
        # eine spaetere Runde die Grafik einsortiert.
        # `-path */user/*` bleibt draussen: `kernel/user/wmplug.fi` ist ein
        # Programm und kein Teil der Kern-Grafik (gleicher Name, anderer Ort).
        TREFFER=$(find "$TMP/kernel" -name "$f.fi" -type f -not -path "*/user/*")
        if [[ -z $TREFFER ]]; then
            echo "SERVERBUILD-WARNUNG: '$f.fi' steht in GFX_DATEIEN," \
                 "liegt aber nicht im Kernbaum -- hier wird NICHTS" \
                 "geloescht. Entweder ist der Name veraltet, oder die" \
                 "Datei wurde verschoben." >&2
        fi
        rm -f $TREFFER
    done
    # Dieselbe Vorsicht fuer die Naht selbst.
    GFXZIEL=$(find "$TMP/kernel" -name "gfx.fi" -type f | head -1)
    [[ -n $GFXZIEL ]] || { echo "SERVERBUILD: gfx.fi nicht gefunden" >&2; exit 1; }
    ersetze gfx-aus gfx || exit 1
fi
weg gfx-aus

# RUNDE MODUL: DERSELBE GRIFF, EINE ETAGE KLEINER.
#
# `--ohne-ps2m` ersetzt `kernel/ps2m.fi` (den Treiber des Zeigegeraets,
# 650 Zeilen) durch `kernel/ps2m-aus.fi` -- dieselben einunddreissig
# Ausfuhren, kein Treiber darin, und statt dessen ein Blick in die
# Treibertafel von `kernel/modtab.fi`. Der so gebaute Kern HAT KEINE
# MAUS, bis eine `.omod`-Datei geladen wird.
#
# Das ist nicht dasselbe wie `nomouse` auf der Kommandozeile: dort ist
# der Treiber im Abbild und wird nur nicht benutzt. Hier ist er NICHT IM
# ABBILD -- der Groessenunterschied zwischen beiden Abbildern ist der
# Preis des Treibers und steht in docs/RUNDE-MODUL.md.
#
# Kein Aufrufer aendert sich: `wm.fi` ruft `ps2m.x(state)` weiter an
# fuenfzehn Stellen. Genau das ist der Beweis, dass der Schnitt an der
# richtigen Stelle liegt.
if [[ $OHNE_PS2M == 1 ]]; then
    if [[ $GUI == off ]]; then
        echo "--ohne-ps2m und --gui off zusammen ergeben nichts: ohne GUI ist ps2m.fi ohnehin nicht im Baum" >&2
        exit 1
    fi
    ersetze ps2m-aus ps2m || exit 1
fi
weg ps2m-aus
KDIR="$TMP/kernel"

# Auch die zwei Wurzeln werden gesucht: `kmain.fi` bleibt zwar oben im
# Kernverzeichnis, aber das steht in keinem Gesetz.
KMAIN=$(find "$KDIR" -name kmain.fi -type f | head -1)
UPROG=$(find "$KDIR" -name uprog.fi -type f | head -1)
[[ -n $KMAIN ]] || { echo "kmain.fi nicht gefunden" >&2; exit 1; }
[[ -n $UPROG ]] || { echo "uprog.fi nicht gefunden" >&2; exit 1; }
"$FIRNC" -o "$TMP/k.o" "$KMAIN" || exit 1
"$FIRNC" -o "$TMP/uprog.o" "$UPROG" || exit 1

# firnc0 stellt jedem Symbol `_F0.` voran, firnc1 `_F1.`
# (docs/SELF_HOSTING.md im Firn-Repo).
P="_F${STUFE}."

# ==================================================== RUNDE PROTOKOLL
# ZWEIMAL BINDEN, UND DANACH NACHRECHNEN.
#
# Die Symbol- und Zeilentabelle (`tools/kernel/symtab.py`) entsteht aus
# einem FERTIG GEBUNDENEN Abbild -- vorher gibt es keine Adressen.  Also:
# einmal binden mit dem Stummel aus `kernel/arch/x86_64/osym.s`, die
# Tabelle daraus erzeugen, noch einmal binden.
#
# Das geht nur auf, wenn der zweite Durchgang keine einzige
# Funktionsadresse verschiebt.  Er tut es nicht, weil die Tabelle in
# `.rodata` liegt und `.rodata` im Bindeskript hinter `.text` und
# `.utext` steht -- aber das wird hier NICHT GEGLAUBT, sondern gemessen:
# `nm` auf beide Abbilder, und wenn eine Adresse gewandert ist, bricht
# der Bau ab.  Waere das je der Fall, zeigte der Panik-Bildschirm falsche
# Namen, und ein falscher Name ist schlimmer als gar keiner.
binde() { # $1 = osym-Objekt, $2 = Ausgabe
    ld -n -T kernel/kernel.ld \
        --defsym=KERNEL_MAIN="${P}kernel_main" \
        --defsym=KERNEL_TRAP="${P}trap__entry" \
        --defsym=KERNEL_SYSCALL="${P}sys__entry" \
        --defsym=KERNEL_TASK_MAIN="${P}tasks__main" \
        --defsym=KERNEL_USER_START="${P}proc__user_start" \
        --defsym=KERNEL_AP_MAIN="${P}smp__ap_main" \
        --defsym=USER_MAIN="${P}u_enter" \
        -o "$2" "$TMP/boot.o" "$TMP/isr.o" "$TMP/switch.o" \
        "$TMP/smp.o" "$TMP/hv.o" "$TMP/k.o" "$TMP/uprog.o" $1 \
        2> >(grep -vE 'GNU-stack|deprecated|LOAD segment with RWX' >&2)
}

# Durchgang 1: OHNE Tabelle. `osym_tab` ist trotzdem aufgeloest -- es
# steht als SCHWACHES Symbol in `boot.s`, und das ist der Grund, aus dem
# jeder andere Laeufer dieses Repos den Kernel weiterhin mit seiner
# eigenen ld-Zeile binden kann.
binde "" "$TMP/osum.elf" || exit 1

if [[ $SYMBOLE == on ]]; then
    nm -n "$TMP/osum.elf" | awk '$2=="T"||$2=="t"' > "$TMP/sym1.txt"
    python3 "$(dirname "$0")/kernel/symtab.py" "$TMP/osum.elf" \
        "$TMP/osym2.s" || { echo "symtab.py fehlgeschlagen" >&2; exit 1; }
    as --64 -o "$TMP/osym2.o" "$TMP/osym2.s" || exit 1
    binde "$TMP/osym2.o" "$TMP/osum2.elf" || exit 1
    nm -n "$TMP/osum2.elf" | awk '$2=="T"||$2=="t"' > "$TMP/sym2.txt"
    if ! cmp -s "$TMP/sym1.txt" "$TMP/sym2.txt"; then
        echo "PROTOKOLL: der zweite Bindedurchgang hat Funktionsadressen" \
             "verschoben -- die Symboltabelle waere falsch. Bau abgebrochen." >&2
        diff "$TMP/sym1.txt" "$TMP/sym2.txt" | head -5 >&2
        exit 1
    fi
    mv -f "$TMP/osum2.elf" "$TMP/osum.elf"
fi

mkdir -p "$(dirname "$AUS")"
cp -f "$TMP/osum.elf" "$AUS.elf"
objcopy -O elf32-i386 "$TMP/osum.elf" "$AUS" || exit 1
echo "$AUS ($(stat -c%s "$AUS") Oktette, Stufe $STUFE, gui=$GUI, tunnel=$TUNNEL, ps2m=$([[ $OHNE_PS2M == 1 ]] && echo modul || echo fest), symbole=$SYMBOLE, ext4=$([[ $OHNE_EXT4 == 1 ]] && echo aus || echo an), ntfs=$([[ $OHNE_NTFS == 1 ]] && echo aus || echo an))"
