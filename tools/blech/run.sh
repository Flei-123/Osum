#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/blech/run.sh -- OSUM AUF FREMDEM BLECH.
#
# ==================================================================
# WARUM ES DIESEN ABSCHNITT GIBT
# ==================================================================
#
# Der Bericht der Runde MERGE-3 (docs/RUNDE-MERGE3.md) hat drei Saetze
# aufgeschrieben, die diese Runde einzeln widerlegt:
#
#   1. "Die automatische Treiberwahl beim Start ist nicht gebaut --
#       welches Geraet die Wurzel traegt, entscheidet die
#       Kommandozeile." Nachgelesen: `osum_stage` ruft `blk.use_ata`,
#       und `root_from_part` ruft `part.scan(state, blk.DEV_ATA)`. Auf
#       einem PC mit NVMe-Riegel endet der Start mit "osum: no drive".
#   2. "SATA im RAID-Modus -- dann findet Osum keine Platte." Richtig,
#       und bis zu dieser Runde SAGTE der Kern es nicht. Ein Notebook,
#       dessen Firmware ab Werk auf Intel RST steht, zeigt eine leere
#       Plattenliste und keinen Grund.
#   3. "Jeder Rechner seit ~2012 hat xHCI. Das ist der richtige und
#       einzige noetige Controller." Der erste Teil stimmt. Ein Rechner
#       VOR 2012 hat gar kein xHCI, und dort ist jeder USB-Anschluss
#       tot.
#
# ==================================================================
# WAS HIER GEMESSEN WIRD -- UND WOMIT ES SICH WIDERLEGEN LIESSE
# ==================================================================
#
#   1. DIE WURZEL WIRD GESUCHT. Dieselbe Maschine, ZWEI Kerne: der vom
#      Abzweigpunkt und der dieser Runde. Auf einer Maschine, deren
#      einzige Platte ein NVMe-Riegel mit einem OFS darauf ist, muss der
#      ALTE "osum: no drive" sagen und der NEUE die Wurzel einhaengen.
#      Ohne den alten Kern daneben waere die Zusage nicht nachweisbar --
#      vielleicht haette der alte es ja auch gekonnt.
#   2. UND SIE WIRD NICHT GERATEN. Steht neben der leeren NVMe-Platte
#      eine AHCI-Platte MIT System, muss die AHCI-Platte gewinnen. Ein
#      Bewerber, der nur DA ist, gewinnt nicht.
#   3. UND DER ALTE WEG BLEIBT DER ERSTE. Mit einer IDE-Platte, die
#      traegt, darf die neue Suche NULL Mal laufen. Das ist die Zusage,
#      an der die 54 bestehenden Abschnitte haengen, und sie wird durch
#      ZAEHLEN belegt.
#   4. DER RAID-MODUS WIRD BENANNT. `-device megasas` ist ein Controller
#      der Klasse 01:04, also genau das, was Intel RST auf einem
#      Notebook hinstellt. Der Kern muss seine Nummern nennen UND sagen,
#      welche Einstellung im BIOS zu aendern ist.
#   5. EHCI: EIN STICK, UND DER WIRT RECHNET NACH. Drei Bloecke ueber
#      Bulk-Only-Transport; ihre gewichteten Oktettsummen rechnet DIESES
#      Skript aus demselben Abbild aus, aus dem QEMU liest. "Der Treiber
#      meldet Erfolg" ist keine Messung.
#   6. EHCI: EINE TASTATUR, UND ES SIND DIE RICHTIGEN CODES. Geprueft
#      wird nicht die ZAHL der Tasten, sondern die FOLGE der Abtastcodes
#      gegen den AT-Satz 1.
#   7. NVMe MIT DREI NAMENSRAEUMEN, und der dritte hat ABSICHTLICH die
#      Nummer 7. Eine Liste, die "1,2,3,..." annimmt, faellt hier auf.
#   8. GEGENPROBEN. Ohne das Wort `ehci` gibt es keinen Treiber; ohne
#      Regler eine Meldung statt eines Haengers; mit einem anderen
#      Regler (ich9-usb-ehci1 auf q35) dieselben Zahlen.
#
# Aufruf:  bash tools/blech/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "BLECH: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

TMPD=$(mktemp -d)
ALTD=""
aufraeumen() {
    [ -n "$ALTD" ] && git worktree remove --force "$ALTD" >/dev/null 2>&1
    rm -rf "$TMPD"
}
trap aufraeumen EXIT

echo "== 0. der Wirt =="
hin "QEMU: $(qemu-system-x86_64 --version | head -1)"
hin "Beschleuniger: $OSUM_QEMU_ACCEL"

# ------------------------------------------------------------ die Kerne
#
# ZWEI Kerne, und der zweite ist der Sinn des Abschnitts: der Stand des
# Abzweigpunkts als Vergleichsmass. Ohne ihn waere jede Zusage dieser
# Runde die BEHAUPTUNG, dass der alte Kern etwas nicht konnte.
bash tools/build-kernel.sh "$TMPD/neu.mb" --stufe 0 >"$TMPD/b1.txt" 2>&1 \
    && ok "der Kern dieser Runde ist gebaut ($(stat -c%s "$TMPD/neu.mb") Oktette)" \
    || { bad "der Kern liess sich nicht bauen"; sed 's/^/        /' "$TMPD/b1.txt" | head -5; }

VOR=$(git merge-base HEAD main 2>/dev/null || echo "")
ALT=""
if [ -n "$VOR" ]; then
    ALTD="$TMPD/alt"
    if git worktree add --detach "$ALTD" "$VOR" >"$TMPD/wt.txt" 2>&1; then
        cp -a vendor/firn/bin "$ALTD/vendor/firn/bin" 2>/dev/null
        cp -a vendor/firn/lib "$ALTD/vendor/firn/lib" 2>/dev/null
        cp -a vendor/firn/.gebaut "$ALTD/vendor/firn/.gebaut" 2>/dev/null
        if ( cd "$ALTD" && bash tools/build-kernel.sh "$TMPD/alt.mb" --stufe 0 ) \
                >"$TMPD/b0.txt" 2>&1; then
            ALT="$TMPD/alt.mb"
            ok "der Kern des Abzweigpunkts ist gebaut ($(stat -c%s "$ALT") Oktette, ${VOR:0:8})"
        else
            hin "der alte Kern liess sich nicht bauen -- der Vergleich faellt aus"
        fi
    fi
fi

# Die Speicherkarte. Diese Runde nimmt VIER Seiten aus `kdata` -- drei
# fuer den EHCI, eine fuer die Wurzelwahl -- und genau an dieser Stelle
# hat das Projekt viermal dieselbe Kollision gebaut.
if python3 tools/kernel/memmap.py >"$TMPD/map.txt" 2>&1; then
    ok "die Speicherkarte von kdata ist kollisionsfrei -- $(cat "$TMPD/map.txt")"
else
    bad "die Speicherkarte kollidiert"
    sed 's/^/        /' "$TMPD/map.txt" | head -10
fi

# ------------------------------------------------------- die Programme
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null
for p in sh ls cat echo; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$p.fi uebersetzt nicht"; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null \
        || bad "$p liess sich nicht binden"
done
python3 tools/osum/mkfs.py build "$TMPD/root.img" 8192 /bin/ \
    "/bin/sh=$TMPD/sh.elf" "/bin/ls=$TMPD/ls.elf" \
    "/bin/cat=$TMPD/cat.elf" "/bin/echo=$TMPD/echo.elf" \
    >"$TMPD/mkfs.txt" 2>&1 \
    && ok "ein OFS-Wurzelabbild von 8192 Bloecken, mit /bin/sh darin" \
    || { bad "mkfs.py"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -3; }

lauf() { # $1 = Abbild, $2 = Kommandozeile, $3 = Ausgabe, Rest = QEMU
    local img=$1 app=$2 out=$3
    shift 3
    timeout 180 $QEMU_X86 -kernel "$img" -m 256 -append "$app" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

hat() { grep -qaF -- "$2" "$1" && ok "$3" || {
    bad "$3"; printf '        (fehlt: %s)\n' "$2"; }; }
hatnicht() { grep -qaF -- "$2" "$1" && bad "$3" || ok "$3"; }
wert() { grep -oaE "$2" "$1" | tail -1 | grep -oaE '[0-9]+$'; }

# =====================================================================
echo "== 1. die Wurzel wird gesucht: nur ein NVMe-Riegel, nichts an 0x1F0 =="
# =====================================================================
cp "$TMPD/root.img" "$TMPD/nv-alt.img"
cp "$TMPD/root.img" "$TMPD/nv-neu.img"

if [ -n "$ALT" ]; then
    lauf "$ALT" "osum nokbd" "$TMPD/1alt.txt" \
        -drive "file=$TMPD/nv-alt.img,format=raw,if=none,id=d0" \
        -device "nvme,drive=d0,serial=blech"
    hat "$TMPD/1alt.txt" "osum: no drive" \
        "DER ALTE KERN findet die Platte nicht -- 'osum: no drive'"
    hatnicht "$TMPD/1alt.txt" "osum: mount=1" \
        "DER ALTE KERN haengt nichts ein"
fi
lauf "$TMPD/neu.mb" "osum nokbd" "$TMPD/1neu.txt" \
    -drive "file=$TMPD/nv-neu.img,format=raw,if=none,id=d0" \
    -device "nvme,drive=d0,serial=blech"
rc=$?
[ "$rc" -eq 21 ] && ok "der neue Kern kommt bis zum Ende (21)" \
                 || bad "der neue Kern endet mit $rc statt 21"
hat "$TMPD/1neu.txt" "rootsel: nvme -- WURZEL" \
    "DER NEUE KERN nimmt den NVMe-Riegel als Wurzel"
hat "$TMPD/1neu.txt" "osum: mount=1" "und haengt sie ein"
hat "$TMPD/1neu.txt" "sh:1" "und /bin/sh liegt darin"
hat "$TMPD/1neu.txt" "osum: sh exit=0" "und die Shell laeuft und endet sauber"

# =====================================================================
echo "== 2. ein Bewerber, der nur DA ist, gewinnt nicht =="
# =====================================================================
dd if=/dev/zero of="$TMPD/leer.img" bs=1M count=8 2>/dev/null
cp "$TMPD/root.img" "$TMPD/ah.img"
lauf "$TMPD/neu.mb" "osum nokbd" "$TMPD/2.txt" \
    -drive "file=$TMPD/leer.img,format=raw,if=none,id=n0" \
    -device "nvme,drive=n0,serial=leer" \
    -device "ahci,id=a0" \
    -drive "file=$TMPD/ah.img,format=raw,if=none,id=d1" \
    -device "ide-hd,drive=d1,bus=a0.0"
hat "$TMPD/2.txt" "rootsel: nvme -- keine Wurzel darauf" \
    "die LEERE NVMe-Platte wird abgelehnt, obwohl sie zuerst drankommt"
hat "$TMPD/2.txt" "rootsel: ahci -- WURZEL" \
    "und die AHCI-Platte mit dem System gewinnt"
hat "$TMPD/2.txt" "osum: mount=1" "eingehaengt"

# =====================================================================
echo "== 3. GEGENPROBE: mit einer IDE-Wurzel laeuft die Suche NULL Mal =="
# =====================================================================
cp "$TMPD/root.img" "$TMPD/ide.img"
dd if=/dev/zero of="$TMPD/leer2.img" bs=1M count=8 2>/dev/null
lauf "$TMPD/neu.mb" "osum nokbd" "$TMPD/3.txt" \
    -drive "file=$TMPD/ide.img,format=raw,if=ide,index=0" \
    -drive "file=$TMPD/leer2.img,format=raw,if=none,id=n0" \
    -device "nvme,drive=n0,serial=leer"
n=$(grep -ca 'rootsel: versuch' "$TMPD/3.txt")
[ "$n" -eq 0 ] && ok "kein einziger Versuch der neuen Suche (0) -- der alte Weg trug" \
               || bad "die neue Suche lief $n Mal, obwohl der alte Weg trug"
hat "$TMPD/3.txt" "osum: mount=1" "und die Wurzel steht"

# =====================================================================
echo "== 4. der RAID-Modus wird beim Namen genannt =="
# =====================================================================
lauf "$TMPD/neu.mb" "hwdiag nokbd nosched noproc nofs noring3" "$TMPD/4.txt" \
    -device megasas -device sdhci-pci \
    -drive "file=$TMPD/leer.img,format=raw,if=none,id=n0" \
    -device "nvme,drive=n0,serial=x" -device "ahci,id=a0"
# NACHTRAG RUNDE BLECH: diese vier Zeilen kommen jetzt aus
# `kernel/blkdev.fi` statt aus `rootsel.fi` -- der Schicht, die fuer
# Speicher dasselbe ist wie `netdev.fi` fuer Netz.  Die AUSSAGE ist
# dieselbe geblieben und um den Chipnamen reicher; nur die Vorsilbe
# heisst jetzt `blkdev:` und nicht mehr `rootsel:`.
hat "$TMPD/4.txt" "RAID-Modus" \
    "ein Controller der Klasse 01:04 wird als RAID-Modus erkannt"
hat "$TMPD/4.txt" "1000:0060" "und mit SEINEN NUMMERN genannt"
hat "$TMPD/4.txt" "MegaRAID" "und mit seinem NAMEN"
hat "$TMPD/4.txt" 'im BIOS "SATA Mode" auf AHCI stellen' \
    "und es steht daneben, was zu tun ist"
hat "$TMPD/4.txt" "SD/eMMC-Regler" "der SD-Regler ebenfalls"
hat "$TMPD/4.txt" "blkdev: reihenfolge: nvme > ahci > ide" \
    "und die Reihenfolge, in der gesucht wird, steht in EINER Zeile"

# =====================================================================
echo "== 5. EHCI: ein Stick, und der Wirt rechnet die Bloecke nach =="
# =====================================================================
dd if=/dev/urandom of="$TMPD/stick.img" bs=512 count=2048 2>/dev/null
python3 - "$TMPD/stick.img" > "$TMPD/summen.txt" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
for lba in (0, 1, 64):
    b = d[lba * 512:(lba + 1) * 512]
    print(lba, sum(v * (i + 1) for i, v in enumerate(b)), b[0])
PY
lauf "$TMPD/neu.mb" "ehci ehcitest nokbd nosched noproc nofs noring3" \
    "$TMPD/5.txt" -device "usb-ehci,id=eh" \
    -drive "file=$TMPD/stick.img,format=raw,if=none,id=st" \
    -device "usb-storage,bus=eh.0,drive=st"
hat "$TMPD/5.txt" "handoff=1" \
    "die Firmware hat den Regler abgegeben (EHCI-Spezifikation 5.1)"
hat "$TMPD/5.txt" "speed=2" "an Anschluss 0 haengt ein Hochgeschwindigkeitsgeraet"
hat "$TMPD/5.txt" "msc blocks=2048  bsize=512" \
    "READ CAPACITY (10): 2048 Bloecke zu 512 Oktett -- die Groesse des Abbilds"
e=$(wert "$TMPD/5.txt" 'fehler=[0-9]+')
[ "${e:-9}" -eq 0 ] && ok "keine Uebertragung ist fehlgeschlagen (fehler=0)" \
                    || bad "fehlgeschlagene Uebertragungen: ${e:-?}"
while read -r lba summe erstes; do
    if grep -qa "selftest lba=$lba  ok=1  sum=$summe  first=$erstes" "$TMPD/5.txt"; then
        ok "Block $lba: Oktett fuer Oktett das, was der WIRT im Abbild hat (sum=$summe)"
    else
        bad "Block $lba: erwartet sum=$summe first=$erstes"
        grep -a "selftest lba=$lba" "$TMPD/5.txt" | sed 's/^/        /'
    fi
done < "$TMPD/summen.txt"

# =====================================================================
echo "== 6. EHCI: eine Tastatur, und es sind die RICHTIGEN Codes =="
# =====================================================================
# h a l l o Eingabe im Abtastcodesatz 1. Die Werte stehen NICHT aus dem
# Kernel hier, sondern aus der AT-Tabelle -- sonst pruefte sich der
# Uebersetzer selbst.
ERWARTET="23 1e 26 26 18 1c"
( sleep 8
  for k in h a l l o ret; do echo "sendkey $k"; sleep 0.3; done
  sleep 22; echo quit ) | \
timeout 180 $QEMU_X86 -kernel "$TMPD/neu.mb" -m 256 \
    -append "ehci ehcitest nokbd nosched noproc nofs noring3" \
    -serial "file:$TMPD/6.txt" -display none -no-reboot -monitor stdio \
    -device "usb-ehci,id=eh" -device "usb-kbd,bus=eh.0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
hat "$TMPD/6.txt" "klasse=1" "die Tastatur wird als Tastatur erkannt"
t=$(wert "$TMPD/6.txt" 'tasten=[0-9]+')
[ "${t:-0}" -eq 6 ] && ok "sechs Tasten sind durch kbd.on_code gegangen (6)" \
                    || bad "Tasten: ${t:-0}, erwartet 6"
if grep -qa "ehci: codes $ERWARTET" "$TMPD/6.txt"; then
    ok "und es sind DIESE sechs: $ERWARTET (h a l l o Eingabe, AT-Satz 1)"
else
    bad "die Abtastcodes stimmen nicht -- erwartet: $ERWARTET"
    grep -a 'ehci: codes' "$TMPD/6.txt" | sed 's/^/        /'
fi
p=$(wert "$TMPD/6.txt" 'abfragen=[0-9]+')
[ "${p:-0}" -ge 500 ] && ok "der Endpunkt wurde $p Mal abgefragt (kein eigener Vektor)" \
                      || bad "zu wenige Abfragen: ${p:-0}"

# =====================================================================
echo "== 6b. ZWEI Geraete am selben Regler -- Tastatur UND Stick =="
# =====================================================================
# Das ist die Messung, die den zweiten eigenen Fehler dieser Runde
# festhaelt: der Geraetesatz war 64 Oktett gross, und vier seiner
# Felder (Hersteller, Erzeugnis, Umschaltbit hinaus, Paketgroesse
# hinein) lagen bei 0x40..0x58 -- also im Platz des NAECHSTEN Geraets.
# Mit EINEM Geraet am Regler faellt das nie auf. Mit zweien traegt die
# Tastatur die Herstellernummer des Sticks.
( sleep 8
  for k in h a l l o ret; do echo "sendkey $k"; sleep 0.3; done
  sleep 22; echo quit ) | \
timeout 180 $QEMU_X86 -kernel "$TMPD/neu.mb" -m 256 \
    -append "ehci ehcitest nokbd nosched noproc nofs noring3" \
    -serial "file:$TMPD/6b.txt" -display none -no-reboot -monitor stdio \
    -device "usb-ehci,id=eh" -device "usb-kbd,bus=eh.0" \
    -drive "file=$TMPD/stick.img,format=raw,if=none,id=st2" \
    -device "usb-storage,bus=eh.0,drive=st2" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
hat "$TMPD/6b.txt" "dev 0  addr=1  klasse=1  0627:0001" \
    "Geraet 0 ist die Tastatur, mit IHRER Herstellernummer"
hat "$TMPD/6b.txt" "dev 1  addr=2  klasse=3  46f4:0001" \
    "Geraet 1 ist der Stick, mit SEINER -- die Saetze ueberschreiben sich nicht"
n=$(wert "$TMPD/6b.txt" 'enum=[0-9]+')
[ "${n:-0}" -eq 2 ] && ok "beide sind aufgezaehlt (enum=2)" \
                    || bad "aufgezaehlt: ${n:-0}, erwartet 2"
if grep -qa "ehci: codes $ERWARTET" "$TMPD/6b.txt"; then
    ok "die Tastatur liefert weiterhin die richtigen Codes, mit dem Stick daneben"
else
    bad "mit zwei Geraeten stimmen die Abtastcodes nicht mehr"
    grep -a 'ehci: codes' "$TMPD/6b.txt" | sed 's/^/        /'
fi
while read -r lba summe erstes; do
    grep -qa "selftest lba=$lba  ok=1  sum=$summe" "$TMPD/6b.txt" \
        && ok "und Block $lba kommt weiterhin Oktett fuer Oktett richtig an" \
        || bad "mit zwei Geraeten weicht Block $lba ab"
done < "$TMPD/summen.txt"

# =====================================================================
echo "== 7. NVMe mit drei Namensraeumen, der dritte mit der Nummer 7 =="
# =====================================================================
python3 - "$TMPD" > "$TMPD/nssummen.txt" <<'PY'
import sys, os
d = sys.argv[1]
for name, mib, seed in (("a", 8, 7), ("b", 4, 23), ("c", 2, 99)):
    p = os.path.join(d, "ns%s.img" % name)
    buf = bytearray(mib * 1024 * 1024)
    for i in range(512):
        buf[i] = (seed * (i + 3)) % 256
    open(p, "wb").write(bytes(buf))
    b = bytes(buf[:512])
    print(name, mib * 2048, sum(v * (i + 1) for i, v in enumerate(b)))
PY
lauf "$TMPD/neu.mb" "nvme nokbd nosched noproc nofs noring3" "$TMPD/7.txt" \
    -device "nvme,serial=drei,id=nv" \
    -drive "file=$TMPD/nsa.img,format=raw,if=none,id=d1" \
    -device "nvme-ns,drive=d1,bus=nv,nsid=1" \
    -drive "file=$TMPD/nsb.img,format=raw,if=none,id=d2" \
    -device "nvme-ns,drive=d2,bus=nv,nsid=2" \
    -drive "file=$TMPD/nsc.img,format=raw,if=none,id=d3" \
    -device "nvme-ns,drive=d3,bus=nv,nsid=7"
hat "$TMPD/7.txt" "nvme: ns count=3  in list=3" "alle drei Namensraeume gefunden"
hat "$TMPD/7.txt" "ns2 nsid=7" \
    "auch der mit der Nummer 7 -- die Liste wird gelesen und nicht gezaehlt"
i=0
while read -r name blocks summe; do
    if grep -qa "ns$i nsid=.*blocks=$blocks " "$TMPD/7.txt"; then
        ok "Namensraum $i: $blocks Bloecke, wie das Abbild gross ist"
    else
        bad "Namensraum $i: erwartet blocks=$blocks"
    fi
    if grep -qa "ns$i nsid=.*lba0=1  sum=$summe" "$TMPD/7.txt"; then
        ok "Namensraum $i: Block 0 ist Oktett fuer Oktett der des Wirtes (sum=$summe)"
    else
        bad "Namensraum $i: erwartet sum=$summe"
        grep -a "ns$i nsid=.*sum=" "$TMPD/7.txt" | sed 's/^/        /'
    fi
    i=$((i+1))
done < "$TMPD/nssummen.txt"

# =====================================================================
echo "== 8. die Gegenproben, in denen die Messung zusammenbrechen muss =="
# =====================================================================
lauf "$TMPD/neu.mb" "nokbd nosched noproc nofs noring3" "$TMPD/8a.txt" \
    -device "usb-ehci,id=eh" -device "usb-kbd,bus=eh.0"
hat "$TMPD/8a.txt" "ehci: skipped" \
    "GEGENPROBE ohne das Wort 'ehci': kein Treiber, obwohl der Regler dasteht"
hatnicht "$TMPD/8a.txt" "ehci: dev 0" "und kein Geraet wird aufgezaehlt"

lauf "$TMPD/neu.mb" "ehci nokbd nosched noproc nofs noring3" "$TMPD/8b.txt"
hat "$TMPD/8b.txt" "ehci: kein EHCI auf dem Bus" \
    "GEGENPROBE mit dem Wort, aber ohne Regler: eine Meldung statt eines Haengers"

# Derselbe Treiber an einem ANDEREN Regler: der EHCI des ICH9 auf q35.
timeout 180 $QEMU_X86 -M q35 -kernel "$TMPD/neu.mb" -m 256 \
    -append "ehci ehcitest nokbd nosched noproc nofs noring3" \
    -serial "file:$TMPD/8c.txt" -display none -no-reboot \
    -device "ich9-usb-ehci1,id=eh" \
    -drive "file=$TMPD/stick.img,format=raw,if=none,id=st" \
    -device "usb-storage,bus=eh.0,drive=st" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
hat "$TMPD/8c.txt" "msc blocks=2048  bsize=512" \
    "derselbe Treiber an ich9-usb-ehci1 (q35): dieselbe Platte"
while read -r lba summe erstes; do
    grep -qa "selftest lba=$lba  ok=1  sum=$summe" "$TMPD/8c.txt" \
        && ok "q35/ich9: Block $lba ebenfalls Oktett fuer Oktett gleich" \
        || bad "q35/ich9: Block $lba weicht ab"
done < "$TMPD/summen.txt"

# =====================================================================
echo "== 9. was der Rechner ueber sich selbst sagt =="
# =====================================================================
lauf "$TMPD/neu.mb" "hwdiag nokbd nosched noproc nofs noring3" "$TMPD/9.txt"
hat "$TMPD/9.txt" "blkdev: reihenfolge: ide" \
    "die nackte Maschine: nur der IDE-Controller des PIIX3 bleibt uebrig"
lauf "$TMPD/neu.mb" "hwdiag nokbd nosched noproc nofs noring3" "$TMPD/9b.txt" \
    -device usb-ehci -device pci-ohci -device piix4-usb-uhci
hat "$TMPD/9b.txt" "usb EHCI" "ein EHCI wird als EHCI benannt"
hat "$TMPD/9b.txt" "usb OHCI" "ein OHCI wird als OHCI benannt"
hat "$TMPD/9b.txt" "usb UHCI" "ein UHCI wird als UHCI benannt"
hat "$TMPD/9b.txt" "(kein Treiber)" \
    "und bei OHCI/UHCI steht dabei, dass es dafuer keinen Treiber gibt"

# =====================================================================
echo "== 10. die zwei Nachrechner: Namen und 8125-Register =="
# =====================================================================
#
# WARUM SIE HIER STEHEN UND NICHT NUR IM VERZEICHNIS LIEGEN. Der Bericht
# der Runde hat sich selbst vorgeworfen, dass `fb.sh` gebaut, aber nie
# angemeldet wurde -- ein Pruefwerkzeug, das niemand aufruft, ist kein
# Pruefwerkzeug. Diese beiden pruefen genau das, was in dieser Runde
# NICHT ueber QEMU pruefbar ist:
#
#   chipnames.py  181 Namensbehauptungen gegen pci.ids und den
#                 Linux-Quelltext. Erster Lauf: 14 davon falsch.
#   r8125regs.py  den 8125-Zweig gegen r8169_main.c -- Adresse UND
#                 Zugriffsbreite UND Wert. Erster Lauf: der Sendeanstoss
#                 falsch, und auf echter Hardware waere kein Paket
#                 hinausgegangen.
#
# Beide laufen OHNE Netz, wenn ihre Vorlagen unter /tmp liegen; fehlen
# sie, holen sie sie einmal. Ohne Netz und ohne Vorlage werden sie
# UEBERSPRUNGEN und sagen das -- ein Abnahmelauf darf nicht an einer
# fehlenden Internetverbindung scheitern, aber er darf sie auch nicht
# verschweigen.

if python3 tools/blech/chipnames.py >"$TMPD/chipnames.txt" 2>&1; then
    n=$(grep -oaE 'BESTAETIGT[^0-9]*([0-9]+)' "$TMPD/chipnames.txt" | grep -oaE '[0-9]+$')
    ok "chipname.fi gegen pci.ids: nichts widerlegt ($n Namen bestaetigt)"
    for fam in igc igb I219; do
        grep -qaE "^$fam-Nummern fehlend +: +0 von" "$TMPD/chipnames.txt" \
            && ok "$fam: alle Nummern aus dem Linux-Quelltext sind benannt" \
            || bad "$fam: es fehlen Nummern in chipname.fi"
    done
elif grep -qa 'hole https' "$TMPD/chipnames.txt"; then
    echo "  ----  chipnames.py uebersprungen (pci.ids nicht da, kein Netz)"
else
    bad "chipname.fi wurde widerlegt -- siehe $TMPD/chipnames.txt"
    sed -n '/WIDERSPRUCH/,/^$/p' "$TMPD/chipnames.txt" | head -12
fi

if python3 tools/blech/r8125regs.py >"$TMPD/r8125.txt" 2>&1; then
    ok "der 8125-Zweig stimmt mit Linux' r8169_main.c ueberein"
    hat "$TMPD/r8125.txt" "tx_kick" "und der Sendeanstoss wird eigens geprueft"
elif grep -qa 'hole https' "$TMPD/r8125.txt"; then
    echo "  ----  r8125regs.py uebersprungen (r8169_main.c nicht da, kein Netz)"
else
    bad "der 8125-Zweig weicht von Linux ab -- siehe $TMPD/r8125.txt"
    sed -n '/WIDERLEGT/,$p' "$TMPD/r8125.txt" | head -8
fi

# =====================================================================
echo "== 11. der ehrliche Bestand, auch ueber Nicht-Ethernet =="
# =====================================================================
#
# `probe` sieht nur Klasse 02 UNTERKLASSE 00. Eine WLAN-Karte ist 02:80
# und kam bis zu dieser Runde in KEINER Liste vor. `-device rocker` ist
# das einzige Geraet der Klasse 02:80, das QEMU 7.2 anbietet -- damit
# ist der Zweig wirklich gefahren und nicht nur gelesen.
lauf "$TMPD/neu.mb" "hwdiag nokbd nosched noproc nofs noring3" "$TMPD/10.txt" \
    -device e1000e,netdev=nx -netdev user,id=nx -device rocker,name=sw1
hat "$TMPD/10.txt" "netdev: bestand" "die Bestandsliste wird gedruckt"
hat "$TMPD/10.txt" "82574L (1G) -> e1000" \
    "die Karte MIT Treiber steht mit ihrem Modellnamen da, nicht nur als 'Intel'"
hat "$TMPD/10.txt" "kein Treiber (kein Ethernet-Port)" \
    "und das Klasse-02:80-Geraet wird GENANNT statt verschwiegen"
hat "$TMPD/10.txt" "netdev: bestand 2 geraete, 1 mit treiber, 1 ohne" \
    "und die Zaehlung darunter stimmt"

# Die Zeilenanfaenge, die Vertraege sind. Sie sind in dieser Runde
# zweimal versehentlich uebersetzt worden; ab jetzt faellt das SOFORT
# hier auf und nicht erst in drei fremden Testdateien.
lauf "$TMPD/neu.mb" "hwdiag nokbd nosched noproc nofs noring3" "$TMPD/11.txt" \
    -device ne2k_pci,netdev=ny -netdev user,id=ny
hat "$TMPD/11.txt" "netdev: no driver for 0x10ec:0x8029" \
    "VERTRAG: der Zeilenanfang ist der von Runde HWNET geblieben"
hat "$TMPD/11.txt" "[RTL8029 (ne2000)]" \
    "und der Klarname haengt HINTEN dran, wo er keine Zusage bricht"

echo
echo "BLECH: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ] || exit 1
exit 0
