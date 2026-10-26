corpus_tables hp-827d
ACPI_TIMEOUT=240 ACPI_MEM=4096 qrun "$K" fuzzclean "osum acpiev amlfuzz=200 amlfuzzmut=0 ecsim noring3 nofs" "${TABLE_ARGS[@]}"
sum=$(line fuzzclean '^amlfuzz: iters=')
chk "control: unmutated loads all succeed" "iters=200 e0=200" "iters=$(val "$sum" iters) e0=$(val "$sum" e0)"
for seed in 1 2 3; do
    ACPI_TIMEOUT=240 ACPI_MEM=4096 qrun "$K" "fuzz$seed" "osum acpiev amlfuzz=400 amlfuzzmut=4 amlfuzzseed=$seed ecsim noring3 nofs" "${TABLE_ARGS[@]}"
    sum=$(line "fuzz$seed" '^amlfuzz: iters=')
    chk "seed $seed: iterations survived" 400 "$(val "$sum" iters)"
    chk "seed $seed: no frame leaked" 0 "$(val "$sum" leaked)"
    chk "seed $seed: finished and kernel exited" "1/21" "$(has "fuzz$seed" '^amlfuzz: done')/$(cat "$D/fuzz$seed.rc")"
    chk_ge "seed $seed: mutations produced defined errors" 1 "$(( $(count "fuzz$seed" '^amlfuzz: iters=.* e[1-9]') ))"
done
qrun "$K" fuzzplain "osum acpiev amlfuzz=300 amlfuzzmut=3 amlfuzzseed=9 noring3 nofs"
sum=$(line fuzzplain '^amlfuzz: iters=')
chk "QEMU DSDT: iterations survived" 300 "$(val "$sum" iters)"
chk "QEMU DSDT: no frame leaked" 0 "$(val "$sum" leaked)"
