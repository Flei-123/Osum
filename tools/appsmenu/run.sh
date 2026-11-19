#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }

HIDDEN_BUNDLES="cliphist disks launcher nedit osk run snip viewer welcome widgets"
VISIBLE_BUNDLES="certus charmap editor explorer firefox installer pdfview settings store taskmgr terminal trashbin vault vplay"
HIDDEN_PACKAGES="widgetdemo netview themetest top netmon zip lock"
PROCESS_ALIASES="xfx freeviewer-host runbox snipt vaultui"

for b in $HIDDEN_BUNDLES; do
    grep -qx 'menu=hidden' "assets/apps/$b.osp/INFO" && ok "bundle $b is hidden from the program list" || bad "bundle $b is listed"
done
for b in $VISIBLE_BUNDLES; do
    grep -qx 'menu=hidden' "assets/apps/$b.osp/INFO" && bad "bundle $b must stay listed" || ok "bundle $b stays listed"
done
for p in $HIDDEN_PACKAGES; do
    grep -q "^$p|.*|hidden\$" tools/loader/apps.tab && ok "package $p is hidden from the program list" || bad "package $p is listed"
done
for f in assets/apps/*.osp; do
    n=$(basename "$f" .osp)
    case " $HIDDEN_BUNDLES $VISIBLE_BUNDLES " in *" $n "*) ;; *) bad "bundle $n is not in the inventory of this gate";; esac
done

python3 -I tools/appreg/build.py "$ROOT" "$T/reg" > "$T/reg.log" 2>&1 && ok "registry builds" || { bad "registry build"; cat "$T/reg.log"; }
for a in $PROCESS_ALIASES; do
    d="$T/reg/usr/share/appreg/$a"
    [ -s "$d/symbol" ] && [ -s "$d/title" ] && ok "process $a resolves to a symbol and a title ($(head -1 "$d/title"))" || bad "process $a has no symbol or title"
done
[ "$(head -1 "$T/reg/usr/share/appreg/xfx/title")" = Firefox ] && ok "xfx is shown as Firefox" || bad "xfx title"
[ "$(head -1 "$T/reg/usr/share/appreg/freeviewer-host/title")" = "Remote control" ] && ok "freeviewer-host is shown as Remote control" || bad "freeviewer-host title"

mkdir -p "$T/c"; cp -a tools assets pakete "$T/c/"; sed -i '/^xfx\t/d' "$T/c/tools/appreg/alias.tsv"
python3 -I tools/appreg/build.py "$T/c" "$T/creg" > /dev/null 2>&1
[ ! -e "$T/creg/usr/share/appreg/xfx" ] && ok "counter-proof: without the alias row xfx has no registry entry" || bad "counter-proof: xfx entry exists without alias row"
echo "APPSMENU: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
