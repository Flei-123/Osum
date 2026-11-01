
osum_sperre() {
    local ziel=$1
    [[ -n $ziel ]] || return 0
    local voll
    voll=$(mkdir -p "$ziel" && cd "$ziel" && pwd) || return 0
    case ":${OSUM_SPERREN:-}:" in
        *":$voll:"*) return 0 ;;
    esac
    local fd
    exec {fd}>"$voll.sperre"
    if ! flock -n "$fd"; then
        echo "LOCK: $voll is currently used by another run." >&2
        echo "        Pass your own directory as an argument, or wait." >&2
        echo "        (Halter: $(cat "$voll.sperre.wer" 2>/dev/null || echo unbekannt))" >&2
        exit 75
    fi
    printf 'pid %s, Baum %s, seit %s\n' "$$" "$(pwd)" "$(date '+%F %T')" \
        > "$voll.sperre.wer"
    export OSUM_SPERREN="${OSUM_SPERREN:-}:$voll"
}
