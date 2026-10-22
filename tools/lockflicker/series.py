#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/lockflicker/series.py <run dir> <base> <prefix> <px> <py> [max_px] -- thin wrapper over tools/uiprof/uiprof.py (MON-4)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "uiprof"))
import uiprof

sys.exit(uiprof.cmd_base(sys.argv[1:]))
