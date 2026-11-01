#!/usr/bin/env bash
#
#   bash tools/usbimg/run.sh [arbeitsverzeichnis]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD"
IMGDIR="$TMPD/bau"
IMG="$IMGDIR/osum-usb.img"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }
is() { # was ist soll
    if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2 (erwartet $3)"; fi
}

OVMF_CODE=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd \
         /usr/share/ovmf/OVMF.fd; do
    [ -f "$c" ] && { OVMF_CODE=$c; break; }
done
OVMF_VARS=""
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [ -f "$v" ] && { OVMF_VARS=$v; break; }
done
KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

echo "== 1. build the image =="
if bash tools/usbimg/build.sh "$IMGDIR" > "$TMPD/build.txt" 2>&1; then
    ok "tools/usbimg/build.sh laeuft durch"
    sed 's/^/       /' "$TMPD/build.txt"
else
    bad "the image cannot be built"
    sed 's/^/       /' "$TMPD/build.txt" | tail -20
    echo "USBIMG: $pass bestanden, $fail gescheitert"
    exit 1
fi

echo "== 2. what is really in the file =="
if sgdisk --print "$IMG" > "$TMPD/gpt.txt" 2>&1; then
    grep -q 'EF00' "$TMPD/gpt.txt" && ok "GPT: partition 1 is an EFI partition (EF00)" \
        || bad "no EFI partition in the table"
    n=$(grep -cE '^ +[0-9]+ ' "$TMPD/gpt.txt")
    is "Partitionen in der Tafel" "$n" "2"
else
    bad "sgdisk cannot read the table"
fi
if dd if="$IMG" bs=512 count=4 status=none | grep -qa 'LIMINE'; then
    ok "the BIOS boot part of Limine is in the MBR area"
else
    bad "no Limine in the MBR area"
fi
for f in ::/EFI/BOOT/BOOTX64.EFI ::/limine.conf ::/osum.mb ::/root.img \
         ::/limine-bios.sys; do
    if mdir -i "$IMGDIR/esp.img" "$f" >/dev/null 2>&1; then
        ok "$f is on the EFI partition"
    else
        bad "$f is missing from the EFI partition"
    fi
done

echo "== 3. echte Umlaute in locale/de/messages =="
u=$(grep -cP '[äöüßÄÖÜ]' locale/de/messages)
if [ "${u:-0}" -gt 0 ]; then
    ok "locale/de/messages: $u lines with real UTF-8 umlauts"
else
    bad "locale/de/messages enthaelt keinen einzigen echten Umlaut"
fi
umschrift=$(awk -F' = ' '/^[a-z][a-z0-9._]* = /{print $2}' locale/de/messages \
    | grep -ocP '\b(aendern|Groesse|groesse|fuer|schliessen|Uebernehmen|Aufloesung|laesst|liess|Oeffnen|Loeschen)\b' || true)
is "ASCII-Umschriften im angezeigten deutschen Text" "${umschrift:-0}" "0"
zeichen=$(python3 -c '
import sys
d = open("locale/de/messages", encoding="utf-8").read()
# every non-ASCII character counts: 2 octets for umlauts, 3 for the typographic quotes
u = sum(len(c.encode("utf-8")) - 1 for c in d if ord(c) > 127)
print("%d %d %d" % (u, len(d), len(d.encode("utf-8"))))
')
set -- $zeichen
if [ "$3" -eq $(( $2 + $1 )) ]; then
    ok "Oktettrechnung stimmt: $1 Zusatzoktette, $2 Zeichen, $3 Oktette ($2 + $1)"
else
    bad "octet count: $2 characters, $3 octets, $1 extra octets -- does not add up"
fi

# ------------------------------------------------------------- Laeufe

lauf() { # name zusatzargumente...
    #
    local name=$1; shift
    local out="$TMPD/$name.txt"
    cp -f "$IMG" "$TMPD/$name.img"
    rm -f "$out"
    # A-038 (24.09.2026): THE DIAGNOSIS ENTRY IS PUT INTO THE COPY, NOT
    # TYPED. Seven `sendkey down` after "the serial file has been quiet
    # for a second" went into nothing under load: the desktop entry ran,
    # and the UEFI run reported "erkannte Firmware: ?" on main and on the
    # branch alike. The copy of the stick gets a limine.conf with exactly
    # the entry from the shipped file -- same kernel, same words -- as
    # its only entry, timeout 0. The stick itself stays untouched.
    diag_conf "$TMPD/$name.img" || bad "$name: diagnostic entry not written into the copy"
    local mon="$TMPD/$name.mon"
    rm -f "$mon"
    timeout 200 qemu-system-x86_64 "${KVM[@]}" -m 2048 \
        -drive "file=$TMPD/$name.img,format=raw,if=none,id=stick" \
        "$@" \
        -serial "file:$out" -display none -no-reboot \
        -monitor "unix:$mon,server,nowait" \
        > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1000 ]; do
        grep -qa 'ENDE DER DIAGNOSE' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    sleep 0.5
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}

lauf_direkt() { # name kommandozeile zusatzargumente...
    local name=$1 cmd=$2; shift 2
    local out="$TMPD/$name.txt"
    rm -f "$out"
    timeout 200 qemu-system-x86_64 "${KVM[@]}" -m 512 -nodefaults -device VGA \
        -kernel "$IMGDIR/osum.mb" -append "$cmd" -net none "$@" \
        -serial "file:$out" -display none -no-reboot \
        > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1000 ]; do
        grep -qa 'ENDE DER DIAGNOSE' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    i=0
    while [ $i -lt 25 ]; do
        grep -qa 'ANGEHALTEN' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    sleep 0.5
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}

# The ESP starts at sector 2048 (build.sh: sgdisk --new=1:2048:...).
diag_conf() { # img
    local img=$1 off=$((2048 * 512)) c="$TMPD/diag.conf"
    mcopy -o -i "$img@@$off" ::/limine.conf "$c.orig" >/dev/null 2>&1 || return 1
    python3 - "$c.orig" "$c" <<'PY' || return 1
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = None
for i, l in enumerate(lines):
    if l.startswith("/") and not l.startswith("//") and "Hardware diagnostics" in l:
        start = i
        break
if start is None:
    sys.exit(1)
end = len(lines)
for j in range(start + 1, len(lines)):
    if lines[j].startswith("/"):
        end = j
        break
block = lines[start:end]
if not any("hwdiag hwdiagstop" in l for l in block):
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(
    "timeout: 0\ndefault_entry: 1\n\n" + "\n".join(block) + "\n")
PY
    mcopy -o -i "$img@@$off" "$c" ::/limine.conf >/dev/null 2>&1 || return 1
    mcopy -o -i "$img@@$off" "$c" ::/boot/limine.conf >/dev/null 2>&1 || return 1
}

warte_auf() { # datei muster sekunden
    local i=0
    while [ $i -lt $(( ${3:-60} * 5 )) ]; do
        grep -qa "$2" "$1" 2>/dev/null && return 0
        sleep 0.2; i=$((i + 1))
    done
    return 1
}

echo "== 4. BIOS: the same file, the way via the MBR =="
lauf bios -device ide-hd,drive=stick
if grep -qa 'firn kernel' "$TMPD/bios.txt"; then
    ok "the kernel boots from the image under BIOS"
else
    bad "the kernel does not boot under BIOS"
    tail -20 "$TMPD/bios.txt" | sed 's/^/       /'
fi
for m in 'hwdiag: firmware=' 'hwdiag: cpu vendor=' 'hwdiag: pci devices=' \
         'hwdiag: fb '; do
    grep -qa "$m" "$TMPD/bios.txt" && ok "BIOS: der Bericht enthaelt '$m'" \
        || bad "BIOS: '$m' fehlt im Bericht"
done
fw=$(grep -aoE 'firmware=(BIOS|UEFI)' "$TMPD/bios.txt" | head -1 | sed 's/.*=//')
is "BIOS-Lauf: erkannte Firmware" "${fw:-?}" "BIOS"
if grep -qa 'ANGEHALTEN' "$TMPD/bios.txt"; then
    ok "the diagnostic entry halts instead of powering off"
else
    bad "the diagnostic entry does not halt"
fi
if grep -qa 'kernel: done' "$TMPD/bios.txt"; then
    bad "CONTROL: the run went through to the end despite hwdiagstop"
else
    ok "CONTROL: after halting no 'kernel: done' mehr"
fi

echo "== 5. UEFI: the same file, the way via BOOTX64.EFI =="
if [ -n "$OVMF_CODE" ]; then
    cp -f "$OVMF_VARS" "$TMPD/vars.fd" 2>/dev/null
    lauf uefi -device ide-hd,drive=stick \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$TMPD/vars.fd"
    if grep -qa 'firn kernel' "$TMPD/uefi.txt"; then
        ok "the same kernel boots under UEFI (OVMF)"
    else
        bad "the kernel does not boot under UEFI"
        tail -25 "$TMPD/uefi.txt" | sed 's/^/       /'
    fi
    grep -qa 'Cannot use text mode with UEFI' "$TMPD/uefi.txt" \
        && bad "the loader demands a text mode -- bit 2 in the multiboot header is missing" \
        || ok "kein 'Cannot use text mode with UEFI' -- der Rahmenpuffer kommt von der Firmware"
    fwu=$(grep -aoE 'firmware=(BIOS|UEFI)' "$TMPD/uefi.txt" | head -1 | sed 's/.*=//')
    is "UEFI-Lauf: erkannte Firmware" "${fwu:-?}" "UEFI"
    src=$(grep -aoE 'hwdiag: fb [0-9]+x[0-9]+' "$TMPD/uefi.txt" | head -1)
    [ -n "$src" ] && ok "UEFI: the firmware set a framebuffer ($src)" \
        || bad "UEFI: no framebuffer in the report"
else
    bad "OVMF is not on this machine -- the UEFI run is skipped"
fi

echo "== 6. Gegenprobe: anderer Plattencontroller, andere Netzkarte =="
lauf ahci -device ahci,id=ahci0 -device ide-hd,bus=ahci0.0,drive=stick \
     -device e1000,netdev=n0 -netdev user,id=n0
if grep -qa 'hwdiag: disk AHCI' "$TMPD/ahci.txt"; then
    ok "with -device ahci the diagnostics report AHCI"
else
    bad "with -device ahci the diagnostics report no AHCI"
    grep -a 'hwdiag: disk' "$TMPD/ahci.txt" | sed 's/^/       /'
fi
if grep -qa 'hwdiag: disk IDE' "$TMPD/bios.txt"; then
    ok "CONTROL: the same report with -device ide-hd still reported IDE"
else
    bad "CONTROL: the IDE run reported no IDE -- the line is a constant"
fi
if grep -qa 'netdev: c0=e1000' "$TMPD/ahci.txt"; then
    ok "netdev picks the e1000 driver for the Intel card"
else
    bad "netdev does not name the driver of the Intel card"
    grep -a 'netdev:' "$TMPD/ahci.txt" | sed 's/^/       /'
fi

lauf virtio -device ide-hd,drive=stick \
     -device virtio-net-pci,netdev=n0 -netdev user,id=n0
if grep -qa 'netdev: c0=virtio-net' "$TMPD/virtio.txt"; then
    ok "and the virtio driver for the virtio card -- two cards, two answers"
else
    bad "netdev does not name virtio-net for virtio"
    grep -a 'netdev:' "$TMPD/virtio.txt" | sed 's/^/       /'
fi
#
lauf fremd -device ide-hd,drive=stick \
     -device ne2k_pci,netdev=n0 -netdev user,id=n0
if grep -qa 'netdev: no driver for' "$TMPD/fremd.txt"; then
    ok "a foreign card (ne2k_pci) is reported as 'no driver for' gemeldet: $(grep -ao 'no driver for.*' "$TMPD/fremd.txt" | head -1)"
else
    bad "a foreign card is not reported as 'no driver for' gemeldet"
    grep -a 'netdev:' "$TMPD/fremd.txt" | sed 's/^/       /'
fi
if grep -qa 'RTL8029 (ne2000)' "$TMPD/fremd.txt"; then
    ok "and it is named by NAME, not only by number"
else
    bad "the foreign card is not named by name"
fi
lauf gefahren -device ide-hd,drive=stick \
     -device rtl8139,netdev=n0 -netdev user,id=n0
if grep -qa 'netdev: c0=r8169' "$TMPD/gefahren.txt"; then
    ok "CONTROL: the same rtl8139 is DRIVEN as r8169, so it is no longer a foreign card"
else
    bad "CONTROL: the rtl8139 is not driven as r8169"
    grep -a 'netdev:' "$TMPD/gefahren.txt" | sed 's/^/       /'
fi
if grep -qa 'ANGEHALTEN' "$TMPD/fremd.txt"; then
    ok "and the kernel runs to the end of the report after the unknown card"
else
    bad "the kernel no longer reaches the end after the unknown card"
fi

echo "== 7. no disk, no card -- and still a report =="
#
lauf_direkt leer "hwdiag hwdiagstop gfx nopci nokbd nosched noproc nofs noring3"
if grep -qa 'hwdiag: pci=NO DEVICE' "$TMPD/leer.txt"; then
    ok "without a bus the report says so instead of hanging silently"
else
    bad "without a bus the message is missing"
    grep -a 'hwdiag: pci' "$TMPD/leer.txt" | sed 's/^/       /' | head -3
fi
if grep -qa 'hwdiag: disk=NONE' "$TMPD/leer.txt"; then
    ok "and likewise without a disk controller"
else
    bad "without a disk controller the message is missing"
    grep -a 'hwdiag: disk' "$TMPD/leer.txt" | sed 's/^/       /'
fi
if grep -qa 'hwdiag: net=NO CARD' "$TMPD/leer.txt"; then
    ok "and without a network card too"
else
    bad "without a network card the message is missing"
    grep -a 'hwdiag: net' "$TMPD/leer.txt" | sed 's/^/       /'
fi
if grep -qa 'ANGEHALTEN' "$TMPD/leer.txt"; then
    ok "and the report is complete anyway"
else
    bad "the report aborts when nothing is found"
fi
lauf_direkt mitbus "hwdiag hwdiagstop gfx nokbd nosched noproc nofs noring3"
if grep -qa 'hwdiag: disk IDE' "$TMPD/mitbus.txt"; then
    ok "GEGENPROBE: dieselbe Maschine MIT Bus meldet ihren IDE-Controller"
else
    bad "CONTROL: the machine with a bus reports no controller"
    grep -a 'hwdiag: disk' "$TMPD/mitbus.txt" | sed 's/^/       /'
fi
if grep -qa 'hwdiag: net=NO CARD' "$TMPD/mitbus.txt"; then
    ok "and without a network card (but with a bus) it says that too"
else
    bad "the machine without a network card does not report it"
fi

echo "== 8. the desktop, in German, with umlauts in the FRAME =="
#
DESKARGS="modfs osum gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs lang=de"
rm -f "$TMPD/desk.txt" "$TMPD/desk.ppm" "$TMPD/desk.sock"
# A-038: the SEARCH opens with the Windows key alone. `meta_l-a` has
# opened the control centre since the quick-settings round (Windows 11
# does the same), and this section photographed the wrong panel.
printf 'warte 5\nsendkey a\nwarte 2\nsendkey meta_l\nwarte 3\n' > "$TMPD/drive"
printf 'sendkey meta_l\nwarte 2\nsendkey meta_l-a\nwarte 3\n' > "$TMPD/drive2"
timeout 240 qemu-system-x86_64 "${KVM[@]}" -m 512 \
    -kernel "$IMGDIR/osum.mb" -initrd "$IMGDIR/root.img" \
    -append "$DESKARGS" \
    -serial "file:$TMPD/desk.txt" -display none -no-reboot -vga std \
    -monitor "unix:$TMPD/desk.sock,server,nowait" \
    > "$TMPD/desk.qemu" 2>&1 &
qpid=$!
warte_auf "$TMPD/desk.txt" '^wm: hold' 120
python3 tools/wm/monitor.py "$TMPD/desk.sock" "$TMPD/drive" 0.12 \
    > "$TMPD/mon.log" 2>&1
sleep 2
python3 tools/gfx/screenshot.py "$TMPD/desk.sock" "$TMPD/desk.ppm" 30 \
    > "$TMPD/shot.txt" 2>&1
# the second picture: search closed, control centre open
python3 tools/wm/monitor.py "$TMPD/desk.sock" "$TMPD/drive2" 0.12 \
    >> "$TMPD/mon.log" 2>&1
sleep 2
python3 tools/gfx/screenshot.py "$TMPD/desk.sock" "$TMPD/desk2.ppm" 30 \
    >> "$TMPD/shot.txt" 2>&1
kill "$qpid" 2>/dev/null; wait "$qpid" 2>/dev/null

if grep -qa 'osum: from module' "$TMPD/desk.txt"; then
    ok "the root comes from the boot module -- no disk driver needed"
else
    bad "the root does not come from the module"
    grep -a 'osum:' "$TMPD/desk.txt" | sed 's/^/       /' | head -5
fi
if grep -qa 'glyphs=' "$TMPD/desk.txt"; then
    ok "the fonts come from the image: $(grep -aoE 'glyphs=[0-9]+' "$TMPD/desk.txt" | head -1)"
else
    bad "no font loaded"
fi
# r145: THE SOCIAL LAYER IS ON THE STICK -- the session (kgui.desk_start) starts the
# service and the Melder when /bin/social exists, and says so on the serial line.
if grep -qaE 'desk: social pid=[1-9]' "$TMPD/desk.txt" && grep -qaE 'desk: melder pid=[1-9]' "$TMPD/desk.txt"; then
    ok "the session starts the social service and notifier ($(grep -aoE 'desk: (social|melder) pid=[0-9]+' "$TMPD/desk.txt" | tr '\n' ' '))"
else
    bad "kein 'desk: social pid=' / 'desk: melder pid=' -- social + melder fehlen im Abbild"
fi
grep -qaE 'desk: (social|melder) (ended|respawn)' "$TMPD/desk.txt" \
    && bad "social service or notifier ends right after the start" \
    || ok "social service and notifier run (no end, no restart during the run)"
if grep -qa 'launcher: name' "$TMPD/desk.txt"; then
    if grep -qa 'launcher: name \[Suchen\]' "$TMPD/desk.txt"; then
        ok "the starter calls itself 'Suchen' -- deutsch, aus /usr/share/locale/de"
    else
        bad "the starter is not German: $(grep -a 'launcher: name' "$TMPD/desk.txt" | tail -1)"
    fi
fi

if [ -s "$TMPD/desk.ppm" ]; then
    ok "a screenshot was taken ($(stat -c%s "$TMPD/desk.ppm") Oktette)"
    finde() { # was text [--nicht]
        local was=$1 text=$2; shift 2
        local aus rc
        aus=$(python3 tools/usbimg/searchtext.py "${BILD:-$TMPD/desk.ppm}" \
              fui:assets/osum-sans.ttf 15 "$text" "$@" 2>&1)
        rc=$?
        if [ $rc = 0 ]; then ok "$was: $aus"; else bad "$was: $aus"; fi
    }
    finde "DER UMLAUT STEHT IM BILD" "Ausführen"
    finde "GEGENPROBE: die ASCII-Ersatzschreibung steht NICHT da" \
          "Ausfuehren" --nicht
    finde "GEGENPROBE: und der englische Text auch nicht" "Run" --nicht
    finde "der deutsche Aufforderungstext des Starters" "Programm suchen:"
    BILD="$TMPD/desk2.ppm" finde "und das Kontrollzentrum ist ebenfalls deutsch" "Dunkelmodus"
    BILD="$TMPD/desk2.ppm" finde "GEGENPROBE: dort steht nicht das englische Wort" "Dark mode" --nicht
    python3 -c "
from PIL import Image
Image.open('$TMPD/desk.ppm').save('$TMPD/desk.png')
" 2>/dev/null && ok "and is at $TMPD/desk.png"
else
    bad "kein Bildschirmfoto"
    tail -10 "$TMPD/shot.txt" | sed 's/^/       /'
fi

echo
echo "USBIMG: $pass bestanden, $fail gescheitert"
echo "        Abbild:     $IMG"
echo "        Foto:       $TMPD/desk.png"
[ "$fail" = 0 ]
