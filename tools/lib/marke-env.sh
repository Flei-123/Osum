# SPDX-License-Identifier: GPL-2.0-only
_marke_env_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
. "$_marke_env_root/tools/lib/marke.sh"
marke_laden "$_marke_env_root" || exit 1
unset _marke_env_root
