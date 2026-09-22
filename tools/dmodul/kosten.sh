#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dmodul/kosten.sh -- RUNDE MODULE: WAS DIE KAESTCHEN KOSTEN.
#
#   bash tools/dmodul/kosten.sh <ausgabe> [accel=kvm|tcg]
#
# ============================================================ DIE FRAGE
#
# Module werden in JEDEM Bild gemalt. Die Frage ist nicht "sieht es gut
# aus", sondern "was geht davon ab". Der Rahmen aus vorhandenen
# Messungen dieses Projekts:
#
#   eine Blur-Blase 360x120      3,1 ms = 18 % des 60-Hz-Budgets
#   ein Taskleistenstreifen      0,01 ms
#
# Ein Modul ist naeher am zweiten als am ersten -- und genau das muss
# nachgerechnet und nicht behauptet werden.
#
# ============================================================ DIE ZAHL
#
# Gemessen wird `wm: composites=` und `pixels=` ueber einen Lauf von
# 20 Sekunden mit `wmhold`. `composites` ist die Zahl der
# Zusammensetzungen, `pixels` die Summe der dabei angefassten
# Bildpunkte -- beide zaehlt der Fensterserver SELBST, keiner wird aus
# einem Bild geraten.
#
# DREI LAEUFE, und der erste ist die Gegenprobe:
#
#   0-aus      alle Module AUS (module.conf mit an=0). Das ist der
#              Zustand VOR dieser Runde -- ohne ihn ist jede Zahl
#              danach eine Zahl ohne Vergleich.
#   1-an       alle drei AN, Vorgabelage.
#   2-bearb    alle drei AN, Bearbeitungsmodus (jedes Modul traegt
#              zusaetzlich einen Akzentrahmen).
#
# WAS DIE ZAHL NICHT SAGT: sie misst den Schreibtisch im RUHEZUSTAND.
# Ein Modul malt sich nur neu, wenn sich seine Zahl geaendert hat
# (`werte_holen` gibt sonst false) -- die Uhr also einmal je Minute,
# Speicher und Last einmal je Sekunde. Der Dauerzustand ist damit
# genau das, was hier steht, und nicht ein Bild je 16 ms.
set -uo pipefail
WURZEL=$(cd "$(dirname "$0")/../.." && pwd)
cd "$WURZEL" || exit 1

OUT=${1:?usage: kosten.sh <ausgabe> [accel=kvm|tcg]}
accel=kvm
for a in "${@:2}"; do
    case "$a" in
        accel=*) accel=${a#*=} ;;
    esac
done
mkdir -p "$OUT"
BUILDD=${LOOKBUILD:-/tmp/osum-dmodul-build}
mkdir -p "$BUILDD"
export FIRNLIB="$WURZEL/lib"

PROGS="desktop taskbar settings launcher explorer sh echo ls cat"

# ---------------------------------------------------------- bauen
newer=$(find "$WURZEL/kernel" "$WURZEL/tools/build-kernel.sh" -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ]; then
    "$WURZEL/tools/build-kernel.sh" "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { tail -20 "$BUILDD/k.log"; echo "der Kern baut nicht"; exit 1; }
fi
USERNEW=$(ls -t "$WURZEL"/kernel/user/*.fi 2>/dev/null | head -1)
for p in $PROGS; do
    if [ -s "$BUILDD/$p.elf" ] \
       && [ "$BUILDD/$p.elf" -nt "$WURZEL/kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    "$WURZEL/vendor/firn/bin/firnc" -c "$WURZEL/kernel/user/$p.fi" \
        -o "$BUILDD/$p.o" > "$BUILDD/e-$p" 2>&1 \
        || { head -20 "$BUILDD/e-$p"; echo "$p uebersetzt nicht"; exit 1; }
    CRT="$BUILDD/crt.o"
    if grep -qa '^profile app' "$WURZEL/kernel/user/$p.fi"; then
        CRT=""
    else
        [ -s "$BUILDD/crt.o" ] || as --64 -o "$BUILDD/crt.o" "$WURZEL/kernel/user/crt.s" 2>/dev/null || CRT=""
    fi
    ld -T "$WURZEL/kernel/user/user.ld" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" $CRT "$BUILDD/$p.o" > "$BUILDD/l-$p" 2>&1 \
        || { head -20 "$BUILDD/l-$p"; echo "$p bindet nicht"; exit 1; }
done

# ---------------------------------------------------------- ein Lauf
messen() {
    local name=$1 conf=$2
    local ARGS=(build "$OUT/d-$name.img" 32768 /lib/)
    ARGS+=("/lib/sans.ttf=$WURZEL/assets/osum-sans.ttf"
           "/lib/mono.ttf=$WURZEL/assets/osum-mono.ttf"
           "/lib/icons.ttf=$WURZEL/assets/osum-icons.ttf")
    ARGS+=(/bin/)
    for p in $PROGS; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
    printf '# taskbar.conf\nedge=bottom\nheight=28\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
        > "$OUT/taskbar.conf"
    printf 'scheme=day\nmode=light\nshape=osum\n' > "$OUT/theme.conf"
    printf 'lang=de\n' > "$OUT/locale.conf"
    printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
    printf 'root:x:0:0:root:/:/bin/sh\n' > "$OUT/passwd"
    printf 'on\n' > "$OUT/uitrace"
    echo "$conf" > "$OUT/module.conf"
    ARGS+=(/etc/
           "/etc/taskbar.conf=$OUT/taskbar.conf@0644"
           "/etc/theme.conf=$OUT/theme.conf@0644"
           "/etc/locale.conf=$OUT/locale.conf@0644"
           "/etc/time.conf=$OUT/time.conf@0644"
           "/etc/passwd=$OUT/passwd@0644"
           "/etc/uitrace=$OUT/uitrace@0644"
           "/etc/module.conf=$OUT/module.conf@0644")
    ARGS+=(/etc/schemas/)
    for s in "$WURZEL"/assets/schemes/*.scheme; do
        ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
    done
    if ls "$WURZEL"/assets/shapes/*.shape >/dev/null 2>&1; then
        ARGS+=(/etc/shapes/)
        for s in "$WURZEL"/assets/shapes/*.shape; do
            ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
        done
    fi
    ARGS+=(/users/ /users/root/ /users/root/config/)
    python3 "$WURZEL"/tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs-$name.log" 2>&1 \
        || { tail -10 "$OUT/mkfs-$name.log"; echo "mkfs $name"; exit 1; }

    local SOCK="$OUT/mon-$name.sock"
    rm -f "$SOCK" "$OUT/s-$name.txt"
    local ACC=()
    if [ "$accel" = kvm ] && [ -e /dev/kvm ]; then ACC=(-accel kvm); fi
    timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
        -append "gfx wm wig wigicons desk wmhold wiglong nokbd nosched noproc nofs" \
        -serial "file:$OUT/s-$name.txt" -display none -no-reboot -vga std \
        -monitor "unix:$SOCK,server,nowait" \
        -drive "file=$OUT/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$OUT/q-$name.log" 2>&1 &
    local PID=$!
    local i=0
    while [ $i -lt 3200 ]; do
        grep -qaE '^wm: hold' "$OUT/s-$name.txt" 2>/dev/null && break
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    # Im Bearbeitungsmodus: den rechten Knopf auf das erste Modul.
    if [ "$name" = 2-bearb ]; then
        local gx gy
        gx=$(awk '/name=uhr /{for(i=1;i<=NF;i++){n=index($i,"=");
            if(substr($i,1,n-1)=="x")x=substr($i,n+1);
            if(substr($i,1,n-1)=="w")w=substr($i,n+1)}print int(x+w/2);exit}' "$OUT/s-$name.txt")
        gy=$(awk '/name=uhr /{for(i=1;i<=NF;i++){n=index($i,"=");
            if(substr($i,1,n-1)=="y")y=substr($i,n+1);
            if(substr($i,1,n-1)=="h")h=substr($i,n+1)}print int(y+h/2);exit}' "$OUT/s-$name.txt")
        if [ -n "$gx" ] && [ -n "$gy" ]; then
            python3 "$WURZEL"/tools/themestore/click.py "$gx,$gy" \
                | sed 's/^mouse_button 1$/mouse_button 2/' > "$OUT/mon-$name.txt"
            python3 "$WURZEL"/tools/wm/monitor.py "$SOCK" "$OUT/mon-$name.txt" \
                > "$OUT/click-$name.log" 2>&1
        fi
    fi
    # Den Lauf zu Ende gehen lassen (`wmhold` haelt 20 s) und dann die
    # letzte Zeile nehmen.
    wait "$PID" 2>/dev/null
    rm -f "$OUT/d-$name.img"
}

zahl() {
    grep -ao "$2=[0-9]*" "$OUT/s-$1.txt" 2>/dev/null | tail -1 | cut -d= -f2
}

echo "== die drei Laeufe =="
messen 0-aus     'uhr=0,1,16,16
speicher=0,1,16,60
cpu=0,1,16,104
taste=280'
echo "  0-aus    fertig"
messen 1-an      'uhr=1,1,16,16
speicher=1,1,16,60
cpu=1,1,16,104
taste=280'
echo "  1-an     fertig"
messen 2-bearb   'uhr=1,1,16,16
speicher=1,1,16,60
cpu=1,1,16,104
taste=280'
echo "  2-bearb  fertig"

echo
printf '%-10s %10s %14s %10s %10s\n' Lauf composites pixels blits ticks
for n in 0-aus 1-an 2-bearb; do
    printf '%-10s %10s %14s %10s %10s\n' "$n" \
        "$(zahl "$n" composites)" "$(zahl "$n" pixels)" \
        "$(zahl "$n" blits)" "$(zahl "$n" ticks)"
done

echo
echo "== was die Module kosten =="
p0=$(zahl 0-aus pixels); p1=$(zahl 1-an pixels); p2=$(zahl 2-bearb pixels)
c0=$(zahl 0-aus composites); c1=$(zahl 1-an composites)
if [ -n "$p0" ] && [ -n "$p1" ] && [ "$p0" -gt 0 ]; then
    python3 - "$p0" "$p1" "${p2:-0}" "${c0:-0}" "${c1:-0}" <<'PY'
import sys
p0, p1, p2, c0, c1 = (int(v) for v in sys.argv[1:6])
print("  Bildpunkte aus     %12d" % p0)
print("  Bildpunkte an      %12d   (%+.2f %%)" % (p1, (p1 - p0) * 100.0 / p0))
if p2:
    print("  Bildpunkte bearb   %12d   (%+.2f %%)" % (p2, (p2 - p0) * 100.0 / p0))
print("  Zusammensetzungen  aus=%d an=%d" % (c0, c1))
# Ein Bildpunkt kostet im Zusammensetzer rund 4 Oktette Schreiben.
# Der Vergleich, der etwas sagt: drei Kaestchen zu 184x36 sind
# 19 872 Bildpunkte je Neuzeichnung.
print("  ein Modulsatz      %12d Bildpunkte je Neuzeichnung (3 x 184 x 36)"
      % (3 * 184 * 36))
PY
fi
