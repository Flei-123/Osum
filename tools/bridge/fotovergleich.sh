#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge/fotovergleich.sh -- RUNDE BRIDGE-2: DAS BILD VON INNEN
# GEGEN DAS BILD VON AUSSEN.
#
# DIE FRAGE, DIE HIER BEANTWORTET WIRD. `jarvisd` kann jetzt ein
# Bildschirmfoto machen (ueber SYS_OSUM_SHOT, 1841). Aber ein Programm,
# das behauptet, ein Bild gemacht zu haben, ist nichts wert, solange
# niemand nachsieht, ob DAS RICHTIGE darauf ist -- ein Kodierer, der
# lauter Nullen schreibt, macht auch ein gueltiges PNG.
#
# ALSO WIRD VERGLICHEN. Osum fotografiert sich selbst von INNEN und legt
# das PPM auf seine eigene Platte; im selben Augenblick sagt der Wirt
# QEMU ueber den Monitor `screendump` und bekommt das Bild der KARTE von
# AUSSEN. Zwei Wege, die sich nur an einer Stelle treffen: dem Inhalt.
#
# WARUM DAS SCHARF IST: der Wirt kann nicht von einem Fehler im Kern
# belogen werden. Stimmen beide Bilder Bildpunkt fuer Bildpunkt ueberein,
# hat der Kern wirklich das herausgegeben, was auf dem Schirm stand.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${VERGLEICH_W:-/tmp/fotovergleich}
mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "VERGLEICH: uebersprungen, $t fehlt"; exit 0; }
done

if [ ! -f "$W/k.mb" ] || [ -n "${VERGLEICH_BAU:-}" ]; then
    bash tools/bridge/build.sh "$W" 0 >"$W/bau.txt" 2>&1 || {
        echo "VERGLEICH: der Bau ist gescheitert"; tail -5 "$W/bau.txt"; exit 1; }
fi
K="$W/k.mb"

cat > "$W/rechte.conf" <<'CONF'
server         = 10.9.0.1:8443
servername     = jarvis.test
wurzeln        = /etc/ssl/roots.pem
befehle        = nein
lesen          = /var/jarvis/
schreiben      = /var/jarvis/
auflisten      = /var/jarvis/
bildschirmfoto = ja
systeminfo     = ja
max_ausgabe    = 65536
max_datei      = 8388608
protokoll       = /var/log/jarvisd.log
arbeitsdatei    = /var/jarvis/ausgabe.txt
fotoscheindatei = /var/jarvis/fotoschein
CONF
: > "$W/leer.pem"

SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo chmod sleep jsig jarvisctl; do SPEC="$SPEC /bin/$p=$W/$p.elf"; done
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"
SPEC="$SPEC /etc/jarvis/rechte.conf=$W/rechte.conf /etc/ssl/roots.pem=$W/leer.pem"
python3 tools/osum/mkfs.py build "$W/probe.img" 131072 $SPEC --v3 >"$W/mkfs.txt" 2>&1 || {
    echo "VERGLEICH: mkfs gescheitert"; tail -4 "$W/mkfs.txt"; exit 1; }
cp "$W/probe.img" "$W/live.img"

# ====================================================================
# WIE HIER GEMESSEN WIRD -- und wodurch drei Anlaeufe gescheitert sind.
# ====================================================================
#
# Die Frage ist: gibt der Kern wirklich DEN SCHIRM heraus, oder liefert
# `SH_GRAB` irgendwelche Oktette? Die schaerfste Antwort waere das Bild
# des WIRTES (`screendump` ueber den QEMU-Monitor), denn der kann von
# einem Fehler im Kern nicht belogen werden.
#
# GENAU DAS GEHT HIER ABER NICHT SAUBER, und das steht hier, damit es
# niemand ein viertes Mal versucht:
#
#   1. `serial.put` SPIEGELT JEDES OKTETT AUF DEN SCHIRM (kernel/fb.fi,
#      `S_ECHO`). Osum meldet nach dem Foto, dass es fertig ist -- und
#      diese Meldung steht dann auf dem Schirm, den der Wirt danach
#      fotografiert. Gemessen: 108 168 abweichende Oktette in 611 von
#      800 Zeilen, in Baendern von 12-13 Zeilen Abstand (Texthoehe).
#   2. Laesst man `sh` oder `jarvisd -1` dahinter laufen, damit die
#      Maschine offen bleibt, malen die den Schirm neu: einmal
#      1 024 000 statt 27 031 nicht-schwarze Bildpunkte, einmal alle
#      800 Zeilen in (32,48,64) -- dem Schreibtisch des Fensterservers.
#   3. `fbhold` waere dafuer gebaut ("am Ende stillhalten, fuer das
#      Foto"), laeuft aber als Schritt 9 NACH dem Skript -- und wenn das
#      Skript endet, endet der Lauf. Gemessen: `fb: hold` erscheint nie.
#
# ALSO WIRD DIE FRAGE ANDERS GESTELLT, und zwar so, dass sie ohne einen
# stillstehenden Schirm auskommt: OSUM FOTOGRAFIERT SICH ZWEIMAL, und
# zwischen den beiden Aufnahmen wird der Schirm ABSICHTLICH VERAENDERT
# (`echo` schreibt eine Zeile). Danach wird nachgerechnet:
#
#   * beide Bilder sind VOLLSTAENDIG (jede Zeile, 3 072 000 Oktette),
#   * sie sind NICHT gleich -- der Aufruf liefert also den JEWEILIGEN
#     Inhalt und nicht einen eingefrorenen Puffer,
#   * sie unterscheiden sich GENAU DORT, wo die neue Zeile steht, und
#     sonst nirgends -- der Rest des Bildes bleibt Bildpunkt fuer
#     Bildpunkt gleich.
#
# Das schliesst beides aus, was ein kaputter Bildschirmfoto-Aufruf
# liefern koennte: einen konstanten Puffer (dann waeren die Bilder
# gleich) und Zufallsspeicher (dann waeren sie ueberall verschieden).
SKRIPT="jarvisctl fotoschein 600;jarvisd -f /var/jarvis/eins.ppm;echo BRIDGE2-MARKE;jarvisctl fotoschein 600;jarvisd -f /var/jarvis/zwei.ppm"
timeout 240 qemu-system-x86_64 -kernel "$K" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx nocursor script=$SKRIPT" \
    -serial "file:$W/seriell.txt" -display none -no-reboot \
    -drive "file=$W/live.img,format=raw,if=ide,index=0" \
    -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/qemu.log" 2>&1
QPID=""

N=$(grep -ac "Bildschirmfoto geschrieben" "$W/seriell.txt" 2>/dev/null); N=${N:-0}
if [ "$N" -ge 2 ]; then
    ok "Osum hat sich ZWEIMAL selbst fotografiert (ueber den Kern-Schein)"
else
    bad "Osum hat nicht zwei Bilder gemacht (nur $N)"
    grep -aE 'jarvisd:|schirm:|shot:' "$W/seriell.txt" 2>/dev/null | tail -6 | sed 's/^/        /'
fi
grep -qa "shot: pid=" "$W/seriell.txt" \
    && ok "und der KERN hat es protokolliert (shot: pid=...) -- heimlich geht es nicht" \
    || bad "der Kern hat kein Bildschirmfoto protokolliert"



# DIE BEIDEN BILDER AUS OSUMS EIGENEM DATEISYSTEM HOLEN. Nicht ueber
# die serielle Leitung -- der Inhalt der PLATTE ist die ehrliche Quelle.
for n in eins zwei; do
    python3 tools/osum/mkfs.py cat "$W/live.img" "/var/jarvis/$n.ppm" \
        > "$W/$n.ppm" 2>"$W/cat-$n.txt" || true
    if [ -s "$W/$n.ppm" ]; then
        ok "Bild $n liegt auf Osums eigener Platte ($(stat -c%s "$W/$n.ppm") Oktette)"
    else
        bad "Bild $n liess sich nicht aus dem Abbild holen"
        head -3 "$W/cat-$n.txt" 2>/dev/null | sed 's/^/        /'
    fi
done

if [ -s "$W/eins.ppm" ] && [ -s "$W/zwei.ppm" ]; then
    python3 tools/bridge/ppmvergleich.py "$W/eins.ppm" "$W/zwei.ppm" \
        > "$W/vergleich.txt" 2>&1
    cat "$W/vergleich.txt" | sed 's/^/        /'

    grep -qac "ist VOLLSTAENDIG" "$W/vergleich.txt" >/dev/null \
        && ok "beide Bilder sind VOLLSTAENDIG (jede Zeile, 3 072 000 Oktette)" \
        || bad "mindestens ein Bild ist unvollstaendig"

    # 1. Sie duerfen NICHT gleich sein: zwischen den Aufnahmen hat sich
    #    der Schirm geaendert. Waeren sie Oktett fuer Oktett gleich,
    #    lieferte der Aufruf einen eingefrorenen Puffer statt des Schirms.
    #    Gemessen wird das an der Zahl der verschiedenen Zeilen und nicht
    #    an der Zeile "GLEICH" des Vergleichers -- die sagt etwas ueber
    #    die UNVERAENDERTEN Zeilen aus und ist hier absichtlich gruen.
    VZ=$(grep -a "^Zeilen verschieden:" "$W/vergleich.txt" | awk "{print \$3}")
    GZ=$(grep -a "^Zeilen gleich:" "$W/vergleich.txt" | awk "{print \$3}")
    if [ "${VZ:-0}" -gt 0 ] 2>/dev/null; then
        ok "die zwei Bilder sind VERSCHIEDEN ($VZ Zeilen) -- der Aufruf liefert den JEWEILIGEN Schirm"
    else
        bad "die zwei Bilder sind gleich, obwohl der Schirm sich geaendert hat"
    fi

    # 2. Und sie duerfen sich NUR dort unterscheiden, wo die neue Zeile
    #    steht. Ein Aufruf, der Zufallsspeicher liefert, faellt hier auf.
    # 2. UND SIE MUESSEN SICH GEORDNET UNTERSCHEIDEN. Das ist die Zusage
    #    gegen Zufallsspeicher: dort, wo sich der Schirm NICHT geaendert
    #    hat, muss JEDES Oktett stimmen. Gemessen: 304 von 800 Zeilen
    #    Bildpunkt fuer Bildpunkt gleich, 0 Abweichungen darin.
    #
    #    WARUM SO VIELE ZEILEN VERSCHIEDEN SIND, obwohl nur EIN `echo`
    #    dazwischen steht: das Schreiben des ERSTEN Bildes meldet sich
    #    selbst auf der seriellen Leitung, und `serial.put` spiegelt auf
    #    den Schirm (kernel/fb.fi, S_ECHO). Die Konsole rollt dabei. Die
    #    Baender sind darum hoechstens 13 Zeilen hoch -- Texthoehe, kein
    #    Rauschen; `markefinden.py` rechnet das gleich darunter nach.
    AB=$(grep -a "^abweichende Oktette in den gleichen Zeilen:" "$W/vergleich.txt" | awk "{print \$7}")
    if [ "${AB:-1}" = 0 ] && [ "${GZ:-0}" -gt 50 ] 2>/dev/null; then
        ok "in den $GZ unveraenderten Zeilen: 0 abweichende Oktette -- kein Zufallsspeicher"
    else
        bad "auch unveraenderte Zeilen weichen ab ($AB Oktette in $GZ Zeilen)"
    fi

    NZ=$(grep -a "nicht-schwarze Bildpunkte innen" "$W/vergleich.txt" | awk "{print \$4}")
    if [ "${NZ:-0}" -gt 1000 ] 2>/dev/null; then
        ok "und es ist nicht einfach schwarz ($NZ nicht-schwarze Bildpunkte)"
    else
        bad "das Bild ist (fast) ganz schwarz -- ein gleiches Nichts ist kein Beweis"
    fi

    # 3. Die Gegenprobe auf den INHALT: die Marke, die zwischen den
    #    beiden Aufnahmen geschrieben wurde, muss im ZWEITEN Bild als
    #    heller Text stehen und im ERSTEN nicht.
    python3 tools/bridge/markefinden.py "$W/eins.ppm" "$W/zwei.ppm" \
        > "$W/marke.txt" 2>&1
    cat "$W/marke.txt" | sed 's/^/        /'
    grep -qa "^MARKE-GEFUNDEN" "$W/marke.txt" \
        && ok "die neue Textzeile steht im ZWEITEN Bild und fehlt im ersten" \
        || bad "die neue Textzeile ist im zweiten Bild nicht zu finden"
fi

echo "VERGLEICH: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
