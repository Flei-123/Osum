#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
cleanup() { git worktree remove --force "$TMPD/mut" > /dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

make_bundle() { # make_bundle <dir> <name> <info> <keys> <start>
    local d="$TMPD/apps/$1.osp"
    cp -a assets/apps/trashbin.osp "$d"
    sed -i -e "s|^name=.*|name=$2|" -e "s|^info=.*|info=$3|" -e "s|^keys=.*|keys=$4|" -e "s|^id=.*|id=com.test.$1|" "$d/INFO"
    printf '%s\n' "$5" > "$d/start.txt"
}

mkdir -p "$TMPD/apps" "$TMPD/files"
for keep in explorer edit settings taskmgr; do cp -a assets/apps/$keep.osp "$TMPD/apps/"; done
cp -a assets/apps/certus.osp "$TMPD/apps/"
printf '/bin/echo\n' > "$TMPD/apps/certus.osp/start.txt"
make_bundle aa-reader "Aa Reader" "Reads certus files" "reader" /bin/edit
make_bundle ab-certus "Abcertus" "Tool" "tool" /bin/edit
make_bundle ac-certus-pad "Ac Certus Pad" "Pad" "pad" /bin/edit
make_bundle notes-one "Notes One" "Notes" "notes" /bin/edit
make_bundle notes-two "Notes Two" "Notes" "notes" /bin/edit
printf 'use=notes-two:3\n' > "$TMPD/startuse.conf"
for f in certus-notes.txt zzqq-file.txt spinatus.txt tattoo.txt; do printf 'x\n' > "$TMPD/files/$f"; done
MKFS_EXTRA="/data/"
for f in certus-notes.txt zzqq-file.txt spinatus.txt tattoo.txt; do MKFS_EXTRA="$MKFS_EXTRA /data/$f=$TMPD/files/$f@0644"; done

echo "== mutant tree: the old ranking =="
git worktree add --detach "$TMPD/mut" HEAD > /dev/null 2>&1 || { bad "mutant worktree"; echo "SEARCHRANKUI: $pass passed, $fail failed"; exit 1; }
python3 -I - "$TMPD/mut" <<'PY'
import sys
root = sys.argv[1]
p = root + "/kernel/user/startrank.fi"
s = open(p).read()
s = s.replace("fn rank_apps(", "fn rank_apps_ranked(").replace("fn rank_files(", "fn rank_files_ranked(")
s += "\nfn rank_apps(term: u64, out: u64, max: u64) -> u64 {\n    return appdir.search(term, out, max)\n}\n\nfn rank_files(term: u64, out: u64, max: u64) -> u64 {\n    return nidx.find(term, out, max)\n}\n"
open(p, "w").write(s)
q = root + "/kernel/user/launcher.fi"
b = open(q, "rb").read()
old = b"if !g_home && napp > 0 {"
assert b.count(old) == 1
open(q, "wb").write(b.replace(old, b"if !g_home {"))
PY

run_tree() { # run_tree <tree> <name>
    ( cd "$1" && APPS_DIR="$TMPD/apps" EH_ETC_EXTRA="/etc/startuse.conf=$TMPD/startuse.conf@0644" EH_MKFS_EXTRA="$MKFS_EXTRA" \
        DESIGNBUILD="$TMPD/build-$2" bash tools/design/eh6.sh "$TMPD/$2" res=1920x1080 accel=kvm tafel=nein \
        drehbuch="$ROOT/tools/searchrank/script.txt" > "$TMPD/$2.log" 2>&1 )
}
echo "== two runs in parallel: ranked and old =="
run_tree "$ROOT" new &
P1=$!
run_tree "$TMPD/mut" old &
P2=$!
wait $P1 $P2

val() { sed -n "s/^$2=//p" "$1" | head -1; }
for n in new old; do
    S="$TMPD/$n/serial.txt"
    [ -s "$S" ] || { bad "$n: no serial output: $(tail -3 "$TMPD/$n.log" | tr '\n' ' ')"; continue; }
    python3 -I tools/searchrank/check.py "$S" certus > "$TMPD/$n.certus" 2>&1
    python3 -I tools/searchrank/check.py "$S" zzqq > "$TMPD/$n.zzqq" 2>&1
    python3 -I tools/searchrank/check.py "$S" notes > "$TMPD/$n.notes" 2>&1
done

D="$TMPD/new"
[ "$(val $D.certus first_app)" = "Certus" ] && ok "certus: the first row is the app Certus" \
    || bad "certus: first row is '$(val $D.certus first_app)'"
[ "$(val $D.certus apps)" = "Certus|Ac Certus Pad|Abcertus|Aa Reader" ] \
    && ok "certus: exact, word start, substring, description" \
    || bad "certus: app order is '$(val $D.certus apps)'"
[ -n "$(val $D.certus files)" ] && grep -q 'apps=4' "$D.certus" \
    && ok "certus: the file hit comes after all four apps" \
    || bad "certus: file hit missing or apps wrong: $(val $D.certus head)"
grep -q 'apps=0 .*dateien=1' "$D.zzqq" && ok "no app named zzqq: only the file is listed" \
    || bad "zzqq: unexpected hits: $(val $D.zzqq head)"
grep -aq 'launcher: oeffne datei' "$D/serial.txt" && bad "Enter opened a file without any app hit" \
    || ok "Enter with no app hit opens nothing"
[ "$(val $D.notes first_app)" = "Notes Two" ] && ok "notes: the used app comes first at equal rank" \
    || bad "notes: first row is '$(val $D.notes first_app)'"
grep -aq 'launcher: use \[notes-two\] n=4' "$D/serial.txt" && ok "starting Notes Two counts the use (3 -> 4)" \
    || bad "no use count line for notes-two"
for f in 00-menu 01-certus; do [ -s "$D/$f.ppm" ] || bad "missing picture $f"; done
if [ -s "$D/00-menu.ppm" ] && [ -s "$D/01-certus.ppm" ]; then
    n=$(python3 -I tools/menualive/check.py diff "$D/00-menu.ppm" "$D/01-certus.ppm" 8 580 450 1035 | sed 's/changed=//')
    [ "${n:-0}" -gt 500 ] && ok "typing changed the menu ($n pixels)" || bad "typing changed ${n:-0} pixels"
fi

echo "== counter-proof: old ranking =="
O="$TMPD/old"
[ "$(val $O.certus first_app)" != "Certus" ] && ok "old ranking: first row is '$(val $O.certus first_app)' not Certus" \
    || bad "old ranking still put Certus first -- the test is blind"
grep -aq 'launcher: oeffne datei' "$O/serial.txt" && ok "old behaviour: Enter opened a file" \
    || bad "old behaviour did not open a file -- the test is blind"

echo
echo "SEARCHRANKUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
