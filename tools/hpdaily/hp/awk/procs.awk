/^Name:/ { emit(); name = $0; sub(/^Name:[ \t]*/, "", name) }
/^Pid:/ { pid = $2 }
/^PPid:/ { ppid = $2 }
/^Ticks:/ { ticks = $2 }
/^Threads:/ { threads = $0; sub(/^Threads:[ \t]*/, "", threads) }
/^VmRSS:/ { rss = $2 }
function emit() {
    if (pid != "") printf "%s %s %s %s %s %s\n", pid, ppid, ticks, threads, rss, name
    pid = ""; ppid = 0; ticks = 0; threads = 0; rss = 0; name = ""
}
END { emit() }
