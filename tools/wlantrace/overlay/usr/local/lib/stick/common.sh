. /etc/stick.conf
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
STICK_RUN=/run/stick
OUT=$STICK_RUN/out
LOG=$OUT/pipeline.log
TRACEFS=/sys/kernel/tracing
mkdir -p "$OUT"

cmdline_value() {
    local w
    for w in $(cat /proc/cmdline); do
        case $w in stick.$1=*) echo "${w#stick.$1=}" ;; esac
    done | tail -1
}

v=$(cmdline_value target)
if [ -n "$v" ]; then
    TARGET_VENDOR=0x${v%%:*}
    TARGET_DEVICE=0x${v##*:}
fi
v=$(cmdline_value modules)
[ -n "$v" ] && TARGET_MODULES=$(echo "$v" | tr ',' ' ')
v=$(cmdline_value vfio)
VFIO_MODE=${v:-auto}
v=$(cmdline_value upload)
[ -n "$v" ] && UPLOAD_HOSTS=$(echo "$v" | tr ',' ' ')
v=$(cmdline_value upload_port)
[ -n "$v" ] && UPLOAD_PORT=$v

say() {
    local line
    line="$(date +%H:%M:%S) $*"
    echo "$line" >> "$LOG"
    echo "$line" > /dev/tty1 2>/dev/null
    echo "$line" > /dev/ttyS0 2>/dev/null
    return 0
}

find_target() {
    TARGET_BDF=
    local d
    for d in /sys/bus/pci/devices/*; do
        [ -e "$d/vendor" ] || continue
        if [ "$(cat "$d/vendor")" = "$TARGET_VENDOR" ] && [ "$(cat "$d/device")" = "$TARGET_DEVICE" ]; then
            TARGET_BDF=${d##*/}
            return 0
        fi
    done
    return 1
}

pci_attr() {
    cat "/sys/bus/pci/devices/$1/$2" 2>/dev/null
}

mark() {
    echo "$*" > "$TRACEFS/trace_marker" 2>/dev/null
    return 0
}

coldplug() {
    find /sys/devices -name modalias -type f -exec cat {} + 2>/dev/null | sort -u | xargs modprobe -b -a -q 2>/dev/null
    return 0
}

wifi_iface() {
    local d
    for d in /sys/class/net/*; do
        [ -e "$d/wireless" ] && { echo "${d##*/}"; return 0; }
    done
    return 1
}
