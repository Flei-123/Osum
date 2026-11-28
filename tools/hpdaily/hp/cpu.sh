CPU_TOP_COUNT=8

cpu_proc_snapshot() {
    $BB timeout 10 /bin/ps 2>/dev/null | $BB awk -f "$LIB/psrows.awk" > "$1"
}

cpu_top_report() {
    local label=$1
    $BB awk -f "$LIB/cputop.awk" "$OUT/top1.txt" "$OUT/top2.txt" | $BB sort -rn | $BB head -n "$CPU_TOP_COUNT" \
        | $BB awk -v prefix="cputop_$label" '{ printf "%s_%d=%s ticks pid=%s rss_kb=%s name=%s\n", prefix, NR, $1, $2, $3, $4 }' >> "$KV"
}

phase_cpu() {
    local label=$1 seconds=${2:-10}
    phase "cpu_$label"
    safe_cat /proc/cpus > "$OUT/cpu1.txt"
    cpu_proc_snapshot "$OUT/top1.txt"
    $BB sleep "$seconds"
    safe_cat /proc/cpus > "$OUT/cpu2.txt"
    cpu_proc_snapshot "$OUT/top2.txt"
    $BB awk -v prefix="cpu_$label" -f "$LIB/cpu.awk" "$OUT/cpu1.txt" "$OUT/cpu2.txt" >> "$KV"
    cpu_top_report "$label"
    kv "cpu_${label}_busy_ticks_total" "$($BB awk -f "$LIB/cputop.awk" "$OUT/top1.txt" "$OUT/top2.txt" | $BB awk '{ sum += $1 } END { print sum + 0 }')"
    kv "cpu_${label}_window_s" "$seconds"
    kv "ram_${label}_free_kb" "$(safe_cat /proc/meminfo | $BB awk '$1 == "MemFree:" { print $2 }')"
}
