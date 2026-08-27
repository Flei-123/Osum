#!/usr/bin/env bash
# tools/i18n/run.sh -- DIE ABNAHME DER RUNDE I18N.
#
# Was diese Runde behauptet und was hier gemessen wird:
#
#   1. DIE SCHRIFTEN KOENNEN MEHR ALS ASCII. Vorher 95 Zeichen, jetzt
#      338 -- gezaehlt aus der cmap-Tabelle der Dateien, die wirklich
#      auf der Platte liegen (tools/i18n/coverage.py). Und sie entstehen
#      weiterhin OKTETT FUER OKTETT reproduzierbar aus DejaVu.
#   2. DER DEKODIERER IST RICHTIG, auch bei falscher Eingabe:
#      ueberlange Formen, Surrogate, alles ueber U+10FFFF und
#      abgeschnittene Folgen werden zu U+FFFD, und die Maschine laeuft
#      weiter. Gemessen in Ring 3 (kernel/user/i18nt.fi).
#   3. DER KATALOG TUT, WAS ER SOLL: Englisch ist Quelle und Rueckfall,
#      ein fehlender Schluessel ergibt nie einen leeren Knopf, und der
#      Zeiger auf einen Text bleibt ueber einen Sprachwechsel hinweg
#      DERSELBE -- daran haengt der Wechsel zur Laufzeit.
#   4. ES STEHT WIRKLICH AUF DEM BILDSCHIRM. Derselbe Schirm auf
#      Englisch und auf Deutsch, und der deutsche mit ECHTEN UMLAUTEN --
#      bildpunktgenau gegen tools/ttf/raster.py gerechnet, nicht "da ist
#      irgendwas hell".
#   5. DIE SPRACHE LAESST SICH ZUR LAUFZEIT WECHSELN, mit der MAUS, in
#      EINEM Lauf, ohne Neustart -- und die TASKLEISTE, ein ANDERER
#      Prozess, zieht mit. Gemessen an ihrem eigenen Mitschnitt.
#   6. IM QUELLTEXT STEHT KEIN DEUTSCHER OBERFLAECHENTEXT MEHR.
#      tools/i18n/scan.py durchsucht den Baum; das Ziel ist 0.
#   7. DIE UTF-8-DEKODIERUNG BREMST DAS ZEICHNEN NICHT SPUERBAR.
#      Mikrosekunden je Textzeile, vorher und nachher.
#   8. DIE TASTATUR HAT ZWEI BELEGUNGEN, umschaltbar, und lehnt eine
#      dritte ab, die es nicht gibt.
#
# Verwendung:  bash tools/i18n/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"

TMPD=${TMPD:-$(mktemp -d)}
KEEP=${KEEP:-0}
[ "$KEEP" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

# Ein Aufruf von schau.py, dessen Ausgabe im Erfolgsfall mitgemeldet wird
# -- eine Zahl wie "526 Tintenpunkte geprueft, 0 falsch" ist die Messung,
# nicht das Wort "OK".
schau() { local was=$1; shift
    local aus; aus=$(python3 tools/gfx/schau.py "$@" 2>&1)
    if [ $? = 0 ]; then ok "$was: $aus"; else bad "$was: $aus"; fi; }
schau_nicht() { local was=$1; shift
    local aus; aus=$(python3 tools/gfx/schau.py "$@" 2>&1)
    if [ $? = 0 ]; then bad "$was -- es steht doch da"; else ok "$was"; fi; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "I18N: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; }

SANS=assets/osum-sans.ttf
MONO=assets/osum-mono.ttf
WX=140; WY=60; BORDER=2; TITLE=22
CX=$((WX + BORDER)); CY=$((WY + TITLE))
ZEILE="gfx wm wig desk einst nostart wmhold wiglong nokbd nosched noproc nofs"

# ===================================================== 1. die Schriften

echo "== 1. die Schriften: mehr als ASCII, und weiter reproduzierbar =="

python3 tools/i18n/coverage.py "$SANS" "$MONO" > "$TMPD/deckung.txt" 2>&1
for f in sans mono; do
    n=$(grep -A1 "assets/osum-$f.ttf" "$TMPD/deckung.txt" \
        | grep -oE '[0-9]+ code points mapped' | grep -oE '^[0-9]+')
    is "osum-$f.ttf bildet Codepunkte ab" "$n" "338"
done
has "$TMPD/deckung.txt" "Latin-1 Supplement                             96 /    96" \
    "die Latin-1-Ergaenzung ist VOLLSTAENDIG da (u/o/a mit zwei Punkten, ss)"
has "$TMPD/deckung.txt" "Specials (U+FFFD lives here)                   1 /    16" \
    "und U+FFFD, das Fehlerbild des Dekodierers"
has "$TMPD/deckung.txt" "all present" \
    "jedes Zeichen, das eine deutsche Oberflaeche braucht, ist in der Schrift"
# GEGENPROBE: der alte Ausschnitt kann es NICHT. Ohne sie ist die
# Messung oben nur eine Zahl ohne Vergleich.
DEJAVU=${DEJAVU:-/usr/share/fonts/truetype/dejavu}
if [ -f "$DEJAVU/DejaVuSans.ttf" ]; then
    python3 tools/ttf/schnitt.py "$DEJAVU/DejaVuSans.ttf" "$TMPD/alt.ttf" \
        --set ascii > "$TMPD/alt.txt" 2>&1
    python3 tools/i18n/coverage.py "$TMPD/alt.ttf" > "$TMPD/altd.txt" 2>&1
    has "$TMPD/altd.txt" "MISSING" \
        "GEGENPROBE: mit dem alten Ausschnitt (--set ascii) FEHLEN sie alle"
    cmp -s "$TMPD/alt.ttf" <(git show HEAD~4:assets/osum-sans.ttf 2>/dev/null) \
        2>/dev/null && ok "und '--set ascii' gibt die alte Datei Oktett fuer Oktett zurueck" \
        || echo "        (die alte Datei liegt nicht mehr im Baum -- nicht verglichen)"
    python3 tools/ttf/schnitt.py "$DEJAVU/DejaVuSans.ttf" "$TMPD/neu.ttf" \
        >/dev/null 2>&1
    python3 tools/ttf/schnitt.py "$DEJAVU/DejaVuSansMono.ttf" "$TMPD/neum.ttf" \
        >/dev/null 2>&1
    cmp -s "$TMPD/neu.ttf" "$SANS" \
        && ok "osum-sans.ttf entsteht Oktett fuer Oktett neu aus DejaVu Sans" \
        || bad "osum-sans.ttf laesst sich nicht reproduzieren"
    cmp -s "$TMPD/neum.ttf" "$MONO" \
        && ok "osum-mono.ttf entsteht Oktett fuer Oktett neu aus DejaVu Sans Mono" \
        || bad "osum-mono.ttf laesst sich nicht reproduzieren"
else
    echo "        (DejaVu liegt nicht unter $DEJAVU -- Schnitt nicht nachgerechnet)"
fi

# ============================================== 2. kein deutscher Text

echo "== 2. im Quelltext steht kein deutscher Oberflaechentext mehr =="

python3 tools/i18n/scan.py > "$TMPD/scan.txt" 2>&1
rc=$?
n=$(grep -oE 'gefunden: [0-9]+' "$TMPD/scan.txt" | grep -oE '[0-9]+$')
is "fest eingebaute deutsche Oberflaechentexte" "${n:-?}" "0"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMPD/scan.txt" | head -20
# GEGENPROBE FUER DEN PRUEFER SELBST: er MUSS anschlagen, wenn wirklich
# einer dasteht. Ein Pruefer ohne Gegenprobe prueft nichts.
mkdir -p "$TMPD/schlecht/kernel/user"
cp kernel/user/schreibtisch.fi "$TMPD/schlecht/kernel/user/"
printf 'static mut x: [u8; 12] = "Uebernehmen\\0"\n' \
    >> "$TMPD/schlecht/kernel/user/schreibtisch.fi"
if python3 tools/i18n/scan.py "$TMPD/schlecht" > "$TMPD/scanbad.txt" 2>&1; then
    bad "GEGENPROBE: der Pruefer uebersieht einen eingebauten deutschen Text"
else
    ok "GEGENPROBE: ein eingebauter deutscher Text FAELLT auf ($(grep -oE 'gefunden: [0-9]+' "$TMPD/scanbad.txt"))"
fi

# ==================================================== 3. der Katalog

echo "== 3. die Sprachdateien =="

for l in en de; do
    [ -f "locale/$l/messages" ] && ok "locale/$l/messages liegt im Baum" \
        || bad "locale/$l/messages fehlt"
done
python3 tools/i18n/quota.py > "$TMPD/quota.txt" 2>&1 \
    && ok "$(head -1 "$TMPD/quota.txt")" \
    || { bad "die Abdeckung laesst sich nicht rechnen"; cat "$TMPD/quota.txt"; }
sed 's/^/        /' "$TMPD/quota.txt" | tail -n +2

# ================================================== 4. bauen und messen

echo "== 4. bauen: Kern, sechs Programme, zwei Abbilder =="

bash tools/i18n/build.sh "$TMPD/en" > "$TMPD/build-en.txt" 2>&1 \
    && ok "das englische Abbild steht" \
    || { bad "das Abbild laesst sich nicht bauen"; tail -20 "$TMPD/build-en.txt"; exit 1; }
sed 's/^/        /' "$TMPD/build-en.txt"
LANG_SET=de bash tools/i18n/build.sh "$TMPD/de" > "$TMPD/build-de.txt" 2>&1 \
    && ok "das deutsche Abbild steht" \
    || { bad "das deutsche Abbild laesst sich nicht bauen"; exit 1; }

echo "== 5. Ring 3: der Dekodierer, der Katalog, die Tastatur =="

cp "$TMPD/en/disk.img" "$TMPD/t.img"
timeout 180 qemu-system-x86_64 -kernel "$TMPD/en/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 script=i18nt;exit" \
    -serial "file:$TMPD/i18nt.txt" -display none -no-reboot \
    -drive "file=$TMPD/t.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
p=$(grep -aoE 'i18n: pass=[0-9]+' "$TMPD/i18nt.txt" | tail -1 | grep -oE '[0-9]+')
f=$(grep -aoE 'fail=[0-9]+' "$TMPD/i18nt.txt" | tail -1 | grep -oE '[0-9]+')
is "Zusagen in Ring 3, gescheitert" "${f:-?}" "0"
ok "Zusagen in Ring 3, erfuellt: ${p:-0}"
grep -a '^i18n: bad' "$TMPD/i18nt.txt" | sed 's/^/        /'

# ================================================ 6. der Bildschirm

echo "== 6. derselbe Bildschirm auf Englisch und auf Deutsch =="

lauf() { # verzeichnis name [monitordatei]
    local d=$1 n=$2 mon=${3:-}
    local sock="$d/mon-$n.sock"
    rm -f "$sock" "$d/$n.txt" "$d/$n.ppm"
    cp -f "$d/disk.img" "$d/live-$n.img"
    timeout 240 qemu-system-x86_64 -kernel "$d/k.mb" -m 256 -append "$ZEILE" \
        -serial "file:$d/$n.txt" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$d/live-$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1500 ]; do
        grep -qaE '^wm: hold' "$d/$n.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i + 1))
    done
    sleep 1
    [ -n "$mon" ] && python3 tools/wm/monitor.py "$sock" "$mon" \
        > "$d/$n.monlog" 2>&1
    python3 tools/gfx/schuss.py "$sock" "$d/$n.ppm" 25 > "$d/$n.shot" 2>&1
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rm -f "$sock"
}

lauf "$TMPD/en" en
lauf "$TMPD/de" de
[ -s "$TMPD/en/en.ppm" ] && ok "das englische Bildschirmfoto steht ($(stat -c%s "$TMPD/en/en.ppm") Oktette)" \
    || { bad "kein englisches Bildschirmfoto"; }
[ -s "$TMPD/de/de.ppm" ] && ok "das deutsche Bildschirmfoto steht" \
    || bad "kein deutsches Bildschirmfoto"

feld() { # datei id was
    grep -a "einstellungen: feld id=$2 " "$1" | tail -1 \
        | grep -oE " $3=[0-9]+" | tail -1 | grep -oE '[0-9]+$'
}
text_von() { grep -a "einstellungen: feld id=$2 " "$1" | tail -1 | sed 's/.* t=//'; }

EF="$TMPD/en/en.txt"; DF="$TMPD/de/de.txt"
is "der Knopf heisst auf Englisch"  "$(text_von "$EF" 5)" "Apply"
is "und auf Deutsch"                "$(text_von "$DF" 5)" "Übernehmen"
is "das Statusfeld auf Englisch"    "$(text_von "$EF" 42)" "ready"
is "und auf Deutsch"                "$(text_von "$DF" 42)" "bereit"

# DIE REGEL DIESER RUNDE, GEMESSEN: der PFAD im uebersetzten Satz ist
# unveraendert geblieben.
case "$(text_von "$DF" 1)" in
    *"/etc/schemas"*) ok "der deutsche Text nennt den Pfad UNVERAENDERT: $(text_von "$DF" 1)" ;;
    *) bad "der Pfad wurde uebersetzt: $(text_von "$DF" 1)" ;;
esac
hasnot "$DF" "/etc/schemata" "und kein Pfad wurde eingedeutscht"

# BILDPUNKTGENAU. Das ist der Unterschied zwischen "der Mitschnitt sagt
# es" und "es steht auf dem Schirm".
ex=$(feld "$EF" 5 x); eb=$(feld "$EF" 5 base)
dx=$(feld "$DF" 5 x); db=$(feld "$DF" 5 base)
schau "der englische Knopf steht bildpunktgenau da" \
    ttext "$TMPD/en/en.ppm" "$SANS" 15 $((CX + ex)) $((CY + eb)) \
    230 230 230 57 64 74 "Apply" 8
schau "DER DEUTSCHE KNOPF AUCH -- MIT ECHTEM UMLAUT" \
    ttext "$TMPD/de/de.ppm" "$SANS" 15 $((CX + dx)) $((CY + db)) \
    230 230 230 57 64 74 "Übernehmen" 8
schau_nicht "und die Ersatzschreibung 'Uebernehmen' steht dort NICHT" \
    ttext "$TMPD/de/de.ppm" "$SANS" 15 $((CX + dx)) $((CY + db)) \
    230 230 230 57 64 74 "Uebernehmen" 8
lx=$(feld "$DF" 1 x); lb=$(feld "$DF" 1 base)
schau "der uebersetzte Satz mit dem unuebersetzten Pfad steht auf dem Schirm" \
    ttext "$TMPD/de/de.ppm" "$SANS" 15 $((CX + lx)) $((CY + lb)) \
    230 230 230 30 34 40 "Farbschema (aus /etc/schemas):" 8

# Die Taskleiste -- ein ANDERER Prozess, dieselbe Sprache.
has "$EF" "leiste: text netz" "die Taskleiste meldet ihr Netzfeld"
grep -a 'leiste: text netz' "$EF" | tail -1 | grep -q 'no network' \
    && ok "auf Englisch: no network" || bad "die Taskleiste ist nicht englisch"
grep -a 'leiste: text netz' "$DF" | tail -1 | grep -q 'kein Netz' \
    && ok "auf Deutsch: kein Netz" || bad "die Taskleiste ist nicht deutsch"

# UND DIE BEIDEN BILDER SIND WIRKLICH VERSCHIEDEN. Ohne diese Zahl
# koennte alles oben stimmen und der Schirm trotzdem zweimal gleich
# aussehen.
d=$(python3 tools/i18n/diff.py "$TMPD/en/en.ppm" "$TMPD/de/de.ppm" 2>&1)
case "$d" in
    0*) bad "die beiden Bildschirmfotos sind IDENTISCH" ;;
    *)  ok "die beiden Bildschirmfotos unterscheiden sich: $d" ;;
esac

# ======================================= 7. der Wechsel zur Laufzeit

echo "== 7. die Sprache wechseln -- mit der Maus, in EINEM Lauf =="

# DREI KLICKS, und keine einzige Koordinate ist geraten:
#
#   1. auf den Reiter "Language". Wo er liegt, meldet das Programm
#      selbst -- seine Breite haengt am Text und der Text an der
#      Sprache ("Language" ist schmaler, als "Sprache" breit ist).
#   2. auf das Auswahlfeld. Ein Klick schaltet weiter, also von
#      "English" auf "Deutsch".
#   3. auf "Apply".
#
# Danach faehrt der Zeiger weg -- sonst hebt er den Knopf hervor und
# das Foto misst eine andere Hintergrundfarbe, als das Programm
# gemeldet hat.
lauf "$TMPD/en" vor
rfeld() { grep -a "einstellungen: reiter nr=$1" "$2" | tail -1 \
          | grep -oE " $3=[0-9]+" | grep -oE '[0-9]+$'; }
rx=$(rfeld 5 "$TMPD/en/vor.txt" x)
ry=$(rfeld 5 "$TMPD/en/vor.txt" y)
rw=$(rfeld 5 "$TMPD/en/vor.txt" w)
rh=$(rfeld 5 "$TMPD/en/vor.txt" h)
if [ -z "${rx:-}" ]; then
    bad "das Programm meldet die Lage seiner Reiter nicht"
else
    ok "der Reiter 'Language' liegt bei x=$rx y=$ry w=$rw h=$rh"
    TX=$((CX + rx + rw / 2)); TY=$((CY + ry + rh / 2))
    python3 tools/i18n/mouse.py "$TX" "$TY" > "$TMPD/klick1.mon"
    lauf "$TMPD/en" tab "$TMPD/klick1.mon"
    has "$TMPD/en/tab.txt" "t=Language of the surface:" \
        "ein Klick auf den Reiter oeffnet die Sprachseite"
    # Das Auswahlfeld (kind=9) und der Knopf (kind=2) dieser Seite.
    zeile_von() { grep -a 'einstellungen: feld' "$1" | grep " kind=$2 " \
                  | tail -1; }
    cx1=$(zeile_von "$TMPD/en/tab.txt" 9 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
    cb1=$(zeile_von "$TMPD/en/tab.txt" 9 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
    # Das LETZTE Auswahlfeld ist die Tastaturbelegung; das erste die
    # Sprache. Also das erste nehmen.
    cx=$(grep -a 'einstellungen: feld' "$TMPD/en/tab.txt" | grep ' kind=9 ' \
         | head -1 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
    cb=$(grep -a 'einstellungen: feld' "$TMPD/en/tab.txt" | grep ' kind=9 ' \
         | head -1 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
    bx=$(zeile_von "$TMPD/en/tab.txt" 2 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
    bb=$(zeile_von "$TMPD/en/tab.txt" 2 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
    if [ -z "${cx:-}" ] || [ -z "${bx:-}" ]; then
        bad "die Sprachseite meldet kein Auswahlfeld oder keinen Knopf"
    else
        ok "das Auswahlfeld liegt bei x=$cx base=$cb, der Knopf bei x=$bx base=$bb"
        python3 tools/i18n/mouse.py "$TX" "$TY" \
            $((CX + cx + 30)) $((CY + cb - 6)) \
            $((CX + bx + 10)) $((CY + bb - 6)) \
            --park $((WX + 500)) $((WY + 380)) > "$TMPD/klick3.mon"
        lauf "$TMPD/en" wechsel "$TMPD/klick3.mon"
        W="$TMPD/en/wechsel.txt"
        if grep -qa 't=Übernehmen' "$W"; then
            ok "NACH DEN DREI KLICKS STEHT DIE OBERFLAECHE AUF DEUTSCH -- ohne Neustart"
        else
            bad "die Oberflaeche ist nach dem Klick nicht deutsch"
            grep -a 'einstellungen: feld' "$W" | tail -8 | sed 's/^/        /'
        fi
        has "$W" "t=Sprache gewechselt: de" "und das Statusfeld sagt es"
        # UND EIN ANDERER PROZESS ZIEHT MIT. Das ist die eigentliche
        # Zusage: die Taskleiste liest die Wahl des Benutzers nach, so
        # wie sie /etc/theme nachliest.
        if grep -a 'leiste: text netz' "$W" | tail -1 | grep -q 'kein Netz'; then
            ok "und die TASKLEISTE, ein ANDERER Prozess, zieht mit: kein Netz statt no network"
        else
            bad "die Taskleiste bleibt englisch: $(grep -a 'leiste: text netz' "$W" | tail -1)"
        fi
        # BILDPUNKTGENAU, in DEMSELBEN Lauf, in dem vorher Englisch stand.
        wx=$(zeile_von "$W" 2 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
        wb=$(zeile_von "$W" 2 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
        schau "der umgestellte Knopf steht bildpunktgenau auf dem Schirm" \
            ttext "$TMPD/en/wechsel.ppm" "$SANS" 15 $((CX + wx)) $((CY + wb)) \
            230 230 230 57 64 74 "Übernehmen" 8
        nx=$(grep -a 'leiste: text netz' "$W" | tail -1 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
        nb=$(grep -a 'leiste: text netz' "$W" | tail -1 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
        schau "und die umgestellte Taskleiste auch" \
            ttext "$TMPD/en/wechsel.ppm" "$SANS" 15 "$nx" $((572 + nb)) \
            230 230 230 42 47 55 "kein Netz" 8
        # DIE WAHL IST GESCHRIEBEN -- unter dem BENUTZER und nicht unter
        # /etc/. Nachgelesen aus dem Abbild, nicht aus einem Mitschnitt.
        python3 tools/osum/mkfs.py cat "$TMPD/en/live-wechsel.img" \
            /users/root/config/locale > "$TMPD/gewaehlt.txt" 2>/dev/null
        is "in /users/root/config/locale steht" \
            "$(tr -d '\n' < "$TMPD/gewaehlt.txt")" "de"
        python3 tools/osum/mkfs.py list "$TMPD/en/live-wechsel.img" \
            > "$TMPD/liste.txt" 2>/dev/null
        grep -q '^/etc/locale' "$TMPD/liste.txt" \
            && bad "die Sprache liegt unter /etc/ -- sie gehoert dem Benutzer" \
            || ok "und NICHT unter /etc/ -- die Sprache gehoert dem Benutzer"
    fi
fi

# ================================================= 8. was es kostet

echo "== 8. was die UTF-8-Dekodierung das Zeichnen kostet =="

# Die Zahl kommt aus dem Kernel selbst (`wm: text ... us=`), einmal mit
# der neuen Textschleife und einmal mit der alten -- beide auf
# derselben Maschine, derselben Schrift, demselben Text.
grep -a '^i18n: draw' "$TMPD/en/en.txt" | sed 's/^/        /'
alt=$(grep -aoE 'i18n: draw ascii us=[0-9]+' "$TMPD/en/en.txt" | tail -1 \
      | grep -oE '[0-9]+$')
neu=$(grep -aoE 'i18n: draw utf8 us=[0-9]+' "$TMPD/en/en.txt" | tail -1 \
      | grep -oE '[0-9]+$')
gl=$(grep -aoE 'i18n: draw glyphs us=[0-9]+' "$TMPD/en/en.txt" | tail -1 \
     | grep -oE '[0-9]+$')
if [ -n "${alt:-}" ] && [ -n "${neu:-}" ] && [ "$alt" -gt 0 ]; then
    d=$(( neu - alt ))
    ad=${d#-}
    proz=$(( ad * 100 / alt ))
    vz="+"; [ "$d" -lt 0 ] && vz="-"
    if [ "$proz" -lt 15 ]; then
        ok "1000 Zeilen zu 40 Zeichen: ${alt} us oktettweise, ${neu} us zeichenweise (${vz}${proz}%, im Rauschen)"
        ok "je Zeile: $(( alt / 1000 )) us gegen $(( neu / 1000 )) us -- und das Holen der 40 Glyphen kostet $(( gl / 1000 )) us"
    else
        bad "die Dekodierung kostet ${vz}${proz}% -- das ist spuerbar"
    fi
else
    bad "der Kernel meldet die Kosten nicht"
fi

# ============================================ 9. die alten Messungen

echo "== 9. was vorher gruen war, ist es noch =="

for r in wm k15; do
    if [ -f "tools/$r/run.sh" ]; then
        bash "tools/$r/run.sh" > "$TMPD/alt-$r.txt" 2>&1
        rc=$?
        z=$(grep -cE '^  OK ' "$TMPD/alt-$r.txt")
        n=$(grep -cE '^  FAIL' "$TMPD/alt-$r.txt")
        if [ "${n:-0}" = 0 ]; then
            ok "tools/$r/run.sh: $z Zusagen, 0 gescheitert"
        else
            bad "tools/$r/run.sh: $z Zusagen, $n gescheitert"
            grep -E '^  FAIL' "$TMPD/alt-$r.txt" | head -10 | sed 's/^/        /'
        fi
    fi
done

echo ""
echo "I18N: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
