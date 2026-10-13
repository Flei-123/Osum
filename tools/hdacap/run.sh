#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hdacap/run.sh -- gate wrapper: the microphone gate lives in tools/hda/cap.sh (qa/gates.sh runs tools/<gate>/run.sh).
cd "$(dirname "$0")/../.." || exit 1
exec bash tools/hda/cap.sh "$@"
