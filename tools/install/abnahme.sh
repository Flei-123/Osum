#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/abnahme.sh -- DIE KETTE, DIE P-001 WIRKLICH ABNIMMT.
#
#   bash tools/install/abnahme.sh [ausgabeverzeichnis]
#
# ==================================================================
# WAS HIER GEMESSEN WIRD, UND WARUM GENAU DIESE REIHENFOLGE
# ==================================================================
#
# Ein Installationsprogramm ist nicht dann fertig, wenn es "fertig"
# meldet. Es ist dann fertig, wenn die Maschine OHNE DAS
# INSTALLATIONSMEDIUM startet und das, was man angelegt hat, einen
# Neustart ueberlebt. Alles davor ist eine Behauptung.
#
# Deshalb genau diese Kette, und jedes Glied einzeln belegt:
#
#   1. VOM STICK STARTEN. Der Kern kommt als Multiboot-Modul mit der
#      Wurzel im Arbeitsspeicher -- die Lage, in der OrientOS heute
#      ausgeliefert wird. Beleg: ein Foto des Schreibtischs.
#
#   2. DAS FENSTER STEHT. /bin/installer laeuft, findet die Platte und
#      zeigt sie mit Groesse und Belegung. Beleg: ein Foto, und die
#      Rechtecke, die das Programm selbst meldet.
#
#   3. INSTALLIEREN. Die Platte bekommt GPT, eine EFI-Partition, das
#      Wurzeldateisystem und den Bootlader. Beleg: die Meldungen der
#      Maschine UND der Wirt, der die Platte danach mit SEINEN
#      Werkzeugen liest (sgdisk, mdir) -- einem Installationsprogramm,
#      dem nur sein eigenes Betriebssystem glaubt, glaubt hier niemand.
#
#   4. DIE MASCHINE AUS. Kein Zustand im Arbeitsspeicher darf das
#      naechste Glied tragen.
#
#   5. DAS MEDIUM WEG. QEMU bekommt KEIN `-kernel`, KEIN `-initrd` und
#      KEIN `-cdrom`. Nur die Platte und OVMF. Was jetzt noch startet,
#      startet von der Platte -- oder gar nicht. Das ist das Glied, an
#      dem sich entscheidet, ob diese Runde etwas wert ist.
#
#   6. EINE DATEI ANLEGEN. Auf der Wurzel, die jetzt auf der Platte
#      liegt.
#
#   7. NEU STARTEN, WIEDER OHNE MEDIUM. Und die Datei MUSS noch da
#      sein, mit ihrem Inhalt.
#
# GEGENPROBE (Glied 8): dieselbe Platte, aber mit einem gekippten
# Oktett im Superblock der Wurzelpartition. Dann DARF der Kern die
# Wurzel NICHT finden. Ohne diese Gegenprobe waere Glied 7 auch dann
# gruen, wenn der Kern seine Wurzel in Wahrheit woanders herholt.
#
# ==================================================================
# WARUM `roh` UND NICHT `platte` FUER DIE GEGENPROBE
# ==================================================================
#
# Runde INSTALL hat das schon einmal gemessen und aufgeschrieben: OVMF
# REPARIERT einen kaputten primaeren GPT-Kopf aus der Sicherung, bevor
# ein Betriebssystem ihn zu Gesicht bekommt. Wer die Tafel kaputtmacht
# und ueber OVMF startet, prueft die Firmware und nicht sich selbst.
# Die Gegenprobe hier trifft deshalb den SUPERBLOCK des Dateisystems --
# den repariert niemand.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

OUT=${1:-/tmp/abnahme}
mkdir -p "$OUT"
SHOTS="$OUT/bilder"
mkdir -p "$SHOTS"

ok=0; bad=0
ok()  { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
bad() { printf '  [FEHL] %s\n' "$*"; bad=$((bad+1)); }
titel() { printf '\n== %s\n' "$*"; }

# Ein Foto aus einem laufenden QEMU ueber den Monitor.
schuss() { # <sockel> <ziel.png>
    local sock=$1 ziel=$2 ppm="$OUT/tmp.ppm"
    printf 'screendump %s\n' "$ppm" | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
    sleep 3
    [ -s "$ppm" ] || return 1
    python3 -c "
from PIL import Image
Image.open('$ppm').save('$ziel')
" 2>/dev/null && rm -f "$ppm" && return 0
    return 1
}

# Wieviel steht auf einem Bild? Ein Schirm, der zu 99 % eine Farbe ist,
# zeigt nichts -- und ein Beleg, der nichts zeigt, ist keiner.
tinte() { # <png> -> Prozent als ganze Zahl
    python3 -c "
from PIL import Image
from collections import Counter
im=Image.open('$1').convert('RGB'); px=im.load(); W,H=im.size
c=Counter(px[x,y] for y in range(0,H,2) for x in range(0,W,2))
bg,n=c.most_common(1)[0]
tot=sum(c.values())
print(int(100*(tot-n)/tot))
" 2>/dev/null || echo 0
}

BAU=${BAU:-$OUT/bau}
ZIEL="$OUT/platte.img"
ZIEL_MIB=${ZIEL_MIB:-320}

# ==================================================================
titel "0. bauen -- Kern UND Abbild aus DEMSELBEN Baum"
# ==================================================================
#
# Wer einen neuen Kern gegen eine alte Wurzel laufen laesst, misst alte
# Programme. Deshalb beides in einem Lauf.
if [ -n "${SCHNELL:-}" ] && [ -f "$BAU/osum.mb" ] && [ -f "$BAU/root.img" ]; then
    echo "   (SCHNELL: vorhandenes $BAU wird benutzt)"
else
    bash tools/usbimg/build.sh "$BAU" > "$OUT/bau.log" 2>&1 || {
        tail -20 "$OUT/bau.log"; echo "== der Bau ist fehlgeschlagen"; exit 1; }
fi
[ -f "$BAU/osum.mb" ] && ok "Kern gebaut ($(stat -c%s "$BAU/osum.mb") Oktette)" \
    || bad "kein Kern"
[ -f "$BAU/root.img" ] && ok "Wurzelabbild gebaut ($(stat -c%s "$BAU/root.img") Oktette)" \
    || bad "kein Wurzelabbild"
python3 tools/osum/mkfs.py list "$BAU/root.img" 2>/dev/null > "$OUT/liste.txt"
grep -q '^/bin/installer ' "$OUT/liste.txt" \
    && ok "/bin/installer liegt im Abbild" || bad "/bin/installer fehlt im Abbild"
grep -q '^/apps/installer.osp/start' "$OUT/liste.txt" \
    && ok "das Buendel liegt im Abbild (steht im Menue)" || bad "Buendel fehlt"

# Eine leere Platte. DUENN angelegt: sie ist 320 MiB gross und belegt
# nur, was wirklich daraufgeschrieben wird -- auf einem Wirt mit 3 GiB
# frei ist das der Unterschied zwischen "laeuft" und "kein Platz".
rm -f "$ZIEL"
truncate -s "${ZIEL_MIB}M" "$ZIEL"
ok "leere Zielplatte, ${ZIEL_MIB} MiB"

# ==================================================================
titel "1.-3. vom Stick starten, das Fenster zeigen, installieren"
# ==================================================================
#
# EIN LAUF fuer diese drei Glieder, und das ist Absicht: sie gehoeren
# zusammen. Der Stick startet, das Fenster steht, und aus demselben
# laufenden System heraus wird die Platte beschrieben. Ein Neustart
# dazwischen waere ein anderer Versuch.
SOCK="$OUT/mon.sock"
SER="$OUT/stick.txt"
rm -f "$SER" "$SOCK"

# `vfs` IST HIER PFLICHT UND WAR ES BEIM ERSTEN LAUF NICHT.
#
# Ohne dieses Wort haengt der Kern /dev gar nicht ein -- und dann
# findet /bin/installer keine einzige Platte, obwohl eine daran
# haengt. Auf der Leitung stand woertlich "installer: ready n=0",
# und im Fenster war die Tabelle leer. Der Fehler sah nach einem
# Fehler des Programms aus und war einer der Kommandozeile.
# tools/install/oneshot.sh hat das Wort von Anfang an drin
# (BASIS="osum vfs ..."); hier fehlte es.
# `wighalt=1200` UND NICHT `wiglong` -- ZWANZIG SEKUNDEN REICHEN NICHT.
#
# GEMESSEN: mit `wiglong` haelt der Fensterserver 20 Sekunden still
# (kernel/kgui.fi, halt_secs) und der Kern faehrt danach herunter --
# auf der Leitung steht dann "kernel: done", und zwar MITTEN in der
# Installation. Das Kopieren der Wurzel dauert aber Minuten: 32768
# Sektoren, und der Kern des Systems geht oktettweise durch den
# FAT32-Schreiber auf die EFI-Partition.
#
# Der Fehler sah aus wie "der Installer tut nichts": das Fenster
# stand, die Platte war gefunden, und dann kam einfach nichts mehr.
# `wighalt=<sekunden>` sticht beide Vorgaben (Runde OBERFLAECHE).
# UND `wmhold` DAZU -- OHNE DAS WIRKT `wighalt` NICHT.
#
# GEMESSEN, zum zweiten Mal an derselben Stelle: die Halteschleife
# in kernel/kgui.fi steht HINTER `if !mode_on(M_WMHOLD) { ... }`.
# Ohne `wmhold` wird sie nie betreten, `wighalt` liest niemand, und
# auf der Leitung fehlt die Zeile "wm: halt sek=" -- der Kern faehrt
# herunter, sobald der Fensterserver seine Messreihe fertig hat.
# Mit `wmhold` UND `wighalt=1200` laeuft er zwanzig Minuten weiter,
# und genau so lange kann eine Installation dauern.
#
# `wmdauer` bleibt daneben: es sorgt dafuer, dass die Schleife auch
# ohne Shell im Fenster laeuft (Runde TAFEL).
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1200 nokbd nosched noproc nofs"
APPEND="$APPEND lang=de uiscale=1 wigapp=/bin/installer,sofort"

timeout 900 $QEMU_X86 -m 512 \
    -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$SER" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$ZIEL,format=raw,if=ide,index=0" > "$OUT/qemu1.log" 2>&1 &
QP=$!

# Warten, bis das Fenster steht.
i=0
while [ $i -lt 400 ]; do
    grep -qa 'installer: ready' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i+1))
done
sleep 5
if schuss "$SOCK" "$SHOTS/20-fenster.png"; then
    t=$(tinte "$SHOTS/20-fenster.png")
    if [ "$t" -ge 5 ]; then
        ok "das Installationsfenster steht (Bild: ${t} % Tinte)"
    else
        bad "der Schirm ist fast leer (${t} % Tinte) -- 20-fenster.png"
    fi
else
    bad "kein Foto vom Fenster"
fi

n=$(grep -ac 'installer: rect' "$SER" 2>/dev/null || echo 0)
[ "${n:-0}" -ge 5 ] && ok "das Fenster meldet $n Bedienelemente" \
    || bad "nur ${n:-0} Bedienelemente gemeldet"
grep -qa 'installer: disk /dev/hda' "$SER" \
    && ok "die Platte wurde gefunden und aufgelistet" \
    || bad "die Platte steht nicht in der Liste"

# Jetzt laeuft die Installation (Schalter `sofort`). Sie dauert Minuten.
i=0
while [ $i -lt 1600 ]; do
    grep -qa 'installer: fertig\|installer: FEHLER' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 3
schuss "$SOCK" "$SHOTS/30-fertig.png" || true

if grep -qa 'installer: fertig' "$SER"; then
    ok "die Installation meldet sich fertig"
else
    bad "die Installation ist nicht fertig geworden"
    grep -aE 'installer:' "$SER" | tail -5 | sed 's/^/        /'
fi
# Die Schritte, die sie unterwegs gemeldet hat.
st=$(grep -aoE 'installer: step=[0-9]+' "$SER" | sed 's/.*=//' | sort -un | tr '\n' ' ')
echo "        Schritte auf der Leitung: $st"
case "$st" in *1*2*3*4*5*) ok "alle fuenf Schritte gemeldet" ;;
                        *) bad "nicht alle Schritte gemeldet: $st" ;; esac

# ==================================================================
titel "4. die Maschine aus"
# ==================================================================
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null
sleep 1
pgrep -f "file=$ZIEL" > /dev/null && bad "es laeuft noch eine Maschine auf der Platte" \
    || ok "die Maschine ist aus"

# ------- und der WIRT liest die Platte mit SEINEN Werkzeugen
titel "4b. was der Wirt auf der Platte findet"
sgdisk -p "$ZIEL" > "$OUT/gpt.txt" 2>&1
grep -q 'EF00' "$OUT/gpt.txt" && ok "eine EFI-Partition steht in der Tafel" \
    || bad "keine EFI-Partition"
grep -qE 'OSUM' "$OUT/gpt.txt" && ok "die Wurzelpartition steht in der Tafel" \
    || bad "keine Wurzelpartition"
mdir -i "$ZIEL@@1048576" ::/EFI/BOOT > "$OUT/esp.txt" 2>&1
grep -qi 'BOOTX64' "$OUT/esp.txt" && ok "der Bootlader liegt auf der EFI-Partition" \
    || bad "kein BOOTX64.EFI"
mdir -i "$ZIEL@@1048576" :: > "$OUT/esp2.txt" 2>&1
grep -qi 'osum' "$OUT/esp2.txt" && ok "der Kern liegt auf der EFI-Partition" \
    || bad "kein Kern auf der EFI-Partition"
grep -qi 'limine' "$OUT/esp2.txt" && ok "die Startdatei liegt daneben" \
    || bad "keine limine.conf"

# ==================================================================
titel "5. VON DER PLATTE starten -- ohne Stick, ohne Modul"
# ==================================================================
#
# KEIN -kernel, KEIN -initrd. Was jetzt startet, startet ueber die
# EFI-Partition, die der Installer beschrieben hat, mit der
# Kommandozeile, die AUF DER PLATTE steht.
OVMF=$(ls /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)
platte_lauf() { # <name> <skript> <limit>
    local name=$1 skript=$2 limit=${3:-300}
    local ser="$OUT/$name.txt" vars="$OUT/$name.vars.fd"
    rm -f "$ser"
    cp -f /usr/share/OVMF/OVMF_VARS.fd "$vars" 2>/dev/null || true
    # ============================================================
    # DIE STARTDATEI DES INSTALLERS BLEIBT, WO SIE IST
    #
    # Fuer den Lauf OHNE Skript (Glied 5) wird hier NICHTS
    # ueberschrieben: was gemessen werden soll, ist die Datei, die der
    # Installer selbst geschrieben hat. Wer sie vorher ersetzt, misst
    # seine eigene Kommandozeile und erfaehrt nichts darueber, ob die
    # Installation eine startfaehige Platte hinterlaesst.
    #
    # Fuer die Laeufe MIT Skript (Glieder 6 und 7) muss eine hinein --
    # ein Skript laesst sich nur ueber die Kommandozeile uebergeben,
    # und die steht auf der Platte. Ein `-append` waere geschummelt.
    # Also wird die limine.conf dann geaendert, so wie ein Mensch es
    # mit einem Editor taete.
    if [ -z "$skript" ]; then
        local args0=(-machine pc -cpu max -m 512 -display none -no-reboot
            -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
            -serial "file:$ser"
            -drive "file=$ZIEL,format=raw,if=ide,index=0"
            -device isa-debug-exit,iobase=0xf4,iosize=0x04)
        [ -f "$vars" ] && args0+=(-drive "if=pflash,format=raw,unit=1,file=$vars")
        timeout "$limit" $QEMU_X86 "${args0[@]}" > /dev/null 2>&1
        return $?
    fi
    {
        echo "timeout: 0"
        echo "verbose: yes"
        echo
        echo "/OrientOS"
        echo "    protocol: multiboot1"
        echo "    path: boot():/osum.mb"
        if [ -n "$skript" ]; then
            echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3 script=$skript"
        else
            echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3"
        fi
    } > "$OUT/$name.conf"
    mcopy -o -i "$ZIEL@@1048576" "$OUT/$name.conf" ::/limine.conf 2>/dev/null \
        || { echo "mcopy fehlgeschlagen"; return 9; }
    local args=(-machine pc -cpu max -m 512 -display none -no-reboot
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
        -serial "file:$ser"
        -drive "file=$ZIEL,format=raw,if=ide,index=0"
        -device isa-debug-exit,iobase=0xf4,iosize=0x04)
    [ -f "$vars" ] && args+=(-drive "if=pflash,format=raw,unit=1,file=$vars")
    timeout "$limit" $QEMU_X86 "${args[@]}" > /dev/null 2>&1
    return $?
}

platte_lauf start "" 300
rc=$?
[ "$rc" = 21 ] && ok "die Platte startet (Beendigungscode 21)" \
    || bad "die Platte startet nicht (Code $rc)"
grep -qa 'osum: rootpart=' "$OUT/start.txt" \
    && ok "der Kern findet seine Wurzel auf der Platte: $(grep -aoE 'rootpart=[0-9]+ +first=[0-9]+ +blocks=[0-9]+' "$OUT/start.txt" | head -1)" \
    || bad "der Kern findet keine Wurzelpartition"
grep -qa 'osum: mount=1' "$OUT/start.txt" \
    && ok "die Wurzel ist eingehaengt" || bad "die Wurzel ist nicht eingehaengt"
# DER ENTSCHEIDENDE SATZ: es war KEIN Modul im Spiel.
grep -qa 'from module' "$OUT/start.txt" \
    && bad "es lief doch ueber ein Boot-Modul -- dann ist nichts bewiesen" \
    || ok "GEGENPROBE: 'from module' kommt nicht vor -- es war kein Stick im Spiel"

# ==================================================================
titel "6. eine Datei anlegen -- auf der Platte"
# ==================================================================
platte_lauf schreib "echo hallo-von-der-platte >/beweis.txt;cat /beweis.txt;sync;exit" 300
rc=$?
[ "$rc" = 21 ] && ok "der Schreiblauf ist durchgelaufen" \
    || bad "der Schreiblauf endete mit Code $rc"
grep -qa 'hallo-von-der-platte' "$OUT/schreib.txt" \
    && ok "die Datei wurde angelegt und gelesen" \
    || bad "die Datei liess sich nicht anlegen"

# ==================================================================
titel "7. NEU STARTEN -- und die Datei muss noch da sein"
# ==================================================================
platte_lauf wieder "cat /beweis.txt;exit" 300
rc=$?
[ "$rc" = 21 ] && ok "der zweite Start ist durchgelaufen" \
    || bad "der zweite Start endete mit Code $rc"
if grep -qa 'hallo-von-der-platte' "$OUT/wieder.txt"; then
    ok "DIE DATEI HAT DEN NEUSTART UEBERLEBT -- das ist der Punkt der Runde"
else
    bad "die Datei ist nach dem Neustart weg"
    tail -5 "$OUT/wieder.txt" | sed 's/^/        /'
fi

# ==================================================================
titel "8. GEGENPROBE -- eine kaputte Wurzel darf NICHT starten"
# ==================================================================
#
# Ein gekipptes Oktett in der Kennung des Superblocks der
# Wurzelpartition. Getroffen wird das Dateisystem und nicht die
# GPT-Tafel: einen kaputten primaeren GPT-Kopf repariert OVMF aus der
# Sicherung, bevor der Kern ihn sieht (gemessen in Runde INSTALL) --
# dann prueft man die Firmware und nicht sich selbst.
cp -f "$ZIEL" "$OUT/kaputt.img"
ERST=$(grep -aoE 'first=[0-9]+' "$OUT/start.txt" | head -1 | sed 's/.*=//')
if [ -n "$ERST" ]; then
    python3 - "$OUT/kaputt.img" "$ERST" <<'PYEOF'
import sys
pfad, erst = sys.argv[1], int(sys.argv[2])
with open(pfad, "r+b") as f:
    f.seek(erst * 512)
    d = bytearray(f.read(8))
    d[0] ^= 0xFF          # die Kennung "-OFS" kippen
    f.seek(erst * 512)
    f.write(bytes(d))
print("Superblock bei Sektor", erst, "gekippt")
PYEOF
    ZIEL_ALT="$ZIEL"; ZIEL="$OUT/kaputt.img"
    platte_lauf kaputt "" 240
    ZIEL="$ZIEL_ALT"
    if grep -qa 'osum: mount=1' "$OUT/kaputt.txt"; then
        bad "die kaputte Wurzel wurde trotzdem eingehaengt -- die Pruefung greift nicht"
    else
        ok "GEGENPROBE: die kaputte Wurzel wird NICHT eingehaengt"
    fi
    rm -f "$OUT/kaputt.img"
else
    bad "der erste Sektor der Wurzel ist unbekannt -- Gegenprobe nicht moeglich"
fi

# ==================================================================
printf '\n===========================================================\n'
printf 'ABNAHME P-001:  %d gruen, %d rot\n' "$ok" "$bad"
printf 'Bilder: %s\n' "$SHOTS"
printf '===========================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
