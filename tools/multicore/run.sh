#!/usr/bin/env bash
#
#   bash tools/multicore/run.sh
#
#     VEK 6 #UD RIP 0x80   KERN 2   ART 1
#
# ======================================================================
# WAS GEMESSEN WIRD
# ======================================================================
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
zahl() { # name value op soll
    local name=$1 value=$2 op=$3 soll=$4
    if [ -z "$value" ]; then bad "$name: no number found (wanted $op $soll)"; return; fi
    if [ "$value" -"$op" "$soll" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, wanted $op $soll"; fi
}

echo "== 1. the numbers that must be equal on both sides =="
for paar in "CPU_SYSRSP:C_SYSRSP" "CPU_KSTACK:C_KSTACK" "CPU_SYSCALLS:C_SYSCALLS"; do
    a=${paar%%:*}; b=${paar##*:}
    va=$(grep -aoE "\.set $a, *[0-9]+" kernel/arch/x86_64/isr.s | grep -oE '[0-9]+' | head -1)
    vb=$(grep -aoE "const $b: u64 = [0-9]+" kernel/arch/cpu.fi | grep -oE '[0-9]+$' | head -1)
    if [ -n "$va" ] && [ "$va" = "$vb" ]; then ok "isr.s $a = cpu.fi $b = $va"
    else bad "isr.s $a='$va' gegen cpu.fi $b='$vb'"; fi
done
grep -qa 'incq %gs:CPU_SYSCALLS' kernel/arch/x86_64/isr.s \
    && ok "syscall_entry counts via the GS base (the proof per core)" \
    || bad "in syscall_entry fehlt 'incq %gs:CPU_SYSCALLS'"

echo
echo "== 2. the latch is in the CODE and not in a comment =="
grep -qa '^fn ring3_allowed' kernel/sched/sched.fi \
    && ok "sched.ring3_allowed exists" || bad "sched.ring3_allowed is missing"
grep -qa 'ring3_allowed(state, i, me)' kernel/sched/sched.fi \
    && ok "the scheduler selection really calls it" \
    || bad "ring3_allowed is NOT called in the pick -- exactly the BLECHKERN bug"
grep -qa 'gs_ready(state, me)' kernel/sched/sched.fi \
    && ok "and it asks the CHECKED GS base" \
    || bad "ring3_allowed does not check the GS base"
# `gs_good` is a fixed array of eight. If MAX_CPUS grows without it,
# `gs_ready` says "no" for every core from the ninth on -- ring 3
# would never run there and nobody would see why.
mc=$(grep -aoE 'const MAX_CPUS: u64 = [0-9]+' kernel/lib/kstate.fi | grep -oE '[0-9]+$')
gg=$(grep -aoE 'static mut gs_good: \[u64; [0-9]+\]' kernel/sched/sched.fi | sed -n 's/.*; \([0-9]*\)\]/\1/p')
if [ -n "$mc" ] && [ "$mc" = "$gg" ]; then ok "kstate.MAX_CPUS = sched.gs_good = $mc"
else bad "MAX_CPUS=$mc, but gs_good holds $gg -- cores above it would never get ring 3"; fi

echo
echo "== 3. no shared block buffer without the lock L_FS =="
py=$(python3 - <<'PYEOF'
import re
s=open("kernel/fs/fs.fi","rb").read().decode("utf-8","surrogateescape")
funcs={}; cur=None; body=[]
for l in s.split("\n"):
    m=re.match(r"^fn (\w+)\(", l)
    if m:
        if cur: funcs[cur]=body
        cur=m.group(1); body=[]
    elif cur is not None:
        if l=="}": funcs[cur]=body; cur=None; body=[]
        else: body.append(l)
if cur: funcs[cur]=body
m=re.search(r"^export \{(.*?)^\}", s, re.S|re.M)
exp=set(t.strip() for t in re.split(r"[,\s]+", m.group(1)) if re.match(r"^[a-zA-Z_]\w*$", t.strip()))
def enter(f): return "enter(state)" in "\n".join(funcs.get(f,[]))
def roh(f):
    return bool(re.search(r"buf_(in|dt|bm|sb|ib|i2)\(|ofsj\.(read|write)\(|blk\.(read|write)\(",
                          "\n".join(funcs.get(f,[]))))
def callers(f):
    return [n for n,b in funcs.items() if n!=f and re.search(r"(?<![\w.])"+f+r"\(", "\n".join(b))]
mitwissen={"inode_get_blind","race_core"}
offen=[f for f in funcs if roh(f) and not enter(f) and f not in mitwissen]
leck=[]; gesehen=set(); todo=list(offen)
while todo:
    f=todo.pop()
    if f in gesehen: continue
    gesehen.add(f)
    if enter(f): continue
    if f in mitwissen: continue
    if f in exp: leck.append(f); continue
    cs=callers(f)
    if not cs: leck.append(f+"(ohne-Aufrufer)")
    todo.extend(cs)
print(len(funcs), len(offen), ",".join(sorted(set(leck))) or "-")
PYEOF
)
nfun=$(echo "$py" | awk '{print $1}')
nroh=$(echo "$py" | awk '{print $2}')
leck=$(echo "$py" | awk '{print $3}')
if [ "$leck" = "-" ]; then
    ok "$nfun functions in fs.fi, $nroh touch blocks -- every way out goes through enter()"
else
    bad "these paths reach a shared buffer WITHOUT L_FS: $leck"
fi

echo
echo "== 4. the kernel and the desktop disk =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "the kernel does not build"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; \
         echo "VIELKERN: $pass bestanden, $fail gescheitert"; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s cannot be assembled"
bauen_ok=1
for p in $PROGS; do
    UPROF=""; UCRT="$TMPD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    vendor/firn/bin/firnc $UPROF -c "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bauen_ok=0; break; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" $UCRT "$TMPD/$p.o" 2>/dev/null || { bauen_ok=0; break; }
    strip --strip-all "$TMPD/$p.elf"
done
if [ "$bauen_ok" = 1 ]; then
    ok "the $(echo $PROGS | wc -w) desktop programs build"
else
    bad "the programs do not build"
    echo "VIELKERN: $pass bestanden, $fail gescheitert"; exit 1
fi

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 || bad "tools/k15/tree.py faellt"
printf '# taskbar.conf\nedge=0\nheight=40\nwidth=0\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/disk.img" 65536 --v3 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" "nur=$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk is ready ($(stat -c%s "$TMPD/disk.img") Oktette)" \
    || { bad "mkfs.py faellt"; tail -4 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs tafel einst"
lauf() { # name smp extra [limit]
    local name=$1 smp=$2 extra=$3 limit=${4:-200}
    local out="$TMPD/$name.txt"
    rm -f "$out"; : > "$out"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout "$limit" $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -smp "$smp" \
        -append "$BASE $extra" -serial "file:$out" -display none -no-reboot \
        -vga std -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    #
    while [ $i -lt 800 ]; do
        [ "$(grep -ac '^tafel: 23 [A-Z]' "$out" 2>/dev/null)" -ge 5 ] && break
        grep -qa '^absturz:  0\|^\*\*\* EXCEPTION' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    sleep 2
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}
#
TAFEL23='^tafel: 23 [A-Z]'
w_r3k()  { grep -a "$TAFEL23" "$1" | tail -1 | grep -oE 'R3K [0-9]+' | awk '{print $2}'; }
w_r3w()  { grep -a "$TAFEL23" "$1" | tail -1 | grep -oE 'R3W [0-9]+' | awk '{print $2}'; }
w_abw()  { grep -a '^r3: syscalls' "$1" | tail -1 | sed -n 's/.*diff=\([0-9]*\).*/\1/p'; }
w_kerne(){ grep -a '^r3: procs' "$1" | tail -1 | sed -n 's/.* n=\([0-9]*\).*/\1/p'; }
w_scpu() { grep -a '^r3: syscalls' "$1" | tail -1 \
    | grep -oE 'c[0-9]+=[0-9]+' | grep -vE '=0$' | wc -l; }
w_exc()  { grep -ac '^\*\*\* EXCEPTION\|^absturz:  0' "$1"; }
w_pid0() { grep -ac '^desk: start .* pid=0' "$1"; }

echo
echo "== 5. four cores, ring 3 on all =="
lauf a4 4 r3alle
L=$TMPD/a4.txt
zahl "R3W (Kerne ohne eigene GS-Basis)" "$(w_r3w $L)" eq 0
zahl "R3K (Kerne, auf denen Ring 3 lief)" "$(w_r3k $L)" ge 2
zahl "Kerne in der Maske der Prozesse" "$(w_kerne $L)" ge 2
zahl "Kerne, auf denen Systemaufrufe ankamen" "$(w_scpu $L)" ge 2
zahl "abw (Summe der Kernzaehler gegen kstate.SYSCALLS)" "$(w_abw $L)" eq 0
zahl "Programmstarts mit pid=0" "$(w_pid0 $L)" eq 0
zahl "Ausnahmen" "$(w_exc $L)" eq 0
grep -qa '^desk: start /bin/settings  pid=[1-9]' $L \
    && ok "the fourth program too (/bin/settings) comes up" \
    || bad "/bin/settings does not come up -- exactly the bug of the previous round"
grep -a '^r3: procs' $L | tail -1 | sed 's/^/        /'
grep -a '^r3: syscalls' $L | tail -1 | sed 's/^/        /'

echo
echo "== 6. acht Kerne =="
lauf a8 8 r3alle
L=$TMPD/a8.txt
zahl "R3W" "$(w_r3w $L)" eq 0
zahl "R3K" "$(w_r3k $L)" ge 2
zahl "Kerne mit Systemaufrufen" "$(w_scpu $L)" ge 2
zahl "abw" "$(w_abw $L)" eq 0
zahl "Programmstarts mit pid=0" "$(w_pid0 $L)" eq 0
zahl "Ausnahmen" "$(w_exc $L)" eq 0
grep -a '^r3: syscalls' $L | tail -1 | sed 's/^/        /'

echo
echo "== 7. NEGATIVE to the measurement: the same disk with r3eins (ring 3 only on core 0) =="
lauf n4 4 "r3eins"
L=$TMPD/n4.txt
zahl "R3K muss 1 sein" "$(w_r3k $L)" eq 1
zahl "nur EIN Kern bekommt Systemaufrufe" "$(w_scpu $L)" eq 1
zahl "abw" "$(w_abw $L)" eq 0
zahl "Ausnahmen" "$(w_exc $L)" eq 0
grep -a '^r3: syscalls' $L | tail -1 | sed 's/^/        /'

echo
echo "== 8. NEGATIVE to the latch, half 1: gsluege -- it MUST hold =="
lauf g4 4 "r3alle gsluege"
L=$TMPD/g4.txt
zahl "R3W muss GROESSER null werden (die Luege wird gesehen)" "$(w_r3w $L)" ge 1
zahl "R3K faellt auf 1 zurueck (Ring 3 bleibt auf Kern 0)" "$(w_r3k $L)" eq 1
zahl "Ausnahmen -- die Maschine lebt" "$(w_exc $L)" eq 0
zahl "nur Kern 0 bekommt Systemaufrufe" "$(w_scpu $L)" eq 1
grep -a "$TAFEL23" $L | tail -1 | sed 's/^/        /'

echo
echo "== 9. NEGATIVE to the latch, half 2: gsluege r3blind -- it MUST break =="
lauf b4 4 "r3alle gsluege r3blind" 200
L=$TMPD/b4.txt
if [ "$(w_exc $L)" -ge 1 ]; then
    ok "without the latch the machine breaks again -- it is what holds it"
    grep -a '^absturz:  [0-6] ' $L | head -7 | sed 's/^/        /'
else
    bad "without the latch NOTHING happens -- then section 8 does not measure the latch"
fi
grep -qa 'ART 3' $L && ok "and in a task of kind 3 (K_USER, so ring 3)" \
    || bad "the break hits no ring 3 task -- then it is a different bug"

echo
echo "== 10. ROUND MERGE-6: the inode buffer, FORCED on several cores =="
fsrace() { # name  smp  extra
    local name=$1 smp=$2 extra=$3
    cp -f "$TMPD/disk.img" "$TMPD/fsr-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -smp "$smp" \
        -append "nokbd nosched noproc $extra" \
        -serial "file:$TMPD/fsr-$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/fsr-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    return 0
}
w_fehl() { grep -a '^smp: fsrace cores=' "$1" | tail -1 \
    | sed -n 's/.*errors=\([0-9]*\).*/\1/p'; }
w_inos() { grep -a '^smp: fsrace   c0' "$1" | tail -1 \
    | grep -oE 'inode=[0-9]+' | sed 's/.*=//' | sort -un | wc -l; }

fsrace mit 4 "fsrace"
L=$TMPD/fsr-mit.txt
if [ -s "$L" ]; then
    grep -a '^smp: fsrace' $L | sed 's/^/        /'
    zahl "Kerne mit je EIGENEM Inodeblock" "$(w_inos $L)" ge 2
    zahl "Abweichungen MIT der Sperre" "$(w_fehl $L)" eq 0
else
    bad "no capture of the fsrace run"
fi

echo
echo "== 11. NEGATIVE to that: fsblind -- without the lock it MUST break =="
fsrace ohne 4 "fsblind"
L=$TMPD/fsr-ohne.txt
if [ -s "$L" ]; then
    grep -a '^smp: fsrace' $L | sed 's/^/        /'
    zahl "Abweichungen OHNE die Sperre" "$(w_fehl $L)" ge 1
else
    bad "no capture of the fsblind run"
fi

echo
echo "== 12. ROUND MERGE-6: the remaining single-core leftovers, counted at the source =="
#
EK_SOLL=${EK_SOLL:-67}
ek=$(python3 tools/multicore/onecore.py | sed -n 's/.*offen=\([0-9]*\).*/\1/p')
if [ -n "$ek" ] && [ "$ek" -le "$EK_SOLL" ] 2>/dev/null; then
    ok "functions with a data-page buffer without a lock word: $ek (contract: at most $EK_SOLL)"
else
    bad "single-core leftovers: $ek, contract is at most $EK_SOLL -- new place? Then enter it in docs/RUNDE-MERGE6.md"
fi
python3 tools/multicore/onecore.py | sed 's/^/        /'

echo
echo "VIELKERN: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ] || exit 1
