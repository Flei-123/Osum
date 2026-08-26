#!/usr/bin/env bash
# tools/guard/run.sh -- RUNDE K10: DIE ZWEI SCHUTZBITS UND DAS BOOT-MODUL.
#
# Diese Runde hat nichts Neues erfunden. Sie holt die letzten zwei
# Faehigkeiten aus OrientOS' Rust-Kernel herueber, die Osum noch nicht
# hatte, und misst sie hier nach. Was portiert wurde:
#
#   `arch/x86_64/user.rs`   -> `kernel/guard.fi`    SMEP/SMAP in CR4
#   `kcore/initramfs.rs`    -> `kernel/bootmod.fi`  Boot-Modul + CRC32
#
# WARUM DAS NICHT ZWEI RUNDEN SIND. Beide sind klein, beide haengen an
# derselben Frage -- was ein Kernel von aussen entgegennimmt und was er
# davon anfassen darf --, und beide brauchen dieselben Gegenproben:
# einmal MIT und einmal OHNE die Sache selbst.
#
# WAS HIER GEMESSEN WIRD:
#
#   1. DIE BITS STEHEN WIRKLICH IN CR4. Nicht "der Kernel sagt, er habe
#      sie gesetzt", sondern das Register selbst, zurueckgelesen und
#      ausgegeben. Gegenprobe: auf einem Prozessor OHNE die beiden
#      (QEMUs Vorgabe `qemu64`) meldet derselbe Kernel ehrlich 0 -- und
#      laeuft trotzdem durch. Ein Kernel, der ein Bit meldet, das die
#      Maschine nicht hat, waere schlimmer als einer ohne das Bit.
#   2. SMAP SETZT WIRKLICH DURCH. `smapraw` laesst den Kernel EINE Zelle
#      Ring-3-Speicher OHNE das `stac`-Fenster lesen. Mit SMAP ist das
#      ein #PF mit Fehlercode 0x1 und der Lauf endet mit 63; mit
#      `nosmap` daneben kommt derselbe Lesezugriff zurueck und liefert
#      das Oktett 0x5A, das der Kernel selbst hingeschrieben hat. Der
#      Unterschied zwischen den beiden Laeufen ist EIN Bit in CR4.
#   3. SMEP SETZT WIRKLICH DURCH. `smepraw` ruft eine Seite mit
#      Benutzerbit auf, in der ein einzelnes `ret` steht. Mit SMEP: #PF
#      mit Fehlercode 0x11 -- Bit 4 ist der Instruktionsabruf, und genau
#      der ist hier der Punkt. Mit `nosmep`: der Aufruf kommt zurueck.
#   4. DAS FENSTER WIRD BENUTZT. `windows=` zaehlt, wie oft `stac` es
#      geoeffnet hat. Eine Zusage "SMAP ist an" ohne eine einzige
#      Oeffnung waere ein Kernel, der Ring-3-Speicher nie anfasst -- und
#      der koennte keine Systemaufrufe.
#   5. JEDER KERN. CR4 ist PRO PROZESSOR. Unter `-smp 4` muessen alle
#      drei weiteren Kerne die Bits nach dem Hochlaufen tragen, und
#      gezaehlt wird nur, wer sie danach WIRKLICH in seinem CR4 stehen
#      hat (zurueckgelesen, nicht angenommen).
#   6. DAS BOOT-MODUL IST EINE PLATTE. Der Lader reicht ein
#      OFS-Dateisystem als Modul herein; der Kernel rechnet seine CRC32,
#      vergleicht sie mit `modcrc=` und mountet es als Wurzel. Darauf
#      laeuft dieselbe Shell wie sonst von der ATA-Platte. Das ist der
#      Unterschied zwischen einem ISO, das nur einen Kern traegt, und
#      einem, das ein Userland hat.
#   7. DIE PRUEFSUMME IST EINE BEDINGUNG, KEINE ANGABE. Mit einem
#      falschen `modcrc=` wird das Modul NICHT benutzt. Ohne `modfs`
#      wird es gesehen, gerechnet und trotzdem nicht benutzt -- ein
#      Modul, das niemand angefordert hat, wird nicht heimlich zur
#      Wurzel.
#   8. DER BEREICH IST RESERVIERT. Am Ende des Laufs wird die Summe
#      NOCH EINMAL gerechnet. Haette `mem.scan` den Bereich des Moduls
#      nicht aus dem Rahmenverwalter genommen, haette ein Prozess
#      daraufgeschrieben und die zweite Summe waere eine andere.
#   9. BEIDE UEBERSETZER. firnc0 und firnc1 bauen denselben Kernel, und
#      er sagt beide Male dasselbe.
#
# Verwendung:  bash tools/guard/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2, erwartet $3"; fi }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "GUARD: skipped, qemu-system-x86_64 is not available"
    exit 0
fi

# Ein Lauf. $1 Abbild, $2 Kommandozeile, $3 Ausgabe, Rest: QEMU-Argumente.
# Rueckgabe ist der Beendigungscode von QEMU: 21 = der Kernel hat sich
# selbst beendet, 63 = er ist an einer Ausnahme stehengeblieben.
lauf() {
    local img=$1 app=$2 out=$3
    shift 3
    timeout 120 qemu-system-x86_64 -kernel "$img" -m 512 -append "$app" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

# ------------------------------------------------------------ 1. bauen

echo "== 1. der Kern und ein Userland, aus beiden Uebersetzern =="
bash vendor/firn/hole-firnc.sh >/dev/null 2>&1 \
    || { echo "GUARD: vendor/firn/hole-firnc.sh fehlgeschlagen"; exit 1; }

for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: der Kern ist gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: der Kern laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
[ -f "$TMPD/k0.mb" ] || { echo "GUARD: $pass passed, $fail failed"; exit 1; }

# Das Userland fuer das Boot-Modul. Neun Programme reichen: gemessen wird
# hier, ob ein Modul eine Platte sein kann, nicht die Shell.
PROGS="sh ls cat echo wc grep uname true false"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>"$TMPD/as.err" \
    || bad "crt.s laesst sich nicht assemblieren"
ubau=1
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/u$p.log" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
             -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>>"$TMPD/u$p.log" \
        && strip --strip-all "$TMPD/$p.elf" \
        || { bad "$p laesst sich nicht bauen"; ubau=0; }
done
[ "$ubau" = 1 ] && ok "$(echo $PROGS | wc -w) unprivilegierte Programme gebaut"

printf 'eins\nzwei\ndrei\n' > "$TMPD/d.txt"
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" 4096 $SPEC \
        /d/ "/d/d.txt=$TMPD/d.txt" > "$TMPD/mkfs.log" 2>&1 \
    && ok "mkfs.py hat ein OFS-Abbild von 4096 Bloecken gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.log" | head -5; }
CRC=$(python3 -c "import zlib,sys;print('%08x'%zlib.crc32(open(sys.argv[1],'rb').read()))" \
        "$TMPD/disk.img")
# So, wie der KERNEL sie schreibt: `serial.hex` gibt die Ziffern aus, die
# die Zahl hat, und nicht acht Stueck. Bei einer Summe, die mit einer Null
# anfaengt, fiele ein Vergleich gegen die aufgefuellte Form.
CRCK=$(printf '%x' "0x$CRC")
ok "die CRC32 des Abbilds auf dem Wirt: 0x$CRC (der Kernel schreibt 0x$CRCK)"

# ------------------------------------------------- 2. die Bits in CR4

echo "== 2. SMEP und SMAP stehen wirklich in CR4 =="
BASIS="nokbd nosched noproc nofs noring3"

rc=0; lauf "$TMPD/k0.mb" "$BASIS" "$TMPD/max.log" -cpu max || rc=$?
gleich "Beendigungscode mit -cpu max" "$rc" 21
has "$TMPD/max.log" "guard: cr4=0x300020  smep=1  smap=1  cpu=1/1" \
    "CR4 traegt Bit 20 UND Bit 21, und CPUID meldet beide"

# DIE GEGENPROBE ZUR MESSUNG SELBST: derselbe Kernel auf einem
# Prozessor, der die Bits nicht kennt (QEMUs Vorgabe). Er darf sie NICHT
# melden und muss trotzdem durchlaufen.
rc=0; lauf "$TMPD/k0.mb" "$BASIS" "$TMPD/alt.log" || rc=$?
gleich "Beendigungscode auf einem Prozessor ohne die Bits" "$rc" 21
has "$TMPD/alt.log" "guard: cr4=0x20  smep=0  smap=0  cpu=0/0" \
    "ohne CPUID-Meldung wird nichts gesetzt und nichts behauptet"

rc=0; lauf "$TMPD/k0.mb" "$BASIS nosmep" "$TMPD/nosmep.log" -cpu max || rc=$?
has "$TMPD/nosmep.log" "smep=0  smap=1" "nosmep laesst SMAP stehen und nimmt SMEP"
rc=0; lauf "$TMPD/k0.mb" "$BASIS nosmap" "$TMPD/nosmap.log" -cpu max || rc=$?
has "$TMPD/nosmap.log" "smep=1  smap=0" "nosmap laesst SMEP stehen und nimmt SMAP"

# --------------------------------------------- 3. sie setzen durch

echo "== 3. die Gegenproben: ein Zugriff, der scheitern MUSS =="
rc=0; lauf "$TMPD/k0.mb" "$BASIS smapraw" "$TMPD/rawr.log" -cpu max || rc=$?
gleich "smapraw mit SMAP: der Kernel bleibt stehen" "$rc" 63
has "$TMPD/rawr.log" "smap: raw read @" "der Lesezugriff wurde wirklich versucht"
has "$TMPD/rawr.log" "EXCEPTION 14 #PF  err=0x1" \
    "und er ist ein #PF (present, Lesezugriff, aus Ring 0)"
hasnot "$TMPD/rawr.log" "got=0x" "der Kernel hat das Oktett NICHT bekommen"

rc=0; lauf "$TMPD/k0.mb" "$BASIS smapraw nosmap" "$TMPD/rawr-off.log" -cpu max || rc=$?
gleich "derselbe Zugriff ohne SMAP: der Lauf endet regulaer" "$rc" 21
has "$TMPD/rawr-off.log" "got=0x5a" \
    "und er liefert genau das Oktett, das der Kernel hingeschrieben hat"

rc=0; lauf "$TMPD/k0.mb" "$BASIS smepraw" "$TMPD/rawx.log" -cpu max || rc=$?
gleich "smepraw mit SMEP: der Kernel bleibt stehen" "$rc" 63
has "$TMPD/rawx.log" "EXCEPTION 14 #PF  err=0x11" \
    "#PF mit Bit 4 gesetzt -- es war ein INSTRUKTIONSABRUF"
hasnot "$TMPD/rawx.log" "came back" "der Aufruf ist nie zurueckgekommen"

rc=0; lauf "$TMPD/k0.mb" "$BASIS smepraw nosmep" "$TMPD/rawx-off.log" -cpu max || rc=$?
gleich "derselbe Aufruf ohne SMEP: der Lauf endet regulaer" "$rc" 21
has "$TMPD/rawx-off.log" "smep: came back (!)" \
    "und das ret in der Nutzerseite wurde wirklich ausgefuehrt"

# ------------------------------------------ 4. das Fenster wird benutzt

echo "== 4. das Fenster: der Kernel fasst Ring-3-Speicher an =="
rc=0; lauf "$TMPD/k0.mb" "osum nokbd nosched nofs noring3 caps" \
     "$TMPD/caps.log" -cpu max || rc=$?
gleich "die Capability-Runde mit SMEP und SMAP" "$rc" 21
n=$(grep -acF 'caps: 18/18 proofs' "$TMPD/caps.log")
gleich "Laeufe mit 18 von 18 Zusagen aus Ring 3" "$n" 2
w=$(grep -aoE 'windows=[0-9]+' "$TMPD/caps.log" | tail -1 | grep -oE '[0-9]+')
if [ "${w:-0}" -gt 0 ]; then
    ok "das SMAP-Fenster wurde ${w}x geoeffnet -- der Kernel liest wirklich Nutzerspeicher"
else
    bad "das Fenster wurde nie geoeffnet (windows=${w:-?}) -- die Zusage misst nichts"
fi
rc=0; lauf "$TMPD/k0.mb" "osum nokbd nosched nofs noring3 caps nosmap" \
     "$TMPD/caps-nosmap.log" -cpu max || rc=$?
w0=$(grep -aoE 'windows=[0-9]+' "$TMPD/caps-nosmap.log" | tail -1 | grep -oE '[0-9]+')
gleich "Gegenprobe: ohne SMAP wird kein Fenster geoeffnet" "${w0:-x}" 0
n=$(grep -acF 'caps: 18/18 proofs' "$TMPD/caps-nosmap.log")
gleich "und Ring 3 meldet trotzdem dieselben Zusagen" "$n" 2

# ------------------------------------------------------ 5. jeder Kern

echo "== 5. CR4 ist pro Prozessor =="
rc=0; lauf "$TMPD/k0.mb" "$BASIS" "$TMPD/smp4.log" -cpu max -smp 4 || rc=$?
gleich "vier Prozessoren mit den Schutzbits" "$rc" 21
has "$TMPD/smp4.log" "smp: online=4 of 4  failed=0" "alle vier sind hochgelaufen"
has "$TMPD/smp4.log" "guard: aps=3" \
    "und alle drei weiteren tragen die Bits WIRKLICH in ihrem CR4"
rc=0; lauf "$TMPD/k0.mb" "$BASIS" "$TMPD/smp1.log" -cpu max -smp 1 || rc=$?
has "$TMPD/smp1.log" "guard: aps=0" "Gegenprobe: mit einem Prozessor zaehlt niemand mit"

# -------------------------------------------------- 6. das Boot-Modul

echo "== 6. ein Boot-Modul ist eine Platte =="
MOD="osum nokbd nosched noproc nofs noring3 modfs modcrc=$CRC"
rc=0
lauf "$TMPD/k0.mb" "$MOD script=ls /bin;uname;cat /d/d.txt;exit" \
     "$TMPD/mod.log" -cpu max -initrd "$TMPD/disk.img" || rc=$?
gleich "der Kernel startet ein Userland aus einem Modul" "$rc" 21
has "$TMPD/mod.log" "blocks=4096  crc=0x$CRCK  want=0x$CRCK  ok=1" \
    "die gerechnete Summe ist die des Wirts, und sie war verlangt"
has "$TMPD/mod.log" "osum: from module" "die Wurzelplatte ist das Modul"
has "$TMPD/mod.log" "osum: mount=1" "das Dateisystem darin ist gemountet"
has "$TMPD/mod.log" "sh: ready, osum" "/bin/sh laeuft -- aus dem Modul geladen"
has "$TMPD/mod.log" "./ ../ sh ls cat echo wc grep uname true false" \
    "'ls /bin' zeigt die neun Programme"
has "$TMPD/mod.log" "eins" "'cat /d/d.txt' liest eine Datei aus dem Modul"
has "$TMPD/mod.log" "osum: sh exit=0" "und die Shell endet sauber"
# ...und das alles mit beiden Schutzbits an.
has "$TMPD/mod.log" "smep=1  smap=1" "das ganze Userland lief mit SMEP und SMAP"

echo "== 7. die Pruefsumme ist eine Bedingung =="
rc=0
lauf "$TMPD/k0.mb" "osum nokbd nosched noproc nofs noring3 modfs modcrc=deadbeef script=exit" \
     "$TMPD/modbad.log" -cpu max -initrd "$TMPD/disk.img" || rc=$?
gleich "mit falscher Vorgabe laeuft der Kernel weiter" "$rc" 21
has "$TMPD/modbad.log" "want=0xdeadbeef  ok=0" "er sagt, dass die Summe nicht passt"
hasnot "$TMPD/modbad.log" "osum: from module" "und benutzt das Modul NICHT"
hasnot "$TMPD/modbad.log" "sh: ready" "es laeuft keine Shell daraus"

rc=0
lauf "$TMPD/k0.mb" "osum nokbd nosched noproc nofs noring3 script=exit" \
     "$TMPD/modoff.log" -cpu max -initrd "$TMPD/disk.img" || rc=$?
has "$TMPD/modoff.log" "crc=0x$CRCK" "ohne 'modfs' wird das Modul gesehen und gerechnet"
hasnot "$TMPD/modoff.log" "osum: from module" "aber nicht benutzt"

rc=0; lauf "$TMPD/k0.mb" "$BASIS" "$TMPD/modnone.log" -cpu max || rc=$?
has "$TMPD/modnone.log" "mod: none" "ohne Modul sagt der Kernel das, statt zu raten"

echo "== 8. der Bereich des Moduls gehoert dem Modul =="
has "$TMPD/mod.log" "mod: recheck crc=0x$CRCK  same=1" \
    "nach einem Lauf mit Prozessen, Seiten und Halde ist das Abbild unveraendert"
f=$(grep -aoE 'frames_free=[0-9]+ of [0-9]+' "$TMPD/mod.log" | tail -1)
a=$(echo "$f" | grep -oE '[0-9]+' | head -1)
b=$(echo "$f" | grep -oE '[0-9]+' | tail -1)
gleich "und jeder Rahmen, den das Userland nahm, kam zurueck ($f)" "$a" "$b"

# ---------------------------------------------- 9. der andere Uebersetzer

echo "== 9. firnc1 baut denselben Kern =="
if [ -f "$TMPD/k1.mb" ]; then
    rc=0; lauf "$TMPD/k1.mb" "$BASIS" "$TMPD/max1.log" -cpu max || rc=$?
    gleich "firnc1: Beendigungscode" "$rc" 21
    has "$TMPD/max1.log" "guard: cr4=0x300020  smep=1  smap=1  cpu=1/1" \
        "firnc1: dieselben Bits in CR4"
    rc=0; lauf "$TMPD/k1.mb" "$BASIS smapraw" "$TMPD/rawr1.log" -cpu max || rc=$?
    gleich "firnc1: smapraw bleibt stehen" "$rc" 63
    rc=0
    lauf "$TMPD/k1.mb" "$MOD script=ls /bin;exit" "$TMPD/mod1.log" \
         -cpu max -initrd "$TMPD/disk.img" || rc=$?
    gleich "firnc1: dasselbe Userland aus demselben Modul" "$rc" 21
    has "$TMPD/mod1.log" "crc=0x$CRCK  want=0x$CRCK  ok=1" "firnc1: dieselbe Pruefsumme"
    has "$TMPD/mod1.log" "sh: ready, osum" "firnc1: /bin/sh laeuft aus dem Modul"
else
    bad "firnc1 hat keinen Kern gebaut"
fi

echo
echo "GUARD: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
