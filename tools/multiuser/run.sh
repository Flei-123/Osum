#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/multiuser/run.sh -- MEHRBENUTZERBETRIEB, GEMESSEN (Runde MULTIUSER).
#
# ==================================================================
# WAS DIESE RUNDE BEHAUPTET UND WAS HIER NACHGERECHNET WIRD
# ==================================================================
#
# Runde K13 hat Benutzer, Rechte und die Anmeldung gebaut und AM ENDE
# EINE LISTE MIT GRENZEN HINGESCHRIEBEN. Diese Runde arbeitet die Liste
# ab, und dieser Laeufer misst genau das:
#
#   1. DAS BETRETUNGSRECHT AUF JEDEM GLIED EINES PFADES. Vorher wurde
#      nur nach der Zieldatei gefragt: ein Verzeichnis 0o700 root:root
#      schuetzte seinen Inhalt NICHT, wenn die Datei darin 0o644 war und
#      man ihren Namen kannte. Gemessen mit zwei Wegen zu zwei gleichen
#      Dateien -- einer offen, einer verschlossen -- und der GEGENPROBE
#      `nowalk`, in der die Messung zusammenbricht.
#   2. ZUSATZGRUPPEN. /etc/group, getgroups/setgroups, initgroups in
#      login und su. Gemessen an einer Datei 0o640 root:projekt, an die
#      `justin` NUR ueber die Nebengruppe kommt. Gegenprobe `nogroups`.
#   3. RECHTE UEBER DIE VFS-SCHICHT. `open_vfs` hatte KEINE Pruefung --
#      kein /dev, kein /proc und keine eingehaengte Platte wurde je
#      gefragt. Gemessen an /dev/hda (0o644 root): lesen ja, schreiben
#      nur root.
#   4. DER KOSTENFAKTOR. Nicht behauptet, sondern gemessen: wie lange
#      eine Pruefung dauert und dass die Zeit MIT DER RUNDENZAHL
#      WAECHST. Aus dieser Messung folgt die Zahl in pw.fi.
#   5. DIE VERZOEGERUNG NACH EINEM FEHLVERSUCH, und dass sie sich
#      verdoppelt -- an den Zahlen, die `login` nennt, UND an der Uhr
#      des Wirts, und mit zwei /etc/login.conf, damit auch bewiesen ist,
#      dass die Datei gelesen wird.
#   6. DIE AUFRUFNUMMERN, gegen beide Tabellen, plus die GEGENPROBE, die
#      den Fehler von Runde MERGE (zweimal 1320) nachbaut.
#   7. setuid VON EINEM GEWOEHNLICHEN BENUTZER AUF root SCHLAEGT FEHL.
#   8. chmod UND chown WIRKEN -- nachgelesen AUS DEM ABBILD.
#   9. passwd schreibt ueber eine Zwischendatei, und /etc/shadow traegt
#      danach weiter 0o600 root:root.
#
# ==================================================================
# WARUM -accel kvm
# ==================================================================
#
# Diese Runde ist die erste, die RECHNET: eine Passwortpruefung ist 8192
# mal HMAC-SHA256. Unter QEMUs Softwareemulation kostet das rund 1,8
# Sekunden, auf der echten CPU 0,26 -- gemessen in Abschnitt 3. Ein
# Laeufer mit zwanzig solchen Pruefungen ist damit der Unterschied
# zwischen einer halben Minute und zehn.
#
# ABER KVM IST NICHT DIE MESSUNG, SONDERN NUR SCHNELLER. Deshalb laeuft
# der rechenlastige Abschnitt ZWEIMAL -- unter KVM und unter TCG -- und
# die Aussagen ueber die RECHTE werden gegeneinander gehalten. Waere
# eine davon unter KVM eine andere, waere die Beschleunigung wertlos.
# Ohne /dev/kvm faellt der Laeufer auf TCG zurueck und sagt es, statt zu
# ueberspringen.
#
# Aufruf:  bash tools/multiuser/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=4096

PROGS="sh echo cat id whoami chmod chown su passwd login init sleep mut"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
[ -n "${KEEP_TMPD:-}" ] && trap - EXIT && echo "TMPD=$TMPD"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
mval() { grep -aoE "mut: $2=-?[0-9]+" "$1" | sed -n "${3:-1}p" | grep -oE '\-?[0-9]+$'; }
mlast() { grep -aoE "mut: $2=-?[0-9]+" "$1" | tail -1 | grep -oE '\-?[0-9]+$'; }
# Die Zeile dieser Runde hat ihr eigenes Praefix. Runde MERGE hat
# gelernt, was passiert, wenn zwei Runden dasselbe Feld auf dieselbe
# Leitung schreiben: `tail -1` nimmt die falsche Null.
muval() { grep -aoE "^mu: .*" "$1" | tail -1 \
    | grep -oE "(^| )$2=[0-9]+" | tail -1 | grep -oE '[0-9]+$'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "MULTIUSER: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

ACCEL=""
KVM=0
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-accel kvm -cpu host"
    KVM=1
fi

# ------------------------------------------------------------- 1. bauen

echo "== 1. bauen, die Speicherkarte und DIE AUFRUFNUMMERN =="

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "firnc0 baut den Kern mit Betretungsrecht und Zusatzgruppen" \
    || { bad "firnc0 baut den Kern nicht"; sed 's/^/        /' "$TMPD/b0.txt" | head -12; }
[ -f "$TMPD/k0.img" ] || { echo "MULTIUSER: $pass passed, $((fail+1)) failed"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s uebersetzt nicht"
rc=0
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 || {
        bad "firnc0 uebersetzt $p.fi nicht"
        sed 's/^/        /' "$TMPD/e$p" | head -6; rc=1; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || {
        bad "ld scheitert an $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$rc" = 0 ] && ok "firnc0 baut $(echo $PROGS | wc -w) Programme in Ring 3" \
              || bad "nicht alle Programme gebaut"

undef=""
for p in mut login su passwd id; do
    u=$(nm -u "$TMPD/$p.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "kein Programm dieser Runde hat ein undefiniertes Symbol" \
               || bad "undefinierte Symbole:$undef"

if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "$(tail -1 "$TMPD/karte.txt")"
else
    bad "der Kartenpruefer schlaegt an"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi
grep -q '"MU"' tools/kernel/memmap.py \
    && ok "der Bereich dieser Runde (MU_OFF) steht in der Speicherkarte" \
    || bad "MU_OFF fehlt in tools/kernel/memmap.py"

if python3 tools/kernel/syscalls.py > "$TMPD/sys.txt" 2>&1; then
    ok "$(tail -1 "$TMPD/sys.txt")"
else
    bad "die Aufrufnummern kollidieren"; sed 's/^/        /' "$TMPD/sys.txt"
fi
for n in "SYS_GETGROUPS 115" "SYS_SETGROUPS 116" "SYS_OSUM_MUSTAT 1200"; do
    set -- $n
    a=$(grep -oE "^const $1: u64 = [0-9]+" kernel/sys.fi | grep -oE '[0-9]+$')
    b=$(grep -oE "^const $1: u64 = [0-9]+" lib/libc/kcall.fi | grep -oE '[0-9]+$')
    if [ "$a" = "$2" ] && [ "$b" = "$2" ]; then
        ok "$1 = $2 im Kernel UND in der libc"
    else
        bad "$1: Kernel '$a', libc '$b', erwartet '$2'"
    fi
done
# ---- DIE GEGENPROBE: der Fehler von Runde MERGE, nachgebaut.
mkdir -p "$TMPD/kol/kernel" "$TMPD/kol/lib/libc" "$TMPD/kol/tools/kernel"
cp kernel/sys.fi "$TMPD/kol/kernel/"
cp lib/libc/kcall.fi "$TMPD/kol/lib/libc/"
cp tools/kernel/syscalls.py "$TMPD/kol/tools/kernel/"
sed -i 's/^const SYS_OSUM_MUSTAT: u64 = 1200/const SYS_OSUM_MUSTAT: u64 = 1320/' \
    "$TMPD/kol/kernel/sys.fi"
if python3 "$TMPD/kol/tools/kernel/syscalls.py" > "$TMPD/kol.txt" 2>&1; then
    bad "GEGENPROBE: zweimal 1320 faellt NICHT auf -- der Waechter ist wertlos"
else
    grep -q '1320 ist 2 mal vergeben' "$TMPD/kol.txt" \
        && ok "GEGENPROBE: zweimal 1320 -- genau der Fehler von Runde MERGE -- faellt auf" \
        || bad "GEGENPROBE faellt, aber anders: $(head -1 "$TMPD/kol.txt")"
fi

# ------------------------------------------------------- 2. die Abbilder

echo "== 2. die Abbilder: /etc/passwd, /etc/group, /etc/shadow, /etc/login.conf =="

ITERS=$(grep -oE '^const KOSTEN: u64 = [0-9]+' kernel/user/pw.fi | grep -oE '[0-9]+$')
if [ -n "$ITERS" ]; then
    ok "der Kostenfaktor steht als Zahl im Quelltext (pw.fi KOSTEN = $ITERS)"
else
    bad "KOSTEN fehlt in kernel/user/pw.fi"; ITERS=8192
fi

python3 - "$TMPD" "$ITERS" <<'PY'
import binascii, hashlib, sys
d, it = sys.argv[1], int(sys.argv[2])
def rec(pw, salt):
    dk = hashlib.pbkdf2_hmac('sha256', pw, salt, it, 32)
    return "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(),
                                binascii.hexlify(dk).decode())
open(d + "/passwd", "w").write(
    "root:x:0:0:root:/:/bin/sh\n"
    "justin:x:1000:1000:Justin:/home/justin:/bin/sh\n"
    "mara:x:1001:1001:Mara:/home/mara:/bin/sh\n")
open(d + "/group", "w").write(
    "root:x:0:\n"
    "justin:x:1000:\n"
    "mara:x:1001:\n"
    "projekt:x:2000:justin,mara\n"
    "gaeste:x:2001:mara\n")
open(d + "/shadow", "w").write(
    "root:%s:0:0:99999:7:::\n" % rec(b"rootpass", bytes(range(8))) +
    "justin:%s:0:0:99999:7:::\n" % rec(b"geheim12", bytes(range(8, 16))) +
    "mara:%s:0:0:99999:7:::\n" % rec(b"marapass", bytes(range(16, 24))))
open(d + "/pw.txt", "w").write("geheim12\n")
open(d + "/neu.txt", "w").write("geheim12\nneuneu77\nneuneu77\n")
open(d + "/geheim.txt", "w").write("DAS-IST-GEHEIM\n")
open(d + "/offen.txt", "w").write("DAS-IST-OFFEN\n")
open(d + "/plan.txt", "w").write("PROJEKTPLAN\n")
open(d + "/nurroot.txt", "w").write("NUR-ROOT\n")
open(d + "/fueralle.txt", "w").write("FUER-ALLE\n")
open(d + "/login.conf.langsam", "w").write(
    "# die Vorgaben dieser Maschine\nverzoegerung_ms = 1000\nmax_versuche = 3\n")
open(d + "/login.conf.schnell", "w").write(
    "verzoegerung_ms = 200\nmax_versuche = 3\n")
PY

printf '# name:art:befehl\nsh:ctrl:/bin/sh\n' > "$TMPD/inittab"
printf '# name:art:befehl\nlogin:ctrl:/bin/login\n' > "$TMPD/inittab-login"

cat > "$TMPD/alsroot.sh" <<'SCRIPT'
echo ==BEGIN==
id
mut werroot
mut pfad /auf/tief/inhalt.txt /zu/tief/inhalt.txt
mut gruppen /gemeinsam/plan.txt
cat /priv/nurroot.txt
cat /priv/fueralle.txt
mut stat
echo ==END==
SCRIPT

cat > "$TMPD/alsjustin.sh" <<'SCRIPT'
echo ==BEGIN==
su justin /bin/id < /t/pw.txt
su justin /bin/mut pfad /auf/tief/inhalt.txt /zu/tief/inhalt.txt < /t/pw.txt
su justin /bin/mut gruppen /gemeinsam/plan.txt < /t/pw.txt
su justin /bin/mut werroot < /t/pw.txt
su justin /bin/cat /priv/nurroot.txt < /t/pw.txt
su justin /bin/cat /priv/fueralle.txt < /t/pw.txt
su justin /bin/cat /zu/tief/inhalt.txt < /t/pw.txt
su justin /bin/cat /auf/tief/inhalt.txt < /t/pw.txt
mut stat
echo ==END==
SCRIPT

cat > "$TMPD/dev.sh" <<'SCRIPT'
echo ==BEGIN==
su justin /bin/mut dev < /t/pw.txt
mut dev
mut stat
echo ==END==
SCRIPT

cat > "$TMPD/aendern.sh" <<'SCRIPT'
echo ==BEGIN==
cat /priv/fueralle.txt > /w/kopie.txt
chmod 640 /w/kopie.txt
chown justin:projekt /w/kopie.txt
mut kdf 2048
mut kdf 8192
echo ==END==
SCRIPT

cat > "$TMPD/passwd.sh" <<'SCRIPT'
echo ==BEGIN==
su justin /bin/passwd < /t/neu.txt
echo pwrc=$?
echo ==END==
SCRIPT

SPEC=""
for p in $PROGS; do
    case $p in
        su|passwd) SPEC="$SPEC /bin/$p=$TMPD/${p}.elf@4755:0:0" ;;
        init)      SPEC="$SPEC /sbin/init=$TMPD/${p}.elf@755:0:0" ;;
        *)         SPEC="$SPEC /bin/$p=$TMPD/${p}.elf" ;;
    esac
done
# DIE VERZEICHNISSE SIND DIE MESSUNG. /geheim ist 0o700 root:root und
# enthaelt eine Datei mit 0o644 -- vor dieser Runde kam man an sie heran.
# ZWEI EBENEN, UND DAS IST DER GANZE PUNKT. Runde K13 hat das
# UNMITTELBARE Elternverzeichnis schon geprueft (`sys.dir_allowed`) --
# `/geheim/inhalt.txt` war also nie offen. Die Luecke war ALLES DARUEBER:
# bei `/zu/tief/inhalt.txt` wurde `/zu/tief` gefragt (0o755, also ja) und
# `/zu` NIE. Wer den Namen kannte, war drin. Genau diese Form steht hier,
# und `/geheim` daneben als Beleg, dass die eine Ebene schon vorher hielt.
DIRS="/bin/ /sbin/ /etc/ /run/ /proc/ /dev/ /t/ /w/@777:0:0
      /home/@755:0:0 /home/justin/@700:1000:1000
      /zu/@700:0:0 /zu/tief/@755:0:0
      /auf/@755:0:0 /auf/tief/@755:0:0
      /geheim/@700:0:0 /gemeinsam/@755:0:0 /priv/@755:0:0"
ETC="/etc/passwd=$TMPD/passwd@644:0:0 /etc/shadow=$TMPD/shadow@600:0:0
     /etc/group=$TMPD/group@644:0:0"
DATA="/t/pw.txt=$TMPD/pw.txt@644:0:0 /t/neu.txt=$TMPD/neu.txt@644:0:0
      /t/alsroot.sh=$TMPD/alsroot.sh@644:0:0
      /t/alsjustin.sh=$TMPD/alsjustin.sh@644:0:0
      /t/dev.sh=$TMPD/dev.sh@644:0:0
      /t/aendern.sh=$TMPD/aendern.sh@644:0:0
      /t/passwd.sh=$TMPD/passwd.sh@644:0:0
      /zu/tief/inhalt.txt=$TMPD/geheim.txt@644:0:0
      /auf/tief/inhalt.txt=$TMPD/offen.txt@644:0:0
      /geheim/inhalt.txt=$TMPD/geheim.txt@644:0:0
      /gemeinsam/plan.txt=$TMPD/plan.txt@640:0:2000
      /priv/nurroot.txt=$TMPD/nurroot.txt@600:0:0
      /priv/fueralle.txt=$TMPD/fueralle.txt@644:0:0"

python3 tools/osum/mkfs.py build "$TMPD/d0.img" $BLOCKS $DIRS $SPEC $ETC $DATA \
    "/etc/inittab=$TMPD/inittab@644:0:0" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py baut das Abbild dieser Runde" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -6; }
python3 tools/osum/mkfs.py build "$TMPD/dl.img" $BLOCKS $DIRS $SPEC $ETC $DATA \
    "/etc/inittab=$TMPD/inittab-login@644:0:0" \
    "/etc/login.conf=$TMPD/login.conf.langsam@644:0:0" >/dev/null 2>&1
python3 tools/osum/mkfs.py build "$TMPD/df.img" $BLOCKS $DIRS $SPEC $ETC $DATA \
    "/etc/inittab=$TMPD/inittab-login@644:0:0" \
    "/etc/login.conf=$TMPD/login.conf.schnell@644:0:0" >/dev/null 2>&1
{ [ -f "$TMPD/dl.img" ] && [ -f "$TMPD/df.img" ]; } \
    && ok "und zwei Anmeldeabbilder, die sich NUR in /etc/login.conf unterscheiden" \
    || bad "die Anmeldeabbilder fehlen"

m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /etc/group)
is "/etc/group liegt im Abbild und darf jeder lesen" "$m" "/etc/group 644 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /etc/shadow)
is "/etc/shadow gehoert root und traegt 0o600" "$m" "/etc/shadow 600 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /zu)
is "das verschlossene Verzeichnis traegt 0o700 root:root" "$m" "/zu 700 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /zu/tief)
is "das Verzeichnis DARIN traegt 0o755 -- es ist nicht das, was schuetzt" \
   "$m" "/zu/tief 755 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /zu/tief/inhalt.txt)
is "und die Datei ganz unten traegt 0o644 -- sie schuetzt gar nichts" \
   "$m" "/zu/tief/inhalt.txt 644 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /gemeinsam/plan.txt)
is "die Projektdatei gehoert root und der Gruppe 2000, 0o640" \
   "$m" "/gemeinsam/plan.txt 640 0 2000"

# --------------------------------------------------------- die Laeufe

# EIN LAUF. Er setzt ZWEI GLOBALE Variablen -- $RC und $DAUER -- und
# druckt nichts.
#
# WARUM NICHT `rc=$(run_case ...)`, wie es K13 tut: eine
# Befehlsersetzung laeuft in einer UNTERSCHALE, und was dort an $DAUER
# geschrieben wird, kommt hier nie an. Der erste Lauf dieser Runde hat
# genau das gemessen -- "drei Fehlversuche dauerten 0 ms laenger (0
# gegen 0)" --, und die Null war nicht die Verzoegerung, sondern die
# Unterschale. Die WANDZEIT ist hier keine Nebensache: sie ist der
# einzige Beweis, dass `login` wirklich gewartet hat und die Zahl nicht
# bloss hingeschrieben.
RC=0
DAUER=0
run_case() {
    local name=$1 img=$2 app=$3 limit=${4:-300}
    cp "$img" "$TMPD/live-$name.img"
    local s=$(date +%s%3N)
    timeout "$limit" qemu-system-x86_64 $ACCEL \
        -kernel "$TMPD/k0.img" -m 256 \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    RC=$?
    DAUER=$(( $(date +%s%3N) - s ))
}
run_tcg() {
    local name=$1 img=$2 app=$3 limit=${4:-900}
    cp "$img" "$TMPD/live-$name.img"
    timeout "$limit" qemu-system-x86_64 -kernel "$TMPD/k0.img" -m 256 \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    RC=$?
}

BASIS="nokbd nosched noproc nofs noring3 vfs"

echo "== 3. der Kostenfaktor, GEMESSEN (nicht abgeschrieben) =="
if [ "$KVM" = 1 ]; then
    ok "/dev/kvm ist da -- die rechenlastigen Laeufe gehen auf die ECHTE CPU"
else
    hin "kein /dev/kvm: alles laeuft unter TCG, also langsamer"
fi

run_case kdf "$TMPD/d0.img" "osum $BASIS murun script=sh /t/aendern.sh"
rc=$RC
F="$TMPD/kdf.txt"
is "der Lauf endet ueber ACPI (0), nicht ueber den Pruefstand (21)" "$rc" "0"
us2048=$(mval "$F" us 1)
us8192=$(mval "$F" us 2)
ps=$(mval "$F" rundenps 2)
if [ -n "${us8192:-}" ] && [ "${us8192:-0}" -gt 100000 ]; then
    ok "EINE Pruefung mit $ITERS Runden braucht messbar Zeit: ${us8192} us"
else
    bad "die Pruefung dauert keine messbare Zeit (${us8192:-?} us)"
fi
if [ -n "${us2048:-}" ] && [ "${us2048:-0}" -gt 0 ] && [ -n "${us8192:-}" ]; then
    v=$(( us8192 * 100 / us2048 ))
    if [ "$v" -ge 300 ] && [ "$v" -le 500 ]; then
        ok "viermal so viele Runden kosten viermal so viel Zeit (${v}/100) -- die Zahl WIRKT"
    else
        bad "das Verhaeltnis stimmt nicht: ${us2048} us zu ${us8192} us (${v}/100)"
    fi
else
    bad "die Messung mit 2048 Runden fehlt"
fi
[ -n "${ps:-}" ] && hin "gemessen: ${ps} PBKDF2-Runden je Sekunde in Ring 3"
hin "daraus folgt der Kostenfaktor $ITERS in kernel/user/pw.fi"

if [ "$KVM" = 1 ]; then
    run_tcg kdftcg "$TMPD/d0.img" "osum $BASIS murun script=sh /t/aendern.sh"
rc=$RC
    G="$TMPD/kdftcg.txt"
    is "derselbe Lauf unter TCG endet ebenso ueber ACPI" "$rc" "0"
    ustcg=$(mval "$G" us 2)
    if [ -n "${ustcg:-}" ] && [ "${us8192:-0}" -gt 0 ]; then
        f=$(( ustcg * 10 / us8192 ))
        ok "und braucht dort ${ustcg} us statt ${us8192} us -- KVM ist ${f}/10 mal schneller"
    else
        bad "die TCG-Messung fehlt"
    fi
fi

# --------------------------------------------- 4. Rechte, root und justin

echo "== 4. dieselben Dateien, einmal als root und einmal als justin =="

run_case root "$TMPD/d0.img" "osum $BASIS murun script=sh /t/alsroot.sh"
rc=$RC
R="$TMPD/root.txt"
is "der Lauf als root endet ueber ACPI" "$rc" "0"
run_case justin "$TMPD/d0.img" "osum $BASIS murun script=sh /t/alsjustin.sh"
rc=$RC
J="$TMPD/justin.txt"
is "der Lauf als justin endet ueber ACPI" "$rc" "0"

has "$R" "uid=0(root)" "root ist root"
has "$J" "uid=1000(justin)" "und justin ist justin -- su hat die Kennung gewechselt"
has "$R" "NUR-ROOT" "root liest die Datei mit 0o600 root:root"
hasnot "$J" "NUR-ROOT" "justin liest sie NICHT"
has "$R" "FUER-ALLE" "root liest die Datei mit 0o644"
has "$J" "FUER-ALLE" "und justin auch -- der Unterschied sind allein die Rechtebits"

echo "== 5. DAS BETRETUNGSRECHT: derselbe Inhalt, zwei Wege =="
is "root kommt durch das offene Verzeichnis" "$(mval "$R" pfadauf)" "1"
is "root kommt auch durch das verschlossene (root darf alles)" "$(mval "$R" pfadzu)" "1"
is "justin kommt durch das offene Verzeichnis" "$(mval "$J" pfadauf)" "1"
is "JUSTIN KOMMT NICHT DURCH /zu -- obwohl /zu/tief 0o755 und die Datei 0o644 traegt" \
   "$(mval "$J" pfadzu)" "0"
hasnot "$J" "DAS-IST-GEHEIM" "und cat bekommt den Inhalt auch nicht"
has "$J" "DAS-IST-OFFEN" "durch /auf/tief dagegen schon -- derselbe Text, anderer Weg"
hasnot "$J" "cat: /geheim/inhalt.txt" "und die EINE Ebene (/geheim, 0o700) hielt schon vor dieser Runde"
w=$(muval "$J" walks)
wd=$(muval "$J" walkdeny)
if [ "${w:-0}" -gt 10 ]; then ok "der Kern hat $w Pfade auf das Betretungsrecht geprueft"
else bad "nur ${w:-0} Pfadpruefungen -- da laeuft niemand"; fi
if [ "${wd:-0}" -gt 0 ]; then ok "und $wd davon abgelehnt"
else bad "keine einzige Ablehnung -- die Pfadpruefung sagt immer ja"; fi

run_case nowalk "$TMPD/d0.img" "osum $BASIS murun nowalk script=sh /t/alsjustin.sh"
rc=$RC
N="$TMPD/nowalk.txt"
is "GEGENPROBE nowalk: justin kommt jetzt an /zu/tief/inhalt.txt heran" \
   "$(mval "$N" pfadzu)" "1"
has "$N" "DAS-IST-GEHEIM" "GEGENPROBE nowalk: der Inhalt steht wirklich da -- das war der Zustand VOR dieser Runde"
wd=$(muval "$N" walkdeny)
if [ "${wd:-0}" -gt 0 ]; then
    ok "und der Zaehler steht trotzdem bei $wd -- gezaehlt wird, nur nicht gewirkt"
else bad "mit nowalk wird nicht einmal mehr gezaehlt"; fi

echo "== 6. ZUSATZGRUPPEN: /etc/group, getgroups, setgroups =="
is "root hat keine Zusatzgruppen (die Bootaufgabe erbt keine)" \
   "$(mval "$R" ngrps)" "0"
is "justin hat GENAU EINE -- projekt, aus /etc/group" "$(mval "$J" ngrps)" "1"
is "und sie ist die 2000" "$(mval "$J" grp)" "2000"
is "JUSTIN OEFFNET DIE DATEI 0o640 root:projekt -- ueber die NEBENgruppe" \
   "$(mval "$J" grpopen)" "1"
has "$J" "groups=2000(projekt)" "id nennt sie mit Namen aus /etc/group"
is "setgroups als GEWOEHNLICHER Benutzer ist -EPERM und nicht 0" \
   "$(mval "$J" setgrps)" "-1"
is "als root gelingt es" "$(mval "$R" setgrps)" "0"
g=$(muval "$J" grphits)
if [ "${g:-0}" -gt 0 ]; then ok "$g Zugriffe wurden von einer NEBENgruppe erlaubt"
else bad "keine Nebengruppe hat je gegriffen"; fi

run_case nogroups "$TMPD/d0.img" "osum $BASIS murun nogroups script=sh /t/alsjustin.sh"
rc=$RC
NG="$TMPD/nogroups.txt"
is "GEGENPROBE nogroups: dieselbe Datei bleibt fuer justin zu" \
   "$(mval "$NG" grpopen)" "0"
is "und die Liste steht trotzdem da -- gesetzt wird, nur nicht beachtet" \
   "$(mval "$NG" ngrps)" "1"

echo "== 7. setuid VON justin AUF root =="
is "justin ist justin" "$(mval "$J" uid)" "1000"
is "setuid(0) ist -EPERM und nicht 0" "$(mval "$J" setroot)" "-1"
is "setgid(0) ebenso" "$(mval "$J" setgroot)" "-1"
is "GEGENPROBE: als root gelingt dasselbe setuid(0)" "$(mval "$R" setroot)" "0"

echo "== 8. die Rechte ueber die VFS-Schicht (/dev, /proc) =="
run_case dev "$TMPD/d0.img" "osum $BASIS murun script=sh /t/dev.sh"
rc=$RC
D="$TMPD/dev.txt"
is "der Lauf endet ueber ACPI" "$rc" "0"
is "JUSTIN DARF /dev/hda NICHT BESCHREIBEN -- vor dieser Runde fragte open_vfs gar nicht" \
   "$(mval "$D" devwrite 1)" "0"
is "root darf es (0o644 root)" "$(mval "$D" devwrite 2)" "1"
is "justin darf /dev/null beschreiben (0o666)" "$(mval "$D" nullwrite 1)" "1"
is "und /proc/meminfo lesen (0o444)" "$(mval "$D" procread 1)" "1"
n=$(muval "$D" nodechk)
if [ "${n:-0}" -gt 0 ]; then ok "$n Rechtefragen gingen ueber die VFS-Schicht"
else bad "die VFS-Schicht hat nie gefragt"; fi

echo "== 9. chmod und chown wirken -- nachgelesen AUS DEM ABBILD =="
m=$(python3 tools/osum/mkfs.py meta "$TMPD/live-kdf.img" /w/kopie.txt)
is "chmod 640 und chown justin:projekt stehen im Inode" \
   "$m" "/w/kopie.txt 640 1000 2000"

echo "== 10. die Anmeldung: richtig, falsch, und wie lange sie wartet =="
run_case login "$TMPD/dl.img" \
    "osum $BASIS script=justin;geheim12;id;whoami;exit"
rc=$RC
L="$TMPD/login.txt"
OKDAUER=$DAUER
is "der Lauf endet ueber ACPI" "$rc" "0"
has "$L" "osum login: " "init startet /bin/login, und es fragt nach dem Namen"
has "$L" "willkommen justin" "das RICHTIGE Passwort laesst herein"
has "$L" "uid=1000(justin) gid=1000 euid=1000(justin) egid=1000" \
    "die Shell dahinter laeuft als justin"
has "$L" "groups=2000(projekt)" "MIT den Zusatzgruppen -- login ruft initgroups"
hasnot "$L" "Anmeldung falsch" "kein Fehlversuch dabei"

run_case loginbad "$TMPD/dl.img" \
    "osum $BASIS script=justin;falsch99;justin;falsch99;justin;falsch99"
rc=$RC
B="$TMPD/loginbad.txt"
BADDAUER=$DAUER
has "$B" "Anmeldung falsch" "das FALSCHE Passwort wird abgewiesen"
hasnot "$B" "willkommen justin" "und niemand kommt herein"
w1=$(grep -aoE 'login: warte [0-9]+ ms' "$B" | sed -n 1p | grep -oE '[0-9]+')
w2=$(grep -aoE 'login: warte [0-9]+ ms' "$B" | sed -n 2p | grep -oE '[0-9]+')
w3=$(grep -aoE 'login: warte [0-9]+ ms' "$B" | sed -n 3p | grep -oE '[0-9]+')
is "nach dem ersten Fehlversuch wartet login" "${w1:-fehlt}" "1000"
is "nach dem zweiten doppelt so lang" "${w2:-fehlt}" "2000"
is "nach dem dritten wieder doppelt" "${w3:-fehlt}" "4000"
# ---- UND ER HAT WIRKLICH GESCHLAFEN. Die Zahl oben koennte `login`
#      hinschreiben, ohne zu warten. Diese hier kommt aus
#      CLOCK_MONOTONIC IN DER MASCHINE und misst NUR den Schlaf --
#      nicht die Passwortpruefung daneben, die auf einer ausgelasteten
#      Maschine ein Vielfaches davon kostet und jede Wandzeitmessung
#      unbrauchbar machen wuerde.
g1=$(grep -aoE 'login: gewartet [0-9]+ ms' "$B" | sed -n 1p | grep -oE '[0-9]+')
g3=$(grep -aoE 'login: gewartet [0-9]+ ms' "$B" | sed -n 3p | grep -oE '[0-9]+')
if [ -n "${g1:-}" ] && [ "${g1:-0}" -ge 900 ]; then
    ok "und die Uhr DER MASCHINE bestaetigt es: gefordert 1000 ms, wirklich gewartet ${g1} ms"
else
    bad "login sagt 1000 ms und hat ${g1:-0} ms gewartet -- da hat niemand geschlafen"
fi
if [ -n "${g3:-}" ] && [ "${g3:-0}" -ge 3600 ]; then
    ok "beim dritten Mal: gefordert 4000 ms, wirklich gewartet ${g3} ms"
else
    bad "beim dritten Mal gefordert 4000 ms, gewartet ${g3:-0} ms"
fi
d=$(( BADDAUER - OKDAUER ))
if [ "$d" -ge 6000 ]; then
    ok "und der ganze Lauf dauert entsprechend laenger: ${BADDAUER} ms gegen ${OKDAUER} ms"
else
    bad "drei Fehlversuche dauerten nur ${d} ms laenger (${BADDAUER} gegen ${OKDAUER})"
fi

run_case loginfast "$TMPD/df.img" \
    "osum $BASIS script=justin;falsch99;justin;falsch99;justin;falsch99"
rc=$RC
S="$TMPD/loginfast.txt"
FASTDAUER=$DAUER
f1=$(grep -aoE 'login: warte [0-9]+ ms' "$S" | sed -n 1p | grep -oE '[0-9]+')
f3=$(grep -aoE 'login: warte [0-9]+ ms' "$S" | sed -n 3p | grep -oE '[0-9]+')
is "mit verzoegerung_ms=200 in /etc/login.conf wartet login 200 ms" "${f1:-fehlt}" "200"
is "und beim dritten Mal 800 -- dieselbe Verdopplung, andere Basis" "${f3:-fehlt}" "800"
h1=$(grep -aoE 'login: gewartet [0-9]+ ms' "$S" | sed -n 1p | grep -oE '[0-9]+')
if [ -n "${h1:-}" ] && [ "${h1:-0}" -ge 180 ] && [ "${h1:-0}" -lt 900 ]; then
    ok "und die Uhr der Maschine sieht ${h1} ms statt 1000 -- die Datei WIRD gelesen"
else
    bad "mit verzoegerung_ms=200 wurden ${h1:-0} ms gewartet"
fi
d=$(( BADDAUER - FASTDAUER ))
hin "der ganze Lauf: ${FASTDAUER} ms gegen ${BADDAUER} ms, also ${d} ms kuerzer"

echo "== 11. passwd: ueber eine Zwischendatei, /etc/shadow bleibt 0o600 root =="
run_case pw "$TMPD/d0.img" "osum $BASIS script=sh /t/passwd.sh"
rc=$RC
P="$TMPD/pw.txt"
has "$P" "passwd: gesetzt fuer justin" "passwd meldet Erfolg"
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
    print("kein osum1-Eintrag: %r" % rec[:40]); raise SystemExit
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
grep -q "^runden $ITERS$" "$TMPD/pwcheck.txt" \
    && ok "der neue Eintrag traegt den Kostenfaktor dieser Runde ($ITERS)" \
    || bad "die Rundenzahl passt nicht: $(grep '^runden' "$TMPD/pwcheck.txt" || true)"
grep -q '^salzlaenge 8' "$TMPD/pwcheck.txt" \
    && ok "und acht Oktette Salz aus getrandom" \
    || bad "die Salzlaenge stimmt nicht"
grep -q '^neu stimmt' "$TMPD/pwcheck.txt" \
    && ok "PYTHON rechnet denselben Wert -- es ist wirklich PBKDF2-HMAC-SHA256" \
    || bad "Python kommt auf einen anderen Wert"
grep -q '^alt stimmt nicht' "$TMPD/pwcheck.txt" \
    && ok "GEGENPROBE: aus dem ALTEN Passwort kommt ein anderer Wert" \
    || bad "altes und neues Passwort ergeben denselben Wert"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/live-pw.img" /etc/shadow)
is "und /etc/shadow gehoert weiter root und traegt 0o600" "$m" "/etc/shadow 600 0 0"
python3 tools/osum/mkfs.py list "$TMPD/live-pw.img" > "$TMPD/liste.txt" 2>&1
if grep -q 'shadow.neu\|shadow.alt' "$TMPD/liste.txt"; then
    bad "eine Zwischendatei liegt noch da: $(grep -o 'shadow\.[a-z]*' "$TMPD/liste.txt" | tr '\n' ' ')"
else
    ok "keine Zwischendatei bleibt liegen -- die vier Schritte gehen auf"
fi

echo
echo "MULTIUSER: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
