#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/appsmerge/run.sh [tree] -- static gate for the Editor merge (16.10.2026): ONE windowed Editor in the start menu.
#   * assets/apps/editor.osp starts /bin/nedit, name=Editor; no assets/apps/nedit.osp ("Editor+") any more
#   * the console editor /bin/edit is still built into the image (PROGS) but has no start menu bundle
#   * the image check list (PFLICHT) names /apps/editor.osp/INFO and no /apps/nedit.osp/*
#   * the Explorer opens text/source files with /bin/nedit (is_text_file)
# Counter-proof: run it on an unpacked old tree (`git archive origin/main~N | tar -x -C dir; bash run.sh dir`) -> FAIL.
set -uo pipefail
T=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$T" || exit 2
ok=0; bad=0
chk() { if eval "$2"; then ok=$((ok+1)); echo "  OK    $1"; else bad=$((bad+1)); echo "  FAIL  $1"; fi; }
chk "editor.osp starts /bin/nedit" "grep -qa '^/bin/nedit' assets/apps/editor.osp/start.txt"
chk "editor.osp is named Editor" "grep -qa '^name=Editor\$' assets/apps/editor.osp/INFO"
chk "no nedit.osp bundle (no Editor+)" "[ ! -e assets/apps/nedit.osp ]"
chk "no console bundle for /bin/edit" "! grep -qa '^/bin/edit' assets/apps/*/start.txt"
chk "/bin/edit stays in the image program list" "grep -a 'PROGS=\${PROGS:-' -A2 tools/usbimg/build.sh | grep -qaw edit"
chk "image check list: editor.osp/INFO present" "grep -qa '/apps/editor.osp/INFO' tools/usbimg/build.sh"
chk "image check list: no nedit.osp path" "! grep -a '^/bin/nedit' tools/usbimg/build.sh | grep -qa 'nedit.osp'"
chk "explorer: text files open in /bin/nedit" "grep -qa 'fn is_text_file' kernel/user/explorer.fi && grep -qa '/bin/nedit' kernel/user/explorer.fi"
chk "dell_walk has no separate Editor+ entry" "! grep -qa 'name=\"Editor+\"' tools/qa/dell_walk.py"
echo "APPSMERGE: $ok ok, $bad fail"
[ "$bad" = 0 ]
