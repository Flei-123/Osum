#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/apprights-host/run.sh -- host test of lib/apprights/{policy,conf}.fi (grant table, manifest ceiling, conf file)
# plus MUTATIONS: each mutated copy of the libs must turn tools/apprights-host/host.fi red. No QEMU, seconds.
#   bash tools/apprights-host/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

build_run() { # libdir out -> exit code of the test, output in $2.txt
    FIRNLIB="$1" vendor/firn/bin/firnc --profile=app tools/apprights-host/host.fi -o "$2" > "$2.build" 2>&1 || return 99
    "$2" > "$2.txt"
}

# 0) real libs
build_run "$PWD/lib" "$T/real"; rc=$?
if [ "$rc" = 0 ]; then ok "host test green ($(tail -1 "$T/real.txt"))"; else bad "host test rc=$rc"; grep -v '^warning' "$T/real.build" | head; grep '^FAIL' "$T/real.txt" | head; fi

# 0b) the libs build in profile kernel (no std.rt, no heap): the kernel and /bin/apprights import them
cat > "$T/kcheck.fi" <<'EOF'
profile kernel
import apprights.policy
import apprights.conf
import apprights.fspolicy
export { u_start }
fn u_start(args: u64) -> u64 {
    return policy.get_mask(args) + conf.manifest_perm(args, 0) + (fspolicy.read_ok(args, args) as u64)
}
EOF
if FIRNLIB="$PWD/lib" vendor/firn/bin/firnc --profile=kernel -c "$T/kcheck.fi" -o "$T/kcheck.o" > "$T/kcheck.build" 2>&1; then
    ok "apprights libs compile in profile kernel"
else
    bad "apprights libs do not compile in profile kernel"; grep -v '^warning' "$T/kcheck.build" | head
fi

# mutations: file | python expression pair (old -> new)
mutate() { # name file old new
    local d="$T/m_$1"
    rm -rf "$d"; mkdir -p "$d"; cp -r lib "$d/lib"
    python3 - "$d/lib/apprights/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    print("MUTATION-ANCHOR-MISSING"); sys.exit(2)
open(p, "w").write(s.replace(old, new, 1))
PY
    [ "$?" = 0 ] || { bad "mutation $1: anchor missing (the lib changed, update this script)"; return; }
    build_run "$d/lib" "$d/t"; local r=$?
    if [ "$r" = 1 ]; then ok "mutation '$1' is caught ($(grep -c '^FAIL' "$d/t.txt") red)"
    elif [ "$r" = 99 ]; then bad "mutation '$1' does not even compile"
    else bad "mutation '$1' SURVIVED (test stays green)"; fi
}
mutate allow-all policy.fi "    let app: u64 = label_app(label)
    if app == 0 {
        return true
    }
    return (get_mask(app) & bit) != 0" "    return true"
mutate no-ceiling-check policy.fi "        if ((mask & P_ALL) & (P_ALL - ceils[s as usize])) != 0 {
            return E_CEIL
        }" ""
mutate float-not-in-all policy.fi "const P_ALL: u64 = 8191" "const P_ALL: u64 = 2047"
mutate float-in-safe policy.fi "const P_SAFE: u64 = 244" "const P_SAFE: u64 = 2292"
mutate float-name-lost policy.fi "    while i < 13 {
        if eq(name, name_at(i)) {" "    while i < 11 {
        if eq(name, name_at(i)) {"
mutate hotkey-in-safe policy.fi "const P_SAFE: u64 = 244" "const P_SAFE: u64 = 4340"
mutate hotkey-name-lost policy.fi "    while i < 13 {
        if eq(name, name_at(i)) {" "    while i < 12 {
        if eq(name, name_at(i)) {"
mutate hotkey-not-in-all policy.fi "const P_ALL: u64 = 8191" "const P_ALL: u64 = 4095"
mutate ceiling-no-clamp policy.fi "    masks[s as usize] = masks[s as usize] & ceils[s as usize]" "    masks[s as usize] = masks[s as usize]"
mutate ceiling-ignored policy.fi "    return ceils[s as usize]
}

fn set_mask" "    return P_ALL
}

fn set_mask"
mutate revoke-all policy.fi "return set_mask(name, get_mask(name) & (P_ALL - (bits & P_ALL)))" "return set_mask(name, 0)"
mutate manifest-all conf.fi "ceil = ceil | (parse_rights(buf + at + 5, e - at - 5) & policy.P_ALL)" "ceil = policy.P_ALL"
mutate manifest-prefix conf.fi "&& rd(buf, at + 3) == 109 && rd(buf, at + 4) == 61" "&& rd(buf, at + 3) == 109"
mutate bad-right-kept conf.fi "if (m & BAD_RIGHT) != 0 || m == 0 {" "if m == 0 {"
mutate comment-kept conf.fi "if s < e && rd(buf, s) != 35 {" "if s < e {"
mutate update-keeps-old conf.fi "if !same_name(cur_name(), app) {" "if true {"
mutate update-no-append conf.fi "    if mask != 0 {
        n = put_line(out, n, outmax, app, mask)" "    if false {
        n = put_line(out, n, outmax, app, mask)"

mutate safe-includes-mic policy.fi "const P_SAFE: u64 = 244" "const P_SAFE: u64 = 245"
mutate safe-drops-net policy.fi "const P_SAFE: u64 = 244" "const P_SAFE: u64 = 240"
mutate auto-ignores-offered conf.fi "return safe - (safe & offered)" "return safe"
mutate auto-ignores-ceiling conf.fi "let safe: u64 = ceil & policy.P_SAFE" "let safe: u64 = policy.P_SAFE"
mutate auto-all-rights conf.fi "let safe: u64 = ceil & policy.P_SAFE" "let safe: u64 = ceil"
mutate find-first-line conf.fi "        if same_name(cur_name(), app) {
            return cur_mask()" "        if true {
            return cur_mask()"
mutate plan-no-tab conf.fi "while q < e && rd(buf, q) != 9 {" "while q < e {"
mutate acct-field-shared policy.fi "return ((&acct[0]) as u64) + (s * 4 + field) * 8" "return ((&acct[0]) as u64) + (s * 4) * 8"
mutate acct-slot-shared policy.fi "return ((&acct[0]) as u64) + (s * 4 + field) * 8" "return ((&acct[0]) as u64) + field * 8"
mutate acct-unbound-app policy.fi "    let s: u64 = app_slot(app)
    if s >= MAX_APPS {
        return 0
    }
    return ((&acct[0]) as u64)" "    var s: u64 = app_slot(app)
    if s >= MAX_APPS {
        s = 0
    }
    return ((&acct[0]) as u64)"

mutate fs-sandbox-ignored policy.fi "    if !sandboxed(name) {
        return false
    }
    return (get_mask(name) & P_FS_HOME) == 0" "    return (get_mask(name) & P_FS_HOME) == 0"
mutate fs-home-ignored policy.fi "    return (get_mask(name) & P_FS_HOME) == 0" "    return true"
mutate fs-flag-in-ceiling policy.fi "    return ceils[s as usize]
}

fn set_mask" "    return ceils[s as usize] | (sbx[s as usize] * F_SANDBOX)
}

fn set_mask"
mutate fs-read-all fspolicy.fi "    if under_data(app, path, plen) {
        return true
    }
    return tbl_match(path, plen)" "    return true"
mutate fs-write-all fspolicy.fi "    return under_data(app, path, slen(path))" "    return true"
mutate fs-name-prefix fspolicy.fi "    return rd(path, 6 + an) == 47" "    return true"
mutate fs-other-data fspolicy.fi "    var i: u64 = 0
    while i < an {
        if rd(path, 6 + i) != rd(app, i) {
            return false
        }
        i = i + 1
    }" ""
mutate fs-link-open fspolicy.fi "    return confined_app(label) == 0" "    return true"
mutate fs-prefix-loose fspolicy.fi "            if plen == n - 1 {
                cmp = n - 1
            } else if plen < n {
                same = false
            }" "            cmp = 1"
mutate fs-exact-loose fspolicy.fi "            if plen != n {
                same = false
            }" ""
mutate fs-sandbox-manifest conf.fi "            return policy.F_SANDBOX" "            return 0"
mutate fs-sandbox-trim conf.fi "while te > at && (rd(buf, te - 1) == 13 || rd(buf, te - 1) == 32) {" "while false {"
echo "APPRIGHTS-HOST: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
