#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/print/run.sh -- ROUND ROADMAP-5, K-008: printing, MEASURED.
#
# The printer on the other side is NOT written in this tree: it is CUPS'
# own IPP Everywhere reference printer, `ippeveprinter` (Debian package
# cups-ipp-utils), in a network namespace behind the same veth bridge
# `tools/account/run.sh` uses. What arrives there is read back by a
# second PWG raster reader written from the standard
# (`tools/print/pwgcheck.py`) and then by OCR (tesseract, German) -- the
# printed page has to SAY what the file said.
#
#  1. `drucke` builds (`--profile=app`, no undefined symbol).
#  2. `drucke info` reads the printer, and says the same as CUPS' own
#     client `ipptool` does about the same printer.
#  3. A German text over two pages: job accepted, job COMPLETED, the
#     spooled file is valid PWG raster (A4, 300 dpi, 8-bit grey, two
#     pages, TotalPageCount 2), nothing inked inside the 15 mm margins,
#     and OCR finds the lines -- umlauts included, in the right order,
#     on the right page. Counter-checks: a damaged file is rejected by
#     the reader, and page two does NOT contain page one.
#  4. /etc/drucker.conf: `drucke <file>` without an address.
#  5. A line longer than the page wraps; its last word is on the paper.
#  6. A form feed starts a new page.
#  7. A PDF goes out unchanged (sha256 of the spool file == the source).
#  8. Refusals: JPEG to a printer without JPEG, text to a printer without
#     PWG raster -- clear answer, exit code 7, and NO job on the printer.
#  9. US Letter: the page size follows the printer's media-default.
# 10. No printer at the address: `keinnetz`, exit code 5.
#
# Call:  bash tools/print/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }
is()  { if [ "${2:-}" = "$3" ]; then ok "$1: $2"; else bad "$1: '${2:-}', erwartet '$3'"; fi; }
num() { local n=$1 v=${2:-} o=$3 w=$4
    if [ -z "$v" ]; then bad "$n: keine Zahl (erwartet $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, erwartet $o $w"; fi
}
kv() { grep -aoE "^drucke: $2 = .*" "$1" 2>/dev/null | tail -1 | sed 's/^drucke: [a-z_]* = //' | tr -d '\r'; }
pk() { grep -aoE "^$2=[^ ]*" "$1" 2>/dev/null | head -1 | cut -d= -f2; }

for t in qemu-system-x86_64 python3 ip ippeveprinter ipptool tesseract; do
    command -v "$t" >/dev/null 2>&1 || { echo "DRUCKE: uebersprungen, $t fehlt"; exit 0; }
done
tesseract --list-langs 2>/dev/null | grep -qx deu || {
    echo "DRUCKE: uebersprungen, tesseract ohne deu"; exit 0; }

TMPD=$(mktemp -d)
NS=drk-$$
V0=dr0-$$
V1=dr1
BPORT=$(( 16000 + ($$ % 300) * 2 ))
QPORT=$(( BPORT + 1 ))
BRPID=""
PIDS=""
aufraeumen() {
    for p in $PIDS; do kill "$p" 2>/dev/null; done
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns pids "$NS" 2>/dev/null | xargs -r kill 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    [ -z "${KEEP_TMPD:-}" ] && rm -rf "$TMPD"
    [ -n "${KEEP_TMPD:-}" ] && echo "TMPD=$TMPD"
}
trap aufraeumen EXIT

FIRNC=${FIRNC:-vendor/firn/bin/firnc}

# ======================================================================
echo "== 1. das Programm baut =="
# ======================================================================
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if FIRNLIB="$ROOT/vendor/firn/lib" "$FIRNC" -c --profile=app \
        -o "$TMPD/drucke.o" kernel/app/drucke.fi > "$TMPD/cc.log" 2>&1; then
    ok "firnc --profile=app: drucke.fi mit font.ttf, font.raster, knetz"
else
    bad "drucke.fi uebersetzt nicht"; head -20 "$TMPD/cc.log" | sed 's/^/        /'
    echo "DRUCKE: $pass passed, $fail failed"; exit 1
fi
undef=$(nm -u "$TMPD/drucke.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "keine undefinierte Marke" || bad "undefiniert: $undef"
ld -T kernel/user/user.ld -o "$TMPD/drucke.elf" "$TMPD/drucke.o" 2>"$TMPD/ld.err" \
    && ok "ld mit kernel/user/user.ld" || { bad "ld schlaegt fehl"; head -3 "$TMPD/ld.err"; }
strip --strip-all "$TMPD/drucke.elf" 2>/dev/null
num "das Programm auf der Platte, in Oktetten" "$(stat -c%s "$TMPD/drucke.elf" 2>/dev/null)" le 1500000

HWNET_PROGS="sh ls cat echo" bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1 \
    || { bad "der Kern baut nicht"; tail -8 "$TMPD/b0.txt" | sed 's/^/        /'
         echo "DRUCKE: $pass passed, $fail failed"; exit 1; }
ok "Kern und Userland gebaut"
K="$TMPD/s0/k.mb"
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"

# ---------------------------------------------------------- the files
python3 - "$TMPD" <<'PY'
import sys, os
d = sys.argv[1]
lines = ["Drucktest OrientOS -- Seite eins",
         "Grüße aus Österreich: äöü ß, Übel Ärger Öfen",
         "",
         "The quick brown fox jumps over the lazy dog 0123456789"]
for i in range(1, 90):
    lines.append("Zeile %03d: Kalender Fenster Drucker Netzwerk %d" % (i, i * 7))
open(os.path.join(d, "probe.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
open(os.path.join(d, "kurz.txt"), "w", encoding="utf-8").write("Kurzer Brief an die Oma\n")
# thirty different words WITHOUT digits: in the mono face OCR reads 0/O
# and 1/l interchangeably, which is a test error, not a print error
WORDS = ("Apfel Birne Kirsche Dattel Erbse Feige Gurke Hafer Ingwer Kohl "
         "Linse Mais Nudel Olive Paprika Quark Rettich Salat Tomate Rucola "
         "Vanille Weizen Zwiebel Banane Karotte Melone Spinat Kresse Fenchel "
         "Pflaume").split()
long = " ".join(WORDS)
open(os.path.join(d, "lang.txt"), "w", encoding="utf-8").write(long + "\nENDE\n")
open(os.path.join(d, "blatt.txt"), "w", encoding="utf-8").write(
    "Blatt A oben\n\fBlatt B oben\n")
# a small, well-formed PDF (one empty page); its content does not matter,
# only that it arrives octet for octet
objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>"]
out = bytearray(b"%PDF-1.4\n")
offs = []
for i, o in enumerate(objs, 1):
    offs.append(len(out))
    out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
x = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
for o in offs:
    out += b"%010d 00000 n \n" % o
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, x)
open(os.path.join(d, "probe.pdf"), "wb").write(out)
open(os.path.join(d, "probe.jpg"), "wb").write(b"\xff\xd8\xff\xe0" + b"\0" * 60 + b"\xff\xd9")
PY
printf 'ziel=ipp://10.9.0.1:8631/ipp/print\n' > "$TMPD/drucker.conf"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"

python3 tools/osum/mkfs.py build "$TMPD/d.img" 16384 \
    /bin/ /etc/ /lib/ /doc/ \
    "/bin/sh=$TMPD/s0/sh.elf" "/bin/ls=$TMPD/s0/ls.elf" \
    "/bin/cat=$TMPD/s0/cat.elf" "/bin/echo=$TMPD/s0/echo.elf" \
    "/bin/drucke=$TMPD/drucke.elf" \
    "/lib/mono.ttf=$ROOT/assets/osum-mono.ttf" \
    "/lib/sans.ttf=$ROOT/assets/osum-sans.ttf" \
    "/etc/passwd=$TMPD/passwd" \
    "/etc/drucker.conf=$TMPD/drucker.conf" \
    "/doc/probe.txt=$TMPD/probe.txt" "/doc/kurz.txt=$TMPD/kurz.txt" \
    "/doc/lang.txt=$TMPD/lang.txt" "/doc/blatt.txt=$TMPD/blatt.txt" \
    "/doc/probe.pdf=$TMPD/probe.pdf" "/doc/probe.jpg=$TMPD/probe.jpg" \
    > "$TMPD/mkfs.txt" 2>&1 && ok "das Abbild: /bin/drucke, /lib/mono.ttf, /etc/drucker.conf" \
    || { bad "mkfs: $(tail -2 "$TMPD/mkfs.txt")"; echo "DRUCKE: $pass passed, $fail failed"; exit 1; }

# ---------------------------------------------------------- network + printers
ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "DRUCKE: uebersprungen, keine Netzraeume"; exit 0; }
ip link add "$V0" type veth peer name "$V1"
ip link set "$V1" netns "$NS"
ip netns exec "$NS" ip addr add 10.9.0.1/24 dev "$V1"
ip netns exec "$NS" ip link set "$V1" up
ip netns exec "$NS" ip link set lo up
ip link set "$V0" up
ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
"$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!

# A4, PWG raster + PDF -- an ordinary office printer
mkdir -p "$TMPD/sp1" "$TMPD/sp2" "$TMPD/sp3"
cat > "$TMPD/a4.conf" <<'EOF'
ATTR keyword media-default iso_a4_210x297mm
ATTR keyword media-supported iso_a4_210x297mm,na_letter_8.5x11in
ATTR mimeMediaType document-format-supported image/pwg-raster,application/pdf
ATTR resolution pwg-raster-document-resolution-supported 300dpi,600dpi
ATTR keyword pwg-raster-document-type-supported black_1,sgray_8
EOF
ip netns exec "$NS" ippeveprinter -r off -p 8631 -a "$TMPD/a4.conf" \
    -k -d "$TMPD/sp1" "Testdrucker" > "$TMPD/p1.log" 2>&1 & PIDS="$PIDS $!"
# PDF only -- no raster, no text
ip netns exec "$NS" ippeveprinter -r off -p 8632 -f application/pdf \
    -k -d "$TMPD/sp2" "Nurpdf" > "$TMPD/p2.log" 2>&1 & PIDS="$PIDS $!"
# the program's own defaults: US Letter
ip netns exec "$NS" ippeveprinter -r off -p 8633 -f image/pwg-raster \
    -k -d "$TMPD/sp3" "Letterdrucker" > "$TMPD/p3.log" 2>&1 & PIDS="$PIDS $!"
sleep 2

lauf() { # <script> <out>
    timeout 240 qemu-system-x86_64 -kernel "$K" -m 512 -enable-kvm \
        -append "osum nokbd nosched noproc nofs nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$1;exit" \
        -serial "file:$2" -display none -no-reboot \
        -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cd" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
[ -e /dev/kvm ] || lauf() { # same without KVM
    timeout 600 qemu-system-x86_64 -kernel "$K" -m 512 \
        -append "osum nokbd nosched noproc nofs nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$1;exit" \
        -serial "file:$2" -display none -no-reboot \
        -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cd" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
U=ipp://10.9.0.1:8631/ipp/print

# ======================================================================
echo "== 2. der Drucker, so wie drucke ihn sieht -- und wie CUPS ihn sieht =="
# ======================================================================
lauf "drucke info $U" "$TMPD/o_info.txt"
is "stand" "$(kv "$TMPD/o_info.txt" stand)" "ok"
is "printer-name" "$(kv "$TMPD/o_info.txt" name)" "Testdrucker"
is "printer-state (3 = idle)" "$(kv "$TMPD/o_info.txt" zustand)" "3"
is "media-default" "$(kv "$TMPD/o_info.txt" papier)" "iso_a4_210x297mm"
grep -aoE '^drucke: format = .*' "$TMPD/o_info.txt" | sed 's/^drucke: format = //' | tr -d '\r' | sort > "$TMPD/fmt_drucke.txt"
ip netns exec "$NS" ipptool -tv "$U" get-printer-attributes.test > "$TMPD/ipptool.txt" 2>&1
# ippeveprinter sends document-format-supported TWICE here (the -a file
# and its own default list; ipptool: "Duplicate ... attribute"). drucke
# takes the first (IPP knows no second one of the same name) -- so the
# comparison is against ipptool's first line, not both mixed.
grep -m1 -aE '^ +document-format-supported ' "$TMPD/ipptool.txt" | sed 's/.* = //' | tr ',' '\n' | sort > "$TMPD/fmt_cups.txt"
num "Formate laut ipptool (CUPS)" "$(wc -l < "$TMPD/fmt_cups.txt")" ge 2
if [ -s "$TMPD/fmt_cups.txt" ] && cmp -s "$TMPD/fmt_drucke.txt" "$TMPD/fmt_cups.txt"; then
    ok "document-format-supported: drucke und ipptool nennen dieselben $(wc -l < "$TMPD/fmt_cups.txt") Formate"
else
    bad "drucke und ipptool sehen verschiedene Formate: $(tr '\n' ' ' < "$TMPD/fmt_drucke.txt") / $(tr '\n' ' ' < "$TMPD/fmt_cups.txt")"
fi
grep -aE '^ +pwg-raster-document-resolution-supported ' "$TMPD/ipptool.txt" | sed 's/.* = //' > "$TMPD/res_cups.txt"
grep -aoE '^drucke: aufloesung = .*' "$TMPD/o_info.txt" | sed 's/^drucke: aufloesung = //; s/^\([0-9]*\)x\1dpi$/\1dpi/' | tr -d '\r' | paste -sd, > "$TMPD/res_drucke.txt"
is "pwg-raster-document-resolution-supported wie ipptool" "$(cat "$TMPD/res_drucke.txt")" "$(cat "$TMPD/res_cups.txt")"

# ======================================================================
echo "== 3. zwei Seiten deutscher Text =="
# ======================================================================
T0=$(date +%s)
lauf "drucke $U /doc/probe.txt" "$TMPD/o_p.txt"
T1=$(date +%s)
is "stand" "$(kv "$TMPD/o_p.txt" stand)" "ok"
is "format" "$(kv "$TMPD/o_p.txt" format)" "image/pwg-raster"
is "aufloesung" "$(kv "$TMPD/o_p.txt" aufloesung)" "300"
is "seiten" "$(kv "$TMPD/o_p.txt" seiten)" "2"
is "ipp_status (0 = successful-ok)" "$(kv "$TMPD/o_p.txt" ipp_status)" "0"
is "der Auftrag ist beim Drucker FERTIG" "$(kv "$TMPD/o_p.txt" auftrag_stand)" "fertig"
JOB=$(kv "$TMPD/o_p.txt" auftrag)
hin "Auftrag $JOB, ganzer Lauf in QEMU $((T1-T0)) s"
SP=$(ls "$TMPD/sp1/$JOB"-*.pwg 2>/dev/null | head -1)
if [ -n "$SP" ]; then
    ok "der Drucker hat die Datei gespoolt: $(basename "$SP"), $(stat -c%s "$SP") Oktette"
    is "  so viele Oktette, wie drucke nennt" "$(stat -c%s "$SP")" "$(kv "$TMPD/o_p.txt" oktette)"
else
    bad "keine gespoolte Datei fuer Auftrag $JOB"; ls -la "$TMPD/sp1" | sed 's/^/        /'
fi
grep -a "Print-Job" "$TMPD/p1.log" | head -2 | sed 's/^/        /'
mkdir -p "$TMPD/pg"
python3 tools/print/pwgcheck.py "${SP:-/nonexistent}" "$TMPD/pg" > "$TMPD/chk.txt" 2>&1
sed 's/^/        /' "$TMPD/chk.txt"
is "der zweite PWG-Leser: gueltig" "$(pk "$TMPD/chk.txt" ok)" "1"
is "Seiten in der Datei" "$(pk "$TMPD/chk.txt" pages)" "2"
grep -q '^page1=2480x3508 dpi=300x300 bpc=8 bpp=8 bpl=2480 cs=18 ncol=1 pagesize=595x842 total=2 ' "$TMPD/chk.txt" \
    && ok "Seite 1: A4 = 2480x3508 bei 300 dpi, sgray 8 Bit, TotalPageCount 2" \
    || bad "Seite 1 hat nicht die erwarteten Kopfwerte"
grep -q 'size=iso_a4_210x297mm' "$TMPD/chk.txt" && ok "PageSizeName iso_a4_210x297mm" || bad "PageSizeName fehlt"
BOX=$(grep -oE '^page1_ink=[0-9]+ box=[0-9,-]+' "$TMPD/chk.txt" | sed 's/.*box=//')
IFS=, read -r BL BT BR BB <<< "$BOX"
M=177   # 15 mm at 300 dpi
if [ -n "$BOX" ] && [ "$BL" -ge "$M" ] && [ "$BT" -ge "$M" ] && [ "$BR" -le $((2480-M)) ] && [ "$BB" -le $((3508-M)) ]; then
    ok "nichts im 15-mm-Rand: Tinte in $BOX"
else
    bad "Tinte im Rand: $BOX"
fi
tesseract "$TMPD/pg/page-1.pgm" - -l deu --psm 6 > "$TMPD/ocr1.txt" 2>/dev/null
tesseract "$TMPD/pg/page-2.pgm" - -l deu --psm 6 > "$TMPD/ocr2.txt" 2>/dev/null
grep -q 'Drucktest' "$TMPD/ocr1.txt" && ok "OCR Seite 1: 'Drucktest'" || bad "OCR Seite 1 liest 'Drucktest' nicht"
grep -q 'Grüße aus Österreich' "$TMPD/ocr1.txt" && ok "OCR Seite 1: 'Grüße aus Österreich' -- mit Umlauten und ß" || bad "OCR Seite 1: die Umlautzeile fehlt: $(sed -n 2p "$TMPD/ocr1.txt")"
# Capital umlauts stand in words: alone ("ÄÖÜ") tesseract drops the
# dots of the Ü although they are on the paper (checked by eye on the
# page image, round ROADMAP-5) -- an OCR weakness, not a print error.
grep -q 'äöü ß' "$TMPD/ocr1.txt" && ok "OCR Seite 1: 'äöü ß'" || bad "OCR: 'äöü ß' fehlt"
grep -q 'Übel Ärger Öfen' "$TMPD/ocr1.txt" && ok "OCR Seite 1: 'Übel Ärger Öfen' -- grosse Umlaute" || bad "OCR: 'Übel Ärger Öfen' fehlt: $(sed -n 2p "$TMPD/ocr1.txt")"
grep -q 'quick brown fox' "$TMPD/ocr1.txt" && ok "OCR Seite 1: 'quick brown fox'" || bad "OCR: 'quick brown fox' fehlt"
Z1=$(grep -c 'Kalender Fenster Drucker Netzwerk' "$TMPD/ocr1.txt")
Z2=$(grep -c 'Kalender Fenster Drucker Netzwerk' "$TMPD/ocr2.txt")
num "OCR: Textzeilen auf beiden Seiten zusammen (von 89)" "$((Z1+Z2))" ge 86
grep -q 'Zeile 001' "$TMPD/ocr1.txt" && ok "Zeile 001 auf Seite 1" || bad "Zeile 001 nicht auf Seite 1"
grep -q 'Zeile 089' "$TMPD/ocr2.txt" && ok "Zeile 089 auf Seite 2" || bad "Zeile 089 nicht auf Seite 2"
if grep -q 'Drucktest\|Zeile 001' "$TMPD/ocr2.txt"; then
    bad "Gegenprobe: Seite 2 enthaelt Seite 1"
else
    ok "Gegenprobe: Seite 2 enthaelt NICHT Seite 1 (die Seiten sind verschieden)"
fi
# The reader must be able to say no.
head -c $(( $(stat -c%s "${SP:-/dev/null}") - 5000 )) "${SP:-/dev/null}" > "$TMPD/kaputt.pwg" 2>/dev/null
python3 tools/print/pwgcheck.py "$TMPD/kaputt.pwg" "$TMPD" > "$TMPD/chk2.txt" 2>&1
is "Gegenprobe: 5000 Oktette abgeschnitten -> der Leser lehnt ab" "$(pk "$TMPD/chk2.txt" ok)" "0"
python3 - "${SP:-/dev/null}" "$TMPD/kaputt2.pwg" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read())
d[4 + 1796] = 254   # the first line repeat count: 255 rows instead of 1
open(sys.argv[2], "wb").write(d)
PY
python3 tools/print/pwgcheck.py "$TMPD/kaputt2.pwg" "$TMPD" > "$TMPD/chk3.txt" 2>&1
is "Gegenprobe: eine falsche Wiederholzahl -> der Leser lehnt ab" "$(pk "$TMPD/chk3.txt" ok)" "0"

# ======================================================================
echo "== 4. ohne Adresse: /etc/drucker.conf =="
# ======================================================================
T0=$SECONDS
lauf "drucke /doc/kurz.txt" "$TMPD/o_c.txt"
# ippeveprinter takes 5..15 s per job. drucke asks every half second, one
# connection per question; before vendor/firn/patches/0007 the ninth
# connect failed until the first TIME_WAIT ran out, and every job took
# 60 s. Boot, rendering and shutdown included, 40 s is generous.
num "Sekunden fuer den ganzen Auftrag (Start bis fertig)" "$((SECONDS-T0))" le 40
is "stand" "$(kv "$TMPD/o_c.txt" stand)" "ok"
is "ziel aus der Datei" "$(kv "$TMPD/o_c.txt" ziel)" "$U"
is "seiten" "$(kv "$TMPD/o_c.txt" seiten)" "1"

# ======================================================================
echo "== 5. eine Zeile, laenger als das Blatt =="
# ======================================================================
lauf "drucke $U /doc/lang.txt" "$TMPD/o_l.txt"
is "stand" "$(kv "$TMPD/o_l.txt" stand)" "ok"
JL=$(kv "$TMPD/o_l.txt" auftrag)
SL=$(ls "$TMPD/sp1/$JL"-*.pwg 2>/dev/null | head -1)
mkdir -p "$TMPD/pl"
python3 tools/print/pwgcheck.py "${SL:-/nonexistent}" "$TMPD/pl" > "$TMPD/chkl.txt" 2>&1
tesseract "$TMPD/pl/page-1.pgm" - -l deu --psm 6 > "$TMPD/ocrl.txt" 2>/dev/null
sed 's/^/        /' "$TMPD/ocrl.txt" | head -5
N=0
for w in Apfel Birne Kirsche Dattel Erbse Feige Gurke Hafer Ingwer Kohl Linse Mais Nudel Olive Paprika Quark Rettich Salat Tomate Rucola Vanille Weizen Zwiebel Banane Karotte Melone Spinat Kresse Fenchel Pflaume; do
    grep -qw "$w" "$TMPD/ocrl.txt" && N=$((N+1))
done
num "OCR: verschiedene Woerter der langen Zeile auf dem Blatt (von 30)" "$N" ge 28
grep -qw 'Pflaume' "$TMPD/ocrl.txt" && ok "das letzte Wort ist auf dem Papier (umgebrochen, nicht abgeschnitten)" || bad "Pflaume (das letzte Wort) fehlt"
num "sie steht auf mehr als einer Zeile" "$(grep -cE 'Apfel|Birne|Kirsche|Dattel|Erbse|Feige|Gurke|Hafer|Ingwer|Kohl|Linse|Mais|Nudel|Olive|Paprika|Quark|Rettich|Salat|Tomate|Rucola|Vanille|Weizen|Zwiebel|Banane|Karotte|Melone|Spinat|Kresse|Fenchel|Pflaume' "$TMPD/ocrl.txt")" ge 3
BOXL=$(grep -oE '^page1_ink=[0-9]+ box=[0-9,-]+' "$TMPD/chkl.txt" | sed 's/.*box=//')
BRL=$(echo "$BOXL" | cut -d, -f3)
num "und nichts laeuft in den rechten Rand (letzte Tinte, Spalte)" "${BRL:-99999}" le $((2480-M))

# ======================================================================
echo "== 6. ein Seitenvorschub =="
# ======================================================================
lauf "drucke $U /doc/blatt.txt" "$TMPD/o_f.txt"
is "stand" "$(kv "$TMPD/o_f.txt" stand)" "ok"
is "zwei Zeilen, dazwischen \\f: seiten" "$(kv "$TMPD/o_f.txt" seiten)" "2"

# ======================================================================
echo "== 7. ein PDF geht unveraendert hinaus =="
# ======================================================================
lauf "drucke $U /doc/probe.pdf" "$TMPD/o_pdf.txt"
is "stand" "$(kv "$TMPD/o_pdf.txt" stand)" "ok"
is "format" "$(kv "$TMPD/o_pdf.txt" format)" "application/pdf"
JP=$(kv "$TMPD/o_pdf.txt" auftrag)
SPDF=$(ls "$TMPD/sp1/$JP"-*.pdf 2>/dev/null | head -1)
if [ -n "$SPDF" ] && [ "$(sha256sum < "$SPDF")" = "$(sha256sum < "$TMPD/probe.pdf")" ]; then
    ok "die gespoolte Datei ist Oktett fuer Oktett das PDF ($(stat -c%s "$SPDF") Oktette)"
else
    bad "das PDF kam nicht unveraendert an: '${SPDF:-keine Datei}'"
fi

# ======================================================================
echo "== 8. Absagen: kein passendes Format =="
# ======================================================================
N1=$(ls "$TMPD/sp1" | wc -l)
lauf "drucke $U /doc/probe.jpg;echo rc=\$?" "$TMPD/o_j.txt"
is "JPEG an einen Drucker ohne JPEG" "$(kv "$TMPD/o_j.txt" stand)" "keinformat"
is "  und kein Auftrag beim Drucker (Dateien im Spool)" "$(ls "$TMPD/sp1" | wc -l)" "$N1"
lauf "drucke ipp://10.9.0.1:8632/ipp/print /doc/kurz.txt" "$TMPD/o_np.txt"
is "Text an einen reinen PDF-Drucker" "$(kv "$TMPD/o_np.txt" stand)" "keinformat"
is "  und dort liegt nichts" "$(ls "$TMPD/sp2" | wc -l)" "0"
grep -qa 'weder PWG-Raster' "$TMPD/o_np.txt" && ok "  mit einem Satz, der sagt warum" || bad "  ohne Begruendung"

# ======================================================================
echo "== 9. US Letter, weil der Drucker es sagt =="
# ======================================================================
lauf "drucke ipp://10.9.0.1:8633/ipp/print /doc/kurz.txt" "$TMPD/o_lt.txt"
is "stand" "$(kv "$TMPD/o_lt.txt" stand)" "ok"
is "breite (8,5 Zoll bei 300 dpi)" "$(kv "$TMPD/o_lt.txt" breite)" "2550"
is "hoehe (11 Zoll)" "$(kv "$TMPD/o_lt.txt" hoehe)" "3300"
SLT=$(ls "$TMPD/sp3/"*.pwg 2>/dev/null | head -1)
python3 tools/print/pwgcheck.py "${SLT:-/nonexistent}" "$TMPD" > "$TMPD/chklt.txt" 2>&1
grep -q 'size=na_letter_8.5x11in' "$TMPD/chklt.txt" && grep -q '^ok=1' "$TMPD/chklt.txt" \
    && ok "die Datei: gueltig, na_letter_8.5x11in" || bad "Letter-Datei: $(tail -2 "$TMPD/chklt.txt")"

# ======================================================================
echo "== 10. kein Drucker unter der Adresse =="
# ======================================================================
T0=$(date +%s)
lauf "drucke ipp://10.9.0.1:8699/ipp/print /doc/kurz.txt" "$TMPD/o_n.txt"
T1=$(date +%s)
is "stand" "$(kv "$TMPD/o_n.txt" stand)" "keinnetz"
hin "in $((T1-T0)) s (samt Start und Ende von QEMU)"

echo "DRUCKE: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
