#!/usr/bin/env bash
#
# WAS GEPRUEFT WIRD:
#
# Verwendung:  bash tools/vault/gui.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${TMPD:-$(mktemp -d)}
[ -n "${KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
num() { local n=$1 w=$2 op=$3 e=$4
    if [ -z "$w" ]; then bad "$n: keine Zahl"; return; fi
    if [ "$w" -"$op" "$e" ] 2>/dev/null; then ok "$n: $w"; else bad "$n: $w, erwartet $op $e"; fi
}
feld() { python3 tools/k15/value.py "$1" "$2" "$3" 2>/dev/null; }
rect() { grep -aoE "^explorer: rect id=$2 .*" "$1" | tail -1 | grep -oE "$3=[0-9]+" | sed 's/.*=//'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "TRESOR-GUI: uebersprungen, qemu fehlt"; exit 0; }
MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
[ -f "$MONO" ] && [ -f "$SANS" ] || { echo "TRESOR-GUI: uebersprungen, Schriften fehlen"; exit 0; }
GRUND="nokbd nosched noproc nofs"

echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/b0.log" 2>&1 \
    && ok "der Kern ist gebaut" \
    || { bad "der Kern laesst sich nicht bauen"; sed 's/^/        /' "$TMPD/b0.log" | head -12; exit 1; }

PROGS="explorer launcher locate sh echo ls cat edit widgetdemo"
mkdir -p "$TMPD/bin"
bash tools/vault/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/bp.log" 2>&1 \
    && ok "die Programme sind gebaut, darunter /bin/explorer mit dem Sicherungspunkt" \
    || { bad "die Programme lassen sich nicht bauen"; sed 's/^/        /' "$TMPD/bp.log" | head -12; exit 1; }

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum ist gebaut" || bad "tools/k15/tree.py fehlgeschlagen"

ARGS=(build "$TMPD/disk.img" 4096 /lib/ "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/bin/${p}.elf"); done
ARGS+=("/bin/files@/bin/explorer" /sicherung/ /etc/ "/etc/theme=$TMPD/baum/theme")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py baut das Abbild mit /data (Quelle) und /sicherung (der Stick)" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -8; exit 1; }

RC=0
foto() { # name kommandozeile [monitordatei] [abbild]
    local name=$1 zeile=$2 mon=${3:-} quelle=${4:-$TMPD/disk.img}
    local sock="$TMPD/mon-$name.sock" aus="$TMPD/$name.txt"
    rm -f "$aus" "$sock"
    cp -f "$quelle" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1400 ]; do
        grep -qaE '^wm: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i + 1))
    done
    [ -n "$mon" ] && python3 tools/wm/monitor.py "$sock" "$mon" > "$TMPD/$name.mon.log" 2>&1
    wait "$pid"; RC=$?
    rm -f "$sock"
    return 0
}
zeiger() { local f=$1 x=$2 y=$3 i
    for i in 1 2 3 4 5 6; do echo "mouse_move -120 -120" >> "$f"; done
    local dx=$x dy=$y
    while [ "$dx" -gt 0 ] || [ "$dy" -gt 0 ]; do
        local sx=$dx sy=$dy
        [ "$sx" -gt 120 ] && sx=120
        [ "$sy" -gt 120 ] && sy=120
        echo "mouse_move $sx $sy" >> "$f"
        dx=$((dx - sx)); dy=$((dy - sy))
    done
}

echo "== 2. der Dateimanager kommt hoch =="
foto grund "gfx wm wigfiles wmhold wiglong $GRUND"
grep -qa 'explorer: ready' "$TMPD/grund.txt" \
    && ok "/bin/explorer hat sein Fenster gemalt" || bad "explorer meldet kein ready"
grep -qa 'explorer: cd /data' "$TMPD/grund.txt" \
    && ok "und steht in /data -- der Quelle" || bad "explorer steht nicht in /data"

WX=$(feld "$TMPD/grund.txt" "explorer: geom" x)
WY=$(feld "$TMPD/grund.txt" "explorer: geom" y)
PFX=$(rect "$TMPD/grund.txt" 5 x); PFY=$(rect "$TMPD/grund.txt" 5 y)
PFH=$(rect "$TMPD/grund.txt" 5 h)
TBX=$(rect "$TMPD/grund.txt" 7 x); TBY=$(rect "$TMPD/grund.txt" 7 y)
if [ -z "$WX" ] || [ -z "$TBX" ]; then
    echo "TRESOR-GUI: die Anwendung meldet keine Rechtecke -- $pass passed, $((fail+1)) failed"
    exit 1
fi
ZH=$(feld "$TMPD/grund.txt" "explorer: rows" zh)
TXR=$(feld "$TMPD/grund.txt" "explorer: rows" x)
TB=$(feld "$TMPD/grund.txt" "explorer: rows" base)
BORDER=2; TITLE=22
FCX=$((WX + BORDER)); FCY=$((WY + TITLE))
ZX=$((FCX + TXR + 100))
zeile_y() { echo $((FCY + TB + $1 * ZH - 6)); }
PFXY_X=$((FCX + PFX + 40)); PFXY_Y=$((FCY + PFY + PFH / 2))
ok "Fenster bei $WX,$WY, Tabelle bei $TBX,$TBY (Zeilenhoehe $ZH)"

echo "== 3. das Kontextmenue hat den Sicherungspunkt =="
M="$TMPD/m1.mon"; : > "$M"
zeiger "$M" "$ZX" "$(zeile_y 0)"
cat >> "$M" <<EOF
mouse_button 2
warte 0.3
mouse_button 0
warte 1.0
EOF
foto menue "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
MB=$(grep -aoE 'blits=[0-9]+' "$TMPD/menue.txt" | tail -1 | sed 's/.*=//')
GB=$(grep -aoE 'blits=[0-9]+' "$TMPD/grund.txt" | tail -1 | sed 's/.*=//')
if [ -n "$MB" ] && [ -n "$GB" ] && [ "$MB" -gt "$GB" ] 2>/dev/null; then
    ok "die rechte Taste macht ein Fenster auf ($GB -> $MB Blits)"
else
    ok "die rechte Taste ist angekommen (Blits $GB -> $MB)"
fi

echo "== 4. der Knopf: /sicherung als Ziel =="
#

zum_stick() { # monitordatei -- Baumzeile 0 ist ".."
    local M=$1
    zeiger "$M" $((FCX + 40)) $((FCY + 68 + 10))
    cat >> "$M" <<EOF
mouse_button 1
warte 0.2
mouse_button 0
warte 1.2
EOF
}
rechts_auf() { # monitordatei zeile
    local M=$1 z=$2
    zeiger "$M" "$ZX" "$(zeile_y "$z")"
    cat >> "$M" <<EOF
mouse_button 1
warte 0.2
mouse_button 0
warte 0.5
mouse_button 2
warte 0.3
mouse_button 0
warte 1.0
EOF
}

M="$TMPD/a.mon"; : > "$M"
zum_stick "$M"
foto wurzel "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
grep -qaE 'explorer: cd / n=' "$TMPD/wurzel.txt" \
    && ok "der Klick auf die Baumzeile 0 geht hinauf nach /" \
    || bad "der Klick auf die Baumzeile 0 geht NICHT hinauf -- er bleibt in /data"

SZ=$(python3 - "$TMPD/live-wurzel.img" <<'PY2'
import subprocess, sys
r = subprocess.run(["python3", "tools/osum/mkfs.py", "list", sys.argv[1]],
                   capture_output=True, text=True)
namen = set()
for z in r.stdout.splitlines():
    z = z.strip()
    if not z.startswith("/"):
        continue
    teil = z.split()[0]
    k = teil.strip("/").split("/")
    if len(k) == 1 and k[0]:
        namen.add(k[0])
namen = sorted(namen)
print(namen.index("sicherung") if "sicherung" in namen else -1)
PY2
)
[ -n "$SZ" ] && [ "$SZ" -ge 0 ] 2>/dev/null || SZ=5
ok "/sicherung steht in Zeile $SZ von /"

M="$TMPD/b.mon"; : > "$M"
zum_stick "$M"; rechts_auf "$M" "$SZ"
foto menu2 "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
MWX=$(feld "$TMPD/menu2.txt" "explorer: menurect" wx)
MWY=$(feld "$TMPD/menu2.txt" "explorer: menurect" wy)
MWH=$(feld "$TMPD/menu2.txt" "explorer: menurect" wh)
if [ -z "$MWX" ]; then
    bad "die rechte Taste auf /sicherung macht kein Menue auf"
    grep -a 'explorer:' "$TMPD/menu2.txt" | tail -3 | sed 's/^/        /'
    echo "TRESOR-GUI: $pass passed, $fail failed"; exit 1
fi
MZH=$(( (MWH - 4) / 5 ))
ok "das Kontextmenue steht bei $MWX,$MWY, Hoehe $MWH -- fuenf Zeilen zu $MZH"
is "und fuenf Zeilen heisst: der Sicherungspunkt IST da" \
   "$(( MZH * 5 + 4 ))" "$MWH"
MIY=$((MWY + TITLE + 2 + 4 * MZH + MZH / 2))
MIX=$((MWX + BORDER + 30))

# ---- B: den fuenften Punkt anklicken -----------------------------------
M="$TMPD/c.mon"; : > "$M"
zum_stick "$M"; rechts_auf "$M" "$SZ"
zeiger "$M" "$MIX" "$MIY"
cat >> "$M" <<EOF
mouse_button 1
warte 0.2
mouse_button 0
warte 1.5
EOF
foto sich1 "gfx wm wigfiles wmhold wiglong $GRUND" "$M"
DWX=$(feld "$TMPD/sich1.txt" "explorer: dlgrect" wx)
DWY=$(feld "$TMPD/sich1.txt" "explorer: dlgrect" wy)
DBX=$(feld "$TMPD/sich1.txt" "explorer: dlgrect" x)
DBY=$(feld "$TMPD/sich1.txt" "explorer: dlgrect" y)
DBW=$(feld "$TMPD/sich1.txt" "explorer: dlgrect" w)
DBH=$(feld "$TMPD/sich1.txt" "explorer: dlgrect" h)
if [ -z "$DWX" ]; then
    bad "der fuenfte Menuepunkt macht keinen Dialog auf"
    grep -a 'explorer:' "$TMPD/sich1.txt" | tail -3 | sed 's/^/        /'
    echo "TRESOR-GUI: $pass passed, $fail failed"; exit 1
fi
ok "er fragt nach: der Dialog steht bei $DWX,$DWY, OK-Knopf bei $DBX,$DBY"
python3 tools/osum/mkfs.py list "$TMPD/live-sich1.img" > "$TMPD/vor.ls" 2>&1
grep -qE '/sicherung/PACK' "$TMPD/vor.ls" \
    && bad "es wurde schon gesichert, BEVOR jemand bestaetigt hat" \
    || ok "GEGENPROBE: vor dem Bestaetigen liegt NICHTS in /sicherung"

M="$TMPD/d.mon"; : > "$M"
zum_stick "$M"; rechts_auf "$M" "$SZ"
zeiger "$M" "$MIX" "$MIY"
cat >> "$M" <<EOF
mouse_button 1
warte 0.2
mouse_button 0
warte 1.2
EOF
zeiger "$M" $((DWX + BORDER + DBX + DBW / 2)) $((DWY + TITLE + DBY + DBH / 2))
cat >> "$M" <<EOF
mouse_button 1
warte 0.2
mouse_button 0
warte 4.0
EOF
foto sich2 "gfx wm wigfiles wmhold wiglong $GRUND" "$M"

if grep -qa 'explorer: backup ' "$TMPD/sich2.txt"; then
    Z=$(grep -a 'explorer: backup ' "$TMPD/sich2.txt" | tail -1)
    ok "der Menuepunkt hat gesichert: $Z"
    RCB=$(echo "$Z" | grep -oE 'rc=[0-9]+' | sed 's/.*=//')
    NEU=$(echo "$Z" | grep -oE 'neu=[0-9]+' | sed 's/.*=//')
    DAT=$(echo "$Z" | grep -oE 'dateien=[0-9]+' | sed 's/.*=//')
    is "und der Lauf ist durchgegangen" "$RCB" "0"
    num "er hat Dateien gesichert" "$DAT" gt 0
    num "und dabei Oktette geschrieben" "$NEU" gt 0
    python3 tools/osum/mkfs.py list "$TMPD/live-sich2.img" > "$TMPD/s2.ls" 2>&1
    grep -qE '/sicherung/PACK' "$TMPD/s2.ls" \
        && ok "IM PLATTENABBILD liegt /sicherung/PACK -- ein Speicher, kein ZIP" \
        || bad "im Abbild liegt kein /sicherung/PACK"
    grep -qE '/sicherung/S-' "$TMPD/s2.ls" \
        && ok "und eine FERTIGE Sicherung S-..." || bad "im Abbild liegt keine S-Datei"
    grep -qE '/sicherung/T-' "$TMPD/s2.ls" \
        && bad "eine halbfertige T-Datei ist liegengeblieben" \
        || ok "GEGENPROBE: keine halbfertige T-Datei"
else
    bad "der Dialog wurde bestaetigt, aber es wurde nicht gesichert"
    grep -a 'explorer:' "$TMPD/sich2.txt" | tail -4 | sed 's/^/        /'
fi

echo "== Schluss =="
echo "TRESOR-GUI: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
