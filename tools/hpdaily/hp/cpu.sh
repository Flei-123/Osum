phase_cpu() {
    local label=$1 seconds=${2:-10}
    phase "cpu_$label"
    safe_cat /proc/cpus > "$OUT/cpu1.txt"
    $BB sleep "$seconds"
    safe_cat /proc/cpus > "$OUT/cpu2.txt"
    $BB awk -v prefix="cpu_$label" -f "$LIB/cpu.awk" "$OUT/cpu1.txt" "$OUT/cpu2.txt" >> "$KV"
    kv "cpu_${label}_window_s" "$seconds"
    kv "ram_${label}_free_kb" "$(safe_cat /proc/meminfo | $BB awk '$1 == "MemFree:" { print $2 }')"
}
