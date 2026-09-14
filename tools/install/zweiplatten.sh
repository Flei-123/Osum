#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/zweiplatten.sh -- INSTALLIERT ER AUF DIE RICHTIGE PLATTE?
#
#   bash tools/install/zweiplatten.sh [bauverzeichnis] [ausgabeverzeichnis]
#
# ==================================================================
# WOGEGEN DIESER LAUF ANTRITT
# ==================================================================
#
# Bis zur Runde INSTALLER stand im Installationsprogramm der Name der
# EFI-Partition FEST:
#
#     static mut D_HDA1 = "/dev/hda1"
#
# Das geht genau so lange gut, wie nur eine Platte im Rechner steckt.
# Wer auf die ZWEITE installiert, bekommt GPT und Wurzeldateisystem
# richtig auf `/dev/hdb` geschrieben -- und danach haengt das Programm
# `/dev/hda1` ein und schreibt den Bootlader auf die EFI-Partition der
# ERSTEN Platte. Das ist kein Schoenheitsfehler: es ist ein Schreibzugriff
# auf einen Datentraeger, den der Benutzer gar nicht genannt hat, und im
# schlimmsten Fall auf das System, von dem er gerade nicht wegwollte.
#
# DIESER LAUF STELLT GENAU DIESE FALLE AUF:
#
#   /dev/hda   ist ABSICHTLICH schon beschrieben -- es ist die fertige
#              Installation aus `tools/install/abnahme.sh`. Vorher und
#              nachher wird ihre Pruefsumme genommen.
#   /dev/hdb   ist leer und das ZIEL.
#
# Danach muessen DREI Dinge gelten, und alle drei werden geprueft:
#
#   1. Die zweite Platte traegt eine vollstaendige Installation.
#   2. Das Programm hat `/dev/hdb1` eingehaengt und nicht `/dev/hda1`.
#   3. DIE ERSTE PLATTE IST OKTETT FUER OKTETT UNVERAENDERT.
#
# Die dritte ist die eigentliche Zusage. Die ersten beiden koennten
# stimmen, waehrend nebenbei etwas kaputtgeht.
#
# ==================================================================
# WARUM DER SCHALTER `zweite` UND NICHT EIN KLICK
# ==================================================================
#
# Der Laeufer muss dem Programm sagen, WELCHE der beiden Platten es
# nehmen soll -- sonst nimmt `sofort` die erste, und das waere der
# falsche Versuch. `zweite` waehlt den zweiten Eintrag der Liste. Ein
# Mensch klickt statt dessen die Zeile an; das ist derselbe Weg durch
# denselben Code, nur ohne Maus.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

BAU=${1:-/tmp/abnahme/bau}
OUT=${2:-/tmp/zweiplatten}
mkdir -p "$OUT"

ok=0; bad=0
ok()  { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
bad() { printf '  [FEHL] %s\n' "$*"; bad=$((bad+1)); }

[ -f "$BAU/osum.mb" ] || { echo "== $BAU/osum.mb fehlt -- erst tools/install/abnahme.sh laufen lassen" >&2; exit 1; }
[ -f "$BAU/root.img" ] || { echo "== $BAU/root.img fehlt" >&2; exit 1; }

# ---- die erste Platte: eine FERTIGE Installation, die heil bleiben muss.
QUELLE=${QUELLE:-/tmp/abnahme/platte.img}
if [ ! -f "$QUELLE" ]; then
    echo "== $QUELLE fehlt -- erst tools/install/abnahme.sh laufen lassen" >&2
    exit 1
fi
cp -f "$QUELLE" "$OUT/hda.img"
VORHER=$(sha256sum < "$OUT/hda.img" | cut -d' ' -f1)
echo "   hda  eine fertige Installation, sha256 ${VORHER:0:16}…"

# ---- die zweite: leer, und das Ziel.
rm -f "$OUT/hdb.img"
head -c $((320 * 1024 * 1024)) /dev/zero > "$OUT/hdb.img"
echo "   hdb  leer, 320 MiB -- das Ziel"

APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1200 nokbd nosched noproc nofs"
APPEND="$APPEND lang=de uiscale=1 wigapp=/bin/installer,sofort,zweite"

# SOBALD DIE INSTALLATION FERTIG IST, WIRD DIE MASCHINE BEENDET.
# `wighalt` haelt den Fensterserver absichtlich lange offen -- das
# braucht die Installation, sie dauert Minuten. Danach aber noch
# zwoelf Minuten auf einen Zeitablauf zu warten, misst nichts; die
# Platten werden erst hinterher gelesen.
timeout "${LIMIT:-1200}" $QEMU_X86 -m 512 \
    -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$OUT/ser.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -drive "file=$OUT/hda.img,format=raw,if=ide,index=0" \
    -drive "file=$OUT/hdb.img,format=raw,if=ide,index=1" > "$OUT/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 1200 ]; do
    grep -qa 'installer: fertig\|installer: FEHLER' "$OUT/ser.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 4
kill "$QP" 2>/dev/null
wait "$QP" 2>/dev/null

echo
echo "== was das Programm gesehen und getan hat"
grep -aE '^installer: (disk|ready|gewaehlt|esp=|fertig|FEHLER|bei=)' "$OUT/ser.txt" \
    | head -12 | sed 's/^/        /'
echo

# ---- 1. hat es beide Platten gefunden?
n=$(grep -aoE 'installer: ready n=[0-9]+' "$OUT/ser.txt" | head -1 | sed 's/.*=//')
[ "${n:-0}" -ge 2 ] && ok "beide Platten in der Liste (n=$n)" \
    || bad "nur ${n:-0} Platte(n) gefunden -- der Versuch misst nichts"

# ---- 2. hat es die ZWEITE eingehaengt?
esp=$(grep -aoE 'installer: esp=/dev/[a-z0-9]+' "$OUT/ser.txt" | head -1 | sed 's/.*esp=//')
if [ "$esp" = "/dev/hdb1" ]; then
    ok "es hat die EFI-Partition des ZIELS eingehaengt: $esp"
elif [ "$esp" = "/dev/hda1" ]; then
    bad "es hat /dev/hda1 eingehaengt -- also die FREMDE Platte"
else
    bad "keine oder unbekannte EFI-Partition: '${esp:-keine}'"
fi

# ---- 3. meldet es sich fertig?
grep -qa 'installer: fertig' "$OUT/ser.txt" \
    && ok "die Installation meldet sich fertig" \
    || bad "die Installation ist nicht fertig geworden"

# ---- 4. DIE ERSTE PLATTE MUSS UNVERAENDERT SEIN. Die eigentliche Zusage.
NACHHER=$(sha256sum < "$OUT/hda.img" | cut -d' ' -f1)
if [ "$VORHER" = "$NACHHER" ]; then
    ok "DIE ERSTE PLATTE IST OKTETT FUER OKTETT UNVERAENDERT"
else
    bad "die erste Platte wurde beschrieben -- ${VORHER:0:16}… -> ${NACHHER:0:16}…"
fi

# ---- 5. und die zweite traegt jetzt wirklich etwas.
sgdisk -p "$OUT/hdb.img" > "$OUT/hdb-gpt.txt" 2>&1
grep -q 'EF00' "$OUT/hdb-gpt.txt" && ok "die zweite Platte hat eine EFI-Partition" \
    || bad "auf der zweiten Platte steht keine EFI-Partition"
grep -qE 'OSUM' "$OUT/hdb-gpt.txt" && ok "die zweite Platte hat eine Wurzelpartition" \
    || bad "auf der zweiten Platte steht keine Wurzelpartition"
if mdir -i "$OUT/hdb.img@@1048576" ::/EFI/BOOT 2>/dev/null | grep -qi 'BOOTX64'; then
    ok "der Bootlader liegt auf der EFI-Partition der ZWEITEN Platte"
else
    bad "kein Bootlader auf der zweiten Platte"
fi

printf '\n=======================================================\n'
printf 'ZWEI PLATTEN:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
