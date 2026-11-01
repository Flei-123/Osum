#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/protocol/run.sh -- RUNDE PROTOKOLL: DIE FUENF MESSUNGEN.
#
set -uo pipefail
cd "$(dirname "$0")/../.."

QEMU_X86=${QEMU_X86:-qemu-system-x86_64}
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh ls cat echo log absturz krach"
quelle() { case $1 in absturz) echo crash ;; krach) echo noise ;; *) echo "$1" ;; esac; }
BLOCKS=4096

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
same() { [ "$2" = "$3" ] && ok "$1: $3" || bad "$1: '$3' statt '$2'"; }
value() { grep -oaE "$2" "$1" | head -1 | grep -oE '[0-9]+$'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
command -v "$QEMU_X86" >/dev/null 2>&1 || {
    echo "PROTOKOLL: uebersprungen, $QEMU_X86 fehlt"; exit 0; }

# ----------------------------------------------------------- Beschleunigung
#
ACCEL=""
ACCELNAME="tcg"
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-accel kvm -cpu host"
    ACCELNAME="kvm"
fi
echo "PROTOKOLL: Beschleunigung = $ACCELNAME"

# ------------------------------------------------------------------ laufen

lauf() { # abbild kommandozeile ausgabe [weitere qemu-argumente]
    local abbild=$1 zeile=$2 aus=$3
    shift 3
    timeout 240 $QEMU_X86 $ACCEL -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

lauf_platte() { # abbild kommandozeile ausgabe platte
    lauf "$1" "$2" "$3" -drive "file=$4,format=raw,if=ide,index=0"
}

echo "== 1. build: kernel with symbol table, and the three new programs =="
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "the kernel cannot be built"
         sed 's/^/        /' "$TMPD/build.log" | head -15
         echo "PROTOKOLL: $pass passed, $fail failed"; exit 1; }
K0="$TMPD/k0.mb"

n=$(grep -oaE 'symtab: [0-9]+ Symbole' "$TMPD/build.log" | grep -oE '[0-9]+')
num "Symbole im Abbild" "$n" gt 3000
n=$(grep -oaE '[0-9]+ Zeilen' "$TMPD/build.log" | head -1 | grep -oE '[0-9]+')
num "Quellzeilen-Eintraege im Abbild" "$n" gt 20000

bash tools/build-kernel.sh "$TMPD/knosym.mb" --ohne-symbole \
    > "$TMPD/build2.log" 2>&1 \
    && ok "--ohne-symbole builds as well" || bad "--ohne-symbole does not build"
if [ -f "$TMPD/knosym.mb" ]; then
    a=$(stat -c%s "$K0"); b=$(stat -c%s "$TMPD/knosym.mb")
    echo "        price of the tables: $((a - b)) octets ($a against $b)"
    num "die Tabellen kosten wirklich Platz" "$((a - b))" gt 100000
fi

for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" \
        || bad "$f.s cannot be assembled"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
for p in $PROGS; do
    q=$(quelle "$p")
    "$FIRNC" "kernel/user/$q.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$q.fi uebersetzt nicht"; sed 's/^/        /' "$TMPD/e$p" | head -6; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null \
        || bad "$p cannot be linked"
done
[ -f "$TMPD/log.elf" ] && ok "/bin/log, /bin/absturz and /bin/krach built" \
                       || bad "die neuen Programme fehlen"

kn=$(grep -aoE 'const SYS_OSUM_KLOG: u64 = [0-9]+' kernel/sys/sys.fi | grep -oE '[0-9]+$')
un=$(grep -aoE 'const SYS_KLOG: u64 = [0-9]+' kernel/user/ulib.fi | grep -oE '[0-9]+$')
[ "$kn" = "$un" ] && [ -n "$kn" ] \
    && ok "SYS_KLOG is the same number in the kernel and in ulib ($kn)" \
    || bad "SYS_KLOG: Kern=$kn ulib=$un"
kn=$(grep -aoE 'const SYS_OSUM_KRACH: u64 = [0-9]+' kernel/sys/sys.fi | grep -oE '[0-9]+$')
un=$(grep -aoE 'const SYS_KRACH: u64 = [0-9]+' kernel/user/ulib.fi | grep -oE '[0-9]+$')
[ "$kn" = "$un" ] && [ -n "$kn" ] \
    && ok "SYS_KRACH is the same number in the kernel and in ulib ($kn)" \
    || bad "SYS_KRACH: Kern=$kn ulib=$un"

python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1
has "$TMPD/map.txt" "0 collisions" "die Speicherkarte von kdata bleibt kollisionsfrei"
KDS=$(sed -n 's/^const KDATA_SIZE: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/lib/kstate.fi | head -1)
grep -q "$KDS" "$TMPD/map.txt" \
    && ok "kdata is $KDS large (the ring needs 64 KiB contiguous)" \
    || bad "kdata does not have the expected size ($KDS)"
a=$(grep -aoE 'KDATA_SIZE, 0x[0-9A-F]+' kernel/arch/x86_64/boot.s | head -1 | grep -oE '0x[0-9A-F]+')
b=$(grep -aoE 'const KDATA_SIZE: u64 = 0x[0-9A-F]+' kernel/lib/kstate.fi | grep -oE '0x[0-9A-F]+')
[ "$a" = "$b" ] && ok "KDATA_SIZE is the same in boot.s and kstate.fi ($a)" \
                || bad "KDATA_SIZE: boot.s=$a kstate.fi=$b"

echo "== 2. (a) four cores, ten thousand lines each, one ring =="
lauf "$K0" "nokbd nosched noproc nofs noring3 logall lograce" \
    "$TMPD/race.txt" -smp 4
if grep -qa 'smp: lograce' "$TMPD/race.txt"; then
    z=$(value "$TMPD/race.txt" 'zeilen=[0-9]+')
    g=$(value "$TMPD/race.txt" 'gesamt=[0-9]+')
    r=$(value "$TMPD/race.txt" 'ring=[0-9]+')
    ro=$(value "$TMPD/race.txt" 'rotiert=[0-9]+')
    kp=$(value "$TMPD/race.txt" 'kaputt=[0-9]+')
    ke=$(value "$TMPD/race.txt" 'kerne=[0-9]+')
    num "Kerne, die geschrieben haben" "$ke" eq 4
    num "Zeilen, die die Kerne geschrieben haben" "$z" eq 40000
    num "Zeilen, die der Ring gezaehlt hat (keine darf verloren gehen)" "$g" eq 40000
    num "Zeilen, die noch im Ring stehen" "$r" eq 510
    num "Zeilen, die der Ring ueberschrieben hat (40000 - 510)" "$ro" eq 39490
    num "verschraenkte Eintraege (Kopf und Text von verschiedenen Kernen)" "$kp" eq 0
else
    bad "the four-core run delivered no lograce line"
    tail -5 "$TMPD/race.txt" | sed 's/^/        /'
fi

echo "== 3. (e) was ein weggefilterter Aufruf kostet =="
ms=$(value "$TMPD/race.txt" 'logbank aufrufe=1000000  ns=[0-9]+  ms=[0-9]+')
je=$(value "$TMPD/race.txt" 'ns_je_10=[0-9]+')
if [ -n "$ms" ]; then
    echo "        1 Mio. Aufrufe Stufe debug (ausgefiltert): $ms ms, $je ns je 10 Aufrufe, $ACCELNAME"
    if [ "$ACCELNAME" = kvm ]; then
        num "eine Million ausgefilterte Aufrufe in Millisekunden" "$ms" lt 100
    else
        num "eine Million ausgefilterte Aufrufe in Millisekunden (TCG, nur Schranke gegen Ausreisser)" \
            "$ms" lt 1000
        echo "        (the acceptance threshold of 100 ms applies to KVM; this ran on TCG)"
    fi
else
    bad "no measurement of the fast path found"
fi

echo "== 4. the log in operation: sources, levels, /proc and /dev =="
lauf "$K0" "nokbd nosched noproc noring3 logdebug" "$TMPD/dbg.txt"
n=$(grep -ac ' [DIWE] ' "$TMPD/dbg.txt")
num "Protokollzeilen auf der seriellen Leitung mit logdebug" "$n" ge 1
grep -qaE '\[ *[0-9]+\] [0-9]+/[0-9]+ [DIWE] [a-z]+ *: ' "$TMPD/dbg.txt" \
    && ok "the format is right: [time] core/pid level source: text" \
    || bad "no line in the agreed format"
lauf "$K0" "nokbd nosched noproc nofs noring3 logquiet" "$TMPD/quiet.txt"
n2=$(grep -ac ' [DI] ' "$TMPD/quiet.txt")
num "debug/info-Zeilen mit logquiet (die Schwelle muss wirken)" "${n2:-0}" eq 0

echo "== 5. the disk, the programs on it and the restart =="
printf 'protokoll\n' > "$TMPD/readme.txt"
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
    /proc/ /dev/ /mnt/ /var/ /var/crash/ \
    /readme.txt="$TMPD/readme.txt" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "OFS-Abbild mit $BLOCKS Bloecken gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head; }

QUIET="nokbd vfs"
# ---- (d) EIN NULLZEIGER IN RING 3.
#
lauf_platte "$K0" "osum $QUIET logall krach script=krach prog;echo WEITERLAEUFT;log -n 3;exit" \
    "$TMPD/r3.txt" "$TMPD/disk.img"
rc=$?
has "$TMPD/r3.txt" "user fault" "(d) der Nullzeiger in Ring 3 wurde als Benutzerfehler behandelt"
has "$TMPD/r3.txt" "process killed" "(d) das Programm ist gestorben"
has "$TMPD/r3.txt" "WEITERLAEUFT" "(d) das System laeuft danach weiter"
hasber=$(grep -aoE '/var/crash/[0-9]+\.txt' "$TMPD/r3.txt" | head -1)
[ -n "$hasber" ] && ok "(d) a report was stored: $hasber" \
                 || bad "(d) no report was stored"
grep -qa 'absturz: bericht' "$TMPD/r3.txt" \
    && ok "(d) the kernel says what became of the report" \
    || bad "(d) the kernel is silent about the report"

lauf_platte "$K0" "osum $QUIET logall krach script=krach kern;exit" \
    "$TMPD/panikdisk.txt" "$TMPD/disk.img"
has "$TMPD/panikdisk.txt" "*** EXCEPTION" "(c) die erzwungene Kernel-Panik hat stattgefunden"
hasber=$(grep -aoE '/var/crash/[0-9]+\.txt' "$TMPD/panikdisk.txt" | tail -1)
[ -n "$hasber" ] && ok "(c) the kernel stored a report despite the panic: $hasber" \
                 || bad "(c) no report was stored on the panic"

lauf_platte "$K0" "osum $QUIET script=absturz;exit" \
    "$TMPD/nachher.txt" "$TMPD/disk.img"
has "$TMPD/nachher.txt" "absturz: ein Bericht vom letzten Start liegt vor" \
    "(c) der Kern findet die Marke des letzten Laufs wieder"
has "$TMPD/nachher.txt" "EIN BERICHT VOM LETZTEN START" \
    "(c) /bin/absturz meldet ihn dem Benutzer"
has "$TMPD/nachher.txt" "ABSTURZBERICHT" "(c) der Bericht selbst wird angezeigt"
has "$TMPD/nachher.txt" "-- rueckspur" "(c) der Bericht enthaelt die Rueckverfolgung"
has "$TMPD/nachher.txt" "-- protokoll" "(c) der Bericht enthaelt die letzten Protokollzeilen"
has "$TMPD/nachher.txt" "ABSTURZBERICHT (KERN)" "(c) es ist der Bericht der Kernel-Panik"
n=$(grep -acE '^  #[0-9]+ [a-z]+\.[a-z_0-9]+\+0x' "$TMPD/nachher.txt")
num "(c) aufgeloeste Symbole im Bericht" "${n:-0}" ge 1

# ---- /bin/log
lauf_platte "$K0" "osum $QUIET logall script=log -z;log -p HALLOWELT;log -n 4;exit" \
    "$TMPD/werkzeug.txt" "$TMPD/disk.img"
has "$TMPD/werkzeug.txt" "zeilen:" "/bin/log -z zeigt die Zahlen des Rings"
has "$TMPD/werkzeug.txt" "HALLOWELT" "/bin/log -p schreibt eine Zeile in den Ring"
grep -qa 'prog *: HALLOWELT' "$TMPD/werkzeug.txt" \
    && ok "the written line shows as source 'prog' im Ring" \
    || bad "the written line does not appear as a log line"
lauf_platte "$K0" "osum $QUIET logall script=cat /proc/klog;exit" \
    "$TMPD/proc.txt" "$TMPD/disk.img"
has "$TMPD/proc.txt" "# klog" "/proc/klog liefert einen Kopf mit den Zahlen"
lauf_platte "$K0" "osum $QUIET logall script=cat /dev/klog;exit" \
    "$TMPD/dev.txt" "$TMPD/disk.img"
grep -qaE '\[ *[0-9]+\] [0-9]+/[0-9]+ [DIWE] ' "$TMPD/dev.txt" \
    && ok "/dev/klog delivers the same lines in the same format" \
    || bad "/dev/klog liefert nichts Lesbares"

lauf_platte "$K0" "osum $QUIET script=krach kern;echo LEBTNOCH;exit" \
    "$TMPD/riegel.txt" "$TMPD/disk.img"
has "$TMPD/riegel.txt" "LEBTNOCH" \
    "ohne 'krach' auf der Kernel-Befehlszeile lehnt der Aufruf 1861 ab"

echo "== 5b. K-011: the report survives the warm restart in memory =="
#
lauf_platte "$K0" "osum $QUIET logall krach script=krach kernfs;exit" \
    "$TMPD/kalt1.txt" "$TMPD/disk.img"
has "$TMPD/kalt1.txt" "Bestellung, art 2" "K-011: die Panik mit gehaltener Sperre hat stattgefunden"
has "$TMPD/kalt1.txt" "absturz: filesystem locked, no report" \
    "K-011: der Riegel verbietet die Platte (so soll es sein)"
lauf_platte "$K0" "osum $QUIET logall script=absturz;exit" \
    "$TMPD/kalt2.txt" "$TMPD/disk.img"
n=$(grep -ac 'aus dem speicher gerettet' "$TMPD/kalt2.txt")
num "GEGENPROBE kalt: nach einem Kaltstart wird nichts gerettet" "${n:-0}" eq 0
n=$(grep -ac 'Bestellung, art 2' "$TMPD/kalt2.txt")
num "GEGENPROBE kalt: kein Bericht der art-2-Panik auf der Platte" "${n:-0}" eq 0

wsock="$TMPD/warm.sock"
rm -f "$wsock" "$TMPD/warm.txt"
timeout 240 $QEMU_X86 $ACCEL -kernel "$K0" -m 256 \
    -append "osum $QUIET logall krach absturzhalt script=absturz;krach kernfs;exit" \
    -serial "file:$TMPD/warm.txt" -display none \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -monitor "unix:$wsock,server,nowait" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
wpid=$!
warte_halt() { # wie viele 'kernel halted'
    local i=0
    while [ $i -lt 600 ]; do
        [ "$(grep -ac 'kernel halted' "$TMPD/warm.txt" 2>/dev/null)" -ge "$1" ] && return 0
        kill -0 "$wpid" 2>/dev/null || return 1
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
if warte_halt 1; then
    ok "K-011 warm: first panic, machine halted"
    python3 - "$wsock" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.3)
s.recv(4096); s.sendall(b"system_reset\n"); time.sleep(0.5); s.close()
PY
    warte_halt 2 && ok "K-011 warm: started after the reset and halted again" \
        || bad "K-011 warm: no second run after the reset"
else
    bad "K-011 warm: the first panic did not come"
fi
kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null; rm -f "$wsock"
awk '/kernel halted/ { n++; next } n == 1' "$TMPD/warm.txt" > "$TMPD/warm2.txt"
has "$TMPD/warm2.txt" "absturz: report rescued from memory" \
    "K-011 warm: der zweite Start findet den Bericht im Speicher"
grep -qaE 'absturz: bericht +/var/crash/[0-9]+\.txt +geschrieben' "$TMPD/warm2.txt" \
    && ok "K-011 warm: and stores it as a file under /var/crash" \
    || bad "K-011 warm: the rescued report was not stored"
has "$TMPD/warm2.txt" "ABSTURZBERICHT (KERN)" "K-011 warm: /bin/absturz zeigt ihn als Kernbericht"
has "$TMPD/warm2.txt" "Bestellung, art 2" "K-011 warm: und es ist der Bericht DIESER Panik (art 2 im Protokollteil)"

echo "== 6. (b) der Panik-Bildschirm, wirklich gelesen =="
sock="$TMPD/mon.sock"
rm -f "$sock" "$TMPD/panik.ppm" "$TMPD/panik.txt"
timeout 240 $QEMU_X86 $ACCEL -kernel "$K0" -m 256 \
    -append "nokbd nosched noproc noring3 gfx logall absturzhalt krach krachjetzt" \
    -serial "file:$TMPD/panik.txt" -display none -no-reboot \
    -vga std -global VGA.edid=off \
    -monitor "unix:$sock,server,nowait" >/dev/null 2>&1 &
qpid=$!
i=0
while [ $i -lt 900 ]; do
    grep -qa 'kernel halted' "$TMPD/panik.txt" 2>/dev/null && break
    kill -0 "$qpid" 2>/dev/null || break
    sleep 0.2
    i=$((i + 1))
done
sleep 1
python3 tools/gfx/screenshot.py "$sock" "$TMPD/panik.ppm" 25 \
    > "$TMPD/schuss.txt" 2>&1
kill "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null
rm -f "$sock"

if [ -s "$TMPD/panik.ppm" ]; then
    ok "a screenshot of the panic exists ($(stat -c%s "$TMPD/panik.ppm") Oktette)"
    python3 tools/protocol/schirmtext.py "$TMPD/panik.ppm" kernel/gfx/font.fi \
        > "$TMPD/schirm.txt" 2>"$TMPD/schirm.err"
    if [ -s "$TMPD/schirm.txt" ]; then
        echo "        --- what is on the screen:"
        sed 's/^/        | /' "$TMPD/schirm.txt" | head -32
        has "$TMPD/schirm.txt" "KERNEL-PANIK" "(b) der Schirm sagt, was los ist"
        has "$TMPD/schirm.txt" "#PF" "(b) der Schirm nennt die Ausnahme beim Namen"
        has "$TMPD/schirm.txt" "RUECKSPUR" "(b) der Schirm hat einen Abschnitt Rueckverfolgung"
        has "$TMPD/schirm.txt" "PROTOKOLL" "(b) der Schirm zeigt die letzten Protokollzeilen"
        has "$TMPD/schirm.txt" "KERN 0" "(b) der Schirm nennt die Kernnummer"
        n=$(grep -oaE '\b(rax|rbx|rcx|rdx|rsi|rdi|rbp|rsp|r8 |r9 |r1[0-5])=0x' \
            "$TMPD/schirm.txt" | sort -u | wc -l)
        num "(b) verschiedene Register auf dem Schirm" "$n" eq 16
        #
        kette=$(awk '/-- RUECKSPUR/ { an = 1; next } /^-- / { an = 0 } an { print $1 }' \
            "$TMPD/schirm.txt" | sed 's/+.*//' | tr '\n' ' ')
        same "(b) die Rueckverfolgung auf dem Schirm ist genau die Aufrufkette" \
            "crash.knall_b crash.knall_a crash.knall KERNEL_MAIN long_mode " "$kette"
        n=$(grep -ac '?' "$TMPD/schirm.txt")
        num "(b) Zeilen mit unlesbaren Zellen (die Glyphen muessen exakt passen)" \
            "${n:-0}" le 1
    else
        bad "(b) no text could be read from the screenshot"
        sed 's/^/        /' "$TMPD/schirm.err" | head -5
    fi
else
    bad "(b) no screenshot was produced"
    sed 's/^/        /' "$TMPD/schuss.txt" | head -5
fi
has "$TMPD/panik.txt" "*** EXCEPTION" "(b) dieselbe Panik steht auch auf der Leitung"
spur() { # datei -> die Namen der kspur-Zeilen, eine je Zeile
    awk '/^  kspur:/ { an = 1; next } an && /^      / { print $1; next } an { exit }' "$1" \
        | sed 's/+0x.*//'
}
has "$TMPD/panik.txt" "kspur: rahmenkette" "(b) die Rueckverfolgung geht die Rahmenzeiger ab, nicht den Stapel"
kette=$(spur "$TMPD/panik.txt" | tr '\n' ' ')
same "(b) die serielle Rueckverfolgung ist genau die Aufrufkette bis zum Start" \
    "crash.knall_b crash.knall_a crash.knall KERNEL_MAIN long_mode " "$kette"
n=$(grep -acE '^ +[a-z_0-9]+\.[a-z_0-9]+\+0x[0-9a-f]+ \([a-z_0-9]+\.fi:[0-9]+\)$' \
    "$TMPD/panik.txt")
num "(b) aufgeloeste Symbole mit Datei:Zeile in der seriellen Rueckverfolgung" "${n:-0}" ge 3
timeout 120 $QEMU_X86 $ACCEL -kernel "$K0" -m 256 \
    -append "nokbd nosched noproc noring3 logall krach krachjetzt stapelscan" \
    -serial "file:$TMPD/scan.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
has "$TMPD/scan.txt" "kspur: stapelscan" "GEGENPROBE: mit 'stapelscan' wird wieder gescannt"
alt=$(spur "$TMPD/scan.txt" | grep -cvE '^(crash\.knall(_a|_b)?|KERNEL_MAIN|long_mode)$')
num "GEGENPROBE: der Scan meldet Eintraege, die keine Rufer sind (Altlast)" "${alt:-0}" ge 1
has "$TMPD/panik.txt" "die letzten Protokollzeilen" \
    "(b) die letzten Protokollzeilen stehen auch auf der Leitung"

echo "== 7. that the driver switch really took place =="
n=0
for f in nvme xhci usb ahci e1000 fs; do
    q=$(find kernel -name "$f.fi" -print -quit)
    k=$(grep -ac 'klog\.' "$q" 2>/dev/null || echo 0)
    [ "$k" -gt 0 ] && n=$((n + 1))
    printf '        %-6s %s Aufrufe der Log-Schnittstelle\n' "$f" "$k"
done
num "Treiber, die ueber die Log-Schnittstelle sprechen" "$n" eq 6

echo "PROTOKOLL: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
