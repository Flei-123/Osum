#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/smb/url.sh -- host gate for lib/smb/url.fi (smb:// paths and listing lines) with counter-proofs.
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

build() { # <libdir> <out>
    FIRNLIB="$1" $FIRNC tools/smb/urltest.fi -o "$2" 2> "$D/cc.err"
}
mkdir -p "$D/good/smb"; cp lib/smb/url.fi "$D/good/smb/"
build "$D/good" "$D/ut" && ok "urltest builds" || { bad "urltest build"; head -5 "$D/cc.err"; echo "SMBURL: $pass ok, $fail FAIL"; exit 1; }

cases() { # <binary> -> prints "cmd|arg|result" lines
    local ut=$1
    while IFS='|' read -r c a; do printf '%s|%s|%s\n' "$c" "$a" "$($ut "$c" "$a")"; done <<'CASES'
l|/data
l|smb://
l|smb://h
l|smb://h/
l|smb://h/s
l|smb://h/s/x/y
h|smb://srv
h|smb://srv:4455/s
h|smb://srv:44x5/s
h|smb:///s
s|smb://h/data/a/b
s|smb://h
r|smb://h/data/a/b/
r|smb://h/data
p|smb://h/data/a/b
p|smb://h/data/a
p|smb://h/data
p|smb://h/data/
p|smb://h
p|smb://h/
p|/data
L|d 12 sub dir
L|- 0 a.txt
L|- 123456789012 big file.bin
L|d x bad
L|x 1 bad
L|- 5 
S|d data	Disk
S|d data
S|d hidden$	Disk
S|p printer	Printer
S|i IPC$	IPC
CASES
}
declare -A WANT=(
 ['l|/data']=0 ['l|smb://']=1 ['l|smb://h']=1 ['l|smb://h/']=1 ['l|smb://h/s']=2 ['l|smb://h/s/x/y']=2
 ['h|smb://srv']="srv 0" ['h|smb://srv:4455/s']="srv 4455" ['h|smb://srv:44x5/s']="srv 0" ['h|smb:///s']="! 0"
 ['s|smb://h/data/a/b']=data ['s|smb://h']='!'
 ['r|smb://h/data/a/b/']=a/b ['r|smb://h/data']=''
 ['p|smb://h/data/a/b']=smb://h/data/a ['p|smb://h/data/a']=smb://h/data ['p|smb://h/data']=smb://h ['p|smb://h/data/']=smb://h
 ['p|smb://h']=/ ['p|smb://h/']=/ ['p|/data']='!'
 ['L|d 12 sub dir']="1 12 sub dir" ['L|- 0 a.txt']="2 0 a.txt" ['L|- 123456789012 big file.bin']="2 123456789012 big file.bin"
 ['L|d x bad']='!' ['L|x 1 bad']='!' ['L|- 5 ']='!'
 ['S|d data	Disk']="1 0 data" ['S|d data']="1 0 data" ['S|d hidden$	Disk']='!' ['S|p printer	Printer']='!' ['S|i IPC$	IPC']='!'
)
check_all() { # <binary> <label> -> number of wrong cases
    local wrong=0 line key got
    while IFS= read -r line; do
        key=${line%|*}; got=${line##*|}
        [ "$got" = "${WANT[$key]}" ] || { wrong=$((wrong+1)); [ "$2" = real ] && printf '    wrong: %s -> %s (want %s)\n' "$key" "$got" "${WANT[$key]}"; }
    done < <(cases "$1")
    echo "$wrong"
}
w=$(check_all "$D/ut" real)
[ "$w" = 0 ] && ok "all ${#WANT[@]} url and listing cases match" || bad "$w of ${#WANT[@]} cases wrong"

mutant() { # <name> <sed expr>
    mkdir -p "$D/m_$1/smb"; sed "$2" lib/smb/url.fi > "$D/m_$1/smb/url.fi"
    cmp -s lib/smb/url.fi "$D/m_$1/smb/url.fi" && { bad "mutant $1 did not change the source"; return; }
    build "$D/m_$1" "$D/ut_$1" || { bad "mutant $1 does not build"; return; }
    local mw; mw=$(check_all "$D/ut_$1" quiet)
    [ "$mw" -gt 0 ] && ok "counter-proof $1: $mw cases turn red" || bad "counter-proof $1 stayed green"
}
mutant prefix 's/PREFIX: \[u8; 7\] = "smb:\/\/\\0"/PREFIX: [u8; 7] = "smc:\/\/\\0"/'
mutant parent 's/n = n - 1\n    }\n    rt.st8(p, n/&/;s/if n > auth + 1 {/if n > auth + 9 {/'
mutant hidden 's/byte(p, e - 1) == 36 as u8/byte(p, e - 1) == 35 as u8/'
mutant port 's/c > 57 as u8/c > 200 as u8/'
mutant kind 's/k == 45 as u8/k == 46 as u8/'
echo "SMBURL: $pass ok, $fail FAIL"
[ "$fail" = 0 ]
