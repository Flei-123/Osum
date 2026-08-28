#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fsrobust/run.sh -- DIE ABNAHME DER RUNDE FSROBUST.
#
# Sieben Abschnitte, und der dritte ist der, um den es geht:
#
#   1. BAUEN. Kern und Programme, und die Abbilder auf dem Wirt.
#   2. DIE GRENZEN. Wie gross eine Datei, ein Datentraeger und ein
#      Verzeichnis wirklich sein duerfen -- gemessen, nicht gerechnet.
#      Die Langfassung steht in docs/OFS-LIMITS.md.
#   3. DER STROMAUSFALL. QEMU wird mit SIGKILL abgeschossen, mitten im
#      Schreiben, zu einem zufaelligen Zeitpunkt. Danach derselbe Kern
#      auf denselben Oktetten: einhaengen, nachtragen, pruefen. Die Zahl
#      der beschaedigten Faelle MUSS null sein.
#   4. DIE GEGENPROBE. Dasselbe mit dem Wort `nojournal`. Hier MUESSEN
#      Schaeden auftreten -- sonst misst Abschnitt 3 nichts.
#   5. DIE HALB GESCHRIEBENE BESTAETIGUNG. Ein Journal mit richtiger
#      Kennung und falscher Pruefsumme darf NICHT nachgetragen werden.
#   6. FSCK. Auf dreizehn mutwillig zerstoerten Abbildern: es muss
#      FERTIG WERDEN und melden. Und `-r` muss beheben, was eindeutig
#      ist.
#   7. RUECKWAERTS. Ein Abbild der Fassung 2 ist Oktett fuer Oktett das
#      von vor dieser Runde, und ein Abbild OHNE Journal haengt sich
#      weiter ein.
#
# Umgebung:
#   FSR_LAEUFE   wie viele Abschuesse je Abschnitt (Vorgabe 10).
#                Die Zahl in docs/OFS-JOURNAL.md kommt aus einem Lauf
#                mit 60.
#   FSR_PAR      wie viele gleichzeitig (Vorgabe 4).
#
# Benutzung:  bash tools/fsrobust/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh ls cat echo rm df touch mkdir fsrlim fsrw fsrv fsck"
LAEUFE=${FSR_LAEUFE:-10}
PAR=${FSR_PAR:-4}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name wert op erwartet
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
val() { tr -d '\000' < "$1" 2>/dev/null | grep -a "^$2: $3 = " | head -1 | sed 's/.* = //'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "FSROBUST: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" >"$TMPD/build.txt" 2>&1 \
    && ok "Kern gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern laesst sich nicht bauen"; tail -8 "$TMPD/build.txt" | sed 's/^/        /';
         echo "FSROBUST: $pass bestanden, $fail gescheitert"; exit 1; }
export FSR_KERNEL="$TMPD/k.mb"

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$p.fi uebersetzt nicht"; sed 's/^/        /' "$TMPD/e$p" | head -6; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
done
ok "$(echo $PROGS | wc -w) Programme gebaut, darunter /bin/fsck"

SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
# Die Platte, auf der der Stromausfall gemessen wird: 32 MiB, 512 Inodes,
# MIT Journal. Klein genug, dass ein Lauf schnell ist, gross genug, dass
# der Zuteiler etwas zu tun hat.
python3 tools/osum/mkfs.py build "$TMPD/j.img" 65536 --v3 --inodes=512 \
    --journal --time=1780000000 $SPEC > "$TMPD/mkj.txt" 2>&1 \
    || bad "mkfs mit Journal"
sed 's/^/        /' "$TMPD/mkj.txt"
grep -qa 'jstart=273 jblocks=522' "$TMPD/mkj.txt" \
    && ok "der Journalbereich liegt zwischen Inodetabelle und Daten (522 Bloecke)" \
    || bad "der Journalbereich sitzt nicht, wo er soll"
python3 tools/osum/mkfs.py build "$TMPD/nj.img" 65536 --v3 --inodes=512 \
    --time=1780000000 $SPEC >/dev/null 2>&1 || bad "mkfs ohne Journal"

lauf() { # abbild anhang ausgabe [zeitlimit]
    local img=$1 app=$2 out=$3 t=${4:-600}
    timeout "$t" qemu-system-x86_64 -accel tcg -kernel "$TMPD/k.mb" -m 512 \
        -append "osum vfs nokbd $app" \
        -serial "file:$out" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0,cache=directsync" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

echo
echo "== 2. die Grenzen, in Ring 3 gemessen =="
python3 tools/osum/mkfs.py build "$TMPD/lim.img" 262144 --v3 --inodes=256 \
    --time=1780000000 $SPEC >/dev/null 2>&1
cp --sparse=always "$TMPD/lim.img" "$TMPD/lim-live.img"
lauf "$TMPD/lim-live.img" "script=fsrlim datei;exit" "$TMPD/lim.txt" 900
rc=$?
[ "$rc" -eq 21 ] && ok "der Kern hat selbst abgeschaltet (exit 21)" \
                 || bad "QEMU exit $rc, erwartet 21"
num "groesster Blockindex einer Datei" "$(val "$TMPD/lim.txt" fsrlim maxidx)" eq 266311
num "groesste Datei in Oktetten" "$(val "$TMPD/lim.txt" fsrlim maxfile)" eq 136351744
# DIE GEGENPROBE ZUR SUCHE. Ohne sie waere die Zahl oben nur der letzte
# Erfolg und keine Grenze.
num "EIN Block weiter geht es NICHT" "$(val "$TMPD/lim.txt" fsrlim ueber)" eq 0

# Ein Verzeichnis IST eine Datei: eines mit ueber zwoelftausend Eintraegen
# liegt hinter der doppelt indirekten Stufe (2.134.016 Oktette).
FSR_PROGS="$PROGS" python3 - "$TMPD" <<'PY' > "$TMPD/gross.txt" 2>&1
import sys, os
sys.path.insert(0, "tools/osum")
import mkfs
t = sys.argv[1]
fs = mkfs.Fs(262144, mkfs.OFS_V3, 20000, 1780000000, 0)
fs.format()
for d in ("/tmp", "/bin", "/dev", "/proc", "/gross"):
    fs.mkdir(d)
for p in os.environ["FSR_PROGS"].split():
    fs.addfile("/bin/" + p, open(os.path.join(t, p + ".elf"), "rb").read())
fs.addfile("/gross/f0000000", b"hallo")
for i in range(1, 12000):
    fs.link("/gross/f%07d" % i, "/gross/f0000000")
gr = fs.resolve("/gross")
print("gross: eintraege=%d groesse=%d"
      % (fs.dir_entries(gr), fs.iget(gr, mkfs.I_SIZE)))
with open(os.path.join(t, "gross.img"), "wb") as f:
    f.write(fs.d)
    f.seek(fs.blocks * 512 - 1)
    f.write(b"\0")
PY
sed 's/^/        /' "$TMPD/gross.txt"
gr_gr=$(grep -oa 'groesse=[0-9]*' "$TMPD/gross.txt" | cut -d= -f2)
num "das Verzeichnis liegt hinter der doppelt indirekten Stufe" \
    "${gr_gr:-0}" gt 2134016
lauf "$TMPD/gross.img" "script=fsrlim gross;exit" "$TMPD/grossl.txt" 900
num "alle Eintraege kamen ueber getdents zurueck" \
    "$(val "$TMPD/grossl.txt" fsrlim dents)" eq 12002
num "und der LETZTE Name liess sich oeffnen" \
    "$(val "$TMPD/grossl.txt" fsrlim dlast)" eq 1

echo
echo "== 3. der Stromausfall: $LAEUFE Abschuesse mit SIGKILL =="
echo "        (QEMU wird mitten im Schreiben mit -9 abgeschossen; die"
echo "         Platte haengt mit cache=directsync, sonst ueberlebte der"
echo "         Seitenpuffer des Wirts den Abschuss und nichts waere"
echo "         gemessen.)"
mkdir -p "$TMPD/runs"
seq 1 "$LAEUFE" | xargs -P "$PAR" -I{} sh -c \
    "bash tools/fsrobust/crash.sh $TMPD/j.img $TMPD/runs {} '' 2>&1" \
    > "$TMPD/crash.log" 2>&1
sort -t= -k2 -n "$TMPD/crash.log" | sed 's/^/        /'
n_l=$(grep -c '^lauf=' "$TMPD/crash.log")
n_s=$(grep '^lauf=' "$TMPD/crash.log" | grep -c 'schaeden=[1-9]')
n_f=$(grep '^lauf=' "$TMPD/crash.log" | grep -c 'fsck=[1-9]')
n_w=$(grep '^lauf=' "$TMPD/crash.log" | grep -c 'wirt=[1-9]')
n_b=$(grep '^lauf=' "$TMPD/crash.log" | grep -vc 'rc2=21')
num "Laeufe durchgefuehrt" "$n_l" eq "$LAEUFE"
num "Laeufe, die danach NICHT mehr hochkamen" "$n_b" eq 0
num "BESCHAEDIGTE FAELLE (Ring 3)" "$n_s" eq 0
num "BESCHAEDIGTE FAELLE (fsck)" "$n_f" eq 0
num "BESCHAEDIGTE FAELLE (Wirt)" "$n_w" eq 0

echo
echo "== 4. die Gegenprobe: dieselben Abschuesse mit 'nojournal' =="
echo "        (hier MUESSEN Schaeden auftreten -- sonst misst"
echo "         Abschnitt 3 nichts)"
seq 101 $((100 + LAEUFE)) | xargs -P "$PAR" -I{} sh -c \
    "bash tools/fsrobust/crash.sh $TMPD/j.img $TMPD/runs {} 'nojournal' 2>&1" \
    > "$TMPD/gegen.log" 2>&1
sort -t= -k2 -n "$TMPD/gegen.log" | grep '^lauf=' | sed 's/^/        /'
g_b=$(grep '^lauf=' "$TMPD/gegen.log" \
      | grep -c 'schaeden=[1-9]\|fsck=[1-9]\|wirt=[1-9]')
if [ "$g_b" -gt 0 ]; then
    ok "ohne Journal treten Schaeden auf: $g_b von $LAEUFE Laeufen"
else
    bad "ohne Journal trat in $LAEUFE Laeufen KEIN Schaden auf -- damit"
    echo "        misst Abschnitt 3 nichts. Mehr Laeufe (FSR_LAEUFE) oder"
    echo "        laengere Schreibzeit (FSR_MINMS/FSR_SPANMS) noetig;"
    echo "        gemessen wurden 26 % bei 60 Laeufen."
fi

echo
echo "== 5. eine halb geschriebene Bestaetigung wird NICHT nachgetragen =="
python3 tools/fsrobust/kaputt.py "$TMPD/j.img" "$TMPD/kaputt" jmuell \
    >/dev/null 2>&1 || bad "kaputt.py jmuell"
cp --sparse=always "$TMPD/kaputt/kaputt-jmuell.img" "$TMPD/jm.img"
lauf "$TMPD/jm.img" "script=fsck /dev/hda;exit" "$TMPD/jm.txt" 600
num "der Kern haengt das Abbild trotzdem ein" \
    "$(tr -d '\000' < "$TMPD/jm.txt" | grep -ca 'osum: mount=1')" ge 1
num "die Bestaetigung ist nach dem Einhaengen weg" \
    "$(val "$TMPD/jm.txt" fsck joffen)" eq 0
num "und das Dateisystem ist unversehrt" \
    "$(val "$TMPD/jm.txt" fsck fehler)" eq 0

echo
echo "== 6. /bin/fsck auf mutwillig zerstoerten Abbildern =="
python3 tools/fsrobust/kaputt.py "$TMPD/j.img" "$TMPD/kaputt" \
    > "$TMPD/kaputt.txt" 2>&1 || bad "kaputt.py"
n_k=$(grep -c '^kaputt: ' "$TMPD/kaputt.txt")
num "kaputte Abbilder gebaut" "$n_k" ge 13
fertig=0
haengt=0
for f in "$TMPD"/kaputt/*.img; do
    n=$(basename "$f" .img)
    cp --sparse=always "$f" "$TMPD/fk.img"
    cp --sparse=always "$TMPD/j.img" "$TMPD/fkboot.img"
    timeout 300 qemu-system-x86_64 -accel tcg -kernel "$TMPD/k.mb" -m 512 \
        -append "osum vfs nokbd script=fsck /dev/hdb;exit" \
        -serial "file:$TMPD/fk.txt" -display none -no-reboot \
        -drive "file=$TMPD/fkboot.img,format=raw,if=ide,index=0" \
        -drive "file=$TMPD/fk.img,format=raw,if=ide,index=1" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rc=$?
    fe=$(val "$TMPD/fk.txt" fsck fehler)
    if [ "$rc" -eq 21 ] && [ -n "$fe" ]; then
        fertig=$((fertig+1))
        printf '        %-22s fehler=%s\n' "$n" "$fe"
    else
        haengt=$((haengt+1))
        printf '        %-22s HAENGT ODER STIRBT (exit %s)\n' "$n" "$rc"
    fi
done
num "kaputte Abbilder, auf denen fsck FERTIG WIRD" "$fertig" eq "$n_k"
num "kaputte Abbilder, auf denen es haengenbleibt" "$haengt" eq 0

# `-r` muss beheben, was eindeutig ist: eine genullte Karte.
cp --sparse=always "$TMPD/kaputt/kaputt-leerkarte.img" "$TMPD/rep.img"
cp --sparse=always "$TMPD/j.img" "$TMPD/repboot.img"
fsck2() { # abbild anhang ausgabe
    timeout 300 qemu-system-x86_64 -accel tcg -kernel "$TMPD/k.mb" -m 512 \
        -append "osum vfs nokbd script=fsck $1 /dev/hdb;exit" \
        -serial "file:$2" -display none -no-reboot \
        -drive "file=$TMPD/repboot.img,format=raw,if=ide,index=0" \
        -drive "file=$TMPD/rep.img,format=raw,if=ide,index=1" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
fsck2 "" "$TMPD/r0.txt"
v0=$(val "$TMPD/r0.txt" fsck fehler)
fsck2 "-r" "$TMPD/r1.txt"
b1=$(val "$TMPD/r1.txt" fsck behoben)
fsck2 "" "$TMPD/r2.txt"
v2=$(val "$TMPD/r2.txt" fsck fehler)
num "vor der Reparatur: Fehler" "$v0" gt 0
num "fsck -r hat behoben" "$b1" gt 0
num "nach der Reparatur: Fehler" "$v2" eq 0

echo
echo "== 7. rueckwaerts: was vorher ging, geht weiter =="
lauf "$TMPD/nj.img" "script=fsck /dev/hda;exit" "$TMPD/nj.txt" 600
num "eine Platte OHNE Journal haengt sich ein" \
    "$(tr -d '\000' < "$TMPD/nj.txt" | grep -ca 'osum: mount=1')" ge 1
num "und sie meldet 0 Journalbloecke" \
    "$(val "$TMPD/nj.txt" fsck journal)" eq 0
num "und sie ist unversehrt" "$(val "$TMPD/nj.txt" fsck fehler)" eq 0
# Ein Abbild der Fassung 2 muss Oktett fuer Oktett dasselbe sein wie
# vorher. Zwei Laeufe von mkfs geben dieselben Oktette -- das ist die
# Zusage aus Runde K15, und sie gilt weiter.
python3 tools/osum/mkfs.py build "$TMPD/v2a.img" 4096 /bin/ \
    "/bin/sh=$TMPD/sh.elf" >/dev/null 2>&1
python3 tools/osum/mkfs.py build "$TMPD/v2b.img" 4096 /bin/ \
    "/bin/sh=$TMPD/sh.elf" >/dev/null 2>&1
cmp -s "$TMPD/v2a.img" "$TMPD/v2b.img" \
    && ok "zweimal gebaut gibt Oktett fuer Oktett dasselbe Abbild (Fassung 2)" \
    || bad "zwei Laeufe von mkfs geben verschiedene Abbilder"
python3 tools/osum/mkfs.py meta "$TMPD/v2a.img" 2>/dev/null | head -1 \
    | grep -qa 'version=2 bmblocks=1 isize=128 dirent=32 namelen=24' \
    && ok "die Vorgabe ist weiter die Fassung 2, unveraendert" \
    || bad "die Vorgabe von mkfs hat sich verschoben"

echo
echo "FSROBUST: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ]
