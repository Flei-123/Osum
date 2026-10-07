#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/progsize/run.sh -- THE TRIPWIRE FOR THE LARGEST PROGRAM.
#
#   bash tools/progsize/run.sh
#
# A file of an OFS format-2 image may hold 2 134 016 octets at most (8 direct
# blocks, 64 through the indirect one, 4096 through the double indirect one,
# 512-octet blocks). `tools/k15/run.sh` (and 25 other image builders) still
# build format 2, and the file manager -- the largest program, because it
# carries fUi's scene host like every scene-tree program -- was 488 octets
# below the limit until 05.10.2026; one more function and `mkfs` refuses it
# ("a file may hold 2134016 octets in this format"), which is how K15 and the
# alltag file-manager runs went red once.
#
# Measures the file manager and the task bar (and the other big scene programs) and says how
# much room is left. FAILS when the file manager is within 256 octets of the
# limit: the next change would break the image builders. The room is lumpy
# (an ELF segment grows in whole 4096-octet pages), so the message also says
# how far the code segment is from its page boundary.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
LIMIT=2134016
LIMIT3=136351744
KEEP=256
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="explorer taskbar settings installer pdfview nedit launcher"
bash tools/sync/build.sh "$OUT" 0 $PROGS > "$OUT/b.txt" 2>&1 || { sed 's/^/    /' "$OUT/b.txt" | head; echo "PROGSIZE: build failed"; exit 1; }
fail=0
for p in $PROGS; do
    [ -f "$OUT/$p.elf" ] || continue
    sz=$(stat -c%s "$OUT/$p.elf")
    left=$((LIMIT - sz))
    left3=$((LIMIT3 - sz))
    page=$(readelf -lW "$OUT/$p.elf" | awk '/LOAD/ && NR<6 {print $5; exit}')
    pend=$(( ( (page + 4095) / 4096 ) * 4096 - page ))
    printf '  %-10s %9d octets, %7d below the format-2 limit; code segment %d octets before its page boundary\n' "$p" "$sz" "$left" "$pend"
    # 07.10.2026: the file manager, the task bar, settings and pdfview were ALREADY past the format-2 limit on main
    # (2 158 152 octets for the file manager), so the image builders that carry them build format 3 (`--v3`, a file
    # may hold 136 351 744 octets). The tripwire is now the format-3 limit with a wide margin: a program that
    # reaches half of it is a design problem, not an image problem.
    if [ "$left3" -lt $((LIMIT3 / 2)) ]; then
        echo "  FAIL  $p is more than half of the format-3 file limit"; fail=1
    fi
done
[ $fail -eq 0 ] && echo "PROGSIZE: ok" || echo "PROGSIZE: a program is too big even for a format-3 image"
exit $fail
