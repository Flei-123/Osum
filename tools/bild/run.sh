#!/usr/bin/env bash
#
#   bash tools/bild/run.sh
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

ARB=${BILD_ARB:-$(mktemp -d)}
mkdir -p "$ARB"
export ARB
[ -n "${BILD_ARB:-}" ] || trap 'rm -rf "$ARB"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() {
    grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' steht da und sollte nicht" \
        || ok "$3"
}
num() {
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "BILD: uebersprungen, kein qemu"; exit 0; }
python3 -c 'import PIL' 2>/dev/null || {
    echo "BILD: uebersprungen, kein Pillow auf dem Wirt"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || true

B=tools/alltag/build.sh

# ============================================== 1. die Testbilder

echo "== 1. die Testbilder, auf dem Wirt mit Pillow gebaut =="

BILDER="$ARB/bilder"
python3 tools/bild/mkbilder.py "$BILDER" > "$ARB/mk.log" 2>&1 \
    && ok "mkbilder: $(grep -c . "$BILDER/liste.txt") Dateien" \
    || { bad "die Testbilder entstehen nicht"; tail -5 "$ARB/mk.log"; exit 1; }

XF="xdir=/b"
for f in "$BILDER"/g-*.gif "$BILDER"/b-*; do
    XF="$XF xfile=/b/$(basename "$f")=$f"
done

python3 - "$BILDER" <<'PYEOF'
import sys, os
d = sys.argv[1]
roh = open(os.path.join(d, "g-tafel.gif"), "rb").read()
open(os.path.join(d, "k-kurz.gif"), "wb").write(roh[:len(roh) // 2])
# Die Bildschirmgroesse im Kopf auf 4000x4000 luegen (Versatz 6..9).
b = bytearray(roh)
b[6] = 160; b[7] = 15; b[8] = 160; b[9] = 15
open(os.path.join(d, "k-luege.gif"), "wb").write(bytes(b))
# Eine Datei, die nur so heisst.
open(os.path.join(d, "k-kein.gif"), "wb").write(b"das ist kein GIF\n" * 4)
print("kaputte Dateien: 3")
PYEOF
for f in k-kurz.gif k-luege.gif k-kein.gif; do
    XF="$XF xfile=/b/$f=$BILDER/$f"
done
ok "drei kaputte Dateien dazugelegt"

echo
echo "== 2. GIF, PNG, BMP und JPEG lesen -- gegen Pillow =="

LESEN="g-einfarb.gif g-tafel.gif g-transp.gif g-lace.gif g-gerade.gif
       g-anim.gif g-gross.gif g-87a.gif b-probe.png b-pal.png
       b-probe.bmp b-voll.jpg"

: > "$ARB/vt1.sh"
for f in $LESEN; do echo "viewer -i /b/$f" >> "$ARB/vt1.sh"; done
for f in k-kurz.gif k-luege.gif k-kein.gif; do
    echo "viewer -i /b/$f" >> "$ARB/vt1.sh"
done

timeout 560 bash "$B" "$ARB/r1" script='sh /vt.sh;exit' \
    progs="viewer sh echo ls cat" desk=no shot=no themes=no bloecke=8192 \
    xfile=/vt.sh="$ARB/vt1.sh" $XF > "$ARB/r1.log" 2>&1
RC=$?
S="$ARB/r1/serial.txt"
if [ ! -s "$S" ]; then
    bad "der Lauf hat nichts gesagt (rc=$RC)"; tail -10 "$ARB/r1.log"
    echo; echo "BILD: $pass passed, $fail failed"; exit 1
fi
num "der Lauf beendet sich sauber" \
    "$(grep -aoE 'qemu exit [0-9]+' "$ARB/r1.log" | tail -1 | grep -oE '[0-9]+$')" eq 21
hat_nicht "$S" "panic" "kein Absturz beim Lesen"

REF=""
for f in $LESEN; do REF="$REF $BILDER/$f"; done
python3 tools/alltag/bildref.py pruefen "$S" $REF > "$ARB/ref.txt" 2>&1
GUT=$(grep -aoE 'bildref: [0-9]+ von [0-9]+' "$ARB/ref.txt" | grep -oE '[0-9]+' | head -1)
VON=$(grep -aoE 'bildref: [0-9]+ von [0-9]+' "$ARB/ref.txt" | grep -oE '[0-9]+' | tail -1)
sed 's/^/    /' "$ARB/ref.txt" | grep -aE 'OK|FAIL' || true
num "Bilder, die mit Pillow uebereinstimmen" "${GUT:-0}" eq "${VON:-12}"

hat "$S" "viewer: art=gif w=48 h=32 bilder=4" \
    "das animierte GIF: erstes Vollbild, vier Teilbilder erkannt"
hat "$S" "viewer: art=gif w=64 h=48" "das verschachtelte GIF wird gelesen"
hat "$S" "viewer: art=gif w=160 h=120" \
    "das grosse GIF (Woerterbuchloeschung) wird gelesen"

hat "$S" "viewer: datei k-kurz.gif" "die abgeschnittene Datei wurde versucht"
hat "$S" "geht nicht" "und abgelehnt, mit einem Grund"
hat_nicht "$S" "art=gif w=4000" "die erlogene Groesse wird nicht geglaubt"

echo
echo "== 3. sichern: als PNG (verlustfrei) und als JPEG (neu) =="

cat > "$ARB/vt2.sh" <<'EOF'
viewer -s /s-gif.png /b/g-tafel.gif
viewer -s /s-lace.png /b/g-lace.gif
viewer -s /s-bmp.png /b/b-probe.bmp
viewer -s /s-png.jpg /b/b-probe.png
viewer -s /s-jpg.jpg /b/b-voll.jpg
viewer -s /s-gif.jpg /b/g-tafel.gif
EOF

timeout 560 bash "$B" "$ARB/r2" script='sh /vt.sh;exit' \
    progs="viewer sh echo ls cat" desk=no shot=no themes=no bloecke=8192 \
    keep=yes xfile=/vt.sh="$ARB/vt2.sh" $XF > "$ARB/r2.log" 2>&1
S2="$ARB/r2/serial.txt"
num "auch dieser Lauf beendet sich sauber" \
    "$(grep -aoE 'qemu exit [0-9]+' "$ARB/r2.log" | tail -1 | grep -oE '[0-9]+$')" eq 21
hat_nicht "$S2" "panic" "kein Absturz beim Sichern"
hat "$S2" "viewer: sichern s-gif.png gif w=40 h=30" "GIF als PNG gesichert"
hat "$S2" "viewer: sichern s-png.jpg png w=48 h=36" "PNG als JPEG gesichert"
hat "$S2" "viewer: sichern s-jpg.jpg jpeg w=64 h=48" "JPEG als JPEG gesichert"
hat_nicht "$S2" "sichern nein" "kein Sichern ist fehlgeschlagen"

HOL="$ARB/hol"
mkdir -p "$HOL"
geholt=0
for f in s-gif.png s-lace.png s-bmp.png s-png.jpg s-jpg.jpg s-gif.jpg; do
    if python3 tools/osum/mkfs.py cat "$ARB/r2/disk.img" "/$f" \
            > "$HOL/$f" 2>/dev/null && [ -s "$HOL/$f" ]; then
        geholt=$((geholt+1))
    fi
done
num "Dateien vom Abbild geholt" "$geholt" eq 6

if command -v file >/dev/null 2>&1; then
    file "$HOL/s-png.jpg" | grep -qa 'JPEG image data' \
        && ok "file(1) nennt es JPEG: $(file -b "$HOL/s-png.jpg" | cut -c1-58)" \
        || bad "file(1) erkennt die geschriebene Datei nicht als JPEG"
    file "$HOL/s-gif.png" | grep -qa 'PNG image data' \
        && ok "file(1) nennt es PNG" \
        || bad "file(1) erkennt die geschriebene Datei nicht als PNG"
fi

# ============================================== 4. der Umlauf, gemessen

echo
echo "== 4. der Umlauf: was wir geschrieben haben, mit Pillow nachgelesen =="

python3 tools/bild/pruefen.py "$BILDER" "$HOL" > "$ARB/umlauf.txt" 2>&1
RCU=$?
sed 's/^/    /' "$ARB/umlauf.txt"
if [ "$RCU" -eq 0 ]; then
    ok "der Umlauf haelt die Schranken ein"
else
    bad "der Umlauf reisst eine Schranke"
fi

# ============================================== 5. das Fenster

echo
echo "== 5. das Fenster: die GIF-Datei kommt an, und die Leiste passt =="

timeout 560 bash "$B" "$ARB/r3" progs="viewer sh echo ls cat theme" \
    desk=no shot=no themes=no bloecke=8192 \
    xdir=/b xfile=/b/g-anim.gif="$BILDER/g-anim.gif" \
    extra="wigapp=/bin/viewer,/b/g-anim.gif" > "$ARB/r3.log" 2>&1
S3="$ARB/r3/serial.txt"
if [ -s "$S3" ]; then
    hat "$S3" "viewer: bild g-anim.gif" \
        "der Ordnerleser findet die GIF-Datei (ist_bildname kennt gif)"
    hat "$S3" "1/4" "und der Kopf sagt, dass es Teilbild 1 von 4 ist"
    hat_nicht "$S3" "viewer: bild kein Bild" "es steht NICHT 'kein Bild' da"
    SW=$(grep -aoE 'viewer: rect id=[0-9]+ kind=17 x=[0-9]+ y=[0-9]+ w=[0-9]+' "$S3" \
        | tail -1 | grep -oE 'w=[0-9]+$' | cut -d= -f2)
    num "der Schieberegler behaelt seine Breite" "${SW:-0}" ge 120
else
    bad "der Fensterlauf hat nichts gesagt"
fi

# ============================================== Schluss

echo
echo "BILD: $pass passed, $fail failed"
[ -n "${BILD_ARB:-}" ] && echo "  (Arbeitsverzeichnis: $ARB)"
[ "$fail" -eq 0 ] || exit 1
exit 0
