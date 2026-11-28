function field(line, key,   n, i, parts) {
    n = split(line, parts, " ")
    for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2) + 0
    return -1
}
FNR == NR {
    if ($1 ~ /^cpu[0-9]+$/) { ticks1[$1] = field($0, "ticks"); idle1[$1] = field($0, "idle") }
    next
}
$1 ~ /^cpu[0-9]+$/ {
    dticks = field($0, "ticks") - ticks1[$1]
    didle = field($0, "idle") - idle1[$1]
    if (dticks > 0) printf "%s_%s_idle_pct=%d\n", prefix, $1, (100 * didle) / dticks
    else printf "%s_%s_idle_pct=-1\n", prefix, $1
}
