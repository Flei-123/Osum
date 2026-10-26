#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: bash tools/acpi/run.sh [--only name,name] [--list]
# env: ACPI_IMG (kernel image, else built), ACPI_BASE_IMG (older image for before/after lines)
set -uo pipefail
cd "$(dirname "$0")/../.."
only=""
list=0
while [ $# -gt 0 ]; do
    case $1 in
        --only) only=$2; shift ;;
        --list) list=1 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
if [ "$list" -eq 1 ]; then
    for f in tools/acpi/sections/*.sh; do b=$(basename "$f" .sh); echo "${b#*-}"; done
    exit 0
fi
. tools/acpi/lib.sh
acpi_init
for f in tools/acpi/sections/*.sh; do
    b=$(basename "$f" .sh)
    name=${b#*-}
    if [ -n "$only" ] && [[ ",$only," != *",$name,"* ]]; then
        continue
    fi
    echo "== $name"
    ( . "$f" )
done
acpi_summary
