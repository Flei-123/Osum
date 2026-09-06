#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/alltag/run.sh -- DIE ABNAHME DER RUNDE ALLTAG.
#
#   bash tools/alltag/run.sh [arbeitsverzeichnis]
#
# Sechs kleine Programme, die am ersten Tag fehlen -- Sperrbildschirm,
# Papierkorb, Ausschnittwerkzeug, Bildbetrachter, ZIP, Taschenrechner --
# und zu jedem eine Zahl, die von aussen nachrechenbar ist. Kein
# Abschnitt sagt "sieht gut aus".
#
# ZEHN ABSCHNITTE, und jeder hat eine Gegenprobe:
#
#   1. BAUEN. Kern und Programme. Ohne diesen Abschnitt sagen die
#      anderen nichts.
#   2. DER RECHNER gegen PYTHON. Vierzig Ausdruecke, mit `-e` durch den
#      Gast und durch Pythons Bibliothek; verglichen werden die ZAHLEN,
#      relative Schranke 1e-9. Gegenprobe: ein Ausdruck, der falsch ist,
#      muss "Fehler im Ausdruck" bekommen und nicht 0.
#   3. ZIP IN BEIDE RICHTUNGEN. Packen -> Entpacken -> `diff` sagt
#      gleich. Ein mit Python erzeugtes ZIP wird entpackt. Und das vom
#      GAST erzeugte Archiv wird auf dem WIRT mit Pythons zipfile
#      geoeffnet -- das ist die Richtung, die ein eigener Entpacker
#      nicht pruefen kann.
#   4. DER PAPIERKORB. Loeschen -> Liste -> Zurueckholen -> `diff` sagt
#      byte-gleich. Leeren. Und im DATEIMANAGER: Entf legt hinein
#      (das Verzeichnis .papierkorb entsteht), Umschalt+Entf loescht
#      endgueltig (es entsteht nicht).
#   5. DIE BILDER gegen PILLOW. PNG (RGBA, Farbtafel, Grau), BMP und
#      JPEG (4:4:4 und 4:2:0): Groesse, die Summe jedes Farbkanals ueber
#      ALLE Bildpunkte und fuenf einzelne Bildpunkte. Verlustfrei heisst
#      EXAKT.
#   6. DAS AUSSCHNITTWERKZEUG. Das PNG, das der Gast schreibt, gegen
#      QEMUs eigenes Bildschirmfoto DESSELBEN Schirms -- Bildpunkt fuer
#      Bildpunkt. Danach macht der Bildbetrachter im Gast dieselbe Datei
#      auf.
#   7. DIE SPERRE. Falsches Kennwort: bleibt zu. Richtiges: auf.
#      Absturz des Sperrers: bleibt zu UND der Kern startet ihn neu.
#      Leerlauf: sperrt von selbst.
#   8. DER LADEN. Sechs signierte Pakete, mit `opk installieren`
#      eingespielt, sechs Buendel unter /apps, der Starter zaehlt sechs.
#      Gegenprobe: ein Paket mit gekipptem Oktett wird abgelehnt.
#   9. DIE BILDER DER PROGRAMME. Je eine Aufnahme nach .alltag-shots/,
#      und jede wird GEMESSEN (shotcheck: keine leere Beschriftung,
#      nichts abgeschnitten, nichts ueberlappend) statt angesehen.
#  10. DIE REGELN DER RUNDE. Kein Zeichenaufruf ausserhalb wlib, das
#      Vierer-Raster, und die Abnahme der Runde THEMESTORE bleibt gruen.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
SHOTS=$ROOT/.alltag-shots
mkdir -p "$SHOTS"
B=tools/alltag/build.sh

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 wert=$2 op=$3 want=$4
    if [ -z "${wert:-}" ]; then bad "$name: keine Zahl (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
hat()    { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' steht da" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "ALLTAG: uebersprungen, qemu-system-x86_64 ist nicht da"
    exit 0
fi
python3 -c "import PIL" 2>/dev/null || {
    echo "ALLTAG: uebersprungen, Pillow fehlt (die Bildabnahme braucht es)"
    exit 0
}

# ------------------------------------------------------------ 1. bauen
echo "== 1. bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if bash "$B" "$OUT/b0" script='echo bereit;exit' \
       progs="rechner zip papierkorb viewer snip lock sh echo ls cat" \
       > "$OUT/bauen.log" 2>&1; then
    ok "Kern und Programme gebaut ($(grep -a '^kernel ' "$OUT/bauen.log" | head -1))"
else
    bad "der Bau ging nicht"; tail -20 "$OUT/bauen.log"; exit 1
fi

# ---------------------------------------------------------- 2. Rechner
echo
echo "== 2. der Rechner gegen Python =="
python3 tools/alltag/rechner.py skript "$OUT/pruef.sh" > "$OUT/skript.log"
bash "$B" "$OUT/rech" script='sh /pruef.sh;rechner -e 2++;exit' \
    progs="rechner sh echo ls cat" xfile=/pruef.sh="$OUT/pruef.sh" \
    > "$OUT/rech.log" 2>&1
if python3 tools/alltag/rechner.py pruefen "$OUT/rech/serial.txt" \
       > "$OUT/rechner.txt" 2>&1; then
    ok "$(tail -1 "$OUT/rechner.txt")"
else
    bad "$(tail -1 "$OUT/rechner.txt")"
    grep -a FAIL "$OUT/rechner.txt" | head -5
fi
hat "$OUT/rech/serial.txt" "Fehler im Ausdruck" \
    "Gegenprobe: '2++' ist ein Fehler und keine Null"

# -------------------------------------------------------------- 3. ZIP
echo
echo "== 3. zip, in beide Richtungen =="
python3 - "$OUT" <<'PY'
import sys, zipfile
d = sys.argv[1]
gross = b"Zeile mit Umlauten aeoeue und Zahlen 0123456789\n" * 900
with zipfile.ZipFile(d + "/fremd.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("gruss.txt", "Hallo aus Python\n")
    z.writestr("gross.bin", gross)
    z.writestr("unter/tief.txt", "tief drin\n")
open(d + "/zt.sh", "w").write("""mkdir /pk
cp /etc/theme.conf /pk/a.txt
cp /etc/passwd /pk/b.txt
mkdir /pk/u
cp /etc/locale.conf /pk/u/c.txt
zip -c /eigen.zip /pk
mkdir /aus
zip -x /eigen.zip /aus
diff /pk/a.txt /aus/pk/a.txt
echo DIFF-A $?
diff /pk/u/c.txt /aus/pk/u/c.txt
echo DIFF-C $?
mkdir /aus2
zip -x /fremd.zip /aus2
cat /aus2/gruss.txt
cat /aus2/unter/tief.txt
echo ZIP-FERTIG
""")
PY
bash "$B" "$OUT/zip" script='sh /zt.sh;exit' \
    progs="zip sh echo ls cat mkdir cp diff" \
    xfile=/zt.sh="$OUT/zt.sh" xfile=/fremd.zip="$OUT/fremd.zip" \
    > "$OUT/zip.log" 2>&1
Z=$OUT/zip/serial.txt
hat "$Z" "DIFF-A 0" "packen -> entpacken: /pk/a.txt ist byte-gleich"
hat "$Z" "DIFF-C 0" "und die Datei im Unterordner auch"
hat "$Z" "Hallo aus Python" "ein fremdes ZIP (Python, deflate) laesst sich entpacken"
hat "$Z" "tief drin" "auch der Eintrag im Unterordner"
python3 tools/osum/mkfs.py cat "$OUT/zip/disk.img" /eigen.zip \
    > "$OUT/eigen.zip" 2>/dev/null
if python3 - "$OUT/eigen.zip" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
assert z.testzip() is None
n = [i.filename for i in z.infolist()]
assert "pk/a.txt" in n and "pk/u/c.txt" in n, n
assert z.read("pk/a.txt").startswith(b"# /etc/theme.conf")
print(len(n))
PY
then ok "das Archiv des Gastes: Pythons zipfile liest es ($(stat -c%s "$OUT/eigen.zip") Oktette)"
else bad "das Archiv des Gastes ist fuer Python kaputt"; fi

# ------------------------------------------------------- 4. Papierkorb
echo
echo "== 4. der Papierkorb =="
cat > "$OUT/pt.sh" <<'EOF'
mkdir /w
cp /etc/theme.conf /w/wichtig.txt
papierkorb weg /w/wichtig.txt
ls /w
papierkorb liste
papierkorb zurueck 1
diff /etc/theme.conf /w/wichtig.txt
echo DIFF-ZURUECK $?
papierkorb weg /w/wichtig.txt
papierkorb leeren
papierkorb liste
echo KORB-FERTIG
EOF
bash "$B" "$OUT/korb" script='sh /pt.sh;exit' \
    progs="papierkorb sh echo ls cat mkdir cp diff rmdir" \
    xfile=/pt.sh="$OUT/pt.sh" > "$OUT/korb.log" 2>&1
K=$OUT/korb/serial.txt
hat "$K" "papierkorb: nummer 1  /w/wichtig.txt" "die Liste kennt den Originalpfad"
hat "$K" "DIFF-ZURUECK 0" "zurueckgeholt und byte-gleich"
hat "$K" "papierkorb: leer" "nach dem Leeren ist er leer"
printf 'eine Notiz\n' > "$OUT/n1.txt"
bash "$B" "$OUT/ex1" desk=no kbd=yes warten=3 extra="wigapp=/bin/explorer,/w" \
    mon="sendkey delete" progs="explorer papierkorb theme sh echo ls cat" \
    xdir=/w xfile=/w/n1.txt="$OUT/n1.txt" > "$OUT/ex1.log" 2>&1
hat "$OUT/ex1/serial.txt" "explorer: tat 3 rc=0" "Entf im Dateimanager: in den Korb"
if python3 tools/osum/mkfs.py list "$OUT/ex1/disk.img" 2>/dev/null \
       | grep -qa '^/.papierkorb/1.info'; then
    ok "und im Korb liegt Eintrag 1 mit seiner Infodatei"
else
    bad "im Korb liegt nichts"
fi
bash "$B" "$OUT/ex2" desk=no kbd=yes warten=3 extra="wigapp=/bin/explorer,/w" \
    mon="sendkey shift-delete" mon="sendkey ret" \
    progs="explorer papierkorb theme sh echo ls cat" \
    xdir=/w xfile=/w/n1.txt="$OUT/n1.txt" > "$OUT/ex2.log" 2>&1
hat "$OUT/ex2/serial.txt" "explorer: tat 5 rc=0" "Umschalt+Entf: endgueltig"
if python3 tools/osum/mkfs.py list "$OUT/ex2/disk.img" 2>/dev/null \
       | grep -qa '^/.papierkorb'; then
    bad "Gegenprobe: Umschalt+Entf hat trotzdem in den Korb gelegt"
else
    ok "Gegenprobe: kein Papierkorb entstanden -- es war wirklich endgueltig"
fi

# ----------------------------------------------------------- 5. Bilder
echo
echo "== 5. die Bilder gegen Pillow =="
python3 - "$OUT" <<'PY'
import sys
from PIL import Image
d = sys.argv[1]
im = Image.new("RGBA", (64, 48))
px = im.load()
for y in range(48):
    for x in range(64):
        px[x, y] = (x * 4 % 256, y * 5 % 256, (x * y) % 256, 255)
im.save(d + "/probe.png")
im.convert("RGB").save(d + "/probe.bmp")
im.convert("P", palette=Image.ADAPTIVE, colors=16).save(d + "/pal.png")
im.convert("L").save(d + "/grau.png")
im.convert("RGB").resize((96, 72)).save(d + "/voll.jpg", quality=95,
                                        subsampling=0)
im.convert("RGB").resize((160, 120)).save(d + "/gross.jpg", quality=80)
PY
cat > "$OUT/vt.sh" <<'EOF'
viewer -i /b/probe.png
viewer -i /b/probe.bmp
viewer -i /b/pal.png
viewer -i /b/grau.png
viewer -i /b/voll.jpg
viewer -i /b/gross.jpg
echo VIEWER-FERTIG
EOF
bash "$B" "$OUT/bild" script='sh /vt.sh;exit' progs="viewer sh echo ls cat" \
    xdir=/b xfile=/vt.sh="$OUT/vt.sh" \
    xfile=/b/probe.png="$OUT/probe.png" xfile=/b/probe.bmp="$OUT/probe.bmp" \
    xfile=/b/pal.png="$OUT/pal.png" xfile=/b/grau.png="$OUT/grau.png" \
    xfile=/b/voll.jpg="$OUT/voll.jpg" xfile=/b/gross.jpg="$OUT/gross.jpg" \
    > "$OUT/bild.log" 2>&1
if python3 tools/alltag/bildref.py pruefen "$OUT/bild/serial.txt" \
       "$OUT/probe.png" "$OUT/probe.bmp" "$OUT/pal.png" "$OUT/grau.png" \
       "$OUT/voll.jpg" "$OUT/gross.jpg" > "$OUT/bilder.txt" 2>&1; then
    ok "$(tail -1 "$OUT/bilder.txt")"
    sed -n 's/^  OK    /        /p' "$OUT/bilder.txt"
else
    bad "$(tail -1 "$OUT/bilder.txt")"
    grep -a FAIL "$OUT/bilder.txt" | head -6
fi

# ------------------------------------------------------------- 6. snip
echo
echo "== 6. das Ausschnittwerkzeug =="
bash "$B" "$OUT/snip" desk=no warten=11 \
    extra="wigapp=/bin/snip,-v,2,-o,/schnipsel.png" \
    progs="snip viewer theme sh echo ls cat" > "$OUT/snip.log" 2>&1
hat "$OUT/snip/serial.txt" "snip: gesichert /schnipsel.png w=1280 h=800" \
    "der Gast hat den ganzen Schirm aufgenommen und geschrieben"
python3 tools/osum/mkfs.py cat "$OUT/snip/disk.img" /schnipsel.png \
    > "$OUT/schnipsel.png" 2>/dev/null
G=$(python3 - "$OUT" <<'PY'
import sys
from PIL import Image, ImageChops
d = sys.argv[1]
try:
    a = Image.open(d + "/schnipsel.png").convert("RGB")
    b = Image.open(d + "/snip/desktop.ppm").convert("RGB")
except Exception as e:
    print(-1)
    sys.exit(0)
if a.size != b.size:
    print(-2)
    sys.exit(0)
diff = ImageChops.difference(a, b)
gleich = sum(1 for p in diff.getdata() if p == (0, 0, 0))
print(gleich * 1000 // (a.size[0] * a.size[1]))
pass
PY
)
num "Bildpunkte gleich wie in QEMUs eigenem Foto (Promille)" "$G" ge 990
# Und der Bildbetrachter macht dieselbe Datei auf -- auf DERSELBEN
# Platte, die der vorige Lauf beschrieben hat.
cp "$OUT/snip/disk.img" "$OUT/snip.img"
bash "$B" "$OUT/snipv" platte="$OUT/snip.img" script='viewer -i /schnipsel.png;exit' \
    progs="snip viewer theme sh echo ls cat" > "$OUT/snipv.log" 2>&1
hat "$OUT/snipv/serial.txt" "viewer: art=png w=1280 h=800" \
    "der Bildbetrachter macht das PNG des Ausschnittwerkzeugs auf"
# UND ER LIEST DIESELBEN ZAHLEN WIE PILLOW aus derselben Datei -- damit
# ist die Kette geschlossen: Schirm -> PNG (Gast) -> Bildpunkte (Gast)
# und Schirm -> PNG (Gast) -> Bildpunkte (Wirt) kommen zum selben
# Ergebnis.
if python3 tools/alltag/bildref.py pruefen "$OUT/snipv/serial.txt" \
       "$OUT/schnipsel.png" > "$OUT/snipref.txt" 2>&1; then
    ok "und liest daraus Zahl fuer Zahl dasselbe wie Pillow"
else
    bad "$(tail -1 "$OUT/snipref.txt")"
fi

# ------------------------------------------------------------ 7. Sperre
echo
echo "== 7. der Sperrbildschirm =="
python3 - "$OUT" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(),
                          binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("root:%s:0:0:99999:7:::\n" % rec)
open(d + "/sperre.conf", "w").write("# /etc/sperre.conf\nleerlauf=2\n")
PY
MON=""
for c in f a l s c h ret g e h e i m 1 2 ret; do MON="$MON mon=sendkey\ $c"; done
eval bash "$B" "$OUT/sp1" kbd=yes warten=8 extra=\"wigapp=/bin/lock\" \
    progs=\"lock desktop taskbar launcher theme sh echo ls cat\" \
    xfile=/etc/shadow="$OUT/shadow" $MON > "$OUT/sp1.log" 2>&1
S=$OUT/sp1/serial.txt
hat "$S" "sperre: falsches Kennwort, bleibt zu" \
    "falsches Kennwort: die Sperre bleibt stehen"
hat "$S" "sperre: aufgesperrt" "richtiges Kennwort: sie geht auf"
bash "$B" "$OUT/sp2" warten=10 extra="wigapp=/bin/lock,-absturz" \
    progs="lock desktop taskbar launcher theme sh echo ls cat" \
    xfile=/etc/shadow="$OUT/shadow" > "$OUT/sp2.log" 2>&1
S2=$OUT/sp2/serial.txt
hat "$S2" "user fault" "der Sperrer stirbt (mit Absicht)"
hat "$S2" "sperre: Sperrer neu, pid=" "und der Kern startet ihn neu"
hatnicht "$S2" "sperre: aufgesperrt" \
    "GEGENPROBE: ein Absturz sperrt NICHT auf"
bash "$B" "$OUT/sp3" script='lock -s;lock -d einmal;lock -s;exit' \
    progs="lock sh echo ls cat" xfile=/etc/sperre.conf="$OUT/sperre.conf" \
    > "$OUT/sp3.log" 2>&1
hat "$OUT/sp3/serial.txt" "sperre: Waechter, Leerlauf 2 s" \
    "der Waechter liest /etc/sperre.conf"
hat "$OUT/sp3/serial.txt" "sperre: Leerlauf abgelaufen, sperre" \
    "und sperrt von selbst, wenn nichts mehr kommt"

# ------------------------------------------------------------- 8. Laden
echo
echo "== 8. der Laden: sechs Pakete, signiert, eingespielt =="
if [ -x /root/orientos-install/pkg/opk.py ] || [ -f /root/orientos-install/pkg/opk.py ]; then
    bash tools/laden/build.sh "$OUT/laden" > "$OUT/laden-bau.log" 2>&1
    bash tools/laden/pakete.sh "$OUT/laden" > "$OUT/laden-pak.log" 2>&1
    export OSUM_SIGN_PASS=alltag OSUM_ERSATZ_PASS=alltag
    python3 tools/ota/schluesselbund.py "$OUT/bund.json" anlegen \
        > "$OUT/bund.log" 2>&1
    python3 tools/ota/schluesselbund.py "$OUT/bund.json" oeffentlich haupt \
        -o "$OUT/schluessel.pub" >> "$OUT/bund.log" 2>&1
    X=""
    for p in calc trash viewer snip zip lock; do
        python3 tools/ota/schluesselbund.py "$OUT/bund.json" signieren \
            "$OUT/laden/stand/$p-1.opk" -o "$OUT/laden/stand/$p-1.opk.sig" \
            >> "$OUT/bund.log" 2>&1
        X="$X xfile=/pakete/$p-1.opk=$OUT/laden/stand/$p-1.opk"
        X="$X xfile=/pakete/$p-1.opk.sig=$OUT/laden/stand/$p-1.opk.sig"
    done
    # DIE GEGENPROBE: ein Paket mit EINEM gekippten Oktett.
    python3 - "$OUT/laden/stand/calc-1.opk" "$OUT/boese.opk" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read())
d[len(d) // 2] ^= 1
open(sys.argv[2], "wb").write(d)
PY
    cp "$OUT/laden/stand/calc-1.opk.sig" "$OUT/boese.opk.sig"
    {
        for p in calc trash viewer snip zip lock; do
            echo "opk installieren /pakete/$p-1.opk"
        done
        echo "opk installieren /pakete/boese.opk"
        echo "opk richten"
        echo "ls /apps"
        echo "echo STORE-FERTIG"
    } > "$OUT/inst.sh"
    eval bash "$B" "$OUT/store" bloecke=262144 inodes=512 mager=yes \
        script=\"sh /inst.sh\;exit\" \
        progs=\"opk sh echo ls cat desktop taskbar launcher theme\" \
        xdir=/pakete xdir=/system \
        xfile=/system/schluessel.pub="$OUT/schluessel.pub" \
        xfile=/inst.sh="$OUT/inst.sh" \
        xfile=/pakete/boese.opk="$OUT/boese.opk" \
        xfile=/pakete/boese.opk.sig="$OUT/boese.opk.sig" \
        $X > "$OUT/store.log" 2>&1
    N=$(grep -ac 'opk: installiert' "$OUT/store/serial.txt")
    num "Pakete eingespielt (Signatur geprueft)" "$N" eq 6
    hat "$OUT/store/serial.txt" "STORE-FERTIG" "und der Lauf kam durch"
    if grep -qa 'boese' "$OUT/store/serial.txt" \
       && grep -qa 'Signatur' "$OUT/store/serial.txt"; then
        BO=$(grep -a -A1 'boese.opk' "$OUT/store/serial.txt" | grep -ac 'installiert boese')
        num "GEGENPROBE: das gekippte Paket wurde NICHT eingespielt" "$BO" eq 0
    fi
    M=$(python3 tools/osum/mkfs.py list "$OUT/store/disk.img" 2>/dev/null \
        | grep -ac 'osp/start')
    num "Buendel unter /apps" "$M" eq 6
    cp "$OUT/store/disk.img" "$OUT/store.img"
    bash "$B" "$OUT/storeg" platte="$OUT/store.img" warten=3 \
        progs="opk sh echo ls cat desktop taskbar launcher theme" \
        > "$OUT/storeg.log" 2>&1
    A=$(grep -a 'launcher: apps=' "$OUT/storeg/serial.txt" | tail -1 \
        | grep -aoE '[0-9]+$')
    num "der Starter zaehlt die neuen Programme" "$A" eq 6
    python3 - "$OUT" "$SHOTS" <<'PY'
import sys
from PIL import Image
Image.open(sys.argv[1] + "/storeg/desktop.ppm").convert("RGB").save(
    sys.argv[2] + "/store-installiert.png")
PY
    ok "Bild: .alltag-shots/store-installiert.png"
else
    echo "  -- opk.py fehlt (/root/orientos-install/pkg/opk.py), Abschnitt uebersprungen"
fi

# ------------------------------------------------- 9. die Bilder, gemessen
echo
echo "== 9. je ein Bild, und jedes wird gemessen =="
schuss() { # name wigapp fenster-x,y [extra-args...]
    local name=$1 app=$2 wxy=$3
    shift 3
    bash "$B" "$OUT/s-$name" desk=no uitrace=yes warten=2 \
        extra="wigapp=$app" progs="$PROGS" "$@" \
        > "$OUT/s-$name.log" 2>&1
    if [ ! -s "$OUT/s-$name/desktop.ppm" ]; then
        bad "$name: kein Bild entstanden"
        return
    fi
    python3 - "$OUT/s-$name/desktop.ppm" "$SHOTS/$name.png" <<'PY'
import sys
from PIL import Image
Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2])
PY
    local o
    o=$(python3 tools/alltag/shotcheck.py "$OUT/s-$name/desktop.ppm" \
        "$OUT/s-$name/serial.txt" --cut="$name: geom" --winat="$wxy" 2>&1 \
        | head -1)
    case "$o" in
        *"empty 0  cut 0  overlapping 0"*) ok "$name: $o" ;;
        *) bad "$name: $o" ;;
    esac
    python3 tools/design/messen.py "$OUT/s-$name" 2>/dev/null \
        | sed -n '/raster/p;/klickflaechen/p' | sed 's/^/        /'
    # DAS RASTER WIRD FUER JEDES PROGRAMM GEFORDERT, nicht nur gezeigt.
    local r
    r=$(python3 tools/design/messen.py "$OUT/s-$name" 2>/dev/null \
        | grep -a 'raster/4' | grep -aoE '\([0-9]+%\)' | tr -dc '0-9')
    num "$name: Vierer-Raster (Prozent)" "$r" ge 92
}
PROGS="rechner zip papierkorb viewer snip lock theme sh echo ls cat"
schuss rechner /bin/rechner 80,60
schuss papierkorb /bin/papierkorb 70,70 \
    xdir=/w xfile=/w/n1.txt="$OUT/n1.txt"
schuss viewer /bin/viewer,/b/probe.png 60,50 \
    xdir=/b xfile=/b/probe.png="$OUT/probe.png" \
    xfile=/b/voll.jpg="$OUT/voll.jpg" xfile=/b/probe.bmp="$OUT/probe.bmp"
schuss snip /bin/snip 50,40
schuss lock /bin/lock 0,0 xfile=/etc/shadow="$OUT/shadow"

# ------------------------------------------------------- 10. die Regeln
echo
echo "== 10. die Regeln dieser Runde =="
Z=0
for f in rechner papierkorb viewer snip lock korb bild jpeg zip; do
    n=$(grep -ac 'wlibc\.\(px\|rect\|rrect\|frame\|frame3\|hline\|vline\|text\|glyph\|blit\|rring\|divider\|drop_shadow\)(' \
        "kernel/user/$f.fi" 2>/dev/null || true)
    Z=$((Z + n))
done
num "direkte Zeichenaufrufe ausserhalb wlib" "$Z" eq 0
R=$(python3 tools/design/messen.py "$OUT/s-viewer" 2>/dev/null \
    | grep -a 'raster/4' | grep -aoE '\([0-9]+%\)' | tr -dc '0-9')
num "Vierer-Raster im Bildbetrachter (Prozent)" "$R" ge 92
if [ -n "${ALLTAG_THEMESTORE:-}" ]; then
    bash tools/themestore/run.sh > "$OUT/themestore.txt" 2>&1
    TP=$(grep -ac '^  OK' "$OUT/themestore.txt")
    TF=$(grep -ac '^  FAIL' "$OUT/themestore.txt")
    num "themestore: gruen" "$TP" ge 81
    num "themestore: rot" "$TF" eq 0
else
    echo "  -- tools/themestore/run.sh laeuft nur mit ALLTAG_THEMESTORE=1 mit"
fi

echo
echo "== ALLTAG: $pass gruen, $fail rot =="
[ "$fail" -eq 0 ]
