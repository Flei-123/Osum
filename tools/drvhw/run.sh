#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
cd "$(dirname "$0")/../.." || exit 1
exec bash tools/drvstore/hw.sh "$@"
