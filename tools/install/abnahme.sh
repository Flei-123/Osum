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
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
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
# HIER STEHT ABSICHTLICH KEIN `wmshell` -- DIE ZEILE IST GEMESSEN.
#
# RUNDE INSTALLER2 (P-001). Der Fehler dieser Runde sah so aus:
#
#     osum: pid1 init
#     init: ziel=grafik
#     init: dienste=1
#     init: herunterfahren      <- und `k15: start` kam nie
#
# URSACHE: `osum(state)` in kernel/kmain.fi startet den ERSTEN PROZESS
# `/bin/init`, und zwar VOR `gfx.stage_surface`, das den Fensterserver
# und damit `wigapp=` ueberhaupt erst hochzieht. `osum` kehrt erst
# zurueck, wenn init fertig ist; init findet im Ziel `grafik` keinen
# Dienst (die inittab des Sticks fuehrt nur `sh:konsole:ctrl`), laeuft
# in seine Leerlaufschranke (4000 * 25 ms) und schaltet ab.
#
# BEHOBEN IM KERN und nicht hier: `wm_owns_shell` fragt jetzt nach
# ALLEN Woertern, mit denen der Fensterserver sein Programm selbst
# startet (`wig`, `wigfiles`, `wigstart`, `desk`, `tileshot`), nicht
# mehr nur nach `wmshell`. Bei `wig` startet `osum` deshalb kein init
# mehr -- haengt die Wurzel aber weiter ein, denn die frueher
# Rueckkehr steht jetzt VOR dem ersten Prozess und nicht vor dem
# Einhaengen (sonst faende der Installer keine Platte: "ready n=0").
#
# UND WARUM NICHT EINFACH `wmshell` DAZU: das Wort startet zusaetzlich
# `/bin/sh` im Terminalfenster. Unter `nokbd` endet sie sofort auf EOF
# und `wait_wm` startet sie im Sekundentakt neu. GEMESSEN: 361 Starts,
# und das Kopieren der Wurzel fiel von 940 auf 43 Bloecke je Minute --
# der Installer verhungerte neben seinem eigenen Terminal.
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
# DIE EFI-PARTITION, DIE SIE EINGEHAENGT HAT. Der Name wird aus dem
# gewaehlten Geraet gebaut; ein fest verdrahtetes /dev/hda1 haette bei
# einer Installation auf die zweite Platte die EFI-Partition der
# ERSTEN beschrieben.
esp=$(grep -aoE 'installer: esp=/dev/[a-z0-9]+' "$SER" | head -1 | sed 's/.*esp=//')
if [ "$esp" = "/dev/hda1" ]; then
    ok "die EFI-Partition wurde aus dem Ziel gebaut: $esp"
else
    bad "falsche oder fehlende EFI-Partition: '${esp:-keine}'"
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
        # MIT MONITOR UND MIT SCHIRM: von diesem Lauf soll ein BILD
        # entstehen. Es ist der Beleg, auf den es in dieser Runde
        # ankommt -- ein Schreibtisch, der von der PLATTE kommt, ohne
        # dass ein Stick im Rechner steckt.
        local msock="$OUT/mon-platte.sock"
        rm -f "$msock"
        local args0=(-machine pc -cpu max -m 512 -display none -no-reboot
            -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
            -serial "file:$ser"
            -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32
            -monitor "unix:$msock,server,nowait"
            -drive "file=$ZIEL,format=raw,if=ide,index=0"
            -device isa-debug-exit,iobase=0xf4,iosize=0x04)
        [ -f "$vars" ] && args0+=(-drive "if=pflash,format=raw,unit=1,file=$vars")
        timeout "$limit" $QEMU_X86 "${args0[@]}" > /dev/null 2>&1 &
        local qp=$!
        # Warten, bis der Schreibtisch wirklich steht.
        local w=0
        while [ $w -lt 240 ]; do
            grep -qa 'desk: start /bin/taskbar' "$ser" 2>/dev/null && break
            kill -0 "$qp" 2>/dev/null || break
            sleep 1; w=$((w+1))
        done
        sleep 12
        schuss "$msock" "$SHOTS/40-von-der-platte.png" || true
        kill "$qp" 2>/dev/null
        wait "$qp" 2>/dev/null
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
            # `initsh` GEHOERT DAZU, UND OHNE ES LAEUFT DAS SKRIPT NICHT.
            #
            # GEMESSEN (Runde INSTALLER2). Seit der Installer eine
            # VOLLSTAENDIGE Wurzel schreibt, liegt auf der Platte auch
            # `/bin/init` -- und `osum(state)` in kernel/kmain.fi
            # startet dann init statt `/bin/sh`. Das Skript aus
            # `script=` liest laut Kommentar bei `wm_owns_shell` "der,
            # der zuerst danach greift"; init greift gar nicht danach.
            # Es findet im Ziel `grafik` keinen Dienst, laeuft in seine
            # Leerlaufschranke und schaltet ab:
            #
            #     osum: pid1 init
            #     init: ziel=grafik
            #     init: herunterfahren
            #
            # Auf der Leitung stand danach KEIN `sh: ready`, und
            # /beweis.txt wurde nie angelegt. Glied 7 meldete deshalb
            # "die Datei ist nach dem Neustart weg" -- sie war nie da.
            #
            # `initsh` ist der dafuer vorgesehene Notweg (kmain.fi,
            # M_INITSH): er nimmt den alten Weg und startet `/bin/sh`,
            # das `script=` dann auch wirklich abarbeitet.
            echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3 initsh script=$skript"
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

platte_lauf start "" 400
rc=$?
# DER BEENDIGUNGSCODE IST HIER 124 UND NICHT 21 -- UND DAS IST DAS
# RICHTIGE ERGEBNIS.
#
# 21 ist der vereinbarte Erfolgscode eines Laufs, der etwas ABARBEITET
# und danach aufhoert (`isa-debug-exit`). Die limine.conf, die der
# Installer schreibt, startet aber den SCHREIBTISCH -- und ein
# Schreibtisch hoert nicht von selbst auf. Er laeuft, bis jemand ihn
# beendet; hier bis `timeout` zuschlaegt, und das ist 124.
#
# Ein Lauf, der hier mit 21 zurueckkaeme, waere der verdaechtige:
# dann haette das System nach dem Start etwas abgearbeitet und sich
# beendet, statt eine Oberflaeche hinzustellen.
#
# Gemessen wird deshalb nicht der Code, sondern WAS AUF DER LEITUNG
# STEHT -- die Wurzel, die Einhaengung und der Schreibtisch. Die drei
# Zusagen darunter tun genau das.
# Der Lauf wird von aussen beendet, sobald das Foto steht -- der Code
# sagt hier also nichts. Was zaehlt, steht auf der Leitung und im Bild.
if [ -s "$OUT/start.txt" ]; then
    ok "die Platte startet und laeuft (ein Schreibtisch endet nicht von selbst)"
else
    bad "von der Platte kam keine einzige Zeile (Code $rc)"
fi
if [ -s "$SHOTS/40-von-der-platte.png" ]; then
    t=$(tinte "$SHOTS/40-von-der-platte.png")
    if [ "$t" -ge 5 ]; then
        ok "BILD: der Schreibtisch von der Platte (${t} % Tinte)"
    else
        bad "der Schirm von der Platte ist fast leer (${t} % Tinte)"
    fi
else
    bad "kein Bild vom Schreibtisch auf der Platte"
fi
# DIE WURZEL -- auf BEIDEN Wegen. Die limine.conf, die der Installer
# schreibt, startet den SCHREIBTISCH; der geht ueber kgui.surface und
# meldet `wm: rootpart=`. Der Textweg (kmain.osum) meldet
# `osum: rootpart=`. Gesucht wird, was davon dasteht -- entscheidend
# ist, DASS die Wurzel von der Partition kommt.
if grep -qaE '(osum|wm): rootpart=' "$OUT/start.txt"; then
    ok "der Kern findet seine Wurzel auf der Platte: $(grep -aoE 'rootpart=[0-9]+ +first=[0-9]+ +blocks=[0-9]+' "$OUT/start.txt" | head -1)"
else
    bad "der Kern findet keine Wurzelpartition"
fi
if grep -qaE '(osum|wm): mount=1' "$OUT/start.txt"; then
    ok "die Wurzel ist eingehaengt"
else
    bad "die Wurzel ist nicht eingehaengt"
fi
# UND DER SCHREIBTISCH KOMMT HOCH. Das ist der Punkt, an dem sich
# "die Platte bootet" von "man kann damit arbeiten" unterscheidet:
# ein Fenster, das der Fensterserver meldet, gibt es nur, wenn ein
# Ring-3-Programm von DIESER Platte gestartet ist.
if grep -qa 'desk: start /bin/desktop' "$OUT/start.txt"; then
    ok "der Schreibtisch startet von der Platte"
else
    bad "kein Schreibtisch -- die Oberflaeche kommt nicht hoch"
fi
# DER ENTSCHEIDENDE SATZ: es war KEIN Modul im Spiel.
grep -qa 'from module' "$OUT/start.txt" \
    && bad "es lief doch ueber ein Boot-Modul -- dann ist nichts bewiesen" \
    || ok "GEGENPROBE: 'from module' kommt nicht vor -- es war kein Stick im Spiel"

# ==================================================================
titel "6. eine Datei anlegen -- auf der Platte"
# ==================================================================
platte_lauf schreib "echo hallo-von-der-platte >/beweis.txt;cat /beweis.txt;sync;exit" 300
rc=$?
# DER BEENDIGUNGSCODE: 21 ODER 0, UND BEIDES IST RICHTIG.
#
# 21 ist `isa-debug-exit` (kernel/power.fi, EXIT_OK): ein Lauf, der
# etwas abarbeitet und den Pruefstand beendet. 0 ist die ECHTE
# ACPI-Abschaltung -- derselbe Kommentar in power.fi sagt es woertlich:
# "eine ACPI-Abschaltung ergibt 0, isa-debug-exit ergibt 21".
#
# GEMESSEN (Runde INSTALLER2): seit auf der Platte ein vollstaendiges
# System liegt, endet der Lauf ueber ACPI ("power: init sagt ab") und
# damit mit 0. Auf 21 zu bestehen hiesse, den SCHLECHTEREN der beiden
# Wege zu verlangen. Was zaehlt, ist dass der Lauf ZU ENDE kam und
# nicht in den Zeitablauf (124) oder einen Absturz lief.
if [ "$rc" = 21 ] || [ "$rc" = 0 ]; then
    ok "der Schreiblauf ist durchgelaufen (Code $rc)"
else
    bad "der Schreiblauf endete mit Code $rc"
fi
# NICHT EINFACH NACH DEM WORT SUCHEN -- ES STEHT SCHON IN DER FRAGE.
#
# GEMESSEN (Runde INSTALLER2): `grep hallo-von-der-platte` traf die
# Zeile `mb: flags=... cmd=... script=echo hallo-von-der-platte >...`,
# also die KOMMANDOZEILE, die der Kern beim Start ausgibt. Der Test
# war damit gruen, waehrend das Skript in Wahrheit NIE lief (statt der
# Shell startete init, siehe `initsh` weiter oben) und /beweis.txt nie
# entstand. Ein gruener Haken auf die eigene Frage ist keine Messung.
#
# Also wird die `mb:`-Zeile ausgenommen und zusaetzlich verlangt, dass
# die Shell ueberhaupt gelaufen ist.
if grep -qa 'sh: ready' "$OUT/schreib.txt"; then
    ok "die Shell auf der Platte ist gelaufen"
else
    bad "auf der Platte lief keine Shell -- das Skript wurde nie abgearbeitet"
fi
if grep -va '^mb: ' "$OUT/schreib.txt" | grep -qa 'hallo-von-der-platte'; then
    ok "die Datei wurde angelegt und gelesen"
else
    bad "die Datei liess sich nicht anlegen"
fi

# ==================================================================
titel "7. NEU STARTEN -- und die Datei muss noch da sein"
# ==================================================================
platte_lauf wieder "cat /beweis.txt;exit" 300
rc=$?
# 21 oder 0 -- die Begruendung steht bei Glied 6.
if [ "$rc" = 21 ] || [ "$rc" = 0 ]; then
    ok "der zweite Start ist durchgelaufen (Code $rc)"
else
    bad "der zweite Start endete mit Code $rc"
fi
# Auch hier OHNE die `mb:`-Zeile -- aus demselben Grund wie oben.
if grep -va '^mb: ' "$OUT/wieder.txt" | grep -qa 'hallo-von-der-platte'; then
    ok "DIE DATEI HAT DEN NEUSTART UEBERLEBT -- das ist der Punkt der Runde"
else
    bad "die Datei ist nach dem Neustart weg"
    tail -5 "$OUT/wieder.txt" | sed 's/^/        /'
fi

# ==================================================================
titel "7b. O-009: DER GERAETESCHLUESSEL UEBERLEBT DEN NEUSTART"
# ==================================================================
#
# `O-009` in OFFEN.md: der Geraeteschluessel entsteht beim Koppeln in
# der RAM-Wurzel, also muss nach jedem Neustart neu gekoppelt werden --
# "haengt an P-001". Sobald die Wurzel auf der PLATTE liegt, ist die
# Bedingung erfuellt, und hier wird sie gemessen.
#
# GEMESSEN WIRD DER ECHTE SCHLUESSEL, NICHT EIN PLATZHALTER. Eine
# fruehere Fassung dieser Probe legte 64 Hexziffern von Hand hin und
# las sie wieder -- das belegt den PFAD, aber nicht den AUSWEIS: es
# haette auch dann gehalten, wenn `jsig` den Schluessel bei jedem Start
# neu wuerfelt, und genau das ist der Fehler, um den es in O-009 geht.
#
# DIESER ABSCHNITT LAEUFT NUR, WENN GLIED 5 TRAEGT -- also wenn von
# der Platte gestartet werden kann. Stand 15.09.2026 tut er das auf
# diesem Wirt NICHT: der Installer bekommt sein Fenster nicht auf
# (`wigapp=/bin/installer` -> `init: herunterfahren`, gemessen in
# Glied 1-3), und damit gibt es keine installierte Platte. Das ist
# P-001 und nicht O-009.
#
# DAMIT O-009 TROTZDEM GEMESSEN IST, steht dieselbe Frage noch einmal
# in `tools/geraetekey/run.sh` -- dort mit einer Wurzel auf einer
# IDE-Platte, die ueber zwei Starts dieselbe bleibt, ohne Installer
# und ohne Oberflaeche. Dort ist sie GRUEN (11/0). Sobald P-001 traegt,
# misst der Abschnitt hier dasselbe noch einmal auf dem echten Weg.
#
# Deshalb der volle Lebenslauf, ueber `/bin/jsig`:
#
#   Lauf 1:  `jsig aus`                 legt das Ed25519-Paar an
#            `jsig unterschreibe <hex>` unterschreibt eine Nachricht
#            -> der oeffentliche Teil UND die Unterschrift werden notiert
#   NEUSTART (dieselbe Platte, kein Medium)
#   Lauf 2:  `jsig aus`                 darf KEINEN neuen anlegen
#            -> derselbe oeffentliche Teil
#            `jsig pruefe <pub> <msg> <sig>` -> die ALTE Unterschrift
#               verifiziert weiterhin
#
# DIE GEGENPROBE (Zuruecksetzen): `rm /etc/jarvis/geraet.key`, dann
# `jsig aus` -- jetzt MUSS ein ANDERER oeffentlicher Teil herauskommen.
# Ohne sie waere Lauf 2 auch dann gruen, wenn `jsig` den Schluessel
# ueberhaupt nicht aus der Datei liest.
NACHRICHT=4f2d303039
platte_lauf jarvis1 "mkdir /etc/jarvis;jsig aus;jsig unterschreibe $NACHRICHT;exit" 300
PUB1=$(grep -aoE '^pub [0-9a-f]{64}' "$OUT/jarvis1.txt" | head -1 | awk '{print $2}')
SIG1=$(grep -aoE '^sig [0-9a-f]{128}' "$OUT/jarvis1.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ] && [ -n "$SIG1" ]; then
    ok "Lauf 1: Ed25519-Paar angelegt (pub ${PUB1:0:16}...)"
else
    bad "Lauf 1: jsig hat keinen Schluessel/keine Unterschrift geliefert"
    tail -6 "$OUT/jarvis1.txt" | sed 's/^/        /'
fi

platte_lauf jarvis2 "jsig aus;jsig pruefe $PUB1 $NACHRICHT $SIG1;exit" 300
PUB2=$(grep -aoE '^pub [0-9a-f]{64}' "$OUT/jarvis2.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ] && [ "$PUB2" = "$PUB1" ]; then
    ok "O-009: NACH DEM NEUSTART DERSELBE oeffentliche Teil -- kein zweites Koppeln"
else
    bad "O-009: der Schluessel hat den Neustart nicht ueberlebt (vorher ${PUB1:-?}, nachher ${PUB2:-?})"
    tail -6 "$OUT/jarvis2.txt" | sed 's/^/        /'
fi
if grep -qa '^ja$' "$OUT/jarvis2.txt"; then
    ok "O-009: eine Unterschrift VON VOR dem Neustart verifiziert weiterhin"
else
    bad "O-009: die alte Unterschrift verifiziert nach dem Neustart nicht"
    tail -6 "$OUT/jarvis2.txt" | sed 's/^/        /'
fi

# UND MIT FREMDEN AUGEN. Dass OrientOS seine eigene Unterschrift
# nachrechnet, ist die schwaechere Aussage -- ein Fehler, der in
# `jsig aus` und in `jsig pruefe` gleich steckt, faellt dabei nicht auf.
# `python-cryptography` hat diesen Fehler nicht. Steht es nicht zur
# Verfuegung, wird das GESAGT und nicht stillschweigend uebergangen.
if [ -n "$PUB1" ] && [ -n "$SIG1" ]; then
    if python3 -c 'import cryptography' 2>/dev/null; then
        python3 - "$PUB1" "$SIG1" "$NACHRICHT" > "$OUT/fremd.txt" 2>&1 <<'PYFREMD'
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature
pub = bytes.fromhex(sys.argv[1]); sig = bytes.fromhex(sys.argv[2])
msg = bytes.fromhex(sys.argv[3])
k = Ed25519PublicKey.from_public_bytes(pub)
try:
    k.verify(sig, msg); print("GUT")
except InvalidSignature:
    print("FALSCH")
try:
    k.verify(sig, msg + b"\x01"); print("GEGENPROBE-FALSCH")
except InvalidSignature:
    print("GEGENPROBE-GUT")
PYFREMD
        if grep -qa '^GUT$' "$OUT/fremd.txt"; then
            ok "O-009: fremdes Werkzeug (python-cryptography) rechnet die ueberlebende Unterschrift nach"
        else
            bad "O-009: python-cryptography verwirft die Unterschrift"
            sed 's/^/        /' "$OUT/fremd.txt" | head -4
        fi
        if grep -qa '^GEGENPROBE-GUT$' "$OUT/fremd.txt"; then
            ok "GEGENPROBE: ueber eine andere Nachricht faellt sie durch"
        else
            bad "GEGENPROBE: die Unterschrift passt auch auf eine andere Nachricht"
        fi
    else
        echo "  [ -- ] python-cryptography fehlt: die fremde Gegenrechnung entfaellt"
    fi
fi

# Die Gegenprobe: zuruecksetzen -- und es MUSS ein anderer werden.
platte_lauf jarvis3 "rm /etc/jarvis/geraet.key;jsig aus;exit" 300
PUB3=$(grep -aoE '^pub [0-9a-f]{64}' "$OUT/jarvis3.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB3" ] && [ -n "$PUB1" ] && [ "$PUB3" != "$PUB1" ]; then
    ok "GEGENPROBE: nach dem Zuruecksetzen ist er WEG und ein neuer entsteht (pub ${PUB3:0:16}...)"
else
    bad "GEGENPROBE: nach dem Loeschen kam derselbe Schluessel wieder (${PUB3:-?}) -- dann liest jsig ihn nicht aus der Datei"
    tail -6 "$OUT/jarvis3.txt" | sed 's/^/        /'
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
    if grep -qaE '(osum|wm): mount=1' "$OUT/kaputt.txt"; then
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
