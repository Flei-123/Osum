#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SERVICESGUEST: skipped, no qemu"; exit 0; }
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="sh ls cat echo svcproof"

boot_tree() {
    ( cd "$1" && firnenv_prepare_old_tree . >/dev/null 2>&1
      ALLTAGREBUILD=1 ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" mager=yes shot=no progs="$PROGS" \
        xfile="/svc.sh=$ROOT/tools/servicesguest/guest.sh" script="sh /svc.sh" ) > "$2.log" 2>&1
}

expect() {
    local line
    line=$(python3 -I "$ROOT/tools/servicesguest/check.py" "$1" | grep -a "^CHECK $2 " | head -1)
    case "$3:$line" in
        ok:*" ok "*) ok "$2" ;;
        fail:*" fail "*) ok "counter-probe: $2 turns red" ;;
        *) bad "$2 -- expected $3, got: ${line:-missing}" ;;
    esac
}

echo "== 1. svcosum storage + clipboard in the guest =="
boot_tree "$ROOT" "$OUT/main" || { bad "build/run failed"; tail -n 15 "$OUT/main.log"; }
S="$OUT/main/serial.txt"
[ -s "$S" ] && grep -aq "kernel: done" "$S" && ok "guest script ran to the end" || bad "guest script did not finish"
python3 -I "$ROOT/tools/servicesguest/check.py" "$S" > "$OUT/main.checks" 2>&1
while read -r _ name state note; do
    if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
done < "$OUT/main.checks"
[ "$(wc -l < "$OUT/main.checks")" -ge 31 ] && ok "all check groups reported" || bad "check groups missing"

echo
echo "== 2. COUNTER-PROBES: mutated trees =="
mutant() {
    local name=$1 file=$2 expr=$3
    shift 3
    local T="$OUT/mut-$name"
    mkdir -p "$T"
    tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$T" -xf -
    sed -i "$expr" "$T/$file"
    if cmp -s "$T/$file" "$ROOT/$file"; then bad "mutant $name: the sed expression changed nothing"; rm -rf "$T"; return; fi
    ( cd "$T" && ALLTAGREBUILD=1 ALLTAGBUILD="$OUT/mut-$name.build" bash tools/alltag/build.sh "$OUT/mut-$name-run" mager=yes shot=no progs="$PROGS" \
        xfile="/svc.sh=$ROOT/tools/servicesguest/guest.sh" script="sh /svc.sh" ) > "$OUT/mut-$name.log" 2>&1
    local MS="$OUT/mut-$name-run/serial.txt"
    [ -s "$MS" ] && ok "mutant $name booted" || { bad "mutant $name did not boot"; rm -rf "$T"; return; }
    local c
    for c in "$@"; do expect "$MS" "$c" fail; done
    rm -rf "$T" "$OUT/mut-$name.build"
}
mutant norename kernel/user/services/svcosum.fi 's/if errno.failed(io.rename(tmp, path_ptr())) {/if true {/' \
    set_new get_after_set overwrite
mutant noclip kernel/user/services/svcosum.fi 's/bits = bits | svcrules.CAP_CLIP_WRITE | svcrules.CAP_CLIP_READ/bits = bits | 0/' \
    caps_clipboard copy_ok paste_round_trip
mutant nolimit kernel/user/services/svcosum.fi 's/n > svcrules.VALUE_MAX {/n > svcrules.VALUE_MAX * 2 {/' \
    value_over_limit_rejected
mutant sharedstore kernel/user/services/svcosum.fi 's/svcrules.store_path(app_ptr(), app_len, key, key_len, path_ptr(), 160)/svcrules.store_path(app_ptr(), 5, key, key_len, path_ptr(), 160)/' \
    isolation_first_app_intact
mutant nokeyfilter kernel/user/services/svcosum.fi 's/if svcrules.valid_key(name, text.length(name)) {/if true {/' \
    keys_empty_store keys_empty_again

echo "SERVICESGUEST: $pass passed, $fail failed"
[ "$fail" = 0 ]
