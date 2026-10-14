#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/power/run.sh -- L-005/L-006/L-007: laptop power policy (lid action, battery/mains item, idle timers).
#   bash tools/power/run.sh
# 1) policy + tray item on the build host (tools/power/host.fi: lid action per power source, edges, standby timer
#    scaled to seconds, battery % / mains states, tooltips)  2) compile checks: lib/power/policy.fi and
#    lib/fui/traypower.fi in profile kernel, /bin/powerd in profile kernel  3) schema + conf keys agree
#    4) the new kernel entries exist (PS_BLANKAFTER, PS_INJECT, acpiev.inject)
# NOT HERE (open, see report): the QEMU run with the fake laptop (laptop.asl + `powerd inject`) and S3 on lid close.
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
FC="vendor/firn/bin/firnc"
echo "== 1. host test =="
if FIRNLIB="$PWD/lib" $FC --profile=app tools/power/host.fi -o "$T/host" > "$T/host.build" 2>&1; then
    "$T/host" > "$T/host.out"; hrc=$?
    grep '^FAIL' "$T/host.out" | head -20
    n=$(grep -c '^ok' "$T/host.out")
    [ "$hrc" = 0 ] && ok "host.fi: $(tail -1 "$T/host.out")" || bad "host.fi: $(tail -1 "$T/host.out")"
    [ "$n" -ge 28 ] && ok "at least 28 checks ran ($n)" || bad "only $n checks ran"
else
    bad "host.fi does not build"; grep -v '^warning' "$T/host.build" | head -20
fi
echo "== 2. kernel-profile compile checks =="
for f in lib/power/policy.fi lib/fui/traypower.fi kernel/user/powerd.fi; do
    printf 'profile kernel\n' > "$T/k.fi"
    case $f in
      lib/power/policy.fi) printf 'import power.policy\nexport { probe }\nfn probe() -> u64 {\n    var c: policy.Conf = policy.conf_default()\n    return policy.lid_action(&c, true)\n}\n' >> "$T/k.fi"; src="$T/k.fi";;
      lib/fui/traypower.fi) printf 'import fui.traypower\nexport { probe }\nfn probe() -> u64 {\n    return traypower.state(1, 50, 0, 1)\n}\n' >> "$T/k.fi"; src="$T/k.fi";;
      *) src=$f;;
    esac
    if FIRNLIB="$PWD/lib" $FC --profile=kernel -c "$src" -o "$T/o.o" > "$T/o.err" 2>&1; then ok "$f compiles in profile kernel"
    else bad "$f does not compile in profile kernel"; grep -v '^warning' "$T/o.err" | head -10; fi
done
echo "== 3. schema, conf keys, image =="
for k in lid_bat lid_ac screen_bat screen_ac standby_bat standby_ac profile_bat profile_ac; do
    grep -q "store /etc/power.conf $k\$" etc/settings.schema && grep -q "k_[a-z_]*: \[u8; [0-9]*\] = \"$k" lib/power/policy.fi \
        && ok "key $k: in the schema and read by policy.fi" || bad "key $k: schema and policy.fi disagree"
done
grep -q 'powerd' tools/usbimg/build.sh && ok "powerd is in the image program list" || bad "powerd missing in tools/usbimg/build.sh"
grep -q '/bin/powerd' kernel/user/glogin.fi && ok "glogin starts powerd" || bad "glogin does not start powerd"
echo "== 4. kernel entries =="
grep -qa 'const PS_BLANKAFTER' kernel/sys/sys.fi && grep -qa 'fn set_blank_after' kernel/pwr/pwr.fi && ok "PS_BLANKAFTER / pwr.set_blank_after" || bad "PS_BLANKAFTER missing"
grep -qa 'const PS_INJECT' kernel/sys/sys.fi && grep -q 'fn inject' kernel/acpi/acpiev.fi && ok "PS_INJECT / acpiev.inject" || bad "PS_INJECT missing"
echo
echo "POWER: $pass passed, $fail failed"
[ "$fail" = 0 ]
