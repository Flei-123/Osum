#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gfx/run.sh -- DER BEWEIS, DASS OSUM EINEN BILDSCHIRM HAT.
#
# Bis Runde K7 war Osums Konsole die serielle Schnittstelle.  Der
# Multiboot-Kopf VERLANGTE seit Commit c4427fa einen linearen Rahmenpuffer
# -- damit ein Lader unter UEFI nicht auf einem Textmodus besteht, den es
# dort nicht gibt -- und benutzt hat ihn niemand.  Diese Runde benutzt ihn.
#
# WAS HIER GEMESSEN WIRD, UND WARUM ES BILDSCHIRMFOTOS SEIN MUESSEN.
#
# Ein Testlauf, der einen Kernel startet und "kein Absturz" meldet, sagt
# ueber einen Bildschirm gar nichts: ein Treiber, der in den falschen
# Speicher schreibt, stuerzt nicht ab, er zeigt nur nichts.  Also macht
# dieser Laeufer echte Bildschirmfotos ueber den QEMU-Monitor
# (`screendump`) und rechnet sie MASCHINELL nach (`tools/gfx/schau.py`):
# Bildgroesse, erwartete Farben an erwarteten Stellen, und -- das ist die
# eigentliche Zusage -- ob geschriebener Text wirklich als Bildpunkte
# erscheint, Bit fuer Bit gegen den Zeichensatz gerechnet.
#
# Die Abschnitte:
#
#   1. BAUEN. Beide Uebersetzer bauen denselben Kernel.
#   2. DER ZEICHENSATZ. `kernel/font.fi` gegen die Rust-Vorlage, aus der
#      er portiert wurde -- 1520 Oktette, Oktett fuer Oktett.  "Portiert"
#      soll nicht "ungefaehr abgeschrieben" heissen.
#   3. DIE FENSTERPLAETZE UND DIE SPEICHERKARTE. `fb.fi` und `apic.fi`
#      teilen sich acht 2-MiB-Plaetze am oberen Ende des
#      Kernel-Seitenverzeichnisses.  Die vier Zahlen dafuer stehen in
#      beiden Dateien; sie werden hier gegeneinander gehalten, weil ein
#      Auseinanderlaufen erst dann auffiele, wenn sich zwei Treiber
#      gegenseitig die Abbildung ueberschreiben.
#      DAZU SEIT RUNDE K7B: die ganze Karte von `kdata`, 38 Bereiche aus
#      vier Dateien, paarweise gegeneinander gerechnet
#      (`tools/kernel/karte.py`).  Runde K7 legte den Zeichensatz auf
#      0x2F000 und Runde K9 die Signaltabelle -- beide Zweige waren fuer
#      sich gruen, und der Textverschmelzer konnte das nicht sehen, weil
#      sich keine gemeinsame ZEILE ueberschnitt, nur zwei ADRESSEN.
#   4. DER RAHMENPUFFER KOMMT AN. Geometrie, Herkunft, Fensteradresse,
#      und die dreizehn Zusagen, die der Kernel ueber seinen eigenen
#      Bildschirm selbst pruefen kann (`fb.selftest`).
#   5. DAS BILDSCHIRMFOTO. 800x600 statt 720x400, vier Farbfelder exakt,
#      eine Linie, zwei Textzeilen bildpunktgenau.
#   6. DIE GEGENPROBE. DERSELBE Kernel, DIESELBE Kommandozeile, nur ohne
#      das Wort `gfx`: die Maschine steht im VGA-Textmodus, das
#      Bildschirmfoto ist 720x400, und JEDE Messung aus Abschnitt 5
#      bricht zusammen.  Ohne diesen Abschnitt beweist ein gruener Test
#      aus Abschnitt 5 nichts.
#   7. BEIDE AUSGABEN ZEIGEN DASSELBE. Der ganze serielle Mitschnitt wird
#      durch dieselbe Zustandsmaschine geschickt, die `fb.putc` ist, und
#      das Ergebnis Bildpunkt fuer Bildpunkt gegen das Foto gehalten.
#   8. RING 3. Ein Programm ohne Kernelrechte oeffnet /dev/fb, schreibt,
#      liest, bildet ab und malt -- zehn Zusagen, davon die Haelfte
#      Ablehnungen.  Und das Band, das es gemalt hat, steht im Foto.
#   9. DIE ZEITEN. Voller Bildaufbau und Rollvorgang, mit und ohne
#      Zweitpuffer, auf derselben Maschine und mit demselben Zeitzaehler.
#  10. ZWEI KACHELN. 1024x768 braucht zwei 2-MiB-Fensterplaetze statt
#      einem -- der Fall, in dem die Abbildung zusammenhaengend sein muss.
#  11. DIE SHELL AUF DEM BILDSCHIRM. /bin/sh von der Platte, seine Ausgabe
#      bildpunktgenau im Foto.
#
# Verwendung:  bash tools/gfx/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ORIENTOS=${ORIENTOS:-$ROOT/../orientos}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}

has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

# Ein Aufruf von schau.py als Zusage.
schau() { # name unterbefehl args...
    local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/schau.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi
}

# Dasselbe, aber es MUSS fehlschlagen (die Gegenprobe).
schau_nicht() { # name unterbefehl args...
    local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/schau.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- ging durch: $aus"; fi
}

bash vendor/firn/hole-firnc.sh >/dev/null || { echo "vendor/firn/hole-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "GFX: skipped, qemu-system-x86_64 ist nicht da"
    exit 0
fi

# ---------------------------------------------------------- ein Lauf
#
# `-vga std` ist der Bochs-VBE-Aufsatz von QEMU (PCI 1234:1111): die
# Karte, deren Register `fb.fi` bedient.  Er ist bei x86 ohnehin die
# Vorgabe; er steht hier ausdruecklich, weil der ganze Abschnitt davon
# abhaengt.
#
# Der Monitor haengt an einem Unix-Socket -- sonst hat der Laeufer nichts,
# woran er `screendump` rufen koennte.

lauf() { # abbild kommandozeile ausgabe [weitere qemu-argumente]
    local abbild=$1 zeile=$2 aus=$3
    shift 3
    timeout 120 qemu-system-x86_64 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    return $?
}

# Ein Lauf MIT Bildschirmfoto.  Der Kern haelt auf das Wort `fbhold` hin
# rund vier Sekunden still und meldet das seriell; genau dann wird
# fotografiert.  Setzt RC auf den Beendigungscode.
RC=0
foto() { # abbild kommandozeile ausgabe ppm [weitere qemu-argumente]
    local abbild=$1 zeile=$2 aus=$3 ppm=$4
    shift 4
    local sock="$TMPD/mon-$$.sock"
    rm -f "$aus" "$ppm" "$sock"
    timeout 120 qemu-system-x86_64 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 400 ]; do
        grep -qa '^fb: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    python3 tools/gfx/schuss.py "$sock" "$ppm" > "$TMPD/schuss.txt" 2>&1
    wait "$pid"
    RC=$?
    rm -f "$sock"
    return 0
}

# Eine Zahl aus einer Zeile des Mitschnitts.
zahl() { # datei muster
    grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+' | tail -1
}

echo "== 1. bauen: derselbe Kernel aus beiden Uebersetzern =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: Kernel gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: der Kernel laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
K0="$TMPD/k0.mb"
[ -f "$K0" ] || { echo "GFX: $pass passed, $((fail + 1)) failed"; exit 1; }

echo "== 2. der Zeichensatz: 1520 Oktette gegen die Rust-Vorlage =="
if [ -f "$ORIENTOS/kernel/src/drivers/font.rs" ]; then
    schau "font.fi ist die Vorlage, Oktett fuer Oktett" \
        font kernel/font.fi "$ORIENTOS/kernel/src/drivers/font.rs"
else
    schau "font.fi hat 95 Glyphen zu 16 Oktetten" font kernel/font.fi
    echo "        (OrientOS liegt nicht unter $ORIENTOS -- Vorlage nicht geprueft)"
fi

echo "== 3. die Fensterplaetze und die Speicherkarte von kdata =="
# Beide Dateien bilden Geraetespeicher in dieselben acht 2-MiB-Plaetze am
# oberen Ende des Kernel-Seitenverzeichnisses ab und fuehren dieselbe
# Belegungsliste.  Laufen die Zahlen auseinander, nehmen sich zwei Treiber
# gegenseitig die Abbildung weg -- und das faellt erst auf, wenn beide
# gleichzeitig gebraucht werden.
w_apic=$(grep -E '^const WIN_SLOTS|^const WIN_FIRST|^const WIN_VIRT|^const HUGE_SIZE' kernel/apic.fi | sed 's/ *\/\/.*//' | sort)
w_fb=$(grep -E '^const WIN_SLOTS|^const WIN_FIRST|^const WIN_VIRT|^const HUGE_SIZE' kernel/fb.fi | sed 's/ *\/\/.*//' | sort)
if [ -n "$w_apic" ] && [ "$w_apic" = "$w_fb" ]; then
    ok "WIN_SLOTS, WIN_FIRST, WIN_VIRT und HUGE_SIZE stehen in beiden gleich"
else
    bad "die Fensterzahlen von fb.fi und apic.fi laufen auseinander"
    diff <(echo "$w_apic") <(echo "$w_fb") | sed 's/^/        /'
fi
# Und die Belegungsliste: fb.fi rechnet sie sich aus pci.K2_SCALARS und
# apic.S_WIN selbst zusammen, weil es pci.fi nicht einbinden darf.
k2=$(grep -E '^const K2_SCALARS' kernel/pci.fi | grep -oE '0x[0-9A-Fa-f]+')
sw=$(grep -E '^const S_WIN' kernel/apic.fi | grep -oE '0x[0-9A-Fa-f]+')
fbl=$(grep -E '^const WIN_LIST' kernel/fb.fi | sed 's/.*= *//; s/ *\/\/.*//')
if [ "$fbl" = "$k2 + $sw" ]; then
    ok "fb.WIN_LIST ist pci.K2_SCALARS + apic.S_WIN ($k2 + $sw)"
else
    bad "fb.WIN_LIST ist '$fbl', erwartet '$k2 + $sw'"
fi

# DIE SPEICHERKARTE VON `kdata`, UND WARUM SIE HIER STEHT.
#
# Der Fehler, der diese Runde ausgeloest hat, war keiner im Bildcode: er
# war eine ADRESSE.  Runde K7 legte den Zustand des Rahmenpuffers samt
# Zeichensatz auf 0x2F000 -- und schrieb die Konstante in `fb.fi` statt
# in die Karte in `kstate.fi`.  Runde K9 las die Karte, fand 0x2F000
# unbelegt und legte die Signaltabelle dorthin.  Beide Zweige waren fuer
# sich gruen; nach dem Verschmelzen loeschte der Signalblock der Aufgabe 1
# die Glyphen '@' bis 'o'.  Auf dem Schirm blieben Ziffern stehen und
# jeder Buchstabe verschwand.
#
# Dasselbe ist in diesem Baum viermal passiert (K4/K2, K5/K2, K6/K5,
# K7/K9), und dreimal endete es als Kommentar statt als Zusage.  Ab hier
# ist es eine Zusage.
kart=$(python3 tools/kernel/karte.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "die Speicherkarte von kdata: $kart"
else bad "die Speicherkarte von kdata kollidiert"; echo "$kart" | sed 's/^/        /'; fi

# UND DIE GEGENPROBE ZUM PRUEFER SELBST.  Ein Kollisionspruefer, der nie
# etwas findet, ist von einem, der nichts prueft, nicht zu unterscheiden.
# Also wird die alte Adresse in einer KOPIE zurueckgesetzt -- der Baum
# bleibt unangetastet -- und der Pruefer MUSS anschlagen.
GG="$TMPD/kernel-gg"
mkdir -p "$GG"
cp kernel/*.fi "$GG/"
sed -i 's/^const FB_OFF: u64 = 0x3C000/const FB_OFF: u64 = 0x2F000/; s/^const FONT_OFF: u64 = 0x3C100/const FONT_OFF: u64 = 0x2F100/' "$GG/fb.fi" "$GG/kstate.fi"
gg=$(python3 tools/kernel/karte.py "$GG" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gg" | grep -q 'KOLLISION: FB'; then
    ok "mit FB_OFF zurueck auf 0x2F000 findet der Pruefer die Kollision mit SIG"
else
    bad "der Kollisionspruefer findet den Fehler dieser Runde NICHT: $gg"
fi

echo "== 4. der Rahmenpuffer kommt an =="
GRUND="nokbd nosched noproc nofs noring3"
lauf "$K0" "gfx $GRUND" "$TMPD/an.txt"
rc=$?
num "der Kern beendet sich sauber" "$rc" eq 21
has "$TMPD/an.txt" "fb: 800x600x32" "800x600 bei 32 Bit je Bildpunkt"
has "$TMPD/an.txt" "pitch=3200" "Zeilenlaenge 3200 = Breite mal vier"
has "$TMPD/an.txt" "src=vbe" "die Quelle ist die Karte (Bochs-VBE ueber PCI)"
has "$TMPD/an.txt" "phys=0xfd000000" "der lineare Puffer liegt in BAR0 der Karte"
has "$TMPD/an.txt" "huge=1" "1,92 MiB passen in EINE 2-MiB-Kachel"
has "$TMPD/an.txt" "cols=100  rows=37" "100 Spalten und 37 Zeilen bei 8x16"
st=$(zahl "$TMPD/an.txt" 'fb: selftest [0-9]+')
num "die Zusagen des Kernels ueber seinen eigenen Bildschirm" "$st" eq 13
# Der Multiboot-Weg: QEMUs `-kernel` hat keinen Videoteil, also MUSS die
# Quelle die Karte sein.  Das steht hier als gemessene Tatsache und nicht
# als Vermutung -- Bit 12 (0x1000) fehlt in den Flags.
mbf=$(grep -aoE '^mb: flags=0x[0-9a-f]+' "$TMPD/an.txt" | head -1 | sed 's/.*=//')
if [ -n "$mbf" ] && [ $(( $(printf '%d' "$mbf") & 4096 )) -eq 0 ]; then
    ok "QEMUs -kernel liefert KEINE Rahmenpufferangaben (flags=$mbf, Bit 12 fehlt)"
else
    bad "unerwartete Multiboot-Flags: $mbf"
fi
# Und die Gegenprobe zum Selbsttest: ohne `gfx` gibt es die Zeile nicht.
lauf "$K0" "$GRUND" "$TMPD/ohne.txt"
hasnot "$TMPD/ohne.txt" "fb: 800x600" "ohne 'gfx' meldet der Kern keinen Bildschirm"
hasnot "$TMPD/ohne.txt" "fb: selftest" "ohne 'gfx' gibt es keinen Selbsttest"

echo "== 5. das Bildschirmfoto: was wirklich auf dem Schirm steht =="
foto "$K0" "gfx nocursor fbtest fbhold $GRUND" "$TMPD/pat.txt" "$TMPD/pat.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/pat.txt" "fb: hold" "der Kern haelt fuer das Foto still"
schau "das Foto ist 800x600 -- der Bildmodus wurde wirklich gesetzt" \
    groesse "$TMPD/pat.ppm" 800 600
schau "Feld 1: reines Rot, 100x100 Bildpunkte" \
    flaeche "$TMPD/pat.ppm" 0 0 100 100 255 0 0
schau "Feld 2: reines Gruen" flaeche "$TMPD/pat.ppm" 100 0 100 100 0 255 0
schau "Feld 3: reines Blau" flaeche "$TMPD/pat.ppm" 200 0 100 100 0 0 255
schau "Feld 4: Weiss" flaeche "$TMPD/pat.ppm" 300 0 100 100 255 255 255
schau "und daneben ist nichts" flaeche "$TMPD/pat.ppm" 400 0 100 100 0 0 0
schau "die Linie trifft ihren Anfang" punkt "$TMPD/pat.ppm" 0 110 255 255 0
schau "die Linie trifft ihr Ende" punkt "$TMPD/pat.ppm" 399 210 255 255 0
# DIE eigentliche Zusage dieses Abschnitts: der Text, den `serial.puts`
# geschrieben hat, steht als BILDPUNKTE da -- 3200 Stellen je Zeile,
# jede einzelne gegen die Bitmaske des Zeichensatzes gerechnet.
schau "Zeile 14 bildpunktgenau: 'OSUM K7 FRAMEBUFFER 01234'" \
    text "$TMPD/pat.ppm" kernel/font.fi 14 0 "OSUM K7 FRAMEBUFFER 01234"
schau "Zeile 15 bildpunktgenau: 'abcdefghijklm ABCDEFGHIJK'" \
    text "$TMPD/pat.ppm" kernel/font.fi 15 0 "abcdefghijklm ABCDEFGHIJK"
# Dieselben zwei Zeilen stehen im seriellen Mitschnitt -- eine Ausgabe,
# zwei Wege.
has "$TMPD/pat.txt" "OSUM K7 FRAMEBUFFER 01234" "dieselbe Zeile steht seriell"

echo "== 6. DIE GEGENPROBE: derselbe Kernel ohne das Wort 'gfx' =="
# Alles bleibt gleich -- dasselbe Abbild, dieselbe Maschine, dasselbe
# `fbhold`, dieselbe Wartezeit, dasselbe Foto.  Nur `gfx` fehlt.  Wenn
# jetzt noch irgendetwas aus Abschnitt 5 durchginge, haette Abschnitt 5
# nicht den Bildschirm gemessen, sondern etwas anderes.
foto "$K0" "nocursor fbtest fbhold $GRUND" "$TMPD/keine.txt" "$TMPD/keine.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/keine.txt" "fb: hold" "auch ohne Bildschirm wird stillgehalten"
schau "das Foto ist 720x400 -- VGA-Textmodus, kein Bildmodus gesetzt" \
    groesse "$TMPD/keine.ppm" 720 400
schau_nicht "Feld 1 ist NICHT rot" \
    flaeche "$TMPD/keine.ppm" 0 0 100 100 255 0 0
schau_nicht "Feld 2 ist NICHT gruen" \
    flaeche "$TMPD/keine.ppm" 100 0 100 100 0 255 0
schau_nicht "die Textzeile steht NICHT da" \
    text "$TMPD/keine.ppm" kernel/font.fi 14 0 "OSUM K7 FRAMEBUFFER 01234"
# Was auf dem Textmodusbild zu sehen ist, ist die Meldung des BIOS -- also
# durchaus Bildpunkte, nur eben keine, die dieser Kernel gemalt hat.  Die
# Zusage ist deshalb nicht "alles schwarz", sondern: die Stellen, die
# Abschnitt 5 misst, GIBT ES HIER NICHT.
schau_nicht "die untere rechte Ecke von 800x600 liegt ausserhalb des Bildes" \
    punkt "$TMPD/keine.ppm" 799 599
schau_nicht "und wo im Bildmodus das gelbe Linienende sitzt, ist keins" \
    punkt "$TMPD/keine.ppm" 399 210 255 255 0

echo "== 7. beide Ausgaben zeigen dasselbe =="
# Der serielle Mitschnitt ab dem Punkt, an dem der Spiegel angeht, durch
# dieselbe Zustandsmaschine geschickt, die `fb.putc` ist -- und dann das
# GANZE Bild dagegen gehalten.  Was hier gruen wird, ist nicht "es steht
# Text da", sondern "es steht GENAU der Text da, den die serielle Konsole
# gesehen hat, an genau der Stelle, an der er stehen muss".
# Der VOLLE Lauf, nicht der abgekuerzte: Aufgaben, Prozesse, Dateisystem
# und die Shell aus Ring 3 reden alle ueber dieselbe Konsole, und erst
# damit rollt das Bild ueberhaupt.  Ein Vergleich auf einem halb vollen
# Bild pruefte das Rollen nicht mit.
foto "$K0" "gfx nocursor fbhold nokbd" "$TMPD/kon.txt" "$TMPD/kon.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
schau "der ganze Bildschirm gegen den seriellen Mitschnitt" \
    konsole "$TMPD/kon.ppm" kernel/font.fi "$TMPD/kon.txt" \
    "fb: console mirrored to screen" "fb: hold" 500
# Und die Gegenprobe dazu: gegen den Mitschnitt eines ANDEREN Laufs kann
# das nicht aufgehen.
schau_nicht "gegen den Mitschnitt des Pruefbild-Laufs geht es NICHT auf" \
    konsole "$TMPD/kon.ppm" kernel/font.fi "$TMPD/pat.txt" \
    "fb: console mirrored to screen" "fb: hold" 500

echo "== 8. Ring 3 malt: /dev/fb ohne Kernelrechte =="
foto "$K0" "gfx fbuser fbhold nokbd nofs" "$TMPD/u.txt" "$TMPD/u.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/u.txt" "fbuser: open fd=3" "open(\"/dev/fb\", O_RDWR) gibt einen Deskriptor"
b=$(zahl "$TMPD/u.txt" 'fbuser: bytes=[0-9]+')
num "lseek(fd,0,SEEK_END) gibt die Groesse des Bildes" "$b" eq 1920000
m=$(grep -aoE 'fbuser: map=[0-9]+' "$TMPD/u.txt" | head -1 | sed 's/.*=//')
num "mmap legt den Puffer auf 0x40200000" "$m" eq 1075838976
z=$(zahl "$TMPD/u.txt" 'fbuser: passed [0-9]+')
num "die Zusagen des Programms in Ring 3" "$z" eq 11
# Und was es gemalt hat, steht im Foto -- vier Streifen ueber die unteren
# achtzig Bildzeilen, an einer Grenze, die auf den Bildpunkt stimmt.
schau "der Streifen ist rot" flaeche "$TMPD/u.ppm" 0 520 200 80 255 0 0
schau "der Streifen ist gruen" flaeche "$TMPD/u.ppm" 200 520 200 80 0 255 0
schau "der Streifen ist blau" flaeche "$TMPD/u.ppm" 400 520 200 80 0 0 255
schau "der Streifen ist gelb" flaeche "$TMPD/u.ppm" 600 520 200 80 255 255 0
schau "und eine Bildzeile darueber ist nichts" \
    flaeche "$TMPD/u.ppm" 0 519 800 1 0 0 0
# Die Gegenprobe: ohne `fbuser` malt niemand dort.
foto "$K0" "gfx fbhold nokbd nofs" "$TMPD/nu.txt" "$TMPD/nu.ppm"
schau_nicht "ohne 'fbuser' ist der Streifen NICHT da" \
    flaeche "$TMPD/nu.ppm" 0 520 200 80 255 0 0

echo "== 9. die Zeiten =="
# Beide Wege in EINEM Lauf, auf derselben Maschine und mit demselben
# Zeitzaehler -- zwei QEMU-Starts waeren zwei Maschinen.
grep -aE '^        fbbench: ' "$TMPD/an.txt" | sed 's/^ */   /'
d_fill=$(grep -a 'fbbench: direct' "$TMPD/an.txt" | grep -oE 'fill=[0-9]+' | grep -oE '[0-9]+')
d_scr=$(grep -a 'fbbench: direct' "$TMPD/an.txt" | grep -oE 'scroll=[0-9]+' | grep -oE '[0-9]+')
b_fill=$(grep -a 'fbbench: buffered' "$TMPD/an.txt" | grep -oE 'fill=[0-9]+' | grep -oE '[0-9]+')
b_flush=$(grep -a 'fbbench: buffered' "$TMPD/an.txt" | grep -oE 'flush=[0-9]+' | grep -oE '[0-9]+')
num "voller Bildaufbau, direkt auf die Karte (us)" "$d_fill" gt 0
num "Rollvorgang, direkt auf die Karte (us)" "$d_scr" gt 0
num "voller Bildaufbau in den Zweitpuffer (us)" "$b_fill" gt 0
num "Uebertragung des Zweitpuffers (us)" "$b_flush" gt 0
# 1,92 MiB in weniger als 100 ms: die Zahl ist absichtlich grosszuegig.
# Sie faengt den Fall ab, in dem die Blockbefehle wieder zu einer Schleife
# aus Einzelzugriffen werden -- das kostete gemessen den Faktor 7.
num "der Bildaufbau bleibt unter 100 ms" "$d_fill" lt 100000
num "die Uebertragung bleibt unter 100 ms" "$b_flush" lt 100000
# Gegenprobe zur Messung selbst: mit `nodbl` gibt es keinen Zweitpuffer,
# also auch keine zweite Zeile.
lauf "$K0" "gfx nodbl $GRUND" "$TMPD/nodbl.txt"
has "$TMPD/nodbl.txt" "back=none" "mit 'nodbl' gibt es keinen Zweitpuffer"
has "$TMPD/nodbl.txt" "fbbench: direct" "der direkte Weg wird trotzdem gemessen"
hasnot "$TMPD/nodbl.txt" "fbbench: buffered" "und der gepufferte nicht"

echo "== 10. 1024x768: zwei Kacheln statt einer =="
foto "$K0" "gfx fbbig nocursor fbtest fbhold $GRUND" "$TMPD/big.txt" "$TMPD/big.ppm"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/big.txt" "fb: 1024x768x32" "1024x768 bei 32 Bit"
has "$TMPD/big.txt" "huge=2" "3 MiB brauchen ZWEI zusammenhaengende Fensterplaetze"
has "$TMPD/big.txt" "cols=128  rows=48" "128 Spalten und 48 Zeilen"
schau "das Foto ist 1024x768" groesse "$TMPD/big.ppm" 1024 768
schau "die vier Farbfelder stehen auch hier" \
    flaeche "$TMPD/big.ppm" 200 0 100 100 0 0 255
schau "und der Text ebenso, bildpunktgenau" \
    text "$TMPD/big.ppm" kernel/font.fi 14 0 "OSUM K7 FRAMEBUFFER 01234"

echo "== 11. die Shell auf dem Bildschirm =="
# /bin/sh von der Platte, wie in Runde K1 und K6 -- nur dass die Ausgabe
# diesmal auf dem Bildschirm landet.  Gebaut wird das kleinste Userland,
# das dafuer reicht.
PROGS="sh echo ls cat"
BLOCKS=2048
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>"$TMPD/crt.err" \
    || bad "crt.s laesst sich nicht uebersetzen"
gebaut=1
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 \
        || { bad "firnc0 uebersetzt $p.fi nicht"; gebaut=0; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>"$TMPD/ld$p.err" \
        || { bad "ld scheitert an $p"; gebaut=0; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
if [ "$gebaut" = 1 ]; then
    ok "vier eigenstaendige ELF64-Programme fuer die Platte gebaut"
    SPEC="/bin/"
    for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
    python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
        > "$TMPD/mkfs.txt" 2>&1 \
        && ok "mkfs.py hat ein OFS-Abbild mit /bin/sh gebaut" \
        || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }
    # `script=` MUSS am Ende stehen: `console_load` nimmt alles dahinter
    # bis zum Zeilenende als Eingabe fuer die Shell.
    foto "$K0" "osum gfx nocursor fbhold nokbd nosched noproc nofs noring3 script=echo OSUM SHELL ON SCREEN;ls /bin;echo DONE" \
        "$TMPD/sh.txt" "$TMPD/sh.ppm" \
        -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0"
    num "der Kern beendet sich sauber" "$RC" eq 21
    has "$TMPD/sh.txt" "OSUM SHELL ON SCREEN" "die Shell hat den Satz seriell gesagt"
    schau "der ganze Bildschirm gegen den Mitschnitt der Shell" \
        konsole "$TMPD/sh.ppm" kernel/font.fi "$TMPD/sh.txt" \
        "fb: console mirrored to screen" "fb: hold" 500
    # Und die Zeile der Shell einzeln, damit im Fehlerfall dasteht, WELCHE
    # Zeile nicht stimmt.
    #
    # DIESE ZEILE IST SEIT DEM VERSCHMELZEN MIT K9 MEHR ALS EIN TEXT: das
    # `write(1, ...)` der Shell laeuft durch `tty.write_out` (sys.fi:823),
    # also durch K9s ZEILENDISZIPLIN, und von dort ueber `tty.emit` auf
    # `serial.put` und den Spiegel. Steht sie bildpunktgenau da, ist
    # bewiesen, dass Terminalschicht und Bildschirm zusammenpassen -- und
    # zwar ohne dass eine Zeile von `tty.fi` das Wort `fb` kennt.
    schau "die Zeile der Shell steht bildpunktgenau auf dem Schirm" \
        finde "$TMPD/sh.ppm" kernel/font.fi "$TMPD/sh.txt" \
        "fb: console mirrored to screen" "fb: hold" "OSUM SHELL ON SCREEN"
    schau "und die Zeile, mit der das Skript endet, ebenso" \
        finde "$TMPD/sh.ppm" kernel/font.fi "$TMPD/sh.txt" \
        "fb: console mirrored to screen" "fb: hold" "DONE"
fi

echo
echo "GFX: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
