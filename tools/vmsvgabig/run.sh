#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgabig/run.sh -- gate entry for vmsvgabig (r1139); the check itself lives in tools/vmsvgaresize/big.sh.
exec bash "$(dirname "$0")/../vmsvgaresize/big.sh" "$@"
