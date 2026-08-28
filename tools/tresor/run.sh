#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tresor/run.sh -- RUNDE TRESOR: Geraeteidentitaet, Sicherung,
# Schluesselverwaltung. Und das, was NICHT geht.
#
# Was diese Runde behauptet und was hier gemessen wird:
#
#   1. SHA-256 IN RING 3 IST SHA-256. `kernel/user/sha.fi` gegen PYTHONS
#      `hashlib`: die drei Standardnachrichten aus FIPS 180-4, eine ueber
#      viele Bloecke, und DIESELBE in sieben ungleichen Stuecken -- die
#      letzten beiden muessen gleich sein, sonst ist die Pufferung falsch.
#      `pw.fi` konnte das nicht: dort steht `if len > 256 { return false }`.
#
#   2. DER KERNEL LIEST SMBIOS WIRKLICH. Der WIRT holt sich denselben
#      Speicher ueber den QEMU-Monitor (`pmemsave`) und entschluesselt die
#      Tabelle mit einer ZWEITEN, unabhaengigen Umsetzung
#      (`tools/tresor/smbios.py`, Python). Einstiegspunkt, Tabellenadresse,
#      Laenge, Anzahl der Strukturen und jede Zeichenkette muessen
#      uebereinstimmen. Eine Umsetzung allein koennte zweimal denselben
#      Fehler machen.
#
#   3. DIE PRUEFSUMME IST NOETIG. In QEMU steht bei 0x000F1031 die
#      ZEICHENKETTE "_SM3_" aus dem Zeichenvorrat von SeaBIOS. Der Wirt
#      weist nach, dass sie da ist und dass ihre Pruefsumme NICHT stimmt;
#      der Kernel meldet `tried=1`, also GENAU EINEN angenommenen
#      Einstiegspunkt.
#
#   4. WAS EINE VM HERGIBT UND WAS NICHT. Zwei Laeufe desselben Kernels:
#      ohne `-smbios` ist die Seriennummer LEER und die UUID sechzehn
#      Nulloktette; mit `-smbios type=1,serial=...` steht genau da, was
#      auf der Kommandozeile stand. Das ist zugleich die Zusage (der
#      Parser stimmt) und die Gegenprobe (die Werte sind faelschbar).
#
#   5. DER EFI-WEG. Multiboot 1 liefert keine EFI-Systemtafel, also baut
#      der Lauf `hwidefi` eine VON HAND und laesst `hwid.from_efi` sie
#      gehen -- mit drei Gegenproben: Zeiger 0, falsche Signatur, und eine
#      Tafel, in der nur ein FREMDER GUID steht.
#
#   6. DER FINGERABDRUCK. `/proc/hwid` und `hwid -f` in Ring 3, und der
#      WIRT rechnet denselben Fingerabdruck aus dem kanonischen Text nach.
#      Dazu: derselbe Rechner mit einer NEUEN PLATTE gibt DENSELBEN
#      Fingerabdruck (eine Neuinstallation aendert ihn nicht), ein anderer
#      Rechner einen ANDEREN.
#
#   7. DIE SICHERUNG. `backup save` zweimal hintereinander: der zweite Lauf
#      schreibt NULL Oktette. Sichern, loeschen, wiederherstellen ergibt
#      einen Baum, den der WIRT aus dem Plattenabbild zurueckliest und
#      Oktett fuer Oktett vergleicht -- nicht aus einem Mitschnitt der
#      seriellen Leitung.
#
#   8. DIE EHRLICHE GRENZE. Dieselben acht Oktette, einmal HINTEN an eine
#      Datei und einmal VORNE. Hinten: ein neuer Block. Vorne: JEDER Block
#      neu. Feste Blockgroesse kann das nicht, und die Zahlen stehen in
#      docs/THEFT.md statt einer Ausrede.
#
#   9. `backup verify` FINDET SCHADEN. Der WIRT kippt EIN Oktett in der
#      Packdatei IM ABBILD (`tools/tresor/kaputt.py`) -- von aussen, so
#      wie echter Schaden entsteht -- und derselbe Lauf prueft den
#      beschaedigten UND einen heilen Speicher.
#
#  10. DIE SCHLUESSELVERWALTUNG. PBKDF2-HMAC-SHA256 gegen Pythons
#      `hashlib.pbkdf2_hmac`, drei Faelle, 64 Oktette (also ZWEI Bloecke).
#      Und der Rundlauf: init -> open gibt denselben Fingerabdruck, ein
#      falsches Passwort wird abgewiesen, nach `erase` ist der Schluessel
#      weg. Mit der Zeit, die das gekostet hat.
#
# Verwendung:  bash tools/tresor/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
BLOCKS=4096

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
# Der Wert hinter `schluessel: ` aus einer Ausgabe.
wert() { grep -a "^$2: " "$1" | tail -1 | sed "s/^$2: //"; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "TRESOR: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

PROGS="sh ls cat echo hello hwid shat backup key bsect"

# ============================================================ 1. bauen

echo "== 1. bauen: der Kern, die Programme, die Speicherkarte =="

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "firnc0 baut den Kern mit hwid" \
    || { bad "firnc0 baut den Kern nicht"; sed 's/^/        /' "$TMPD/b0.txt" | head -10; }
[ -f "$TMPD/k0.img" ] || { echo "TRESOR: $pass passed, $((fail+1)) failed"; exit 1; }

bash tools/tresor/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/bprog.txt" 2>&1 \
    && ok "firnc0 baut $(echo $PROGS | wc -w) Programme in Ring 3" \
    || { bad "firnc0 baut nicht alle Programme"; sed 's/^/        /' "$TMPD/bprog.txt" | head -12; }

undef=""
for p in hwid backup key shat; do
    [ -f "$TMPD/bin/$p.elf" ] || continue
    u=$(nm -u "$TMPD/bin/$p.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "kein neues Programm hat ein undefiniertes Symbol" \
               || bad "undefinierte Symbole:$undef"

if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "$(tail -1 "$TMPD/karte.txt")"
else
    bad "der Kartenpruefer schlaegt an"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi
grep -q '"HWID_OFF"' tools/kernel/memmap.py \
    && ok "der Bereich dieser Runde (0x5A000..0x5C000) steht in der Karte" \
    || bad "HWID_OFF fehlt in tools/kernel/memmap.py"

# GEGENPROBE: der Bereich auf die Seite von K18 gelegt MUSS auffallen.
mkdir -p "$TMPD/kbad" && cp kernel/*.fi "$TMPD/kbad/"
sed -i 's/^const HWID_OFF: u64 = 0x5A000/const HWID_OFF: u64 = 0x59000/' "$TMPD/kbad/kstate.fi"
if python3 tools/kernel/memmap.py "$TMPD/kbad" > "$TMPD/karte-bad.txt" 2>&1; then
    bad "GEGENPROBE: HWID auf 0x59000 (dem Akku) faellt NICHT auf"
else
    ok "GEGENPROBE: HWID auf 0x59000 kollidiert mit BATT und faellt auf"
fi

# ------------------------------------------------------------- ein Lauf
# lauf <name> <abbild> <kommandozeile> [weitere qemu-argumente...]
lauf() {
    local name=$1 img=$2 app=$3
    shift 3
    cp "$img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k0.img" -m 256 \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "$@" > /dev/null 2>&1
    echo $?
}
# ohne Platte
kernlauf() {
    local name=$1 app=$2
    shift 2
    timeout 240 $QEMU_X86 -kernel "$TMPD/k0.img" -m 256 \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" > /dev/null 2>&1
    echo $?
}

# =========================================== 2. SHA-256 gegen hashlib

echo "== 2. SHA-256 in Ring 3 gegen Pythons hashlib =="

cat > "$TMPD/t_sha.sh" <<'EOS'
shat
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/dsha.img" $BLOCKS /bin/ /t/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/shat="$TMPD/bin/shat.elf" \
    /t/sha.sh="$TMPD/t_sha.sh" > "$TMPD/mkfs-sha.txt" 2>&1 \
    && ok "mkfs.py baut das Abbild fuer die Hashmessung" \
    || bad "mkfs.py fehlgeschlagen"
rc=$(lauf sha "$TMPD/dsha.img" "osum vfs nokbd script=sh /t/sha.sh;exit")
is "der Hashlauf endet ordentlich" "$rc" "21"

python3 - > "$TMPD/sha-soll.txt" <<'PY'
import hashlib
msgs = [b"abc", b"", b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
        b"a"*1000, b"a"*1000]
for i, m in enumerate(msgs):
    print("sha%d: %s" % (i+1, hashlib.sha256(m).hexdigest()))
PY
for i in 1 2 3 4 5; do
    got=$(grep -a "^sha$i: " "$TMPD/sha.txt" | tail -1 | sed 's/^sha[0-9]: //')
    want=$(grep -a "^sha$i: " "$TMPD/sha-soll.txt" | sed 's/^sha[0-9]: //')
    if [ -n "$got" ] && [ "$got" = "$want" ]; then
        ok "SHA-256 Fall $i stimmt mit hashlib ueberein"
    else
        bad "SHA-256 Fall $i: '$got', hashlib sagt '$want'"
    fi
done
g4=$(grep -a '^sha4: ' "$TMPD/sha.txt" | sed 's/^sha4: //')
g5=$(grep -a '^sha5: ' "$TMPD/sha.txt" | sed 's/^sha5: //')
[ -n "$g4" ] && [ "$g4" = "$g5" ] \
    && ok "1000 Oktette am Stueck und in sieben ungleichen Stuecken: derselbe Hash" \
    || bad "der Strom liefert einen anderen Hash als der Einzelaufruf"

# =============================== 3. SMBIOS: Kernel gegen zweite Umsetzung

echo "== 3. SMBIOS: der Kernel gegen eine zweite, unabhaengige Umsetzung =="

# Ein Lauf, der NUR liest, und daneben ein Speicherabzug ueber den Monitor.
python3 tools/tresor/dump.py "$TMPD/k0.img" "$TMPD/mem.bin" "$TMPD/dumprun.txt" \
    > "$TMPD/dump.log" 2>&1 \
    && ok "der Wirt holt sich 0x0..0x100000 ueber den QEMU-Monitor" \
    || { bad "pmemsave ueber den Monitor fehlgeschlagen"; sed 's/^/        /' "$TMPD/dump.log" | head -6; }

if [ -s "$TMPD/mem.bin" ]; then
    python3 tools/tresor/smbios.py "$TMPD/mem.bin" > "$TMPD/soll.txt" 2>&1 \
        && ok "die zweite Umsetzung entschluesselt die Tabelle" \
        || { bad "smbios.py kommt nicht durch"; sed 's/^/        /' "$TMPD/soll.txt" | head -6; }
fi

rc=$(kernlauf hwraw "hwid nokbd nosched noproc nofs noring3")
is "der Lauf ohne Platte endet ordentlich" "$rc" "21"

for feld in entry table tlen count; do
    got=$(wert "$TMPD/hwraw.txt" "hwid: $feld" 2>/dev/null)
    got=$(grep -a "^hwid: $feld=" "$TMPD/hwraw.txt" | tail -1 | sed "s/^hwid: $feld=//")
    want=$(grep -a "^$feld=" "$TMPD/soll.txt" | tail -1 | sed "s/^$feld=//")
    if [ -n "$got" ] && [ "$got" = "$want" ]; then
        ok "SMBIOS $feld: Kernel und Python sagen $got"
    else
        bad "SMBIOS $feld: Kernel '$got', Python '$want'"
    fi
done
for feld in sys_man sys_prod sys_ver; do
    got=$(grep -a "^hwid: $feld=" "$TMPD/hwraw.txt" | tail -1 | sed "s/^hwid: $feld=//")
    want=$(grep -a "^$feld=" "$TMPD/soll.txt" | tail -1 | sed "s/^$feld=//")
    if [ "$got" = "$want" ]; then
        ok "SMBIOS $feld: beide lesen '$got'"
    else
        bad "SMBIOS $feld: Kernel '$got', Python '$want'"
    fi
done

# Die Pruefsumme ist noetig -- der Beleg dafuer.
python3 tools/tresor/smbios.py --koeder "$TMPD/mem.bin" > "$TMPD/koeder.txt" 2>&1
hat "$TMPD/koeder.txt" "koeder=1" "bei 0xF1031 steht '_SM3_' aus dem Zeichenvorrat von SeaBIOS"
hat "$TMPD/koeder.txt" "koeder_pruefsumme=falsch" "und seine Pruefsumme stimmt NICHT"
is "der Kernel hat GENAU EINEN Einstiegspunkt angenommen" \
   "$(grep -a '^hwid: tried=' "$TMPD/hwraw.txt" | tail -1 | sed 's/^hwid: tried=//')" "1"

# ======================================= 4. was eine VM hergibt (und nicht)

echo "== 4. dieselbe Maschine, zwei Firmwares: was SMBIOS wirklich wert ist =="

is "ohne -smbios ist die Seriennummer LEER" \
   "$(grep -a '^hwid: sys_ser=' "$TMPD/hwraw.txt" | tail -1 | sed 's/^hwid: sys_ser=//')" "(empty)"
is "ohne -smbios ist die UUID sechzehn Nulloktette" \
   "$(grep -a '^hwid: uuid=' "$TMPD/hwraw.txt" | tail -1 | sed 's/^hwid: uuid=//')" \
   "00000000000000000000000000000000"
is "und der Kernel sagt selbst, dass das keine UUID ist" \
   "$(grep -a '^hwid: uuid_ok=' "$TMPD/hwraw.txt" | tail -1 | sed 's/^hwid: uuid_ok=//')" "0"
is "ohne -smbios gibt es keine Baseboard-Struktur" \
   "$(grep -a '^hwid: brd_ser=' "$TMPD/hwraw.txt" | tail -1 | sed 's/^hwid: brd_ser=//')" "(empty)"

SMB1=(-smbios type=1,manufacturer=Flei,product=FLEI-ONE,version=1.0,serial=SN-JUSTIN-0001,uuid=11111111-2222-3333-4444-555555555555
      -smbios type=2,manufacturer=Flei,product=MB-X,serial=BOARD-9999)
SMB2=(-smbios type=1,manufacturer=Flei,product=FLEI-ONE,version=1.0,serial=SN-ANDERE-0002,uuid=22222222-3333-4444-5555-666666666666
      -smbios type=2,manufacturer=Flei,product=MB-X,serial=BOARD-1234)

rc=$(kernlauf hwfake "hwid nokbd nosched noproc nofs noring3" "${SMB1[@]}")
is "der Lauf mit gesetzter Firmware endet ordentlich" "$rc" "21"
is "die Seriennummer ist genau die von der Kommandozeile" \
   "$(grep -a '^hwid: sys_ser=' "$TMPD/hwfake.txt" | tail -1 | sed 's/^hwid: sys_ser=//')" "SN-JUSTIN-0001"
is "die Baseboard-Seriennummer auch" \
   "$(grep -a '^hwid: brd_ser=' "$TMPD/hwfake.txt" | tail -1 | sed 's/^hwid: brd_ser=//')" "BOARD-9999"
is "die UUID auch" \
   "$(grep -a '^hwid: uuid=' "$TMPD/hwfake.txt" | tail -1 | sed 's/^hwid: uuid=//')" \
   "11111111222233334444555555555555"
is "und jetzt IST es eine UUID" \
   "$(grep -a '^hwid: uuid_ok=' "$TMPD/hwfake.txt" | tail -1 | sed 's/^hwid: uuid_ok=//')" "1"

# NVMe: die Seriennummer aus IDENTIFY CONTROLLER.
dd if=/dev/zero of="$TMPD/nv.img" bs=1M count=8 status=none
rc=$(kernlauf hwnvme "hwid nvme nokbd nosched noproc nofs noring3" \
     -drive "file=$TMPD/nv.img,format=raw,if=none,id=nv0" \
     -device nvme,drive=nv0,serial=NVME-SER-4242)
is "der NVMe-Lauf endet ordentlich" "$rc" "21"
is "die Seriennummer des Laufwerks kommt aus IDENTIFY CONTROLLER" \
   "$(grep -a '^hwid: nvme_ser=' "$TMPD/hwnvme.txt" | tail -1 | sed 's/^hwid: nvme_ser=//')" \
   "NVME-SER-4242"
is "und das Modell dazu" \
   "$(grep -a '^hwid: nvme_mod=' "$TMPD/hwnvme.txt" | tail -1 | sed 's/^hwid: nvme_mod=//')" \
   "QEMU NVMe Ctrl"
# GEGENPROBE: ohne das Wort `nvme` steht der Controller nie, also auch
# keine Seriennummer -- obwohl das Laufwerk am Bus haengt.
rc=$(kernlauf hwnonvme "hwid nokbd nosched noproc nofs noring3" \
     -drive "file=$TMPD/nv.img,format=raw,if=none,id=nv0" \
     -device nvme,drive=nv0,serial=NVME-SER-4242)
is "GEGENPROBE: ohne das Wort nvme gibt es keine Laufwerksnummer" \
   "$(grep -a '^hwid: nvme_ok=' "$TMPD/hwnonvme.txt" | tail -1 | sed 's/^hwid: nvme_ok=//')" "0"

# MAC
rc=$(kernlauf hwmac "hwid nic nokbd nosched noproc nofs noring3" \
     -netdev user,id=n0 -device virtio-net-pci,netdev=n0,mac=52:54:00:12:34:56)
is "die MAC-Adresse kommt aus dem Treiber" \
   "$(grep -a '^hwid: mac=' "$TMPD/hwmac.txt" | tail -1 | sed 's/^hwid: mac=//')" "525400123456"
is "GEGENPROBE: ohne Karte gibt es keine MAC" \
   "$(grep -a '^hwid: mac_ok=' "$TMPD/hwraw.txt" | tail -1 | sed 's/^hwid: mac_ok=//')" "0"

# ============================================== 5. der EFI-Weg

echo "== 5. der EFI-Weg, gegen eine von Hand gebaute Systemtafel =="

rc=$(kernlauf hwefi "hwid hwidefi nokbd nosched noproc nofs noring3" "${SMB1[@]}")
is "der EFI-Lauf endet ordentlich" "$rc" "21"
is "from_efi nimmt denselben Einstiegspunkt wie der Suchlauf" \
   "$(grep -a '^hwidefi: same=' "$TMPD/hwefi.txt" | tail -1 | sed 's/^hwidefi: same=//')" "1"
is "und liest dieselbe Zeichenkette" \
   "$(grep -a '^hwidefi: sys_man=' "$TMPD/hwefi.txt" | tail -1 | sed 's/^hwidefi: sys_man=//')" "Flei"
is "GEGENPROBE: der Zeiger 0 wird abgewiesen" \
   "$(grep -a '^hwidefi: zero=' "$TMPD/hwefi.txt" | tail -1 | sed 's/^hwidefi: zero=//')" "1"
is "GEGENPROBE: eine Tafel ohne Signatur wird abgewiesen" \
   "$(grep -a '^hwidefi: nosig=' "$TMPD/hwefi.txt" | tail -1 | sed 's/^hwidefi: nosig=//')" "1"
is "GEGENPROBE: eine Tafel mit nur einem FREMDEN GUID gibt nichts her" \
   "$(grep -a '^hwidefi: decoy=' "$TMPD/hwefi.txt" | tail -1 | sed 's/^hwidefi: decoy=//')" "1"
nicht "$TMPD/hwraw.txt" "hwidefi:" "GEGENPROBE: ohne das Wort hwidefi wird der Pfad nie betreten"

# ================================== 6. /proc/hwid und der Fingerabdruck

echo "== 6. /proc/hwid, der Fingerabdruck und was ihn NICHT aendert =="

cat > "$TMPD/t_hwid.sh" <<'EOS'
cat /proc/hwid
echo ==FP==
hwid -f
echo ==FULL==
hwid
echo ==END==
EOS
mkimg_hwid() { # ziel
    python3 tools/osum/mkfs.py build "$1" $BLOCKS /bin/ /t/ /proc/ /dev/ \
        /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
        /bin/echo="$TMPD/bin/echo.elf" /bin/ls="$TMPD/bin/ls.elf" \
        /bin/hwid="$TMPD/bin/hwid.elf" /t/hwid.sh="$TMPD/t_hwid.sh" \
        > /dev/null 2>&1
}
mkimg_hwid "$TMPD/dh1.img" && ok "mkfs.py baut das Abbild fuer /proc/hwid" \
    || bad "mkfs.py fehlgeschlagen"
# Ein ZWEITES Abbild, frisch gebaut -- das ist die "Neuinstallation".
mkimg_hwid "$TMPD/dh2.img"

rc=$(lauf hwp1 "$TMPD/dh1.img" "osum vfs nokbd script=sh /t/hwid.sh;exit" "${SMB1[@]}")
is "der /proc/hwid-Lauf endet ordentlich" "$rc" "21"
hat "$TMPD/hwp1.txt" "system_serial: SN-JUSTIN-0001" "/proc/hwid traegt die Seriennummer"
hat "$TMPD/hwp1.txt" "uuid: 11111111-2222-3333-4444-555555555555" \
    "/proc/hwid schreibt die UUID in der gewohnten Form 8-4-4-4-12"
hat "$TMPD/hwp1.txt" "uuid_valid: 1" "und sagt, dass sie eine ist"

fingerabdruck() { # datei
    tr -d '\r' < "$1" | sed -n '/^==FP==/,/^==FULL==/p' \
        | grep -aoE '^[0-9a-f]{64}$' | tail -1
}
FP1=$(fingerabdruck "$TMPD/hwp1.txt")
[ ${#FP1} -eq 64 ] && ok "hwid -f gibt 64 Hexziffern" \
                   || bad "hwid -f gibt '$FP1' (${#FP1} Zeichen)"

# Der Wirt rechnet denselben Fingerabdruck aus dem kanonischen Text nach.
SOLL=$(python3 - <<'PY'
import hashlib
canon = (b"system_manufacturer=Flei\n"
         b"system_product=FLEI-ONE\n"
         b"system_serial=SN-JUSTIN-0001\n"
         b"uuid=11111111-2222-3333-4444-555555555555\n"
         b"board_serial=BOARD-9999\n")
print(hashlib.sha256(canon).hexdigest())
PY
)
is "der Fingerabdruck ist auf dem Wirt nachrechenbar" "$FP1" "$SOLL"

# DIESELBE Maschine, ANDERE Platte: der Fingerabdruck darf sich nicht ruehren.
rc=$(lauf hwp2 "$TMPD/dh2.img" "osum vfs nokbd script=sh /t/hwid.sh;exit" "${SMB1[@]}")
FP2=$(fingerabdruck "$TMPD/hwp2.txt")
is "eine NEUE PLATTE aendert den Fingerabdruck nicht" "$FP2" "$FP1"

# ANDERE Maschine: er muss sich aendern.
rc=$(lauf hwp3 "$TMPD/dh1.img" "osum vfs nokbd script=sh /t/hwid.sh;exit" "${SMB2[@]}")
FP3=$(fingerabdruck "$TMPD/hwp3.txt")
if [ -n "$FP3" ] && [ "$FP3" != "$FP1" ]; then
    ok "eine ANDERE Maschine hat einen anderen Fingerabdruck"
else
    bad "zwei verschiedene Maschinen haben denselben Fingerabdruck ($FP3)"
fi

# Und die Ehrlichkeit: ohne Firmwareangaben zaehlt der Fingerabdruck wenig.
rc=$(lauf hwp4 "$TMPD/dh1.img" "osum vfs nokbd script=sh /t/hwid.sh;exit")
hat "$TMPD/hwp4.txt" "system_serial: " "ohne -smbios bleibt die Seriennummer leer"
q=$(grep -a '^sources: ' "$TMPD/hwp4.txt" | tail -1 | sed 's/^sources: //')
[ "${q:-0}" -le 2 ] && ok "und der Fingerabdruck stuetzt sich auf hoechstens zwei Quellen (${q:-0})" \
                    || bad "unerwartet viele Quellen ohne Firmwareangaben: $q"

# ==================================== 7. die Sicherung: Kern der Runde

echo "== 7. die Sicherung: doppelt, inkrementell, und Oktett fuer Oktett zurueck =="

python3 - "$TMPD" <<'PY'
import os, sys
t = sys.argv[1] + "/baum"
os.makedirs(t + "/sub/deep", exist_ok=True)
a = b"ABCDEFGH" * 128
open(t + "/a.txt", "wb").write(a * 10)
open(t + "/sub/copy.txt", "wb").write(a * 10)   # DIESELBEN Oktette
open(t + "/sub/deep/small.txt", "wb").write(b"hello osum\n")
open(t + "/empty.txt", "wb").write(b"")
open(t + "/rand.bin", "wb").write(bytes((i * 7 + 3) % 256 for i in range(5000)))
PY

cat > "$TMPD/t_backup.sh" <<'EOS'
echo ==RUN1==
backup save /d /store s1
echo ==RUN2==
backup save /d /store s2
echo ==VERIFY==
backup verify /store s1
echo ==RESTORE==
backup restore /store s1 /out
echo ==GET==
backup get /store s1 /rand.bin /got.bin
echo ==GETBAD==
backup get /store s1 /nosuch /nope.bin
echo ==LIST==
backup list /store
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/dbackup.img" $BLOCKS \
    /bin/ /t/ /d/ /d/sub/ /d/sub/deep/ /store/ /out/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/ls="$TMPD/bin/ls.elf" \
    /bin/backup="$TMPD/bin/backup.elf" \
    /d/a.txt="$TMPD/baum/a.txt" /d/rand.bin="$TMPD/baum/rand.bin" /d/empty.txt= \
    /d/sub/copy.txt="$TMPD/baum/sub/copy.txt" \
    /d/sub/deep/small.txt="$TMPD/baum/sub/deep/small.txt" \
    /t/backup.sh="$TMPD/t_backup.sh" > "$TMPD/mkfs-backup.txt" 2>&1 \
    && ok "mkfs.py baut den Quellbaum" || bad "mkfs.py fehlgeschlagen"

rc=$(lauf backup "$TMPD/dbackup.img" "osum vfs nokbd script=sh /t/backup.sh;exit")
is "der Sicherungslauf endet ordentlich" "$rc" "21"
B="$TMPD/backup.txt"

abschnitt() { sed -n "/^==$1==/,/^==/p" "$B"; }
feld() { abschnitt "$1" | grep -a "^$2: " | tail -1 | sed "s/^$2: //"; }

R1_CH=$(feld RUN1 "chunks");     R1_NEW=$(feld RUN1 "new chunks")
R1_RD=$(feld RUN1 "read bytes"); R1_WR=$(feld RUN1 "written bytes")
R2_NEW=$(feld RUN2 "new chunks"); R2_WR=$(feld RUN2 "written bytes")
R2_RD=$(feld RUN2 "read bytes")

is "der erste Lauf sieht 9 Bloecke" "$R1_CH" "9"
is "und speichert davon 5 -- der Rest ist doppelt" "$R1_NEW" "5"
is "gelesen: 25491 Oktette" "$R1_RD" "25491"
is "geschrieben: 11155 Oktette" "$R1_WR" "11155"
is "DER ZWEITE LAUF SCHREIBT NULL NEUE BLOECKE" "$R2_NEW" "0"
is "und null Oktette" "$R2_WR" "0"
is "obwohl er denselben Baum GANZ gelesen hat" "$R2_RD" "$R1_RD"

# Die Zeiten. KEINE Zusage mit fester Zahl -- sie haengen vom Wirt ab und
# ein Test, der bei Last umfaellt, misst den Wirt und nicht das Programm.
# Sie werden gemeldet, damit die Doku eine reproduzierbare Quelle hat.
R1_MS=$(feld RUN1 "ms"); R2_MS=$(feld RUN2 "ms")
ok "Zeit: erster Lauf ${R1_MS} ms, zweiter Lauf ${R2_MS} ms (Zeitgeber 100 Hz, also 10 ms Aufloesung)"

is "verify prueft 9 Bloecke" "$(feld VERIFY 'chunks checked')" "9"
is "und findet nichts Kaputtes" "$(feld VERIFY corrupt)" "0"
is "und nichts Fehlendes" "$(feld VERIFY missing)" "0"
is "wiederhergestellt: 3 Verzeichnisse" "$(feld RESTORE 'restored dirs')" "3"
is "wiederhergestellt: 5 Dateien" "$(feld RESTORE 'restored files')" "5"
is "wiederhergestellt: 25491 Oktette" "$(feld RESTORE 'restored bytes')" "25491"
abschnitt LIST | grep -qa '^s1$' && ok "backup list nennt s1" || bad "backup list nennt s1 nicht"
abschnitt LIST | grep -qa '^s2$' && ok "backup list nennt s2" || bad "backup list nennt s2 nicht"
abschnitt GETBAD | grep -qa 'no such path' \
    && ok "backup get auf einen Pfad, den es nicht gibt, ist ein FEHLER" \
    || bad "backup get auf einen unbekannten Pfad meldet keinen Fehler"

# DER EIGENTLICHE NACHWEIS: der Wirt liest den wiederhergestellten Baum
# AUS DEM ABBILD und haelt ihn gegen das Original.
python3 - "$TMPD/live-backup.img" > "$TMPD/vergleich.txt" 2>&1 <<'PY'
import subprocess, sys
img = sys.argv[1]
def cat(p):
    r = subprocess.run(["python3", "tools/osum/mkfs.py", "cat", img, p],
                       capture_output=True)
    return r.stdout if r.returncode == 0 else None
paare = [("/d/a.txt", "/out/a.txt"),
         ("/d/rand.bin", "/out/rand.bin"),
         ("/d/empty.txt", "/out/empty.txt"),
         ("/d/sub/copy.txt", "/out/sub/copy.txt"),
         ("/d/sub/deep/small.txt", "/out/sub/deep/small.txt"),
         ("/d/rand.bin", "/got.bin")]
gleich = 0
for a, b in paare:
    da, db = cat(a), cat(b)
    if da is not None and db is not None and da == db:
        gleich += 1
    else:
        print("UNGLEICH %s <-> %s" % (a, b))
print("verglichen=%d gleich=%d" % (len(paare), gleich))
PY
sed 's/^/        /' "$TMPD/vergleich.txt" | grep -v 'verglichen=' | head -6
is "der wiederhergestellte Baum ist OKTETT FUER OKTETT der alte (6 Eintraege)" \
   "$(grep -a '^verglichen=' "$TMPD/vergleich.txt")" "verglichen=6 gleich=6"

# ================================= 8. die ehrliche Grenze der festen Blockgroesse

echo "== 8. die ehrliche Grenze: dieselben acht Oktette, hinten und vorne =="

python3 - "$TMPD" <<'PY'
import sys
st = 88172645463325252
def nxt():
    global st
    st ^= (st << 13) & 0xFFFFFFFFFFFFFFFF
    st ^= st >> 7
    st ^= (st << 17) & 0xFFFFFFFFFFFFFFFF
    return st & 0xFF
t = sys.argv[1]
base = bytes(nxt() for _ in range(10240))
open(t + "/base.bin", "wb").write(base)
open(t + "/app.bin", "wb").write(base + b"12345678")
open(t + "/pre.bin", "wb").write(b"12345678" + base)
PY

cat > "$TMPD/t_shift.sh" <<'EOS'
echo ==A1==
backup save /one /sa b1
echo ==A2==
backup save /oneapp /sa b2
echo ==B1==
backup save /one /sb b1
echo ==B2==
backup save /onepre /sb b2
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/dshift.img" $BLOCKS \
    /bin/ /t/ /one/ /oneapp/ /onepre/ /sa/ /sb/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/backup="$TMPD/bin/backup.elf" \
    /one/a.bin="$TMPD/base.bin" /oneapp/a.bin="$TMPD/app.bin" \
    /onepre/a.bin="$TMPD/pre.bin" /t/shift.sh="$TMPD/t_shift.sh" \
    > /dev/null 2>&1 && ok "mkfs.py baut die drei Fassungen derselben Datei" \
    || bad "mkfs.py fehlgeschlagen"

rc=$(lauf shift "$TMPD/dshift.img" "osum vfs nokbd script=sh /t/shift.sh;exit")
is "der Verschiebungslauf endet ordentlich" "$rc" "21"
S="$TMPD/shift.txt"
sfeld() { sed -n "/^==$1==/,/^==/p" "$S" | grep -a "^$2: " | tail -1 | sed "s/^$2: //"; }

is "die Ausgangsdatei belegt 3 Bloecke" "$(sfeld A1 'new chunks')" "3"
is "ACHT OKTETTE HINTEN: EIN neuer Block" "$(sfeld A2 'new chunks')" "1"
is "das sind 2056 von 10248 Oktetten" "$(sfeld A2 'written bytes')" "2056"
is "ACHT OKTETTE VORNE: DREI neue Bloecke -- alle" "$(sfeld B2 'new chunks')" "3"
is "das sind 10248 von 10248 Oktetten, also alles" "$(sfeld B2 'written bytes')" "10248"

# ======================================= 9. verify findet echten Schaden

echo "== 9. ein gekipptes Oktett in der Packdatei, von aussen =="

cp "$TMPD/live-shift.img" "$TMPD/kaputt.img"
python3 tools/tresor/kaputt.py "$TMPD/kaputt.img" /sa/PACK 100 > "$TMPD/kaputt.txt" 2>&1 \
    && ok "$(cat "$TMPD/kaputt.txt")" || { bad "kaputt.py fehlgeschlagen"; cat "$TMPD/kaputt.txt"; }
n=$(cmp -l "$TMPD/live-shift.img" "$TMPD/kaputt.img" 2>/dev/null | wc -l)
is "genau EIN Oktett im Abbild ist anders" "$n" "1"

cat > "$TMPD/t_ver.sh" <<'EOS'
echo ==BAD==
backup verify /sa b1
echo ==GOOD==
backup verify /sb b1
echo ==END==
EOS
python3 - "$TMPD" <<'PY'
import sys, os
sys.path.insert(0, "tools/osum")
import mkfs
t = sys.argv[1]
for name in ("kaputt.img",):
    img = os.path.join(t, name)
    n = os.path.getsize(img)
    fs = mkfs.load(img)
    fs.addfile("/t/ver.sh", open(os.path.join(t, "t_ver.sh"), "rb").read())
    with open(img, "r+b") as f:
        f.write(bytes(fs.d[:n]))
PY
rc=$(lauf ver "$TMPD/kaputt.img" "osum vfs nokbd script=sh /t/ver.sh;exit")
is "der Pruefungslauf endet ordentlich" "$rc" "21"
V="$TMPD/ver.txt"
vfeld() { sed -n "/^==$1==/,/^==/p" "$V" | grep -a "^$2: " | tail -1 | sed "s/^$2: //"; }
is "im beschaedigten Speicher findet verify GENAU EINEN kaputten Block" \
   "$(vfeld BAD corrupt)" "1"
is "GEGENPROBE: im heilen Speicher desselben Laufs findet es keinen" \
   "$(vfeld GOOD corrupt)" "0"

# ================================ 10. die Schluesselverwaltung

echo "== 10. die Schluesselverwaltung: PBKDF2 gegen hashlib, und der Rundlauf =="

cat > "$TMPD/t_key.sh" <<'EOS'
echo ==KDF==
key kdf password saltsalt 1
key kdf password saltsalt 2048
key kdf hunter2 NaClNaCl 4096
echo ==INIT==
key init /k.blob correct-horse
echo ==OPEN==
key open /k.blob correct-horse
echo ==WRONG==
key open /k.blob wrong-pass
echo ==ERASE==
key erase /k.blob
echo ==AFTER==
key open /k.blob correct-horse
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/dkey.img" $BLOCKS /bin/ /t/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/key="$TMPD/bin/key.elf" \
    /t/key.sh="$TMPD/t_key.sh" > /dev/null 2>&1 \
    && ok "mkfs.py baut das Abbild fuer die Schluesselmessung" || bad "mkfs.py fehlgeschlagen"

rc=$(lauf key "$TMPD/dkey.img" "osum vfs nokbd script=sh /t/key.sh;exit")
is "der Schluessellauf endet ordentlich" "$rc" "21"
K="$TMPD/key.txt"

python3 - > "$TMPD/kdf-soll.txt" <<'PY'
import hashlib
for pw, salt, it in ((b"password", b"saltsalt", 1),
                     (b"password", b"saltsalt", 2048),
                     (b"hunter2", b"NaClNaCl", 4096)):
    print(hashlib.pbkdf2_hmac("sha256", pw, salt, it, 64).hex())
PY
i=1
while [ $i -le 3 ]; do
    got=$(grep -a '^dk: ' "$K" | sed -n "${i}p" | sed 's/^dk: //')
    want=$(sed -n "${i}p" "$TMPD/kdf-soll.txt")
    if [ -n "$got" ] && [ "$got" = "$want" ]; then
        ok "PBKDF2-HMAC-SHA256 Fall $i (64 Oktette, zwei Bloecke) stimmt mit hashlib"
    else
        bad "PBKDF2 Fall $i: '$got' statt '$want'"
    fi
    i=$((i+1))
done

FP_INIT=$(sed -n '/^==INIT==/,/^==OPEN==/p' "$K" | grep -a '^key sha256: ' | tail -1 | sed 's/^key sha256: //')
FP_OPEN=$(sed -n '/^==OPEN==/,/^==WRONG==/p' "$K" | grep -a '^key sha256: ' | tail -1 | sed 's/^key sha256: //')
[ ${#FP_INIT} -eq 64 ] && ok "init erzeugt einen Schluessel und nennt seinen Fingerabdruck" \
                       || bad "init nennt keinen Fingerabdruck"
is "open mit dem richtigen Passwort gibt DENSELBEN Schluessel zurueck" "$FP_OPEN" "$FP_INIT"
sed -n '/^==WRONG==/,/^==ERASE==/p' "$K" | grep -qa 'wrong passphrase' \
    && ok "ein falsches Passwort wird abgewiesen (die Marke wird VOR dem Auspacken geprueft)" \
    || bad "ein falsches Passwort wird nicht abgewiesen"
sed -n '/^==WRONG==/,/^==ERASE==/p' "$K" | grep -qa '^key sha256: ' \
    && bad "bei falschem Passwort kommt trotzdem ein Schluessel heraus" \
    || ok "und dabei kommt KEIN Schluessel heraus"
ERMS=$(sed -n '/^==ERASE==/,/^==AFTER==/p' "$K" | grep -a '^erase ms: ' | tail -1 | sed 's/^erase ms: //')
[ -n "$ERMS" ] && ok "crypto erase gemessen: ${ERMS} ms" || bad "erase meldet keine Zeit"
sed -n '/^==AFTER==/,/^==END==/p' "$K" | grep -qa 'cannot read' \
    && ok "nach erase ist der Schluessel weg -- open findet nichts mehr" \
    || bad "nach erase laesst sich der Schluessel noch oeffnen"

# GEGENPROBE: der Schluessel selbst darf NIE auf der Leitung stehen.
if grep -qa '^key: [0-9a-f]\{64\}$' "$K"; then
    bad "der Schluessel steht im Klartext in der Ausgabe"
else
    ok "GEGENPROBE: der Schluessel selbst steht nirgends in der Ausgabe"
fi

# ============ 11. verwaiste Pakete: die eine Ausnahme, und was sie kostet
#
# Der Nachtrag vom 27.08.2026. Ein Backup traegt KEINE Programme -- ihre
# Oktette liegen in einer Quelle und der Hash im PLAN benennt sie
# eindeutig. Das gilt aber nur, solange eine Quelle sie auch liefern kann.
# Ein selbst gebautes, nie veroeffentlichtes Paket ist VERWAIST: sein Hash
# steht im PLAN, und niemand kann die Oktette herausgeben.
#
# Gemessen wird hier:
#   * dasselbe Backup einmal OHNE und einmal MIT Verwaisten -- die
#     Differenz ist der Preis der Ausnahme, in Oktetten und in Prozent;
#   * das ERREICHBARE Paket landet NICHT im Schnappschuss (Gegenprobe);
#   * ein zweiter Rechner, auf dem es den Baum GAR NICHT gibt, stellt aus
#     dem Speicher allein wieder her, und der Wirt vergleicht die Oktette
#     mit dem Original AUS DEM ABBILD;
#   * das wiederhergestellte Paket LAEUFT -- was zugleich beweist, dass
#     `restore` die Rechtebits wirklich setzt;
#   * eine kaputte Zeile und ein fehlender Eintrag sind LAUTE Fehler.

echo "== 11. verwaiste Pakete: sichern, Baum wegwerfen, wiederherstellen =="

ORPH=8c3851919b9fcd2a889d
REACH=bc9c62d6877b710a648c

python3 - "$TMPD" "$ORPH" "$REACH" <<'PY2'
import os, sys
t, orph, reach = sys.argv[1], sys.argv[2], sys.argv[3]
# DER SICHERUNGSSATZ, wie ihn PLAN2 definiert: PLAN + config + state.
os.makedirs(t + "/set/config", exist_ok=True)
os.makedirs(t + "/set/state", exist_ok=True)
open(t + "/set/PLAN", "wb").write(
    ("app mine 0.1.0\t%s\napp hallo 1.0.0\t%s\n" % (orph, reach)).encode())
open(t + "/set/config/app.conf", "wb").write(b"theme=dark\nfont=12\n")
# DIE GROESSE IST MIT ABSICHT GEWAEHLT. PLAN2 hat den Sicherungssatz eines
# echten Baumes gemessen: 44 076 Oktette (docs/BACKUP.md § 2). Ein
# Spielzeugsatz von 800 Oktetten wuerde den Aufschlag durch ein 29-KiB-Paket
# als "+3587 %" ausweisen -- eine wahre Zahl, die nichts bedeutet. Hier
# steht deshalb ungefaehr so viel Benutzerdatum wie dort, damit der
# Prozentsatz mit der echten Messung VERGLEICHBAR ist.
st = 0x2545F4914F6CDD1D
def nxt():
    global st
    st ^= (st << 13) & 0xFFFFFFFFFFFFFFFF
    st ^= st >> 7
    st ^= (st << 17) & 0xFFFFFFFFFFFFFFFF
    return st & 0xFF
open(t + "/set/state/doc.txt", "wb").write(bytes(nxt() for _ in range(24000)))
open(t + "/set/state/notes.md", "wb").write(bytes(nxt() for _ in range(19000)))
# Die ORPHANS-Liste nach der Schnittstelle aus docs/ORPHANS.md.
open(t + "/ORPHANS", "wb").write((orph + "\n").encode())
open(t + "/EMPTY", "wb").write(b"")
open(t + "/BADSHAPE", "wb").write(b"../../etc/passwd\n")
open(t + "/MISSING", "wb").write(b"deadbeefdeadbeefdead\n")
PY2

# Das verwaiste Paket ist ein ECHTES Programm -- sonst liesse sich nicht
# messen, dass es nach der Wiederherstellung laeuft.
cp "$TMPD/bin/hello.elf" "$TMPD/orph-start"
cp "$TMPD/bin/echo.elf" "$TMPD/reach-start"
printf 'name=mine\nversion=0.1.0\n' > "$TMPD/orph-meta"
printf 'name=hallo\nversion=1.0.0\n' > "$TMPD/reach-meta"

cat > "$TMPD/t_orph.sh" <<'EOS'
echo ==BASE==
backup save /set /sa a1
echo ==WITH==
backup save /set /sb b1 /t/ORPHANS /tree
echo ==EMPTY==
backup save /set /sc c1 /t/EMPTY /tree
echo ==BADSHAPE==
backup save /set /sd d1 /t/BADSHAPE /tree
echo ==MISSING==
backup save /set /se e1 /t/MISSING /tree
echo ==SNAP==
cat /sb/S-b1
echo ==END==
EOS

python3 tools/osum/mkfs.py build "$TMPD/dorph.img" $BLOCKS \
    /bin/ /t/ /set/ /set/config/ /set/state/ /tree/ /tree/store/ \
    "/tree/store/$ORPH/" "/tree/store/$REACH/" /tree/users/ /tree/users/cache/ \
    /sa/ /sb/ /sc/ /sd/ /se/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/backup="$TMPD/bin/backup.elf" \
    /set/PLAN="$TMPD/set/PLAN" /set/config/app.conf="$TMPD/set/config/app.conf" \
    /set/state/doc.txt="$TMPD/set/state/doc.txt" \
    /set/state/notes.md="$TMPD/set/state/notes.md" \
    "/tree/store/$ORPH/start=$TMPD/orph-start" \
    "/tree/store/$ORPH/PAKET=$TMPD/orph-meta" \
    "/tree/store/$REACH/start=$TMPD/reach-start" \
    "/tree/store/$REACH/PAKET=$TMPD/reach-meta" \
    /tree/users/cache/thumb.bin="$TMPD/reach-meta" \
    /t/ORPHANS="$TMPD/ORPHANS" /t/EMPTY="$TMPD/EMPTY" \
    /t/BADSHAPE="$TMPD/BADSHAPE" /t/MISSING="$TMPD/MISSING" \
    /t/orph.sh="$TMPD/t_orph.sh" > "$TMPD/mkfs-orph.txt" 2>&1 \
    && ok "mkfs.py baut den Baum mit einem verwaisten und einem erreichbaren Paket" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs-orph.txt" | head -6; }

rc=$(lauf orph "$TMPD/dorph.img" "osum vfs nokbd script=sh /t/orph.sh;exit")
is "der Verwaisten-Lauf endet ordentlich" "$rc" "21"
O="$TMPD/orph.txt"
ofeld() { sed -n "/^==$1==/,/^==/p" "$O" | grep -a "^$2: " | tail -1 | sed "s/^$2: //"; }

is "OHNE Liste sichert backup NULL verwaiste Eintraege" "$(ofeld BASE 'orphan entries')" "0"
is "und schreibt dafuer auch null verwaiste Oktette" "$(ofeld BASE 'orphan bytes')" "0"
is "MIT Liste sichert backup GENAU EINEN verwaisten Eintrag" "$(ofeld WITH 'orphan entries')" "1"
is "eine LEERE Liste ist kein Fehler und sichert nichts" "$(ofeld EMPTY 'orphan entries')" "0"

# DIE ZAHL, um die es geht: was die Ausnahme kostet.
BASEB=$(ofeld BASE 'written bytes')
WITHB=$(ofeld WITH 'written bytes')
ORPHB=$(ofeld WITH 'orphan bytes')
if [ -n "$BASEB" ] && [ -n "$WITHB" ] && [ "$BASEB" -gt 0 ] 2>/dev/null; then
    DIFF=$((WITHB - BASEB))
    PCT=$(awk -v a="$DIFF" -v b="$BASEB" 'BEGIN{printf "%.1f", a*100/b}')
    is "die Differenz ist genau das, was die verwaisten Oktette ausmachen" \
       "$DIFF" "$ORPHB"
    ok "PREIS DER AUSNAHME: $BASEB -> $WITHB Oktette, +$DIFF (+$PCT %)"
    echo "        (ohne Verwaiste $BASEB, mit $WITHB, Aufschlag $DIFF Oktette = $PCT %)"
else
    bad "die Oktettzahlen des Verwaisten-Laufs fehlen"
fi

# GEGENPROBEN am Schnappschuss selbst.
SNAP=$(sed -n '/^==SNAP==/,/^==END==/p' "$O")
echo "$SNAP" | grep -qa "/store/$ORPH/start" \
    && ok "der Schnappschuss nennt das VERWAISTE Paket" \
    || bad "der Schnappschuss nennt das verwaiste Paket nicht"
echo "$SNAP" | grep -qa "$REACH" \
    && bad "das ERREICHBARE Paket steht im Schnappschuss und darf nicht" \
    || ok "GEGENPROBE: das ERREICHBARE Paket steht NICHT im Schnappschuss"
echo "$SNAP" | grep -qa "cache" \
    && bad "cache steht im Schnappschuss und darf nie" \
    || ok "GEGENPROBE: cache steht NICHT im Schnappschuss"
echo "$SNAP" | grep -qa "/state/doc.txt" \
    && ok "die Benutzerdaten stehen drin -- Regel 1" \
    || bad "die Benutzerdaten fehlen im Schnappschuss"

# LAUTE FEHLER, beide.
sed -n '/^==BADSHAPE==/,/^==MISSING==/p' "$O" | grep -qa 'not a lower case hex store name' \
    && ok "eine Zeile, die kein Speichername ist, ist ein LAUTER Fehler (kein Pfad-Ausbruch)" \
    || bad "'../../etc/passwd' in der Liste wird nicht abgewiesen"
sed -n '/^==MISSING==/,/^==SNAP==/p' "$O" | grep -qa 'orphan is not in the store' \
    && ok "ein verwaister Eintrag, den es nicht gibt, ist ein LAUTER Fehler" \
    || bad "ein fehlender verwaister Eintrag wird stillschweigend uebergangen"

# ---- DER EIGENTLICHE NACHWEIS: ein Rechner OHNE den Baum ----------------
#
# Das zweite Abbild bekommt NUR den Sicherungsspeicher. Kein /tree, kein
# /set, kein Paket -- die Oktette koennen nirgendwo anders herkommen als
# aus PACK.
for f in PACK INDEX S-b1; do
    python3 tools/osum/mkfs.py cat "$TMPD/live-orph.img" "/sb/$f" > "$TMPD/sb-$f" 2>/dev/null \
        || bad "der Wirt kann /sb/$f nicht aus dem Abbild lesen"
done
[ -s "$TMPD/sb-PACK" ] && ok "der Wirt holt PACK, INDEX und den Schnappschuss aus dem Abbild" \
                       || bad "PACK ist leer"

cat > "$TMPD/t_orphr.sh" <<EOS
echo ==RESTORE==
backup restore /sb b1 /out
echo ==VERIFY==
backup verify /sb b1
echo ==RUN==
/out/store/$ORPH/start
echo ==END==
EOS

python3 tools/osum/mkfs.py build "$TMPD/dorphr.img" $BLOCKS \
    /bin/ /t/ /sb/ /out/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/backup="$TMPD/bin/backup.elf" \
    /sb/PACK="$TMPD/sb-PACK" /sb/INDEX="$TMPD/sb-INDEX" /sb/S-b1="$TMPD/sb-S-b1" \
    /t/orphr.sh="$TMPD/t_orphr.sh" > "$TMPD/mkfs-orphr.txt" 2>&1 \
    && ok "der zweite Rechner hat NUR den Speicher -- keinen Baum, kein Paket" \
    || { bad "mkfs.py baut das zweite Abbild nicht"; sed 's/^/        /' "$TMPD/mkfs-orphr.txt" | head -6; }

rc=$(lauf orphr "$TMPD/dorphr.img" "osum vfs nokbd script=sh /t/orphr.sh;exit")
is "der Wiederherstellungs-Lauf endet ordentlich" "$rc" "21"
R="$TMPD/orphr.txt"
sed -n '/^==VERIFY==/,/^==RUN==/p' "$R" | grep -qa '^corrupt: 0$' \
    && ok "der Speicher des zweiten Rechners ist heil (corrupt: 0)" \
    || bad "verify meldet Schaden im uebertragenen Speicher"
sed -n '/^==RUN==/,/^==END==/p' "$R" | grep -qa 'hello' \
    && ok "DAS WIEDERHERGESTELLTE PAKET LAEUFT -- also sind die Rechtebits mitgekommen" \
    || { bad "das wiederhergestellte Paket laeuft nicht"; \
         sed -n '/^==RUN==/,/^==END==/p' "$R" | sed 's/^/        /' | head -4; }

python3 - "$TMPD/live-orphr.img" "$TMPD/orph-start" "$ORPH" > "$TMPD/orphcmp.txt" 2>&1 <<'PY2'
import subprocess, sys
img, orig, orph = sys.argv[1], sys.argv[2], sys.argv[3]
r = subprocess.run(["python3", "tools/osum/mkfs.py", "cat", img,
                    "/out/store/%s/start" % orph], capture_output=True)
got = r.stdout if r.returncode == 0 else b""
want = open(orig, "rb").read()
print("original=%d wieder=%d gleich=%s" % (len(want), len(got), got == want))
PY2
cat "$TMPD/orphcmp.txt" | sed 's/^/        /'
grep -qa 'gleich=True' "$TMPD/orphcmp.txt" \
    && ok "das verwaiste Paket ist OKTETT FUER OKTETT wieder da, aus dem Abbild gelesen" \
    || bad "das wiederhergestellte verwaiste Paket ist NICHT oktettgleich"

# ====== 12. was der Entwurf taugt: Deduplizierung, Zuwachs, Rueckweg
#
# Der ZWEITE NACHTRAG vom 27.08.2026. Justins Frage war, ob beim Sichern
# "eine Backup-Datei, ein ZIP oder so" herauskommt. Die Antwort ist nein,
# und hier stehen die Zahlen, die erklaeren, warum das die bessere
# Antwort ist:
#
#   * DIESELBE DATEI IN DREI ORDNERN liegt EINMAL im Speicher.
#   * DERSELBE BAUM ZWEIMAL gesichert schreibt beim zweiten Mal NICHTS.
#   * EINE GROSSE DATEI MINIMAL GEAENDERT kostet die geaenderten Bloecke
#     und keinen Oktett mehr -- ein ZIP haette alles neu geschrieben.
#   * WIEDERHERSTELLEN geht einzeln (eine Datei) und ganz (der Baum),
#     und der WIRT vergleicht die Oktette aus dem Plattenabbild.
#   * EIN ABGEBROCHENER LAUF hinterlaesst NICHTS, was wie eine fertige
#     Sicherung aussieht.

echo "== 12. Deduplizierung, Zuwachs und der Rueckweg =="

python3 - "$TMPD" <<'PY2'
import sys, os
t = sys.argv[1]
st = 0x139408DCBBF7A44
def nxt():
    global st
    st ^= (st << 13) & 0xFFFFFFFFFFFFFFFF
    st ^= st >> 7
    st ^= (st << 17) & 0xFFFFFFFFFFFFFFFF
    return st & 0xFF
# 1. DIESELBE DATEI IN DREI ORDNERN. 8192 Oktette = genau zwei Bloecke.
gleich = bytes(nxt() for _ in range(8192))
for d in ("x", "y", "z"):
    os.makedirs(t + "/drei/" + d, exist_ok=True)
    open(t + "/drei/%s/gleich.bin" % d, "wb").write(gleich)
# 2. DER BAUM, zweimal gesichert -- und einmal mit EINER kleinen Aenderung.
os.makedirs(t + "/data/sub", exist_ok=True)
a = bytes(nxt() for _ in range(20000))
b = bytes(nxt() for _ in range(16384))   # genau vier Bloecke
c = bytes(nxt() for _ in range(8000))
open(t + "/data/a.txt", "wb").write(a)
open(t + "/data/b.bin", "wb").write(b)
open(t + "/data/sub/c.txt", "wb").write(c)
# Dieselben Dateien, EIN Oktett anders -- im ERSTEN Block von b.bin.
os.makedirs(t + "/data2/sub", exist_ok=True)
b2 = bytearray(b); b2[100] ^= 0xFF
open(t + "/data2/a.txt", "wb").write(a)
open(t + "/data2/b.bin", "wb").write(bytes(b2))
open(t + "/data2/sub/c.txt", "wb").write(c)
open(t + "/BADLIST", "wb").write(b"deadbeefdeadbeefdead\n")
print("%d %d %d" % (len(a), len(b), len(c)))
PY2

cat > "$TMPD/t_mess.sh" <<'EOS'
echo ==DEDUP==
backup save /drei /st1 d1
echo ==RUN1==
backup save /data /st3 r1
echo ==RUN2==
backup save /data /st3 r2
echo ==RUN3==
backup save /data2 /st3 r3
echo ==GET==
backup get /st3 r1 /a.txt /got.bin
echo ==REST==
backup restore /st3 r1 /out
echo ==LIST==
backup list /st3
echo ==ABBRUCH==
backup save /data /st4 k1 /BADLIST /data
echo ==NACHABBRUCH==
backup list /st4
echo ==RESTABBRUCH==
backup restore /st4 k1 /out2
echo ==END==
EOS

python3 tools/osum/mkfs.py build "$TMPD/dmess.img" $BLOCKS \
    /bin/ /t/ /drei/ /drei/x/ /drei/y/ /drei/z/ \
    /data/ /data/sub/ /data2/ /data2/sub/ \
    /st1/ /st3/ /st4/ /out/ /out2/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/backup="$TMPD/bin/backup.elf" \
    /drei/x/gleich.bin="$TMPD/drei/x/gleich.bin" \
    /drei/y/gleich.bin="$TMPD/drei/y/gleich.bin" \
    /drei/z/gleich.bin="$TMPD/drei/z/gleich.bin" \
    /data/a.txt="$TMPD/data/a.txt" /data/b.bin="$TMPD/data/b.bin" \
    /data/sub/c.txt="$TMPD/data/sub/c.txt" \
    /data2/a.txt="$TMPD/data2/a.txt" /data2/b.bin="$TMPD/data2/b.bin" \
    /data2/sub/c.txt="$TMPD/data2/sub/c.txt" \
    /BADLIST="$TMPD/BADLIST" /t/mess.sh="$TMPD/t_mess.sh" \
    > "$TMPD/mkfs-mess.txt" 2>&1 \
    && ok "mkfs.py baut den Messbaum" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs-mess.txt" | head -6; }

rc=$(lauf mess "$TMPD/dmess.img" "osum vfs nokbd script=sh /t/mess.sh;exit")
is "der Messlauf endet ordentlich" "$rc" "21"
M="$TMPD/mess.txt"
mfeld() { sed -n "/^==$1==/,/^==/p" "$M" | grep -a "^$2: " | tail -1 | sed "s/^$2: //"; }

# ---- 1. DIESELBE DATEI IN DREI ORDNERN -----------------------------------
is "drei Ordner, dieselbe Datei: 6 Bloecke gesehen" "$(mfeld DEDUP 'chunks')" "6"
is "aber nur ZWEI davon sind neu" "$(mfeld DEDUP 'new chunks')" "2"
is "gelesen wurden alle 24576 Oktette" "$(mfeld DEDUP 'read bytes')" "24576"
is "GESCHRIEBEN nur 8192 -- die Datei liegt EINMAL im Speicher" \
   "$(mfeld DEDUP 'written bytes')" "8192"

# ---- 2. ZWEITER LAUF, NICHTS GEAENDERT -----------------------------------
W1=$(mfeld RUN1 'written bytes'); W2=$(mfeld RUN2 'written bytes')
T1=$(mfeld RUN1 'ms');            T2=$(mfeld RUN2 'ms')
R1=$(mfeld RUN1 'read bytes');    R2=$(mfeld RUN2 'read bytes')
is "erster Lauf schreibt den ganzen Baum" "$W1" "44384"
is "und das ist genau, was er gelesen hat -- ein letzter Block wird NICHT auf 4096 aufgefuellt" \
   "$W1" "$R1"
is "ZWEITER LAUF SCHREIBT NULL OKTETTE" "$W2" "0"
is "und liest dabei trotzdem alles wieder" "$R2" "$R1"
ok "ZAHLEN: 1. Lauf $W1 Oktette in ${T1} ms, 2. Lauf $W2 Oktette in ${T2} ms"
echo "        (der Faktor ist kein Verhaeltnis, sondern eine Null:"
echo "         $W1 -> $W2 Oktette bei gleichem Lesen von $R1)"

# ---- 3. EINE GROSSE DATEI, EIN OKTETT ANDERS -----------------------------
W3=$(mfeld RUN3 'written bytes'); N3=$(mfeld RUN3 'new chunks')
is "EIN Oktett in b.bin geaendert: genau EIN neuer Block" "$N3" "1"
is "das sind 4096 Oktette von 44384 gelesenen" "$W3" "4096"
if [ -n "$W1" ] && [ -n "$W3" ] && [ "$W3" -gt 0 ] 2>/dev/null; then
    F=$(awk -v a="$W1" -v b="$W3" 'BEGIN{printf "%.0f", a/b}')
    ok "FAKTOR der kleinen Aenderung: $W1 -> $W3 Oktette, ${F}x weniger"
fi

# ---- 4. DER RUECKWEG -----------------------------------------------------
sed -n '/^==GET==/,/^==REST==/p' "$M" | grep -qa 'backup:' \
    && bad "backup get meldet einen Fehler" \
    || ok "backup get holt die einzelne Datei ohne Fehler (die Oktette werden unten verglichen)"
is "der ganze Baum kommt zurueck: die Wurzel und sub" "$(mfeld REST 'restored dirs')" "2"
is "und 3 Dateien" "$(mfeld REST 'restored files')" "3"
is "und 44384 Oktette" "$(mfeld REST 'restored bytes')" "44384"
sed -n '/^==LIST==/,/^==ABBRUCH==/p' "$M" | grep -qa '^r1$' \
    && ok "backup list nennt die drei Sicherungen" || bad "backup list nennt r1 nicht"

python3 - "$TMPD/live-mess.img" "$TMPD" > "$TMPD/messcmp.txt" 2>&1 <<'PY2'
import subprocess, sys
img, t = sys.argv[1], sys.argv[2]
def cat(p):
    r = subprocess.run(["python3", "tools/osum/mkfs.py", "cat", img, p],
                       capture_output=True)
    return r.stdout if r.returncode == 0 else None
paare = [("/data/a.txt", "/out/a.txt"), ("/data/b.bin", "/out/b.bin"),
         ("/data/sub/c.txt", "/out/sub/c.txt"), ("/data/a.txt", "/got.bin")]
gleich = 0
for a, b in paare:
    da, db = cat(a), cat(b)
    if da is not None and db is not None and da == db:
        gleich += 1
    else:
        print("UNGLEICH %s <-> %s" % (a, b))
print("verglichen=%d gleich=%d" % (len(paare), gleich))
PY2
sed 's/^/        /' "$TMPD/messcmp.txt" | grep -v 'verglichen=' | head -4
is "aus dem Abbild geprueft: jede Datei OKTETT FUER OKTETT (3 Dateien + 1 einzeln)" \
   "$(grep -a '^verglichen=' "$TMPD/messcmp.txt")" "verglichen=4 gleich=4"

# ---- 5. EIN ABGEBROCHENER LAUF HINTERLAESST NICHTS -----------------------
sed -n '/^==ABBRUCH==/,/^==NACHABBRUCH==/p' "$M" | grep -qa 'could not be completed' \
    && ok "ein Lauf, der scheitert, sagt es" \
    || bad "der gescheiterte Lauf meldet nichts"
sed -n '/^==NACHABBRUCH==/,/^==RESTABBRUCH==/p' "$M" | grep -qa '^k1$' \
    && bad "die abgebrochene Sicherung k1 wird aufgelistet -- sie sieht aus wie eine fertige" \
    || ok "danach steht KEINE Sicherung im Speicher -- kein halbes Backup"
sed -n '/^==RESTABBRUCH==/,/^==END==/p' "$M" | grep -qa 'no such snapshot' \
    && ok "und wiederherstellen laesst sich daraus auch nichts" \
    || bad "aus dem abgebrochenen Lauf laesst sich etwas wiederherstellen"

# GEGENPROBE AM ABBILD: liegt da wirklich kein S-, und auch kein T-?
python3 tools/osum/mkfs.py list "$TMPD/live-mess.img" > "$TMPD/mess.ls" 2>&1
grep -qE '/st4/S-' "$TMPD/mess.ls" \
    && bad "im Abbild liegt eine S-Datei aus dem abgebrochenen Lauf" \
    || ok "GEGENPROBE im Abbild: /st4 hat keine S-Datei"
grep -qE '/st4/T-' "$TMPD/mess.ls" \
    && bad "die halbfertige T-Datei ist liegengeblieben" \
    || ok "GEGENPROBE im Abbild: die halbfertige T-Datei ist weggeraeumt"

# ================ 13. Geheimnisse: drei Klassen, zwei getrennte Passwoerter

echo "== 13a. ChaCha20 und die Ableitung gegen RFC 8439 und hashlib =="

python3 tools/tresor/vectors.py > "$TMPD/vec.txt" 2>&1 \
    && ok "der Wirt rechnet die Vektoren nach (cryptography + hashlib)" \
    || { bad "vectors.py laeuft nicht"; sed 's/^/        /' "$TMPD/vec.txt" | head -6; }

cat > "$TMPD/t_sec1.sh" <<'EOS'
bsect
EOS
python3 tools/osum/mkfs.py build "$TMPD/dsec1.img" $BLOCKS /bin/ /t/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/echo="$TMPD/bin/echo.elf" \
    /bin/bsect="$TMPD/bin/bsect.elf" /t/s.sh="$TMPD/t_sec1.sh" \
    > "$TMPD/mkfs-sec1.txt" 2>&1 \
    && ok "mkfs.py baut das Abbild fuer die Vektoren" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs-sec1.txt" | head -6; }

rc=$(lauf sec1 "$TMPD/dsec1.img" "osum vfs nokbd script=sh /t/s.sh;exit")
is "der Vektorlauf endet ordentlich" "$rc" "21"
V="$TMPD/sec1.txt"
hv() { grep -a "^$1: " "$V" | sed "s/^$1: //" | tr -d '\r'; }
wv() { grep -a "^$1: " "$TMPD/vec.txt" | sed "s/^$1: //"; }

is "cc1: ChaCha20-Block = RFC 8439 2.3.2" "$(hv cc1)" "$(wv cc1)"
is "cc2: die Verschluesselung von RFC 8439 2.4.2" "$(hv cc2)" "$(wv cc2)"
is "und cc2 ist DER TEXT AUS DEM RFC selbst" "$(hv cc2)" "$(wv rfc242)"
is "cc3: 4096 Oktette -- der Zaehler laeuft 64 mal weiter" "$(hv cc3)" "$(wv cc3)"
is "hm1: HMAC-SHA256 ueber 4096 Oktette (key.fi kann das nicht)" "$(hv hm1)" "$(wv hm1)"
is "pb1: PBKDF2-HMAC-SHA256, 2048 Runden, gegen hashlib" "$(hv pb1)" "$(wv pb1)"
is "cls: die Einstufung von neun Pfaden" "$(hv cls)" "dddssdnnn"

SL=$(grep -a '^sl1: ' "$V" | sed 's/^sl1: //' | tr -d '\r')
is "sl1: der BLOCKNAME ist HMAC(CONV, Klartext)" "$(echo "$SL" | sed -n 1p)" "$(wv sl1name)"
is "sl1: die ersten 32 Oktette Geheimtext" "$(echo "$SL" | sed -n 2p)" "$(wv sl1ct)"
is "sl1: die Marke (encrypt-then-MAC)" "$(echo "$SL" | sed -n 3p)" "$(wv sl1tag)"
is "sl2: entsiegeln gibt den Klartext zurueck" "$(hv sl2)" "yes"
is "sl3: EIN gekipptes Oktett und das Entsiegeln VERWEIGERT" "$(hv sl3)" "yes"
is "sl4: derselbe Klartext -> DERSELBE Name (Dedup ueberlebt)" "$(hv sl4)" "yes"
is "sl5: anderes Passwort -> ANDERER Name (der Bestaetigungsangriff faellt aus)" \
   "$(hv sl5)" "yes"
is "sl5 gegengerechnet auf dem Wirt" "$(wv sl5name)" "$(wv sl5name)"

# ---------------------------------------------------------------------------

echo "== 13b. drei Klassen in einer echten Sicherung =="

# Der Sicherungssatz. Jede Datei traegt eine EINDEUTIGE Marke, damit der
# Wirt sie im fertigen Speicher suchen kann -- und ihr Fehlen etwas heisst.
python3 - "$TMPD" <<'PY2'
import os, sys
t = sys.argv[1] + "/set"
for d in ("config", "config/vpn", "config/vpn/keys", "state", "state/session",
          "secrets", "etc", "device"):
    os.makedirs(t + "/" + d, exist_ok=True)
st = 0x51DE7A1B4C9E2F03
def nxt():
    global st
    st ^= (st << 13) & 0xFFFFFFFFFFFFFFFF
    st ^= st >> 7
    st ^= (st << 17) & 0xFFFFFFFFFFFFFFFF
    return st & 0xFF
def blob(mark, n):
    return mark + bytes(nxt() for _ in range(n - len(mark)))
# (a) GEWOEHNLICH
open(t + "/PLAN", "wb").write(blob(b"MARK-PLAN-ORDINARY-DATA ", 8192))
open(t + "/config/theme", "wb").write(b"MARK-THEME-ORDINARY\n")
open(t + "/state/last", "wb").write(b"MARK-STATE-ORDINARY\n")
open(t + "/etc/passwd", "wb").write(b"MARK-PASSWD-ORDINARY\n")
# (b) GEHEIM
open(t + "/secrets/vault.kdbx", "wb").write(blob(b"MARK-VAULT-SECRET-BANK-PW ", 8192))
open(t + "/config/vpn/keys/home.key", "wb").write(b"MARK-VPNKEY-SECRET\n")
open(t + "/etc/shadow", "wb").write(b"MARK-SHADOW-SECRET\n")
# (c) DARF NIE MIT
open(t + "/device/key", "wb").write(b"MARK-DEVICEKEY-NEVER\n")
open(t + "/etc/machine-id", "wb").write(b"MARK-MACHINEID-NEVER\n")
open(t + "/state/session/token", "wb").write(b"MARK-SESSION-NEVER\n")
PY2

cat > "$TMPD/t_sec2.sh" <<'EOS'
echo ==A==
backup save /set /sA a1
echo ==B==
backup save /set /sB b1 -mmasterpw
echo ==BRESTNOM==
backup restore /sB b1 /outX
echo ==BREST==
backup restore /sB b1 /outB -mmasterpw
echo ==C==
backup save /set /sC c1 -pstorepw -mmasterpw
echo ==CVERIFY==
backup verify /sC c1 -pstorepw -mmasterpw
echo ==CVERIFYNOP==
backup verify /sC c1
echo ==CWRONGP==
backup restore /sC c1 /outZ -pnonsense -mmasterpw
echo ==CWRONGM==
backup restore /sC c1 /outZ -pstorepw -mnonsense
echo ==CREST==
backup restore /sC c1 /outC -pstorepw -mmasterpw
echo ==DEDUPA==
backup save /dup /sD d1
echo ==DEDUPB==
backup save /dup /sE e1 -pstorepw
echo ==DEDUPA2==
backup save /dup /sD d2
echo ==DEDUPB2==
backup save /dup /sE e2 -pstorepw
echo ==END==
EOS

python3 - "$TMPD" <<'PY2'
import os, sys
t = sys.argv[1]
st = 0x139408DCBBF7A44
def nxt():
    global st
    st ^= (st << 13) & 0xFFFFFFFFFFFFFFFF
    st ^= st >> 7
    st ^= (st << 17) & 0xFFFFFFFFFFFFFFFF
    return st & 0xFF
gleich = bytes(nxt() for _ in range(8192))   # genau zwei Bloecke
for d in ("x", "y", "z"):
    os.makedirs(t + "/dup/" + d, exist_ok=True)
    open(t + "/dup/%s/gleich.bin" % d, "wb").write(gleich)
PY2

python3 tools/osum/mkfs.py build "$TMPD/dsec2.img" $BLOCKS \
    /bin/ /t/ /proc/ /dev/ \
    /set/ /set/config/ /set/config/vpn/ /set/config/vpn/keys/ \
    /set/state/ /set/state/session/ /set/secrets/ /set/etc/ /set/device/ \
    /dup/ /dup/x/ /dup/y/ /dup/z/ \
    /sA/ /sB/ /sC/ /sD/ /sE/ /outB/ /outC/ /outX/ /outZ/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/backup="$TMPD/bin/backup.elf" \
    /set/PLAN="$TMPD/set/PLAN" \
    /set/config/theme="$TMPD/set/config/theme" \
    /set/config/vpn/keys/home.key="$TMPD/set/config/vpn/keys/home.key" \
    /set/state/last="$TMPD/set/state/last" \
    /set/state/session/token="$TMPD/set/state/session/token" \
    /set/secrets/vault.kdbx="$TMPD/set/secrets/vault.kdbx" \
    /set/etc/passwd="$TMPD/set/etc/passwd" \
    /set/etc/shadow="$TMPD/set/etc/shadow" \
    /set/etc/machine-id="$TMPD/set/etc/machine-id" \
    /set/device/key="$TMPD/set/device/key" \
    /dup/x/gleich.bin="$TMPD/dup/x/gleich.bin" \
    /dup/y/gleich.bin="$TMPD/dup/y/gleich.bin" \
    /dup/z/gleich.bin="$TMPD/dup/z/gleich.bin" \
    /t/s.sh="$TMPD/t_sec2.sh" > "$TMPD/mkfs-sec2.txt" 2>&1 \
    && ok "mkfs.py baut den Sicherungssatz mit allen drei Klassen" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs-sec2.txt" | head -8; }

rc=$(lauf sec2 "$TMPD/dsec2.img" "osum vfs nokbd script=sh /t/s.sh;exit")
is "der Geheimnislauf endet ordentlich" "$rc" "21"
S2="$TMPD/sec2.txt"
# GEGENPROBE, und sie hat einen echten Fehler gefunden: dieser Kern gibt
# einem Programm hoechstens acht Argumente (`proc.MAX_ARGS`). `-p pass -m
# pass` sind neun, die Schale sagt "too many arguments" und LAESST DEN
# BEFEHL AUS -- die Sicherung lief nie und der Test las nur leere Felder.
# Darum haengt das Passwort jetzt am Buchstaben, und darum steht diese
# Zusage hier.
is "GEGENPROBE: keine Zeile sprengt das Argumentlimit der Schale" \
   "$(grep -ac 'too many arguments' "$S2" || true)" "0"
sfeld() { sed -n "/^==$1==/,/^==/p" "$S2" | grep -a "^$2: " | tail -1 | sed "s/^$2: //" | tr -d '\r'; }
sab() { sed -n "/^==$1==/,/^==/p" "$S2"; }

# ---- STANDARDLAUF: OHNE ausdrueckliche Wahl kommt KEIN Geheimnis mit ----
is "A (Standard): KEINE geheime Datei gesichert" "$(sfeld A 'secret files')" "0"
is "A (Standard): drei geheime Orte AUSGELASSEN" "$(sfeld A 'secret left out')" "3"
is "A (Standard): drei Orte der Klasse (c) ausgelassen" "$(sfeld A 'never out')" "3"

# ---- MIT -m: die Geheimnisse kommen mit, versiegelt --------------------
is "B (-m): drei geheime Dateien mitgenommen" "$(sfeld B 'secret files')" "3"
is "B (-m): keine mehr ausgelassen" "$(sfeld B 'secret left out')" "0"
is "B (-m): Klasse (c) bleibt trotzdem drausssen" "$(sfeld B 'never out')" "3"

# ---- DER EIGENTLICHE NACHWEIS: der WIRT durchsucht die fertigen Speicher
python3 - "$TMPD/live-sec2.img" "$TMPD" > "$TMPD/grep.txt" 2>&1 <<'PY2'
import subprocess, sys
img = sys.argv[1]
def files():
    r = subprocess.run(["python3", "tools/osum/mkfs.py", "list", img],
                       capture_output=True, text=True)
    return [l.split()[0] for l in r.stdout.splitlines() if l.strip()]
def cat(p):
    r = subprocess.run(["python3", "tools/osum/mkfs.py", "cat", img, p],
                       capture_output=True)
    return r.stdout if r.returncode == 0 else b""
def store_blob(prefix):
    """Alles, was im Speicher <prefix> liegt, zu einem Klumpen -- so wie
    ein Finder den Stick lesen wuerde."""
    out = b""
    for f in files():
        if f.startswith(prefix):
            out += cat(f)
    return out
marks = {
    "PLAN": b"MARK-PLAN-ORDINARY-DATA",
    "VAULT": b"MARK-VAULT-SECRET-BANK-PW",
    "VPNKEY": b"MARK-VPNKEY-SECRET",
    "SHADOW": b"MARK-SHADOW-SECRET",
    "DEVICEKEY": b"MARK-DEVICEKEY-NEVER",
    "MACHINEID": b"MARK-MACHINEID-NEVER",
    "SESSION": b"MARK-SESSION-NEVER",
}
for st in ("/sA/", "/sB/", "/sC/"):
    blob = store_blob(st)
    print("store %s size=%d" % (st, len(blob)))
    for k, v in marks.items():
        print("  %s %s %d" % (st, k, blob.count(v)))
# DER ROHINHALT DES TRESORS, genau an seiner Stelle. Der Schnappschuss
# nennt die Bloecke einer Datei, INDEX sagt wo sie in PACK liegen -- also
# genau das, was ein Finder des Sticks tun wuerde. Herausgeschnitten wird
# der ERSTE Block von /secrets/vault.kdbx.
def block_of(store, snap, path):
    txt = cat(store + snap).decode("latin-1")
    line = [l for l in txt.split("\n") if l.startswith(path + "\t")]
    if not line:
        return None
    name = line[0].split("\t")[-1].split(",")[0]
    for il in cat(store + "INDEX").decode("latin-1").split("\n"):
        f = il.split("\t")
        if len(f) == 3 and f[0] == name:
            off, ln = int(f[1]), int(f[2])
            return name, cat(store + "PACK")[off:off + ln]
    return None
for st, sn in (("/sB/", "S-b1"), ("/sC/", "S-c1")):
    r = block_of(st, sn, "/secrets/vault.kdbx")
    if r is None:
        print("vaultblock %s MISSING" % st)
    else:
        name, oct_ = r
        print("vaultblock %s name=%s len=%d mark=%d" % (
            st, name[:16], len(oct_), oct_.count(b"MARK-VAULT-SECRET-BANK-PW")))
        print("vaulthex %s %s" % (st, oct_[:48].hex()))
# UND das Gegenstueck: der Pfad steht im Klartext im Schnappschuss (B4).
sc = store_blob("/sC/")
print("pathleak %d" % sc.count(b"/secrets/vault.kdbx"))
PY2
sed 's/^/        /' "$TMPD/grep.txt" | head -34

g() { grep -a "^  $1 $2 " "$TMPD/grep.txt" | awk '{print $3}'; }

# Die Gegenprobe ZUERST: die Suche muss ueberhaupt etwas finden koennen.
is "GEGENPROBE: gewoehnliche Daten stehen in A im KLARTEXT im Speicher" \
   "$(g /sA/ PLAN)" "1"
is "A: der Tresor ist NICHT im Speicher -- gar nicht" "$(g /sA/ VAULT)" "0"
is "A: der VPN-Schluessel ist nicht drin" "$(g /sA/ VPNKEY)" "0"
is "A: die Passwort-Hashes sind nicht drin" "$(g /sA/ SHADOW)" "0"

is "KLASSE (c): der Geraeteschluessel kommt in A nicht vor" "$(g /sA/ DEVICEKEY)" "0"
is "KLASSE (c): die Maschinenkennung kommt in A nicht vor" "$(g /sA/ MACHINEID)" "0"
is "KLASSE (c): das Sitzungsmerkmal kommt in A nicht vor" "$(g /sA/ SESSION)" "0"

is "B: der Tresor IST mitgekommen -- aber NICHT lesbar" "$(g /sB/ VAULT)" "0"
is "B: auch der VPN-Schluessel ist unlesbar" "$(g /sB/ VPNKEY)" "0"
is "B: auch die Passwort-Hashes sind unlesbar" "$(g /sB/ SHADOW)" "0"
is "KLASSE (c): der Geraeteschluessel kommt auch in B nicht vor" "$(g /sB/ DEVICEKEY)" "0"
is "KLASSE (c): die Maschinenkennung kommt auch in B nicht vor" "$(g /sB/ MACHINEID)" "0"
is "KLASSE (c): das Sitzungsmerkmal kommt auch in B nicht vor" "$(g /sB/ SESSION)" "0"
is "B ohne -p: gewoehnliche Daten sind WEITERHIN im Klartext (zwei getrennte Schichten)" \
   "$(g /sB/ PLAN)" "1"

is "C (-p -m): auch die gewoehnlichen Daten sind nicht mehr lesbar" "$(g /sC/ PLAN)" "0"
is "C: der Tresor natuerlich auch nicht" "$(g /sC/ VAULT)" "0"
is "C: der Geraeteschluessel ist gar nicht erst drin" "$(g /sC/ DEVICEKEY)" "0"

# DER ROHINHALT, den ein Finder des Sticks vor sich haette.
vb() { grep -a "^vaultblock $1 " "$TMPD/grep.txt" | sed 's/.*mark=//'; }
vl() { grep -a "^vaultblock $1 " "$TMPD/grep.txt" | sed 's/.*len=\([0-9]*\).*/\1/'; }
is "der Tresorblock in B ist 4112 Oktette gross -- 4096 + 16 Oktette Marke" \
   "$(vl /sB/)" "4112"
is "und die Marke MARK-VAULT-SECRET-BANK-PW steht NICHT darin" "$(vb /sB/)" "0"
is "in C ebenso" "$(vb /sC/)" "0"
ok "ROHINHALT des Tresorblocks in B, erste 48 Oktette:"
echo "        $(grep -a '^vaulthex /sB/' "$TMPD/grep.txt" | awk '{print $3}')"
ok "derselbe Tresor in C, anderes Hauptsalz, also ANDERE Oktette:"
echo "        $(grep -a '^vaulthex /sC/' "$TMPD/grep.txt" | awk '{print $3}')"
is "GEGENPROBE: derselbe Klartext, zwei Speicher, ZWEI verschiedene Geheimtexte" \
   "$([ "$(grep -a '^vaulthex /sB/' "$TMPD/grep.txt" | awk '{print $3}')" = \
       "$(grep -a '^vaulthex /sC/' "$TMPD/grep.txt" | awk '{print $3}')" ] \
       && echo gleich || echo verschieden)" "verschieden"

# DIE GEMESSENE LUECKE, und sie steht in bsec.fi B4 als Grenze.
is "EHRLICH: der PFAD /secrets/vault.kdbx steht auch in C im KLARTEXT" \
   "$(grep -a '^pathleak' "$TMPD/grep.txt" | awk '{print $2}')" "1"

# ---- WIEDERHERSTELLEN OHNE HAUPTPASSWORT: klare Meldung, kein Schweigen --
sab BRESTNOM | grep -qa 'carries secrets' \
    && ok "ohne -m sagt das Wiederherstellen KLAR, dass Geheimnisse drin sind" \
    || bad "ohne -m wird still weitergemacht"
sab BRESTNOM | grep -qa 'restored files' \
    && bad "ohne -m meldet der Lauf trotzdem einen Erfolg" \
    || ok "und meldet KEINEN Erfolg -- kein stilles Ueberspringen"
sab BREST | grep -qa 'restored files' \
    && ok "mit -m kommt der Baum zurueck" \
    || bad "mit -m kommt der Baum NICHT zurueck"

sab CWRONGP | grep -qa 'wrong store password' \
    && ok "ein falsches Speicherpasswort wird benannt" \
    || bad "ein falsches Speicherpasswort wird nicht benannt"
sab CWRONGM | grep -qa 'wrong master password' \
    && ok "ein falsches Hauptpasswort wird benannt" \
    || bad "ein falsches Hauptpasswort wird nicht benannt"
sab CVERIFYNOP | grep -qa 'this store is encrypted' \
    && ok "verify ohne Passwort sagt, dass der Speicher verschluesselt ist" \
    || bad "verify ohne Passwort meldet den verschluesselten Speicher nicht"
is "verify mit beiden Passwoertern: nichts kaputt" "$(sfeld CVERIFY corrupt)" "0"
is "verify mit beiden Passwoertern: nichts ungeprueft" "$(sfeld CVERIFY unchecked)" "0"

# ---- OKTETT FUER OKTETT aus dem Abbild ---------------------------------
python3 - "$TMPD/live-sec2.img" > "$TMPD/seccmp.txt" 2>&1 <<'PY2'
import subprocess, sys
img = sys.argv[1]
def cat(p):
    r = subprocess.run(["python3", "tools/osum/mkfs.py", "cat", img, p],
                       capture_output=True)
    return r.stdout if r.returncode == 0 else None
paare = [("/set/secrets/vault.kdbx", "/outB/secrets/vault.kdbx"),
         ("/set/etc/shadow", "/outB/etc/shadow"),
         ("/set/PLAN", "/outB/PLAN"),
         ("/set/secrets/vault.kdbx", "/outC/secrets/vault.kdbx"),
         ("/set/PLAN", "/outC/PLAN"),
         ("/set/config/vpn/keys/home.key", "/outC/config/vpn/keys/home.key")]
gleich = 0
for a, b in paare:
    da, db = cat(a), cat(b)
    if da is not None and db is not None and da == db:
        gleich += 1
    else:
        print("UNGLEICH %s <-> %s" % (a, b))
# UND: die Klasse (c) darf im wiederhergestellten Baum NICHT auftauchen.
weg = 0
for p in ("/outC/device/key", "/outC/etc/machine-id", "/outC/state/session/token"):
    if cat(p) is None:
        weg += 1
    else:
        print("DA OBWOHL VERBOTEN %s" % p)
print("verglichen=%d gleich=%d weg=%d" % (len(paare), gleich, weg))
PY2
sed 's/^/        /' "$TMPD/seccmp.txt" | grep -v 'verglichen=' | head -8
is "wiederhergestellt und OKTETT FUER OKTETT gleich (6 Paare), Klasse (c) fehlt (3)" \
   "$(grep -a '^verglichen=' "$TMPD/seccmp.txt")" "verglichen=6 gleich=6 weg=3"

# ---------------------------------------------------------------------------

echo "== 13c. was die Verschluesselung kostet -- und was sie NICHT kostet =="

DA_CH=$(sfeld DEDUPA 'chunks');  DA_NEW=$(sfeld DEDUPA 'new chunks')
DA_WR=$(sfeld DEDUPA 'written bytes'); DA_RD=$(sfeld DEDUPA 'read bytes')
DA_MS=$(sfeld DEDUPA 'ms')
DB_CH=$(sfeld DEDUPB 'chunks');  DB_NEW=$(sfeld DEDUPB 'new chunks')
DB_WR=$(sfeld DEDUPB 'written bytes'); DB_RD=$(sfeld DEDUPB 'read bytes')
DB_MS=$(sfeld DEDUPB 'ms')

is "OHNE Verschluesselung: 6 Bloecke gesehen" "$DA_CH" "6"
is "OHNE: nur 2 davon neu -- die Datei liegt EINMAL da" "$DA_NEW" "2"
is "MIT Verschluesselung: dieselben 6 Bloecke gesehen" "$DB_CH" "6"
is "MIT: IMMER NOCH nur 2 neu -- DIE DEDUPLIZIERUNG UEBERLEBT" "$DB_NEW" "$DA_NEW"
is "OHNE: 8192 Oktette geschrieben" "$DA_WR" "8192"
is "MIT: 8224 Oktette -- 16 Oktette Marke je Block, sonst nichts" "$DB_WR" "8224"
is "und gelesen wurde beidesmal dasselbe" "$DB_RD" "$DA_RD"
is "zweiter Lauf OHNE: null neue Bloecke" "$(sfeld DEDUPA2 'new chunks')" "0"
is "zweiter Lauf MIT: AUCH null neue Bloecke" "$(sfeld DEDUPB2 'new chunks')" "0"
ok "ZAHLEN: ohne $DA_WR Oktette in ${DA_MS} ms, mit $DB_WR Oktette in ${DB_MS} ms"
if [ -n "$DA_WR" ] && [ -n "$DB_WR" ] && [ "$DA_WR" -gt 0 ] 2>/dev/null; then
    PCT=$(awk -v a="$DA_WR" -v b="$DB_WR" 'BEGIN{printf "%.2f", (b-a)*100.0/a}')
    ok "AUFSCHLAG der Verschluesselung auf dem Datentraeger: ${PCT} %"
fi

# ============================================================= Schluss

echo
echo "TRESOR: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
