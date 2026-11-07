#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
#
#   bash tools/install/acceptance.sh [ausgabeverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1   # r1223: QEMU -kernel/-initrd has no boot medium; the installer needs /boot/osum.mb in the root
. tools/lib/qemu.sh

OUT=${1:-/tmp/abnahme}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
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
    echo "   (QUICK: existing $BAU is used)"
else
    bash tools/usbimg/build.sh "$BAU" > "$OUT/bau.log" 2>&1 || {
        tail -20 "$OUT/bau.log"; echo "== the build failed"; exit 1; }
fi
[ -f "$BAU/osum.mb" ] && ok "Kern gebaut ($(stat -c%s "$BAU/osum.mb") Oktette)" \
    || bad "kein Kern"
[ -f "$BAU/root.img" ] && ok "Wurzelabbild gebaut ($(stat -c%s "$BAU/root.img") Oktette)" \
    || bad "kein Wurzelabbild"
bash tools/mkfsfi/mkfs.sh list "$BAU/root.img" 2>/dev/null > "$OUT/liste.txt"
grep -q '^/bin/installer ' "$OUT/liste.txt" \
    && ok "/bin/installer is in the image" || bad "/bin/installer is missing from the image"
grep -q '^/apps/installer.osp/start' "$OUT/liste.txt" \
    && ok "the bundle is in the image (listed in the menu)" || bad "Buendel fehlt"

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
#     init: target=grafik
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
        ok "the installer window is up (frame: ${t} % ink)"
    else
        bad "the screen is almost empty (${t} % ink) -- 20-fenster.png"
    fi
else
    bad "no photo of the window"
fi

n=$(grep -ac 'installer: rect' "$SER" 2>/dev/null || echo 0)
[ "${n:-0}" -ge 5 ] && ok "the window reports $n controls" \
    || bad "only ${n:-0} controls reported"
grep -qa 'installer: disk /dev/hda' "$SER" \
    && ok "the disk was found and listed" \
    || bad "the disk is not in the list"

i=0
while [ $i -lt 3000 ]; do
    grep -qa 'installer: done\|installer: ERROR' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 3
schuss "$SOCK" "$SHOTS/30-fertig.png" || true

if grep -qa 'installer: done' "$SER"; then
    ok "the installation reports done"
else
    bad "the installation did not finish"
    grep -aE 'installer:' "$SER" | tail -5 | sed 's/^/        /'
fi
esp=$(grep -aoE 'installer: esp=/dev/[a-z0-9]+' "$SER" | head -1 | sed 's/.*esp=//')
if [ "$esp" = "/dev/hda1" ]; then
    ok "the EFI partition was built from the target: $esp"
else
    bad "falsche oder fehlende EFI-Partition: '${esp:-keine}'"
fi
st=$(grep -aoE 'installer: step=[0-9]+' "$SER" | sed 's/.*=//' | sort -un | tr '\n' ' ')
echo "        steps on the wire: $st"
case "$st" in *1*2*3*4*5*) ok "all five steps reported" ;;
                        *) bad "not all steps reported: $st" ;; esac

# ==================================================================
titel "4. die Maschine aus"
# ==================================================================
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null
sleep 1
pgrep -f "file=$ZIEL" > /dev/null && bad "a machine is still running on the disk" \
    || ok "the machine is off"

titel "4b. was der Wirt auf der Platte findet"
sgdisk -p "$ZIEL" > "$OUT/gpt.txt" 2>&1
grep -q 'EF00' "$OUT/gpt.txt" && ok "an EFI partition is in the table" \
    || bad "keine EFI-Partition"
grep -qE 'OSUM' "$OUT/gpt.txt" && ok "the root partition is in the table" \
    || bad "keine Wurzelpartition"
mdir -i "$ZIEL@@1048576" ::/EFI/BOOT > "$OUT/esp.txt" 2>&1
grep -qi 'BOOTX64' "$OUT/esp.txt" && ok "the bootloader is on the EFI partition" \
    || bad "kein BOOTX64.EFI"
mdir -i "$ZIEL@@1048576" :: > "$OUT/esp2.txt" 2>&1
grep -qi 'osum' "$OUT/esp2.txt" && ok "the kernel is on the EFI partition" \
    || bad "no kernel on the EFI partition"
grep -qi 'limine' "$OUT/esp2.txt" && ok "the startup file is next to it" \
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
            #     init: target=grafik
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
    ok "the disk boots and runs (a desktop does not end by itself)"
else
    bad "not a single line came from the disk (code $rc)"
fi
if [ -s "$SHOTS/40-von-der-platte.png" ]; then
    t=$(tinte "$SHOTS/40-von-der-platte.png")
    # DAILY-DRIVER (r172): the installed system has no autologin any more, its
    # first picture is the LOGIN SCREEN (little ink: a small dialog on a light
    # screen), the desktop comes after the password -- test 7c types it
    if [ "$t" -ge 2 ]; then
        ok "FRAME: the login screen from the disk (${t} % ink)"
    else
        bad "the screen from the disk is almost empty (${t} % ink)"
    fi
else
    bad "no frame of the desktop on the disk"
fi
if grep -qaE '(osum|wm): rootpart=|rootsel: (ahci|ide|nvme)[a-z]* -- WURZEL' "$OUT/start.txt"; then
    ok "the kernel finds its root on the disk: $(grep -aoE 'rootpart=[0-9]+ +first=[0-9]+ +blocks=[0-9]+|rootsel: [a-z]+ -- WURZEL, Bloecke=[0-9]+ +first=[0-9]+' "$OUT/start.txt" | head -1)"
else
    bad "the kernel finds no root partition"
fi
if grep -qaE '(osum|wm): mount=1' "$OUT/start.txt"; then
    ok "the root is mounted"
else
    bad "the root is not mounted"
fi
if grep -qaE 'desk: start /bin/(desktop|glogi)|glogin: (ready|rect)' "$OUT/start.txt"; then
    ok "the surface (login screen or desktop) starts from the disk"
else
    bad "no desktop -- the surface does not come up"
fi
grep -qa 'from module' "$OUT/start.txt" \
    && bad "it ran through a boot module after all -- then nothing is proven" \
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
    ok "the write run completed (code $rc)"
else
    bad "the write run ended with code $rc"
fi
#
if grep -qa 'sh: ready' "$OUT/schreib.txt"; then
    ok "the shell on the disk ran"
else
    bad "no shell ran on the disk -- the script was never executed"
fi
if grep -va '^mb: ' "$OUT/schreib.txt" | grep -qa 'hallo-von-der-platte'; then
    ok "the file was created and read"
else
    bad "the file could not be created"
fi

# ==================================================================
titel "7. NEU STARTEN -- und die Datei muss noch da sein"
# ==================================================================
platte_lauf wieder "cat /beweis.txt;exit" 300
rc=$?
if [ "$rc" = 21 ] || [ "$rc" = 0 ]; then
    ok "the second boot completed (code $rc)"
else
    bad "the second boot ended with code $rc"
fi
if grep -va '^mb: ' "$OUT/wieder.txt" | grep -qa 'hallo-von-der-platte'; then
    ok "THE FILE SURVIVED THE REBOOT -- that is the point of the round"
else
    bad "the file is gone after the reboot"
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
    ok "the account run completed (code $rc)"
else
    bad "the account run ended with code $rc"
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
grep -q '^ok1' "$OUT/konto-py.txt" && ok "/etc/passwd: exactly root and abnahme (the stick accounts are gone)" || bad "/etc/passwd stimmt nicht"
grep -q '^ok2' "$OUT/konto-py.txt" && ok "abnahme has uid/gid 1000 and home folder /users/abnahme" || bad "uid/gid/Heimordner falsch"
grep -q '^ok3' "$OUT/konto-py.txt" && ok "root is locked (!)" || bad "root not locked"
grep -q '^ok4' "$OUT/konto-py.txt" && ok "the hash belongs to the chosen password (PBKDF2, recomputed by Python)" || bad "hash does not match the password"
grep -q '^ok5' "$OUT/konto-py.txt" && ok "CONTROL: a wrong password and the default passwords live/startkennwort do NOT match" || bad "a wrong password matches"
grep -q '^ok6' "$OUT/konto-py.txt" && ok "/etc/group kennt abnahme" || bad "/etc/group without abnahme"
grep -q '^ok7' "$OUT/konto-py.txt" && ok "/users/abnahme is there, /users/live is not" || bad "Heimordner falsch"
grep -q '^ok8' "$OUT/konto-py.txt" && ok "no /etc/autologin on the installed disk" || bad "/etc/autologin is still there"

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
        grep -qa 'glogin: ready' "$ser" 2>/dev/null && break
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
        grep -qa 'glogin: signed in as\|glogin: rejected' "$ser" 2>/dev/null && break
        sleep 1; w=$((w+1))
    done
    sleep 2
    kill "$qp" 2>/dev/null; wait "$qp" 2>/dev/null
}
if command -v socat >/dev/null 2>&1; then
    login_lauf login-ok g e h e i m 1 2 3 ret
    grep -aq 'glogin: ready' "$OUT/login-ok.txt" && ok "the login screen appears (no autologin on the installed disk)" || bad "kein Anmeldeschirm"
    grep -aq 'glogin: signed in as abnahme' "$OUT/login-ok.txt" && ok "login with the new account and the chosen password works" || bad "login with the new account: $(grep -a 'glogin:' "$OUT/login-ok.txt" | tail -3 | tr '\n' '|')"
    grep -aq 'glogin: uid=1000' "$OUT/login-ok.txt" && ok "the session runs as uid 1000" || bad "uid 1000 fehlt"
    login_lauf login-bad f a l s c h 9 9 9 ret
    grep -aq 'glogin: rejected' "$OUT/login-bad.txt" && ok "CONTROL: a wrong password is rejected" || bad "wrong password not rejected"
    grep -aq 'glogin: signed in as' "$OUT/login-bad.txt" && bad "COUNTER-PROOF: signed in anyway" || ok "COUNTER-PROOF: nobody signed in"
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
    bad "run 1: jsig delivered no key/no signature"
    tail -6 "$OUT/jarvis1.txt" | sed 's/^/        /'
fi

platte_lauf jarvis2 "jsig init;jsig verify $PUB1 $NACHRICHT $SIG1;exit" 300
PUB2=$(grep -aoE '^pub [0-9a-f]{64}' "$OUT/jarvis2.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ] && [ "$PUB2" = "$PUB1" ]; then
    ok "O-009: AFTER THE REBOOT THE SAME public part -- no second pairing"
else
    bad "O-009: the key did not survive the reboot (before ${PUB1:-?}, after ${PUB2:-?})"
    tail -6 "$OUT/jarvis2.txt" | sed 's/^/        /'
fi
if grep -qa '^yes$' "$OUT/jarvis2.txt"; then
    ok "O-009: a signature FROM BEFORE the reboot still verifies"
else
    bad "O-009: the old signature does not verify after the reboot"
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
            ok "O-009: a foreign tool (python-cryptography) recomputes the surviving signature"
        else
            bad "O-009: python-cryptography verwirft die Unterschrift"
            sed 's/^/        /' "$OUT/fremd.txt" | head -4
        fi
        if grep -qa '^GEGENPROBE-GUT$' "$OUT/fremd.txt"; then
            ok "CONTROL: it fails for a different message"
        else
            bad "CONTROL: the signature also fits a different message"
        fi
    else
        echo "  [ -- ] python-cryptography missing: the foreign cross-check is skipped"
    fi
fi

platte_lauf jarvis3 "rm /etc/jarvis/device.key;jsig init;exit" 300
PUB3=$(grep -aoE '^pub [0-9a-f]{64}' "$OUT/jarvis3.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB3" ] && [ -n "$PUB1" ] && [ "$PUB3" != "$PUB1" ]; then
    ok "CONTROL: after the reset it is GONE and a new one appears (pub ${PUB3:0:16}...)"
else
    bad "CONTROL: after deleting, the same key came back (${PUB3:-?}) -- then jsig does not read it from the file"
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
        bad "the broken root was mounted anyway -- the check does not work"
    else
        ok "CONTROL: the broken root is NOT mounted"
    fi
    rm -f "$OUT/kaputt.img"
else
    bad "the first sector of the root is unknown -- control not possible"
fi

# ==================================================================
printf '\n===========================================================\n'
printf 'ABNAHME P-001:  %d gruen, %d rot\n' "$ok" "$bad"
printf 'Bilder: %s\n' "$SHOTS"
printf '===========================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
