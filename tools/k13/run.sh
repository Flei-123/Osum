#!/usr/bin/env bash
# tools/k13/run.sh -- BENUTZER, RECHTE UND DER ERSTE PROZESS (Runde K13).
#
# Was diese Runde behauptet und was hier gemessen wird:
#
#   1. JEDER PROZESS HAT EINE KENNUNG, und sie ueberlebt `fork` und
#      `execve`. Gemessen in Ring 3 ohne Platte (`k13run`, kernel/uprog.fi):
#      das Kind meldet seine Kennung ueber den Beendigungscode zurueck.
#      Und mit den Regeln von POSIX: root darf alles, wer die Kennung
#      abgelegt hat, kommt nur ueber die GESICHERTE zurueck, und
#      `setuid(0)` danach MUSS -EPERM sein.
#   2. DATEIEN HABEN RECHTE UND EINEN EIGENTUEMER, im Inode auf der
#      Platte. Der WIRT liest sie hinterher AUS DEM ABBILD zurueck
#      (`mkfs.py meta`) -- nicht aus einem Mitschnitt der seriellen
#      Leitung. Ein Abbild der alten Fassung bleibt lesbar; die Fassung
#      steht im Superblock, und `ofsv2raw` zeigt, was ohne sie geschaehe.
#   3. DIE RECHTEPRUEFUNG WIRKT. Dasselbe Programm, dieselben Dateien,
#      einmal als root und einmal als `justin`: 0o600 laesst den einen
#      durch und den anderen nicht, 0o000 laesst root durch (so ist die
#      Regel) und `justin` nicht, /etc/shadow liest nur root. Die
#      GEGENPROBE ist `noperm`: derselbe Kernel, dieselben Dateien, die
#      Pruefung sagt immer ja -- und die Messung bricht zusammen.
#   4. PASSWOERTER SIND NICHT IM KLARTEXT und auch kein blosser SHA.
#      PBKDF2-HMAC-SHA256 mit Salz. Gemessen gegen PYTHONS `hashlib`:
#      dieselben Eingaben, dieselben 64 Hexziffern. Und `passwd` schreibt
#      wirklich in /etc/shadow -- der Wirt liest die Datei aus dem Abbild
#      und rechnet den Eintrag mit Python nach.
#   5. DAS setuid-BIT WIRKT. `justin` liest /etc/shadow nicht, `su` liest
#      es fuer ihn -- weil die Datei das Bit traegt. GEGENPROBE `nosuid`:
#      dasselbe scheitert.
#   6. ES GIBT EINEN PROZESS 1. Er startet Dienste, startet abgestuerzte
#      neu, nimmt Waisen an und faehrt herunter. Die Waise ist die
#      GEGENPROBE: ohne init steigt die Zahl der Leichen nachweislich.
#      Und dass die Abschaltung wirklich ACPI war und nicht der Ausgang
#      des Pruefstands, steht im Beendigungscode von QEMU: 0 gegen 21.
#   7. DER NOTWEG STEHT. `initsh` startet die Shell wie vor dieser Runde.
#
# Verwendung:  bash tools/k13/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
BLOCKS=4096

K13="id whoami chmod chown passwd su login init svc k13t"
BASIS="sh ls cat echo sleep true false wc grep"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
val() { grep -aoE "$2" "$1" | tail -1 | grep -oE '\-?[0-9]+$'; }

bash vendor/firn/hole-firnc.sh >/dev/null || { echo "vendor/firn/hole-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "K13: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# ------------------------------------------------------------- 1. bauen

echo "== 1. bauen: ein Kern, zehn neue Programme, die Speicherkarte =="

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "firnc0 baut den Kern mit Benutzern, Rechten und init" \
    || { bad "firnc0 baut den Kern nicht"; sed 's/^/        /' "$TMPD/b0.txt" | head -8; }
[ -f "$TMPD/k0.img" ] || { echo "K13: $pass passed, $((fail+1)) failed"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s uebersetzt nicht"

build_progs() { # stufe
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    for p in $K13 $BASIS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s uebersetzt $p.fi nicht"
            sed 's/^/        /' "$TMPD/e$p$s" | head -6; rc=1; continue; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>/dev/null || {
            bad "firnc$s: ld scheitert an $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}
build_progs 0 && ok "firnc0 baut $(echo $K13 $BASIS | wc -w) Programme in Ring 3" \
             || bad "firnc0 baut nicht alle Programme"

undef=""
for p in $K13; do
    u=$(nm -u "$TMPD/${p}0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "kein neues Programm hat ein undefiniertes Symbol" \
               || bad "undefinierte Symbole:$undef"

if python3 tools/kernel/karte.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "$(tail -1 "$TMPD/karte.txt")"
else
    bad "der Kartenpruefer schlaegt an"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi
grep -q '"K13_OFF"' tools/kernel/karte.py \
    && ok "der Bereich dieser Runde (0x41000..0x43000) steht in der Karte" \
    || bad "K13_OFF fehlt in tools/kernel/karte.py"
# RUNDE ARM: die Kopie braucht `kernel/arch/x86_64/` mit -- `hv.fi` liegt
# seit dem Trennschnitt dort, und ohne sie stirbt der Kartenpruefer an
# einem KeyError statt die Kollision zu melden, die hier gemessen wird.
mkdir -p "$TMPD/kbad/arch/x86_64"
cp kernel/*.fi "$TMPD/kbad/"
cp kernel/arch/x86_64/*.fi "$TMPD/kbad/arch/x86_64/"
sed -i 's/^const K13_OFF: u64 = 0x41000/const K13_OFF: u64 = 0x40000/' "$TMPD/kbad/kstate.fi"
if python3 tools/kernel/karte.py "$TMPD/kbad" > "$TMPD/karte-bad.txt" 2>&1; then
    bad "GEGENPROBE: K13 auf 0x40000 (dem Hypervisor) faellt NICHT auf"
else
    ok "GEGENPROBE: K13 auf 0x40000 kollidiert mit HV und faellt auf"
fi

# ---------------------------------------------------------- 2. die Faelle

echo "== 2. die Abbilder: /etc/passwd, /etc/shadow, /etc/inittab =="

python3 - "$TMPD" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
def rec(pw, salt):
    dk = hashlib.pbkdf2_hmac('sha256', pw, salt, 2048, 32)
    return "$osum1$2048$%s$%s" % (binascii.hexlify(salt).decode(),
                                  binascii.hexlify(dk).decode())
open(d + "/passwd", "w").write(
    "root:x:0:0:root:/:/bin/sh\n"
    "justin:x:1000:1000:Justin:/home:/bin/sh\n")
open(d + "/shadow", "w").write(
    "root:%s:0:0:99999:7:::\n" % rec(b"rootpass", bytes(range(8))) +
    "justin:%s:0:0:99999:7:::\n" % rec(b"geheim12", bytes(range(8, 16))))
open(d + "/pw.txt", "w").write("geheim12\n")
open(d + "/bad.txt", "w").write("falsch99\n")
open(d + "/rootpw.txt", "w").write("rootpass\n")
open(d + "/neu.txt", "w").write("geheim12\nneuneu77\nneuneu77\n")
PY
printf '# name:art:befehl\nblink:respawn:/bin/sleep 1\nsh:ctrl:/bin/sh\n' \
    > "$TMPD/inittab"
printf '# name:art:befehl\nblink:respawn:/bin/sleep 1\nlogin:ctrl:/bin/login\n' \
    > "$TMPD/inittab-login"

cat > "$TMPD/rechte.sh" <<'SCRIPT'
echo ==BEGIN==
id
whoami
k13t /w/root.txt /w/rootneu.txt
su justin /bin/k13t /w/ju.txt /w/juneu.txt < /t/pw.txt
su justin /bin/id < /t/pw.txt
su justin /bin/su root /bin/id < /t/bad.txt
echo badpw=$?
su justin /bin/su root /bin/id < /t/rootpw.txt
chmod 4755 /w/root.txt
chmod 640 /w/rootneu.txt
chown justin:justin /w/rootneu.txt
echo ==END==
SCRIPT

cat > "$TMPD/dienste.sh" <<'SCRIPT'
echo ==BEGIN==
svc status
sleep 3
svc status
svc stop blink
svc start blink
k13t waise
sleep 1
echo ==END==
SCRIPT

cat > "$TMPD/passwd.sh" <<'SCRIPT'
echo ==BEGIN==
su justin /bin/passwd < /t/neu.txt
echo pwrc=$?
echo ==END==
SCRIPT

SPEC=""
for p in $K13 $BASIS; do
    case $p in
        su|passwd) SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf@4755:0:0" ;;
        init)      SPEC="$SPEC /sbin/init=$TMPD/${p}0.elf@755:0:0" ;;
        *)         SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf" ;;
    esac
done
DIRS="/bin/ /sbin/ /etc/ /run/ /t/ /w/@777:0:0 /home/@755:1000:1000"
ETC="/etc/passwd=$TMPD/passwd@644:0:0 /etc/shadow=$TMPD/shadow@600:0:0"
DATA="/t/pw.txt=$TMPD/pw.txt@644:0:0 /t/bad.txt=$TMPD/bad.txt@644:0:0
      /t/rootpw.txt=$TMPD/rootpw.txt@644:0:0 /t/neu.txt=$TMPD/neu.txt@644:0:0
      /t/rechte.sh=$TMPD/rechte.sh@644:0:0
      /t/dienste.sh=$TMPD/dienste.sh@644:0:0
      /t/passwd.sh=$TMPD/passwd.sh@644:0:0"

python3 tools/osum/mkfs.py build "$TMPD/d0.img" $BLOCKS $DIRS $SPEC $ETC $DATA \
    "/etc/inittab=$TMPD/inittab@644:0:0" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py baut ein Abbild der Fassung 2 mit Rechten und Eigentuemern" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }
python3 tools/osum/mkfs.py build "$TMPD/dl.img" $BLOCKS $DIRS $SPEC $ETC $DATA \
    "/etc/inittab=$TMPD/inittab-login@644:0:0" >/dev/null 2>&1
python3 tools/osum/mkfs.py build "$TMPD/dv1.img" $BLOCKS --v1 $DIRS $SPEC $ETC $DATA \
    "/etc/inittab=$TMPD/inittab@644:0:0" >/dev/null 2>&1 \
    && ok "mkfs.py baut auch ein Abbild der Fassung 1 (--v1)" \
    || bad "mkfs.py --v1 fehlgeschlagen"

m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /bin/passwd)
is "die Rechte von /bin/passwd im Abbild" "$m" "/bin/passwd 4755 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /etc/shadow)
is "die Rechte von /etc/shadow im Abbild" "$m" "/etc/shadow 600 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/dv1.img" /bin/passwd)
is "dieselbe Datei in der Fassung 1 (dort gibt es keine Rechte)" \
   "$m" "/bin/passwd 755 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/dv1.img" /etc/shadow)
is "und auch /etc/shadow traegt dort keine (alles 0o755, alles root)" \
   "$m" "/etc/shadow 755 0 0"

# ---------------------------------------------------------- 3. die Laeufe

run_case() { # name kernel abbild anhang [zeitlimit]
    local name=$1 kern=$2 img=$3 app=$4 limit=${5:-240}
    cp "$img" "$TMPD/live-$name.img"
    timeout "$limit" qemu-system-x86_64 -kernel "$kern" -m 128 \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $?
}

echo "== 3. Kennungen in Ring 3, ohne Platte (kernel/uprog.fi) =="
rc=$(timeout 90 qemu-system-x86_64 -kernel "$TMPD/k0.img" -m 128 \
    -append "k13run zombie nokbd nosched noproc nofs noring3" \
    -serial "file:$TMPD/ids.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1; echo $?)
F="$TMPD/ids.txt"
is "der Lauf endet ordentlich" "$rc" "21"
is "die Bootaufgabe ist root, und der erste Prozess erbt es" \
   "$(grep -aoE 'k13u: uid=[0-9]+' "$F" | sed -n 1p | grep -oE '[0-9]+$')" "0"
is "auch die wirksame Kennung" \
   "$(grep -aoE 'k13u: euid=[0-9]+' "$F" | sed -n 1p | grep -oE '[0-9]+$')" "0"
is "umask gibt die ALTE Maske zurueck" "$(val "$F" 'k13u: umask0=[0-9]+')" "0"
is "und beim zweiten Mal die eben gesetzte (0o022)" \
   "$(val "$F" 'k13u: umask1=[0-9]+')" "18"
is "root legt die wirksame Kennung ab" "$(val "$F" 'k13u: dropeu=[0-9]+')" "7"
is "und holt sie ueber die ECHTE zurueck" "$(val "$F" 'k13u: backeu=[0-9]+')" "0"
is "setuid als root gelingt" "$(val "$F" 'k13u: setuid=[0-9]+')" "0"
is "danach ist die echte Kennung 7" "$(val "$F" 'k13u: uid=[0-9]+')" "7"
is "und die Gruppe 5" "$(val "$F" 'k13u: gid=[0-9]+')" "5"
is "GEGENPROBE: setuid(0) danach ist -EPERM und nicht 0" \
   "$(val "$F" 'k13u: reroot=-?[0-9]+')" "-1"
is "getresuid: die echte" "$(val "$F" 'k13u: r=[0-9]+')" "7"
is "getresuid: die wirksame" "$(val "$F" 'k13u: e=[0-9]+')" "7"
is "getresuid: die gesicherte" "$(val "$F" 'k13u: s=[0-9]+')" "7"
is "DIE KENNUNG UEBERLEBT fork (das Kind meldet sie im Beendigungscode)" \
   "$(val "$F" 'k13u: childu=[0-9]+')" "7"
zb=$(grep -aoE 'k13: zombies=[0-9]+ after=[0-9]+' "$F" | tail -1)
is "GEGENPROBE ZU init: ohne Prozess 1 bleibt die Waise als Leiche stehen" \
   "$zb" "k13: zombies=0 after=1"

echo "== 4. Rechte: derselbe Test als root und als justin =="
rc=$(run_case rechte "$TMPD/k0.img" "$TMPD/d0.img" \
    "osum nokbd nosched noproc nofs noring3 script=sh /t/rechte.sh")
F="$TMPD/rechte.txt"
is "die Maschine schaltet sich ueber ACPI ab (0), nicht ueber den Pruefstand (21)" \
   "$rc" "0"
has "$F" "k13t: sha=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" \
    "SHA-256(\"abc\") ist der Wert aus FIPS 180-4"
python3 - "$F" <<'PY' > "$TMPD/hash.txt" 2>&1
import binascii, hashlib, hmac, re, sys
raw = open(sys.argv[1], "rb").read().decode("latin1")
def got(tag):
    m = re.findall(r"k13t: %s=([0-9a-f]{64})" % tag, raw)
    return m[0] if m else ""
want = {
    "sha": hashlib.sha256(b"abc").hexdigest(),
    "hmac": hmac.new(b"key", b"The quick brown fox", hashlib.sha256).hexdigest(),
    "kdf": binascii.hexlify(
        hashlib.pbkdf2_hmac("sha256", b"geheim12", b"saltsalt", 2048, 32)).decode(),
}
for k, v in want.items():
    print("%s %s" % (k, "gleich" if got(k) == v else "UNGLEICH %s != %s" % (got(k), v)))
PY
for t in sha hmac kdf; do
    line=$(grep "^$t " "$TMPD/hash.txt")
    if [ "$line" = "$t gleich" ]; then ok "$t stimmt mit Pythons hashlib ueberein"
    else bad "$t: $line"; fi
done
is "ein Eintrag wird gebaut und wiedererkannt" \
   "$(val "$F" 'k13t: rndtrip=[0-9]+')" "1"
is "GEGENPROBE: ein FALSCHES Passwort wird abgelehnt" \
   "$(val "$F" 'k13t: wrong=[0-9]+')" "0"

nth() { grep -aoE "k13t: $2=-?[0-9]+" "$1" | sed -n "$3p" | grep -oE '\-?[0-9]+$'; }
is "root: die eigene Kennung" "$(nth "$F" uid 1)" "0"
is "justin: die eigene Kennung nach su" "$(nth "$F" uid 2)" "1000"
is "root oeffnet seine Datei mit 0o600" "$(nth "$F" openown 1)" "1"
is "justin oeffnet seine Datei mit 0o600" "$(nth "$F" openown 2)" "1"
is "die Rechtebits kommen aus dem Inode zurueck (0o600 = 384)" \
   "$(nth "$F" mode 1)" "384"
is "0o666 abzueglich umask 0o027 ist 0o640 = 416" "$(nth "$F" newm 1)" "416"
is "root darf eine Datei mit 0o000 lesen (so ist die Regel)" \
   "$(nth "$F" opendeny 1)" "1"
is "justin darf es NICHT" "$(nth "$F" opendeny 2)" "0"
is "root liest /etc/shadow" "$(nth "$F" wdeny 1)" "1"
is "justin liest /etc/shadow NICHT" "$(nth "$F" wdeny 2)" "0"
has "$F" "uid=1000(justin) gid=1000 euid=1000(justin) egid=1000" \
    "id nennt Kennung UND Namen aus /etc/passwd"
has "$F" "su: falsches Passwort" "su lehnt ein falsches Passwort ab"
is "und gibt dabei 1 zurueck" "$(val "$F" 'badpw=[0-9]+')" "1"
has "$F" "uid=0(root) gid=0 euid=0(root) egid=0" \
    "MIT dem richtigen Passwort wird justin zu root"

A="$TMPD/live-rechte.img"
m=$(python3 tools/osum/mkfs.py meta "$A" /w/root.txt)
is "chmod 4755 steht wirklich im Inode" "$m" "/w/root.txt 4755 0 0"
m=$(python3 tools/osum/mkfs.py meta "$A" /w/rootneu.txt)
is "chown justin:justin steht wirklich im Inode" "$m" "/w/rootneu.txt 640 1000 1000"
m=$(python3 tools/osum/mkfs.py meta "$A" /w/ju.txt)
is "die Datei, die justin angelegt hat, gehoert justin" "$m" "/w/ju.txt 644 1000 1000"

kc=$(val "$F" 'checks=[0-9]+')
kd=$(val "$F" 'denied=[0-9]+')
if [ "${kc:-0}" -gt 100 ]; then ok "der Kern hat $kc Rechtefragen beantwortet"
else bad "nur ${kc:-0} Rechtefragen -- da fragt niemand"; fi
if [ "${kd:-0}" -gt 0 ]; then ok "davon $kd abgelehnt"
else bad "keine einzige Ablehnung -- die Pruefung sagt immer ja"; fi
sx=$(val "$F" 'suidexec=[0-9]+')
if [ "${sx:-0}" -gt 0 ]; then ok "das setuid-Bit hat $sx mal gegriffen"
else bad "das setuid-Bit hat nie gegriffen"; fi

echo "== 5. GEGENPROBEN: noperm, nosuid, ofsv2raw =="
rc=$(run_case noperm "$TMPD/k0.img" "$TMPD/d0.img" \
    "osum noperm nokbd nosched noproc nofs noring3 script=sh /t/rechte.sh")
G="$TMPD/noperm.txt"
is "GEGENPROBE noperm: justin darf jetzt die Datei mit 0o000 lesen" \
   "$(nth "$G" opendeny 2)" "1"
is "GEGENPROBE noperm: justin liest jetzt auch /etc/shadow" "$(nth "$G" wdeny 2)" "1"
kd=$(val "$G" 'denied=[0-9]+')
if [ "${kd:-0}" -gt 0 ]; then
    ok "und der Zaehler der Ablehnungen steht trotzdem bei $kd -- gezaehlt wird, nur nicht gewirkt"
else bad "mit noperm wird nicht einmal mehr gezaehlt"; fi

rc=$(run_case nosuid "$TMPD/k0.img" "$TMPD/d0.img" \
    "osum nosuid nokbd nosched noproc nofs noring3 script=sh /t/rechte.sh")
G="$TMPD/nosuid.txt"
has "$G" "su: kein Eintrag in shadow" \
    "GEGENPROBE nosuid: ohne das setuid-Bit kommt su nicht an /etc/shadow"
is "und der Zaehler bleibt bei null" "$(val "$G" 'suidexec=[0-9]+')" "0"

rc=$(run_case v1 "$TMPD/k0.img" "$TMPD/dv1.img" \
    "osum nokbd nosched noproc nofs noring3 script=sh /t/rechte.sh")
G="$TMPD/v1.txt"
is "ein Abbild der Fassung 1 wird als Fassung 1 eingehaengt" \
   "$(val "$G" 'k13: ofsver=[0-9]+')" "1"
has "$G" "uid=0(root)" "und ist vollstaendig lesbar -- die Programme laufen"

rc=$(run_case v2raw "$TMPD/k0.img" "$TMPD/dv1.img" \
    "osum ofsv2raw nokbd nosched noproc nofs noring3 script=sh /t/rechte.sh")
G="$TMPD/v2raw.txt"
hasnot "$G" "uid=0(root) gid=0 euid=0(root) egid=0" \
    "GEGENPROBE ofsv2raw: dasselbe Abbild mit den Regeln der Fassung 2 bricht zusammen"

echo "== 6. der erste Prozess: init, Dienste, Waisen, Abschaltung =="
rc=$(run_case init "$TMPD/k0.img" "$TMPD/d0.img" \
    "osum nokbd nosched noproc nofs noring3 script=sh /t/dienste.sh")
F="$TMPD/init.txt"
is "die Maschine faehrt ueber ACPI herunter (QEMU beendet sich mit 0)" "$rc" "0"
has "$F" "osum: pid1 init" "der Kern startet /sbin/init und nicht die Shell"
has "$F" "init: dienste=2" "init liest /etc/inittab und findet zwei Dienste"
hasnot "$F" "init: ich bin nicht der Prozess 1" "init IST der Prozess 1"
is "und der Kern sagt es auch" "$(val "$F" 'init=[0-9]+')" "1"
first=$(grep -aoE '^blink running [0-9]+ [0-9]+' "$F" | sed -n '1p' | awk '{print $4}')
later=$(grep -aoE '^blink running [0-9]+ [0-9]+' "$F" | sed -n '2p' | awk '{print $4}')
if [ -n "${later:-}" ] && [ "$later" -gt "${first:-0}" ]; then
    ok "ein Dienst mit respawn wird neu gestartet: $first -> $later Starts"
else bad "der Dienst wurde nicht neu gestartet (${first:-?} -> ${later:-?})"; fi
has "$F" "blink done" "svc stop haelt ihn an"
last=$(grep -aoE '^blink running [0-9]+ [0-9]+' "$F" | tail -1 | awk '{print $4}')
if [ -n "${last:-}" ] && [ "$last" -gt "${later:-0}" ]; then
    ok "svc start startet ihn wieder ($last Starts)"
else bad "svc start hat nicht gestartet (${later:-?} -> ${last:-?})"; fi
is "DIE WAISE FAELLT AN DEN PROZESS 1 und wird eingesammelt" \
   "$(val "$F" 'init: orphans=[0-9]+')" "1"
is "und am Ende steht keine Leiche mehr" "$(val "$F" 'zombies=[0-9]+')" "0"
has "$F" "power: acpi pm1a=" "die Abschaltung liest FADT und _S5_ aus der ACPI-Tafel"

rc=$(run_case noacpi "$TMPD/k0.img" "$TMPD/d0.img" \
    "osum noacpi nokbd nosched noproc nofs noring3 script=sh /t/dienste.sh")
is "GEGENPROBE noacpi: derselbe Lauf endet ueber den Pruefstand (21) statt ueber ACPI (0)" \
   "$rc" "21"

rc=$(run_case initsh "$TMPD/k0.img" "$TMPD/d0.img" \
    "osum initsh nokbd nosched noproc nofs noring3 script=id")
F="$TMPD/initsh.txt"
is "DER NOTWEG: mit initsh endet der Lauf wie vor dieser Runde" "$rc" "21"
hasnot "$F" "osum: pid1 init" "und zwar mit /bin/sh statt /sbin/init"
has "$F" "sh: ready, osum" "die Shell startet unmittelbar aus dem Kern"
has "$F" "uid=0(root)" "das System ist damit vollstaendig benutzbar"

echo "== 7. die Anmeldung: Name und Passwort ueber die Konsole =="
rc=$(run_case login "$TMPD/k0.img" "$TMPD/dl.img" \
    "osum nokbd nosched noproc nofs noring3 script=justin;geheim12;id;whoami;exit")
F="$TMPD/login.txt"
is "der Lauf endet ueber ACPI" "$rc" "0"
has "$F" "osum login: " "init startet /bin/login, und es fragt nach dem Namen"
has "$F" "willkommen justin" "das Passwort stimmt"
has "$F" "uid=1000(justin) gid=1000 euid=1000(justin) egid=1000" \
    "die Shell dahinter laeuft als justin -- gemessen, nicht behauptet"
hasnot "$F" "Anmeldung falsch" "kein Fehlversuch dabei"

rc=$(run_case loginbad "$TMPD/k0.img" "$TMPD/dl.img" \
    "osum nokbd nosched noproc nofs noring3 script=justin;falsch99;justin;falsch99;justin;falsch99")
F="$TMPD/loginbad.txt"
has "$F" "Anmeldung falsch" "GEGENPROBE: ein falsches Passwort wird abgelehnt"
hasnot "$F" "willkommen justin" "und niemand kommt herein"

echo "== 8. passwd schreibt wirklich in /etc/shadow =="
rc=$(run_case pw "$TMPD/k0.img" "$TMPD/d0.img" \
    "osum nokbd nosched noproc nofs noring3 script=sh /t/passwd.sh")
F="$TMPD/pw.txt"
has "$F" "passwd: gesetzt fuer justin" "passwd meldet Erfolg"
python3 tools/osum/mkfs.py cat "$TMPD/live-pw.img" /etc/shadow > "$TMPD/shadow.neu" 2>&1
python3 - "$TMPD/shadow.neu" <<'PY' > "$TMPD/pwcheck.txt" 2>&1
import binascii, hashlib, sys
raw = open(sys.argv[1], "rb").read()
rec = ""
for l in raw.decode("latin1").splitlines():
    f = l.split(":")
    if len(f) > 1 and f[0] == "justin":
        rec = f[1]
if not rec.startswith("$osum1$"):
    print("kein osum1-Eintrag: %r" % rec[:40])
    raise SystemExit
_, _, it, salt, dk = rec.split("$", 4)
neu = binascii.hexlify(hashlib.pbkdf2_hmac(
    "sha256", b"neuneu77", binascii.unhexlify(salt), int(it), 32)).decode()
alt = binascii.hexlify(hashlib.pbkdf2_hmac(
    "sha256", b"geheim12", binascii.unhexlify(salt), int(it), 32)).decode()
print("klartext" if b"neuneu77" in raw else "keinklartext")
print("runden %s" % it)
print("salzlaenge %d" % (len(salt) // 2))
print("neu %s" % ("stimmt" if dk == neu else "STIMMT NICHT"))
print("alt %s" % ("stimmt" if dk == alt else "stimmt nicht"))
PY
grep -q '^keinklartext' "$TMPD/pwcheck.txt" \
    && ok "das Passwort steht NICHT im Klartext in /etc/shadow" \
    || bad "das Passwort steht im Klartext in /etc/shadow"
grep -q '^runden 2048' "$TMPD/pwcheck.txt" \
    && ok "der Eintrag traegt seine Rundenzahl (2048) bei sich" \
    || bad "die Rundenzahl fehlt: $(grep '^runden' "$TMPD/pwcheck.txt" || true)"
grep -q '^salzlaenge 8' "$TMPD/pwcheck.txt" \
    && ok "und acht Oktette Salz aus getrandom" \
    || bad "die Salzlaenge stimmt nicht: $(grep '^salzlaenge' "$TMPD/pwcheck.txt" || true)"
grep -q '^neu stimmt' "$TMPD/pwcheck.txt" \
    && ok "PYTHON rechnet denselben Wert aus dem NEUEN Passwort -- es ist PBKDF2-HMAC-SHA256" \
    || bad "Python kommt auf einen anderen Wert: $(grep '^neu' "$TMPD/pwcheck.txt" || true)"
grep -q '^alt stimmt nicht' "$TMPD/pwcheck.txt" \
    && ok "GEGENPROBE: aus dem ALTEN Passwort kommt ein anderer Wert" \
    || bad "altes und neues Passwort ergeben denselben Wert"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/live-pw.img" /etc/shadow)
is "und /etc/shadow gehoert weiter root und traegt 0o600" "$m" "/etc/shadow 600 0 0"

echo "== 9. der zweite Uebersetzer =="
if bash tools/build-kernel.sh "$TMPD/k1.img" --stufe 1 > "$TMPD/b1.txt" 2>&1; then
    ok "firnc1 baut denselben Kern"
    if build_progs 1; then
        ok "firnc1 baut dieselben Programme"
        # NUR DIE PROGRAMME, DIE DIESER FALL BRAUCHT. Das Abbild kann
        # nicht groesser werden: die Blockkarte von OFS ist EIN Block,
        # also 512 * 8 = 4096 Bloecke = 2 MiB, und mehr Bloecke kann
        # `block_alloc` nicht vergeben (kernel/fs.fi). Das Userland aus
        # firnc1 ist groesser als das aus firnc0 und passt vollstaendig
        # nicht hinein -- also die zehn, die `rechte.sh` und
        # `/etc/inittab` wirklich anfassen.
        SPEC1=""
        for p in sh echo sleep id whoami k13t chmod chown su init; do
            case $p in
                su|passwd) SPEC1="$SPEC1 /bin/$p=$TMPD/${p}1.elf@4755:0:0" ;;
                init)      SPEC1="$SPEC1 /sbin/init=$TMPD/${p}1.elf@755:0:0" ;;
                *)         SPEC1="$SPEC1 /bin/$p=$TMPD/${p}1.elf" ;;
            esac
        done
        python3 tools/osum/mkfs.py build "$TMPD/d1.img" $BLOCKS $DIRS \
            $SPEC1 $ETC $DATA "/etc/inittab=$TMPD/inittab@644:0:0" \
            > "$TMPD/mkfs1.txt" 2>&1 \
            && ok "und ein Abbild daraus" \
            || { bad "mkfs.py scheitert am Userland von firnc1"
                 sed 's/^/        /' "$TMPD/mkfs1.txt" | head -4; }
        rc=$(run_case stufe1 "$TMPD/k1.img" "$TMPD/d1.img" \
            "osum nokbd nosched noproc nofs noring3 script=sh /t/rechte.sh")
        G="$TMPD/stufe1.txt"
        is "und derselbe Lauf endet ebenso ueber ACPI" "$rc" "0"
        is "justin darf die Datei mit 0o000 auch dort nicht" "$(nth "$G" opendeny 2)" "0"
        has "$G" "k13t: kdf=dcf06f20c853126acc0b866d93a4fbcc6c816f5e68d90e59f532f32b1a33ed38" \
            "und PBKDF2 liefert dieselben 64 Hexziffern"
    else
        bad "firnc1 baut die Programme nicht"
    fi
else
    bad "firnc1 baut den Kern nicht"
    sed 's/^/        /' "$TMPD/b1.txt" | head -8
fi

echo
echo "K13: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
