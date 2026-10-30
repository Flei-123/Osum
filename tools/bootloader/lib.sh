# SPDX-License-Identifier: GPL-2.0-only
OSB_OFF=$((2048*512))
OSB_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OSB_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
OSB_KVM=(); [ -w /dev/kvm ] && OSB_KVM=(-accel kvm -cpu host)

osb_prepare() {
    local dir=$1
    bash tools/bootloader/build.sh "$dir/BOOTX64.EFI" > "$dir/osboot-build.txt" 2>&1 || { cat "$dir/osboot-build.txt"; return 1; }
    if [ -n "${STICK_IMG:-}" ]; then
        cp "$STICK_IMG" "$dir/stick.img"
    else
        bash tools/usbimg/build.sh "$dir/build" > "$dir/build.txt" 2>&1 || { tail -5 "$dir/build.txt"; return 1; }
        mv "$dir/build/${MARKE_DATEI}-usb.img" "$dir/stick.img"
        rm -rf "$dir/build"
    fi
    if [ -n "${KERNEL:-}" ]; then
        mcopy -i "$dir/stick.img@@$OSB_OFF" -o "$KERNEL" ::osum.mb || return 1
    fi
    mcopy -i "$dir/stick.img@@$OSB_OFF" ::limine.conf "$dir/limine.conf" || return 1
    sed -i 's/^timeout: .*/timeout: 0/' "$dir/limine.conf"
    cp "$dir/stick.img" "$dir/limine.img"
    mcopy -i "$dir/limine.img@@$OSB_OFF" -o "$dir/limine.conf" ::limine.conf || return 1
    python3 tools/bootloader/mkcfg.py "$dir/limine.conf" "$dir/osboot.cfg" --timeout 0 --logo /osboot.logo > /dev/null || return 1
    python3 tools/bootloader/mklogo.py assets/marke/start-quelle.png "$dir/osboot.logo" > /dev/null || return 1
    mcopy -i "$dir/stick.img@@$OSB_OFF" -o "$dir/osboot.logo" ::osboot.logo || return 1
    mcopy -i "$dir/stick.img@@$OSB_OFF" -o "$dir/BOOTX64.EFI" ::EFI/BOOT/BOOTX64.EFI || return 1
    mcopy -i "$dir/stick.img@@$OSB_OFF" -o "$dir/osboot.cfg" ::osboot.cfg
}

osb_bus() {
    case "$1" in
        ehci) echo "-device usb-ehci -device usb-storage,drive=stick" ;;
        xhci) echo "-device qemu-xhci -device usb-storage,drive=stick" ;;
        ide) echo "-device ide-hd,drive=stick,bus=ide.0,bootindex=0" ;;
        ahci) echo "-device ide-hd,drive=stick,bus=ide.0,bootindex=0" ;;
        nvme) echo "-device nvme,drive=stick,serial=osbstick,bootindex=0" ;;
    esac
}

osb_boot() {
    local dir=$1 name=$2 img=$3 mach=$4 bus=$5 secs=$6 want=$7
    cp "$img" "$dir/$name.img"
    cp "$OSB_VARS" "$dir/$name.vars"
    rm -f "$dir/$name.txt"
    local t0 t1
    t0=$(date +%s%N)
    timeout $((secs+15)) qemu-system-x86_64 "${OSB_KVM[@]}" -machine "$mach" -m 2048 -smp 2 \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OSB_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$dir/$name.vars" \
        -drive "file=$dir/$name.img,format=raw,if=none,id=stick" $(osb_bus "$bus") \
        -serial "file:$dir/$name.txt" -display none -no-reboot -pidfile "$dir/$name.pid" &
    local i=0
    while [ $i -lt $((secs*5)) ]; do
        grep -aq "$want\|EXCEPTION" "$dir/$name.txt" 2>/dev/null && break
        sleep 0.2; i=$((i+1))
    done
    t1=$(date +%s%N)
    OSB_MS=$(( (t1 - t0) / 1000000 ))
    grep -aq "$want" "$dir/$name.txt" 2>/dev/null || OSB_MS=-1
    sleep "${OSB_TAIL:-0}"
    kill "$(cat "$dir/$name.pid" 2>/dev/null)" 2>/dev/null; wait 2>/dev/null
    rm -f "$dir/$name.img" "$dir/$name.vars"
}

osb_with_cfg() {
    local dir=$1 name=$2 cfg=$3
    cp "$dir/stick.img" "$dir/$name.base"
    if [ "$cfg" = "-" ]; then
        mdel -i "$dir/$name.base@@$OSB_OFF" ::osboot.cfg
    else
        mcopy -i "$dir/$name.base@@$OSB_OFF" -o "$cfg" ::osboot.cfg
    fi
}

osb_without_limine() {
    local dir=$1 name=$2
    mdel -i "$dir/$name.base@@$OSB_OFF" ::limine.conf
}

osb_start() {
    local dir=$1 name=$2 img=$3 mach=$4 bus=$5
    cp "$img" "$dir/$name.img"
    cp "$OSB_VARS" "$dir/$name.vars"
    rm -f "$dir/$name.txt" "$dir/$name.mon"
    qemu-system-x86_64 "${OSB_KVM[@]}" -machine "$mach" -m 2048 -smp 2 \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OSB_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$dir/$name.vars" \
        -drive "file=$dir/$name.img,format=raw,if=none,id=stick" $(osb_bus "$bus") \
        -serial "file:$dir/$name.txt" -monitor "unix:$dir/$name.mon,server,nowait" \
        -display none -no-reboot -pidfile "$dir/$name.pid" &
    local i=0
    while [ ! -S "$dir/$name.mon" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
}

osb_wait_text() {
    local dir=$1 name=$2 want=$3 secs=$4 i=0
    while [ $i -lt $((secs*5)) ]; do
        grep -aq "$want" "$dir/$name.txt" 2>/dev/null && return 0
        sleep 0.2; i=$((i+1))
    done
    return 1
}

osb_hmp() {
    python3 -I tools/bootloader/hmp.py "$1/$2.mon" "$3" "${4:-0.5}"
}

osb_shot() {
    osb_hmp "$1" "$2" "screendump $1/$3.ppm" 0.8
}

osb_stop() {
    kill "$(cat "$1/$2.pid" 2>/dev/null)" 2>/dev/null; wait 2>/dev/null
    rm -f "$1/$2.img" "$1/$2.vars" "$1/$2.mon"
}

bios_prepare() {
    local dir=$1
    bash tools/bootloader/build-bios.sh "$dir/bios" > "$dir/bios-build.txt" 2>&1 || { cat "$dir/bios-build.txt"; return 1; }
    if [ -n "${STICK_IMG:-}" ]; then
        cp "$STICK_IMG" "$dir/stick.img"
    else
        OSBOOT=1 bash tools/usbimg/build.sh "$dir/build" > "$dir/build.txt" 2>&1 || { tail -5 "$dir/build.txt"; return 1; }
        mv "$dir/build/${MARKE_DATEI}-usb.img" "$dir/stick.img"
        rm -rf "$dir/build"
    fi
    if [ -n "${KERNEL:-}" ]; then
        mcopy -i "$dir/stick.img@@$OSB_OFF" -o "$KERNEL" ::osum.mb || return 1
    fi
    python3 tools/bootloader/biosinstall.py "$dir/stick.img" "$dir/bios/osboot-stage0.bin" "$dir/bios/osboot-stage2.bin" > "$dir/bios-install.txt" || return 1
    mcopy -i "$dir/stick.img@@$OSB_OFF" ::limine.conf "$dir/limine.conf" || return 1
    sed -i 's/^timeout: .*/timeout: 0/' "$dir/limine.conf"
    python3 tools/bootloader/mkcfg.py "$dir/limine.conf" "$dir/osboot.cfg" --timeout 0 > /dev/null || return 1
}

bios_bus() {
    case "$1" in
        usb) echo "-device usb-ehci -device usb-storage,drive=stick,bootindex=0" ;;
        nvme) echo "-device nvme,drive=stick,serial=osbstick,bootindex=0" ;;
        *) echo "-device ide-hd,drive=stick,bus=ide.0,bootindex=0" ;;
    esac
}

bios_start() {
    local dir=$1 name=$2 img=$3 mach=$4 bus=$5
    cp "$img" "$dir/$name.img"
    rm -f "$dir/$name.txt" "$dir/$name.mon"
    qemu-system-x86_64 "${OSB_KVM[@]}" -machine "$mach" -m 2048 -smp 2 \
        -drive "file=$dir/$name.img,format=raw,if=none,id=stick" $(bios_bus "$bus") \
        -serial "file:$dir/$name.txt" -monitor "unix:$dir/$name.mon,server,nowait" \
        -display none -no-reboot -pidfile "$dir/$name.pid" &
    local i=0
    while [ ! -S "$dir/$name.mon" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
}

bios_finish() {
    kill "$(cat "$1/$2.pid" 2>/dev/null)" 2>/dev/null; wait 2>/dev/null
    rm -f "$1/$2.img" "$1/$2.mon"
}

bios_boot() {
    local dir=$1 name=$2 img=$3 mach=$4 bus=$5 secs=$6 want=$7
    bios_start "$dir" "$name" "$img" "$mach" "$bus"
    local t0 t1
    t0=$(date +%s%N)
    osb_wait_text "$dir" "$name" "$want\|EXCEPTION" "$secs"
    t1=$(date +%s%N)
    OSB_MS=$(( (t1 - t0) / 1000000 ))
    grep -aq "$want" "$dir/$name.txt" 2>/dev/null || OSB_MS=-1
    sleep "${OSB_TAIL:-0}"
    bios_finish "$dir" "$name"
}

bios_with_cfg() {
    local dir=$1 name=$2 cfg=$3
    cp "$dir/stick.img" "$dir/$name.base"
    if [ "$cfg" = "-" ]; then
        mdel -i "$dir/$name.base@@$OSB_OFF" ::osboot.cfg 2>/dev/null
        mdel -i "$dir/$name.base@@$OSB_OFF" ::limine.conf
    else
        mcopy -i "$dir/$name.base@@$OSB_OFF" -o "$cfg" ::osboot.cfg
    fi
}
