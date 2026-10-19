#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/run.sh -- QUICK performance gate (seconds, no VM): budgets.json vs the committed baseline + 1.5x counter-proof.
# The measuring runner is tools/bench/measure.sh; the NIGHTLY full gate (own ODB=1 image + 3 runs + port-I/O trace) is tools/benchfull/run.sh.
cd "$(dirname "$0")/../.." || exit 2
exec bash tools/bench/gate.sh --static "$@"
