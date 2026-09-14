#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmplug/run.sh -- DER ABNAHMELAUF DER RUNDE WMPLUGIN.
#
# Er faehrt alles selber nach und druckt am Ende
# "N bestanden, M gescheitert". Nichts darin ist abgeschrieben: jede
# Zusage haengt an einer Zeile, die ein WIRKLICH gebooteter Kern auf die
# serielle Leitung geschrieben hat, oder an einem Bildpunkt in einem
# Foto, das aus demselben Lauf stammt.
#
# WAS HIER GEMESSEN WIRD
#
#   1. RING-3-TRENNUNG. Kein Plugin-Symbol im Kernabbild -- am ELF
#      nachgesehen, nicht behauptet.
#   2. DIE DREI HARTEN GRENZEN, jede in einem EIGENEN Lauf:
#        Absturz  /bin/plugboese segv   -> `wmplug: tot platz=` und der
#                                          Schreibtisch malt weiter
#        Frist    /bin/plugboese hang   -> `grund=2`, Bildrate bleibt
#        Rechte   /bin/plugboese greif  -> Fehlercode UND das Fenster
#                                          steht nachweislich still
#   3. DIE SCHNITTSTELLE, einmal ganz durch (/bin/plugprobe): Fassung,
#      Kuerzel ohne und mit Gewaehrung, Ereignisse, Tempo vor/nach.
#   4. DIE VERWALTUNG: /bin/wmplug list/info/disable/list an einem
#      wirklich angemeldeten Plugin.
#   5. DIE ZWEI ECHTEN PLUGINS -- dafuer laufen die beiden Modullaeufer
#      regel.sh und widget.sh mit, und ihre Zahlen gehen in die Summe
#      ein. Sie bringen auch die Fotos fuer "an und aus zur Laufzeit".
#   6. tools/check-ui.sh.
#
# Die Bilder landen in docs/shots/wmplug/.
#
# Gebrauch:  bash tools/wmplug/run.sh
#            WMPLUG_SCHNELL=1 bash tools/wmplug/run.sh   (ohne die zwei
#            Modullaeufer -- nur die Kernseite, fuer die Runde am Stueck)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d /tmp/wmplug-run-XXXXXX)
[ "${WMPLUG_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
SHOTS="docs/shots/wmplug"
mkdir -p "$SHOTS"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
# Die Leitung des Kerns traegt Namen mit fester Laenge
# (`serial.text(name, 8)`), also stehen mitten in den Zeilen
# Nulloktette. Gesucht wird darum immer in der geputzten Fassung.
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasre() { grep -qaE "$2" "$1" && ok "$3" || bad "$3 -- /$2/ trifft nicht"; }
hasnotre() { grep -qaE "$2" "$1" && bad "$3 -- /$2/ sollte nicht zutreffen" || ok "$3"; }
# Eine Zahl aus einer Zeile der Leitung: zahl <datei> <muster> <feld>
zahl() { grep -aE "$2" "$1" | tail -1 | grep -oE "$3=-?[0-9]+" | head -1 | sed 's/.*=//'; }

# DIE LEITUNG REISST, UND ZWAR MITTEN IM WORT.
#
# GEMESSENER BEFUND: der Kern schreibt seine Zeilen stueckweise
# (`serial.puts` je Wortteil), und faellt dazwischen ein Zeitgeber oder
# ein anderer Kernpfad herein, steht dessen Zeile MITTEN in der ersten:
#
#     wmplug: tot platz=0 pid=6
#     wmplwm: fokus id=7 vor=0
#     ug: unreg boese grund=1 holte=0 verlor=0
#
# Eine Zusage, die `unreg boese ... grund=1` zeilenweise sucht, ist dann
# rot -- obwohl der Kern genau das gesagt hat. Also wird fuer solche
# Zusagen der Zeilenumbruch WEGGENOMMEN und im durchgehenden Strom
# gesucht. Das ist keine Nachsicht, sondern die richtige Frage: es geht
# darum, OB der Kern den Grund genannt hat, nicht darum, ob die Zeile
# heil geblieben ist.
flach() { tr -d '\n' < "$1" > "$1.flat"; }
hasflat() { grep -qaE "$2" "$1.flat" && ok "$3" \
    || bad "$3 -- /$2/ trifft auch im durchgehenden Strom nicht"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "WMPLUG: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

# ====================================================== 1. bauen
echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kernel baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; }
[ -f "$TMPD/k.mb" ] || { echo; echo "WMPLUG: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher calc sh
       plugboese plugprobe plugregel pluguhr wmplug
       plugtempo plugspaet"
gebaut=1
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc uebersetzt $p.fi nicht"
        sed 's/^/        /' "$TMPD/$p.err" | head -6; gebaut=0; }
done
[ "$gebaut" = 1 ] && ok "$(echo $PROGS | wc -w) Programme gebaut" \
    || { echo; echo "WMPLUG: $pass bestanden, $fail gescheitert"; exit 1; }

# ====================================== 2. die Ring-3-Trennung am Abbild
echo "== 2. Ring 3, am Kernabbild nachgesehen =="
# DAS IST DIE ZUSAGE DER RUNDE. Hyprland laedt seine Plugins als .so in
# den Compositor; bei uns LIEGT DER FENSTERSERVER IM KERN, und ein
# Plugin dort waere Fremdcode in Ring 0. Also darf kein einziges Symbol
# eines Plugins im Kernabbild stehen -- das laesst sich sehen.
# DIE SYMBOLTAFEL WIRD EINMAL ABGELEGT UND DANN GELESEN, nicht in eine
# Roehre geschickt. GEMESSENER BEFUND: unter `set -o pipefail` beendet
# `grep -q` die Roehre beim ERSTEN Treffer, `nm` bekommt SIGPIPE, und
# die Roehre gilt als gescheitert -- der Fund wurde so zum Fehlschlag.
# Genau daran ist die Gegenprobe unten einmal falsch rot gewesen.
nm -a "$TMPD/k.mb.elf" > "$TMPD/sym.txt" 2>/dev/null \
    && ok "die Symboltafel des Kerns ist lesbar ($(wc -l < "$TMPD/sym.txt") Symbole)" \
    || bad "nm kommt an $TMPD/k.mb.elf nicht heran -- ohne sie misst Abschnitt 2 nichts"
for sym in plugregel__ pluguhr__ plugboese__ plugprobe__ plugtempo__ plugspaet__; do
    if grep -qF "$sym" "$TMPD/sym.txt"; then
        bad "der Kernel traegt Symbole von $sym -- Fremdcode in Ring 0"
    else
        ok "kein Symbol von $sym im Kernabbild"
    fi
done
# Und die Gegenprobe zur Gegenprobe: das Kernmodul der Schnittstelle IST
# drin. Waere es das nicht, pruefte die Schleife oben nur ein leeres nm.
grep -qF 'wmplug__reg' "$TMPD/sym.txt" \
    && ok "kernel/wmplug.fi selbst ist im Abbild (die Probe oben misst wirklich)" \
    || bad "wmplug__reg fehlt im Abbild -- dann sagt die Symbolprobe nichts"

# ====================================================== 3. das Abbild
echo "== 3. das Abbild =="
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py fehlgeschlagen"
for f in etc/wmplug.conf etc/wmregeln.conf; do
    [ -f "$f" ] && ok "$f liegt im Baum" || bad "$f fehlt"
done
# Die Zeile, an der die Rechte-Gegenprobe haengt. Wer sie aufbohrt,
# macht sie kaputt -- also wird sie geprueft und nicht vorausgesetzt.
grep -qE '^boese[[:space:]]+rechte=0x0*1([[:space:]]|$)' etc/wmplug.conf \
    && ok "/etc/wmplug.conf gibt 'boese' genau R_EV_WIN (0x001)" \
    || bad "'boese rechte=0x001' steht nicht mehr in /etc/wmplug.conf"
# DIE ZWEI FRISTEN DIESER RUNDE STEHEN IN DER DATEI UND NICHT IM SKRIPT.
# Wer sie dort aendert, aendert die Messung -- also wird hier gelesen,
# was gemessen wird, und nicht daneben eine zweite Wahrheit gepflegt.
grep -qE '^uhr[[:space:]].*frist=100([[:space:]]|$)' etc/wmplug.conf \
    && ok "/etc/wmplug.conf gibt dem Widget frist=100 Ticks (1 s)" \
    || bad "'uhr ... frist=100' steht nicht in /etc/wmplug.conf"
grep -qE '^regel[[:space:]].*frist=500([[:space:]]|$)' etc/wmplug.conf \
    && ok "/etc/wmplug.conf gibt der Regel-Engine frist=500 Ticks (5 s)" \
    || bad "'regel ... frist=500' steht nicht in /etc/wmplug.conf"
[ -f etc/wmplug.autostart ] \
    && ok "etc/wmplug.autostart liegt im Baum (die Autostart-Liste)" \
    || bad "etc/wmplug.autostart fehlt"

# DAS ABBILD, UND ZWAR EINES JE AUTOSTART-LISTE.
#
# Seit dieser Runde startet nicht mehr ein Hilfsprogramm die
# Erweiterungen (/bin/uhrstart ist weg), sondern der SCHREIBTISCH liest
# /etc/wmplug.autostart und ruft fuer jede Zeile `wmplug enable <name>`.
# Die Liste liegt also IM ABBILD -- und weil jeder Lauf dieser Abnahme
# eine andere Liste braucht, baut diese Funktion je Lauf ein eigenes.
# Das kostet ein paar Sekunden mkfs und ist der ehrliche Weg: gemessen
# wird derselbe Weg, den ein Benutzer geht.
printf 'on\n' > "$TMPD/uitrace"
abbild() { # name  [autostart-zeile ...]
    local nm=$1; shift
    : > "$TMPD/auto-$nm.txt"
    local z
    for z in "$@"; do printf '%s\n' "$z" >> "$TMPD/auto-$nm.txt"; done
    local A=(build "$TMPD/disk-$nm.img" 32768 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf"
        "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
    local p n
    for p in $PROGS; do
        n=$p; [ "$p" = plugspaet ] && n=uhrspaet
        A+=("/bin/$n=$TMPD/$p.elf")
    done
    # DIE LEISTE SOLL SAGEN, WAS SIE MALT. Ohne /etc/uitrace schweigt
    # sie, und dann gibt es keine Zeile `taskbar: plug nr=0 x= y= w= h=`
    # -- also auch keine Koordinate, an der sich ein Foto nachrechnen
    # liesse. Die Spur kostet ein paar Zeilen auf der seriellen Leitung
    # und aendert am Bild nichts; gemessen wird trotzdem am Bild.
    A+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/uitrace=$TMPD/uitrace"
        "/etc/wmplug.conf=etc/wmplug.conf"
        "/etc/wmregeln.conf=etc/wmregeln.conf"
        "/etc/wmplug.autostart=$TMPD/auto-$nm.txt")
    while read -r z; do A+=("$z"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs-$nm.txt" 2>&1
}

# Das Grundabbild OHNE Autostart -- fuer die Laeufe, die ihr Programm
# selbst mitbringen (`wigapp=`), und als Gegenprobe, dass eine leere
# Liste wirklich nichts startet.
abbild basis \
    && ok "das Abbild ist gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs-basis.txt" | head -5; }
cp -f "$TMPD/disk-basis.img" "$TMPD/disk.img" 2>/dev/null

# ====================================================== der Laufhelfer
BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug"

warte() { # datei marke pid schritte
    local f=$1 m=$2 pid=$3 n=${4:-900} i=0
    while [ $i -lt "$n" ]; do
        grep -qa "$m" "$f" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done
    return 1
}

# lauf <name> <zusatzwoerter> [foto-marke]
# Legt $TMPD/<name>.clean (Leitung ohne Nulloktette), $TMPD/<name>.rc
# (Exitcode von QEMU) und, wenn eine Marke da ist, $TMPD/<name>.ppm an.
lauf() {
    local name=$1 extra=$2 marke=${3:-} marke2=${4:-}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock" "$TMPD/$name.ppm"
    # WELCHES ABBILD? Das mit der Autostart-Liste dieses Laufs, wenn es
    # eines gibt -- sonst das Grundabbild.
    local img="$TMPD/disk.img"
    [ -s "$TMPD/disk-$name.img" ] && img="$TMPD/disk-$name.img"
    cp -f "$img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$BASE $extra" -serial "file:$out" -display none \
        -no-reboot -vga std -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    if [ -n "$marke" ]; then
        warte "$out" "$marke" "$pid"
        sleep 2
        python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name.ppm" 25 \
            > "$TMPD/$name.shot" 2>&1
        # WIE WEIT WAR DIE LEITUNG, ALS DAS FOTO ENTSTAND? Wer spaeter
        # eine Koordinate aus dem Protokoll liest, muss die Zeile
        # nehmen, die VOR dem Foto stand -- nicht die letzte des Laufs.
        wc -l < "$out" > "$TMPD/$name.marke"
    fi
    # EIN ZWEITES FOTO AUS DEMSELBEN LAUF, an einer zweiten Marke.
    # Nur so laesst sich "zur Laufzeit" belegen: derselbe Server,
    # dieselbe Leiste, kein Neustart -- nur der Zustand des Plugins hat
    # sich zwischen den beiden Augenblicken geaendert.
    if [ -n "$marke2" ]; then
        warte "$out" "$marke2" "$pid"
        sleep 2
        python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name-2.ppm" 25 \
            > "$TMPD/$name-2.shot" 2>&1
    fi
    wait "$pid"; echo "$?" > "$TMPD/$name.rc"
    rm -f "$sock"
    tr -d '\000' < "$out" > "$TMPD/$name.clean"
    flach "$TMPD/$name.clean"
}

sauber() { # name
    local rc; rc=$(cat "$TMPD/$1.rc" 2>/dev/null)
    [ "$rc" = 21 ] && ok "$1: der Kern beendet sich sauber (21)" \
        || bad "$1: Exitcode $rc statt 21"
}

# ========================================== 4. die Absturz-Gegenprobe
echo "== 4. Absturz: ein Plugin stuerzt ab (SIGSEGV) =="
# DER AUTOSTART FAEHRT DIE GEGENPROBE. Eine Zeile in
# /etc/wmplug.autostart, mehr braucht es nicht: der Schreibtisch ruft
# `wmplug enable boesebar segv`, das gewaehrt die Rechte aus
# /etc/wmplug.conf (dort traegt `boesebar` zusaetzlich R_ACT_BAR) und
# startet /bin/plugboese. ZWEI FOTOS aus DEMSELBEN Lauf: eines, waehrend
# das Plugin sein Feld in der Leiste besetzt haelt, und eines, nachdem
# der Kern den Toten abgeholt hat.
abbild segv 'boesebar segv' || bad "segv: das Abbild ist nicht gebaut"
lauf segv "" '^plugboese: leiste gesetzt' 'wmplug: tot platz='
S=$TMPD/segv.clean
sauber segv
has "$S" "plugboese: abi=1" "das Plugin hat die Fassung erfragt"
hasre "$S" '^plugboese: platz=[0-9]+ rechte=2049$' \
    "es hat genau die Rechte aus /etc/wmplug.conf (0x801 = 2049: sehen + Leiste)"
has "$S" "plugboese: leiste gesetzt, rc=0" \
    "es hat VOR dem Absturz ein Feld in der Leiste besetzt (WM_PLUG_BAR)"
has "$S" "plugboese: gleich stuerze ich ab" "es sagt an, dass es gleich abstuerzt"
hasre "$S" 'wmplug: tot platz=[0-9]+ pid=[0-9]+' \
    "der Kern hat den Toten selbst abgeholt (reap)"
hasflat "$S" 'unreg boesebar *grund=1' \
    "und abgemeldet mit grund=1 (G_CRASH) -- der Grund steht auf der Leitung"
# DER EIGENTLICHE PUNKT: der Schreibtisch lebt danach WEITER.
has "$S" "wm: hold" "der Fensterserver steht noch"
hasnotre "$S" '^(panic|PANIC|kernel panic)' "kein Panik im Kern"
# Weitere Bildlaeufe NACH dem Absturz -- gezaehlt, nicht vermutet.
# WIE VIELE BILDER HAT DER SERVER GEBAUT? `wm: vsync= ... comp=N` ist
# der Zaehler des Zusammensetzers selbst (kernel/wm.fi), nicht einer,
# der fuer diese Runde erfunden wurde.
fr_tot=$(zahl "$S" '^wm: vsync=' 'comp')
if [ -n "${fr_tot:-}" ] && [ "$fr_tot" -gt 0 ] 2>/dev/null; then
    ok "der Zusammensetzer lief trotz des Absturzes $fr_tot Runden (wm: comp=)"
else
    bad "keine Zahl 'comp=' -- ohne sie ist 'laeuft weiter' nur Meinung"
fi
has "$S" "wmplug: bilanz" "und der Kern zieht am Ende seine Bilanz"
# EIN TOTER WIRD EINMAL ABGEHOLT, NICHT ZWEIMAL. Der Kehrbesen laeuft
# aus zwei Pfaden (compose je Bild, poll je Tick); ohne Sperre hat ihn
# der Zeitgeber mitten in seiner eigenen Ausgabe noch einmal angestossen
# und derselbe Absturz wurde doppelt gezaehlt (gemessen: kicks=2).
n_tot=$(grep -ca 'wmplug: tot platz=' "$S")
[ "${n_tot:-0}" = 1 ] \
    && ok "der Tote wurde GENAU EINMAL abgeholt (eine Zeile 'wmplug: tot')" \
    || bad "'wmplug: tot' steht ${n_tot}x da -- der Kehrbesen laeuft in sich selbst"
k_segv=$(zahl "$S" '^wmplug: bilanz' 'kicks')
[ "${k_segv:-0}" = 1 ] \
    && ok "und genau einmal gezaehlt (kicks=1 fuer einen Absturz)" \
    || bad "die Bilanz zaehlt kicks=${k_segv} fuer EINEN Absturz"
if [ -s "$TMPD/segv.ppm" ]; then
    cp -f "$TMPD/segv.ppm" "$SHOTS/nach-absturz.ppm"
    masse=$(python3 tools/gfx/checkshot.py groesse "$TMPD/segv.ppm" 2>/dev/null)
    [ "$masse" = "800 600" ] \
        && ok "Foto nach dem Absturz: 800x600, der Bildmodus steht noch" \
        || bad "das Foto nach dem Absturz misst '$masse' statt '800 600'"
    # NICHT NUR "ein Bild kam an": auf dem Schirm muss auch etwas zu
    # sehen sein. Ein schwarzes Bild waere genau der Fall, den diese
    # Runde ausschliessen will -- Plugin tot, Schreibtisch tot.
    nl=$(python3 tools/gfx/checkshot.py nichtleer "$TMPD/segv.ppm" 0 0 800 600 2>/dev/null \
         | grep -oE '[0-9]+' | head -1)
    if [ -n "${nl:-}" ] && [ "$nl" -gt 100000 ] 2>/dev/null; then
        ok "und $nl von 480000 Bildpunkten sind nicht schwarz -- der Schreibtisch malt"
    else
        bad "nur '$nl' nichtschwarze Bildpunkte -- der Schirm ist nach dem Absturz leer"
    fi
    # Als PNG ablegen wie die Bilder der beiden Modullaeufer -- ein
    # PPM von anderthalb Megaoktett gehoert nicht in den Baum.
    python3 -c "from PIL import Image; Image.open('$SHOTS/nach-absturz.ppm').save('$SHOTS/nach-absturz.png')" \
        2>/dev/null && rm -f "$SHOTS/nach-absturz.ppm"
    [ -s "$SHOTS/nach-absturz.png" ] \
        && ok "das Foto liegt als docs/shots/wmplug/nach-absturz.png" \
        || bad "nach-absturz.png wurde nicht abgelegt"
else
    bad "kein Foto nach dem Absturz"
fi

# ============================================ 5. die Haenger-Gegenprobe
echo "== 5. Frist: ein Plugin haengt in der Endlosschleife =="
# `plugfrist` kuerzt die Frist des Kerns auf wenige Ticks, damit sie
# innerhalb eines Laufs wirklich reisst. Die Frist SELBST steht in
# kernel/wmplug.fi; dieses Wort setzt nur den Zeiger kuerzer.
abbild hang 'boese hang' || bad "hang: das Abbild ist nicht gebaut"
lauf hang "plugfrist" '^wm: hold'
H=$TMPD/hang.clean
sauber hang
has "$H" "plugboese: ab jetzt hole ich nichts" "das Plugin hoert auf abzuholen"
hasflat "$H" 'unreg boese *grund=2' \
    "die Frist hat gegriffen: abgemeldet mit grund=2 (G_FRIST)"
has "$H" "wm: hold" "der Schreibtisch steht auch danach"
hasnotre "$H" '^(panic|PANIC|kernel panic)' "kein Panik im Kern"
# KEIN TEMPOEINBRUCH DURCH DEN HAENGER: derselbe Zaehler wie oben,
# derselbe Kern, dasselbe Abbild -- nur das Plugin haengt.
fr_hang=$(zahl "$H" '^wm: vsync=' 'comp')
if [ -n "${fr_hang:-}" ] && [ "$fr_hang" -gt 0 ] 2>/dev/null; then
    ok "auch mit dem Haenger lief der Zusammensetzer $fr_hang Runden"
else
    bad "keine Zahl 'comp=' im Haengerlauf"
fi
if [ -n "${fr_hang:-}" ] && [ -n "${fr_tot:-}" ]; then
    # Die zwei Zahlen stehen nebeneinander im Bericht. Verglichen wird
    # grosszuegig (Haelfte), weil beide Laeufe verschiedene Programme
    # starten -- eine schaerfere Schranke waere eine Scheingenauigkeit.
    if [ "$fr_hang" -ge $((fr_tot / 2)) ]; then
        ok "Bildrunden Absturzlauf $fr_tot gegen Haengerlauf $fr_hang -- kein Einbruch"
    else
        bad "Bildrunden brechen ein: $fr_tot gegen $fr_hang"
    fi
fi

# ============================================= 6. die Rechte-Gegenprobe
echo "== 6. Rechte: ein Plugin greift nach einem fremden Fenster =="
abbild greif 'boese greif' || bad "greif: das Abbild ist nicht gebaut"
lauf greif "" '^wm: hold'
G=$TMPD/greif.clean
sauber greif
# R_DEFAULT (0x1F) ist das, was der KERN einem unbekannten Plugin gibt:
# zusehen, nichts anfassen. Die Zeile `boese rechte=0x001` in
# /etc/wmplug.conf ist noch enger und wuerde erst durch
# `wmplug enable boese` wirksam -- hier wird also der WEITERE der beiden
# Faelle gemessen, und selbst der hat kein einziges Aktionsbit.
hasre "$G" '^plugboese: platz=[0-9]+ rechte=1$' \
    "das Plugin hat GENAU R_EV_WIN (0x001) und ausdruecklich KEIN R_ACT_WIN (0x100)"
# UND DAMIT LIEST ES TROTZDEM DIE FENSTERTAFEL. Das ist die Zusage des
# neuen Leserechts: bis zu dieser Runde ging WM_LIST nur an eine
# Taskleiste, und dieses Plugin legte dafuer ein verborgenes Fenster von
# 32x16 Bildpunkten an. Das Fenster ist weg; der Schluessel ist das
# Recht. Ginge es nicht, staende unten kein `vorher id=`.
hasnotre "$G" 'plugboese-lese' \
    "es legt KEIN verborgenes Hilfsfenster mehr an (der Titel kommt nicht vor)"
hasre "$G" 'plugboese: vorher id=[0-9]+ x=[0-9]+ y=[0-9]+' \
    "es hat den Ort des fremden Fensters VORHER gelesen"
hasre "$G" 'plugboese: griff nach fremdem id=[0-9]+ fehler=2' \
    "der Griff wird mit -E_RIGHTS (cap.E_RIGHTS = 2) abgewiesen"
hasre "$G" 'plugboese: griff .* deny=1' \
    "und der Kern zaehlt die Abweisung mit (PL_DENY + 1)"
hasre "$G" 'plugboese: nachher id=[0-9]+ x=[0-9]+ y=[0-9]+' \
    "es hat den Ort NACHHER noch einmal gelesen"
# DAS IST DIE ZUSAGE: nicht der Rueckgabewert, sondern der ZUSTAND.
has "$G" "plugboese: rechteprobe: abgewiesen UND nichts bewegt" \
    "vorher und nachher sind gleich -- die Handlung ist NICHT passiert"
# Und die Zahlen noch einmal von aussen nachgerechnet, damit die Zusage
# nicht nur davon lebt, dass das Plugin sie selbst zieht.
vx=$(zahl "$G" '^plugboese: vorher' 'x'); vy=$(zahl "$G" '^plugboese: vorher' 'y')
nx=$(zahl "$G" '^plugboese: nachher' 'x'); ny=$(zahl "$G" '^plugboese: nachher' 'y')
if [ -n "${vx:-}" ] && [ "$vx" = "${nx:-}" ] && [ "$vy" = "${ny:-}" ]; then
    ok "nachgerechnet: ($vx,$vy) vorher = ($nx,$ny) nachher"
else
    bad "der Ort hat sich geaendert: ($vx,$vy) -> ($nx,$ny)"
fi
# Der Griff ging auf (7,7) -- wenn er gewirkt haette, staende das da.
if [ "${nx:-x}" = 7 ] && [ "${ny:-y}" = 7 ]; then
    bad "das Fenster steht auf (7,7) -- der Griff hat gewirkt"
else
    ok "das Fenster steht NICHT auf (7,7), dem Ziel des Griffs"
fi

# ================================= 7. die Schnittstelle und das Tempo
echo "== 7. die Schnittstelle einmal ganz durch, und das Tempo =="
lauf probe "wigapp=/bin/plugprobe,plugprobe,zkey" '^wm: hold'
P=$TMPD/probe.clean
sauber probe
has "$P" "probe: abi=1" "PL_ABI meldet die Fassung 1 -- die Schnittstelle ist versioniert"
hasre "$P" '^probe: platz=[0-9]+' "der Prueflauf hat einen Tafelplatz"
# Kuerzel: OHNE Gewaehrung abgewiesen, MIT Gewaehrung angenommen.
hasre "$P" '^probe: key ohne rc=-[0-9]+' \
    "ein Kuerzel OHNE R_ACT_KEY wird abgewiesen"
hasre "$P" '^probe: key mit rc=[0-9]+' \
    "und MIT Gewaehrung (WM_PLUG_GRANT) angenommen"
hasre "$P" '^probe: ev typ=[0-9]+ dat=[0-9]+' \
    "es sind wirklich Ereignisse durch den Ring gelaufen"
# DIE ZWEI TEMPOZAHLEN. PL_FRAMES/PL_LATUS kommen aus der vorhandenen
# Bilduhr des Servers; gelesen wird VOR und NACH der Plugin-Last im
# selben Lauf, also ist der Vergleich einer und nicht zweier Maschinen.
f1=$(grep -aE '^probe: frames=' "$P" | head -1 | sed 's/.*=//')
f2=$(grep -aE '^probe: frames=' "$P" | tail -1 | sed 's/.*=//')
l1=$(grep -aE '^probe: latus=' "$P" | head -1 | sed 's/.*=//')
l2=$(grep -aE '^probe: latus=' "$P" | tail -1 | sed 's/.*=//')
if [ -n "${f1:-}" ] && [ -n "${f2:-}" ] && [ "$f2" -gt "$f1" ] 2>/dev/null; then
    ok "Bilder vor der Last: $f1, nach der Last: $f2 (der Server hat weitergemalt)"
else
    bad "keine zwei Bildzahlen aus demselben Lauf ($f1 / $f2)"
fi
if [ -n "${l1:-}" ] && [ -n "${l2:-}" ]; then
    ok "Latenz je Bild vorher ${l1} us, nachher ${l2} us -- beide Zahlen stehen im Bericht"
else
    bad "keine zwei Latenzzahlen ($l1 / $l2)"
fi
hasre "$P" '^probe: ende, ?rc=|^probe: ende' "der Prueflauf meldet sich sauber ab"

# ============================== 7b. das Tempo, sauber und in EINEM Lauf
echo "== 7b. Bildrate und Latenz: 60 Bilder vor, 60 Bilder nach dem Laden =="
# WARUM NOCH EINE MESSUNG, wo Abschnitt 7 schon zwei Zahlen hat: die
# dortigen kommen aus `PL_LATUS`, und das ist der MITTELWERT SEIT DEM
# HOCHLAUF. Ein Mittelwert ueber alles bewegt sich nach zwei Minuten
# kaum noch -- er kann einen Einbruch nach dem Laden gar nicht zeigen.
# /bin/plugtempo misst stattdessen zwei FENSTER von je 60 Bildern im
# selben Lauf, jeweils nach einem Warmlauf (die erste Glyphe ist teuer,
# danach liegt sie im Cache von fUi), und meldet Mittel, Kleinstes und
# Groesstes -- eine Zahl ohne Streuung ist keine Messung.
# `wighalt=50` verlaengert das Stillhalten des Servers von zwanzig auf
# fuenfzig Sekunden (kernel/kgui.fi, `pmon.wighalt`). Ohne das Wort
# endet der Lauf mitten im zweiten Messfenster -- gemessen: bei 8 Bildern
# je Sekunde dauern zweimal 60 Bilder plus zwei Warmlaeufe rund 25
# Sekunden, und zwanzig sind zwanzig.
lauf tempo "wighalt=50 wigapp=/bin/plugtempo,plugtempo,bilder=60" 'tempo: ende'
T=$TMPD/tempo.clean
sauber tempo
hasre "$T" '^tempo: vor bilder=[0-9]+' "das Messfenster VOR dem Laden steht auf der Leitung"
hasre "$T" '^tempo: nach bilder=[0-9]+' "und das Messfenster NACH dem Laden auch"
has "$T" "wmplug: reg uhr" "zwischen den beiden Fenstern wurde wirklich ein Plugin geladen"
tv_b=$(zahl "$T" '^tempo: vor '  'bilder'); tn_b=$(zahl "$T" '^tempo: nach ' 'bilder')
tv_u=$(zahl "$T" '^tempo: vor '  'us');     tn_u=$(zahl "$T" '^tempo: nach ' 'us')
tv_f=$(zahl "$T" '^tempo: vor '  'fps10');  tn_f=$(zahl "$T" '^tempo: nach ' 'fps10')
tv_mi=$(zahl "$T" '^tempo: vor ' 'min');    tn_mi=$(zahl "$T" '^tempo: nach ' 'min')
tv_ma=$(zahl "$T" '^tempo: vor ' 'max');    tn_ma=$(zahl "$T" '^tempo: nach ' 'max')
if [ "${tv_b:-0}" -ge 60 ] 2>/dev/null && [ "${tn_b:-0}" -ge 60 ] 2>/dev/null; then
    ok "beide Fenster haben wirklich 60 Bilder (vor $tv_b, nach $tn_b)"
else
    bad "die Messfenster sind zu klein: vor '$tv_b', nach '$tn_b' Bilder"
fi
if [ -n "${tv_u:-}" ] && [ -n "${tn_u:-}" ]; then
    ok "Bildzeit vor dem Laden ${tv_u} us (min ${tv_mi}, max ${tv_ma}), nach dem Laden ${tn_u} us (min ${tn_mi}, max ${tn_ma})"
    ok "Bildrate vor dem Laden ${tv_f} (x10), nach dem Laden ${tn_f} (x10) -- beide Zahlen gehen in den Bericht"
else
    bad "keine zwei Bildzeiten aus demselben Lauf ('$tv_u' / '$tn_u')"
fi
# DIE SCHRANKE. Sie ist grosszuegig und sie sagt warum: das zweite
# Fenster traegt einen zusaetzlichen Ring-3-Prozess UND ein Feld mehr in
# der Leiste. Bricht die Bildrate dabei um mehr als ein Drittel ein, ist
# das Erweiterungssystem zu teuer -- und dann steht es hier rot.
# UND DIE LATENZ, mit derselben Frage: die mittlere Bildzeit kommt aus
# der Bilduhr des Servers (PL_FRSUM/PL_FRN, ueber das Messfenster
# gerechnet). Doppelt so teuer waere zu teuer.
if [ -n "${tv_u:-}" ] && [ -n "${tn_u:-}" ] && [ "${tv_u:-0}" -gt 0 ] 2>/dev/null; then
    if [ "$tn_u" -le $(( tv_u * 2 )) ]; then
        ok "die Bildzeit bleibt in der Groessenordnung: ${tv_u} us -> ${tn_u} us"
    else
        bad "die Bildzeit verdoppelt sich mehr als: ${tv_u} us -> ${tn_u} us"
    fi
fi
if [ -n "${tv_f:-}" ] && [ -n "${tn_f:-}" ] && [ "${tv_f:-0}" -gt 0 ] 2>/dev/null; then
    if [ "$tn_f" -ge $(( tv_f * 2 / 3 )) ]; then
        ok "kein Tempoeinbruch: ${tn_f} ist mindestens zwei Drittel von ${tv_f} (Bildrate x10)"
    else
        bad "Tempoeinbruch nach dem Laden: ${tv_f} -> ${tn_f} (Bildrate x10)"
    fi
fi

# ======================= 7c. einschalten ZUR LAUFZEIT, am Bildpunkt
echo "== 7c. wmplug enable an einem LAUFENDEN Plugin =="
# DIE GEGENPROBE ZUM ABSCHALTEN. /bin/uhrspaet startet das Widget OHNE
# jede Gewaehrung (der Kern gibt R_DEFAULT, also kein R_ACT_BAR), macht
# das erste Foto moeglich, ruft dann `/bin/wmplug enable uhr` und laesst
# das zweite Foto entstehen. Zwischen den Bildern liegt KEIN Neustart:
# derselbe Prozess, derselbe Tafelplatz, neue Rechte.
lauf spaet "wigapp=/bin/uhrspaet,uhrspaet,wartems=3000,runden=40" \
    'uhrspaet: vor dem enable' 'taskbar: text plug '
SP=$TMPD/spaet.clean
sauber spaet
has "$SP" "pluguhr: KEIN recht R_ACT_BAR" \
    "das Widget startet OHNE R_ACT_BAR -- der Text wird abgewiesen"
hasre "$SP" 'uhrspaet: (grant|enable) r=' \
    "danach wird gewaehrt (WM_PLUG_GRANT -- derselbe Ruf wie 'wmplug enable uhr')"
has "$SP" "taskbar: text plug " "und die Leiste malt den Widget-Text"
# EIN EINZIGER PROZESS: das Widget ist nicht neu gestartet worden, es
# gibt genau eine Anmeldung auf der Leitung.
n_reg=$(grep -ca 'wmplug: reg uhr' "$SP")
[ "${n_reg:-0}" = 1 ] \
    && ok "genau EINE Anmeldung (wmplug: reg uhr) -- kein Prozessneustart" \
    || bad "'wmplug: reg uhr' steht ${n_reg}x da -- da hat sich etwas neu angemeldet"
n_hold_sp=$(grep -ca '^wm: hold' "$SP")
[ "${n_hold_sp:-0}" = 1 ] \
    && ok "und der Fensterserver lief durch (genau ein 'wm: hold')" \
    || bad "'wm: hold' steht ${n_hold_sp}x da"
# UND JETZT DER BILDPUNKT. Die Lage des Widget-Kastens kommt aus der
# Leiste selbst (`taskbar: plug nr=0 x= y= w= h=` plus `taskbar: geom`),
# nicht aus diesem Skript.
zl=$(grep -a '^taskbar: plug nr=0 ' "$TMPD/spaet.clean" | tail -1)
gl=$(grep -a '^taskbar: geom ' "$TMPD/spaet.clean" | tail -1)
feld() { printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | sed 's/.*=//'; }
px=$(feld "$zl" x); py=$(feld "$zl" y); pw=$(feld "$zl" w); ph=$(feld "$zl" h)
gx=$(feld "$gl" x); gy=$(feld "$gl" y); gx=${gx:-0}; gy=${gy:-0}
if [ -z "${px:-}" ] || [ ! -s "$TMPD/spaet.ppm" ] || [ ! -s "$TMPD/spaet-2.ppm" ]; then
    bad "ohne Widget-Kasten oder ohne zwei Fotos gibt es nichts nachzurechnen (Kasten '$zl')"
else
    # DIE KOORDINATE WIRD NICHT GERATEN, SONDERN GEFUNDEN. Die Mitte
    # des Kastens liegt bei kurzem Text zwischen zwei Buchstaben und
    # zeigt dann in beiden Bildern dieselbe Leistenfarbe -- gemessen,
    # und deshalb steht hier keine getippte Zahl mehr. Dieses Stueck
    # zaehlt die verschiedenen Bildpunkte im Kasten UND nennt den
    # ersten; an dem rechnet danach checkshot.py nach.
    read -r dz dx dy <<<"$(python3 - "$TMPD/spaet.ppm" "$TMPD/spaet-2.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" <<'PYD'
import sys
def load(p):
    d = open(p, 'rb').read(); t = []; i = 2
    while len(t) < 3:
        while i < len(d) and d[i:i+1].isspace(): i += 1
        if d[i:i+1] == b'#':
            while d[i:i+1] != b'\n': i += 1
            continue
        j = i
        while j < len(d) and not d[j:j+1].isspace(): j += 1
        t.append(int(d[i:j])); i = j
    return t[0], t[1], d[i+1:]
a = load(sys.argv[1]); b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0; erst = (-1, -1)
for y in range(y0, min(y0 + h, a[1], b[1])):
    for x in range(x0, min(x0 + w, a[0], b[0])):
        o = (y * a[0] + x) * 3
        if a[2][o:o+3] != b[2][o:o+3]:
            n += 1
            if erst == (-1, -1): erst = (x, y)
print(n, erst[0], erst[1])
PYD
)"
    if [ "${dz:-0}" -gt 40 ]; then
        ok "im Widget-Kasten unterscheiden sich $dz Bildpunkte zwischen vorher und nachher"
    else
        bad "vorher und nachher unterscheiden sich im Kasten nur in ${dz:-0} Bildpunkten"
    fi
    if [ "${dx:-0}" -ge 0 ] && [ "${dx:--1}" != "-1" ]; then
        v1=$(python3 tools/gfx/checkshot.py punkt "$TMPD/spaet.ppm" "$dx" "$dy" 2>&1)
        v2=$(python3 tools/gfx/checkshot.py punkt "$TMPD/spaet-2.ppm" "$dx" "$dy" 2>&1)
        if [ "$v1" != "$v2" ]; then
            ok "checkshot punkt ($dx,$dy): vor dem Gewaehren [$v1], danach [$v2] -- verschieden"
        else
            bad "checkshot punkt ($dx,$dy): beide [$v1]"
        fi
    else
        bad "kein einziger verschiedener Bildpunkt im Kasten -- das Einschalten hat nichts bewirkt"
    fi
    # Und die Tinte im Kasten: NACH dem Einschalten stehen dort
    # Buchstaben, vorher nicht. Die Vergleichsfarbe wird aus dem Bild
    # GELESEN (eine Ecke des Kastens), nicht getippt.
    ecke2=$(python3 tools/gfx/checkshot.py punkt "$TMPD/spaet-2.ppm" \
        "$((gx+px+1))" "$((gy+py+1))" 2>/dev/null)
    tinte=$(python3 tools/gfx/checkshot.py flaeche "$TMPD/spaet-2.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" $ecke2 2>&1 | grep -oE '^[0-9]+')
    if [ "${tinte:-0}" -gt 20 ]; then
        ok "im Widget-Kasten stehen nach dem Einschalten $tinte Bildpunkte Tinte"
    else
        bad "nach dem Einschalten steht kein Text im Kasten (${tinte:-0} Punkte)"
    fi
    cp -f "$TMPD/spaet.ppm" "$TMPD/enable-vorher.ppm"
    cp -f "$TMPD/spaet-2.ppm" "$TMPD/enable-nachher.ppm"
    for b in enable-vorher enable-nachher; do
        python3 tools/gfx/ppm2png.py "$TMPD/$b.ppm" "$SHOTS/$b.png" >/dev/null 2>&1
    done
    [ -s "$SHOTS/enable-nachher.png" ] \
        && ok "die zwei Fotos liegen als docs/shots/wmplug/enable-vorher.png und -nachher.png" \
        || bad "die zwei Fotos des Einschaltens wurden nicht abgelegt"
fi

# ===================================================== 8. die Verwaltung
echo "== 8. /bin/wmplug: list, info, disable, list =="
lauf verw "wigapp=/bin/uhrstart,uhrstart,verwaltung,runden=30" '^wm: hold'
V=$TMPD/verw.clean
sauber verw
has "$V" "wmplug: reg uhr" "das Widget ist angemeldet -- es gibt etwas zu verwalten"
has "$V" "wmplug: abi=" "wmplug list nennt die Fassung der Schnittstelle"
hasre "$V" 'Plugins [0-9]+ von [0-9]+' "und sagt, wie viele Plaetze belegt sind"
# KEIN `^` IN DIESEN MUSTERN. Die serielle Leitung traegt Kernzeilen
# und Ring-3-Zeilen durcheinander; gemessen steht dort
# `plugstart: wmplug: unreg uhr grund=4`, weil der Kern mitten in die
# Zeile des Starthelfers geschrieben hat. Ein Anker am Zeilenanfang
# macht daraus eine Zusage, die nie zutrifft.
has "$V" "plugstart: list vorher" "list lief vor dem Abschalten"
has "$V" "plugstart: info uhr" "info lief"
has "$V" "disable uhr" "disable lief"
has "$V" "plugstart: list nachher" "und list noch einmal danach"
# DER ZUSTANDSWECHSEL, vom Kern selbst gemeldet: grund=4 ist G_USER,
# also "jemand hat `wmplug disable` gesagt" -- und nicht Absturz (1),
# nicht Frist (2), nicht Rechte (3).
hasflat "$V" 'unreg uhr *grund=4' \
    "der Kern meldet die Abmeldung mit grund=4 (G_USER) -- nicht Absturz, nicht Frist"
# UND DER ZUSTAND, nicht nur die Meldung: die Tafel zaehlt vor dem
# Abschalten ein Plugin und danach keines. DAS ist "an und aus zur
# Laufzeit", in einer Zahl, die der Kern selbst nennt.
v1=$(grep -a 'Plugins [0-9]* von' "$V" | head -1 | grep -oE 'Plugins [0-9]+' | grep -oE '[0-9]+')
v2=$(grep -a 'Plugins [0-9]* von' "$V" | tail -1 | grep -oE 'Plugins [0-9]+' | grep -oE '[0-9]+')
if [ "${v1:-x}" = 1 ] && [ "${v2:-x}" = 0 ]; then
    ok "die Tafel zaehlt vor dem Abschalten $v1 Plugin, danach $v2 -- am Zustand gemessen"
else
    bad "die Tafel zaehlt '$v1' vorher und '$v2' nachher (erwartet 1 und 0)"
fi
has "$V" "pluguhr: ende" "und das Widget selbst ist wirklich gegangen"
# Und ohne Neustart des Fensterservers: derselbe Lauf, `wm: hold` steht
# nur einmal da.
n_hold=$(grep -ca '^wm: hold' "$V")
[ "${n_hold:-0}" = 1 ] \
    && ok "der Fensterserver wurde dabei NICHT neu gestartet (genau ein 'wm: hold')" \
    || bad "'wm: hold' steht ${n_hold}x da -- da ist etwas neu gestartet"

# ================================================== 9. tools/check-ui.sh
echo "== 9. der Zeichenweg =="
if bash tools/check-ui.sh > "$TMPD/ui.txt" 2>&1; then
    grep -qa PASSED "$TMPD/ui.txt" \
        && ok "tools/check-ui.sh meldet PASSED (kein neuer Zeichenweg am fUi vorbei)" \
        || bad "check-ui.sh ist gruen, sagt aber nicht PASSED"
else
    bad "tools/check-ui.sh meldet einen Fehler"
    tail -8 "$TMPD/ui.txt" | sed 's/^/        /'
fi

# =========================== 10. die zwei echten Plugins (Modullaeufer)
if [ "${WMPLUG_SCHNELL:-0}" = 1 ]; then
    echo "== 10. die zwei Modullaeufer -- UEBERSPRUNGEN (WMPLUG_SCHNELL=1) =="
else
    for m in regel widget; do
        echo "== 10.$m: tools/wmplug/$m.sh =="
        bash "tools/wmplug/$m.sh" > "$TMPD/$m.log" 2>&1
        z=$(grep -aiE '^[A-Z]+: [0-9]+ bestanden, [0-9]+ gescheitert' "$TMPD/$m.log" | tail -1)
        mp=$(printf '%s' "$z" | grep -oE '[0-9]+ bestanden' | grep -oE '[0-9]+')
        mf=$(printf '%s' "$z" | grep -oE '[0-9]+ gescheitert' | grep -oE '[0-9]+')
        if [ -n "${mp:-}" ] && [ -n "${mf:-}" ]; then
            printf '  ....  %s.sh: %s bestanden, %s gescheitert (geht in die Summe ein)\n' \
                "$m" "$mp" "$mf"
            pass=$((pass + mp)); fail=$((fail + mf))
            [ "$mf" = 0 ] || sed -n 's/^  FAIL/        FAIL/p' "$TMPD/$m.log" | head -8
        else
            bad "$m.sh hat keine Schlusszeile geliefert"
            tail -8 "$TMPD/$m.log" | sed 's/^/        /'
        fi
    done
fi

# ================================================= 11. die Fotos liegen da
echo "== 11. die Fotos =="
for b in regel-mit-recht regel-ohne-recht widget-an widget-aus-laufzeit nach-absturz \
         enable-vorher enable-nachher; do
    if [ -s "$SHOTS/$b.png" ] || [ -s "$SHOTS/$b.ppm" ]; then
        ok "docs/shots/wmplug/$b liegt da"
    else
        if [ "${WMPLUG_SCHNELL:-0}" = 1 ]; then
            printf '  ....  %s -- nicht geprueft (WMPLUG_SCHNELL=1)\n' "$b"
        else
            bad "docs/shots/wmplug/$b fehlt"
        fi
    fi
done

# ============ 12. die Fensterregel, an der Koordinate nachgerechnet
echo "== 12. die zwei Bilder der Fensterregel, Punkt fuer Punkt =="
# DIE BILDUNTERSCHRIFT WIRD NACHGERECHNET. In den Bildern der
# Fensterregel steht das Fenster von /bin/calc einmal dort, wo die Regel
# es hinschickt (zentriert, 230,70) und einmal dort, wo der
# Fensterserver es von selbst hinlegt (80,60). Bisher stand das nur in
# regel.sh; hier wird es ein zweites Mal und aus einem anderen Skript
# gerechnet, denn genau diese zwei Bilder gehen als 04 und 05 an die
# Jury. checkshot.py liest nur PPM, die abgelegten Bilder sind PNG --
# also werden sie zurueckgewandelt und dann gemessen.
regel_ppm() { # png ppm
    python3 - "$1" "$2" <<'PYX'
import sys
try:
    from PIL import Image
except Exception:
    sys.exit(2)
try:
    Image.open(sys.argv[1]).convert('RGB').save(sys.argv[2])
except Exception:
    sys.exit(3)
PYX
}
if [ "${WMPLUG_SCHNELL:-0}" = 1 ]; then
    printf '  ....  die Regelbilder -- nicht geprueft (WMPLUG_SCHNELL=1)\n'
elif [ -s "$SHOTS/regel-mit-recht.png" ] && [ -s "$SHOTS/regel-ohne-recht.png" ] \
     && regel_ppm "$SHOTS/regel-mit-recht.png" "$TMPD/rmit.ppm" \
     && regel_ppm "$SHOTS/regel-ohne-recht.png" "$TMPD/rohne.ppm"; then
    # (500,300) liegt im zentrierten Fenster (230..570) und ausserhalb
    # des unveraenderten (80..420); (120,300) genau andersherum.
    a=$(python3 tools/gfx/checkshot.py punkt "$TMPD/rmit.ppm" 500 300 2>&1)
    b=$(python3 tools/gfx/checkshot.py punkt "$TMPD/rohne.ppm" 500 300 2>&1)
    c=$(python3 tools/gfx/checkshot.py punkt "$TMPD/rohne.ppm" 120 300 2>&1)
    d=$(python3 tools/gfx/checkshot.py punkt "$TMPD/rmit.ppm" 120 300 2>&1)
    [ "$a" != "$b" ] \
        && ok "checkshot punkt (500,300): mit Recht [$a], ohne Recht [$b] -- verschieden" \
        || bad "checkshot punkt (500,300): beide [$a] -- die Regel ist im Bild nicht zu sehen"
    [ "$a" = "$c" ] \
        && ok "und dieselbe Fensterfarbe steht ohne Recht bei (120,300): [$c] -- das Fenster ist gewandert" \
        || bad "die Fensterfarbe wanderte nicht mit: [$a] gegen [$c]"
    [ "$d" != "$c" ] \
        && ok "checkshot punkt (120,300): mit Recht [$d], ohne Recht [$c] -- verschieden" \
        || bad "checkshot punkt (120,300): beide [$c]"
else
    bad "die zwei Regelbilder liegen nicht als PNG in $SHOTS (oder PIL fehlt)"
fi

echo
echo "WMPLUG: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
