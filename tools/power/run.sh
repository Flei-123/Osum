#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/power/run.sh -- L-005/L-006/L-007: laptop power policy (lid action, battery/mains item, idle timers).
#   bash tools/power/run.sh
# 1) policy + tray item on the build host (tools/power/host.fi: lid action per power source, edges, standby timer
#    scaled to seconds, battery % / mains states, tooltips)  2) compile checks: lib/power/policy.fi and
#    lib/fui/traypower.fi in profile kernel, /bin/powerd in profile kernel  3) schema + conf keys agree
#    4) the new kernel entries exist (PS_BLANKAFTER, PS_INJECT, acpiev.inject)
# 5) QEMU stage (skip: POWER_HOST_ONLY=1; reuse a built kernel: POWER_KERNEL=<k0.img>): the real kernel with the fake laptop
#    (tools/acpiev/asl/laptop.asl via -acpitable, `acpiev evfake`), powerd running, `powerd inject L P S A` flips lid / percent /
#    battery state / mains through AML -> GPE -> Notify -> kernel values. Checks the logged lid action per power source,
#    `powerd status` (the taskbar item model) and the idle standby timer (seconds, scaled down).
# NOT HERE: S3 on a lid close (tools/s3, s3dev gates cover the sleep itself).
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
    [ "$n" -ge 40 ] && ok "at least 40 checks ran ($n)" || bad "only $n checks ran"
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

if [ -z "${POWER_HOST_ONLY:-}" ]; then
echo "== 5. QEMU: fake laptop, powerd, lid / mains / battery / idle timer =="
if ! command -v qemu-system-x86_64 >/dev/null 2>&1 || ! command -v iasl >/dev/null 2>&1; then
    echo "  SKIP  qemu or iasl missing"; POWER_HOST_ONLY=1
fi
fi
if [ -z "${POWER_HOST_ONLY:-}" ]; then
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -w /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
export FIRNLIB="$PWD/lib"
mkdir -p "$T/bin" "$T/asl"
cp tools/acpiev/asl/laptop.asl "$T/asl/"
( cd "$T/asl" && iasl laptop.asl > iasl.txt 2>&1 ) && ok "laptop.asl compiles (fake lid, battery, mains)" || bad "laptop.asl does not compile"
if bash tools/sync/build.sh "$T/bin" 0 sh echo sleep cat powerd > "$T/b.txt" 2>&1; then ok "user programs build (sh echo sleep cat powerd)"
else bad "user programs do not build"; tail -5 "$T/b.txt"; fi
K="${POWER_KERNEL:-$T/k0.img}"
if [ -z "${POWER_KERNEL:-}" ]; then
    if ./tools/build-kernel.sh "$K" --stufe 0 > "$T/k.txt" 2>&1; then ok "the kernel builds"; else bad "the kernel does not build"; tail -5 "$T/k.txt"; fi
fi
if [ -f "$K" ] && [ -f "$T/asl/laptop.aml" ] && [ -f "$T/bin/powerd.elf" ]; then
cat > "$T/power.conf" <<'CONF'
# gate: lid on battery does nothing, lid on mains shuts down; no idle standby here (own boot below)
lid_bat=nothing
lid_ac=shutdown
screen_bat=40
screen_ac=90
standby_bat=0
standby_ac=0
profile_bat=save
profile_ac=performance
CONF
cat > "$T/s.sh" <<'SCRIPT'
echo ==STATUS0==
powerd status
powerd &
sleep -m 1500
echo ==BAT77==
powerd inject 1 77 1 0
sleep -m 1200
powerd status
echo ==BAT15==
powerd inject 1 15 1 0
sleep -m 1200
powerd status
echo ==BAT5==
powerd inject 1 5 1 0
sleep -m 1200
powerd status
echo ==LIDBAT==
powerd inject 0 77 1 0
sleep -m 1500
powerd inject 1 77 1 0
sleep -m 1500
echo ==CHARGING==
powerd inject 1 77 2 1
sleep -m 1200
powerd status
echo ==FULL==
powerd inject 1 100 0 1
sleep -m 1200
powerd status
echo ==LIDAC==
powerd inject 0 100 0 1
sleep -m 1500
echo ==SVC==
cat /run/svc.cmd
echo ==BACKBAT==
powerd inject 1 60 1 0
sleep -m 1500
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$T/disk.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ "/etc/power.conf=$T/power.conf" \
    "/bin/sh=$T/bin/sh.elf" "/bin/echo=$T/bin/echo.elf" "/bin/sleep=$T/bin/sleep.elf" "/bin/cat=$T/bin/cat.elf" \
    "/bin/powerd=$T/bin/powerd.elf" "/t/s.sh=$T/s.sh" > "$T/mkfs.txt" 2>&1 || { bad "mkfs failed"; tail -3 "$T/mkfs.txt"; }
timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -kernel "$K" -m 512 \
    -append "osum vfs nokbd nosched noproc acpiev evfake script=sh /t/s.sh;exit" \
    -acpitable "file=$T/asl/laptop.aml" \
    -serial "file:$T/ser.txt" -display none -no-reboot \
    -drive "file=$T/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/ser.txt" | tr -d '\r' > "$T/ser.klar" 2>/dev/null
if [ -n "${POWER_KEEP:-}" ]; then cp "$T/ser.klar" "$POWER_KEEP"; fi
has() { grep -qaF -- "$1" "$T/ser.klar" && ok "$2" || bad "$2 -- '$1' missing"; }
sec() { awk -v a="==$1==" -v b="==$2==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$T/ser.klar"; }
chk() { sec "$1" "$2" | grep -qaF -- "$3" && ok "$4" || bad "$4 -- '$3' not in ==$1=="; }
has "acpiev: ready=" "the kernel found the fake laptop (acpiev ready)"
has "powerd: on, conf /etc/power.conf" "powerd started and reads /etc/power.conf"
has "powerd: source mains=0 profile=" "battery source applied (profile, screen-off, brightness)"
chk BAT77 BAT15 "pct=77" "inject 77 % -> kernel shows 77 %"
chk BAT77 BAT15 "tray=1" "77 % on battery -> tray state 'discharging'"
chk BAT15 BAT5 "tray=4" "15 % on battery -> tray state 'low'"
chk BAT5 LIDBAT "tray=5" "5 % on battery -> tray state 'critical'"
chk BAT5 LIDBAT "battery critical" "tooltip says 'battery critical'"
chk CHARGING FULL "tray=2" "mains + charging -> tray state 'charging'"
chk CHARGING FULL "ac=1" "mains adapter seen (_PSR)"
chk FULL LIDAC "tray=3" "mains, full -> tray state 'plugged'"
chk LIDBAT CHARGING "powerd: lid closed mains=0 action=nothing" "lid closed on battery -> action 'nothing'"
chk LIDBAT CHARGING "powerd: lid opened mains=0" "lid opened is seen"
chk LIDAC SVC "powerd: lid closed mains=1 action=shutdown" "lid closed on mains -> action 'shutdown'"
chk SVC BACKBAT "shutdown" "shutdown action wrote 'shutdown' to /run/svc.cmd"
chk BACKBAT END "powerd: source mains=0" "mains unplugged -> battery source applied again"
grep -aq "powerd: standby after idle" "$T/ser.klar" && bad "idle standby fired although standby_bat=0" || ok "standby_bat=0 -> no idle standby"
# second boot: idle timer (standby_bat=6 seconds, no input at all)
cp "$T/power.conf" "$T/power1.conf"
sed -i 's/^standby_bat=0/standby_bat=6/' "$T/power1.conf"
printf 'powerd &\nsleep -m 14000\necho ==END==\n' > "$T/s2.sh"
python3 tools/osum/mkfs.py build "$T/disk2.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ "/etc/power.conf=$T/power1.conf" \
    "/bin/sh=$T/bin/sh.elf" "/bin/echo=$T/bin/echo.elf" "/bin/sleep=$T/bin/sleep.elf" "/bin/cat=$T/bin/cat.elf" \
    "/bin/powerd=$T/bin/powerd.elf" "/t/s.sh=$T/s2.sh" > "$T/mkfs2.txt" 2>&1 || { bad "mkfs (idle boot) failed"; tail -3 "$T/mkfs2.txt"; }
timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -kernel "$K" -m 512 \
    -append "osum vfs nokbd nosched noproc acpiev evfake script=sh /t/s.sh;exit" \
    -acpitable "file=$T/asl/laptop.aml" \
    -serial "file:$T/ser2.txt" -display none -no-reboot \
    -drive "file=$T/disk2.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/ser2.txt" | tr -d '\r' > "$T/ser2.klar" 2>/dev/null
n=$(grep -ac "powerd: standby after idle mains=0" "$T/ser2.klar")
[ "$n" = 1 ] && ok "idle 6 s on battery -> standby wish, fired exactly once" || bad "idle standby fired $n times (want 1)"
grep -aq "powerd: lid closed mains=0 action=sleep" "$T/ser.klar" && bad "unexpected sleep action on battery" || ok "no sleep action where the conf says nothing"
# third boot: brightness persistence (restore from /etc/backlight.conf, save a changed level), fake PWM via `blpch`
printf 'percent=40\n' > "$T/backlight.conf"
printf 'powerd &\nsleep -m 3500\necho ==A==\ncat /etc/backlight.conf\necho ==END==\n' > "$T/s3.sh"
python3 tools/osum/mkfs.py build "$T/disk3.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ "/etc/power.conf=$T/power.conf" "/etc/backlight.conf=$T/backlight.conf" \
    "/bin/sh=$T/bin/sh.elf" "/bin/echo=$T/bin/echo.elf" "/bin/sleep=$T/bin/sleep.elf" "/bin/cat=$T/bin/cat.elf" \
    "/bin/powerd=$T/bin/powerd.elf" "/t/s.sh=$T/s3.sh" > "$T/mkfs3.txt" 2>&1 || { bad "mkfs (backlight boot) failed"; tail -3 "$T/mkfs3.txt"; }
timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -kernel "$K" -m 512 \
    -append "osum vfs nokbd nosched noproc acpiev evfake blpch script=sh /t/s.sh;exit" \
    -acpitable "file=$T/asl/laptop.aml" \
    -serial "file:$T/ser3.txt" -display none -no-reboot \
    -drive "file=$T/disk3.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/ser3.txt" | tr -d '\r' > "$T/ser3.klar" 2>/dev/null
if [ -n "${POWER_KEEP:-}" ]; then cp "$T/ser3.klar" "$POWER_KEEP.bl"; fi
awk '/==A==/{f=1;next} /==END==/{f=0} f' "$T/ser3.klar" | grep -aqF "percent=40" && ok "/etc/backlight.conf keeps percent=40" || bad "/etc/backlight.conf lost percent=40"
grep -aqF "powerd: backlight restored 40" "$T/ser3.klar" && ok "boot applies the saved level from /etc/backlight.conf" || bad "saved level not applied at boot"
awk '/==END==/{exit} {print}' "$T/ser3.klar" | grep -aqF "powerd: backlight saved" && bad "level saved although nothing changed" || ok "unchanged level (just restored) is not written back"
if [ -n "${POWER_KEEP:-}" ]; then cp "$T/ser.klar" "$POWER_KEEP"; fi
else
    bad "QEMU stage inputs missing (kernel / laptop.aml / powerd.elf)"
fi
fi
echo
echo "POWER: $pass passed, $fail failed"
[ "$fail" = 0 ]
