#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/loader/abbild.sh -- DIE PLATTE, MIT DER DIESE RUNDE GEMESSEN WIRD.
#
#   bash tools/loader/abbild.sh [arbeitsverzeichnis]
#
# Was daran anders ist als bei den beiden Abbildern davor:
#
#   tools/look/shot.sh   baut eine Platte mit OBERFLAECHE, aber ohne
#                        `opk`, ohne `ota`, ohne `fetch` und ohne Netz.
#   tools/install/build.sh baut eine Platte mit `opk`/`ota`/`fetch`,
#                        aber ohne eine einzige Zeile Oberflaeche.
#
# Ein Laden, der Programme mit Fenstern ausliefert, braucht BEIDES auf
# derselben Platte -- sonst kann man zwar installieren oder zusehen,
# aber nicht beides nacheinander. Diese Datei ist die Zusammenlegung,
# und sie erfindet dafuer nichts Neues: die Bausteine sind
# `tools/k15/bundle.py`, `tools/k15/tree.py`, `tools/hwnet/mkroots.py`
# und `tools/osum/mkfs.py`, alle unveraendert.
#
# WAS AUF DIE PLATTE KOMMT UND WARUM:
#
#   /bin/*                   die Programme aus tools/loader/build.sh
#   /apps/*.osp              die MITGELIEFERTEN Buendel (assets/apps).
#                            Sie sind der Vorher-Zustand: `opk` baut
#                            /apps bei der ersten Installation
#                            VOLLSTAENDIG neu (kernel/user/opk.fi,
#                            `apps_bauen`), und genau daran sieht man
#                            hinterher, was aus dem Laden kam.
#   /system/schluessel.pub   der Vertrauensanker. OHNE IHN INSTALLIERT
#                            `opk` NICHTS -- das ist die Zusage der
#                            Runde UPDATE und sie bleibt.
#   /etc/ota.conf            die Quelle, als NAME und nicht als Adresse
#   /etc/ssl/roots.pem       die Wurzeln, damit `fetch` eine echte Kette
#                            pruefen kann
#   /boese/*.opk             die beschaedigten Pakete aus
#                            /root/ota-avx-nach/boese -- das Pruefmaterial
#                            fuer die Gegenprobe. Sie liegen auf der
#                            Platte und NICHT im Laden: was der Laden
#                            ausliefert, ist heil.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-/tmp/laden}
BLOCKS=${LADEN_BLOCKS:-262144}          # 512-Oktett-Bloecke -> 128 MiB
BOESE=${BOESE:-/root/ota-avx-nach/boese}
QUELLE=${LADEN_QUELLE:-https://store.fleitec.com/osum/aktuell}
PUB=${LADEN_PUB:-$OUT/schluessel.pub}

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
# DER NAMENSDIENST STEHT SCHON AUF DER PLATTE.
#
# `dhcp` schreibt dieselbe Datei, und der Textlauf dieser Runde misst
# genau das. Fuer die BILDER wird sie mitgeliefert: dort wird der Befehl
# ueber die Tastatur in ein Fenster getippt, und jeder Buchstabe, den
# ein Foto nicht braucht, ist eine Fehlerquelle mehr. 10.0.2.3 ist der
# Aufloeser von QEMUs Benutzernetz -- dieselbe Zahl, die der
# DHCP-Server dort in Option 6 nennt.
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
# RUNDE CERTUS-AUF-OSUM: DIE PAKETE MIT AUF DIE PLATTE.
#
# `/store/` war bis hierher ein leeres Verzeichnis -- der Ort, an den
# `ota` holt, was es aus dem Netz bekommt. Mit $LADEN_STAND legt dieser
# Bau die fertigen Pakete samt ihren Signaturen GLEICH dort hinein.
# Damit laesst sich der Weg des Pakets (Signatur pruefen, auspacken,
# Buendel unter /apps) OHNE einen Server im Netz messen -- der Weg MIT
# Server bleibt tools/loader/run.sh, und beide messen dasselbe `opk`.
if [ -n "${LADEN_STAND:-}" ] && [ -d "${LADEN_STAND}" ]; then
    for f in "$LADEN_STAND"/*.opk "$LADEN_STAND"/*.opk.sig; do
        [ -e "$f" ] || continue
        ARGS+=("/store/$(basename "$f")=$f")
    done
fi
# DIE MITGELIEFERTEN BUENDEL -- der Vorher-Zustand.
#
# RUNDE GLYPHE: `nur=` -- SONST GIBT ES DIESES ABBILD NICHT.
#
# Ein Buendel ist ein VERWEIS auf eine Datei unter /bin; liegt sie nicht
# auf DIESER Platte, bricht mkfs.py mit "gibt es nicht" ab. Die Runde
# WERKZEUGE hat assets/apps/taskmgr.osp dazugelegt, und /bin dieses
# Laeufers hat kein taskmgr -- gemessen am zusammengefuehrten Stand:
#
#     FEHLGESCHLAGEN: mkfs
#     mkfs: '/bin/taskmgr' gibt es nicht
#
# MERGE-6 hat denselben Bruch in tools/design/capture.sh und
# tools/multicore/run.sh gefunden und dort denselben Riegel eingebaut;
# HIER fiel er nicht auf, weil dieser Laeufer in jener Runde nicht
# gefahren ist. Er ist der Grund, warum die Auflage offen blieb.
while read -r z; do ARGS+=("$z"); done \
    < <(python3 tools/k15/bundle.py assets/apps "$P/buendel" \
        "nur=$(ls "$OUT/bin" | tr '\n' ' ')")
# DAS PRUEFMATERIAL FUER DIE GEGENPROBE.
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
