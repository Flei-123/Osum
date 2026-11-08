#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
find kernel lib -name '*.fi' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-
