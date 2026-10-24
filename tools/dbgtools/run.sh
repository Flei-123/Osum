#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dbgtools/run.sh -- QEMU gate: lspci, pcicfg, regdump, prphread, wlanctl (SYS_OSUM_DBG), with counter-proofs.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=$(mktemp -d); [ -z "${DBGTOOLS_KEEP:-}" ] && trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
TOOLS="lspci pcicfg regdump prphread wlanctl"
PROGS="sh cat echo sleep su $TOOLS"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; echo "DBGTOOLS: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; echo "DBGTOOLS: $pass passed, $fail failed"; exit 1; }
printf 'root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/:/bin/sh\n' > "$D/passwd"
printf 'root:x:0:\njustin:x:1000:\n' > "$D/group"
cat > "$D/s.sh" <<'EOS'
echo ==LSPCI==
lspci
echo ==LSPCIV==
lspci -v 00:05.0
echo ==LSPCI-ONE==
lspci 00:06.0
echo ==LSPCI-BAD==
lspci 99:99.9
echo ==LSPCI-NONE==
lspci 00:1f.7
echo ==CFG==
pcicfg 00:06.0 0 10
echo ==CFG-DEFAULT==
pcicfg 00:05.0
echo ==CFG-RANGE==
pcicfg 00:06.0 100 4
echo ==CFG-BADADDR==
pcicfg zz
echo ==REG-ID==
regdump 00:06.0 0 0 1
echo ==REG-BAR==
regdump 00:05.0 1 0 1
echo ==REG-BIG==
regdump 00:06.0 0 0 100000
echo ==REG-WRITE-NOFLAG==
regdump 00:06.0 0 4 1
echo ==REG-WRITE==
regdump --write 00:06.0 0 4 a5a5a5a5
regdump 00:06.0 0 4 1
echo ==REG-WRITE-NOVALUE==
regdump --write 00:06.0 0 4
regdump 00:06.0 0 4 1
echo ==CFG-WRITE==
pcicfg 00:06.0 4 2
pcicfg --write 00:06.0 4 2 0
pcicfg 00:06.0 4 2
echo ==REG-DECODE-OFF==
regdump 00:06.0 0 0 1
pcicfg --write 00:06.0 4 2 7
pcicfg 00:06.0 4 2
regdump 00:06.0 0 0 1
echo ==PRPH==
prphread 00:06.0 a01e30 1
prphread 00:06.0
echo ==USER-LSPCI==
su justin /bin/lspci 00:06.0
echo ==USER-CFG==
su justin /bin/pcicfg 00:06.0 0 4
echo ==USER-CFGW==
su justin /bin/pcicfg --write 00:06.0 4 2 0
pcicfg 00:06.0 4 2
echo ==USER-REG==
su justin /bin/regdump 00:06.0 0 0 1
echo ==USER-REGW==
su justin /bin/regdump --write 00:06.0 0 4 11111111
regdump 00:06.0 0 4 1
echo ==USER-PRPH==
su justin /bin/prphread 00:06.0 a01e30
echo ==USER-RELOAD==
su justin /bin/wlanctl reload
echo ==USER-STATUS==
su justin /bin/wlanctl status
echo ==END==
EOS
cat > "$D/w.sh" <<'EOS'
echo ==W-START==
sleep 15
wlanctl status
echo ==W-RELOAD==
wlanctl reload
sleep 10
echo ==W-AFTER==
wlanctl status
wlanctl dump
cat /tmp/wlan-dump.txt
echo ==END==
EOS
mkdir -p "$D/blobs"
python3 -I tools/iwlfh/ref.py gen "$D/blobs" > /dev/null 2>&1 && ok "fake firmware blobs generated" || bad "fake firmware blobs"
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
python3 tools/osum/mkfs.py build "$D/d.img" 20000 --v3 /lib/ /tmp/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do if [ "$p" = su ]; then echo "/bin/su=$D/bin/su.elf@4755:0:0"; else echo "/bin/$p=$D/bin/$p.elf"; fi; done) \
    "/etc/passwd=$D/passwd" "/etc/group=$D/group" \
    "/t/s.sh=$D/s.sh" "/t/w.sh=$D/w.sh" "$FWPATH=$D/blobs/v7.bin" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
head -c 8388608 /dev/zero > "$D/nvme.img"
runvm() {
    local name=$1; local words=$2; shift 2
    cp "$D/d.img" "$D/d-$name.img"
    timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum vfs $words script=sh ${SCRIPT:-/t/s.sh};exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
runvm main "" -device e1000,addr=0x5 -device edu,addr=0x6 -drive "file=$D/nvme.img,format=raw,if=none,id=nv" -device nvme,drive=nv,serial=dbg,addr=0x7
SCRIPT=/t/w.sh runvm bound "iwlfhtest iwlfhbind"
SCRIPT=/t/w.sh runvm free "iwlfhtest"
[ -n "${DBGTOOLS_KEEP:-}" ] && mkdir -p /tmp/dbgtools-keep; cp "$D"/*.klar /tmp/dbgtools-keep/
M="$D/main.klar"; B="$D/bound.klar"; F="$D/free.klar"
sec() { sed -n "/==$2==/,/==/p" "$1" | sed '1d;$d'; }
sec "$M" LSPCI | grep -aq '^00:03.0 8086:100e class=020000 hdr=00 drv=e1000 builtin' && ok "lspci: e1000 id, class and driver" || bad "lspci: e1000 line"
sec "$M" LSPCI | grep -aq '^00:07.0 1b36:0010 class=010802 .* drv=nvme' && ok "lspci: NVMe id, class and driver" || bad "lspci: nvme line"
sec "$M" LSPCI | grep -aq '^00:06.0 1234:11e8 class=00ff00 .* drv=none' && ok "lspci: edu device without driver shows drv=none" || bad "lspci: edu line"
has "$M" "bar0 addr=00000000feba0000 size=00020000 flags=0" "lspci -v: BAR0 address and size"
has "$M" "bar1 addr=000000000000c040 size=00000040 flags=1" "lspci -v: I/O BAR flagged"
has "$M" "lspci: bad address" "lspci: malformed address refused"
has "$M" "lspci: error 19 no such device" "lspci: absent device refused"
sec "$M" CFG | head -1 | grep -aq '^00: 34 12 e8 11 03 01 10 00 10 00 ff 00 00 00 00 00$' && ok "pcicfg: hexdump equals the QEMU edu config (vendor/device, command, revision, class)" || bad "pcicfg: edu hexdump differs"
sec "$M" CFG-DEFAULT | head -1 | grep -aq '^00: 86 80 0e 10' && ok "pcicfg: default 64-byte dump of the e1000" || bad "pcicfg: default dump"
has "$M" "pcicfg: error 22 invalid argument" "pcicfg: offset past 255 refused"
has "$M" "bar0+00000000: 010000ed" "regdump: edu identification register reads 010000ed"
has "$M" "regdump: error 6 no such device or space" "regdump: unmapped BAR refused"
has "$M" "regdump: error 22 invalid argument" "regdump: count above the limit refused"
sec "$M" REG-WRITE-NOFLAG | grep -aq '^bar0+00000004: 00000000$' && ok "regdump: liveness register starts at zero (plain read changes nothing)" || bad "regdump: liveness start"
sec "$M" REG-WRITE | grep -aq '^bar0+00000004: 5a5a5a5a$' && ok "regdump --write: edu liveness register returns the inverted value" || bad "regdump --write effect"
sec "$M" REG-WRITE-NOVALUE | grep -aq '^bar0+00000004: 5a5a5a5a$' && ok "regdump --write without value: usage, register unchanged" || bad "regdump write without value"
sec "$M" CFG-WRITE | grep -aq '^04: 00 00$' && ok "pcicfg --write: command register cleared" || bad "pcicfg --write effect"
sec "$M" REG-DECODE-OFF | head -1 | grep -aq 'regdump: error 6' && ok "regdump: refused while PCI memory decode is off (no silent enable)" || bad "regdump with decode off"
sec "$M" REG-DECODE-OFF | tail -1 | grep -aq '^bar0+00000000: 010000ed$' && ok "regdump: works again after the command register is restored" || bad "regdump after restore"
has "$M" "prphread: error 6 no such device or space" "prphread: non-Intel device refused"
sec "$M" USER-LSPCI | grep -aq '^00:06.0 1234:11e8' && ok "user: lspci allowed without root" || bad "user lspci"
sec "$M" USER-CFG | grep -aq '^00: 34 12 e8 11$' && ok "user: pcicfg read allowed without root" || bad "user pcicfg read"
for t in USER-CFGW USER-REG USER-REGW USER-PRPH USER-RELOAD; do
    sec "$M" $t | grep -aq 'error 1 permission denied' && ok "user: $t refused (counter-proof, root only)" || bad "user: $t was not refused"
done
sec "$M" USER-REGW | tail -1 | grep -aq '^bar0+00000004: 5a5a5a5a$' && ok "user: refused write left the register unchanged" || bad "user write changed the register"
sec "$M" USER-CFGW | tail -1 | grep -aq '^04: 07 00$' && ok "user: refused config write left the command register unchanged" || bad "user config write took effect"
sec "$M" USER-STATUS | grep -aq 'reload pending=0 finished=0' && ok "user: wlanctl status allowed" || bad "user wlanctl status"
sec "$B" W-RELOAD | grep -aq 'wlanctl: error 16 busy' && ok "wlanctl reload: refused while a WLAN driver is bound (fake 8265)" || bad "reload with bound driver"
sec "$B" W-AFTER | grep -aq 'reload pending=0 finished=0' && ok "wlanctl status: refused reload ran nothing" || bad "bound: reload counters"
sec "$B" W-START | grep -aq 'driver=bound' && ok "wlanctl status: shows /proc/wlan with the bound driver" || bad "bound: status lacks driver=bound"
sec "$F" W-RELOAD | grep -aq 'reload requested' && ok "wlanctl reload: accepted without a bound driver" || bad "free: reload not accepted"
sec "$F" W-AFTER | grep -aq 'reload pending=0 finished=1' && ok "wlanctl status: the reload ran once in the WLAN task (finished=1)" || bad "free: reload did not finish"
has "$F" "wlan: reload done" "serial: reload done line"
has "$F" "wrote /tmp/wlan-dump.txt" "wlanctl dump: file written"
has "$F" "== /proc/wlan ==" "dump file: /proc/wlan section"
has "$F" "== secure boot ==" "dump file: secure boot section"
has "$F" "no wireless pci device" "dump file: says so when no wireless PCI device exists"
hasnot "$M" "EXCEPTION" "no kernel exception"
hasnot "$F" "EXCEPTION" "no kernel exception (reload boot)"
docs_missing() {
    python3 -I - "$1" "$2" <<'PY'
import os, re, sys
doc = open(sys.argv[1]).read()
build = open(sys.argv[2]).read()
progs = set(re.search(r'PROGS=\$\{PROGS:-"([^"]*)"\}', build).group(1).split())
exempt = {"key", "wlan"}
missing = []
for span in re.findall(r'`([^`\n]+)`', doc):
    words = span.split()
    w = words[0] if words else ""
    if re.fullmatch(r'[a-z][a-z0-9_]*', w) and os.path.exists('kernel/user/%s.fi' % w) and w not in exempt and w not in progs:
        missing.append(w)
print(" ".join(sorted(set(missing))))
PY
}
NEED=$(docs_missing docs/ERSTER-BOOT.md tools/usbimg/build.sh)
[ -z "$NEED" ] && ok "every program documented in ERSTER-BOOT.md is in the stick PROGS" || bad "documented but not in PROGS: $NEED"
for t in drvctl $TOOLS; do grep -q "\`$t" docs/ERSTER-BOOT.md && ok "ERSTER-BOOT.md documents $t" || bad "ERSTER-BOOT.md does not mention $t"; done
sed 's/ wlanctl"}/"}/' tools/usbimg/build.sh > "$D/build-nowlanctl.sh"
CP=$(docs_missing docs/ERSTER-BOOT.md "$D/build-nowlanctl.sh")
[ "$CP" = "wlanctl" ] && ok "counter-proof: wlanctl dropped from PROGS is reported" || bad "counter-proof: expected 'wlanctl', got '$CP'"
echo "DBGTOOLS: $pass passed, $fail failed"
[ "$fail" = 0 ]
