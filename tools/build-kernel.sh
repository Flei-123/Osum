#!/usr/bin/env bash
# tools/build-kernel.sh -- EIN Kernelabbild, aus dem Repo heraus.
#
# Bis hierher hat jeder Testlaeufer unter tools/ den Kernel selbst gebaut,
# und jeder tat es mit denselben zehn Zeilen. Das ging, solange nur die
# Laeufer bauten. Seit OrientOS diesen Kernel als seine Grundlage benutzt
# (vendor/osum dort), braucht es EINE Stelle, die sagt, wie ein Abbild
# entsteht -- sonst baut das andere Repo etwas leicht anderes und misst
# etwas leicht anderes.
#
#   ./tools/build-kernel.sh AUSGABE [--stufe 0|1] [--cmdline "..."]
#
# Ergebnis: AUSGABE ist ein Multiboot-Abbild (ELF32-Huelle, damit sowohl
# `qemu-system-x86_64 -kernel` als auch ein Multiboot-Lader wie Limine es
# nimmt). Daneben liegt AUSGABE.elf, die ungewandelte ELF64-Fassung mit
# den Symbolen -- die braucht, wer einen Rueckverfolger schreibt.
#
# --stufe waehlt den Uebersetzer: 0 = firnc0 (Rust), 1 = firnc1 (Firn).
# Beide muessen dasselbe Abbild bauen koennen; genau das misst ./test.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

AUS=${1:-}
if [[ -z $AUS ]]; then
    sed -n '2,20p' "$0"
    exit 1
fi
shift

STUFE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stufe) STUFE=$2; shift 2 ;;
        *) echo "unbekannte Option: $1" >&2; exit 1 ;;
    esac
done

export FIRNLIB="$ROOT/lib"
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen" >&2; exit 1; }

if [[ $STUFE == 0 ]]; then
    FIRNC="$ROOT/vendor/firn/bin/firnc"
else
    FIRNC="$ROOT/vendor/firn/bin/firnc1"
fi
[[ -x $FIRNC ]] || { echo "Uebersetzer fehlt: $FIRNC" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Die fuenf Assemblerdateien. Was in ihnen steht, kann eine Sprache nicht
# ausdruecken: der Multiboot-Kopf, der Sprung in den langen Modus, die
# Einsprungpunkte der Unterbrechungen, der Kontextwechsel, der
# Trampolinsprung der anderen Prozessoren -- und seit Runde K12 der
# Weltwechsel in eine Gastmaschine samt den Gaesten selbst (hv.s).
for f in boot isr switch smp hv; do
    as --64 -o "$TMP/$f.o" "kernel/$f.s" || exit 1
done

"$FIRNC" -o "$TMP/k.o" kernel/kmain.fi || exit 1
"$FIRNC" -o "$TMP/uprog.o" kernel/uprog.fi || exit 1

# firnc0 stellt jedem Symbol `_F0.` voran, firnc1 `_F1.`
# (docs/SELF_HOSTING.md im Firn-Repo).
P="_F${STUFE}."
ld -n -T kernel/kernel.ld \
    --defsym=KERNEL_MAIN="${P}kernel_main" \
    --defsym=KERNEL_TRAP="${P}trap__entry" \
    --defsym=KERNEL_SYSCALL="${P}sys__entry" \
    --defsym=KERNEL_TASK_MAIN="${P}tasks__main" \
    --defsym=KERNEL_USER_START="${P}proc__user_start" \
    --defsym=KERNEL_AP_MAIN="${P}smp__ap_main" \
    --defsym=USER_MAIN="${P}u_enter" \
    -o "$TMP/osum.elf" "$TMP/boot.o" "$TMP/isr.o" "$TMP/switch.o" \
    "$TMP/smp.o" "$TMP/hv.o" "$TMP/k.o" "$TMP/uprog.o" 2> >(grep -vE \
        'GNU-stack|deprecated|LOAD segment with RWX' >&2) || exit 1

mkdir -p "$(dirname "$AUS")"
cp -f "$TMP/osum.elf" "$AUS.elf"
objcopy -O elf32-i386 "$TMP/osum.elf" "$AUS" || exit 1
echo "$AUS ($(stat -c%s "$AUS") Oktette, Stufe $STUFE)"
