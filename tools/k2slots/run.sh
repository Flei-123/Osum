#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
cd "$(dirname "$0")/../.."
python3 tools/k2slots/check.py . "$@"
