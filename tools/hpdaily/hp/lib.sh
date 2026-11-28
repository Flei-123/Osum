BB=/bin/busybox
HPD_ROOT=${HPD_ROOT:-/tmp/hpdaily}
OUT=$HPD_ROOT/run
LIB=$HPD_ROOT/lib
KV=$OUT/result.kv

up_cs() {
    $BB awk '{ printf "%d", $1 * 100 }' /proc/uptime
}

kv() {
    echo "$1=$2" >> "$KV"
}

phase() {
    echo "$1" > "$OUT/phase"
    kv "phase_$1_up_cs" "$(up_cs)"
}

tok() {
    $BB awk -v key="$1" '{
        for (i = 1; i <= NF; i++) {
            n = index($i, "=")
            if (n > 0 && substr($i, 1, n - 1) == key) { print substr($i, n + 1); exit }
        }
    }'
}

tok_file() {
    tok "$1" < "$2"
}

if_rx() {
    $BB awk -v dev="$1:" '$1 == dev { print $2; found = 1 } END { if (!found) print 0 }' /proc/net/dev
}

rx_total() {
    echo $(( $(if_rx usb0) + $(if_rx wlan0) ))
}

safe_cat() {
    $BB timeout "${2:-5}" /bin/cat "$1" 2>/dev/null
}

ratio() {
    $BB awk -v a="$1" -v b="$2" 'BEGIN { if (b > 0) printf "%.2f", a / b; else print 0 }'
}

lines_of() {
    $BB wc -l < "$1" 2>/dev/null | $BB awk '{ print $1 + 0 }'
}

install_awk() {
    $BB mkdir -p "$LIB"
    for name in procs psrows cpu cputop fxsum threads; do
        emit_awk_$name > "$LIB/$name.awk"
    done
}
