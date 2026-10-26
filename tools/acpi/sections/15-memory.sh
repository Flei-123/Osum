ACPI_MEM=2048 qrun "$K" mem2g "osum acpiev noring3 nofs"
chk "2 GiB machine: DSDT found" 1 "$(val "$(line mem2g '^aml: tables=')" tables)"
chk "2 GiB machine: events stage ready" 1 "$(val "$(line mem2g '^acpiev: ready=')" ready)"
ACPI_MEM=4096 qrun "$K" mem4g "osum acpiev noring3 nofs"
chk "4 GiB machine: DSDT found" 1 "$(val "$(line mem4g '^aml: tables=')" tables)"
chk "4 GiB machine: events stage ready" 1 "$(val "$(line mem4g '^acpiev: ready=')" ready)"
if [ -n "$KB" ]; then
    ACPI_MEM=2048 qrun "$KB" mem2gbase "osum acpiev noring3 nofs"
    echo "  note  before: 2 GiB machine, aml tables=$(val "$(line mem2gbase '^aml: tables=')" tables) acpiev ready=$(val "$(line mem2gbase '^acpiev: ready=')" ready)"
fi
