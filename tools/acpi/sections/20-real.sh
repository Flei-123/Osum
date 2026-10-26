ACPI_MEM=4096 qrun "$K" plain "osum acpiev noring3 nofs"
base_nodes=$(val "$(line plain '^aml: tables=')" nodes)

declare -A WANT_NODES=([hp-827d]=5216 [surface-laptop-4]=4573 [amd-server]=3130)
declare -A WANT_DEFER=([hp-827d]=11 [surface-laptop-4]=7 [amd-server]=1)
declare -A FULL_KINDS=(
    [hp-827d]="_STA _CRS _BIF _BIX _BST _PSR _BCL _BQC _PRW _EJ0 _WAK _E__"
    [surface-laptop-4]="_STA _CRS _PRS _BCL _BQC _PRW _PTS _WAK _EJ0 _E__"
    [amd-server]="_PRS _PRW _PTS _WAK _EJ0 _L__ _E__"
)

for machine in hp-827d surface-laptop-4 amd-server; do
    corpus_tables "$machine"
    ACPI_TIMEOUT=300 ACPI_MEM=4096 qrun "$K" "real-$machine" "osum acpiev amlsweep ecsim noring3 nofs" "${TABLE_ARGS[@]}"
    hold=$(line "real-$machine" '^amlhold: ')
    chk "$machine: loader reports no error" 0 "$(val "$hold" e)"
    chk "$machine: no table counted bad" 0 "$(val "$hold" bad)"
    chk "$machine: nodes added to the QEMU namespace" "${WANT_NODES[$machine]}" "$(( $(val "$hold" nodes) - base_nodes ))"
    chk "$machine: region operands deferred (as measured on the device for the HP)" "${WANT_DEFER[$machine]}" "$(val "$hold" defer)"
    chk "$machine: sweep finished" 1 "$(has "real-$machine" '^amlsweep: done')"
    chk "$machine: no method failed on an unsupported opcode" 0 "$(count "real-$machine" '^amlsweep: opcode')"
    for kind in ${FULL_KINDS[$machine]}; do
        n=$(val "$(sweep_line "real-$machine" "$kind")" n)
        chk "$machine: every $kind evaluated ok ($n)" "$n/$n" "$(sweep_full "real-$machine" "$kind")"
    done
    chk "$machine: kernel finished" 21 "$(cat "$D/real-$machine.rc")"
done
