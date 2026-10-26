# SPDX-License-Identifier: GPL-2.0-only

acpi_init() {
    ROOT=$(pwd)
    D=$(mktemp -d)
    RESULTS=$D/results
    : > "$RESULTS"
    trap 'rm -rf "$D"' EXIT
    . tools/lib/qemu.sh
    export ROOT D RESULTS
    if [ -n "${ACPI_IMG:-}" ]; then
        K=$ACPI_IMG
    else
        K=$D/osum.mb
        nice -n 10 ./tools/build-kernel.sh "$K" > "$D/build.log" 2>&1 || { echo "kernel build failed"; tail -20 "$D/build.log"; exit 1; }
    fi
    KB=${ACPI_BASE_IMG:-}
    export K KB
}

chk() {
    if [ "$2" = "$3" ]; then
        printf '  ok    %s\n' "$1"; echo ok >> "$RESULTS"
    else
        printf '  FAIL  %s: want <%s> got <%s>\n' "$1" "$2" "$3"; echo fail >> "$RESULTS"
    fi
}

chk_ge() {
    if [ -n "$3" ] && [ "$3" -ge "$2" ] 2>/dev/null; then
        printf '  ok    %s (%s)\n' "$1" "$3"; echo ok >> "$RESULTS"
    else
        printf '  FAIL  %s: want >= %s got <%s>\n' "$1" "$2" "$3"; echo fail >> "$RESULTS"
    fi
}

chk_le() {
    if [ -n "$3" ] && [ "$3" -le "$2" ] 2>/dev/null; then
        printf '  ok    %s (%s)\n' "$1" "$3"; echo ok >> "$RESULTS"
    else
        printf '  FAIL  %s: want <= %s got <%s>\n' "$1" "$2" "$3"; echo fail >> "$RESULTS"
    fi
}

has() {
    grep -aqE -- "$2" "$D/$1.txt" 2>/dev/null && echo 1 || echo 0
}

count() {
    grep -acE -- "$2" "$D/$1.txt" 2>/dev/null || true
}

line() {
    grep -aE -m1 -- "$2" "$D/$1.txt" 2>/dev/null | tr -d '\r\000'
}

val() {
    echo "$1" | grep -oE -- "(^| )$2=[^ ]*" | head -1 | sed 's/^ //; s/^[^=]*=//'
}

qrun() {
    local kernel=$1 name=$2 append=$3
    shift 3
    rm -f "$D/$name.txt" "$D/$name.rc"
    timeout "${ACPI_TIMEOUT:-120}" $QEMU_X86 -kernel "$kernel" -m "${ACPI_MEM:-256}" -append "$append" \
        -serial "file:$D/$name.txt" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $? > "$D/$name.rc"
}

qstart() {
    local kernel=$1 name=$2 append=$3
    shift 3
    rm -f "$D/$name.txt" "$D/$name.rc" "$D/$name.mon"
    timeout "${ACPI_TIMEOUT:-120}" $QEMU_X86 -kernel "$kernel" -m "${ACPI_MEM:-256}" -append "$append" \
        -serial "file:$D/$name.txt" -display none -no-reboot \
        -monitor "unix:$D/$name.mon,server,nowait" "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    eval "QPID_$name=$!"
}

qwaitfor() {
    local name=$1 pattern=$2 tries=${3:-300} pid
    eval "pid=\$QPID_$name"
    for _ in $(seq 1 "$tries"); do
        grep -aqE -- "$pattern" "$D/$name.txt" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.1
    done
    return 1
}

qmon() {
    local name=$1
    shift
    printf '%s\n' "$*" | timeout 10 socat - "unix-connect:$D/$name.mon" > /dev/null 2>&1
}

qfinish() {
    local name=$1 pid
    eval "pid=\$QPID_$name"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 0
}

qwaitexit() {
    local name=$1 tries=${2:-300} pid
    eval "pid=\$QPID_$name"
    for _ in $(seq 1 "$tries"); do
        kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null; echo $? > "$D/$name.rc"; return 0; }
        sleep 0.1
    done
    return 1
}

asl_build() {
    local src=$1 out=$2
    iasl -p "$out" "$src" > /dev/null 2>&1 && [ -f "$out.aml" ]
}

acpi_summary() {
    local ok fail
    ok=$(grep -c '^ok' "$RESULTS" || true)
    fail=$(grep -c '^fail' "$RESULTS" || true)
    echo
    echo "acpi: $ok ok, $fail fail"
    [ "$fail" -eq 0 ]
}

lastline() {
    grep -aE -- "$2" "$D/$1.txt" 2>/dev/null | tail -1 | tr -d '\r\000'
}

lines_of() {
    grep -aE -- "$2" "$D/$1.txt" 2>/dev/null | tr -d '\r\000'
}

tool() {
    python3 -I "tools/acpi/$@"
}
