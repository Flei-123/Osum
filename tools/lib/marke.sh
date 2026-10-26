# SPDX-License-Identifier: GPL-2.0-only

marke_laden() {
    local root="${1:-.}"
    local conf="$root/marke.conf"
    if [ ! -f "$conf" ]; then
        echo "marke.sh: $conf is missing" >&2
        return 1
    fi
    local k v line
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
            *=*) ;;
            *) continue ;;
        esac
        k=${line%%=*}
        v=${line#*=}
        k=$(printf '%s' "$k" | tr -d ' \t')
        v=${v%\"}; v=${v#\"}
        v=${v%\'}; v=${v#\'}
        case "$k" in
            PRODUKT|KERN|HERSTELLER|KURZ|WEB|FEED)
                eval "MARKE_$k=\$v" ;;
        esac
    done < "$conf"

    local f e
    for f in PRODUKT KERN HERSTELLER KURZ WEB FEED; do
        eval "e=\${OSUM_MARKE_$f:-}"
        [ -n "$e" ] && eval "MARKE_$f=\$e"
        eval "v=\${MARKE_$f:-}"
        if [ -z "$v" ]; then
            echo "marke.sh: field $f is missing in $conf" >&2
            return 1
        fi
    done

    MARKE_DATEI=$(printf '%s' "$MARKE_PRODUKT" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cd 'a-z0-9-')
    if [ -z "$MARKE_DATEI" ]; then
        echo "marke.sh: no file name can be derived from PRODUKT='$MARKE_PRODUKT'" >&2
        return 1
    fi
    MARKE_ROOT=$(cd "$root" && pwd)
    export MARKE_PRODUKT MARKE_KERN MARKE_HERSTELLER MARKE_KURZ \
           MARKE_WEB MARKE_FEED MARKE_DATEI MARKE_ROOT
}

marke_render() {
    python3 "$MARKE_ROOT/tools/marke/brandrender.py" "$MARKE_ROOT/marke.conf" "$1" "$2"
}
