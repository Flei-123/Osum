#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
reg=${1:?usage: specs.sh <registry-root>}
echo "/usr/share/appreg/"
for dir in "$reg"/usr/share/appreg/*/; do
    id=$(basename "$dir")
    echo "/usr/share/appreg/$id/"
    for file in "$dir"*; do
        echo "/usr/share/appreg/$id/$(basename "$file")=$file@0644"
    done
done
