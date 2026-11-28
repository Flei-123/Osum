NR > 1 && $4 != "idle" {
    pid = substr($0, 1, 5) + 0
    for (i = 1; i <= NF; i++) if ($i == "real") { ticks = $(i - 1); name = $(i + 1) }
    if (name == "-") name = "kernel_task"
    print pid, 0, ticks, 0, 0, name
}
