#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
cd "$(dirname "$0")/../.."
exec bash tools/usbimg/joinprobe.sh "$@"
