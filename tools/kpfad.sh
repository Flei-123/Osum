
if [[ -z ${KPFAD_WURZEL:-} ]]; then
    KPFAD_WURZEL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi
declare -A _KPFAD_CACHE 2>/dev/null || true

kfi() {
    local name=${1:-}
    if [[ -z $name ]]; then
        echo "kfi: ohne Modulnamen aufgerufen" >&2
        return 1
    fi
    if [[ -n ${_KPFAD_CACHE[$name]:-} ]]; then
        echo "${_KPFAD_CACHE[$name]}"
        return 0
    fi
    local p
    p=$(bash "$KPFAD_WURZEL/tools/kfind.sh" "$name") || return 1
    _KPFAD_CACHE[$name]=$p
    echo "$p"
}
