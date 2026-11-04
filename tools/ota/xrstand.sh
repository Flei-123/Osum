#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
exec bash "$(dirname "$0")/standpkg.sh" xremote "${1:?usage: xrstand.sh <stand-dir>}"
