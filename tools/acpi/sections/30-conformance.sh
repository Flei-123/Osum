if ! asl_conform; then
    chk "conformance tables compile" 1 0
else
    want=$(grep -c 'Method (T[0-9]' tools/acpi/asl/conform.asl)
    qrun "$K" conform "osum acpiev amlconf noring3 nofs" -acpitable "file=$D/conform.aml"
    sum=$(line conform '^amlconf: pass=')
    chk "conformance: tests that passed" "$want" "$(val "$sum" pass)"
    chk "conformance: failures are only the planted one" 1 "$(val "$sum" fail)"
    chk "counter-proof: the planted failing test is reported" 1 "$(has conform '^amlconf: fail TBAD ret=999 e=0$')"
    chk "conformance: no other test failed" 1 "$(count conform '^amlconf: fail ')"
    chk "conformance: kernel finished" 21 "$(cat "$D/conform.rc")"
fi
