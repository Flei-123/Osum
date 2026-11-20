#!/usr/bin/env bash
set -uo pipefail
WD=${1:?workdir}
HERE=$(cd "$(dirname "$0")" && pwd)
APP_PKGS=${APP_PKGS:-"wine"} APP_TREES="/usr/share/wine" bash "$HERE/prep-apps.sh" "$WD"
