#!/usr/bin/env bash
DEVPARTS_CONF=${DEVPARTS_CONF:-$(dirname "${BASH_SOURCE[0]}")/devparts.conf}
devparts() { awk -v k="$1" '$1 == k { sub(/^[^ ]+ /, ""); print }' "$DEVPARTS_CONF"; }
