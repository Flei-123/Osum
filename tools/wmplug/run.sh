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
       plugboese plugprobe plugregel pluguhr plugstart wmplug"
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
for sym in plugregel__ pluguhr__ plugboese__ plugprobe__; do
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
grep -qE '^boese[[:space:]]+rechte=0x0*1$' etc/wmplug.conf \
    && ok "/etc/wmplug.conf gibt 'boese' genau R_EV_WIN (0x001)" \
    || bad "'boese rechte=0x001' steht nicht mehr in /etc/wmplug.conf"

ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do
    n=$p; [ "$p" = plugstart ] && n=uhrstart
    ARGS+=("/bin/$n=$TMPD/$p.elf")
done
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme"
    "/etc/wmplug.conf=etc/wmplug.conf" "/etc/wmregeln.conf=etc/wmregeln.conf")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "das Abbild ist gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

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
    local name=$1 extra=$2 marke=${3:-}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock" "$TMPD/$name.ppm"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
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
    fi
    wait "$pid"; echo "$?" > "$TMPD/$name.rc"
    rm -f "$sock"
    tr -d '\000' < "$out" > "$TMPD/$name.clean"
}

sauber() { # name
    local rc; rc=$(cat "$TMPD/$1.rc" 2>/dev/null)
    [ "$rc" = 21 ] && ok "$1: der Kern beendet sich sauber (21)" \
        || bad "$1: Exitcode $rc statt 21"
}

# ========================================== 4. die Absturz-Gegenprobe
echo "== 4. Absturz: ein Plugin stuerzt ab (SIGSEGV) =="
lauf segv "wigapp=/bin/plugboese,boese,segv" '^wm: hold'
S=$TMPD/segv.clean
sauber segv
has "$S" "plugboese: abi=1" "das Plugin hat die Fassung erfragt"
hasre "$S" '^plugboese: platz=[0-9]+ rechte=31$' \
    "es ist angemeldet und hat R_DEFAULT (0x1F): alle Ereignisbits, KEIN Aktionsbit"
has "$S" "plugboese: gleich stuerze ich ab" "es sagt an, dass es gleich abstuerzt"
hasre "$S" 'wmplug: tot platz=[0-9]+ pid=[0-9]+' \
    "der Kern hat den Toten selbst abgeholt (reap)"
hasre "$S" 'wmplug: unreg boese *grund=1' \
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
else
    bad "kein Foto nach dem Absturz"
fi

# ============================================ 5. die Haenger-Gegenprobe
echo "== 5. Frist: ein Plugin haengt in der Endlosschleife =="
# `plugfrist` kuerzt die Frist des Kerns auf wenige Ticks, damit sie
# innerhalb eines Laufs wirklich reisst. Die Frist SELBST steht in
# kernel/wmplug.fi; dieses Wort setzt nur den Zeiger kuerzer.
lauf hang "plugfrist wigapp=/bin/plugboese,boese,hang" '^wm: hold'
H=$TMPD/hang.clean
sauber hang
has "$H" "plugboese: ab jetzt hole ich nichts" "das Plugin hoert auf abzuholen"
hasre "$H" 'wmplug: unreg boese *grund=2' \
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
lauf greif "wigapp=/bin/plugboese,boese,greif" '^wm: hold'
G=$TMPD/greif.clean
sauber greif
# R_DEFAULT (0x1F) ist das, was der KERN einem unbekannten Plugin gibt:
# zusehen, nichts anfassen. Die Zeile `boese rechte=0x001` in
# /etc/wmplug.conf ist noch enger und wuerde erst durch
# `wmplug enable boese` wirksam -- hier wird also der WEITERE der beiden
# Faelle gemessen, und selbst der hat kein einziges Aktionsbit.
hasre "$G" '^plugboese: platz=[0-9]+ rechte=31$' \
    "das Plugin hat R_DEFAULT (0x1F) und ausdruecklich KEIN R_ACT_WIN (0x100)"
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
hasre "$V" 'wmplug: unreg uhr *grund=4' \
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
for b in regel-mit-recht regel-ohne-recht widget-an widget-aus-laufzeit; do
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

echo
echo "WMPLUG: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
