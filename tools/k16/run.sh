#!/usr/bin/env bash
#
# Verwendung:  bash tools/k16/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

. tools/lib/firnenv.sh
firnenv_need_firnc1
FC1=$FIRNC1
ULD=kernel/user/user.ld

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
gleich() { # name ist soll
    if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht dastehen" || ok "$3"; }
wert() { grep -a -m1 -oE "$2" "$1" 2>/dev/null | head -1; }

[ -x "$FIRNC" ] || { echo "firnc0 fehlt"; exit 1; }
[ -x "$FC1" ]   || { echo "firnc1 fehlt"; exit 1; }

# ===================================================================
echo "== 1. the assembler: from firnc's .s straight to a program =="

as --64 -o "$TMPD/hostcrt.o" tools/k11/hostcrt.s 2>/dev/null \
    || { echo "as auf hostcrt.s fehlgeschlagen"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || { echo "as auf crt.s fehlgeschlagen"; exit 1; }

if "$FIRNC" -c -o "$TMPD/fas.o" kernel/user/fas.fi > "$TMPD/fas.err" 2>&1 \
   && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/fas" \
        "$TMPD/hostcrt.o" "$TMPD/fas.o" 2>/dev/null; then
    ok "fas ist gebaut ($(stat -c%s "$TMPD/fas") Oktette)"
else
    bad "fas cannot be built"; sed 's/^/        /' "$TMPD/fas.err" | head -8
fi
FAS="$TMPD/fas"

mkdir -p "$TMPD/s"
PROGS=""
for f in kernel/user/*.fi; do
    n=$(basename "$f" .fi)
    case "$n" in appdir|flate|nidx|pw|tools|ulib) continue;; esac
    grep -q "fn u_start" "$f" || continue
    PROGS="$PROGS $n"
done
#
gebaut=0; nichtgebaut=""
for p in $PROGS; do
    if "$FC1" "kernel/user/$p.fi" > "$TMPD/s/$p.s" 2>"$TMPD/s/$p.err"; then
        FCRT=(--crt _F1.u_start)
        grep -qE '^[[:space:]]*(\.globl[[:space:]]+_start|_start:)' \
            "$TMPD/s/$p.s" && FCRT=()
        if "$FAS" "$TMPD/s/$p.s" -o "$TMPD/s/$p.bin" "${FCRT[@]}" \
                > "$TMPD/s/$p.fas" 2>&1; then
            gebaut=$((gebaut+1))
        else
            nichtgebaut="$nichtgebaut $p[$(head -1 "$TMPD/s/$p.fas")]"
        fi
    else
        nichtgebaut="$nichtgebaut $p[firnc]"
    fi
done
ANZ=$(echo $PROGS | wc -w)
if [ -z "$nichtgebaut" ]; then
    ok "fas translates and links all $gebaut programs of this userland"
else
    bad "fas scheitert an:$nichtgebaut"
fi
num "Programme, die fas gebunden hat" "$gebaut" eq "$ANZ"

printf 'b\na\nb\nc\na\n' > "$TMPD/in.txt"
VERGLEICH="echo wc sort head tail uniq grep cat seq tr cut basename dirname which true false"
same=0; diffs=""
for p in $VERGLEICH; do
    as --64 -o "$TMPD/s/$p.o" "$TMPD/s/$p.s" 2>/dev/null || { diffs="$diffs $p(as)"; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F1.u_start -o "$TMPD/s/$p.ld" \
        "$TMPD/hostcrt.o" "$TMPD/s/$p.o" 2>/dev/null || { diffs="$diffs $p(ld)"; continue; }
    "$FAS" "$TMPD/s/$p.s" -o "$TMPD/s/$p.fas" --wirt --crt _F1.u_start 2>/dev/null
    chmod +x "$TMPD/s/$p.fas" "$TMPD/s/$p.ld"
    case $p in
      echo) A="hallo welt 42";; wc|sort|uniq|cat) A="$TMPD/in.txt";;
      head|tail) A="-n 2 $TMPD/in.txt";; grep) A="a $TMPD/in.txt";;
      seq) A="1 7";; tr) A="a X";; cut) A="-c 1 $TMPD/in.txt";;
      basename|dirname) A="/x/y/z.txt";; which) A="ls";; *) A="";;
    esac
    o1=$("$TMPD/s/$p.ld" $A < "$TMPD/in.txt" 2>&1; echo "rc=$?")
    o2=$("$TMPD/s/$p.fas" $A < "$TMPD/in.txt" 2>&1; echo "rc=$?")
    if [ "$o1" = "$o2" ]; then same=$((same+1)); else diffs="$diffs $p"; fi
done
ANZV=$(echo $VERGLEICH | wc -w)
if [ -z "$diffs" ]; then
    ok "$same of $ANZV programs: fas and as+ld say the same and go with the same code"
else
    bad "fas and as+ld differ at:$diffs"
fi

printf '.intel_syntax noprefix\n.text\n.globl _start\n_start:\n    mov rax, rbx\n    quatschbefehl rax, rbx\n    ret\n' > "$TMPD/kaputt.s"
if "$FAS" "$TMPD/kaputt.s" -o "$TMPD/kaputt.bin" --wirt > "$TMPD/kaputt.err" 2>&1; then
    bad "CONTROL: fas let an unknown instruction through"
else
    if grep -q "Zeile 6" "$TMPD/kaputt.err" && grep -q "quatschbefehl" "$TMPD/kaputt.err"; then
        ok "CONTROL: an unknown instruction aborts -- with line number and word"
    else
        bad "CONTROL: the abort does not name line 6 and the word: $(head -1 "$TMPD/kaputt.err")"
    fi
fi
printf '.intel_syntax noprefix\n.text\nfoo:\n    ret\n' > "$TMPD/ohne.s"
if "$FAS" "$TMPD/ohne.s" -o "$TMPD/ohne.bin" --wirt > "$TMPD/ohne.err" 2>&1; then
    bad "CONTROL: fas linked a source without _start"
else
    hat "$TMPD/ohne.err" "_start" "GEGENPROBE: ohne die Marke _start bricht fas ab"
fi
printf '.intel_syntax noprefix\n.text\n.globl _start\n_start:\n    jmp nirgendwo\n' > "$TMPD/weg.s"
if "$FAS" "$TMPD/weg.s" -o "$TMPD/weg.bin" --wirt > "$TMPD/weg.err" 2>&1; then
    bad "CONTROL: fas linked a jump into nothing"
else
    hat "$TMPD/weg.err" "nirgendwo" "GEGENPROBE: ein Sprung auf einen unbekannten Namen bricht ab"
fi
printf '.intel_syntax noprefix\n.text\n.globl _start\n_start:\n    mov edi, 5\n    mov eax, 60\n    syscall\n' > "$TMPD/gut.s"
if "$FAS" "$TMPD/gut.s" -o "$TMPD/gut.bin" --wirt >/dev/null 2>&1; then
    chmod +x "$TMPD/gut.bin"; "$TMPD/gut.bin"; rc=$?
    num "und dieselbe Quelle ohne den Fehler laeuft und gibt 5 zurueck" "$rc" eq 5
else
    bad "the error-free control could not be built"
fi

# ===================================================================
echo "== 2. the numbers from which the kernel changes follow =="
mkdir -p "$TMPD/mess"
printf 'fn main(start: u64) -> i32 {\n    return 0\n}\n' > "$TMPD/mess/klein.fi"
python3 - "$ROOT/$FC1" "$TMPD/mess/klein.fi" > "$TMPD/mess.txt" 2>&1 <<'PY'
import resource, subprocess, sys
fc1, quelle = sys.argv[1], sys.argv[2]
def geht(art, wert):
    def pre():
        resource.setrlimit(art, (wert, wert))
    try:
        return subprocess.run([fc1, quelle], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL,
                              preexec_fn=pre).returncode == 0
    except Exception:
        return False
def kleinste(art, lo, hi, einheit):
    while lo < hi:
        m = (lo + hi) // 2
        if geht(art, m * einheit): hi = m
        else: lo = m + 1
    return lo
ar = kleinste(resource.RLIMIT_AS, 1, 512, 1024 * 1024)
st = kleinste(resource.RLIMIT_STACK, 8, 2048, 1024)
print("adressraum_mib", ar)
print("stapel_kib", st)
print("weniger_adressraum", 1 if geht(resource.RLIMIT_AS, (ar - 1) * 1024 * 1024) else 0)
print("weniger_stapel", 1 if geht(resource.RLIMIT_STACK, (st - 8) * 1024) else 0)
PY
AR=$(wert "$TMPD/mess.txt" 'adressraum_mib [0-9]+' | grep -oE '[0-9]+')
ST=$(wert "$TMPD/mess.txt" 'stapel_kib [0-9]+' | grep -oE '[0-9]+')
num "firnc1 braucht so viel Adressraum (MiB) -- Osum gibt 3 MiB Abbild und 6 MiB Arena" "${AR:-}" le 9
num "firnc1 braucht so viel Stapel (KiB) -- Osum gibt jetzt 504" "${ST:-}" le 504
gleich "GEGENPROBE: mit einem MiB weniger Adressraum geht es nicht" \
    "$(wert "$TMPD/mess.txt" 'weniger_adressraum [0-9]+' | grep -oE '[0-9]+$')" "0"
gleich "GEGENPROBE: mit acht KiB weniger Stapel geht es nicht" \
    "$(wert "$TMPD/mess.txt" 'weniger_stapel [0-9]+' | grep -oE '[0-9]+$')" "0"

echo "== 2b. the silent abort of firnc1 (D-019) =="
LEER="$TMPD/leerimport"
rm -rf "$LEER"; mkdir -p "$LEER"
cp kernel/user/fuiapp/apphost.fi "$LEER/" 2>/dev/null
FIRNLIB="$PWD/lib" "$FC1" -c -o "$LEER/x.o" "$LEER/apphost.fi" \
    > "$LEER/c1.out" 2> "$LEER/c1.err"
RC1=$?
FIRNLIB="$PWD/lib" "$FIRNC" -c -o "$LEER/x0.o" "$LEER/apphost.fi" \
    > "$LEER/c0.out" 2> "$LEER/c0.err"
RC0=$?
gleich "firnc1 geht bei fehlendem Import mit 2" "$RC1" "2"
gleich "und schreibt dabei KEIN Oktett (das ist der Mangel)" \
    "$(cat "$LEER/c1.out" "$LEER/c1.err" | wc -c)" "0"
[ "$RC0" -ne 0 ] \
    && ok "firnc0 scheitert an derselben Stelle (rc=$RC0)" \
    || bad "firnc0 haette auch scheitern muessen"
grep -q "ulib.fi" "$LEER/c0.err" \
    && ok "firnc0 NAMES the missing file -- that is how to get at the cause" \
    || bad "firnc0 no longer names the missing file"
#
#     error: the module 'std.rt' belongs to the standard library and
#     is not available in profile 'kernel'
#
#     error: the program has no function 'main'
#
UPROF_G=""
grep -qa '^profile app' kernel/user/taskmgr.fi && UPROF_G=--profile=app
FIRNLIB="$PWD/lib" "$FC1" -c $UPROF_G -o "$TMPD/wlib-gross.o" \
    kernel/user/taskmgr.fi > "$TMPD/gross.err" 2>&1
RCG=$?
gleich "wlib AN IHREM PLATZ, ueber taskmgr.fi eingebunden, uebersetzt firnc1 klaglos (keine Groessengrenze)" \
    "$RCG" "0"

# ===================================================================
echo "== 3. the memory map: the range of this round overlaps none =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "$(tail -1 "$TMPD/karte.txt")"
else
    bad "the memory map has collisions"; sed 's/^/        /' "$TMPD/karte.txt" | head -5
fi
grep -q 'K16_OFF' tools/kernel/memmap.py \
    && ok "the range K16 is in tools/kernel/memmap.py and is counted" \
    || bad "K16 fehlt in tools/kernel/memmap.py"
mkdir -p "$TMPD/kern"
( cd kernel && find . -name '*.fi' -exec cp --parents {} "$TMPD/kern/" \; )
sed -i 's/^const K16_OFF: u64 = 0x49000$/const K16_OFF: u64 = 0x3F000/' "$TMPD/kern/lib/kstate.fi"
grep -q '^const K16_OFF: u64 = 0x3F000' "$TMPD/kern/lib/kstate.fi" \
    || bad "the control could not move K16_OFF at all"
if python3 tools/kernel/memmap.py "$TMPD/kern" > "$TMPD/karte2.txt" 2>&1; then
    bad "CONTROL: at 0x3F000 (round K10, the font reader) the checker should have raised the alarm"
else
    ok "CONTROL: on an already occupied page the map checker raises the alarm ($(grep -c COLLISION "$TMPD/karte2.txt") Kollisionen)"
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo
    echo "K16: $pass passed, $fail failed  (without QEMU -- parts 4 and 5 skipped)"
    [ "$fail" -eq 0 ] && exit 0 || exit 1
fi

# ===================================================================
echo "== 4. the compiler on Osum =="

bash tools/build-kernel.sh "$TMPD/k.mb" >/dev/null 2>&1 \
    || { bad "the kernel cannot be built"; echo "K16: $pass passed, $fail failed"; exit 1; }

mkdir -p "$TMPD/o"
bau_osum() { # name
    "$FIRNC" -c -o "$TMPD/o/$1.o" "kernel/user/$1.fi" > "$TMPD/o/$1.err" 2>&1 || return 1
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/o/$1" \
        "$TMPD/crt.o" "$TMPD/o/$1.o" 2>/dev/null || return 1
    strip --strip-all "$TMPD/o/$1"
}
for p in sh cat echo hello fas firun k16; do
    bau_osum "$p" || { bad "$p cannot be built for Osum"; sed 's/^/        /' "$TMPD/o/$p.err" | head -5; }
done

FIRNQ=""
for k in "${FIRN_REPO:-}" "$ROOT/../firn" "$ROOT/../../firn" "$ROOT/../../../firn"; do
    [ -n "$k" ] && [ -f "$k/bin/firnc1.fi" ] && FIRNQ=$(cd "$k" && pwd) && break
done
if [ -z "$FIRNQ" ]; then
    bad "the source of the compiler (bin/firnc1.fi) was not found"
else
    if ( cd "$FIRNQ" && FIRNLIB="$FIRNQ/lib" "$ROOT/$FIRNC" -c -o "$TMPD/o/firnc.o" bin/firnc1.fi ) > "$TMPD/firnc.err" 2>&1 \
       && ld -T "$ULD" -o "$TMPD/o/firnc" "$TMPD/o/firnc.o" 2>/dev/null; then
        strip --strip-all "$TMPD/o/firnc"
        ok "firnc is linked for Osum ($(stat -c%s "$TMPD/o/firnc") Oktette, Abbild ab 0x40100000)"
    else
        bad "firnc cannot be linked for Osum"; sed 's/^/        /' "$TMPD/firnc.err" | head -5
    fi
fi

mkdir -p "$TMPD/q"
cat > "$TMPD/q/probe.fi" <<'FI'
fn schreib(fd: u64, p: u64, n: u64) -> u64 {
    return asm("syscall", out("rax"), in("rax") 1, in("rdi") fd,
        in("rsi") p, in("rdx") n, clobber("rcx"), clobber("r11"),
        clobber("memory"))
}

fn main(start: u64) -> i32 {
    var s: [u8; 30] = "osum hat mich uebersetzt\n\0\0\0\0\0"
    schreib(1, (&s[0]) as u64, 25)
    return 42
}
FI
cat > "$TMPD/q/kaputt.fi" <<'FI'
fn main(start: u64) -> i32 {
    return diesenamengibtesnicht
}
FI
printf 'fn main(start: u64) -> i32 {\n    return 1\n}\n' > "$TMPD/q/andere.fi"

lauf() { # abbild anhang ausgabe [zeitlimit]
    local img=$1 anh=$2 out=$3 tl=${4:-900}
    cp "$img" "$TMPD/live.img"
    timeout "$tl" $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 \
        -append "$anh" -serial "file:$out" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

if [ -x "$TMPD/o/firnc" ]; then
bash tools/mkfsfi/mkfs.sh build "$TMPD/d.img" 8192 /bin/ \
    /bin/sh="$TMPD/o/sh" /bin/echo="$TMPD/o/echo" /bin/fas="$TMPD/o/fas" \
    /bin/firun="$TMPD/o/firun" /bin/k16="$TMPD/o/k16" \
    /bin/firnc="$TMPD/o/firnc" \
    /probe.fi="$TMPD/q/probe.fi" /kaputt.fi="$TMPD/q/kaputt.fi" \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "a disk image with the compiler on it ($(grep -o 'free=[0-9]*' "$TMPD/mkfs.txt") Bloecke)" \
    || { bad "mkfs for the compiler image failed"; head -3 "$TMPD/mkfs.txt"; }
fi

if [ -f "$TMPD/d.img" ]; then
S='cd /;firnc probe.fi > /probe.s;echo UEB=$?;fas /probe.s -o /probe;echo BIN=$?;/probe;echo LAUF=$?;exit'
lauf "$TMPD/d.img" "osum nokbd nosched noproc nofs noring3 script=$S" "$TMPD/ueb.txt"
rc=$?
num "QEMU-Beendigungscode des Uebersetzerlaufs" "$rc" eq 21
cp "$TMPD/live.img" "$TMPD/nach-ueb.img"
gleich "der Uebersetzer auf Osum ist zufrieden zurueckgekommen" \
    "$(wert "$TMPD/ueb.txt" 'UEB=[0-9]+')" "UEB=0"
gleich "der Assembler auf Osum ist zufrieden zurueckgekommen" \
    "$(wert "$TMPD/ueb.txt" 'BIN=[0-9]+')" "BIN=0"
hat "$TMPD/ueb.txt" "osum hat mich uebersetzt" \
    "DAS AUF OSUM UEBERSETZTE PROGRAMM LAEUFT AUF OSUM UND SAGT SEINEN SATZ"
gleich "und es geht mit genau dem Code, den seine Quelle nennt" \
    "$(wert "$TMPD/ueb.txt" 'LAUF=[0-9]+')" "LAUF=42"

bash tools/mkfsfi/mkfs.sh cat "$TMPD/nach-ueb.img" /probe.s > "$TMPD/osum.s" 2>/dev/null
bash tools/mkfsfi/mkfs.sh cat "$TMPD/nach-ueb.img" /probe > "$TMPD/osum.bin" 2>/dev/null
( cd "$TMPD/q" && "$ROOT/$FC1" probe.fi > "$TMPD/wirt.s" 2>/dev/null )
"$FAS" "$TMPD/wirt.s" -o "$TMPD/wirt.bin" > "$TMPD/wirt.fas" 2>&1 \
    || { bad "fas did not get through on the host: $(head -1 "$TMPD/wirt.fas")"; }
num "die .s von Osum ist nicht leer (Oktette)" "$(stat -c%s "$TMPD/osum.s" 2>/dev/null || echo 0)" gt 1000
if cmp -s "$TMPD/osum.s" "$TMPD/wirt.s"; then
    ok "CHARACTER-IDENTICAL: the assembler text from Osum is octet for octet the one from the host ($(stat -c%s "$TMPD/osum.s") Oktette)"
else
    bad "the assembler text differs: $(cmp "$TMPD/osum.s" "$TMPD/wirt.s" 2>&1 | head -1)"
    diff "$TMPD/osum.s" "$TMPD/wirt.s" 2>/dev/null | head -6 | sed 's/^/        /'
fi
if cmp -s "$TMPD/osum.bin" "$TMPD/wirt.bin"; then
    ok "CHARACTER-IDENTICAL: the executable from Osum is octet for octet the one from the host ($(stat -c%s "$TMPD/osum.bin") Oktette)"
else
    bad "the executable differs: Osum $(stat -c%s "$TMPD/osum.bin" 2>/dev/null || echo -) Oktette, Wirt $(stat -c%s "$TMPD/wirt.bin" 2>/dev/null || echo -) Oktette, $(cmp -l "$TMPD/osum.bin" "$TMPD/wirt.bin" 2>/dev/null | wc -l) verschieden"
    head -c 120 "$TMPD/osum.bin" | od -An -tx1 | head -2 | sed 's/^/        osum /'
    head -c 120 "$TMPD/wirt.bin" | od -An -tx1 | head -2 | sed 's/^/        wirt /'
    head -2 "$TMPD/wirt.fas" | sed 's/^/        /' 
fi
( cd "$TMPD/q" && "$ROOT/$FC1" andere.fi > "$TMPD/andere.s" 2>/dev/null )
if cmp -s "$TMPD/osum.s" "$TMPD/andere.s"; then
    bad "CONTROL: a different source came out character-identical -- the comparison measures nothing"
else
    ok "CONTROL: a DIFFERENT source does NOT come out character-identical"
fi

GROW=$(wert "$TMPD/ueb.txt" 'stackgrow=[0-9]+' | grep -oE '[0-9]+')
num "Stapelseiten, die waehrend des Laufs bei Bedarf entstanden sind" "${GROW:-0}" gt 10

lauf "$TMPD/d.img" "osum nokbd nosched noproc nofs noring3 nostackgrow script=$S" \
     "$TMPD/nostack.txt"
if [ "$(wert "$TMPD/nostack.txt" 'UEB=[0-9]+')" = "UEB=0" ]; then
    bad "CONTROL nostackgrow: the compiler ran through anyway -- the growth proves nothing"
else
    ok "CONTROL nostackgrow: the compiler does NOT get through ($(wert "$TMPD/nostack.txt" 'UEB=[0-9]+'))"
fi
hat "$TMPD/nostack.txt" "user fault:" \
    "GEGENPROBE nostackgrow: er stirbt an einem Seitenfehler"
hatnicht "$TMPD/nostack.txt" "osum hat mich uebersetzt" \
    "GEGENPROBE nostackgrow: und nichts wird uebersetzt"
gleich "GEGENPROBE nostackgrow: kein einziges Stapelfach ist entstanden" \
    "$(wert "$TMPD/nostack.txt" 'stackgrow=[0-9]+')" "stackgrow=0"

lauf "$TMPD/d.img" "osum nokbd nosched noproc nofs noring3 nobigmem script=$S" \
     "$TMPD/nobig.txt"
if [ "$(wert "$TMPD/nobig.txt" 'UEB=[0-9]+')" = "UEB=0" ]; then
    bad "CONTROL nobigmem: the compiler ran through anyway -- the arena proves nothing"
else
    ok "CONTROL nobigmem: without the big arena the compiler does not get through ($(wert "$TMPD/nobig.txt" 'UEB=[0-9]+'))"
fi
hatnicht "$TMPD/nobig.txt" "osum hat mich uebersetzt" \
    "GEGENPROBE nobigmem: und nichts wird uebersetzt"

S2='cd /;k16 open /probe.fi;k16 open /kaputt.fi;exit'
lauf "$TMPD/d.img" "osum nokbd nosched noproc nofs noring3 script=$S2" "$TMPD/open.txt"
hat "$TMPD/open.txt" "osum hat mich uebersetzt" \
    "DER DOPPELKLICK: fopen auf eine .fi uebersetzt sie und startet sie"
G=$(grep -a -c 'k16: fopen_c = 42' "$TMPD/open.txt" 2>/dev/null || true)
num "und der Beendigungscode des uebersetzten Programms kommt durch (42)" "${G:-0}" ge 1
K=$(grep -a -c 'k16: fopen_c = 70' "$TMPD/open.txt" 2>/dev/null || true)
num "GEGENPROBE: eine .fi, die NICHT uebersetzt, endet mit 70 statt mit 0" "${K:-0}" ge 1
hat "$TMPD/open.txt" "firun: the compiler refuses, code 1" \
    "GEGENPROBE: und der Nutzer LIEST, warum -- der Grund steht auf dem Schirm"
hat "$TMPD/open.txt" "error in the source" \
    "GEGENPROBE: und zwar als Satz und nicht als nackte Zahl"
fi

# ===================================================================
echo "== 5. what opens a file: the table and the outrigger =="

mkdir -p "$TMPD/d"
printf 'fn main(start: u64) -> i32 {\n    return 0\n}\n' > "$TMPD/d/p.fi"
printf 'ein text\n' > "$TMPD/d/q.txt"
cp "$TMPD/o/hello" "$TMPD/d/tarn.fi"          # heisst .fi, IST ein ELF
printf 'weder magisch noch bekannt\n' > "$TMPD/d/fremd.zzz"
printf '#!/bin/echo ausleger\nrest egal\n' > "$TMPD/d/s1.sh"
printf '#!/r2.sh\n' > "$TMPD/d/r1.sh"
printf '#!/r1.sh\n' > "$TMPD/d/r2.sh"

bash tools/mkfsfi/mkfs.sh build "$TMPD/t.img" 8192 /bin/ \
    /bin/sh="$TMPD/o/sh" /bin/cat="$TMPD/o/cat" /bin/echo="$TMPD/o/echo" \
    /bin/hello="$TMPD/o/hello" /bin/k16="$TMPD/o/k16" \
    /p.fi="$TMPD/d/p.fi" /q.txt="$TMPD/d/q.txt" /tarn.fi="$TMPD/d/tarn.fi" \
    /fremd.zzz="$TMPD/d/fremd.zzz" /s1.sh="$TMPD/d/s1.sh" \
    /r1.sh="$TMPD/d/r1.sh" /r2.sh="$TMPD/d/r2.sh" \
    > "$TMPD/mkfs2.txt" 2>&1 \
    && ok "a disk image with the seven cases on it" \
    || { bad "mkfs for the table run failed"; head -3 "$TMPD/mkfs2.txt"; }

lauf "$TMPD/t.img" "osum nokbd nosched noproc nofs noring3 script=k16;exit" \
     "$TMPD/tab.txt" 300
rc=$?
num "QEMU-Beendigungscode des Tabellenlaufs" "$rc" eq 21
hat "$TMPD/tab.txt" "k16: fertig" "das Programm in Ring 3 ist durchgelaufen"

k16w() { grep -a -m1 -oE "k16: $1 = .*" "$TMPD/tab.txt" 2>/dev/null | sed "s/k16: $1 = //"; }
K() { gleich "$3" "$(k16w "$1")" "$2"; }

K art_elf_l   "elf"  "eine ELF-Datei wird an ihrer magischen Zahl erkannt"
K art_elf_a   "1"    "und ihre Wirkung ist: sie SELBST starten (A_EXEC)"
K art_elf_m   "4"    "die magische Zahl ist vier Oktette lang"
K art_fi_l    "firn" "eine .fi wird an ihrer Endung erkannt"
K art_fi_p    "/bin/firun" "und geoeffnet wird sie mit /bin/firun"
K art_fi_e    ".fi"  "die Endung im Satz ist .fi"
K art_txt_p   "/bin/edit" "eine .txt wird mit dem Editor geoeffnet"
K art_tarn_l  "elf"  "DER INHALT GEHT VOR: /tarn.fi heisst .fi und IST ein Programm"
K art_foreign   "-8"   "GEGENPROBE: weder magische Zahl noch bekannte Endung: -ENOEXEC"
K art_gone     "-2"   "GEGENPROBE: eine Datei, die es nicht gibt: -ENOENT"
num "Eintraege in der Tabelle" "$(k16w tab_anz)" ge 8
K tab_end     "-2"   "GEGENPROBE: hinter dem letzten Eintrag: -ENOENT"
num "freg hat einen Platz vergeben" "$(k16w reg_nr)" ge 0
if [ "$(k16w reg_danach)" = "-8" ]; then
    bad "after freg /fremd.zzz is still not classified -- the table has no effect"
else
    ok "after freg /fremd.zzz is classified (place $(k16w reg_danach)) -- the table really works"
fi
K reg_prog    "/bin/cat" "und zwar mit dem Programm, das Ring 3 eingetragen hat"
K reg_short    "-22"  "GEGENPROBE: ein Satz der falschen Laenge wird abgelehnt (-EINVAL)"
num "fopen auf ein Programm gibt eine Prozessnummer" "$(k16w open_elf)" gt 0
K open_foreign  "-2"   "GEGENPROBE: fopen auf einen Pfad, den es nicht gibt, startet NICHTS"
num "ein Skript mit #! startet ueber seinen Ausleger" "$(k16w shebang)" gt 0
hat "$TMPD/tab.txt" "ausleger /s1.sh" \
    "DER AUSLEGER BEKOMMT SEIN ARGUMENT UND DEN PFAD: 'ausleger /s1.sh'"
K shebang_ring "-40" "GEGENPROBE: ein #! im Kreis endet mit -ELOOP und startet nichts"
K kein_programm "-8" "GEGENPROBE: eine Datei ohne #! und ohne ELF-Kopf bleibt kein Programm"
SB=$(wert "$TMPD/tab.txt" 'shebangs=[0-9]+' | grep -oE '[0-9]+')
num "wie oft execve einen Ausleger gefunden hat" "${SB:-0}" ge 1

echo
echo "K16: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
