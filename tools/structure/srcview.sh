#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
for f in "$@"; do
    if [ -d "${f%.fi}" ] && [ "${f%.fi}" != "$f" ] && ls "${f%.fi}"/*.fi >/dev/null 2>&1; then
        bash tools/structure/catprog.sh "$f"
    else
        cat "$f"
    fi
done
