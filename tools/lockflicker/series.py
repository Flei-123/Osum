#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "uiprof"))
import uiprof

sys.exit(uiprof.cmd_base(sys.argv[1:]))
