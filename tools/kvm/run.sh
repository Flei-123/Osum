#!/usr/bin/env bash
#
# Aufruf:  bash tools/kvm/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }

# ---------------------------------------------------- ueberspringen?

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "KVM: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi
if [ ! -c /dev/kvm ] || [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    echo "KVM: skipped, /dev/kvm is not there or not usable"
    exit 0
fi

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

if ! qemu-system-x86_64 -accel kvm -m 32 -display none -no-reboot \
        -kernel /bin/true > "$TMPD/probe.txt" 2>&1; then
    if grep -qi 'kvm' "$TMPD/probe.txt" \
       && grep -qiE 'permission|failed to initialize|not access|no such' "$TMPD/probe.txt"; then
        echo "KVM: skipped, /dev/kvm cannot be used"
        sed 's/^/       /' "$TMPD/probe.txt" | head -3
        exit 0
    fi
fi

HERSTELLER=$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $3}')
echo "== 0. der Wirt =="
hin "CPU: ${HERSTELLER:-unbekannt},$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2-)"
hin "QEMU: $(qemu-system-x86_64 --version | head -1)"

# ------------------------------------------------------- der Kernel

bash tools/build-kernel.sh "$TMPD/osum.mb" --stufe 0 >/dev/null 2>&1 \
    || { echo "KVM: the kernel could not be built"; exit 1; }
if [ -s "$TMPD/osum.mb" ]; then
    ok "the kernel is built ($(stat -c%s "$TMPD/osum.mb") Oktette, Stufe 0)"
else
    bad "the kernel is missing"
fi

lauf() {
    local acc=$1 name=$2 mem=$3 kerne=$4 cmd=$5 abbild=$6
    shift 6
    LOG="$TMPD/$name.txt"
    RC=0
    timeout 180 qemu-system-x86_64 -accel "$acc" -kernel "$abbild" \
        -m "$mem" -smp "$kerne" -append "$cmd" -serial "file:$LOG" \
        -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "$@" >/dev/null 2>&1 || RC=$?
}

gruen() { # name beschreibung
    local name=$1 was=$2
    local log="$TMPD/$name.txt"
    if [ "$RC" -eq 21 ]; then
        ok "$was: Beendigungscode 21"
    else
        bad "$was: Beendigungscode $RC statt 21"
    fi
    if grep -qa '^kernel: done' "$log"; then
        ok "$was: bis \"kernel: done\" gekommen ($(grep -ac '' "$log") Zeilen)"
    else
        bad "$was: \"kernel: done\" fehlt ($(grep -ac '' "$log") Zeilen)"
        grep -a -A6 'EXCEPTION' "$log" | head -8 | sed 's/^/          /'
    fi
    if grep -qa 'EXCEPTION' "$log"; then
        bad "$was: an exception in the run -- $(grep -a -m1 'EXCEPTION' "$log")"
    else
        ok "$was: keine einzige Ausnahme"
    fi
}

echo
echo "== 1. the same kernel under KVM: five command lines =="

lauf kvm k1 128 1 "osum nokbd nosched noproc nofs noring3" "$TMPD/osum.mb"
gruen k1 "1.1 der kurze Lauf (an dem MSR 0x1A2 den Kernel getoetet hat)"

lauf kvm k2 512 1 "osum nopwr" "$TMPD/osum.mb"
gruen k2 "1.2 Prozesse in Ring 3 (an dem sysret/iretq den Kernel getoetet hat)"

lauf kvm k3 512 1 "osum" "$TMPD/osum.mb"
gruen k3 "1.3 der volle Lauf"

lauf kvm k4 512 1 "osum" "$TMPD/osum.mb" -cpu host
gruen k4 "1.4 mit -cpu host, also den ECHTEN Merkmalsbits dieser CPU"

lauf kvm k5 512 4 "osum smp" "$TMPD/osum.mb" -cpu host
gruen k5 "1.5 vier Prozessoren mit -cpu host"
kerne=$(grep -a -m1 '^smp: online=' "$TMPD/k5.txt" | sed 's/^smp: online=\([0-9]*\).*/\1/')
if [ "${kerne:-0}" -eq 4 ]; then
    ok "1.5 and all four really started (online=$kerne)"
else
    bad "1.5 online=${kerne:-fehlt} statt 4"
fi

echo
echo "== 2. the opposite direction: the same lines under TCG =="

lauf tcg t1 128 1 "osum nokbd nosched noproc nofs noring3" "$TMPD/osum.mb"
gruen t1 "2.1 der kurze Lauf unter TCG"
lauf tcg t2 512 1 "osum nopwr" "$TMPD/osum.mb"
gruen t2 "2.2 Prozesse in Ring 3 unter TCG"
lauf tcg t3 512 1 "osum" "$TMPD/osum.mb"
gruen t3 "2.3 der volle Lauf unter TCG"

echo
echo "== 3. what the real CPU says differently from the emulation =="

gp_kvm=$(grep -a -m1 '^pwr: msr-gp=' "$TMPD/k3.txt" | sed 's/^pwr: msr-gp=//' | tr -d '\r\000')
gp_tcg=$(grep -a -c '^pwr: msr-gp=' "$TMPD/t3.txt")
if [ "$gp_tcg" -eq 0 ]; then
    ok "3.1 under TCG not a single power register rejects the access"
else
    bad "3.1 under TCG there is a msr-gp line -- then this section measures nothing"
fi
if [ -n "$gp_kvm" ] && [ "$gp_kvm" -gt 0 ] 2>/dev/null; then
    ok "3.2 under KVM this CPU rejects $gp_kvm power registers -- caught instead of dead"
    HAT_GP=1
else
    hin "3.2 diese CPU hat alle Energieregister, die pwr.fi anfasst (msr-gp=0)"
    HAT_GP=0
fi

# ============================================ 4. die Gegenproben

echo
echo "== 4. the control runs: the versions in which it collapses =="

variante() { # name sed-ausdruck datei probe
    local name=$1 ausdruck=$2 datei=$3 probe=$4
    local R="$TMPD/v-$name"
    mkdir -p "$R/tools"
    cp -a kernel "$R/kernel"
    cp tools/build-kernel.sh "$R/tools/"
    ln -sfn "$ROOT/lib" "$R/lib"
    ln -sfn "$ROOT/vendor" "$R/vendor"
    sed -i "$ausdruck" "$R/kernel/$datei"
    if ! grep -qaF "$probe" "$R/kernel/$datei"; then
        bad "CONTROL RUN $name: the line could not be bent"
        return 1
    fi
    bash "$R/tools/build-kernel.sh" "$TMPD/$name.mb" --stufe 0 >/dev/null 2>&1
}

if variante ohnefaenger 's/^const GP_VECTOR: u64 = 13$/const GP_VECTOR: u64 = 133/' \
        arch/x86_64/trap.fi 'const GP_VECTOR: u64 = 133'; then
    lauf tcg gf-tcg 128 1 "osum nokbd nosched noproc nofs noring3" "$TMPD/ohnefaenger.mb"
    if [ "$RC" -eq 21 ] && grep -qa '^kernel: done' "$TMPD/gf-tcg.txt"; then
        ok "4.1 WITHOUT catcher path the kernel runs THROUGH under TCG -- the emulation does not see the error"
    else
        bad "4.1 WITHOUT catcher path the kernel already dies under TCG ($RC) -- then the control run measures something else"
    fi
    lauf kvm gf-kvm 128 1 "osum nokbd nosched noproc nofs noring3" "$TMPD/ohnefaenger.mb"
    if [ "$HAT_GP" -eq 1 ]; then
        if [ "$RC" -ne 21 ] && grep -qa 'EXCEPTION 13 #GP' "$TMPD/gf-kvm.txt"; then
            ok "4.2 WITHOUT catcher path the same kernel dies under KVM with a #GP ($(grep -a -m1 'rcx=' "$TMPD/gf-kvm.txt" | sed 's/.*\(rcx=[^ ]*\).*/\1/'))"
        else
            bad "4.2 WITHOUT catcher path the kernel runs through under KVM anyway ($RC) -- then it is not the catcher that saves it"
        fi
    else
        hin "4.2 ausgelassen: dieser Wirt verweigert kein Energieregister, hier ist nichts zu fangen"
    fi
fi

if variante altstar 's/(0x1B << 48)/(0x18 << 48)/' \
        arch/x86_64/user.fi '(0x18 << 48)'; then
    lauf tcg as-tcg 512 1 "osum nopwr" "$TMPD/altstar.mb"
    if [ "$RC" -eq 21 ] && grep -qa '^kernel: done' "$TMPD/as-tcg.txt"; then
        ok "4.3 with the OLD MSR_STAR the kernel runs THROUGH under TCG -- invisible for 25 rounds"
    else
        bad "4.3 with the old MSR_STAR the kernel already dies under TCG ($RC)"
    fi
    lauf kvm as-kvm 512 1 "osum nopwr" "$TMPD/altstar.mb"
    if [ "$HERSTELLER" = "AuthenticAMD" ]; then
        if [ "$RC" -ne 21 ] && grep -qa 'EXCEPTION 13 #GP  err=0x20' "$TMPD/as-kvm.txt"; then
            ok "4.4 with the OLD MSR_STAR it dies under KVM with #GP err=0x20 -- at selector 0x20 itself"
        else
            bad "4.4 with the old MSR_STAR the kernel runs through under KVM ($RC) -- then MSR_STAR is not the cause"
        fi
    else
        hin "4.4 ausgelassen: dieser Wirt ist ${HERSTELLER:-nicht AMD}, und Intel setzt die zwei Bits bei sysret selbst"
    fi
fi

if bash tools/build-kernel.sh "$TMPD/osum1.mb" --stufe 1 >/dev/null 2>&1; then
    lauf kvm s1 512 1 "osum nopwr" "$TMPD/osum1.mb"
    gruen s1 "4.5 der mit firnc1 gebaute Kernel unter KVM"
else
    bad "4.5 the kernel could not be built with firnc1"
fi

echo
echo "KVM: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
