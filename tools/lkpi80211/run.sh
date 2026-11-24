#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "OK    $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }
host() { FIRNLIB="$1" "$FIRNC" --profile=app tools/lkpi80211/host.fi -o "$2" > "$2.build" 2>&1; }
if FIRNLIB="$PWD/lib" "$FIRNC" --profile=kernel -c tools/lkpi80211/kcheck.fi -o "$T/kcheck.o" > "$T/kcheck.build" 2>&1; then
    ok "wlan.macplan compiles in profile kernel"
else
    bad "wlan.macplan does not compile in profile kernel"; grep -v '^warning' "$T/kcheck.build" | head -10
fi
if host "$PWD/lib" "$T/host"; then
    "$T/host" > "$T/host.out"; rc=$?
    grep '^FAIL' "$T/host.out" | head -10
    [ "$rc" = 0 ] && ok "host sequences: $(grep '^checks=' "$T/host.out")" || bad "host sequences: $(grep '^checks=' "$T/host.out")"
else
    bad "host build"; grep -v '^warning' "$T/host.build" | head -10
fi
mutant() {
    local name=$1 from=$2 to=$3 lib="$T/m-$1"
    mkdir -p "$lib"; cp -rs "$PWD/lib/." "$lib/"
    rm "$lib/wlan/macplan.fi"
    python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert sys.argv[2] in s; open(sys.argv[4],"w").write(s.replace(sys.argv[2], sys.argv[3], 1))' \
        lib/wlan/macplan.fi "$from" "$to" "$lib/wlan/macplan.fi" || { bad "mutant $name: pattern missing"; return; }
    if host "$lib" "$T/host-$name" && ! "$T/host-$name" > "$T/host-$name.out" 2>&1; then
        ok "mutant $name rejected ($(grep -c '^FAIL' "$T/host-$name.out") checks red)"
    else
        bad "mutant $name not rejected"
    fi
}
mutant jump "        (*p).sta = (*p).sta - 1" "        (*p).sta = target"
mutant keepkeys "    drop_keys(p)" "    (*p).n = (*p).n"
mutant nochanctx "    emit(p, OP_ADD_CHANCTX, 0)" "    (*p).n = (*p).n"
mutant openauth "        if (*p).rsn && !(*p).ptk { return false }" "        (*p).n = (*p).n"
. compat/linuxkpi/flags.sh
. compat/linuxkpi/wifibuild.sh
SHIM=compat/linuxkpi/shim
lkpi_fetch_headers wifi "$T/hdr" && ok "fetch: wifi protocol headers from the pinned tarball, file set sha256 verified" || bad "fetch: wifi protocol headers"
if FIRNLIB="$PWD/lib" "$FIRNC" --profile=app tools/lkpi80211/dump.fi -o "$T/dump" > "$T/dump.build" 2>&1 && "$T/dump" > "$T/ops.txt"; then
    ok "planner dump: $(wc -l < "$T/ops.txt") events"
else
    bad "planner dump"; grep -v '^warning' "$T/dump.build" | head -10
fi
if build_wifi "$SHIM" "$T/wifi" > "$T/wifi.build" 2>&1; then
    ok "wifi shim and fake driver harness build"
    "$T/wifi" < "$T/ops.txt" > "$T/wifi.out"; rc=$?
    grep '^FAIL' "$T/wifi.out" | head -10
    [ "$rc" = 0 ] && ok "fake mac80211 driver: $(grep '^checks=' "$T/wifi.out") $(grep '^applied=' "$T/wifi.out") $(grep '^failures=' "$T/wifi.out")" || bad "fake mac80211 driver run"
else
    bad "wifi build"; head -10 "$T/wifi.build"
fi
if build_wifi_rt "$SHIM" "$T/rt" > "$T/rt.build" 2>&1; then
    "$T/rt" > "$T/rt.out"; rc=$?
    grep '^FAIL' "$T/rt.out" | head -10
    [ "$rc" = 0 ] && ok "shim runtime (dma, pages, work, timers, napi, skb): $(grep '^checks=' "$T/rt.out") $(grep '^failures=' "$T/rt.out")" || bad "shim runtime run"
else
    bad "shim runtime build"; head -10 "$T/rt.build"
fi
rtmutant() {
    local name=$1 file=$2 from=$3 to=$4 m="$T/rm-$1"
    rm -rf "$m"; cp -r "$SHIM" "$m"
    python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert sys.argv[2] in s; open(sys.argv[1],"w").write(s.replace(sys.argv[2], sys.argv[3], 1))' \
        "$m/$file" "$from" "$to" || { bad "runtime mutant $name: pattern missing"; return; }
    if build_wifi_rt "$m" "$T/rtm-$name" > "$T/rtm-$name.build" 2>&1 && ! "$T/rtm-$name" > "$T/rtm-$name.out" 2>&1; then
        ok "runtime mutant $name rejected ($(grep -c '^FAIL' "$T/rtm-$name.out") checks red)"
    else
        bad "runtime mutant $name not rejected"
    fi
}
rtmutant delayearly src/wifi_sched.c "if (time_after(timer->expires, now))" "if (0)"
rtmutant napioff src/wifi_net.c "if (!(napi->state & LKPI_NAPI_ENABLED) || (napi->state & LKPI_NAPI_SCHEDULED))" "if (napi->state & LKPI_NAPI_SCHEDULED)"
rtmutant skbdirty src/wifi_skb.c "skb->in_use = 1;" "skb->in_use = 1; skb->shinfo.nr_frags = 1;"
rtmutant dmaerr src/wifi_mem.c "return addr == DMA_MAPPING_ERROR;" "return 0;"
python3 -I tools/lkpi80211/synccheck.py "$SHIM/include/osum/macplan_ops.h" lib/wlan/macplan.fi > "$T/sync.out" 2>&1 && ok "macplan op numbers in the shim header equal lib/wlan/macplan.fi" || { bad "op numbers differ"; head -5 "$T/sync.out"; }
wmutant() {
    local name=$1 file=$2 from=$3 to=$4 m="$T/wm-$1"
    rm -rf "$m"; cp -r "$SHIM" "$m"
    python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert sys.argv[2] in s; open(sys.argv[1],"w").write(s.replace(sys.argv[2], sys.argv[3], 1))' \
        "$m/src/$file" "$from" "$to" || { bad "shim mutant $name: pattern missing"; return; }
    if build_wifi "$m" "$m/wifi" > "$m/build.txt" 2>&1 && ! "$m/wifi" < "$T/ops.txt" > "$m/out.txt" 2>&1; then
        ok "shim mutant $name rejected ($(grep -c '^FAIL' "$m/out.txt") checks red)"
    else
        bad "shim mutant $name not rejected"
    fi
}
wmutant stepskip wifi_dispatch.c "if (arg != old + 1 && arg + 1 != old)" "if (0)"
wmutant keymap wifi_dispatch.c "arg == MACPLAN_KEY_SET_PAIRWISE || arg == MACPLAN_KEY_DEL_PAIRWISE;" "arg == MACPLAN_KEY_SET_PAIRWISE;"
wmutant qosmap wifi_dispatch.c "changed = BSS_CHANGED_QOS;" "changed = BSS_CHANGED_BSSID;"
wmutant assocflag wifi_dispatch.c "cfg.assoc = w->state.sta_state >= IEEE80211_STA_ASSOC;" "cfg.assoc = 1;"
wmutant acdrop wifi_dispatch.c "0, arg, &params);" "0, 0, &params);"
wmutant skbleak wifi_skb.c "	live--;
	for (i = 0;" "	for (i = 0;"
wmutant doublefree wifi_skb.c "if (!skb->in_use || skb->magic != SKB_MAGIC_LIVE) {" "if (0) {"
wmutant scanguard wifi_upcall.c "if (!w->state.scanning)
		return;" "if (0)
		return;"
wmutant chanorder wifi_dispatch.c "if (!w->state.assigned || w->state.sta_state != IEEE80211_STA_NOTEXIST)" "if (!w->state.assigned)"
echo "LKPI80211: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
