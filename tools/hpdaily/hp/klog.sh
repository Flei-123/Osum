KLOG_PATTERN='panic|#DF|double fault|#GP|#UD|#PF|BUG:|oops|NMI|hang|stall|freeze|integer overflow'

klog_mark() {
    kv klog_lines_start "$(lines_of /var/log/klog)"
}

phase_klog() {
    phase klog
    local start=$1 total
    total=$(lines_of /var/log/klog)
    kv klog_lines_end "$total"
    if [ "$total" -lt "$start" ]; then
        kv klog_rotated 1
        start=0
    fi
    $BB tail -n +$(( start + 1 )) /var/log/klog 2>/dev/null > "$OUT/klog.new"
    kv klog_new_lines "$(lines_of "$OUT/klog.new")"
    kv klog_new_bad "$($BB grep -E -i -c "$KLOG_PATTERN" "$OUT/klog.new")"
    kv klog_total_bad "$($BB grep -E -i -c "$KLOG_PATTERN" /var/log/klog)"
    $BB grep -E -i "$KLOG_PATTERN" "$OUT/klog.new" | $BB head -8 | $BB awk '{ printf "klog_hit_%d=%s\n", NR, substr($0, 1, 160) }' >> "$KV"
    kv crash_files_end "$($BB ls /var/crash 2>/dev/null | $BB wc -l | $BB awk '{ print $1 }')"
    kv uptime_end_s "$($BB awk '{ print int($1) }' /proc/uptime)"
}
