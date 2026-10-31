#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
#
#   bash tools/install/abnahme.sh [ausgabeverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1   # r1223: QEMU -kernel/-initrd has no boot medium; the installer needs /boot/osum.mb in the root
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

rm -f "$ZIEL"
truncate -s "${ZIEL_MIB}M" "$ZIEL"
ok "leere Zielplatte, ${ZIEL_MIB} MiB"

# ==================================================================
titel "1.-3. vom Stick starten, das Fenster zeigen, installieren"
# ==================================================================
#
SOCK="$OUT/mon.sock"
SER="$OUT/stick.txt"
rm -f "$SER" "$SOCK"

#     osum: pid1 init
#     init: ziel=grafik
#     init: dienste=1
#     init: herunterfahren      <- und `k15: start` kam nie
#
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1200 nokbd nosched noproc nofs"
APPEND="$APPEND lang=de uiscale=1 wigapp=/bin/installer,now,account=abnahme,password=geheim123"

timeout 3000 $QEMU_X86 -m 512 \
    -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$SER" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$ZIEL,format=raw,if=ide,index=0" > "$OUT/qemu1.log" 2>&1 &
QP=$!

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

i=0
while [ $i -lt 3000 ]; do
    grep -qa 'installer: done\|installer: ERROR' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 3
schuss "$SOCK" "$SHOTS/30-fertig.png" || true

if grep -qa 'installer: done' "$SER"; then
    ok "die Installation meldet sich fertig"
else
    bad "die Installation ist nicht fertig geworden"
    grep -aE 'installer:' "$SER" | tail -5 | sed 's/^/        /'
fi
esp=$(grep -aoE 'installer: esp=/dev/[a-z0-9]+' "$SER" | head -1 | sed 's/.*esp=//')
if [ "$esp" = "/dev/hda1" ]; then
    ok "die EFI-Partition wurde aus dem Ziel gebaut: $esp"
else
    bad "falsche oder fehlende EFI-Partition: '${esp:-keine}'"
fi
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
INST_DRIVE=${INST_DRIVE:-ahci}
disk_boot_args() { # sets DISKBOOT for the CURRENT $ZIEL
    if [ "$INST_DRIVE" = ahci ]; then
        DISKBOOT=(-device ich9-ahci,id=ahci0 -drive "if=none,id=hd0,file=$ZIEL,format=raw" -device ide-hd,drive=hd0,bus=ahci0.0)
    else
        DISKBOOT=(-drive "file=$ZIEL,format=raw,if=ide,index=0")
    fi
}
OVMF=$(ls /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)
platte_lauf() { # <name> <skript> <limit>
    local name=$1 skript=$2 limit=${3:-300}
    local ser="$OUT/$name.txt" vars="$OUT/$name.vars.fd"
    rm -f "$ser"
    cp -f /usr/share/OVMF/OVMF_VARS.fd "$vars" 2>/dev/null || true
    #
    if [ -z "$skript" ]; then
        local msock="$OUT/mon-platte.sock"
        rm -f "$msock"
        disk_boot_args
        local args0=(-machine pc -cpu max -m 512 -display none -no-reboot
            -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
            -serial "file:$ser"
            -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32
            -monitor "unix:$msock,server,nowait"
            "${DISKBOOT[@]}"
            -device isa-debug-exit,iobase=0xf4,iosize=0x04)
        [ -f "$vars" ] && args0+=(-drive "if=pflash,format=raw,unit=1,file=$vars")
        timeout "$limit" $QEMU_X86 "${args0[@]}" > /dev/null 2>&1 &
        local qp=$!
        local w=0
        while [ $w -lt 240 ]; do
            # wait for the sign-in screen / desktop line too: the taskbar line comes first and a loaded host needs seconds more
            grep -qa 'desk: start /bin/taskbar' "$ser" 2>/dev/null && grep -qaE 'desk: start /bin/(desktop|glogi)' "$ser" 2>/dev/null && break
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
        echo "/${MARKE_PRODUKT}"
        echo "    protocol: multiboot1"
        echo "    path: boot():/osum.mb"
        if [ -n "$skript" ]; then
            #
            #     osum: pid1 init
            #     init: ziel=grafik
            #     init: herunterfahren
            #
            echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3 initsh script=$skript"
        else
            echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3"
        fi
    } > "$OUT/$name.conf"
    mcopy -o -i "$ZIEL@@1048576" "$OUT/$name.conf" ::/limine.conf 2>/dev/null \
        || { echo "mcopy fehlgeschlagen"; return 9; }
    disk_boot_args
    local args=(-machine pc -cpu max -m 512 -display none -no-reboot
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
        -serial "file:$ser"
        "${DISKBOOT[@]}"
        -device isa-debug-exit,iobase=0xf4,iosize=0x04)
    [ -f "$vars" ] && args+=(-drive "if=pflash,format=raw,unit=1,file=$vars")
    timeout "$limit" $QEMU_X86 "${args[@]}" > /dev/null 2>&1
    return $?
}

platte_lauf start "" 400
rc=$?
#
if [ -s "$OUT/start.txt" ]; then
    ok "die Platte startet und laeuft (ein Schreibtisch endet nicht von selbst)"
else
    bad "von der Platte kam keine einzige Zeile (Code $rc)"
fi
if [ -s "$SHOTS/40-von-der-platte.png" ]; then
    t=$(tinte "$SHOTS/40-von-der-platte.png")
    # DAILY-DRIVER (r172): the installed system has no autologin any more, its
    # first picture is the LOGIN SCREEN (little ink: a small dialog on a light
    # screen), the desktop comes after the password -- test 7c types it
    if [ "$t" -ge 2 ]; then
        ok "BILD: der Anmeldeschirm von der Platte (${t} % Tinte)"
    else
        bad "der Schirm von der Platte ist fast leer (${t} % Tinte)"
    fi
else
    bad "kein Bild vom Schreibtisch auf der Platte"
fi
if grep -qaE '(osum|wm): rootpart=|rootsel: (ahci|ide|nvme)[a-z]* -- WURZEL' "$OUT/start.txt"; then
    ok "der Kern findet seine Wurzel auf der Platte: $(grep -aoE 'rootpart=[0-9]+ +first=[0-9]+ +blocks=[0-9]+|rootsel: [a-z]+ -- WURZEL, Bloecke=[0-9]+ +first=[0-9]+' "$OUT/start.txt" | head -1)"
else
    bad "der Kern findet keine Wurzelpartition"
fi
if grep -qaE '(osum|wm): mount=1' "$OUT/start.txt"; then
    ok "die Wurzel ist eingehaengt"
else
    bad "die Wurzel ist nicht eingehaengt"
fi
if grep -qaE 'desk: start /bin/(desktop|glogi)|glogin: (bereit|rect)' "$OUT/start.txt"; then
    ok "die Oberflaeche (Anmeldeschirm bzw. Schreibtisch) startet von der Platte"
else
    bad "kein Schreibtisch -- die Oberflaeche kommt nicht hoch"
fi
grep -qa 'from module' "$OUT/start.txt" \
    && bad "es lief doch ueber ein Boot-Modul -- dann ist nichts bewiesen" \
    || ok "GEGENPROBE: 'from module' kommt nicht vor -- es war kein Stick im Spiel"

# the installer's own limine.conf, kept for step 7c (the next steps overwrite it with scripts)
mcopy -i "$ZIEL@@1048576" ::/limine.conf "$OUT/inst-limine.conf" 2>/dev/null
# r1247: the installer must write `default_entry: 1` (selfupdate: ab.esp_flip / osupdate need the line to arm slot B)
grep -aq '^default_entry: 1' "$OUT/inst-limine.conf" && ok "installed limine.conf carries default_entry: 1 (update-ready)" \
    || bad "installed limine.conf has no default_entry line"

# ==================================================================
titel "6. eine Datei anlegen -- auf der Platte"
# ==================================================================
platte_lauf schreib "echo hallo-von-der-platte >/beweis.txt;cat /beweis.txt;sync;exit" 300
rc=$?
#
if [ "$rc" = 21 ] || [ "$rc" = 0 ]; then
    ok "der Schreiblauf ist durchgelaufen (Code $rc)"
else
    bad "der Schreiblauf endete mit Code $rc"
fi
#
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
if [ "$rc" = 21 ] || [ "$rc" = 0 ]; then
    ok "der zweite Start ist durchgelaufen (Code $rc)"
else
    bad "der zweite Start endete mit Code $rc"
fi
if grep -va '^mb: ' "$OUT/wieder.txt" | grep -qa 'hallo-von-der-platte'; then
    ok "DIE DATEI HAT DEN NEUSTART UEBERLEBT -- das ist der Punkt der Runde"
else
    bad "die Datei ist nach dem Neustart weg"
    tail -5 "$OUT/wieder.txt" | sed 's/^/        /'
fi

# ==================================================================
# ==================================================================
titel "7a. DAS EIGENE KONTO (r172) -- der Installer legt es an"
# ==================================================================
#
platte_lauf konto "echo ==PASSWD;cat /etc/passwd;echo ==SHADOW;cat /etc/shadow;echo ==GROUP;cat /etc/group;echo ==AUTOLOGIN;ls /etc;echo ==USERS;ls /users;echo ==ENDE;exit" 300
rc=$?
if [ "$rc" = 21 ] || [ "$rc" = 0 ]; then
    ok "der Kontolauf ist durchgelaufen (Code $rc)"
else
    bad "der Kontolauf endete mit Code $rc"
fi
python3 - "$OUT/konto.txt" "geheim123" > "$OUT/konto-py.txt" 2>&1 <<'PYEOF2'
import sys, hashlib, binascii, re
raw = open(sys.argv[1], 'rb').read().decode('latin1')
# the serial line also carries the shell's echo and the loader's chatter
raw = '\n'.join(l for l in raw.replace('\r', '').split('\n') if not l.startswith('elf:') and not l.startswith('osum$ ') and not l.startswith('osum:'))
pw = sys.argv[2]
# the guest echoes the script on the kernel command line; take the part after the last "==PASSWD" that is a line of its own
def sect(name, nxt):
    m = re.findall(r'(?m)^==%s\r?\n(.*?)^==%s' % (name, nxt), raw, re.S)
    return m[-1] if m else ''
passwd = sect('PASSWD', 'SHADOW'); shadow = sect('SHADOW', 'GROUP')
group = sect('GROUP', 'AUTOLOGIN'); users = sect('USERS', 'ENDE')
auto = sect('AUTOLOGIN', 'USERS')
names = [l.split(':')[0] for l in passwd.splitlines() if ':' in l]
print("passwd-names", names)
print("ok1" if names == ['root', 'abnahme'] else "bad1 passwd names %r" % names)
row = [l for l in passwd.splitlines() if l.startswith('abnahme:')]
print("ok2" if row and row[0].split(':')[2:4] == ['1000', '1000'] and row[0].split(':')[5] == '/users/abnahme' else "bad2 %r" % row)
sh = {l.split(':')[0]: l.split(':')[1] for l in shadow.splitlines() if ':' in l}
print("ok3" if sh.get('root') == '!' else "bad3 root field %r" % sh.get('root'))
h = sh.get('abnahme', '')
m = re.match(r'^\$osum1\$(\d+)\$([0-9a-f]+)\$([0-9a-f]+)$', h)
def check(p):
    if not m: return False
    dk = hashlib.pbkdf2_hmac('sha256', p.encode(), binascii.unhexlify(m.group(2)), int(m.group(1)), 32)
    return binascii.hexlify(dk).decode() == m.group(3)
print("ok4" if check(pw) else "bad4 hash does not match the password")
print("ok5" if not check('falsch-123') and not check('live') and not check('startkennwort') else "bad5 wrong password accepted")
print("ok6" if 'abnahme' in [l.split(':')[0] for l in group.splitlines() if ':' in l] else "bad6 group")
ut = [t.rstrip('/') for t in users.split()]
print("ok7" if 'abnahme' in ut and 'live' not in ut else "bad7 users %r" % users)
print("ok8" if 'autologin' not in auto.split() and 'passwd' in auto.split() else "bad8 autologin still there or no listing: %r" % auto[:200])
PYEOF2
cat "$OUT/konto-py.txt" | sed 's/^/        /'
grep -q '^ok1' "$OUT/konto-py.txt" && ok "/etc/passwd: genau root und abnahme (die Konten des Sticks sind weg)" || bad "/etc/passwd stimmt nicht"
grep -q '^ok2' "$OUT/konto-py.txt" && ok "abnahme hat uid/gid 1000 und Heimordner /users/abnahme" || bad "uid/gid/Heimordner falsch"
grep -q '^ok3' "$OUT/konto-py.txt" && ok "root ist gesperrt (!)" || bad "root nicht gesperrt"
grep -q '^ok4' "$OUT/konto-py.txt" && ok "der Hash gehoert zum gewaehlten Passwort (PBKDF2, von Python nachgerechnet)" || bad "Hash passt nicht zum Passwort"
grep -q '^ok5' "$OUT/konto-py.txt" && ok "GEGENPROBE: ein falsches Passwort und die Standardpasswoerter live/startkennwort passen NICHT" || bad "ein falsches Passwort passt"
grep -q '^ok6' "$OUT/konto-py.txt" && ok "/etc/group kennt abnahme" || bad "/etc/group ohne abnahme"
grep -q '^ok7' "$OUT/konto-py.txt" && ok "/users/abnahme liegt da, /users/live nicht" || bad "Heimordner falsch"
grep -q '^ok8' "$OUT/konto-py.txt" && ok "kein /etc/autologin auf der installierten Platte" || bad "/etc/autologin liegt noch da"

# ==================================================================
titel "7c. MIT DEM NEUEN KONTO ANMELDEN -- am echten Anmeldeschirm"
# ==================================================================
#
login_lauf() { # name keys...
    local name=$1; shift
    local ser="$OUT/$name.txt" vars="$OUT/$name.vars.fd" msock="$OUT/mon-$name.sock"
    rm -f "$ser" "$msock"
    cp -f /usr/share/OVMF/OVMF_VARS.fd "$vars" 2>/dev/null || true
    # the file the INSTALLER wrote (saved after step 5, before the script runs overwrote it)
    mcopy -o -i "$ZIEL@@1048576" "$OUT/inst-limine.conf" ::/limine.conf 2>/dev/null || true
    disk_boot_args
    local a=(-machine pc -cpu max -m 512 -display none -no-reboot
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
        -serial "file:$ser"
        -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32
        -monitor "unix:$msock,server,nowait"
        "${DISKBOOT[@]}")
    [ -f "$vars" ] && a+=(-drive "if=pflash,format=raw,unit=1,file=$vars")
    timeout 300 $QEMU_X86 "${a[@]}" > /dev/null 2>&1 &
    local qp=$! w=0
    while [ $w -lt 240 ]; do
        grep -qa 'glogin: bereit' "$ser" 2>/dev/null && break
        kill -0 "$qp" 2>/dev/null || break
        sleep 1; w=$((w+1))
    done
    # the login screen is up, but the session services still start behind it: type once the serial line has been
    # quiet for 3 s (at most 60 s), not after a fixed 4 s that a loaded host can overrun
    local q=0 sz0=-1 sz1
    w=0
    while [ $w -lt 60 ] && [ $q -lt 3 ]; do
        sleep 1; w=$((w+1))
        sz1=$(stat -c %s "$ser" 2>/dev/null || echo 0)
        if [ "$sz1" = "$sz0" ]; then q=$((q+1)); else q=0; fi
        sz0=$sz1
    done
    local k
    for k in "$@"; do
        echo "sendkey $k" | socat - "UNIX-CONNECT:$msock" > /dev/null 2>&1
        sleep 0.4
    done
    w=0
    while [ $w -lt 40 ]; do
        grep -qa 'glogin: angemeldet als\|glogin: abgewiesen' "$ser" 2>/dev/null && break
        sleep 1; w=$((w+1))
    done
    sleep 2
    kill "$qp" 2>/dev/null; wait "$qp" 2>/dev/null
}
if command -v socat >/dev/null 2>&1; then
    login_lauf login-ok g e h e i m 1 2 3 ret
    grep -aq 'glogin: bereit' "$OUT/login-ok.txt" && ok "der Anmeldeschirm kommt (kein Autologin auf der installierten Platte)" || bad "kein Anmeldeschirm"
    grep -aq 'glogin: angemeldet als abnahme' "$OUT/login-ok.txt" && ok "Anmeldung mit dem neuen Konto und dem gewaehlten Passwort klappt" || bad "Anmeldung mit dem neuen Konto: $(grep -a 'glogin:' "$OUT/login-ok.txt" | tail -3 | tr '\n' '|')"
    grep -aq 'glogin: uid=1000' "$OUT/login-ok.txt" && ok "die Sitzung laeuft als uid 1000" || bad "uid 1000 fehlt"
    login_lauf login-bad f a l s c h 9 9 9 ret
    grep -aq 'glogin: abgewiesen' "$OUT/login-bad.txt" && ok "GEGENPROBE: ein falsches Passwort wird abgewiesen" || bad "falsches Passwort nicht abgewiesen"
    grep -aq 'glogin: angemeldet als' "$OUT/login-bad.txt" && bad "GEGENPROBE: trotzdem angemeldet" || ok "GEGENPROBE: niemand angemeldet"
else
    echo "   (socat fehlt: 7c uebersprungen)"
fi

titel "7b. O-009: DER GERAETESCHLUESSEL UEBERLEBT DEN NEUSTART"
# ==================================================================
#
NACHRICHT=4f2d303039
platte_lauf jarvis1 "mkdir /etc/jarvis;jsig init;jsig sign $NACHRICHT;exit" 300
PUB1=$(grep -aoE '^pub [0-9a-f]{64}' "$OUT/jarvis1.txt" | head -1 | awk '{print $2}')
SIG1=$(grep -aoE '^sig [0-9a-f]{128}' "$OUT/jarvis1.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ] && [ -n "$SIG1" ]; then
    ok "Lauf 1: Ed25519-Paar angelegt (pub ${PUB1:0:16}...)"
else
    bad "Lauf 1: jsig hat keinen Schluessel/keine Unterschrift geliefert"
    tail -6 "$OUT/jarvis1.txt" | sed 's/^/        /'
fi

platte_lauf jarvis2 "jsig init;jsig verify $PUB1 $NACHRICHT $SIG1;exit" 300
PUB2=$(grep -aoE '^pub [0-9a-f]{64}' "$OUT/jarvis2.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ] && [ "$PUB2" = "$PUB1" ]; then
    ok "O-009: NACH DEM NEUSTART DERSELBE oeffentliche Teil -- kein zweites Koppeln"
else
    bad "O-009: der Schluessel hat den Neustart nicht ueberlebt (vorher ${PUB1:-?}, nachher ${PUB2:-?})"
    tail -6 "$OUT/jarvis2.txt" | sed 's/^/        /'
fi
if grep -qa '^yes$' "$OUT/jarvis2.txt"; then
    ok "O-009: eine Unterschrift VON VOR dem Neustart verifiziert weiterhin"
else
    bad "O-009: die alte Unterschrift verifiziert nach dem Neustart nicht"
    tail -6 "$OUT/jarvis2.txt" | sed 's/^/        /'
fi

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

platte_lauf jarvis3 "rm /etc/jarvis/device.key;jsig init;exit" 300
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
