#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
devstones_spec() { # devstones_spec <stonesdir>: image spec words for make, tcc (+ musl headers/crt) and the git https helpers
    local S=$1 out="" d f rel
    [ -r "$S/make" ] && out="$out /bin/make=$S/make"
    [ -r "$S/strace" ] && out="$out /bin/strace=$S/strace"
    if [ -r "$S/gitexec/git-remote-http" ]; then
        out="$out /libexec/ /libexec/git-core/ /libexec/git-core/git-remote-http=$S/gitexec/git-remote-http"
        out="$out /libexec/git-core/git-remote-https@/libexec/git-core/git-remote-http"
        [ -r "$S/gitexec/git-http-fetch" ] && out="$out /libexec/git-core/git-http-fetch=$S/gitexec/git-http-fetch"
    fi
    if [ -r "$S/tcc" ] && [ -r "$S/lib/tcc/libtcc1.a" ] && [ -d "$S/include" ]; then
        out="$out /bin/tcc=$S/tcc /usr/ /usr/lib/ /usr/lib/tcc/ /usr/lib/libtcc1.a=$S/lib/tcc/libtcc1.a /usr/lib/tcc/include/ /usr/include/"
        for f in runmain.o bt-exe.o bcheck.o bcheck_run.o; do [ -r "$S/lib/tcc/$f" ] && out="$out /usr/lib/$f=$S/lib/tcc/$f"; done
        for f in "$S"/lib/tcc/include/*.h; do out="$out /usr/lib/tcc/include/$(basename "$f")=$f"; done
        for f in crt1.o crti.o crtn.o; do out="$out /usr/lib/$f=$S/lib/musl/$f"; done
        for f in c m dl pthread rt; do out="$out /usr/lib/lib$f.so->/lib/ld-musl-x86_64.so.1"; done
        while IFS= read -r d; do [ "$d" = . ] || out="$out /usr/include/${d#./}/"; done < <(cd "$S/include" && find . -type d | sort)
        while IFS= read -r f; do out="$out /usr/include/${f#./}=$S/include/${f#./}"; done < <(cd "$S/include" && find . -type f | sort)
    fi
    echo "$out"
}
