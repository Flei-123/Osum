#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/kvm/run.sh -- DERSELBE KERNEL AUF DER ECHTEN CPU.
#
# ==================================================================
# WARUM ES DIESEN ABSCHNITT GIBT
# ==================================================================
#
# Die ganze Abnahme dieses Projekts lief bis zur Runde KVMFIX unter TCG:
# QEMU uebersetzt die Gastbefehle in Wirtsbefehle und fuehrt DIE aus.
# Das ist eine Nachbildung, und eine Nachbildung ist NACHSICHTIG. Sie
# nimmt Register an, die es nicht gibt, und sie legt bei `sysret`
# stillschweigend Bits zurecht, die eine echte CPU so laesst, wie der
# Kernel sie hingeschrieben hat.
#
# Mit /dev/kvm laeuft derselbe Gastcode auf der ECHTEN CPU. Damit ist
# dieser Abschnitt die naechstbeste Sache zu einem echten PC -- und er
# hat auf Anhieb ZWEI Fehler gefunden, die 25 Runden lang unter TCG
# unsichtbar waren und die auf einem echten Rechner beide toedlich sind:
#
#   1. IA32_TEMPERATURE_TARGET (MSR 0x1A2) ist ein INTEL-Register.
#      `pwr.fi` las es ungeschuetzt. Auf einer AMD-CPU: #GP, Kernel tot.
#      Unter TCG gab QEMU eine Null zurueck und niemand merkte etwas.
#   2. MSR_STAR trug als `sysret`-Grundwert 0x18. Daraus macht `sysretq`
#      SS = 0x18 + 8 = 0x20 -- ein Selektor mit RPL 0. INTEL und QEMUs
#      TCG setzen die untersten zwei Bits dabei selbst auf 3 (aus 0x20
#      wird 0x23); AMD tut das NICHT. Der naechste Zeitgeberschlag in
#      Ring 3 landete dann im `iretq` des Kernels, und der verlangt
#      SS.RPL == CPL: #GP mit Fehlercode 0x20, dem Selektor selbst.
#
# Beide sind behoben (`kernel/msr.fi`, `kernel/arch/x86_64/user.fi`).
# Dieser Laeufer sorgt dafuer, dass sie behoben BLEIBEN.
#
# ==================================================================
# WAS HIER GEMESSEN WIRD
# ==================================================================
#
#   1. DER KERNEL LAEUFT UNTER KVM DURCH. Fuenf Befehlszeilen, und jede
#      muss dasselbe liefern wie unter TCG: Beendigungscode 21, die
#      Zeile "kernel: done", und KEIN "EXCEPTION" irgendwo dazwischen.
#      Darunter die beiden Zeilen, an denen der Kernel gestorben ist.
#   2. DERSELBE LAUF UNTER TCG IST AUCH GRUEN. Ohne diese Haelfte waere
#      nicht gesagt, ob KVM etwas repariert oder nur etwas anderes tut.
#   3. `-cpu host`: die ECHTEN Merkmalsbits der Wirts-CPU, ohne QEMUs
#      Maske davor. Das ist der Lauf, der einem echten PC am naechsten
#      kommt.
#   4. VIER PROZESSOREN. Der Weg ueber das Trampolin und die
#      APIC-Startfolge ist unter KVM eine andere Strecke als unter TCG.
#   5. UND DREI GEGENPROBEN, IN DENEN DIE MESSUNG ZUSAMMENBRICHT.
#      Eine Zusage ohne eine Fassung, in der sie faellt, ist keine:
#         * der Kernel OHNE Faengerpfad (`GP_VECTOR` verbogen) MUSS
#           unter KVM an einem #GP sterben -- und unter TCG trotzdem
#           durchlaufen. Genau das ist der Unterschied, um den es geht.
#         * der Kernel mit dem ALTEN MSR_STAR (0x18) MUSS unter KVM mit
#           err=0x20 sterben -- und unter TCG trotzdem durchlaufen.
#         * beide Gegenproben laufen NUR dort, wo sie etwas beweisen
#           koennen: die erste nur, wenn dieser Wirt wirklich ein
#           Register verweigert (`pwr: msr-gp` groesser 0), die zweite
#           nur auf einer AMD-CPU. Auf einem Intel-Wirt sagt der Laeufer
#           das hin und laesst die Gegenprobe aus, statt eine Zusage zu
#           erfinden, die dort gar nicht gelten kann.
#
# OHNE /dev/kvm WIRD UEBERSPRUNGEN, nicht gemeldet. Ein Rechner ohne
# Virtualisierung kann diese Frage nicht beantworten, und eine rote
# Abnahme, die nur "hier fehlt ein Geraet" bedeutet, waere Laerm.
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
    echo "KVM: uebersprungen, /dev/kvm ist nicht da oder nicht benutzbar"
    exit 0
fi

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# Und die Probe aufs Exempel: laesst sich mit diesem /dev/kvm wirklich
# eine Maschine starten? Ein Container kann den Geraeteknoten haben und
# trotzdem an einer Berechtigung scheitern. Dann wird uebersprungen und
# nicht gemeldet.
if ! qemu-system-x86_64 -accel kvm -m 32 -display none -no-reboot \
        -kernel /bin/true > "$TMPD/probe.txt" 2>&1; then
    if grep -qi 'kvm' "$TMPD/probe.txt" \
       && grep -qiE 'permission|failed to initialize|not access|no such' "$TMPD/probe.txt"; then
        echo "KVM: uebersprungen, /dev/kvm laesst sich nicht benutzen"
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
    || { echo "KVM: der Kernel liess sich nicht bauen"; exit 1; }
if [ -s "$TMPD/osum.mb" ]; then
    ok "der Kernel ist gebaut ($(stat -c%s "$TMPD/osum.mb") Oktette, Stufe 0)"
else
    bad "der Kernel fehlt"
fi

# lauf BESCHLEUNIGER NAME SPEICHER KERNE BEFEHLSZEILE ABBILD [ZUSATZ...]
# Setzt LOG auf die Ausgabedatei und RC auf den Beendigungscode.
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

# Ein vollstaendiger, GRUENER Lauf: 21, "kernel: done", kein "EXCEPTION".
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
        bad "$was: eine Ausnahme im Lauf -- $(grep -a -m1 'EXCEPTION' "$log")"
    else
        ok "$was: keine einzige Ausnahme"
    fi
}

# ================================================ 1. der Kernel unter KVM

echo
echo "== 1. derselbe Kernel unter KVM: fuenf Befehlszeilen =="

# Genau die Zeile, an der Absturz 1 hing (rdmsr 0x1A2 in pwr.probe).
lauf kvm k1 128 1 "osum nokbd nosched noproc nofs noring3" "$TMPD/osum.mb"
gruen k1 "1.1 der kurze Lauf (an dem MSR 0x1A2 den Kernel getoetet hat)"

# Genau die Zeile, an der Absturz 2 hing (iretq nach Ring 3 mit SS.RPL 0).
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
    ok "1.5 und alle vier sind wirklich angelaufen (online=$kerne)"
else
    bad "1.5 online=${kerne:-fehlt} statt 4"
fi

# ============================== 2. dieselben Zeilen unter TCG sind auch gruen

echo
echo "== 2. die Gegenrichtung: dieselben Zeilen unter TCG =="

lauf tcg t1 128 1 "osum nokbd nosched noproc nofs noring3" "$TMPD/osum.mb"
gruen t1 "2.1 der kurze Lauf unter TCG"
lauf tcg t2 512 1 "osum nopwr" "$TMPD/osum.mb"
gruen t2 "2.2 Prozesse in Ring 3 unter TCG"
lauf tcg t3 512 1 "osum" "$TMPD/osum.mb"
gruen t3 "2.3 der volle Lauf unter TCG"

# ================================ 3. was die echte CPU anders sagt als TCG

echo
echo "== 3. was die echte CPU anders sagt als die Nachbildung =="

# `pwr: msr-gp=N` erscheint NUR, wenn wirklich ein Register mit einem #GP
# geantwortet hat. Unter TCG antwortet keines so -- die Zeile darf dort
# also nicht stehen. Das ist die Messung des Unterschieds selbst.
gp_kvm=$(grep -a -m1 '^pwr: msr-gp=' "$TMPD/k3.txt" | sed 's/^pwr: msr-gp=//' | tr -d '\r\000')
gp_tcg=$(grep -a -c '^pwr: msr-gp=' "$TMPD/t3.txt")
if [ "$gp_tcg" -eq 0 ]; then
    ok "3.1 unter TCG weist kein einziges Energieregister den Zugriff ab"
else
    bad "3.1 unter TCG steht eine msr-gp-Zeile -- dann misst dieser Abschnitt nichts"
fi
if [ -n "$gp_kvm" ] && [ "$gp_kvm" -gt 0 ] 2>/dev/null; then
    ok "3.2 unter KVM weist diese CPU $gp_kvm Energieregister ab -- gefangen statt gestorben"
    HAT_GP=1
else
    hin "3.2 diese CPU hat alle Energieregister, die pwr.fi anfasst (msr-gp=0)"
    HAT_GP=0
fi

# ============================================ 4. die Gegenproben

echo
echo "== 4. die Gegenproben: die Fassungen, in denen es zusammenbricht =="

# Baut den Kern EINMAL anders. Der Kernbaum wird kopiert, EINE Zeile
# verbogen und aus der Kopie gebaut -- denselben Weg geht
# tools/build-kernel.sh ohnehin (es uebersetzt immer aus /tmp), also ist
# der Unterschied zwischen den Abbildern wirklich nur diese Zeile.
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
        bad "GEGENPROBE $name: die Zeile liess sich nicht verbiegen"
        return 1
    fi
    bash "$R/tools/build-kernel.sh" "$TMPD/$name.mb" --stufe 0 >/dev/null 2>&1
}

# --- OHNE FAENGERPFAD ------------------------------------------------
# `GP_VECTOR` in trap.fi auf 133 gelegt: der #GP-Behandler sieht in der
# Faengertabelle nicht mehr nach, jedes fehlende MSR ist wieder toedlich.
if variante ohnefaenger 's/^const GP_VECTOR: u64 = 13$/const GP_VECTOR: u64 = 133/' \
        arch/x86_64/trap.fi 'const GP_VECTOR: u64 = 133'; then
    lauf tcg gf-tcg 128 1 "osum nokbd nosched noproc nofs noring3" "$TMPD/ohnefaenger.mb"
    if [ "$RC" -eq 21 ] && grep -qa '^kernel: done' "$TMPD/gf-tcg.txt"; then
        ok "4.1 OHNE Faengerpfad laeuft der Kernel unter TCG DURCH -- die Nachbildung sieht den Fehler nicht"
    else
        bad "4.1 OHNE Faengerpfad stirbt der Kernel schon unter TCG ($RC) -- dann misst die Gegenprobe etwas anderes"
    fi
    lauf kvm gf-kvm 128 1 "osum nokbd nosched noproc nofs noring3" "$TMPD/ohnefaenger.mb"
    if [ "$HAT_GP" -eq 1 ]; then
        if [ "$RC" -ne 21 ] && grep -qa 'EXCEPTION 13 #GP' "$TMPD/gf-kvm.txt"; then
            ok "4.2 OHNE Faengerpfad stirbt derselbe Kernel unter KVM an einem #GP ($(grep -a -m1 'rcx=' "$TMPD/gf-kvm.txt" | sed 's/.*\(rcx=[^ ]*\).*/\1/'))"
        else
            bad "4.2 OHNE Faengerpfad laeuft der Kernel unter KVM trotzdem durch ($RC) -- dann rettet ihn nicht der Faenger"
        fi
    else
        hin "4.2 ausgelassen: dieser Wirt verweigert kein Energieregister, hier ist nichts zu fangen"
    fi
fi

# --- DER ALTE MSR_STAR -----------------------------------------------
# 0x18 statt 0x1B: `sysretq` legt SS = 0x20 an, RPL 0. Auf Intel und
# unter TCG faellt das nicht auf, weil beide die zwei Bits selbst setzen.
if variante altstar 's/(0x1B << 48)/(0x18 << 48)/' \
        arch/x86_64/user.fi '(0x18 << 48)'; then
    lauf tcg as-tcg 512 1 "osum nopwr" "$TMPD/altstar.mb"
    if [ "$RC" -eq 21 ] && grep -qa '^kernel: done' "$TMPD/as-tcg.txt"; then
        ok "4.3 mit dem ALTEN MSR_STAR laeuft der Kernel unter TCG DURCH -- 25 Runden lang unsichtbar"
    else
        bad "4.3 mit dem alten MSR_STAR stirbt der Kernel schon unter TCG ($RC)"
    fi
    lauf kvm as-kvm 512 1 "osum nopwr" "$TMPD/altstar.mb"
    if [ "$HERSTELLER" = "AuthenticAMD" ]; then
        if [ "$RC" -ne 21 ] && grep -qa 'EXCEPTION 13 #GP  err=0x20' "$TMPD/as-kvm.txt"; then
            ok "4.4 mit dem ALTEN MSR_STAR stirbt er unter KVM an #GP err=0x20 -- am Selektor 0x20 selbst"
        else
            bad "4.4 mit dem alten MSR_STAR laeuft der Kernel unter KVM durch ($RC) -- dann ist MSR_STAR nicht die Ursache"
        fi
    else
        hin "4.4 ausgelassen: dieser Wirt ist ${HERSTELLER:-nicht AMD}, und Intel setzt die zwei Bits bei sysret selbst"
    fi
fi

# --- UND DER ZWEITE UEBERSETZER --------------------------------------
# firnc0 und firnc1 bauen denselben Kernel, und beide muessen unter KVM
# durchlaufen. Ohne das gilt die Zusage nur fuer eine der beiden Stufen.
if bash tools/build-kernel.sh "$TMPD/osum1.mb" --stufe 1 >/dev/null 2>&1; then
    lauf kvm s1 512 1 "osum nopwr" "$TMPD/osum1.mb"
    gruen s1 "4.5 der mit firnc1 gebaute Kernel unter KVM"
else
    bad "4.5 der Kernel liess sich mit firnc1 nicht bauen"
fi

echo
echo "KVM: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
