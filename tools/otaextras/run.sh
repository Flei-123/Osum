#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
PATH_LIMIT=60

mkdir -p "$T/img"
python3 -I tools/appreg/build.py "$ROOT" "$T/img/appreg" > "$T/reg.log" 2>&1 && ok "registry builds" || { cat "$T/reg.log"; bad "registry build"; }

stage() { bash tools/ota/stage-extras.sh "$1" "$2" > "$2.log" 2>&1; }

stage "$T/img" "$T/x1" && ok "stage-extras succeeds" || { cat "$T/x1.log"; bad "stage-extras"; }
cmp -s assets/osum-icons.ttf "$T/x1/lib/icons.ttf" && ok "icon font staged as /lib/icons.ttf" || bad "icon font missing or different"

apps=0; wrong=0
for dir in "$T/img/appreg/usr/share/appreg"/*/; do
    id=$(basename "$dir")
    apps=$((apps+1))
    cmp -s "$dir/symbol" "$T/x1/usr/share/appreg/$id/symbol" || wrong=$((wrong+1))
done
[ "$apps" -ge 10 ] && [ "$wrong" = 0 ] && ok "registry staged for $apps apps, symbols identical" || bad "registry staging: $apps apps, $wrong differ"

long=$(cd "$T/x1" && find . -type f | sed 's#^\.##' | awk -v m=$PATH_LIMIT 'length($0) > m' | wc -l)
[ "$long" = 0 ] && ok "all staged paths fit $PATH_LIMIT characters" || bad "$long staged paths too long"
bad_chars=$(cd "$T/x1" && find . -type f | sed 's#^\.##' | grep -vcE '^/(apps|etc|usr/share|lib)/[A-Za-z0-9._/-]+$')
[ "$bad_chars" = 0 ] && ok "all staged paths pass the publisher path rule" || bad "$bad_chars staged paths rejected by the publisher"

: > "$T/empty.txt"
OVERLAY_ASSETS="$T/empty.txt" stage "$T/img" "$T/x2"
[ -e "$T/x2/lib/icons.ttf" ] && bad "counter-proof: empty asset list still stages the font" || ok "counter-proof: empty asset list stages no font"

mkdir -p "$T/noreg"
stage "$T/noreg" "$T/x3" && bad "counter-proof: missing registry not detected" || ok "counter-proof: missing registry fails the staging"

echo "otaextras: $pass ok, $fail fail"
[ "$fail" = 0 ]
