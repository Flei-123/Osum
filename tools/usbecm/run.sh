#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Gate "usbecm": USB CDC-ECM network driver end to end (script lives in tools/usbnet/qemu.sh).
exec bash "$(dirname "$0")/../usbnet/qemu.sh" "$@"
