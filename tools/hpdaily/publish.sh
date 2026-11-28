#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
target=${HPDAILY_PUBLISH_DIR:-/srv/store/osum/hpdaily}
bash "$here/bundle.sh" "$target/hpdaily.sh"
busybox sh -n "$target/hpdaily.sh"
sha256sum "$target/hpdaily.sh"
