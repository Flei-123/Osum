#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""odbc entry point: python3 tools/odbc/odbc.py --port unix:/tmp/odb.sock info"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from odb.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
