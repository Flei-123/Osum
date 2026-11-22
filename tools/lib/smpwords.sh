#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

smp_boot_words() {
    local cpus=${1:-1} words=${2:-}
    case " $words " in *" smpfrueh "*) printf '%s' "$words"; return ;; esac
    if [ "$cpus" -gt 1 ]; then words="smpfrueh${words:+ $words}"; fi
    printf '%s' "$words"
}
