#!/usr/bin/env bash
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WD=${1:?workdir}
APP_PKGS=$(cat "$HERE/linuxcompat-packages.txt") APP_TREES=$(cat "$HERE/linuxcompat-trees.txt") APP_HOOK="$HERE/linuxcompat-build.sh" exec bash "$HERE/prep-apps.sh" "$WD"
