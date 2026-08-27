#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/speicher/build.sh -- Kernel, Programme und die ZWEI Plattenabbilder
# der Runde SPEICHER, zum Iterieren waehrend der Arbeit. Die Abnahme baut
# in tools/speicher/run.sh alles noch einmal und misst.
#
#   bash tools/speicher/build.sh [ausgabeverzeichnis]
#
# WARUM ZWEI ABBILDER. Sie beantworten zwei verschiedene Fragen, und ein
# einziges Abbild koennte nur eine davon beantworten:
#
#   gross.img   VIERTAUSEND LEERE DATEIEN (tools/k15/bigfs.py). Hier geht
#               es um ZEIT: wie lange braucht der Index fuer eine Antwort,
#               wie lange der vollstaendige Durchlauf. Leer duerfen sie
#               sein, weil der Durchlauf trotzdem jede Inode anfassen
#               muss -- und nur so passen viertausend auf zwei Megaoktett.
#   inhalt.img  DIESELBE ANORDNUNG, ABER MIT INHALT (tools/speicher/tree.py),
#               schief verteilt. Hier geht es um RICHTIGKEIT: die Summen
#               sind nicht null, also faellt ein Fehler in der
#               Aufsummierung auf. Auf diesem Abbild laeuft die
#               Gegenprobe und stehen die Bildschirmfotos.
#
# DIE GRENZE, die beide Abbilder bindet: die Blockkarte von OFS ist EIN
# Block, also 4096 Bloecke, also zwei Megaoktett. Davon gehen 1026 fuer
# Superblock, Karte und die Inode-Tabelle mit 4096 Eintraegen ab, der
# Rest teilt sich zwischen Programmen, Schriften und Inhalt. Deshalb
# bekommt nicht jede Datei Inhalt. (Die Runde OFS3 hebt genau diese
# Grenze auf -- mehrblockige Blockkarte; danach darf hier mehr stehen.)
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/speicher}
BUDGET=${BUDGET:-420000}
mkdir -p "$OUT"

# `speicher` ist die Anwendung der Runde, `du` das Gegenstueck auf der
# Kommandozeile -- die beiden MUESSEN dieselbe Zahl liefern, und dass sie
# aus derselben Quelle (kernel/user/nidx.fi) kommen, ist der Grund.
PROGS="speicher du sh echo ls cat locate"

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -30 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    if ! "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -30 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"
        head -12 "$OUT/$p.lderr"
        rc=1
        continue
    fi
    strip --strip-all "$OUT/$p.elf"
    printf '   %-10s %7d Oktette\n' "$p" "$(stat -c%s "$OUT/$p.elf")"
done
[ "$rc" = 0 ] || exit 1

# --------------------------------------------------------- gross.img (Zeit)
python3 tools/k15/bigfs.py "$OUT/gross" 4000 > "$OUT/gross.log" 2>&1 || exit 1
ARGS=(build "$OUT/gross.img" 4096 /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
while read -r zeile; do ARGS+=("$zeile"); done < "$OUT/gross/angaben"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs-gross.log" 2>&1 || {
    echo "== mkfs.py (gross) fehlgeschlagen"; tail -5 "$OUT/mkfs-gross.log"
    exit 1; }
echo "   gross.img $(stat -c%s "$OUT/gross.img") Oktette  ($(tail -1 "$OUT/gross.log"))"

# ------------------------------------------------- inhalt.img (Richtigkeit)
#
# Die Schriften und das Farbschema kommen mit: der Fensterserver liest
# beide VON DER PLATTE, und ohne sie gibt es kein Bildschirmfoto.
python3 tools/speicher/tree.py "$OUT/baum" 4000 "$BUDGET" \
    > "$OUT/baum.log" 2>&1 || { cat "$OUT/baum.log"; exit 1; }
cp -f tools/k15/theme "$OUT/baum/theme" 2>/dev/null || \
    python3 - "$OUT/baum/theme" <<'EOF'
import sys
open(sys.argv[1], "wb").write(open(
    "tools/k15/tree.py").read().split('THEME = b"""')[1]
    .split('"""')[0].encode())
EOF
ARGS=(build "$OUT/inhalt.img" 4096 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf"
      "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
ARGS+=(/etc/ "/etc/theme=$OUT/baum/theme")
while read -r zeile; do ARGS+=("$zeile"); done < "$OUT/baum/angaben"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs-inhalt.log" 2>&1 || {
    echo "== mkfs.py (inhalt) fehlgeschlagen"; tail -5 "$OUT/mkfs-inhalt.log"
    echo "   -> BUDGET kleiner setzen (jetzt $BUDGET)"; exit 1; }
echo "   inhalt.img $(stat -c%s "$OUT/inhalt.img") Oktette  ($(tail -1 "$OUT/baum.log"))"
python3 tools/osum/mkfs.py stat "$OUT/inhalt.img" | sed 's/^/   /'
exit 0
