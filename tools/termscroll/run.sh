#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/termscroll/run.sh -- gate wrapper for the terminal scrollback check (tools/term/scroll.sh, r838).
cd "$(dirname "$0")/../.."
exec bash tools/term/scroll.sh "$@"
