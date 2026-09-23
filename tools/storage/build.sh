#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/storage/build.sh -- Kernel, Programme und die ZWEI Plattenabbilder
# der Runde SPEICHER, zum Iterieren waehrend der Arbeit. Die Abnahme baut
# in tools/storage/run.sh alles noch einmal und misst.
#
#   bash tools/storage/build.sh [ausgabeverzeichnis]
#
# WARUM ZWEI ABBILDER. Sie beantworten zwei verschiedene Fragen, und ein
# einziges Abbild koennte nur eine davon beantworten:
#
#   gross.img   VIERTAUSEND LEERE DATEIEN (tools/k15/bigfs.py). Hier geht
#               es um ZEIT: wie lange braucht der Index fuer eine Antwort,
#               wie lange der vollstaendige Durchlauf. Leer duerfen sie
#               sein, weil der Durchlauf trotzdem jede Inode anfassen
#               muss -- und nur so passen viertausend auf zwei Megaoktett.
#   inhalt.img  DIESELBE ANORDNUNG, ABER MIT INHALT (tools/storage/tree.py),
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
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
BUDGET=${BUDGET:-420000}
mkdir -p "$OUT"

# `speicher` ist die Anwendung der Runde, `du` das Gegenstueck auf der
# Kommandozeile -- die beiden MUESSEN dieselbe Zahl liefern, und dass sie
# aus derselben Quelle (kernel/user/nidx.fi) kommen, ist der Grund.
# Seit ENGLISCH ETAPPE 9 heisst die QUELLE storage.fi; das Programm heisst
# weiter /bin/speicher (run.sh sucht "k15: start /bin/speicher").
PROGS="storage du sh echo ls cat locate"
binname() { if [[ $1 == storage ]]; then echo speicher; else echo "$1"; fi; }

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -30 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -30 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/$p.elf" $UCRT "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
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
# Auf gross.img laeuft nur `du -m /data` (run.sh: lauf zeit). /bin/speicher
# ist seit profile app 1,26 MB und passt neben 4000 Inodes nicht mehr in
# die zwei Megaoktett einer OFS-Blockkarte ("mkfs: the disk is full").
for p in $PROGS; do
    [[ $p == storage ]] && continue
    ARGS+=("/bin/$(binname $p)=$OUT/$p.elf")
done
while read -r zeile; do ARGS+=("$zeile"); done < "$OUT/gross/angaben"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs-gross.log" 2>&1 || {
    echo "== mkfs.py (gross) fehlgeschlagen"; tail -5 "$OUT/mkfs-gross.log"
    exit 1; }
echo "   gross.img $(stat -c%s "$OUT/gross.img") Oktette  ($(tail -1 "$OUT/gross.log"))"

# ------------------------------------------------- inhalt.img (Richtigkeit)
#
# Die Schriften und das Farbschema kommen mit: der Fensterserver liest
# beide VON DER PLATTE, und ohne sie gibt es kein Bildschirmfoto.
python3 tools/storage/tree.py "$OUT/baum" 4000 "$BUDGET" \
    > "$OUT/baum.log" 2>&1 || { cat "$OUT/baum.log"; exit 1; }
cp -f tools/k15/theme "$OUT/baum/theme" 2>/dev/null || \
    python3 - "$OUT/baum/theme" <<'EOF'
import sys
open(sys.argv[1], "wb").write(open(
    "tools/k15/tree.py").read().split('THEME = b"""')[1]
    .split('"""')[0].encode())
EOF
# A-029: DAS INHALTSABBILD HAT 8192 BLOECKE (4 MiB), NICHT 4096. Seit
# `profile app` ist /bin/speicher 1,26 MB gross; zusammen mit den zwei
# Schriften, den uebrigen Programmen und dem Messbaum (BUDGET) passte
# es nicht mehr auf 2 MiB, und mkfs.py brach mit "the disk is full" ab
# -- der ganze Laeufer mass danach nichts. Die Blockkarte darf seit
# Runde INSTALL mehrblockig sein (mkfs.py, `bmblocks`), 8192 benutzen
# k16, metal und hotplug schon. gross.img bleibt bei 4096: es braucht
# nur `du`, und /bin/speicher steht dort gar nicht.
INHALT_BLOCKS=${INHALT_BLOCKS:-8192}
ARGS=(build "$OUT/inhalt.img" "$INHALT_BLOCKS" /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf"
      "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$(binname $p)=$OUT/$p.elf"); done
ARGS+=(/etc/ "/etc/theme=$OUT/baum/theme")
while read -r zeile; do ARGS+=("$zeile"); done < "$OUT/baum/angaben"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs-inhalt.log" 2>&1 || {
    echo "== mkfs.py (inhalt) fehlgeschlagen"; tail -5 "$OUT/mkfs-inhalt.log"
    echo "   -> BUDGET kleiner setzen (jetzt $BUDGET)"; exit 1; }
echo "   inhalt.img $(stat -c%s "$OUT/inhalt.img") Oktette  ($(tail -1 "$OUT/baum.log"))"
# mkfs.py kennt kein `stat` (stand hier und meldete nur "unknown
# command"); die Zahl der Namen im Abbild sagt dasselbe.
echo "   inhalt.img: $(python3 tools/osum/mkfs.py list "$OUT/inhalt.img" | wc -l) Namen"
exit 0
