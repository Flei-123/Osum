#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
URL=${ROOTS_BUNDLE_URL:-https://curl.se/ca/cacert.pem}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
curl -fsS -m 60 -o "$T/cacert.pem" "$URL"
curl -fsS -m 30 -o "$T/cacert.pem.sha256" "$URL.sha256"
want=$(awk '{print $1; exit}' "$T/cacert.pem.sha256")
have=$(sha256sum "$T/cacert.pem" | awk '{print $1}')
[ "$want" = "$have" ] || { echo "refresh: bundle digest mismatch ($want vs $have)" >&2; exit 1; }
stamp=$(sed -n 's/^## Certificate data from Mozilla as of: //p' "$T/cacert.pem" | head -1)
python3 tools/hwnet/mkroots.py "$T/subset.pem" "$T/cacert.pem" "# source: curl.se cacert.pem, Mozilla as of $stamp, sha256 $have"
cp "$T/subset.pem" tools/roots/mozilla-subset.pem
printf '%s  cacert.pem  # Mozilla as of %s\n' "$have" "$stamp" > tools/roots/bundle.sha256
echo "refresh: pinned $have ($stamp)"
