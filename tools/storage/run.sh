#!/usr/bin/env bash
#
# Verwendung:  bash tools/storage/run.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${1:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${1:-}" "$TMPD"
mkdir -p "$TMPD"
SHOTS=${SHOTS:-$ROOT/docs/bilder/speicher}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name wert op erwartet
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
feld() { grep -aoE "(^|[^a-z])$3=[0-9]+" <(grep -aF "$2" "$1" | tail -1) \
         | tail -1 | sed 's/.*=//'; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "STORAGE: skipped, qemu-system-x86_64 is not there"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }

echo "== bauen"
bash tools/storage/build.sh "$TMPD" || exit 1

# --------------------------------------------------------------- Laeufe
#
lauf() { # name kommandozeile [abbild] [frist]
    local name=$1 zeile=$2 img=${3:-inhalt.img} frist=${4:-3000}
    cp -f "$TMPD/$img" "$TMPD/live-$name.img"
    timeout "$frist" $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$zeile;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo "RC=$?" > "$TMPD/$name.rc"
}

foto() { # name kommandozeile [marke]
    local name=$1 zeile=$2 marke=${3:-'^speicher: ready'}
    local sock="$TMPD/mon-$name.sock"
    local aus="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$TMPD/inhalt.img" "$TMPD/live-$name.img"
    timeout 900 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 4000 ]; do
        grep -qaE "$marke" "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    rm -f "$sock"
    return 0
}

echo "== 1. time: the index against the complete walk"
echo "   (on gross.img, four thousand files -- this takes minutes)"
lauf zeit 'du -m /data' gross.img
IUS=$(feld "$TMPD/zeit.txt" "du: index [/data]" us10)
WUS=$(feld "$TMPD/zeit.txt" "du: durchlauf [/data]" us)
NDAT=$(feld "$TMPD/zeit.txt" "du: durchlauf [/data]" dateien)
BUS=$(feld "$TMPD/zeit.txt" "du: bauen" us)
has "$TMPD/zeit.txt" "du: vergleich" "die Messung ist durchgelaufen"
num "Dateien im Durchlauf" "$NDAT" ge 4000
if [ -n "${IUS:-}" ] && [ -n "${WUS:-}" ] && [ "$IUS" -gt 0 ]; then
    FAKTOR=$(( WUS * 10 / IUS ))
    ok "Index $((IUS / 10)) us je Abfrage, Durchlauf $WUS us -- Faktor $FAKTOR"
    num "der Index ist wenigstens tausendmal schneller" "$FAKTOR" ge 1000
    ok "einmaliger Aufbau des Index: $BUS us"
    if [ -n "${BUS:-}" ] && [ "$BUS" -gt 0 ]; then
        num "schon der AUFBAU schlaegt den Durchlauf" \
            $(( WUS / BUS )) ge 2
    fi
else
    bad "Zeiten fehlen (Index '$IUS', Durchlauf '$WUS')"
fi

echo "== 2. correctness: the same question on an image WITH content"
lauf mess 'du -m /data'
MOKT=$(feld "$TMPD/mess.txt" "du: index [/data]" okt)
MWOKT=$(feld "$TMPD/mess.txt" "du: durchlauf [/data]" okt)
SOLL=$(awk '$1=="/data"{print $2}' "$TMPD/baum/soll")
num "die Summe ist nicht null" "${MOKT:-0}" gt 0
if [ "${MOKT:-x}" = "${MWOKT:-y}" ]; then ok "Index = Durchlauf: $MOKT Oktette"
else bad "Index $MOKT, Durchlauf $MWOKT"; fi
if [ "${MOKT:-x}" = "${SOLL:-y}" ]; then ok "and the host computes the same: $SOLL"
else bad "the host says $SOLL, the guest $MOKT"; fi
has "$TMPD/mess.txt" "oktok=1" "die Gegenprobe des Gastes selbst"

echo "== 3. EVERY directory, octet for octet, against three numbers"
lauf probe 'du -p'
if python3 tools/storage/check.py "$TMPD/baum/soll" "$TMPD/probe.txt" \
        > "$TMPD/pruefen.log" 2>&1; then
    ok "$(tail -1 "$TMPD/pruefen.log")"
else
    bad "die grosse Gegenprobe: $(tail -3 "$TMPD/pruefen.log" | tr '\n' ' ')"
fi
sed 's/^/     /' "$TMPD/pruefen.log"

echo "== 4. The journal must pick up GROWTH (not only new names)"
lauf schreib 'du -w'
has "$TMPD/schreib.txt" "du: write" "die Schreibprobe ist gelaufen"
num "kein Satz ist verlorengegangen" "$(feld "$TMPD/schreib.txt" 'du: write nachgezogen' lost)" eq 0
num "die Summe wurde nachgezogen, ohne neu zu bauen" \
    "$(feld "$TMPD/schreib.txt" 'du: write bauten' bauten)" eq 1
num "die nachgezogene Summe stimmt" \
    "$(feld "$TMPD/schreib.txt" 'du: write nachgezogen' ok)" eq 1
num "und nach dem Loeschen steht wieder der alte Stand da" \
    "$(feld "$TMPD/schreib.txt" 'du: write weg' ok)" eq 1

echo "== 5. control run: without catching up the number MUST become wrong"
lauf schreibW 'du -W'
WOK=$(feld "$TMPD/schreibW.txt" 'du: write nachgezogen' ok)
WNACH=$(feld "$TMPD/schreibW.txt" 'du: write nachgezogen' nachher)
WERW=$(feld "$TMPD/schreibW.txt" 'du: write nachgezogen' erwartet)
if [ "${WOK:-1}" = "0" ] && [ "${WNACH:-0}" != "${WERW:-0}" ]; then
    ok "without journal the sum is off ($WNACH instead of $WERW) -- so the journal really caught up before"
else
    bad "without journal everything was still right (ok=$WOK, $WNACH against $WERW): then the probe measures nothing"
fi

echo "== 6. Die Oberflaeche"
mkdir -p "$SHOTS"
GRUND="nokbd nosched noproc nofs"
foto ruhe "gfx wm wig wigspeicher wmhold wiglong wighalt=240 $GRUND" '^speicher: ready'
has "$TMPD/ruhe.txt" "k15: start /bin/speicher" "/bin/speicher kommt VON DER PLATTE"
has "$TMPD/ruhe.txt" "speicher: kachel" "es hat seine Kacheln gerechnet"
SOKT=$(feld "$TMPD/ruhe.txt" "speicher: cd /data" okt)
if [ "${SOKT:-x}" = "${SOLL:-y}" ]; then
    ok "the surface shows the same number as you and as the host: $SOKT"
else
    bad "die Oberflaeche sagt '$SOKT', du und der Wirt sagen '$SOLL'"
fi
ZSUM=$(grep -aoE '^speicher: zeile i=[0-9]+ okt=[0-9]+' "$TMPD/ruhe.txt" \
       | grep -oE 'okt=[0-9]+' | sed 's/okt=//' \
       | awk '{s+=$1} END{print s+0}')
if [ "${ZSUM:-0}" = "${SOKT:-x}" ]; then
    ok "the rows add up to the total: $ZSUM"
else
    bad "the rows give $ZSUM, the top says $SOKT"
fi
has "$TMPD/ruhe.txt" "speicher: probe" "die Oberflaeche rechnet sich selbst gegen"
num "und zwar richtig" "$(feld "$TMPD/ruhe.txt" 'speicher: probe' ok)" eq 1

if [ -s "$TMPD/ruhe.ppm" ]; then
    python3 tools/gfx/ppm2png.py "$TMPD/ruhe.ppm" "$SHOTS/speicher.png" \
        > "$TMPD/png.log" 2>&1 || cp -f "$TMPD/ruhe.ppm" "$SHOTS/speicher.ppm"
    ok "Bildschirmfoto: $SHOTS/speicher.png"
    if python3 tools/storage/kachelprobe.py "$TMPD/ruhe.ppm" \
            "$TMPD/ruhe.txt" > "$TMPD/kachel.log" 2>&1; then
        ok "$(tail -1 "$TMPD/kachel.log")"
    else
        bad "the treemap in the image: $(tail -2 "$TMPD/kachel.log" | tr '\n' ' ')"
    fi
    sed 's/^/     /' "$TMPD/kachel.log"
else
    bad "kein Bildschirmfoto entstanden"
fi

echo "== 7. control run: the same surface without index"
foto ohne "gfx wm wig wigspeicher wignoidx wmhold wiglong $GRUND" \
    '^speicher: (ready|cd)'
OOKT=$(feld "$TMPD/ohne.txt" "speicher: cd" okt)
if [ "${OOKT:-0}" = "0" ]; then
    ok "without index the surface shows zero -- it invents nothing"
else
    bad "without index it says '$OOKT': woher?"
fi
if grep -qa "speicher: kachel" "$TMPD/ohne.txt"; then
    bad "without index tiles are painted anyway -- from which shares?"
else
    ok "without index the tiles disappear"
fi
[ -s "$TMPD/ohne.ppm" ] && { python3 tools/gfx/ppm2png.py "$TMPD/ohne.ppm" \
    "$SHOTS/speicher-ohne-index.png" >/dev/null 2>&1 || \
    cp -f "$TMPD/ohne.ppm" "$SHOTS/speicher-ohne-index.ppm"; }

echo
echo "SPEICHER: $pass bestanden, $fail durchgefallen   (Arbeitsstand: $TMPD)"
[ "$fail" -eq 0 ] || exit 1
exit 0
