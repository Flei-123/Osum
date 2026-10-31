#!/usr/bin/env bash
#
# Verwendung:  bash tools/install/build.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/marke-env.sh
. tools/sync/gc.sh   # r278: FIRN_FUNCTION_SECTIONS + ld --gc-sections (OSUM_NO_GC=1 = off)
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${1:-/tmp/install}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
ZIEL_MIB=${ZIEL_MIB:-256}
# RUNDE MERGE-2: 32768 STATT 10240 BLOECKE (16 MiB statt 5 MiB).
#
BLOCKS=${QUELL_BLOCKS:-32768}
KARTEN=${KARTEN:-128}
INODES=${INODES:-512}

mkdir -p "$OUT/bin"

PROGS=${PROGS:-"sh ls cat echo cp mv rm mkdir rmdir touch head tail wc grep sort uniq true false sleep ps kill uname date df mount umount install opk ota dhcp host reboot sync tar find du chmod id whoami wlan sntp wrace wspam"}

APPS=${APPS:-"fetch wasm prim rootsctl nettest"}

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
    if ! "$CC" $OPTL "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -20 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld $GCS -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
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

# ---------------------------------------------------------- die Apps
gebaut_app=""
for p in $APPS; do
    [ -f "kernel/app/$p.fi" ] || continue
    #
    APPFLAGS=""
    case "$p" in
        wasm) APPFLAGS="--no-pass=inline" ;;
    esac
    if ! FIRNLIB="$ROOT/lib" "$CC" $OPTL -c --profile=app $APPFLAGS \
            -o "$OUT/app-$p.o" "kernel/app/$p.fi" > "$OUT/app-$p.err" 2>&1; then
        echo "== $p (app): der Uebersetzer sagt nein"
        head -20 "$OUT/app-$p.err"
        exit 1
    fi
    if ! ld $GCS -T kernel/user/user.ld -o "$OUT/bin/$p" "$OUT/app-$p.o" \
            2> "$OUT/app-$p.lderr"; then
        echo "== $p (app): der Binder sagt nein"
        head -12 "$OUT/app-$p.lderr"
        exit 1
    fi
    strip --strip-all "$OUT/bin/$p"
    gebaut="$gebaut $p"
    gebaut_app="$gebaut_app $p"
done
if [ -n "$gebaut_app" ]; then
    asz=0
    for a in $gebaut_app; do asz=$((asz + $(stat -c%s "$OUT/bin/$a"))); done
    echo "   apps      $(echo "$gebaut_app" | wc -w) Stueck ($asz Oktette)"
fi

# ---------------------------------------------------------- limine.conf
#
cat > "$OUT/limine.conf" <<EOF
timeout: 0
verbose: yes

/${MARKE_PRODUKT}
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
bash tools/install/pakete.sh "$OUT" || exit 1
SPEC+=(/quelle1/ /quelle2/)
SPEC+=("/system/schluessel.pub=$OUT/schluessel.pub")

# ---------------------------------------------------- RUNDE BETRIEB
#
if [ -n "${OTA_ERSATZ:-}" ] && [ -s "${OTA_ERSATZ}" ]; then
    SPEC+=("/system/ersatz.pub=$OTA_ERSATZ")
    echo "   ersatz    $(stat -c%s "$OTA_ERSATZ") Oktette"
fi
printf '%08d\n' "${OTA_KGEN:-0}" > "$OUT/SCHLUESSELGEN"
SPEC+=("/system/SCHLUESSELGEN=$OUT/SCHLUESSELGEN")

# ---------------------------------------------------------- RUNDE OTA
#
ROOTS=${OTA_ROOTS:-}
if [ -z "$ROOTS" ]; then
    if python3 tools/hwnet/mkroots.py "$OUT/roots.pem" > "$OUT/roots.log" 2>&1; then
        ROOTS="$OUT/roots.pem"
    fi
fi
SPEC+=(/etc/ssl/)
if [ -n "$ROOTS" ] && [ -s "$ROOTS" ]; then
    SPEC+=("/etc/ssl/roots.pem=$ROOTS")
    echo "   wurzeln   $(stat -c%s "$ROOTS") Oktette"
else
    echo "   wurzeln   KEINE -- fetch wird nichts vertrauen"
fi

if [ -n "${OTA_CONF:-}" ]; then
    [ "$OTA_CONF" -ef "$OUT/ota.conf" ] || cp -f "$OTA_CONF" "$OUT/ota.conf"
else
    cat > "$OUT/ota.conf" <<'EOFC'
# /etc/ota.conf -- woher dieses Geraet seine Updates holt.
#
# quelle   die Adresse der Quelle. IPv4 und nicht ein Name: dieses
#          System hat keinen Resolver (docs/ROADMAP-UPDATE.md A2).
# name     der Name, den das Zertifikat tragen MUSS. Ohne ihn wird die
#          Adresse als Name genommen, und die traegt kein Zertifikat --
#          die Verbindung wird dann abgelehnt, und das ist richtig so.
# abstand  Sekunden zwischen zwei automatischen Suchen.
# auto     ja/nein. Vorgabe: ja (Entscheidung des Besitzers 02.10.2026).
# frist    Sekunden, die der Wachhund auf den Erfolgsvermerk wartet.
#quelle=https://192.0.2.1:443
#name=pkg.example.org
abstand=3600
auto=true
frist=120
EOFC
fi
SPEC+=("/etc/ota.conf=$OUT/ota.conf")
for q in 1 2; do
    for f in "$OUT/quelle$q"/*; do
        SPEC+=("/quelle$q/$(basename "$f")=$f")
    done
done
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
