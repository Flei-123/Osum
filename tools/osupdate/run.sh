#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/osupdate/run.sh -- SELFUPDATE stage 1 gate (docs/SELFUPDATE.md).
#
# `ota system search|apply|confirm` on a REAL installed disk (GPT + FAT32 ESP, OVMF + Limine, QEMU),
# against a local HTTPS feed (tools/ota/server.py serving system/dev, signed with the test key the
# test image trusts). The "new" kernel is the built kernel with a patched commit string, so the
# running version is observable (`osum <hash>` on the first serial line, /proc/version).
#
#   bash tools/osupdate/run.sh [--keep]
#
# SECTIONS
#   1. build + install, user file written, feeds (good / bad-hash / bad-sig / not newer) published
#   2. good update: apply restart -> slot B on the ESP, trial boot runs the NEW kernel, confirm
#      promotes B -> A, SYSVERSION grows, next boot (slot A) still runs it, user file survived
#   3. negative: bad signature -> nothing touched on the ESP
#   4. negative: bad kernel hash -> download refused, no slot B, config untouched
#   5. negative: trial kernel dies right after ab_boot (`abpanic` word on entry B only) ->
#      3 attempts, loader back on slot A, old kernel runs, update dropped, user file survived
#   6. counter-proof: an update that is not newer is refused
#   7. periodic check of the service (installs nothing)
#   8. stage 2 raw: /bin overlay without gzip (fallback transport), old files moved to /system/old
#   9. stage 2 negative: overlay file with a wrong hash in a signed list -> refused, /bin untouched
#  10. stage 2 negative: gz with a flipped bit but a matching transport hash -> gunzip CRC refuses
#  11. stage 2 power cut: journal + half-moved files without a pending note -> restored on next confirm
# Sections 2 and 5 run with the gzip feed (kernel + overlay files as .gz, streaming gunzip on the
# device): the trial boot sees the new /bin files, confirm drops the backups, a lost trial restores them.
# OSU_SECS="8 9" runs only the listed sections (1 always runs); OSU_ONLY7=1 = "7".
#   7. periodic system check of the service (`ota service 1 system`): finds, fetches the changelog,
#      marks the notification, installs nothing; a not-newer feed stays `current`
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
KEEP=${1:-}
OWN_OUT=0
if [ -z "${OUT:-}" ]; then OUT=$(mktemp -d "${TMPDIR:-/tmp}/osupdate-run.XXXXXX"); OWN_OUT=1; fi
mkdir -p "$OUT"
. "$ROOT/tools/lib/sperre.sh" && osum_sperre "$OUT"
export OUT
PORT=${OSU_PORT:-$(( 18000 + ($$ % 900) ))}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
export OSUM_CPU=${OSUM_CPU:-SandyBridge}   # no AVX2 for /bin/fetch (docs/OTA.md)
export OTA_DRIVE=${OTA_DRIVE:-ahci}      # installed disk on AHCI (DMA): ESP file copies of 8.6 MB take 30 s instead of >10 min over IDE PIO

pass=0
fail=0
if [ -n "${OSU_ONLY7:-}" ] && [ -z "${OSU_SECS:-}" ]; then OSU_SECS="7"; fi
want() { [ -z "${OSU_SECS:-}" ] && return 0; case " $OSU_SECS " in *" $1 "*) return 0 ;; esac; return 1; }
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
hat() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hatnicht() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present but must not be" || ok "$3"; }

SRVPID=""
dienst_aus() {
    if [ -n "$SRVPID" ]; then kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; fi
    SRVPID=""
}
dienst() { # <root>
    dienst_aus
    : > "$OUT/srv.log"
    python3 tools/ota/server.py --wurzel "$1" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/srv.log" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    local i
    for i in $(seq 1 40); do
        grep -qa "^START port=$PORT " "$OUT/srv.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
aufraeumen() {
    dienst_aus
    if [ "$OWN_OUT" = 1 ] && [ "$KEEP" != "--keep" ] && [ -z "${OSU_KEEP:-}" ]; then rm -rf "$OUT"; fi
}
trap aufraeumen EXIT

ESP="$OUT/ziel.img@@1048576"
esp_get() { mcopy -i "$ESP" "::/$1" - 2>/dev/null; }
esp_put() { mcopy -o -i "$ESP" "$1" "::/$2"; }
esp_sha() { esp_get "$1" | sha256sum | cut -d' ' -f1; }
esp_has() { mdir -i "$ESP" "::/$1" > /dev/null 2>&1; }
conf_default() { esp_get limine.conf | sed -n 's/^default_entry: *//p'; }
commit_of() { first_line "$1" | sed 's/^osum //' | cut -c1-7; }

# One boot of the installed disk. The first boot of a case lets oneshot.sh write the (one entry)
# config; later boots keep the ESP config and only swap the script= of every entry.
lauf() { # name script [keep]
    local n=$1 sk=$2
    if [ "${3:-}" = keep ]; then
        esp_get limine.conf > "$OUT/$n.conf0"
        python3 - "$OUT/$n.conf0" "$OUT/$n.conf" "$sk" <<'EOF'
import re, sys
t = open(sys.argv[1], encoding="latin1").read()
t = re.sub(r"script=.*", lambda m: "script=" + sys.argv[3], t)
open(sys.argv[2], "w", encoding="latin1").write(t)
EOF
        esp_put "$OUT/$n.conf" limine.conf
        ESP_KEEP=1 OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh "$n" platte "$sk" 600 > /dev/null 2>&1
    else
        OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh "$n" platte "$sk" 600 > /dev/null 2>&1
    fi
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$n.txt" 2>/dev/null
    cat "$OUT/$n.rc" 2>/dev/null
}
first_line() { grep -a -m1 '^osum ' "$1" | tr -d '\r'; }
fresh_disk() { cp --sparse=always "$OUT/basis.img" "$OUT/ziel.img"; }

echo "== 1. build + install + feeds =="
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 && ok "pinned compiler" || bad "fetch-firnc.sh"
bash tools/install/pakete.sh "$OUT" > "$OUT/pak.log" 2>&1 && ok "base packages + test key (tools/install/pakete.sh)" || { tail -5 "$OUT/pak.log"; bad "install/pakete.sh"; }
python3 tools/ota/mkcerts.py "$OUT/certs" ota.test 10.0.2.2 > "$OUT/certs.log" 2>&1 && ok "certificates" || { cat "$OUT/certs.log"; bad "mkcerts.py"; }
cat > "$OUT/ota.conf" <<EOF
quelle=https://10.0.2.2:$PORT
name=ota.test
kanal=dev
abstand=3600
auto=nein
frist=15
EOF
printf '00000100\n' > "$OUT/sysver"
# /bin overlay fixtures: OLD files go into the image, the NEW set is published in the feed
mkdir -p "$OUT/ovl" "$OUT/ovl-old"
python3 - "$OUT" <<'EOF'
import os, random, sys
o = sys.argv[1]
words = ["alpha", "beta", "gamma", "delta", "kernel", "system", "update", "overlay", "taskbar", "login"]
def text(n, seed):
    r = random.Random(seed)
    return "".join("line %d %s %s %08x\n" % (i, r.choice(words), r.choice(words), r.getrandbits(32))
                   for i in range(n))
def put(path, data):
    open(path, "wb").write(data if isinstance(data, bytes) else data.encode())
put(o + "/ovl/gate-ovl.txt", "OVERLAY-NEW-CONTENT\n")
put(o + "/ovl/gate-new.txt", "BRAND-NEW-FILE\n")
put(o + "/ovl/gate-big.txt", text(8000, 1))                      # ~270 KB: many 32 KiB windows, long matches
put(o + "/ovl/gate-rnd.bin", random.Random(3).randbytes(40000))  # incompressible: stored blocks
put(o + "/ovl-old/gate-ovl.txt", "OVERLAY-OLD-CONTENT\n")
put(o + "/ovl-old/gate-big.txt", text(300, 2))
put(o + "/ovl-old/gate-rnd.bin", random.Random(4).randbytes(900))
EOF
h() { sha256sum "$1" | cut -d' ' -f1; }
H_BIG_NEW=$(h "$OUT/ovl/gate-big.txt"); H_RND_NEW=$(h "$OUT/ovl/gate-rnd.bin")
H_BIG_OLD=$(h "$OUT/ovl-old/gate-big.txt"); H_RND_OLD=$(h "$OUT/ovl-old/gate-rnd.bin")
PROGS_DEF=$(sed -n 's/^PROGS=${PROGS:-"\(.*\)"}$/\1/p' tools/install/build.sh)
[ -n "$PROGS_DEF" ] && export PROGS="$PROGS_DEF shasum" || bad "cannot read the default PROGS of install/build.sh"
SEED="user-data-$$-$(date +%s)"
printf '%s\n' "$SEED" > "$OUT/gate-seed"
OTA_ROOTS="$OUT/certs/ca.pem" OTA_CONF="$OUT/ota.conf" ZIEL_MIB=96 \
    EXTRA="/system/SYSVERSION=$OUT/sysver /gate-seed=$OUT/gate-seed /bin/gate-ovl.txt=$OUT/ovl-old/gate-ovl.txt /bin/gate-big.txt=$OUT/ovl-old/gate-big.txt /bin/gate-rnd.bin=$OUT/ovl-old/gate-rnd.bin" \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built (kernel $(stat -c%s "$OUT/k.mb") octets)" || { tail -20 "$OUT/build.log"; bad "install/build.sh"; }
rm -f "$OUT/ziel.img"
head -c $((96 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 > /dev/null 2>&1
gleich "install onto an empty GPT disk" "$(cat "$OUT/inst.rc" 2>/dev/null)" "21"
mdir -i "$ESP" ::/ > /dev/null 2>&1 && ok "ESP (partition 1) is a readable FAT" || bad "ESP unreadable"

# baseline boot: write the user file (runtime write onto the persistent root)
rc=$(lauf base0 "cp /gate-seed /users/gate.txt;cat /users/gate.txt;cat /system/SYSVERSION;ota system status;exit")
gleich "baseline boot" "$rc" "21"
OLD=$(commit_of "$OUT/base0.txt")
[ -n "$OLD" ] && ok "old kernel commit $OLD" || bad "no 'osum <hash>' line on the baseline boot"
hat "$OUT/base0.txt" "$SEED" "user file written + read back on the root partition"
hat "$OUT/base0.txt" "00000100" "SYSVERSION of the image is 00000100"
hat "$OUT/base0.txt" "system: no update pending" "no update pending"
cp --sparse=always "$OUT/ziel.img" "$OUT/basis.img"
OLDSHA=$(esp_sha osum.mb)

# the "new" kernel: same binary, other commit string (so the running version is observable)
NEW=$(printf '%s' "$OLD-new" | sha256sum | cut -c1-7)
mkdir -p "$OUT/img-new" "$OUT/img-old"
python3 - "$OUT/k.mb" "$OUT/img-new/osum.mb" "$NEW" <<'EOF'
import re, sys
d = open(sys.argv[1], "rb").read()
m = re.search(rb"osum ([0-9a-f]{7})[+0-9a-f]", d)
assert m, "no version string"
new = sys.argv[3].encode()
assert len(new) == 7
d = d[:m.start(1)] + new + d[m.end(1):]
open(sys.argv[2], "wb").write(d)
EOF
grep -qaF "osum $NEW" "$OUT/img-new/osum.mb" && ok "new kernel prepared (commit $NEW)" || bad "patching the kernel failed"
cp "$OUT/k.mb" "$OUT/img-old/osum.mb"
KSHA=$(sha256sum "$OUT/img-new/osum.mb" | cut -d' ' -f1)
pubt() { # <imgdir> <feed> <channel> [args] -- signed with the test key the image trusts
    local i=$1 f=$2 c=$3; shift 3
    python3 tools/ota/publish_system.py "$i" "$f" "$c" --key "$OUT/geheim.key" "$@" > "$OUT/pub.log" 2>&1
}
printf 'Gate build: new kernel, patched commit %s\n' "$NEW" > "$OUT/notes.txt"
pubt "$OUT/img-new" "$OUT/feed-good" dev --count 200 --notes "$OUT/notes.txt" --overlay "$OUT/ovl" --gz && ok "good feed: build 200 (gzip + 4 overlay files)" || { cat "$OUT/pub.log"; bad "publish good"; }
pubt "$OUT/img-new" "$OUT/feed-raw" dev --count 200 --notes "$OUT/notes.txt" --overlay "$OUT/ovl" && ok "raw feed: build 200 (no gzip, 4 overlay files)" || { cat "$OUT/pub.log"; bad "publish raw"; }
pubt "$OUT/img-new" "$OUT/feed-badovl" dev --count 200 --overlay "$OUT/ovl" --gz --bad-ovl-hash && ok "bad overlay hash feed" || bad "publish bad-ovl-hash"
pubt "$OUT/img-new" "$OUT/feed-badgz" dev --count 200 --overlay "$OUT/ovl" --gz --bad-gz && ok "bad gz feed (flipped bit inside the deflate data)" || bad "publish bad-gz"
grep -qa "^sysgz" "$OUT/feed-good/system/dev/VERZEICHNIS" && grep -qa "^sysfile.file" "$OUT/feed-good/system/dev/VERZEICHNIS" && ok "list carries sysfile file + sysgz lines" || bad "list lacks the overlay lines"
pubt "$OUT/img-new" "$OUT/feed-badsig" dev --count 200 --bad-sig && ok "bad-signature feed" || bad "publish bad-sig"
pubt "$OUT/img-new" "$OUT/feed-badhash" dev --count 200 --bad-hash && ok "bad-hash feed" || bad "publish bad-hash"
pubt "$OUT/img-new" "$OUT/feed-old" dev --count 100 && ok "not-newer feed (build 100)" || bad "publish old"

echo
if want 2; then
echo "== 2. good update: apply restart -> trial of B -> confirm -> promoted =="
fresh_disk
dienst "$OUT/feed-good" && ok "feed up on 127.0.0.1:$PORT" || bad "feed does not start"
rc=$(lauf g1 "ota system search;ota system apply restart;ota system status;exit")
hat "$OUT/g1.txt" "system: update available" "search sees the update"
hat "$OUT/g1.txt" "system: available build 200" "available build 200"
hat "$OUT/g1.txt" "Gate build: new kernel" "changelog is shown"
hat "$OUT/g1.txt" "system: staged in slot B" "apply stages slot B"
hat "$OUT/g1.txt" "system: restarting" "apply restart restarts"
hatnicht "$OUT/g1.txt" "system: no update pending" "the script after the restart line did not run (machine went down)"
esp_has osum-b.mb && ok "ESP now holds osum-b.mb" || bad "no osum-b.mb on the ESP"
gleich "slot B hash == signed hash" "$(esp_sha osum-b.mb)" "$KSHA"
gleich "slot A untouched" "$(esp_sha osum.mb)" "$OLDSHA"
gleich "limine default_entry is 2" "$(conf_default)" "2"
esp_get limine.conf | grep -qa 'osum-b.mb' && ok "entry B points at osum-b.mb" || bad "no entry B"
mdir -i "$ESP" ::/ > /dev/null 2>&1 && ok "ESP FAT still readable" || bad "ESP FAT damaged"
rc=$(lauf g2 "cat /system/SYSVERSION;ota system status;cat /bin/gate-ovl.txt;shasum /bin/gate-big.txt /bin/gate-rnd.bin;exit" keep)
hat "$OUT/g2.txt" "OVERLAY-NEW-CONTENT" "trial boot: new /bin file (gz transport)"
hat "$OUT/g2.txt" "$H_BIG_NEW" "trial boot: gunzipped 270 KB file is byte-identical"
hat "$OUT/g2.txt" "$H_RND_NEW" "trial boot: gunzipped incompressible file is byte-identical"
gleich "trial boot ran" "$rc" "21"
gleich "the NEW kernel runs (first serial line)" "$(commit_of "$OUT/g2.txt")" "$NEW"
hat "$OUT/g2.txt" "ab: gen=" "ab_boot counted the trial"
hat "$OUT/g2.txt" "system: pending trial of build" "status shows the pending trial"
gleich "slot A still untouched before confirm" "$(esp_sha osum.mb)" "$OLDSHA"
rc=$(lauf g3 "ota system confirm;ota system status;cat /system/SYSVERSION;ls /system/old;ls /system;exit" keep)
hat "$OUT/g3.txt" "system: overlay committed" "confirm commits the overlay"
hatnicht "$OUT/g3.txt" "SYSOVL" "journal removed"
hatnicht "$OUT/g3.txt" "gate-ovl.txt" "backups removed from /system/old"
hat "$OUT/g3.txt" "system: new kernel confirmed and promoted to slot A" "confirm promotes B -> A"
gleich "slot A == new kernel" "$(esp_sha osum.mb)" "$KSHA"
gleich "limine default_entry back to 1" "$(conf_default)" "1"
hat "$OUT/g3.txt" "00000200" "SYSVERSION is 200 (00000200)"
hat "$OUT/g3.txt" "system: no update pending" "nothing pending any more"
rc=$(lauf g4 "cat /users/gate.txt;ota system search;exit" keep)
gleich "next boot (slot A)" "$(commit_of "$OUT/g4.txt")" "$NEW"
hat "$OUT/g4.txt" "$SEED" "user file survived the update"
hat "$OUT/g4.txt" "system: up to date" "search now says up to date"
dienst_aus

echo
fi
if want 3; then
echo "== 3. negative: bad signature =="
fresh_disk
dienst "$OUT/feed-badsig" || bad "feed does not start"
rc=$(lauf s1 "ota system search;ota system apply;ota system status;exit")
hatnicht "$OUT/s1.txt" "system: staged" "nothing staged"
hatnicht "$OUT/s1.txt" "system: update available" "no update announced from a forged list"
esp_has osum-b.mb && bad "osum-b.mb exists" || ok "no slot B on the ESP"
gleich "slot A untouched" "$(esp_sha osum.mb)" "$OLDSHA"
gleich "limine default_entry unchanged (no line)" "$(conf_default)" ""
hat "$OUT/s1.txt" "system: no update pending" "no pending record"
dienst_aus

echo
fi
if want 4; then
echo "== 4. negative: bad kernel hash in a correctly signed list =="
fresh_disk
dienst "$OUT/feed-badhash" || bad "feed does not start"
rc=$(lauf h1 "ota system apply;ota system status;exit")
hat "$OUT/h1.txt" "ota: kernel download or check failed" "hash mismatch refused"
hatnicht "$OUT/h1.txt" "system: staged" "nothing staged"
esp_has osum-b.mb && bad "bad file left on the ESP" || ok "the bad download was removed"
gleich "slot A untouched" "$(esp_sha osum.mb)" "$OLDSHA"
gleich "limine default_entry unchanged (no line)" "$(conf_default)" ""
hat "$OUT/h1.txt" "system: no update pending" "no pending record"
dienst_aus

echo
fi
if want 5; then
echo "== 5. negative: trial kernel dies right after ab_boot -> back on slot A =="
fresh_disk
dienst "$OUT/feed-good" || bad "feed does not start"
rc=$(lauf p1 "cp /gate-seed /users/gate2.txt;ota system apply;exit")
hat "$OUT/p1.txt" "system: staged in slot B" "staged"
dienst_aus
# the fault is injected into entry B ONLY (kernel word abpanic), the way a broken kernel would be
esp_get limine.conf > "$OUT/p.conf0"
python3 - "$OUT/p.conf0" "$OUT/p.conf" <<'EOF'
import sys
lines = open(sys.argv[1], encoding="latin1").read().split("\n")
out, inb = [], False
for l in lines:
    if l.startswith("/"):
        inb = "(update)" in l
    if inb and l.strip().startswith("cmdline:"):
        l = l.replace(" initsh", " abpanic initsh", 1)
    out.append(l)
open(sys.argv[2], "w", encoding="latin1").write("\n".join(out))
EOF
grep -qa abpanic "$OUT/p.conf" && ok "abpanic word on entry B" || bad "could not inject the fault"
esp_put "$OUT/p.conf" limine.conf
for b in 2 3 4; do
    ESP_KEEP=1 OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh "p$b" platte "exit" 300 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/p$b.txt" 2>/dev/null
done
for b in 2 3 4; do
    if [ "$b" = 4 ]; then # the third attempt gives up (rolls back) instead of counting
        hat "$OUT/p$b.txt" "ab: ERPROBUNG gescheitert" "boot $((b-1)) of the trial kernel reached ab_boot (gives up)"
    else
        hat "$OUT/p$b.txt" "ab: gen=" "boot $((b-1)) of the trial kernel reached ab_boot"
    fi
    gleich "boot $((b-1)) runs the NEW kernel" "$(commit_of "$OUT/p$b.txt")" "$NEW"
    hatnicht "$OUT/p$b.txt" "glogin: bereit" "boot $((b-1)) never reached the desktop (fault)"
done
hat "$OUT/p4.txt" "ab: ERPROBUNG gescheitert" "third attempt: trial declared failed"
hat "$OUT/p4.txt" "ab: esp: default_entry set to 1" "kernel puts the loader back on slot A"
gleich "ESP now reads default_entry 1" "$(conf_default)" "1"
rc=$(lauf p5 "cat /users/gate2.txt;ota system confirm;ota system status;cat /system/SYSVERSION;cat /bin/gate-ovl.txt;shasum /bin/gate-big.txt;ls /bin;exit" keep)
hat "$OUT/p5.txt" "system: overlay restored" "lost trial: overlay restored"
hat "$OUT/p5.txt" "OVERLAY-OLD-CONTENT" "lost trial: old /bin file is back"
hat "$OUT/p5.txt" "$H_BIG_OLD" "lost trial: old big file is back"
hatnicht "$OUT/p5.txt" "gate-new.txt" "lost trial: the new file is gone"
gleich "after the rollback the OLD kernel runs" "$(commit_of "$OUT/p5.txt")" "$OLD"
hat "$OUT/p5.txt" "$SEED" "user file written before the update survived the failed update"
hat "$OUT/p5.txt" "system: trial kernel was rolled back, update dropped" "update dropped"
hat "$OUT/p5.txt" "system: no update pending" "no pending record left"
hat "$OUT/p5.txt" "00000100" "SYSVERSION unchanged (100)"
gleich "slot A is still the old kernel" "$(esp_sha osum.mb)" "$OLDSHA"

echo
fi
if want 6; then
echo "== 6. counter-proof: an update that is not newer =="
fresh_disk
dienst "$OUT/feed-old" || bad "feed does not start"
rc=$(lauf o1 "ota system apply;ota system status;exit")
hat "$OUT/o1.txt" "system: up to date" "build 100 is not newer than 100"
esp_has osum-b.mb && bad "slot B written for an old build" || ok "no slot B"
dienst_aus

echo
fi
if want 8; then
echo "== 8. stage 2 raw: /bin overlay without gzip, apply swaps the files, old ones kept in /system/old =="
fresh_disk
dienst "$OUT/feed-raw" || bad "feed does not start"
rc=$(lauf r1 "cat /bin/gate-ovl.txt;ota system apply;cat /bin/gate-ovl.txt;cat /bin/gate-new.txt;shasum /bin/gate-big.txt /bin/gate-rnd.bin;cat /system/old/gate-ovl.txt;cat /system/SYSOVL;exit")
hat "$OUT/r1.txt" "OVERLAY-OLD-CONTENT" "before apply: the old /bin file"
hat "$OUT/r1.txt" "system: overlay files verified: 4" "4 overlay files verified"
hat "$OUT/r1.txt" "OVERLAY-NEW-CONTENT" "after apply: /bin has the new content"
hat "$OUT/r1.txt" "BRAND-NEW-FILE" "after apply: a brand-new /bin file exists"
hat "$OUT/r1.txt" "$H_BIG_NEW" "big text file (270 KB) is byte-identical"
hat "$OUT/r1.txt" "$H_RND_NEW" "incompressible file is byte-identical"
hat "$OUT/r1.txt" "1gate-ovl.txt" "journal says the file pre-existed"
hat "$OUT/r1.txt" "0gate-new.txt" "journal says the file is new"
dienst_aus
fi

if want 9; then
echo "== 9. stage 2 negative: wrong overlay hash in a signed list =="
fresh_disk
dienst "$OUT/feed-badovl" || bad "feed does not start"
rc=$(lauf b1 "ota system apply;cat /bin/gate-ovl.txt;ota system status;exit")
hat "$OUT/b1.txt" "ota: overlay file download or check failed" "bad overlay hash refused"
hatnicht "$OUT/b1.txt" "system: staged" "nothing staged"
hat "$OUT/b1.txt" "OVERLAY-OLD-CONTENT" "/bin untouched"
esp_has osum-b.mb && bad "slot B written" || ok "no slot B (overlay is checked before the kernel)"
dienst_aus
fi

if want 10; then
echo "== 10. stage 2 negative: gz with a flipped bit (transport hash matches, gunzip CRC must refuse) =="
fresh_disk
dienst "$OUT/feed-badgz" || bad "feed does not start"
rc=$(lauf z1 "ota system apply;cat /bin/gate-ovl.txt;ota system status;exit")
hat "$OUT/z1.txt" "ota: overlay file download or check failed" "corrupt gz refused"
hatnicht "$OUT/z1.txt" "system: staged" "nothing staged"
hat "$OUT/z1.txt" "OVERLAY-OLD-CONTENT" "/bin untouched"
esp_has osum-b.mb && bad "slot B written" || ok "no slot B"
dienst_aus
fi

if want 11; then
echo "== 11. stage 2 power cut: journal + half-moved file, no pending note -> restored by the next confirm =="
fresh_disk
rc=$(lauf c1 "mkdir /system/old;mv /bin/gate-ovl.txt /system/old/gate-ovl.txt;echo 1gate-ovl.txt > /system/SYSOVL;ota system confirm;cat /bin/gate-ovl.txt;exit")
hat "$OUT/c1.txt" "system: overlay restored" "restore ran"
hat "$OUT/c1.txt" "OVERLAY-OLD-CONTENT" "the old file is back in /bin"
fi

if want 7; then
echo "== 7. periodic system check of the service (ota service 1 system): finds, notes, notifies once, installs nothing =="
fresh_disk
dienst "$OUT/feed-good" || bad "feed does not start"
rc=$(lauf p1 "ota set auto ja;ota service 1 system;cat /system/sys.stand;cat /system/sys.notified;cat /system/sys.notes;exit")
hat "$OUT/p1.txt" "phase=available" "service check: sys.stand says available"
hat "$OUT/p1.txt" "there=200" "service check: the offered build is 200"
hat "$OUT/p1.txt" "00000200" "service check: build 200 is marked as notified"
hat "$OUT/p1.txt" "Gate build: new kernel" "service check: the changelog was fetched (sys.notes)"
hatnicht "$OUT/p1.txt" "system: update available" "service check is quiet (no console chatter)"
esp_has osum-b.mb && bad "periodic check wrote slot B" || ok "periodic check installs nothing (no slot B)"
[ "$(conf_default)" = "2" ] && bad "periodic check armed slot B (default_entry 2)" || ok "periodic check leaves default_entry alone (not 2: '$(conf_default)')"
dienst_aus
# the same service against a feed with an old build: stays current, no notification marker
fresh_disk
dienst "$OUT/feed-old" || bad "feed does not start"
rc=$(lauf p2 "ota set auto ja;ota service 1 system;cat /system/sys.stand;cat /system/sys.notified;exit")
hat "$OUT/p2.txt" "phase=current" "service check on a not-newer feed: phase current"
hatnicht "$OUT/p2.txt" "00000100" "... and no notification marker (no build number written)"
dienst_aus

fi

echo
echo "osupdate: $pass/$fail OK/FAIL"
[ "$fail" = 0 ]
