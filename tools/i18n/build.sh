#!/usr/bin/env bash
# tools/i18n/build.sh -- Kern, Programme und ein Plattenabbild fuer Runde
# I18N, zum Iterieren waehrend der Arbeit. Die Abnahme in
# tools/i18n/run.sh baut damit und misst darauf.
#
#   bash tools/i18n/build.sh [ausgabeverzeichnis] [--stufe 0|1]
#
# WAS DIESES ABBILD MEHR TRAEGT ALS DAS VON RUNDE K15 -- und beides ist
# der Grund dieser Runde:
#
#   /usr/share/locale/en/messages   die Quellsprache
#   /usr/share/locale/de/messages   die deutsche Uebersetzung
#   /users/<name>/config/           wo die WAHL DES BENUTZERS liegt
#
# DIE PFADE SIND ENGLISCH UND BLEIBEN ES, in jeder Sprache. Das ist die
# Regel dieser Runde (docs/I18N.md, Abschnitt 1) und der Unterschied zu
# einem System, das "Program Files" im Dateimanager "Programme" nennt
# und danach nichts mehr findet.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"

OUT=/tmp/i18n
STUFE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stufe) STUFE=$2; shift 2 ;;
        *) OUT=$1; shift ;;
    esac
done
mkdir -p "$OUT"

if [[ $STUFE == 0 ]]; then CC=${FIRNC:-vendor/firn/bin/firnc}
else CC=${FIRNC1:-vendor/firn/bin/firnc1}; fi

# Die Oberflaeche dieser Runde plus das, was ein Abbild sonst braucht.
PROGS="schreibtisch leiste einstellungen starter explorer i18nt \
       sh echo ls cat"

bash tools/build-kernel.sh "$OUT/k.mb" --stufe "$STUFE" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -20 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    if ! "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"; head -25 "$OUT/$p.err"
        rc=1; continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F$STUFE.u_start" \
            -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"; head -12 "$OUT/$p.lderr"
        rc=1; continue
    fi
    strip --strip-all "$OUT/$p.elf"
    printf '   %-14s %7d Oktette\n' "$p" "$(stat -c%s "$OUT/$p.elf")"
done
[ "$rc" = 0 ] || exit 1

# Ein Farbschema, damit die Oberflaeche nicht in den eingebauten Farben
# steht -- die Bildschirmfotos werden gegen die Schriftrasterung
# gerechnet, und dafuer muss der Hintergrund bekannt sein.
cat > "$OUT/theme" <<'EOF'
bg=1E2228
fg=E6E6E6
panel=2A2F37
btn=39404A
line=4A515C
EOF
# Die Benutzertafel. `root` mit Kennung 0 -- msg.fi sucht darin den
# Namen zu seiner eigenen Kennung, um /users/<name>/config/locale zu
# finden.
cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
# Die WAHL DES BENUTZERS. Auf diesem Abbild steht sie auf Englisch;
# tools/i18n/run.sh legt daneben ein zweites Abbild mit "de" an und
# haelt die beiden Bildschirmfotos gegeneinander.
printf 'en\n' > "$OUT/locale-en"
printf 'de\n' > "$OUT/locale-de"

ARGS=(build "$OUT/disk.img" 4096 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
ARGS+=(/etc/ "/etc/theme=$OUT/theme" "/etc/passwd=$OUT/passwd")
# DIE SPRACHDATEIEN. /usr/share/locale/<code>/messages -- englische
# Pfade, ISO-639-Codes als Verzeichnisnamen.
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
# DIE VERZEICHNISSE DES BENUTZERS.
ARGS+=(/users/ /users/root/ /users/root/config/
       "/users/root/config/locale=$OUT/locale-${LANG_SET:-en}")
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$OUT/disk.img") Oktette (Sprache: ${LANG_SET:-en})"
exit 0
