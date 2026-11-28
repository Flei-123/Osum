/^Name:/ { emit(); name = $0; sub(/^Name:[ \t]*/, "", name) }
/^Pid:/ { tid = $2 }
/^State:/ { state = $2 }
/^Ticks:/ { ticks = $2 }
/^Runs:/ { runs = $2 }
/^Syscall:/ { syscall = $0; sub(/^Syscall:[ \t]*/, "", syscall); gsub(/[ \t]+/, "_", syscall) }
function emit() {
    if (tid != "") printf "%s %s %d %s %s %s\n", tid, state, ticks, runs, (syscall == "" ? "-" : syscall), name
    tid = ""; state = ""; ticks = 0; runs = 0; syscall = ""; name = ""
}
END { emit() }
