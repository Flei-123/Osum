{
    pid = $1; ppid[pid] = $2; ticks[pid] = $3; threads[pid] = $4; rss[pid] = $5
    name = $6; for (i = 7; i <= NF; i++) name = name " " $i
    comm[pid] = name
    order[++count] = pid
}
END {
    if (root == 0 || !(root in comm)) {
        root = 0
        for (i = 1; i <= count; i++) {
            p = order[i]
            if (comm[p] == "firefox" && comm[ppid[p]] != "firefox") { root = p; break }
        }
    }
    inset[root] = 1
    changed = 1
    while (changed) {
        changed = 0
        for (i = 1; i <= count; i++) {
            p = order[i]
            if (!(p in inset) && (ppid[p] in inset)) { inset[p] = 1; changed = 1 }
        }
    }
    for (i = 1; i <= count; i++) {
        p = order[i]
        if (p in inset) { fx_ticks += ticks[p]; fx_rss += rss[p]; fx_procs++; fx_threads += threads[p] }
        if (comm[p] == "wayd") wayd_ticks += ticks[p]
        if (comm[p] == "xremoted") xr_ticks += ticks[p]
    }
    printf "root=%d alive=%d fx_ticks=%d fx_rss_kb=%d fx_procs=%d fx_threads=%d wayd_ticks=%d xremoted_ticks=%d\n", root, (root in comm), fx_ticks, fx_rss, fx_procs, fx_threads, wayd_ticks, xr_ticks
    if (members != "" && root > 0) for (p in inset) print p > members
}
