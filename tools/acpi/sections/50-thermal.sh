# SPDX-License-Identifier: GPL-2.0-only
asl_build tools/acpi/asl/thermal.asl "$D/thermal" || { printf '  FAIL  thermal ssdt build\n'; echo fail >> "$RESULTS"; exit 0; }
TAB=(-acpitable "file=$D/thermal.aml")
BASE="osum acpiev evself evwait noring3 nofs thermsim"
ZA='_TZ\.TZA0'
ZB='_SB\.TZB0'
ZC='_SB\.TZC0'

zline() {
    grep -aE "^zone .*$2 " "$D/$1.txt" 2>/dev/null | tr -d '\r\000' | "$3" -1
}

tz() {
    qstart "$K" "$1" "$BASE $2" "${TAB[@]}"
}

tz basic "thermms=200 thermdump=1 thermt1=3 thermv1=0 thermt2=5 thermv2=65535"
tz crit "thermms=100 thermcrit=1"
tz nocrt "thermms=200 thermcritb=2 thermdump=6"
tz hot "thermms=200 thermt1=2 thermv1=3700 thermdump=6"
tz lowend "thermms=200 thermtemp=2532 thermdump=3"
tz lowbad "thermms=200 thermtemp=2531 thermdump=3"
tz defint "thermdump=3"
tz zonec "thermms=200 thermdump=1 thermcset=2 thermcval=50 thermabsent=4"
qstart "$K" off "$BASE nothermal" "${TAB[@]}"
for n in basic crit nocrt hot lowend lowbad defint zonec off; do qwaitexit $n 1200 || { qfinish $n; echo "  timeout in run $n"; }; done

A1=$(zline basic "$ZA" head)
B1=$(zline basic "$ZB" head)
AL=$(zline basic "$ZA" tail)
BL=$(zline basic "$ZB" tail)
chk "basic: kernel finished (machine kept running)" 21 "$(cat "$D/basic.rc")"
chk "basic: header zones and interval" 1 "$(has basic '^thermal zones=3 interval_ms=200$')"
chk "basic: zone A found with temp 30.0" 30.0 "$(val "$A1" temp_c)"
chk "basic: zone A crt" 100.0 "$(val "$A1" crt_c)"
chk "basic: zone A hot" 90.0 "$(val "$A1" hot_c)"
chk "basic: zone A psv" 50.0 "$(val "$A1" psv_c)"
chk "basic: zone B found with temp 30.0" 30.0 "$(val "$B1" temp_c)"
chk "basic: zone B has no crt" na "$(val "$B1" crt_c)"
chk_ge "basic: valid samples counted" 1 "$(val "$A1" valid)"
chk_le "basic: sampling is rate limited" 8 "$(val "$A1" valid)"
chk "basic: no early invalid" 0 "$(val "$A1" invalid)"
chk_ge "invalid values counted (0 and 0xFFFF)" 2 "$(val "$AL" invalid)"
chk_ge "invalid values counted on zone B" 2 "$(val "$BL" invalid)"
chk "invalid value never shown as temperature" 30.0 "$(val "$AL" temp_c)"
chk "invalid value never in min" 30.0 "$(val "$AL" min)"
chk "invalid value never in max" 30.0 "$(val "$AL" max)"
chk "basic: no errors" 0 "$(val "$AL" errors)"
chk "basic: line format" 1 "$([[ "$AL" =~ ^zone\ [^\ ]+\ temp_c=-?[0-9]+\.[0-9]\ crt_c=[^\ ]+\ hot_c=[^\ ]+\ psv_c=[^\ ]+\ min=[^\ ]+\ max=[^\ ]+\ valid=[0-9]+\ invalid=[0-9]+\ errors=[0-9]+ ]] && echo 1 || echo 0)"
chk "basic: cpu line" 1 "$(has basic '^cpu temp_c=')"
chk "basic: no false alarm" 0 "$(count basic 'thermal: CRITICAL')"

chk "critical: machine powered off through ACPI" 0 "$(cat "$D/crit.rc")"
chk "critical: reported once" 1 "$(count crit 'thermal: CRITICAL .*TZA0')"
chk "critical: filesystems synced first" 1 "$(has crit '^thermal: filesystems synced')"
chk "critical: power off message" 1 "$(has crit '^thermal: powering off')"
chk "critical: acpi shutdown path used" 1 "$(has crit '^power: acpi pm1a=')"

AN=$(zline nocrt "$ZA" tail)
BN=$(zline nocrt "$ZB" tail)
chk "no crt: machine kept running" 21 "$(cat "$D/nocrt.rc")"
chk "no crt: no critical action" 0 "$(count nocrt 'thermal: (CRITICAL|powering off)')"
chk "no crt: hot reading recorded on zone B" 116.8 "$(val "$BN" max)"
chk_ge "no crt: zone B keeps being sampled" 15 "$(val "$BN" valid)"
chk "no crt: zone A unaffected" 30.0 "$(val "$AN" temp_c)"

AH=$(zline hot "$ZA" tail)
chk "hot: machine kept running" 21 "$(cat "$D/hot.rc")"
chk "hot: no critical action" 0 "$(count hot 'thermal: (CRITICAL|powering off)')"
chk "hot: one hot event" 1 "$(val "$AH" hot_events)"
chk "hot: one passive event" 1 "$(val "$AH" psv_events)"
chk "hot: hot message" 1 "$(count hot 'thermal: hot .*TZA0')"

AE=$(zline lowend "$ZA" tail)
chk "lower bound 2532 dK is valid" -20.0 "$(val "$AE" temp_c)"
chk "lower bound has no invalid" 0 "$(val "$AE" invalid)"
AB=$(zline lowbad "$ZA" tail)
chk "below lower bound is invalid" na "$(val "$AB" temp_c)"
chk_ge "below lower bound counted" 1 "$(val "$AB" invalid)"
chk "below lower bound no valid" 0 "$(val "$AB" valid)"

AD=$(zline defint "$ZA" head)
chk "default interval" 1 "$(has defint '^thermal zones=3 interval_ms=2000$')"
chk_ge "default interval samples" 1 "$(val "$AD" valid)"
chk_le "default interval is slow" 3 "$(val "$AD" valid)"

chk "off: module off message" 1 "$(has off '^thermal: off')"
chk "off: no zones listed" 0 "$(count off '^thermal: zone ')"
chk "off: machine kept running" 21 "$(cat "$D/off.rc")"
chk "off: events still ready" 1 "$(val "$(line off '^acpiev: ready=')" ready)"

C1=$(zline zonec "$ZC" head)
CL=$(zline zonec "$ZC" tail)
chk "zone C: kernel finished" 21 "$(cat "$D/zonec.rc")"
chk "zone C: found with ec style temp" 45.0 "$(val "$C1" temp_c)"
chk "zone C: crt from constant" 128.0 "$(val "$C1" crt_c)"
chk "zone C: psv from method" 65.0 "$(val "$C1" psv_c)"
chk "zone C: new temp after change" 50.0 "$(val "$CL" temp_c)"
chk "zone C: limits re-read after trip point change notify" 70.0 "$(val "$CL" psv_c)"
chk "zone C: absent after status turns 0" 0 "$(val "$CL" present)"
chk "zone C: no errors" 0 "$(val "$CL" errors)"
chk "zone C: no false alarm" 0 "$(count zonec 'thermal: (CRITICAL|powering off)')"
