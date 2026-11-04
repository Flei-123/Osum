#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
exec python3 -E -s main.py "$@"
