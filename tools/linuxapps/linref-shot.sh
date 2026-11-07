#!/usr/bin/env bash
set -uo pipefail
WD=${1:?workdir from prep-firefox.sh}
URL=${2:?page url}
RUNS=${3:-6}
ok=0
for i in $(seq 1 "$RUNS"); do
    out=$(bash "$WD/bwfx.sh" /bin/sh -c "mkdir -p /tmp/p; echo 'user_pref(\"gfx.webrender.software\", true);' > /tmp/p/user.js; timeout 90 /usr/bin/firefox --headless --screenshot /tmp/x.png --profile /tmp/p '$URL' >/dev/null 2>&1; echo \"rc=\$? png=\$(wc -c < /tmp/x.png 2>/dev/null)\"" 2>&1 | tail -1)
    echo "run $i: $out"
    case "$out" in *"png=0"*|*"png="|*"png= "*) ;; *) ok=$((ok + 1)) ;; esac
done
echo "LINREF-SHOT: $ok of $RUNS produced a png"
[ "$ok" -eq "$RUNS" ]
