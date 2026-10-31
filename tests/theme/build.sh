#!/usr/bin/env bash
#
#   bash tests/theme/build.sh [ausgabeverzeichnis] [uebersetzer]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
OUT=${1:-/tmp/theme}
CC=${2:-vendor/firn/bin/firnc}
mkdir -p "$OUT"

PROGS="themetest explorer launcher taskbar desktop settings sh echo ls cat"

bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/k.log" 2>&1 || {
    echo "== der Kern laesst sich nicht bauen"; tail -20 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -25 "$OUT/$p.err"
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
    printf '   %-14s %7d Oktette\n' "$p" "$(stat -c%s "$OUT/$p.elf")"
done
[ "$rc" = 0 ] || exit 1

printf '%s\n' "$PROGS" > "$OUT/progs.txt"

python3 tools/k15/tree.py "$OUT/baum" > /dev/null || exit 1

cat > "$OUT/theme.conf" <<'EOF'
# /etc/theme.conf -- welches Schema, welcher Modus, welche Akzentfarbe.
#
# Das Schema liegt unter /etc/schemas/ und liefert die ROHEN Rampen.
# Der Modus entscheidet, welche der Bindungen der semantischen Ebene
# darauf gelegt wird: light, dark, oder auto nach der Tageszeit.
# Ist accent leer, gilt die Akzentfarbe des Schemas.
scheme=day
mode=auto
accent=
light_start=07:00
dark_start=19:00
EOF
cat > "$OUT/time.conf" <<'EOF'
# Minuten, um die die ANZEIGE gegen UTC verschoben wird. Die
# Hardware-Uhr laeuft auf UTC und dieser Kernel kann sie nicht stellen.
offset=120
EOF

# 8192 blocks (4 MiB) held these programs with 4 per cent to spare
# after round LOOK. That is not spare room, that is a countdown.
#
ARGS=(build "$OUT/disk.img" 32768 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644")
ARGS+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
rm -rf "$OUT/apps"
cp -a assets/apps "$OUT/apps"
rm -rf "$OUT/apps/editor.osp" "$OUT/apps/widgets.osp"
#
while read -r zeile; do ARGS+=("$zeile"); done \
    < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" "nur=$PROGS")
while read -r pfad; do ARGS+=("$pfad"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$OUT/disk.img") Oktette"
exit 0
