# SPDX-License-Identifier: GPL-2.0-only
# tools/lib/sperre.sh -- A-024: EIN AUSGABEORDNER, EIN LAUF.
#
#   . tools/lib/sperre.sh
#   osum_sperre "$OUT"
#
# WARUM ES DAS GIBT. Viele Laeufer legen ihre Platten und Bilder unter
# einem festen Standardpfad ab (`OUT=${1:-/tmp/abnahme}` und 31 weitere).
# Am 23.09.2026 liefen zwei Runden gleichzeitig `tools/install/abnahme.sh`
# ohne Argument; beide schrieben dieselbe `platte.img`, und die zweite
# mass **16/17 statt 35/0** -- kein einziger der 17 Fehler war echt.
#
# WARUM NICHT EINFACH ANDERE PFADE. Die Standardpfade sind eine
# Schnittstelle: `tools/loader/*.sh` etwa teilen sich `/tmp/laden`, und
# ein Skript liest dort, was das andere gebaut hat. Wer die Pfade je
# Lauf verschiebt, zerbricht das still. Also bleibt der Pfad, und ein
# zweiter Lauf auf DENSELBEN Ordner wird ABGEWIESEN, laut und mit
# Beendigungscode 75 (EX_TEMPFAIL) -- statt falsch zu messen.
#
# VERSCHACHTELT IST ERLAUBT. Ruft ein Lauf, der die Sperre haelt, einen
# Helfer auf, der denselben Ordner sperren will (derselbe Lauf, nur eine
# Ebene tiefer), geht das durch: die gehaltenen Ordner stehen in
# OSUM_SPERREN und werden an Kindprozesse vererbt.
#
# Die Sperre ist `flock` auf "<ordner>.sperre" und faellt mit dem Prozess
# -- ein abgestuerzter Lauf hinterlaesst keine Leiche, die den naechsten
# blockiert.

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
        echo "SPERRE: $voll wird gerade von einem anderen Lauf benutzt." >&2
        echo "        Eigenen Ordner als Argument angeben, oder warten." >&2
        echo "        (Halter: $(cat "$voll.sperre.wer" 2>/dev/null || echo unbekannt))" >&2
        exit 75
    fi
    printf 'pid %s, Baum %s, seit %s\n' "$$" "$(pwd)" "$(date '+%F %T')" \
        > "$voll.sperre.wer"
    export OSUM_SPERREN="${OSUM_SPERREN:-}:$voll"
}
