#!/usr/bin/env bash
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

bash vendor/firn/hole-firnc.sh >/dev/null || { echo "hole-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "TRESOR: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

PROGS="sh ls cat echo hwid shat bak key"

# ============================================================ 1. bauen

echo "== 1. bauen: der Kern, die Programme, die Speicherkarte =="

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "firnc0 baut den Kern mit hwid" \
    || { bad "firnc0 baut den Kern nicht"; sed 's/^/        /' "$TMPD/b0.txt" | head -10; }
[ -f "$TMPD/k0.img" ] || { echo "TRESOR: $pass passed, $((fail+1)) failed"; exit 1; }

bash tools/tresor/bauen.sh "$TMPD/bin" 0 $PROGS > "$TMPD/bprog.txt" 2>&1 \
    && ok "firnc0 baut $(echo $PROGS | wc -w) Programme in Ring 3" \
    || { bad "firnc0 baut nicht alle Programme"; sed 's/^/        /' "$TMPD/bprog.txt" | head -12; }

undef=""
for p in hwid bak key shat; do
    [ -f "$TMPD/bin/$p.elf" ] || continue
    u=$(nm -u "$TMPD/bin/$p.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "kein neues Programm hat ein undefiniertes Symbol" \
               || bad "undefinierte Symbole:$undef"

if python3 tools/kernel/karte.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "$(tail -1 "$TMPD/karte.txt")"
else
    bad "der Kartenpruefer schlaegt an"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi
grep -q '"HWID_OFF"' tools/kernel/karte.py \
    && ok "der Bereich dieser Runde (0x5A000..0x5C000) steht in der Karte" \
    || bad "HWID_OFF fehlt in tools/kernel/karte.py"

# GEGENPROBE: der Bereich auf die Seite von K18 gelegt MUSS auffallen.
mkdir -p "$TMPD/kbad" && cp kernel/*.fi "$TMPD/kbad/"
sed -i 's/^const HWID_OFF: u64 = 0x5A000/const HWID_OFF: u64 = 0x59000/' "$TMPD/kbad/kstate.fi"
if python3 tools/kernel/karte.py "$TMPD/kbad" > "$TMPD/karte-bad.txt" 2>&1; then
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
    timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.img" -m 256 \
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
    timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.img" -m 256 \
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

cat > "$TMPD/t_bak.sh" <<'EOS'
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
python3 tools/osum/mkfs.py build "$TMPD/dbak.img" $BLOCKS \
    /bin/ /t/ /d/ /d/sub/ /d/sub/deep/ /store/ /out/ /proc/ /dev/ \
    /bin/sh="$TMPD/bin/sh.elf" /bin/cat="$TMPD/bin/cat.elf" \
    /bin/echo="$TMPD/bin/echo.elf" /bin/ls="$TMPD/bin/ls.elf" \
    /bin/backup="$TMPD/bin/bak.elf" \
    /d/a.txt="$TMPD/baum/a.txt" /d/rand.bin="$TMPD/baum/rand.bin" /d/empty.txt= \
    /d/sub/copy.txt="$TMPD/baum/sub/copy.txt" \
    /d/sub/deep/small.txt="$TMPD/baum/sub/deep/small.txt" \
    /t/bak.sh="$TMPD/t_bak.sh" > "$TMPD/mkfs-bak.txt" 2>&1 \
    && ok "mkfs.py baut den Quellbaum" || bad "mkfs.py fehlgeschlagen"

rc=$(lauf bak "$TMPD/dbak.img" "osum vfs nokbd script=sh /t/bak.sh;exit")
is "der Sicherungslauf endet ordentlich" "$rc" "21"
B="$TMPD/bak.txt"

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
python3 - "$TMPD/live-bak.img" > "$TMPD/vergleich.txt" 2>&1 <<'PY'
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
    /bin/echo="$TMPD/bin/echo.elf" /bin/backup="$TMPD/bin/bak.elf" \
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

# ============================================================= Schluss

echo
echo "TRESOR: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
