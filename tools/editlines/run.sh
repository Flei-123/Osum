#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.."
MODE=${1:-fix}
D=$(mktemp -d)
BAK=$D/fuied.bak
cleanup() {
    [ -f "$BAK" ] && cp "$BAK" kernel/user/fuied.fi
    rm -rf "$D"
}
trap cleanup EXIT
if [ "$MODE" = nofix ]; then
    cp kernel/user/fuied.fi "$BAK"
    python3 - <<'P'
p = "kernel/user/fuied.fi"
s = open(p, encoding="latin-1").read()
a = "        tas(t, TS_DIRTY, 1)\n        ta_sel_clear(t)\n        ta_follow(t)\n"
assert s.count(a) == 1
s = s.replace(a, "        tas(t, TS_DIRTY, 1)\n        ta_follow(t)\n")
open(p, "w", encoding="latin-1").write(s)
P
fi
python3 tools/editlines/mkscript.py 24 tools/editlines/gui.txt > "$D/script.txt"
bash tools/design/eh6.sh "$D/out" accel=kvm drehbuch="$D/script.txt" moreprogs=nedit > "$D/run.log" 2>&1
if [ ! -f "$D/out/end.ppm" ]; then
    echo "FAIL: no screenshot"
    tail -15 "$D/run.log"
    exit 1
fi
cp "$D/out/end.ppm" "${EDITLINES_KEEP:-/dev/null}" 2>/dev/null
if [ "$MODE" = nofix ]; then
    python3 -I tools/editlines/check.py "$D/out/end.ppm" expect-fail
else
    python3 -I tools/editlines/check.py "$D/out/end.ppm" expect-ok
fi
