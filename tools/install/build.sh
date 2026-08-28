#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/build.sh -- Kern, Programme und die beiden Platten dieser
# Runde, zum Iterieren waehrend der Arbeit.
#
# WAS HIER ENTSTEHT, und warum genau das:
#
#   k.mb         der Kern.
#   bin/*        die unprivilegierten Programme.
#   quelle.img   ein OFS-Dateisystem, das dem BOOT-MODUL des Produkts
#                entspricht -- die Programme, dazu unter /boot der Kern
#                selbst, der EFI-Bootlader und seine Konfiguration.
#                Das ist der Punkt: ein System, das sich selbst
#                installieren koennen soll, muss den Bootlader BEI SICH
#                haben. Ein ISO kann Osum nicht lesen.
#                Gebaut mit `--karten=128`: die Blockkarte deckt damit
#                524288 Bloecke = 256 MiB ab, obwohl das Abbild selbst
#                nur wenige Megaoktett gross ist. Genau dieser Vorrat
#                laesst `/bin/install` das Dateisystem auf der Platte
#                WACHSEN, ohne die Inodetabelle zu verschieben.
#   ziel.img     eine leere Platte.
#
# Verwendung:  bash tools/install/build.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/install}
LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
ZIEL_MIB=${ZIEL_MIB:-256}
BLOCKS=${QUELL_BLOCKS:-10240}
KARTEN=${KARTEN:-128}
INODES=${INODES:-512}

mkdir -p "$OUT/bin"

PROGS=${PROGS:-"sh ls cat echo cp mv rm mkdir rmdir touch head tail wc grep sort uniq true false sleep ps kill uname date df mount umount install opk sync tar find du chmod id whoami"}

bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || {
    echo "== firnc laesst sich nicht bauen"; tail -20 "$OUT/firnc.log"; exit 1; }

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -30 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
gebaut=""
for p in $PROGS; do
    [ -f "kernel/user/$p.fi" ] || continue
    if ! "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -20 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/bin/$p" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"
        head -12 "$OUT/$p.lderr"
        rc=1
        continue
    fi
    strip --strip-all "$OUT/bin/$p"
    gebaut="$gebaut $p"
done
[ "$rc" = 0 ] || exit 1
echo "   programme $(echo "$gebaut" | wc -w) Stueck"

# ---------------------------------------------------------- limine.conf
#
# DAS IST DIE KOMMANDOZEILE, MIT DER DAS SYSTEM VON DER PLATTE STARTET.
# KEIN `modfs` darin: es gibt kein Boot-Modul mehr, die Wurzel liegt auf
# der Partition. Genau das ist der Nachweis dieser Runde -- derselbe Kern,
# eine andere Herkunft der Wurzel.
cat > "$OUT/limine.conf" <<'EOF'
timeout: 0
verbose: yes

/OrientOS
    protocol: multiboot1
    path: boot():/osum.mb
    cmdline: osum vfs nokbd nosched noproc nofs noring3
EOF

# ---------------------------------------------------------- quelle.img
# THE FILESYSTEM VERSION. Version 2 holds 8 + 64 + 4096 blocks in one
# file -- 2,134,016 octets -- and the kernel outgrew that: with twenty
# rounds in it, it is 2.8 megaoctets, so the image the installer writes
# cannot even carry the kernel it boots. Version 3 (round OFS3) has the
# triple indirect pointer and holds 136,351,744 octets in one file.
# FSVER=2 keeps the old behaviour for whoever wants to measure it.
FSVER=${FSVER:-3}
V3=()
[ "$FSVER" = 3 ] && V3=(--v3)
SPEC=(build "$OUT/quelle.img" "$BLOCKS" "${V3[@]}" "--inodes=$INODES" "--karten=$KARTEN" /bin/)
for p in $gebaut; do SPEC+=("/bin/$p=$OUT/bin/$p"); done
SPEC+=(/boot/ "/boot/osum.mb=$OUT/k.mb" "/boot/BOOTX64.EFI=$LIMINE/BOOTX64.EFI" "/boot/limine.conf=$OUT/limine.conf" /efi/ /etc/ /dev/ /proc/ /mnt/ /store/ /apps/ /system/ /users/ /tmp/)
# ---------------------------------------------------------- die Quellen
#
# ZWEI SIGNIERTE PAKETQUELLEN LIEGEN AUF DER PLATTE. Das ist die Lage,
# um die es bei „aktualisieren" geht: das Geraet holt sich eine neue
# Fassung von einem Ort, den es lesen kann, und prueft sie gegen den
# INDEX. Ein Netzzugang waere dafuer eine zweite Baustelle -- was hier
# gemessen wird, ist die Paketverwaltung und nicht das Netz.
bash tools/install/pakete.sh "$OUT" || exit 1
SPEC+=(/quelle1/ /quelle2/)
# RUNDE UPDATE: der vertraute Schluessel gehoert auf das Geraet, sonst
# installiert `/bin/opk` nichts mehr.
SPEC+=("/system/schluessel.pub=$OUT/schluessel.pub")
for q in 1 2; do
    for f in "$OUT/quelle$q"/*; do
        SPEC+=("/quelle$q/$(basename "$f")=$f")
    done
done
# Was ein Testschritt zusaetzlich hineinlegen will -- etwa die beiden
# beschaedigten Pakete der Gegenproben. Das laeuft NICHT ueber die
# Quelle: die beschreibt, was ausgeliefert wird, nicht den Aufbau eines
# Nachweises.
for e in ${EXTRA:-}; do SPEC+=("$e"); done
python3 tools/osum/mkfs.py "${SPEC[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
CRC=$(python3 -c 'import zlib,sys;print("%08x"%zlib.crc32(open(sys.argv[1],"rb").read()))' "$OUT/quelle.img")
echo "$CRC" > "$OUT/quelle.crc"
echo "   quelle    $(stat -c%s "$OUT/quelle.img") Oktette, CRC32 0x$CRC"

# ---------------------------------------------------------- ziel.img
rm -f "$OUT/ziel.img"
truncate -s "${ZIEL_MIB}M" "$OUT/ziel.img"
echo "   ziel      ${ZIEL_MIB} MiB leer"
exit 0
