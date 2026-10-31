#!/usr/bin/env bash
#
#   bash tools/loader/abbild.sh [arbeitsverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-/tmp/laden}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
BLOCKS=${LADEN_BLOCKS:-262144}          # 512-Oktett-Bloecke -> 128 MiB
BOESE=${BOESE:-/root/ota-avx-nach/boese}
QUELLE=${LADEN_QUELLE:-https://store.fleitec.com/osum/aktuell}
PUB=${LADEN_PUB:-$OUT/schluessel.pub}
if [ -z "${LADEN_PUB:-}" ] && [ ! -s "$PUB" ] \
   && [ -s "${STORE_DIR:-/srv/store}/osum/aktuell/schluessel.pub" ]; then
    PUB="${STORE_DIR:-/srv/store}/osum/aktuell/schluessel.pub"
fi

[ -d "$OUT/bin" ] || { echo "== $OUT/bin fehlt -- erst tools/loader/build.sh"; exit 1; }
[ -s "$PUB" ] || { echo "== $PUB fehlt (der oeffentliche Schluessel der Auslieferung)"; exit 1; }

mkdir -p "$OUT/platte"
P="$OUT/platte"

# ------------------------------------------------------------ Dateien
python3 tools/k15/tree.py "$P/baum" > "$P/baum.log" 2>&1 || exit 1

cat > "$P/passwd" <<'EOF'
root:x:0:0:root:/:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=modern\nlight_start=07:00\ndark_start=19:00\n' > "$P/theme.conf"
printf '# taskbar.conf -- tools/loader/abbild.sh\nedge=bottom\nheight=28\nwidth=104\nautohide=0\nontop=1\nalign=left\n' > "$P/taskbar.conf"
printf '# /etc/time.conf\noffset=120\n' > "$P/time.conf"
printf 'lang=de\n' > "$P/locale.conf"
#
printf 'nameserver 10.0.2.3\n' > "$P/resolv.conf"
cat > "$P/ota.conf" <<EOF
# /etc/ota.conf -- woher dieses Geraet seine Programme holt.
quelle=$QUELLE
abstand=3600
auto=nein
frist=30
EOF

if [ ! -s "$OUT/roots.pem" ]; then
    python3 tools/hwnet/mkroots.py "$OUT/roots.pem" > "$OUT/roots.log" 2>&1 || {
        echo "== mkroots.py"; tail -5 "$OUT/roots.log"; exit 1; }
fi

# ------------------------------------------------------------ mkfs-Spec
ARGS=(build "$P/disk.img" "$BLOCKS" --v3 --inodes=2048 --karten=256 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf"
      "/lib/sans.ttf=assets/osum-sans.ttf"
      "/lib/icons.ttf=assets/osum-icons.ttf"
      /bin/)
for p in $(ls "$OUT/bin"); do ARGS+=("/bin/$p=$OUT/bin/$p"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/
       "/etc/passwd=$P/passwd@0644"
       "/etc/theme.conf=$P/theme.conf@0644"
       "/etc/taskbar.conf=$P/taskbar.conf@0644"
       "/etc/time.conf=$P/time.conf@0644"
       "/etc/locale.conf=$P/locale.conf@0644"
       "/etc/ota.conf=$P/ota.conf@0644"
       "/etc/resolv.conf=$P/resolv.conf@0644"
       /etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
if ls assets/shapes/*.shape >/dev/null 2>&1; then
    ARGS+=(/etc/shapes/)
    for s in assets/shapes/*.shape; do
        ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
    done
fi
if python3 tools/netview/icons.py bauen "$P/nvicons" > "$P/nvicons.log" 2>&1; then
    ARGS+=(/etc/netview/)
    for q in state-nocarrier state-noip state-noroute state-online \
             mark-filtered mark-faked mark-none sys-faking \
             tile-fake tile-net tile-hide; do
        [ -e "$P/nvicons/$q" ] && ARGS+=("/etc/netview/$q=$P/nvicons/$q")
    done
fi
ARGS+=(/etc/ssl/ "/etc/ssl/roots.pem=$OUT/roots.pem")
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
[ -e locale/en/icons ] && ARGS+=("/usr/share/locale/en/icons=locale/en/icons")
[ -e locale/de/icons ] && ARGS+=("/usr/share/locale/de/icons=locale/de/icons")
ARGS+=(/system/ "/system/schluessel.pub=$PUB")
ARGS+=(/store/ /users/ /tmp/ /mnt/ /dev/ /proc/)
#
if [ -n "${LADEN_STAND:-}" ] && [ -d "${LADEN_STAND}" ]; then
    for f in "$LADEN_STAND"/*.opk "$LADEN_STAND"/*.opk.sig; do
        [ -e "$f" ] || continue
        ARGS+=("/store/$(basename "$f")=$f")
    done
fi
#
while read -r z; do ARGS+=("$z"); done \
    < <(python3 tools/k15/bundle.py assets/apps "$P/buendel" \
        "nur=$(ls "$OUT/bin" | tr '\n' ' ')")
if [ -d "$BOESE" ]; then
    ARGS+=(/boese/)
    for f in "$BOESE"/*; do
        b=$(basename "$f")
        [ "${#b}" -lt 24 ] || { echo "   uebersprungen (Name zu lang): $b"; continue; }
        ARGS+=("/boese/$b=$f")
    done
fi
while read -r z; do ARGS+=("$z"); done < "$P/baum/liste"

python3 tools/osum/mkfs.py "${ARGS[@]}" > "$P/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$P/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$P/disk.img") Oktette, $(ls "$OUT/bin" | wc -l) Programme"
exit 0
