#!/usr/bin/env bash

# up_profile <wurzeldatei> -> druckt "app" oder "kernel"
up_profile() {
    if grep -qa '^profile app' "$1" 2>/dev/null; then
        printf 'app\n'
    else
        printf 'kernel\n'
    fi
}

# up_build <cc> <prog> <obj> <elf> <crt> <uld> <stufe> [err]
up_build() {
    local cc="$1" prog="$2" obj="$3" elf="$4" crt="$5" uld="$6" stufe="$7"
    local err="${8:-$3.err}"
    local src="kernel/user/$prog.fi"
    local prof="" usecrt="$crt"

    [ -f "$src" ] || { echo "up_build: $src fehlt" > "$err"; return 1; }

    if [ "$(up_profile "$src")" = app ]; then
        prof="--profile=app"
        usecrt=""
    fi

    # shellcheck disable=SC2086
    "$cc" $prof -c "$src" -o "$obj" > "$err" 2>&1 || return 1
    ld -T "$uld" --defsym=USER_ENTRY="_F$stufe.u_start" \
        -o "$elf" $usecrt "$obj" >> "$err" 2>&1 || return 1
    strip --strip-all "$elf" 2>/dev/null
    return 0
}
