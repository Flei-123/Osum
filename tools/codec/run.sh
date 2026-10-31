#!/usr/bin/env bash
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
. tools/lib/userprog.sh      # up_build
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
PROGS="sh cat echo h264t"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name wert op soll
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
gleich() { # name soll ist
    if [ "$2" = "$3" ]; then ok "$1"
    else bad "$1"; printf '        soll: %s\n        ist : %s\n' "$2" "$3"; fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

wert() { grep -a -m1 "^h264: $2 = " "$1" 2>/dev/null | sed 's/.* = //' \
         | tr -d '\r\000'; }

echo "== 0. die Vorbedingungen =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 \
    || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "CODEC: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; }
for w in ffmpeg python3 sha256sum; do
    command -v "$w" >/dev/null 2>&1 || {
        echo "CODEC: uebersprungen, $w fehlt"; exit 0; }
done
ffmpeg -hide_banner -encoders > "$TMPD/enc.txt" 2>/dev/null || true
grep -q libx264 "$TMPD/enc.txt" || {
    echo "CODEC: uebersprungen, ffmpeg kann kein libx264"; exit 0; }
ok "die Werkzeuge des Wirts sind da (ffmpeg mit libx264, qemu, python3)"

# ------------------------------------------------- 1. die Speicherkarte

echo "== 1. die Speicherkarte von kdata =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Karte: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/karte.txt" | head -10
fi
hat "$TMPD/karte.txt" "0 Kollisionen" "keine zwei Bereiche ueberschneiden sich"

v=$(grep -aE "^const CODEC_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
m=$(grep -aE "^const CODEC_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ "$((v))" -eq $((0x118000)) ] && [ "$((v + m))" -le $((0x120000)) ]; then
    ok "CODEC_OFF = $v, CODEC_MAX = $m -- genau der zugeteilte Bereich 0x118000..0x120000"
else
    bad "CODEC_OFF = ${v:-fehlt} (+${m:-?}) liegt AUSSERHALB von 0x118000..0x120000"
fi

mkdir -p "$TMPD/kollision"
( cd kernel && find . -name '*.fi' -exec cp --parents {} "$TMPD/kollision/" \; )
sed -i 's/^const CODEC_OFF: u64 = 0x118000$/const CODEC_OFF: u64 = 0x108000/' \
    "$TMPD/kollision/lib/kstate.fi"
if python3 tools/kernel/memmap.py "$TMPD/kollision" > "$TMPD/karte2.txt" 2>&1; then
    bad "GEGENPROBE: CODEC_OFF auf 0x108000 (= WMP_OFF) und der Pruefer schweigt"
else
    ok "GEGENPROBE: CODEC_OFF auf WMP_OFF gelegt -- der Kartenpruefer schlaegt an"
fi

if [ "$((m))" -le $((0x8000)) ]; then
    ok "der Bereich ist $((m / 1024)) KiB -- zu klein fuer einen Bildpuffer, also liegt dort keiner"
else
    bad "CODEC_MAX = $m ist groesser als die zugeteilten acht Seiten"
fi

# ------------------------------------------- 2. die erzeugten Tafeln

echo "== 2. die Zahlentafeln: erzeugt, nicht abgetippt =="
if python3 tools/codec/mktab.py > "$TMPD/h264tab.fi" 2>"$TMPD/tab.err"; then
    if cmp -s "$TMPD/h264tab.fi" kernel/user/h264tab.fi; then
        ok "kernel/user/h264tab.fi ist genau das, was mktab.py erzeugt"
    else
        bad "kernel/user/h264tab.fi weicht von mktab.py ab -- von Hand geaendert?"
    fi
else
    bad "tools/codec/mktab.py scheitert"
    sed 's/^/        /' "$TMPD/tab.err" | head -5
fi

if python3 tools/codec/praefix.py > "$TMPD/praefix.txt" 2>&1; then
    ok "alle CAVLC-Tafeln sind praefixfrei: $(tail -1 "$TMPD/praefix.txt")"
else
    bad "eine CAVLC-Tafel ist MEHRDEUTIG"
    sed 's/^/        /' "$TMPD/praefix.txt" | head -10
fi

# ----------------------------------------------------------- 3. bauen

echo "== 3. bauen: der Kern und die Programme, aus beiden Uebersetzern =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s laesst sich nicht assemblieren"

baue_stufe() { # 0 | 1
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" \
        > "$TMPD/k$s.log" 2>&1 || {
        bad "firnc$s: der Kern laesst sich nicht bauen"
        grep -viE 'warning|^\s+\||^\s+=|note:' "$TMPD/k$s.log" | tail -12 \
            | sed 's/^/        /'
        return 1
    }
    for p in $PROGS; do
        up_build "$cc" "$p" "$TMPD/$p$s.o" "$TMPD/$p$s.elf" "$TMPD/crt.o" \
            "$ULD" "$s" "$TMPD/e$p$s" || {
            bad "firnc$s baut $p nicht"
            grep -viE 'GNU-stack|RWX' "$TMPD/e$p$s" | head -8 | sed 's/^/        /'
            rc=1
        }
    done
    return $rc
}
baue_stufe 0 || { echo "== CODEC: $pass bestanden, $((fail+1)) gescheitert =="; exit 1; }
ok "firnc0: der Kern und $(echo $PROGS | wc -w) Programme sind gebaut"
if baue_stufe 1; then
    ok "firnc1: dasselbe aus dem Uebersetzer, der in Firn geschrieben ist"
else
    bad "firnc1 baut diese Runde nicht"
fi

for f in kernel/user/h264.fi kernel/user/h264tab.fi; do
    sed 's://.*::' "$f" > "$TMPD/ohnekomm.fi"
    if grep -qaE '\b(f32|f64)\b|allow_fp|std\.math' "$TMPD/ohnekomm.fi"; then
        bad "$f enthaelt Fliesskomma -- damit ist Bitgleichheit nicht zu haben"
        grep -naE '\b(f32|f64)\b|allow_fp|std\.math' "$TMPD/ohnekomm.fi" \
            | head -5 | sed 's/^/        /'
    else
        ok "kein Fliesskomma im Code von $(basename "$f") (keine f32/f64, kein allow_fp, kein std.math)"
    fi
done

# ------------------------------------------------- 4. das Pruefmaterial

echo "== 4. das Pruefmaterial, vom WIRT mit x264 gebaut =="
MED="$TMPD/m"
if bash tools/codec/mkmedia.sh "$MED" > "$TMPD/med.log" 2>&1; then
    ok "$(grep -c . "$MED/liste.txt") Stroeme stehen (Baseline, I und I+P)"
    sed -n '2,$p' "$TMPD/med.log" | sed 's/^/        /'
else
    bad "tools/codec/mkmedia.sh scheitert"
    tail -10 "$TMPD/med.log" | sed 's/^/        /'
    echo "== CODEC: $pass bestanden, $fail gescheitert =="
    exit 1
fi

for f in "$MED"/*.264; do
    pr=$(ffprobe -v error -select_streams v:0 -show_entries stream=profile \
         -of csv=p=0 "$f" 2>/dev/null)
    case "$pr" in
        Constrained\ Baseline|Baseline) ;;
        *) bad "$(basename "$f"): Profil '$pr' statt Baseline"; ;;
    esac
done
ok "alle Stroeme tragen das Baseline-Profil (ffprobe)"

sl=$(python3 tools/codec/nalzahl.py "$MED/slices.264" 2>/dev/null)
sl_n=$(echo "$sl" | cut -d' ' -f1)
sl_fm=$(echo "$sl" | cut -d' ' -f3)
num "der Strom 'slices' hat so viele Slice-Einheiten (3 Bilder x 4)" \
    "${sl_n:-0}" eq 12
case "$sl_fm" in
    0,*) ok "und sie fangen bei verschiedenen Makrobloecken an ($sl_fm)" ;;
    *) bad "die first_mb_in_slice-Werte sehen falsch aus: $sl_fm" ;;
esac

ffmpeg -y -v error -f lavfi -i testsrc2=size=128x96:rate=5 -frames:v 2 \
    -c:v libx264 -profile:v high -pix_fmt yuv420p -f h264 \
    "$MED/x_high.264" 2>/dev/null \
    && ok "ein HIGH-Profile-Strom fuer die Gegenprobe steht" \
    || bad "der High-Profile-Strom laesst sich nicht bauen"
ffmpeg -y -v error -f lavfi -i testsrc2=size=128x96:rate=5 -frames:v 2 \
    -c:v libx264 -profile:v main -coder 1 -pix_fmt yuv420p -f h264 \
    "$MED/x_cabac.264" 2>/dev/null \
    && ok "ein CABAC-Strom (Main) fuer die Gegenprobe steht" \
    || bad "der CABAC-Strom laesst sich nicht bauen"

ffmpeg -y -v error -f lavfi -i testsrc2=size=1920x1080:rate=5 -frames:v 1 \
    -c:v libx264 -profile:v baseline -pix_fmt yuv420p -f h264 \
    "$MED/x_gross.264" 2>/dev/null \
    && ok "ein 1920x1080-Strom fuer die Grenzprobe steht" \
    || bad "der 1920x1080-Strom laesst sich nicht bauen"

# ------------------------------------------------------ 5. die Platte

echo "== 5. die Wurzelplatte =="
MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/${p}0.elf"; done
for f in "$MED"/*.264; do MKARGS="$MKARGS /v/$(basename "$f")=$f"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" 16384 --inodes=128 \
    /bin/ /v/ $MKARGS > "$TMPD/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht: $(tail -1 "$TMPD/mkfs.log")" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.log" | head -5; }

lauf() { # name kommandozeile [zeitlimit]
    local name=$1 app=$2 t=${3:-300}
    cp --sparse=always "$TMPD/root.img" "$TMPD/live-$name.img"
    local cpuarg=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && cpuarg="-cpu host"
    # shellcheck disable=SC2086
    timeout "$t" $QEMU_X86 $cpuarg -kernel "$TMPD/k0.mb" -m 512 \
        -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        > /dev/null 2>&1
    echo $?
}

# ============================================== 6. DIE GEGENPROBE
#

echo "== 6. die ffmpeg-Gegenprobe: jedes Bild, jede Pruefsumme =="
GESAMT_BILDER=0
GESAMT_GLEICH=0
NUR=${OSUM_CODEC_SCHNELL:-0}
while read -r name w h nf; do
    if [ "$NUR" = 1 ]; then
        case "$name" in i_klein|p_klein) ;; *) continue ;; esac
    fi
    rc=$(lauf "$name" "osum nokbd script=h264t /v/$name.264")
    D="$TMPD/$name.txt"
    if [ "$rc" != 21 ]; then
        bad "[$name] der Kernel beendet sich nicht selbst (rc=$rc)"
        continue
    fi
    if [ ! -f "$D" ]; then bad "[$name] keine serielle Ausgabe"; continue; fi
    python3 tools/codec/mkyuvsha.py "$MED/$name.yuv" "$w" "$h" \
        > "$TMPD/$name.soll" 2>/dev/null
    gleich_hier=1
    n_hier=0
    while read -r i soll; do
        n_hier=$((n_hier+1))
        GESAMT_BILDER=$((GESAMT_BILDER+1))
        ist=$(grep -a -m1 "^h264: sha $i = " "$D" | sed 's/.* = //' | tr -d '\r\000')
        if [ "$ist" = "$soll" ]; then
            GESAMT_GLEICH=$((GESAMT_GLEICH+1))
        else
            gleich_hier=0
            printf '        Bild %s  ffmpeg %s\n                 Osum   %s\n' \
                "$i" "$soll" "${ist:-(fehlt)}"
        fi
    done < "$TMPD/$name.soll"
    fr=$(wert "$D" frames); er=$(wert "$D" err)
    kf=$(wert "$D" kframes); kw=$(wert "$D" kw); kh=$(wert "$D" kh)
    ms=$(wert "$D" ms); fps=$(wert "$D" fps)
    if [ "$gleich_hier" = 1 ] && [ "$fr" = "$nf" ] && [ "$er" = 0 ]; then
        ok "[$name] ${w}x${h}, $fr Bilder BITGLEICH -- $ms ms, $((fps/100)).$(printf %02d $((fps%100))) Bilder/s"
    else
        bad "[$name] ${w}x${h}: $fr von $nf Bildern, err=$er, $n_hier Summen geprueft"
    fi
    gleich "[$name] der Kern zaehlt dieselben Bilder (kdata CODEC_OFF)" "$nf" "$kf"
    gleich "[$name] der Kern kennt die Breite" "$w" "$kw"
    gleich "[$name] der Kern kennt die Hoehe" "$h" "$kh"
done < "$MED/liste.txt"
num "die Gegenprobe insgesamt: bitgleiche Bilder" "$GESAMT_GLEICH" eq "$GESAMT_BILDER"

echo "== 7. die Gegenproben: was ABGEWIESEN werden muss =="

rc=$(lauf high "osum nokbd script=h264t /v/x_high.264")
num "[high] der Kernel beendet sich selbst statt zu haengen" "$rc" eq 21
er=$(wert "$TMPD/high.txt" err)
fr=$(wert "$TMPD/high.txt" frames)
gleich "[high] ein High-Profile-Strom wird ABGEWIESEN (err=2, nicht Baseline)" "2" "$er"
gleich "[high] und es entsteht KEIN Bild" "0" "$fr"

rc=$(lauf cabac "osum nokbd script=h264t /v/x_cabac.264")
num "[cabac] der Kernel beendet sich selbst" "$rc" eq 21
er=$(wert "$TMPD/cabac.txt" err)
if [ "$er" = 2 ] || [ "$er" = 3 ]; then
    ok "[cabac] ein CABAC-Strom wird ABGEWIESEN (err=$er)"
else
    bad "[cabac] ein CABAC-Strom wird NICHT abgewiesen (err=$er)"
fi

echo "== 7c. abgeschnittene Stroeme =="
kurz_ok=0; kurz_bad=0
for SRC in "$MED/i_sd.264" "$MED/slices.264"; do
G=$(stat -c%s "$SRC")
for teil in 1 2 3 5 8 13 21 34 55 89; do
    n=$((G * teil / 100))
    head -c "$n" "$SRC" > "$TMPD/kurz.264"
    cp --sparse=always "$TMPD/root.img" "$TMPD/live-kurz.img"
    python3 tools/osum/mkfs.py build "$TMPD/kurz.img" 16384 --inodes=128 \
        /bin/ /v/ "/bin/sh=$TMPD/sh0.elf" "/bin/h264t=$TMPD/h264t0.elf" \
        "/v/kurz.264=$TMPD/kurz.264" > /dev/null 2>&1
    cpuarg=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && cpuarg="-cpu host"
    # shellcheck disable=SC2086
    timeout 120 $QEMU_X86 $cpuarg -kernel "$TMPD/k0.mb" -m 512 \
        -append "osum nokbd script=h264t /v/kurz.264" \
        -serial "file:$TMPD/kurz.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/kurz.img,format=raw,if=ide,index=0" >/dev/null 2>&1
    r=$?
    if [ "$r" = 21 ]; then kurz_ok=$((kurz_ok+1)); else
        kurz_bad=$((kurz_bad+1))
        printf '        %s %d%% (%d Oktette): rc=%s\n' \
            "$(basename "$SRC")" "$teil" "$n" "$r"
    fi
done
done
num "abgeschnittene Stroeme, die sauber enden (von 20)" "$kurz_ok" eq 20
num "abgeschnittene Stroeme, die haengen oder abstuerzen" "$kurz_bad" eq 0

# 7d. VERFAELSCHTE Oktette. Dasselbe in Grausam: einzelne Bits kippen.
echo "== 7d. verfaelschte Oktette =="
kipp_ok=0; kipp_bad=0
for seed in 1 2 3 4 5 6 7 8 9 10 11 12; do
    python3 - "$SRC" "$TMPD/kipp.264" "$seed" <<'PYEOF'
import random, sys
src, ziel, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = bytearray(open(src, 'rb').read())
r = random.Random(seed)
# Den Anfang (SPS/PPS) in Ruhe lassen: es geht um den SLICE-Inhalt.
for _ in range(6):
    p = r.randrange(64, len(d))
    d[p] ^= 1 << r.randrange(8)
open(ziel, 'wb').write(bytes(d))
PYEOF
    python3 tools/osum/mkfs.py build "$TMPD/kipp.img" 16384 --inodes=128 \
        /bin/ /v/ "/bin/sh=$TMPD/sh0.elf" "/bin/h264t=$TMPD/h264t0.elf" \
        "/v/kipp.264=$TMPD/kipp.264" > /dev/null 2>&1
    cpuarg=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && cpuarg="-cpu host"
    # shellcheck disable=SC2086
    timeout 120 $QEMU_X86 $cpuarg -kernel "$TMPD/k0.mb" -m 512 \
        -append "osum nokbd script=h264t /v/kipp.264" \
        -serial "file:$TMPD/kipp-$seed.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/kipp.img,format=raw,if=ide,index=0" >/dev/null 2>&1
    r=$?
    if [ "$r" = 21 ]; then kipp_ok=$((kipp_ok+1)); else
        kipp_bad=$((kipp_bad+1))
        printf '        Saat %d: rc=%s\n' "$seed" "$r"
    fi
done
num "verfaelschte Stroeme, die sauber enden (von 12)" "$kipp_ok" eq 12
num "verfaelschte Stroeme, die haengen oder abstuerzen" "$kipp_bad" eq 0

echo "== 7e. Unsinn =="
: > "$TMPD/leer.264"
head -c 4096 /dev/urandom > "$TMPD/muell.264"
printf '\x00\x00\x01' > "$TMPD/stub.264"
unsinn_ok=0
for f in leer muell stub; do
    python3 tools/osum/mkfs.py build "$TMPD/u.img" 16384 --inodes=128 \
        /bin/ /v/ "/bin/sh=$TMPD/sh0.elf" "/bin/h264t=$TMPD/h264t0.elf" \
        "/v/u.264=$TMPD/$f.264" > /dev/null 2>&1
    cpuarg=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && cpuarg="-cpu host"
    # shellcheck disable=SC2086
    timeout 120 $QEMU_X86 $cpuarg -kernel "$TMPD/k0.mb" -m 512 \
        -append "osum nokbd script=h264t /v/u.264" \
        -serial "file:$TMPD/u-$f.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/u.img,format=raw,if=ide,index=0" >/dev/null 2>&1
    [ $? = 21 ] && unsinn_ok=$((unsinn_ok+1))
done
num "Unsinn als Eingabe, sauber abgewiesen (von 3)" "$unsinn_ok" eq 3

# ---------------------------------------------------- 8. check-ui

echo "== 7f. die Kreisprobe: schneller gegen langsamen Weg der MC =="
while read -r name w h nf; do
    if [ "$NUR" = 1 ]; then
        case "$name" in i_klein|p_klein) ;; *) continue ;; esac
    fi
    rc=$(lauf "l_$name" "osum nokbd script=h264t --langsam /v/$name.264")
    if [ "$rc" != 21 ]; then
        bad "[$name] der langsame Weg beendet sich nicht selbst (rc=$rc)"
        continue
    fi
    a=$(grep -a '^h264: sha ' "$TMPD/$name.txt" 2>/dev/null | tr -d '\r\000' | sort)
    b=$(grep -a '^h264: sha ' "$TMPD/l_$name.txt" 2>/dev/null | tr -d '\r\000' | sort)
    na=$(printf '%s\n' "$a" | grep -c . || true)
    if [ -n "$a" ] && [ "$a" = "$b" ]; then
        ok "[$name] schneller Weg == langsamer Weg, $na Bilder oktettweise gleich"
    else
        bad "[$name] der schnelle Weg weicht vom langsamen ab"
        diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -4 | sed 's/^/        /'
    fi
done < "$MED/liste.txt"

echo "== 7g. ueber der Grenze (1280x720) wird abgewiesen =="
rc=$(lauf gross "osum nokbd script=h264t /v/x_gross.264")
num "[gross] der Kernel beendet sich selbst statt zu haengen" "$rc" eq 21
er=$(wert "$TMPD/gross.txt" err)
fr=$(wert "$TMPD/gross.txt" frames)
gleich "[gross] 1920x1080 wird ABGEWIESEN (err=4, zu gross)" "4" "$er"
gleich "[gross] und es entsteht KEIN Bild" "0" "$fr"

echo "== 8. die Oberflaechenregel =="
if bash tools/check-ui.sh > "$TMPD/ui.txt" 2>&1; then
    ok "check-ui: $(tail -1 "$TMPD/ui.txt")"
else
    bad "check-ui schlaegt fehl"
    tail -10 "$TMPD/ui.txt" | sed 's/^/        /'
fi

echo
echo "== CODEC: $pass bestanden, $fail gescheitert =="
[ "$fail" = 0 ] || exit 1
exit 0
