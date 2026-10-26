#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/publish-hp.sh <image-dir|-> "<notes>" [prog ...] [--dry]
#   Builds the kernel of the CURRENT clean commit, signs it with the OTA bundle and publishes it to
#   https://store.fleitec.com/osum/system/$HP_CHANNEL (default stable: the HP has no kanal= in /etc/ota.conf).
#   <image-dir> holds <prog>.elf for the overlay programs named after it; "-" = kernel only.
#   Then on the HP (bridge, device HP-ORIENTOS): see reports/20261026-G-updatepath.txt.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ $# -ge 2 ] || { sed -n 2,8p "$0"; exit 2; }
export CHANNEL=${HP_CHANNEL:-stable}
exec bash tools/ota/feed-dev.sh "$@"
