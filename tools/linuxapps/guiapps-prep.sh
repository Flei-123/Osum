#!/usr/bin/env bash
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WD=${1:?workdir}
APP_PKGS=$(cat "$HERE/guiapps-packages.txt") APP_TREES=$(cat "$HERE/guiapps-trees.txt") exec bash "$HERE/prep-apps.sh" "$WD"
