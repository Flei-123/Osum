#!/usr/bin/env bash
#
#   bash tools/clip2/run.sh [arbeitsverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
if [ -n "${1:-}" ]; then
    OUT=$1
else
    OUT=$(mktemp -d)
    trap 'rm -rf "$OUT"' EXIT
fi
mkdir -p "$OUT"
SHOTS=${CLIP2_SHOTS:-$ROOT/.clip2-shots}
mkdir -p "$SHOTS"
RES=${RES:-1280x800}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaE "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- fehlt: $2"; }
hatnicht() { grep -qaE "$2" "$1" 2>/dev/null && bad "$3 -- '$2' sollte NICHT da sein" || ok "$3"; }
letzte() { grep -aoE "$2" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'; }
groesste() { grep -aoE "$2" "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "CLIP-2: skipped, qemu-system-x86_64 is not there"; exit 0
fi

# =================================================== 1. der Quelltext
#
echo "== 1. Quelltext =="
grep -qE '^const K_DROP: u64 = [0-9]+' <(bash tools/structure/catprog.sh kernel/user/fuiapp/wlib.fi) \
    && ok "wlib kennt K_DROP" || bad "wlib kennt kein K_DROP"
grep -qE 'fire\(d, K_DROP, line, w\)' <(bash tools/structure/catprog.sh kernel/user/fuiapp/wlib.fi) \
    && ok "on_up feuert K_DROP" || bad "on_up feuert kein K_DROP"
grep -qE 'fn drop_an\(' <(bash tools/structure/catprog.sh kernel/user/fuiapp/wlib.fi) \
    && ok "wlib has drop_an (a window registers as a target)" \
    || bad "wlib has no drop_an"
grep -qE 'fuiscene\.drop_accept\(true\)' <(bash tools/structure/srcview.sh kernel/user/explorer.fi) \
    && ok "the file manager registers as a drop target" \
    || bad "the file manager does not register"
grep -qE 'fn ablegen\(' <(bash tools/structure/srcview.sh kernel/user/explorer.fi) \
    && ok "the file manager has a drop function" \
    || bad "the file manager has no drop function"
grep -qE 'expakt\.paste' <(bash tools/structure/srcview.sh kernel/user/explorer.fi) \
    && ok "dropping goes through expakt.einfuegen (so io.rename)" \
    || bad "das Ablegen geht an expakt vorbei"
if grep -qE 'io\.(create|write_all|unlink)\(' <(bash tools/structure/srcview.sh kernel/user/explorer.fi); then
    bad "explorer.fi fasst Dateien selbst an"
else
    ok "explorer.fi does not touch any file itself"
fi
if grep -qE 'wlibc\.drag_take' <(bash tools/structure/srcview.sh kernel/user/explorer.fi); then
    bad "the file manager calls wlibc.drag_take past the library"
else
    ok "negative test: no wlibc.drag_take in the file manager"
fi

# ======================================================== 2. der Bau
echo "== 2. bauen =="
export DESIGNBUILD=${DESIGNBUILD:-$OUT/designbuild}
bash tools/design/capture.sh "$OUT/bau" nurbau=ja res="$RES" \
    > "$OUT/bau.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: der Bau"; tail -20 "$OUT/bau.log"; exit 1; }
ok "Kern und Programme uebersetzen"

# ======================================================== 3. der Lauf
#
echo "== 3. der Lauf =="
cat > "$OUT/dreh.txt" <<'DREH'
warteauf explorer: ready || 240
warte 8
foto 20-vorher
ziehvon ftabzeile1 ftabzeile3
warte 6
foto 21-leerlauf
ziehvon ftabzeile2 ftabzeile0
warte 8
foto 22-abgelegt
doppelauf ftabzeile0
warteauf explorer: cd /data/bilder || 60
warte 5
foto 23-in-bilder
DREH

bash tools/design/capture.sh "$OUT/lauf" res="$RES" \
    extra='nostart wigapp=/bin/explorer' uitrace=yes vorherbild=ja drehbuch="$OUT/dreh.txt" \
    > "$OUT/lauf.log" 2>&1
S="$OUT/lauf/serial.txt"
if [ ! -s "$S" ]; then
    echo "FAILED: no serial output"; tail -20 "$OUT/lauf.log"; exit 1
fi
hat "$S" 'explorer: ready' "der Dateimanager ist hochgekommen"
grep -qa 'KEIN RECHTECK GEMELDET' "$OUT/lauf.log" \
    && bad "a ziehvon did not find its rectangle (see lauf.log)" \
    || ok "every ziehvon found its two rectangles"

echo "== 4. Punkt 1: die Naht =="
hat "$S" 'explorer: drops [0-9]+' "wlib meldet das Ablegen (K_DROP)"
dn=$(groesste "$S" 'explorer: drops [0-9]+')
[ "${dn:-0}" -ge 2 ] 2>/dev/null \
    && ok "Punkt 1: $dn Ablegungen gemeldet" \
    || bad "point 1: only ${dn:-0} drops reported -- expected >= 2"

# ------------------------------------- Punkt 2/5: was die Leitung sagt
echo "== 5. points 2 and 5: the deed and the idle time =="
hat "$S" 'expl: drop /data/alpha\.txt q=/data/bilder' \
    "Punkt 2: alpha.txt wurde auf /data/bilder abgelegt"
hat "$S" 'expl: drop /data/notizen q=/data same' \
    "Punkt 5: das Ablegen im selben Ordner wurde als 'gleich' erkannt"
hatnicht "$S" 'explorer: dlgrect' \
    "Punkt 5: kein Dialog beim Ablegen im selben Ordner"
drc=$(grep -aoE 'expl: drop\* rc=[0-9]+' "$S" | tail -1 \
      | grep -oE '[0-9]+$')
[ "${drc:-1}" = "0" ] \
    && ok "Punkt 2: das Ablegen meldete rc=0" \
    || bad "Punkt 2: das Ablegen meldete rc=${drc:-?}"

echo "== 6. the disk (read by the host) =="
IMG="$OUT/lauf/disk.img"
if [ ! -s "$IMG" ]; then
    bad "no disk image to look at"
else
    #
    VOR=""
    if [ -s "$OUT/lauf/disk.img.vorher" ]; then
        VOR=$(python3 tools/clip2/read.py "$OUT/lauf/disk.img.vorher" \
              2>/dev/null \
              | grep -oE '^da /data/alpha\.txt ino=[0-9]+' \
              | grep -oE '[0-9]+$')
    fi
    if [ -n "$VOR" ]; then
        ok "the inode of /data/alpha.txt before the run: $VOR"
    else
        bad "MEASUREMENT INCOMPLETE: the inode before the run is not readable"
    fi
    python3 tools/clip2/read.py "$IMG" ${VOR:+"$VOR"} \
        > "$OUT/platte.txt" 2>"$OUT/platte.err"
    if [ -s "$OUT/platte.txt" ]; then
        cat "$OUT/platte.txt"
        grep -qE '^da /data/bilder/alpha\.txt ' "$OUT/platte.txt" \
            && ok "Punkt 2: alpha.txt liegt in /data/bilder" \
            || bad "point 2: alpha.txt does NOT lie in /data/bilder"
        grep -qE '^weg /data/alpha\.txt' "$OUT/platte.txt" \
            && ok "point 2: alpha.txt is no longer in /data" \
            || bad "point 2: alpha.txt is still in /data -- copied instead of moved?"
        # Punkt 3: dieselbe Inode, derselbe Inhalt.
        grep -qE '^inode gleich' "$OUT/platte.txt" \
            && ok "Punkt 3: dieselbe Inodenummer -- umgehaengt, nicht kopiert" \
            || bad "point 3: the inode number changed"
        grep -qE '^inhalt ok' "$OUT/platte.txt" \
            && ok "point 3: the content is unchanged ('eins')" \
            || bad "point 3: the content does not match"
        grep -qE '^da /data/notizen ' "$OUT/platte.txt" \
            && ok "Punkt 5: notizen liegt unveraendert in /data" \
            || bad "Punkt 5: notizen ist verschwunden"
    else
        bad "the image could not be read"; head -5 "$OUT/platte.err"
    fi
fi

echo "== 7. the negative test: without drop_an wlib registers nothing =="
GEG=$OUT/gegen
mkdir -p "$GEG"
#
GBAUM="$GEG/baum"
EXPL_SHA0=$(bash tools/structure/srcview.sh kernel/user/explorer.fi | sha256sum | cut -d' ' -f1)
rm -rf "$GBAUM"; mkdir -p "$GBAUM"
tar -C "$ROOT" --exclude=./.git --exclude=./docs --exclude=./pruef \
    --exclude=./.gauntlet-shots --exclude=./.clip2-shots -cf - . \
    | tar -C "$GBAUM" -xf -
if ! grep -qE '^\s*fuiscene\.drop_accept\(true\)' "$GBAUM"/kernel/user/explorer/*.fi; then
    bad "GEGENPROBE GREIFT NICHT: 'fuiscene.drop_accept(true)' steht gar nicht da"
else
    ok "negative test holds: the line 'fuiscene.drop_accept(true)' ist da"
    sed -i 's/^\(\s*\)fuiscene\.drop_accept(true)/\1fuiscene.drop_accept(false)/' \
        "$GBAUM"/kernel/user/explorer/*.fi
    if grep -qE '^\s*fuiscene\.drop_accept\(false\)' "$GBAUM"/kernel/user/explorer/*.fi; then
        ok "negative test: the registration is set to false"
        export DESIGNBUILD="$GEG/designbuild"
        bash "$GBAUM/tools/design/capture.sh" "$GEG/bau" nurbau=ja res="$RES" \
            > "$GEG/bau.log" 2>&1
        if [ $? -ne 0 ]; then
            bad "NEGATIVE TEST MEASURES NOTHING: the build without drop_an did not go through"
            tail -10 "$GEG/bau.log"
        else
            ok "negative test: the build without drop_an goes through"
            cp "$OUT/dreh.txt" "$GEG/dreh.txt"
            bash "$GBAUM/tools/design/capture.sh" "$GEG/lauf" res="$RES" \
                extra='nostart wigapp=/bin/explorer' uitrace=yes \
                drehbuch="$GEG/dreh.txt" > "$GEG/lauf.log" 2>&1
            GS="$GEG/lauf/serial.txt"
            if [ ! -s "$GS" ]; then
                bad "NEGATIVE TEST MEASURES NOTHING: no serial output"
            else
                # Sie muss ueberhaupt gelaufen sein ...
                if grep -qaE 'explorer: ready' "$GS"; then
                    ok "negative test: the file manager came up even without drop_an"
                    hatnicht "$GS" 'explorer: drops [0-9]+' \
                        "GEGENPROBE: ohne drop_an meldet wlib kein Ablegen"
                    hatnicht "$GS" 'expl: drop ' \
                        "GEGENPROBE: ohne drop_an legt der Dateimanager nichts ab"
                    GIMG="$GEG/lauf/disk.img"
                    if [ -s "$GIMG" ]; then
                        python3 tools/clip2/read.py "$GIMG" \
                            > "$GEG/platte.txt" 2>/dev/null
                        grep -qE '^da /data/alpha\.txt ' "$GEG/platte.txt" \
                            && ok "GEGENPROBE: alpha.txt blieb in /data" \
                            || bad "NEGATIVE TEST MEASURES NOTHING: alpha.txt is gone anyway"
                    fi
                else
                    bad "NEGATIVE TEST MEASURES NOTHING: the file manager did not come up"
                fi
            fi
        fi
    else
        bad "NEGATIVE TEST DOES NOT HOLD: sed changed nothing"
    fi
fi
rm -rf "$GBAUM"
[ "$(bash tools/structure/srcview.sh kernel/user/explorer.fi | sha256sum | cut -d' ' -f1)" = "$EXPL_SHA0" ] \
    && ok "kernel/user/explorer.fi in the tree is untouched" \
    || bad "WARNING: kernel/user/explorer.fi in the tree was changed"

# ============================================================ 8. Bilder
echo "== 8. die Bilder =="
if python3 -c "import PIL" 2>/dev/null; then
    python3 - "$OUT/lauf" <<'PY'
import glob, os, sys
from PIL import Image
for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.ppm"))):
    Image.open(p).convert("RGB").save(p[:-4] + ".png")
PY
    n=0
    for f in "$OUT/lauf"/*.png; do
        [ -e "$f" ] || continue
        n=$((n+1)); cp "$f" "$SHOTS/"
    done
    [ "$n" -ge 3 ] && ok "$n Aufnahmen entstanden" || bad "only $n recordings"
else
    echo "  (Pillow missing, no pictures)"
fi

echo
echo "================= CLIP-2 ================="
echo "  gruen $pass   rot $fail"
echo "  Ablage: $OUT"
[ "$fail" -eq 0 ] || exit 1
