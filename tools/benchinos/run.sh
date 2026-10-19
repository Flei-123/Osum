#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/benchinos/run.sh -- gate entry for the in-OS bench check (the script is tools/bench/inos.sh).
cd "$(dirname "$0")/../.." || exit 2
exec bash tools/bench/inos.sh "$@"
