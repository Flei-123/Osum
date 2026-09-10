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
# RUNDE MERGE-2: 32768 STATT 10240 BLOECKE (16 MiB statt 5 MiB).
#
# Dieselbe Ursache wie in tools/k13/run.sh, nur an der anderen Stelle:
# die Quelle traegt den Kern UND das Userland. Gemessen an diesem
# Stand sind das 3 112 516 Oktette Kern und 1 687 208 Oktette fuer die
# 34 Programme -- zusammen mit Limine, den zwei signierten Quellen und
# dem Journal (522 Bloecke) passt das nicht mehr in fuenf Megaoktette,
# und mkfs.py endete mit "mkfs: the disk is full". Die Zahl ist eine
# Arbeitsgroesse fuer ein Abbild im Temporaerbereich, kein Versprechen:
# sie darf grosszuegig sein. Das Zielgeraet bleibt bei ZIEL_MIB.
BLOCKS=${QUELL_BLOCKS:-32768}
KARTEN=${KARTEN:-128}
INODES=${INODES:-512}

mkdir -p "$OUT/bin"

PROGS=${PROGS:-"sh ls cat echo cp mv rm mkdir rmdir touch head tail wc grep sort uniq true false sleep ps kill uname date df mount umount install opk ota dhcp host reboot sync tar find du chmod id whoami wlan"}

# RUNDE OTA: DIE PROGRAMME DER ZWEITEN BAUART.
#
# Alles unter `kernel/user/` ist `profile kernel`: freistehend, ohne
# Halde, mit `crt.s` davor. Ein Programm, das TLS spricht, kann so nicht
# gebaut werden -- die Datensatzschicht allein braucht eine Halde. Dafuer
# gibt es `kernel/app/` (Runde HWNET): `--profile=app`, die VOLLE
# Firn-Bibliothek aus `vendor/firn/lib`, gebunden mit demselben
# `user.ld` und OHNE `crt.s`, weil Firns eigenes `_start` schon das tut,
# was Osums Lader erwartet.
#
# BIS ZU DIESER RUNDE LAG `/bin/fetch` IN KEINEM ABBILD. `docs/UPDATE.md`
# hat das als ersten Punkt der Fehlliste benannt: "es fehlt die
# Verdrahtung, nicht die Kryptographie". Von hier an ist es drin, und
# damit kann das Geraet selbst holen, was es einspielt.
# RUNDE SCHLEUSE: `wasm` ist die zweite App. Sie braucht `--profile=app`
# aus demselben Grund wie `fetch` -- der Deuter legt den linearen
# Speicher des Gastes auf der Halde an, und eine Halde hat `profile
# kernel` nicht.
APPS=${APPS:-"fetch wasm prim"}

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

# ---------------------------------------------------------- die Apps
gebaut_app=""
for p in $APPS; do
    [ -f "kernel/app/$p.fi" ] || continue
    # RUNDE SCHLEUSE: `--no-pass=inline` fuer die Apps, und das ist
    # GEMESSEN und nicht geraten. Der WASM-Deuter besteht aus einer sehr
    # langen if/else-Kette ueber die Befehlsnummer; das Einsetzen der
    # Aufrufe blaeht genau diese Kette auf und verdraengt sie aus dem
    # Befehlszwischenspeicher. `prim.wasm` (Primzahlen unter 200000),
    # derselbe Deuter, nur andere Uebersetzung:
    #
    #     dev            30,06 s
    #     dev-fast        4,98 s   <- Standard
    #     release-safe    9,14 s
    #     release-fast    8,21 s
    #     release-fast --no-pass=inline   4,80 s   <- das hier
    #
    # Eine hoehere Optimierungsstufe war also LANGSAMER, bis das
    # Einsetzen abgeschaltet wurde.
    # RUNDE WASM-MERGE: die Messung oben gilt fuer den WASM-Deuter, NICHT
    # fuer jede App. `jarvisd`, `konto` und `fetch` sind seit SCHLEUSE
    # dazugekommen und sind KEINE lange Verteilerkette -- fuer sie ist das
    # Einsetzen nuetzlich. Darum steht der Schalter jetzt an der Datei,
    # fuer die er gemessen wurde, statt pauschal an allen Apps.
    APPFLAGS=""
    case "$p" in
        wasm) APPFLAGS="--no-pass=inline" ;;
    esac
    if ! FIRNLIB="$ROOT/lib" "$CC" -c --profile=app $APPFLAGS \
            -o "$OUT/app-$p.o" "kernel/app/$p.fi" > "$OUT/app-$p.err" 2>&1; then
        echo "== $p (app): der Uebersetzer sagt nein"
        head -20 "$OUT/app-$p.err"
        exit 1
    fi
    # KEIN crt.o: Firns eigenes `_start` ist der Eintrittspunkt.
    if ! ld -T kernel/user/user.ld -o "$OUT/bin/$p" "$OUT/app-$p.o" \
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

# ---------------------------------------------------- RUNDE BETRIEB
#
# DER ERSATZSCHLUESSEL UND DIE SCHLUESSELGENERATION.
#
# `/system/ersatz.pub` ist der zweite vertraute Schluessel. Er ist NICHT
# derselbe wie der Hauptschluessel und seine geheime Haelfte liegt
# ausdruecklich NICHT dort, wo gebaut wird -- sie steckt im
# Schluesselbund (`tools/ota/schluesselbund.py`), verschluesselt und mit
# einer eigenen Passphrase. Wer ihn hier hineinlegt, tut das mit
# $OTA_ERSATZ; ohne die Variable liegt keiner im Abbild, und dann
# verhaelt sich das Geraet genau wie vor dieser Runde.
#
# `/system/SCHLUESSELGEN` ist die Generation, bei der dieses Geraet
# ausgeliefert wurde -- neun Oktett fester Breite, wie `/system/FASSUNG`.
if [ -n "${OTA_ERSATZ:-}" ] && [ -s "${OTA_ERSATZ}" ]; then
    SPEC+=("/system/ersatz.pub=$OTA_ERSATZ")
    echo "   ersatz    $(stat -c%s "$OTA_ERSATZ") Oktette"
fi
printf '%08d\n' "${OTA_KGEN:-0}" > "$OUT/SCHLUESSELGEN"
SPEC+=("/system/SCHLUESSELGEN=$OUT/SCHLUESSELGEN")

# ---------------------------------------------------------- RUNDE OTA
#
# DER WURZELSPEICHER. `/bin/fetch` prueft die Kette gegen
# `/etc/ssl/roots.pem`; ohne die Datei wird NICHTS vertraut, und das ist
# das richtige Verhalten, aber kein brauchbares Abbild. $OTA_ROOTS zeigt
# auf die Datei, die hineinsoll; ohne die Variable wird die Auswahl aus
# `tools/hwnet/mkroots.py` genommen (die Mozilla-Wurzeln des Wirts). Geht
# auch das nicht, bleibt die Datei WEG -- und dann sagt `fetch` beim
# ersten Versuch "no trust store", was besser ist als eine leere Datei,
# die wie ein Speicher aussieht.
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

# DIE EINSTELLUNGEN. Die Vorgabe schaltet die automatische Suche AUS und
# nennt keine Quelle: ein Abbild, das ab Werk irgendwo nachfragt, waere
# eine Entscheidung, die niemand getroffen hat.
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
# auto     ja/nein. Vorgabe: nein.
# frist    Sekunden, die der Wachhund auf den Erfolgsvermerk wartet.
#quelle=https://192.0.2.1:443
#name=pkg.example.org
abstand=3600
auto=nein
frist=120
EOFC
fi
SPEC+=("/etc/ota.conf=$OUT/ota.conf")
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
