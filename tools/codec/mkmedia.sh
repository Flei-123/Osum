#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/codec/mkmedia.sh -- DAS PRUEFMATERIAL DIESER RUNDE, vom WIRT gebaut.
#
# Erzeugt rohe Annex-B-Stroeme (.264) mit x264 im BASELINE-PROFIL und
# daneben das, was ffmpeg daraus dekodiert (rohes YUV 4:2:0, I420).
# Diese YUV-Datei ist die WAHRHEIT, gegen die Osum bitweise verglichen
# wird -- h.264 ist exakt spezifiziert, "sieht aehnlich aus" gilt nicht.
#
#   bash tools/codec/mkmedia.sh ZIELVERZEICHNIS
set -u
ZIEL=${1:?Zielverzeichnis fehlt}
mkdir -p "$ZIEL"

# Ein Strom: Name, Breite, Hoehe, Bilder, zusaetzliche x264-Schalter.
# -profile:v baseline erzwingt CAVLC, keine B-Bilder, kein 8x8.
mach() {
    local name=$1 w=$2 h=$3 n=$4; shift 4
    local quelle=$1; shift
    ffmpeg -y -v error -f lavfi -i "$quelle" -frames:v "$n" \
        -c:v libx264 -profile:v baseline -pix_fmt yuv420p \
        "$@" -f h264 "$ZIEL/$name.264" 2>"$ZIEL/$name.enc.log" || return 1
    # Die Gegenprobe: ffmpeg dekodiert DIESELBE Datei nach rohem YUV.
    ffmpeg -y -v error -i "$ZIEL/$name.264" \
        -f rawvideo -pix_fmt yuv420p "$ZIEL/$name.yuv" \
        2>"$ZIEL/$name.dec.log" || return 1
    printf '%s %s %s %s\n' "$name" "$w" "$h" "$n" >> "$ZIEL/liste.txt"
    return 0
}

rm -f "$ZIEL/liste.txt"

# --- NUR I-BILDER. -g 1 heisst: jedes Bild ist ein IDR. Das ist die
#     erste Stufe der Abnahme; sie misst Intra-Vorhersage, Transformation
#     und Deblocking OHNE Bewegungskompensation.
mach i_klein   64  64  3 "testsrc2=size=64x64:rate=5"     -g 1 -qp 26
mach i_sd     176 144  3 "testsrc2=size=176x144:rate=5"   -g 1 -qp 26
mach i_glatt  128  96  2 "color=c=gray:size=128x96:rate=5" -g 1 -qp 20
mach i_scharf 160 128  2 "testsrc=size=160x128:rate=5"    -g 1 -qp 18

# --- I + P. Ein IDR am Anfang, danach nur P-Bilder: das misst
#     Bewegungskompensation, Viertelpel und P_Skip.
mach p_klein   64  64  6 "testsrc2=size=64x64:rate=5"     -g 100 -qp 26
mach p_sd     176 144  8 "testsrc2=size=176x144:rate=5"   -g 100 -qp 26
# Ein Strom mit echter Bewegung: ein wanderndes Muster erzwingt
# Bewegungsvektoren, die NICHT null sind (sonst waere alles P_Skip).
mach p_bewegt 176 144  8 "testsrc2=size=352x288:rate=5" -g 100 -qp 24 \
     -vf "crop=176:144:'min(88,n*8)':'min(72,n*4)'"
# Ein glattes Bild mit Bewegung -- hier entstehen viele P_Skip-Bloecke.
mach p_skip   128  96  6 "color=c=navy:size=128x96:rate=5" -g 100 -qp 26

# --- CIF, die groesste Masse dieser Runde (MAXW/MAXH in h264.fi).
#     Dieser Strom traegt die Geschwindigkeitsangabe im Bericht: er ist
#     das, was man wirklich abspielen wuerde.
mach cif      352 288 10 "testsrc2=size=352x288:rate=10" -g 100 -qp 26

# --- P-023: DIE GROSSEN MASSE. Sie sind der Grund dieser Runde --
#     der Dekodierer war fuer sie zu langsam, und MAXW/MAXH standen bei
#     CIF. Beide werden GENAUSO bitweise gegen ffmpeg geprueft wie die
#     kleinen; eine schnelle Fassung, die anders rechnet, waere wertlos.
#     Wenige Bilder, weil die YUV-Dateien gross sind (720p: 1,4 MiB je
#     Bild) und die Platte des Wirts knapp ist.
mach vga      640 480  6 "testsrc2=size=640x480:rate=10" -g 100 -qp 26
mach hd720   1280 720  4 "testsrc2=size=1280x720:rate=10" -g 100 -qp 26

# --- MEHRERE SLICES JE BILD. Der Regelfall in jedem Rundfunkstrom (ein
#     verlorenes Paket kostet dann nur einen Streifen) und der Fall, an
#     dem ein Dekodierer auffliegt, der ein Bild fuer einen Slice haelt:
#     ueber eine Slicegrenze hinweg gibt es KEINE Nachbarn, weder fuer
#     die Syntax noch fuer die Bildpunkte der Intra-Vorhersage.
mach slices   176 144  3 "testsrc2=size=176x144:rate=5" -g 1 -qp 26 \
     -x264-params slices=4

echo "PRUEFMATERIAL:"
while read -r name w h n; do
    s264=$(stat -c%s "$ZIEL/$name.264" 2>/dev/null || echo 0)
    syuv=$(stat -c%s "$ZIEL/$name.yuv" 2>/dev/null || echo 0)
    soll=$(( w * h * 3 / 2 * n ))
    printf '  %-10s %3dx%-3d %d Bilder  %6d Oktette .264  %8d YUV (soll %d)\n' \
        "$name" "$w" "$h" "$n" "$s264" "$syuv" "$soll"
done < "$ZIEL/liste.txt"
