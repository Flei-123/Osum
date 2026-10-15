#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Gate entry for W-AX201 M1; the test itself lives in tools/wlan/iwl.{fi,sh}.
exec bash "$(dirname "$0")/../wlan/iwl.sh" "$@"
