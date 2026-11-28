FX_LOG=/var/log/xfx.log
FX_POLL_S=2

fx_status() {
    $BB timeout 15 /bin/xfx status 2>&1
}

fx_root_pid() {
    fx_status | tok pid
}

fx_running() {
    case "$(fx_status)" in
        *firefox=running*) return 0 ;;
    esac
    return 1
}

proc_ticks() {
    /bin/ps 2>/dev/null | $BB awk -v name="$1" '$NF == name { sum += $6 } END { print sum + 0 }'
}

fx_snapshot() {
    $BB cat /proc/[0-9]*/status 2>/dev/null | $BB awk -f "$LIB/procs.awk" > "$OUT/procs.txt"
    $BB awk -v root="${1:-0}" -v wayd_pid="$($BB pgrep -o wayd)" -v members="$OUT/members.txt" -f "$LIB/fxsum.awk" "$OUT/procs.txt"
}

fx_stop() {
    phase fx_stop
    if fx_running; then
        kv ff_initial_running 1
        $BB timeout 40 /bin/xfx stop > "$OUT/xfx_stop.log" 2>&1
        local waited=0
        while fx_running && [ "$waited" -lt 30 ]; do
            $BB sleep 1
            waited=$(( waited + 1 ))
        done
        kv ff_stop_wait_s "$waited"
    else
        kv ff_initial_running 0
    fi
}

fx_stop_if_running() {
    local waited=0
    fx_running || return 0
    $BB timeout 40 /bin/xfx stop > "$OUT/xfx_stop_reload.log" 2>&1
    while fx_running && [ "$waited" -lt 30 ]; do
        $BB sleep 1
        waited=$(( waited + 1 ))
    done
}

fx_wait_ready() {
    local mark=$1 limit=${2:-60} waited=0
    while [ "$waited" -lt "$limit" ]; do
        if [ "$($BB tail -c +$(( mark + 1 )) "$FX_LOG" 2>/dev/null | $BB grep -c 'wayd: ready on')" -gt 0 ]; then
            echo "$waited"
            return 0
        fi
        $BB sleep 1
        waited=$(( waited + 1 ))
    done
    echo -1
    return 1
}

fx_dump_threads() {
    local label=$1 pid tid n=0
    : > "$OUT/threads.raw"
    for pid in $($BB cat "$OUT/members.txt" 2>/dev/null); do
        for tid in /proc/$pid/task/*; do
            [ -e "$tid/status" ] && echo "$tid/status"
        done
    done > "$OUT/thread_paths.txt"
    $BB xargs $BB cat < "$OUT/thread_paths.txt" 2>/dev/null | $BB awk -f "$LIB/threads.awk" > "$OUT/threads.raw"
    kv "ff_${label}_threads_total" "$(lines_of "$OUT/threads.raw")"
    kv "ff_${label}_threads_running" "$($BB awk '$2 != "S" { n++ } END { print n + 0 }' "$OUT/threads.raw")"
    kv "ff_${label}_threads_with_syscall" "$($BB awk '$5 != "-" { n++ } END { print n + 0 }' "$OUT/threads.raw")"
    $BB awk '$2 != "S" || $5 != "-"' "$OUT/threads.raw" | $BB sort -k3,3nr | $BB head -40 \
        | $BB awk -v l="$label" '{ printf "thread_%s_%d=%s\n", l, NR, $0 }' >> "$KV"
}

fx_load() {
    local label=$1 url=$2 deadline=${3:-120}
    phase "ff_$label"
    echo "$url" > /etc/xfx.url
    local mark rx0 t0 ready_s
    fx_stop_if_running
    mark=$($BB wc -c < "$FX_LOG" 2>/dev/null | $BB awk '{ print $1 + 0 }')
    rx0=$(rx_total)
    t0=$(up_cs)
    ( /bin/xfx start > "$OUT/xfx_start_$label.log" 2>&1 < /dev/null & )
    $BB sleep 2
    if $BB grep -q 'no desktop session' "$OUT/xfx_start_$label.log" 2>/dev/null; then
        kv "ff_${label}_url" "$url"
        kv "ff_${label}_state" no_session
        return 0
    fi
    ready_s=$(fx_wait_ready "$mark" 60)
    kv "ff_${label}_url" "$url"
    kv "ff_${label}_wayd_ready_s" "$ready_s"
    local root
    root=$(fx_root_pid)
    kv "ff_${label}_root_pid" "${root:-0}"
    local prev=-1 quiet=0 settle_s=-1 elapsed=0 sample ticks rxd
    : > "$OUT/ff_$label.timeline"
    while [ "$elapsed" -lt "$deadline" ]; do
        $BB sleep "$FX_POLL_S"
        elapsed=$(( ( $(up_cs) - t0 ) / 100 ))
        sample=$(fx_snapshot "${root:-0}")
        ticks=$(echo "$sample" | tok fx_ticks)
        rxd=$(( $(rx_total) - rx0 ))
        echo "$elapsed $ticks $rxd $(echo "$sample" | tok alive)" >> "$OUT/ff_$label.timeline"
        if [ "$prev" -ge 0 ] && [ $(( ticks - prev )) -le "${FX_SETTLE_TICKS:-40}" ] && [ "$rxd" -ge "${FX_MIN_RX_BYTES:-4096}" ]; then
            quiet=$(( quiet + 1 ))
        else
            quiet=0
        fi
        prev=$ticks
        if [ "$quiet" -ge 2 ]; then
            settle_s=$elapsed
            break
        fi
    done
    sample=$(fx_snapshot "${root:-0}")
    kv "ff_${label}_settle_s" "$settle_s"
    kv "ff_${label}_elapsed_s" "$elapsed"
    kv "ff_${label}_rx_bytes" "$(( $(rx_total) - rx0 ))"
    kv "ff_${label}_alive" "$(echo "$sample" | tok alive)"
    kv "ff_${label}_procs" "$(echo "$sample" | tok fx_procs)"
    kv "ff_${label}_threads" "$(echo "$sample" | tok fx_threads)"
    kv "ff_${label}_ticks" "$(echo "$sample" | tok fx_ticks)"
    kv "ff_${label}_rss_kb" "$(echo "$sample" | tok fx_rss_kb)"
    kv "ff_${label}_wayd_ticks" "$(proc_ticks wayd)"
    kv "ff_${label}_xremoted_ticks" "$(proc_ticks xremoted)"
    kv "ff_${label}_state" "$(fx_verdict "$settle_s" "$(echo "$sample" | tok alive)" "$(( $(rx_total) - rx0 ))" "$ready_s")"
    fx_dump_threads "$label"
}

fx_verdict() {
    if [ "$4" -lt 0 ]; then echo no_window; return; fi
    if [ "$2" != "1" ]; then echo crashed; return; fi
    if [ "$1" -ge 0 ]; then echo settled; return; fi
    if [ "$3" -lt "${FX_MIN_RX_BYTES:-4096}" ]; then echo stalled_no_network; return; fi
    echo busy_not_settled
}

fx_restore() {
    [ -f "$OUT/xfx.url.orig" ] && $BB cp "$OUT/xfx.url.orig" /etc/xfx.url
    [ -f "$OUT/xfx.env.orig" ] && $BB cp "$OUT/xfx.env.orig" /etc/xfx.env
}

fx_prepare() {
    $BB cp /etc/xfx.url "$OUT/xfx.url.orig" 2>/dev/null
    if [ -f /etc/xfx.env ]; then
        $BB cp /etc/xfx.env "$OUT/xfx.env.orig"
        kv ff_debug_env "$($BB head -c 120 /etc/xfx.env | $BB tr '\n' ';')"
        : > /etc/xfx.env
    fi
}
