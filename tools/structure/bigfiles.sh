#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
cd "$(dirname "$0")/../.."
LIMIT=${1:-3000}
echo "| lines | file |"
echo "|---:|---|"
git ls-files '*.fi' | xargs wc -l | grep -v ' total$' | sort -rn | awk -v l="$LIMIT" '$1>l {printf "| %d | `%s` |\n", $1, $2}'
