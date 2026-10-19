#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/benchfull/run.sh -- NIGHTLY performance gate: builds its own ODB=1 image (~9 min), measures 3 runs + idle port-I/O trace
# (tools/bench/measure.sh, ~12 min) and checks every number against tools/bench/budgets.json. Run under /root/jarvis/bin/heavy.
cd "$(dirname "$0")/../.." || exit 2
exec bash tools/bench/gate.sh "$@"
