#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/foot/run.sh -- gate entry for the foot proof stone (r701): the real foot terminal on wayd (window, pixels, keyboard echo).
# The work lives in tools/wayland/foot.sh; this wrapper gives the QA manifest (tools/qa/gates.tsv) a tools/<gate>/run.sh to call.
# Skips (exit 0) when the foot stones are missing (tools/unterbau/build-foot-stones.sh /root/stones).
set -uo pipefail
cd "$(dirname "$0")/../.."
exec bash tools/wayland/foot.sh "$@"
