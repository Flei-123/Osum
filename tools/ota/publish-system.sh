#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/publish-system.sh <imgdir> <feeddir> <channel> [more publish_system.py args]
# Signs with the existing bundle; the passphrase comes from OSUM_SIGN_PASS or the secrets file.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ $# -ge 3 ] || { echo "usage: $0 <imgdir> <feeddir> <channel> [args]" >&2; exit 2; }
IMG=$1; FEED=$2; CH=$3; shift 3
export OSUM_SIGN_PASS=${OSUM_SIGN_PASS:-$(cat /root/.secrets/osum-ota-pass.txt)}
exec python3 tools/ota/publish_system.py "$IMG" "$FEED" "$CH" \
    --bund "${OSUM_BUND:-/root/.secrets/osum-ota-bund.json}" "$@"
