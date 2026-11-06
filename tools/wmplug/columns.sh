#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
SHOTS="docs/shots/wmplug"
GAUNTLET=".gauntlet-shots"
mkdir -p "$SHOTS"

TMPD=$(mktemp -d /tmp/wmplug-spalten-XXXXXX)
[ "${SPALTEN_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "SPALTEN: skipped, qemu-system-x86_64 is missing"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

# ------------------------------------------------------------- 1. bauen
echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "the kernel does not build"; tail -12 "$TMPD/k.log" | sed 's/^/        /'
         echo; echo "SPALTEN: $pass bestanden, $fail gescheitert"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher calc sh pluguhr plugregel plugpaar wmplug"
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc uebersetzt $p.fi nicht"; head -6 "$TMPD/$p.err" | sed 's/^/        /'
        echo; echo "SPALTEN: $pass bestanden, $fail gescheitert"; exit 1; }
done
ok "$(echo $PROGS | wc -w) Programme gebaut"

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "the directory tree is ready" || bad "tools/k15/tree.py fehlgeschlagen"
ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do
    ARGS+=("/bin/$p=$TMPD/$p.elf")
done
printf 'titel=no-such-window-title kacheln\n' > "$TMPD/wmregeln.conf"
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme"
    "/etc/wmplug.conf=etc/wmplug.conf" "/etc/wmregeln.conf=$TMPD/wmregeln.conf")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the image is built" \
    || { bad "mkfs.py fehlgeschlagen"; head -5 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

# ------------------------------------------------------------ 2. laufen
BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug"

warte() { local f=$1 m=$2 pid=$3 i=0
    while [ $i -lt 900 ]; do
        grep -qa "$m" "$f" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done; return 1; }

lauf() { # name zusatz marke
    local name=$1 extra=$2 marke=$3
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock" "$TMPD/$name.ppm"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$BASE $extra" -serial "file:$out" -display none \
        -no-reboot -vga std -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    warte "$out" "$marke" "$pid"
    sleep "${SHOT_DELAY:-0.4}"
    python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name.ppm" 25 \
        > "$TMPD/$name.shot" 2>&1
    wait "$pid"; echo "$?" > "$TMPD/$name.rc"
    rm -f "$sock"
    tr -d '\000' < "$out" > "$TMPD/$name.clean"
    local rc; rc=$(cat "$TMPD/$name.rc")
    [ "$rc" = 21 ] && ok "$name: the kernel exits cleanly (21)" \
        || bad "$name: Exitcode $rc statt 21"
    [ -s "$TMPD/$name.ppm" ] && ok "$name: the photo exists ($(stat -c%s "$TMPD/$name.ppm") Oktette)" \
        || bad "$name: no photo"
}

echo "== 2. two plugins at the same time, then 'wmplug list' und 'wmplug info' =="
lauf paar "wigapp=/bin/plugpaar" 'Nr Name'
P="$TMPD/paar.clean"
has "$P" "wmplug: reg uhr" "das Widget ist angemeldet"
has "$P" "wmplug: reg regel" "die Regel-Engine ist angemeldet"
z=$(grep -aoE 'Plugins [0-9]+ von [0-9]+' "$P" | tail -1 | grep -oE '[0-9]+' | head -1)
[ "${z:-0}" -ge 2 ] && ok "the table counts $z plugins (two data rows under the header)" \
    || bad "the table counts '$z' Plugins -- fuer die Spaltenprobe braucht es zwei"
lang=$(grep -aoE 'wmplug: abi=[0-9]+  Plugins [0-9]+ von [0-9]+' "$P" | tail -1)
[ -n "$lang" ] && [ "${#lang}" -le 40 ] \
    && ok "erste Statuszeile '$lang' ist ${#lang} Zeichen lang (<= 40)" \
    || bad "first status line does not fit in 40 characters ('$lang')"
zwei=$(grep -aoE '  Timeout [0-9]+ Ticks  Area [0-9]+' "$P" | tail -1)
[ -n "$zwei" ] && [ "${#zwei}" -le 40 ] \
    && ok "zweite Statuszeile '$zwei' ist ${#zwei} Zeichen lang (<= 40)" \
    || bad "the status line is not wrapped ('$zwei')"

echo "== 3. the labels of 'info' =="
grep -qaE '  Leistentext +[0-9]+' "$P" \
    && ok "bei 'info' there is a separator between bar text and number" \
    || bad "'Leistentext' und die Zahl kleben wieder zusammen"
spalten=$(grep -aoE '^  (Name|Slot|Rechte|Maske|liegt|rejected|eingelegt|abgeholt|Reason|Leistentext) +[^ ]' "$P" \
    | sed 's/.$//' | awk '{ print length($0) }' | sort -u | tr '\n' ' ')
if [ "$(echo $spalten | wc -w)" = 1 ]; then
    ok "all labels of 'info' are ${spalten% } characters wide -- one column"
else
    bad "the labels of 'info' have different widths: $spalten"
fi

echo "== 4. the column position, recomputed from the photo =="
#
WIN=$(grep -aE '^wm: win .* t=\[Terminal' "$P" | tail -1)
WX=$(printf '%s' "$WIN" | grep -oE ' x=[0-9]+' | head -1 | grep -oE '[0-9]+')
WY=$(printf '%s' "$WIN" | grep -oE ' y=[0-9]+' | head -1 | grep -oE '[0-9]+')
RAND=$(grep -aoE '^const BORDER0: u64 = [0-9]+' kernel/ui/wm/wmgeom.fi | grep -oE '[0-9]+$')
TITEL=$(grep -aoE '^const TITLE_H0: u64 = [0-9]+' kernel/ui/wm/wmgeom.fi | grep -oE '[0-9]+$')
if [ -n "$WX" ] && [ -n "$WY" ] && [ -n "$RAND" ] && [ -n "$TITEL" ]; then
    GX=$((WX + RAND)); GY=$((WY + TITEL))
    ok "the terminal is at $WX,$WY according to the window server -- grid from $GX,$GY"
else
    GX=26; GY=62
    bad "no window position of the terminal in the capture (x='$WX' y='$WY' Rand='$RAND' Titel='$TITEL')"
fi
GRID=(assets/osum-mono.ttf 16 "$GX" "$GY" 10 19)
VG=(232 234 237); HG=(18 24 32)
tgrid() { # ppm zeile spalte text
    python3 tools/gfx/checkshot.py tgrid "$1" "${GRID[@]}" "$2" "$3" \
        "${VG[@]}" "${HG[@]}" "$4" 2>&1
}
kopf=""
for z in $(seq 0 23); do
    if tgrid "$TMPD/paar.ppm" "$z" 2 "Nr Name" > "$TMPD/t.txt" 2>&1; then
        kopf=$z; break
    fi
done
if [ -n "$kopf" ]; then
    ok "the table header is pixel-exact in grid row $kopf ($(cat "$TMPD/t.txt"))"
    if [ "$GX,$GY" != "26,62" ]; then
        alt=0
        for z in $(seq 0 23); do
            python3 tools/gfx/checkshot.py tgrid "$TMPD/paar.ppm" \
                assets/osum-mono.ttf 16 26 62 10 19 "$z" 2 "${VG[@]}" "${HG[@]}" \
                "Nr Name" >/dev/null 2>&1 && alt=$((alt + 1))
        done
        [ "$alt" = 0 ] && ok "CONTROL: at the old origin 26,62 the header is in no row" \
            || bad "GEGENPROBE: am alten Ursprung 26,62 'steht' der Kopf $alt mal"
    fi
else
    bad "no table header can be found in the photo"
fi

paar_probe() { # zeileKopf zeileWert kopfSpalte kopfText wertSpalte wertText name
    local zk=$1 zw=$2 sk=$3 tk=$4 sw=$5 tw=$6 nm=$7
    local a b
    if a=$(tgrid "$TMPD/paar.ppm" "$zk" "$sk" "$tk") \
        && b=$(tgrid "$TMPD/paar.ppm" "$zw" "$sw" "$tw"); then
        ok "$nm: Kopf '$tk' ab Spalte $sk, Wert '$tw' ab Spalte $sw -- dieselbe Endspalte"
    else
        bad "$nm: header or value is not where the widths say ($a / $b)"
    fi
}
if [ -n "$kopf" ]; then
    d1=$((kopf + 1))
    zeile0=$(grep -aoE '^ +0 [a-z]+ +0x[0-9A-F]+ 0x[0-9A-F]+' "$P" | tail -1)
    n0=$(echo "$zeile0" | awk '{print $2}')
    r0=$(echo "$zeile0" | awk '{print $3}')
    m0=$(echo "$zeile0" | awk '{print $4}')
    if [ -n "${n0:-}" ] && [ -n "${r0:-}" ] && [ -n "${m0:-}" ]; then
        ok "Platz 0 traegt '$n0' mit Rechten $r0 und Maske $m0 (aus der Leitung desselben Laufs)"
        paar_probe "$kopf" "$d1" 13 "Rechte" 14 "$r0" "Rechte"
        paar_probe "$kopf" "$d1" 20 "Maske" 20 "$m0" "Maske"
        paar_probe "$kopf" "$d1" 5 "Name" 5 "$n0" "Name"
        paar_probe "$kopf" "$d1" 26 "liegt" 30 "0" "liegt"
        paar_probe "$kopf" "$d1" 32 "rejected" 39 "0" "rejected"
        zeile1=$(grep -aoE '^ +1 [a-z]+ +0x[0-9A-F]+ 0x[0-9A-F]+' "$P" | tail -1)
        n1=$(echo "$zeile1" | awk '{print $2}')
        r1=$(echo "$zeile1" | awk '{print $3}')
        if [ -n "${n1:-}" ] && [ -n "${r1:-}" ]; then
            paar_probe "$kopf" "$((kopf + 2))" 5 "Name" 5 "$n1" "Name (Platz 1)"
            paar_probe "$kopf" "$((kopf + 2))" 13 "Rechte" 14 "$r1" "Rechte (Platz 1)"
        else
            bad "there is no second data row on the line"
        fi
    else
        bad "there is no data row with name, rights and mask on the line"
    fi
fi

# ------------------------------------------------------- 5. die Bilder
echo "== 5. die Bilder ablegen =="
wandel() { # ppm ziel
    [ -s "$1" ] || { bad "$1 is missing -- no image"; return 1; }
    if python3 tools/gfx/ppm2png.py "$1" "$2" > /dev/null 2>&1 \
        || python3 -c "from PIL import Image; Image.open('$1').save('$2')" 2>/dev/null; then
        ok "$2 liegt ab ($(stat -c%s "$2") Oktette)"
    else
        cp -f "$1" "${2%.png}.ppm"; ok "${2%.png}.ppm is stored (no PNG converter there)"
    fi
}
wandel "$TMPD/paar.ppm" "$SHOTS/spalten-zwei-plugins.png"
[ -d "$GAUNTLET" ] && wandel "$TMPD/paar.ppm" "$GAUNTLET/09-wmplug-verwaltung.png"

echo
echo "SPALTEN: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
