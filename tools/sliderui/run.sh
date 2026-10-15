#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sliderui/run.sh -- r834 gate: drag and click on the Settings sliders (mouse speed, energy scrb) on the audit machine.
# Thin wrapper so tools/qa/gates.sh finds a run.sh; the test itself is tools/mouseui/slider.sh.
set -uo pipefail
cd "$(dirname "$0")/../.."
exec bash tools/mouseui/slider.sh "$@"
