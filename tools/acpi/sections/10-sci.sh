REAL=tools/acpi/real

qrun "$K" route "osum acpiev evself noring3 nofs"
route=$(line route '^acpiev: route ')
chk "SCI routed from the MADT override (irq gsi flags level low count)" \
    "irq=9 gsi=9 flags=0x000d level=1 low=0 ovr=5" \
    "irq=$(val "$route" irq) gsi=$(val "$route" gsi) flags=$(val "$route" flags) level=$(val "$route" level) low=$(val "$route" low) ovr=$(val "$route" ovr)"
chk "I/O APIC entry: level, active high, vector 37" "0x00008025" "$(val "$(line route '^acpiev: ready=')" ioapic)"
chk "diagnostic line scix" 1 "$(has route '^scix gsi=9 irq=9 flags=0x000d level=1 low=0 irqs=0 shared=0 empty=0 storms=0 masked=0 polls=0 stray_pm1=0 stray_gpe=0 stray_bit=65535 armed=2 gpe_masked=0 gpe_failed=0$')"
chk "diagnostic line scireg" 1 "$(has route '^scireg pm1sts=0x[0-9a-f]{4} pm1en=0x0100 gpests=0x[0-9a-f]{8},0x[0-9a-f]{8},0x[0-9a-f]{8},0x[0-9a-f]{8} gpeen=0x00000006,')"
chk "GPE register selftest" 1 "$(has route '^acpiev: selftest reg ok')"

qrun "$K" ovrdump "osum amldump noring3 nofs"
tool dumptab.py "$D/ovrdump.txt" APIC "$D/apic.bin"
want=$(tool madt.py "$D/apic.bin" | tr '\n' ';')
got=$(lines_of route '^acpiev: ovr ' | sed -E 's/^acpiev: ovr //; s/flags=0x/flags=0x/' | tr '\n' ';')
chk "kernel override list equals the independent parse of the dumped MADT" "$want" "$got"

qrun "$K" noovr "osum acpiev evself scinoovr noring3 nofs"
chk "counter-proof scinoovr: default route flags" "irq=9 gsi=9 flags=0x0000 level=1 low=1" \
    "irq=$(val "$(line noovr '^acpiev: route ')" irq) gsi=$(val "$(line noovr '^acpiev: route ')" gsi) flags=$(val "$(line noovr '^acpiev: route ')" flags) level=$(val "$(line noovr '^acpiev: route ')" level) low=$(val "$(line noovr '^acpiev: route ')" low)"
chk "counter-proof scinoovr: entry is level, active low" "0x0000a025" "$(val "$(line noovr '^acpiev: ready=')" ioapic)"

for machine in surface-laptop-4 amd-server; do
    tool retag.py "$REAL/$machine/APIC" "$D/xapc-$machine.bin" XAPC
    qrun "$K" "xapc-$machine" "osum acpiev evself noring3 nofs" -acpitable "file=$D/xapc-$machine.bin"
    want=$(tool madt.py "$REAL/$machine/APIC" | sed -E 's/^/acpiev: xapc /' | tr '\n' ';')
    got=$(lines_of "xapc-$machine" '^acpiev: xapc ' | tr '\n' ';')
    chk "real MADT of $machine parsed like the independent parser" "$want" "$got"
done

qrun "$K" stray "osum acpiev evself evwait scistorm noring3 nofs"
last=$(lastline stray '^acpiev: ready=')
chk "stray PM1 event: cleared once" 1 "$(val "$last" stray)"
chk_le "stray PM1 event: no storm (interrupts)" 4 "$(val "$last" irqs)"
chk "stray PM1 event: line stays unmasked" 0 "$(val "$last" masked)"
chk "stray PM1 event: timer enable bit switched off" "0x0100" "$(val "$last" pm1en)"

qstart "$K" storm "osum acpiev evdump evwait scistorm noscistray noring3 nofs"
qwaitfor storm 'acpiev: sci storm' 300
sleep 2
qmon storm system_powerdown
qwaitfor storm 'acpiev: ev taste' 100
qwaitexit storm 150
qfinish storm
last=$(lastline storm '^acpiev: ready=')
chk "storm guard fired once" 1 "$(count storm '^acpiev: sci storm gsi=9 ')"
chk "storm line names the source (PM1 timer status+enable)" 1 "$(has storm '^acpiev: sci storm gsi=9 empty=256 irqs=[0-9]+ entry=0x00018025 pm1sts=0x0001 pm1en=0x0101$')"
chk_le "storm cut off after the empty limit (interrupts)" 400 "$(val "$last" irqs)"
chk "line masked, polling continues" 1 "$(val "$last" masked)"
chk_ge "polls counted while masked" 1 "$(val "$last" polls)"
chk "power button still seen while the line is masked" 1 "$(has storm '^acpiev: ev taste')"
chk "storm snapshot in the diagnostics" 1 "$(has storm '^scisnap ')"

qrun "$K" nostorm "osum acpiev evwait scistorm noscistray noscistorm noring3 nofs"
last=$(lastline nostorm '^acpiev: ready=')
chk_ge "counter-proof noscistorm: the storm runs on (interrupts)" 100000 "$(val "$last" irqs)"
chk "counter-proof noscistorm: line never masked" 0 "$(val "$last" masked)"

qstart "$K" button "osum acpiev evdump evwait noring3 nofs"
qwaitfor button 'acpiev: ready=' 300
sleep 2
qmon button system_powerdown
qwaitfor button 'acpiev: ev taste' 100
qfinish button
chk "power button: SCI delivered, press reported" 1 "$(count button '^acpiev: ev taste')"
chk "power button: no storm detected" 0 "$(count button 'acpiev: sci storm')"

qstart "$K" nobutton "osum noacpiev evdump noring3 nofs"
qwaitfor nobutton 'kernel: done' 200
sleep 1
qmon nobutton system_powerdown
sleep 2
qfinish nobutton
chk "counter-proof noacpiev: press not reported" 0 "$(count nobutton 'ev taste')"

ECAML=tools/ecquery/asl/ec
if [ ! -f $ECAML.aml ]; then iasl -p $ECAML $ECAML.asl > /dev/null 2>&1; fi
qrun "$K" ecrate "osum acpiev evself ecsim noring3 nofs" -acpitable "file=$ECAML.aml"
chk "EC polling is rate limited (polls in a burst of 2000 calls)" 1 "$(val "$(line ecrate '^acpiev: selftest ecrate ')" polls)"

chk "evaluation guard refuses a second entry" 1 "$(has route '^acpiev: selftest guard ok')"

gpe_hotplug() {
    local name=$1 append=$2
    qstart "$K" "$name" "$append"
    qwaitfor "$name" 'acpiev: ready=' 300
    sleep 2
    qmon "$name" 'device_add e1000,id=hp0,bus=pci.0,addr=0x7'
    qwaitexit "$name" 300
}

gpe_hotplug gpeedge "osum acpiev evdump evwait noring3 nofs"
chk "PCI hotplug GPE (edge): method ran" 1 "$(has gpeedge '^acpiev: ev gpe b=0x01')"
chk "PCI hotplug GPE (edge): never masked" 0 "$(val "$(lastline gpeedge '^scix ')" gpe_masked)"
gpe_hotplug gpelevel "osum acpiev evdump evwait scigpelv noring3 nofs"
chk "PCI hotplug GPE treated as level: method ran" 1 "$(has gpelevel '^acpiev: ev gpe b=0x01')"
chk "level GPE: masked while pending" 1 "$(val "$(lastline gpelevel '^scix ')" gpe_masked)"
chk "level GPE: enable bit back after the method" "0x00000006" "$(echo "$(lastline gpelevel '^scireg ')" | grep -oE 'gpeen=0x[0-9a-f]{8}' | sed 's/gpeen=//')"
chk "level GPE: no failure" 0 "$(val "$(lastline gpelevel '^scix ')" gpe_failed)"

qrun "$K" defer "osum acpiev evself blpch scidefer noring3 nofs"
chk "brightness key from the interrupt path is queued, applied by the pump" "before=50 queued=1 after=60" \
    "$(line defer '^acpiev: defer ' | sed -E 's/^acpiev: defer //')"
