lauf() {
    local img=$1 arg=$2 ser=$3
    rm -f "$ser"
    cp -f "$BAU/root.img" "$OUT/wurzel.img"
    local zblk
    zblk=$(bash tools/mkfsfi/mkfs.sh where "$OUT/wurzel.img" /etc/ziel 2>/dev/null \
        | sed -n 's/.*first=\([0-9]*\).*/\1/p')
    if [ -n "$zblk" ]; then
        printf 'kons\n\0\0' | dd of="$OUT/wurzel.img" bs=512 seek="$zblk" \
            conv=notrunc status=none
    fi
    timeout "${LIMIT:-600}" $QEMU_X86 -m "${QEMU_MEM:-512}" \
        -kernel "$BAU/osum.mb" \
        -append "osum vfs nokbd nosched noproc noring3 script=$arg;exit" \
        -serial "file:$ser" -display none -no-reboot \
        -drive "file=$OUT/wurzel.img,format=raw,if=ide,index=0" \
        -drive "file=$img,format=raw,if=ide,index=1" \
        > "$OUT/qemu.log" 2>&1
    rm -f "$OUT/wurzel.img"
    return 0
}
