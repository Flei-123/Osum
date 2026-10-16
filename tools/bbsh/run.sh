#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# gate wrapper (gates.tsv convention tools/<gate>/run.sh)
exec bash "$(dirname "$0")/../usbimg/bbsh.sh" "$@"
