#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
exec bash kernel/user/certus/build.sh "$1"
