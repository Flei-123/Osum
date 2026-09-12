# SPDX-License-Identifier: GPL-2.0-only
# tools/lib/marke.sh -- die Marke fuer Skripte. EINE Stelle, wie im Kern.
#
#   . tools/lib/marke.sh     (aus dem Wurzelverzeichnis des Repos)
#   echo "$MARKE_PRODUKT"    -> OrientOS
#   echo "$MARKE_DATEI"      -> orientos      (fuer Dateinamen)
#
# Dasselbe Verhalten wie `kernel/brand.fi` und wie die Vorlage
# `/root/projects/freeviewer/src/brand.rs`: Vorgaben aus `marke.conf`,
# geschlagen von den Umgebungsvariablen `OSUM_MARKE_*`.
#
#   OSUM_MARKE_PRODUKT="Xoffi OS" bash tools/usbimg/build.sh /tmp/bau
#
# WARUM DAS HIER NOCHMAL STEHT UND NICHT NUR IM KERN: das Bootmenue,
# der Dateiname des Abbilds und `/etc/ota.conf` entstehen im
# BAUSKRIPT und nie im Kern. Sie muessen denselben Namen sehen, sonst
# heisst das Abbild anders als der Startschirm. Gelesen wird trotzdem
# dieselbe Datei -- es gibt keine zweite Vorgabe.
#
# ABGELEITET (nicht gespeichert, wie `reg_key()` in der Vorlage):
#   MARKE_DATEI = PRODUKT kleingeschrieben, ohne Leerzeichen und ohne
#   alles, was kein Buchstabe, keine Ziffer und kein Bindestrich ist.
#   "OrientOS" -> orientos, "Xoffi OS" -> xoffios

marke_laden() {
    local wurzel="${1:-.}"
    local conf="$wurzel/marke.conf"
    if [ ! -f "$conf" ]; then
        echo "marke.sh: $conf fehlt" >&2
        return 1
    fi
    local k v
    while IFS= read -r zeile; do
        case "$zeile" in
            ''|'#'*) continue ;;
            *=*) ;;
            *) continue ;;
        esac
        k=${zeile%%=*}
        v=${zeile#*=}
        k=$(printf '%s' "$k" | tr -d ' \t')
        v=${v%\"}; v=${v#\"}
        v=${v%\'}; v=${v#\'}
        case "$k" in
            PRODUKT|KERN|HERSTELLER|KURZ|WEB|FEED)
                eval "MARKE_$k=\$v" ;;
        esac
    done < "$conf"

    # Die Umgebung schlaegt die Datei -- der ganze Trick der Vorlage.
    local f e
    for f in PRODUKT KERN HERSTELLER KURZ WEB FEED; do
        eval "e=\${OSUM_MARKE_$f:-}"
        [ -n "$e" ] && eval "MARKE_$f=\$e"
        eval "v=\${MARKE_$f:-}"
        if [ -z "$v" ]; then
            echo "marke.sh: Feld $f fehlt in $conf" >&2
            return 1
        fi
    done

    # abgeleitet, nicht gespeichert
    MARKE_DATEI=$(printf '%s' "$MARKE_PRODUKT" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cd 'a-z0-9-')
    if [ -z "$MARKE_DATEI" ]; then
        echo "marke.sh: aus PRODUKT='$MARKE_PRODUKT' laesst sich kein" \
             "Dateiname bilden" >&2
        return 1
    fi
    export MARKE_PRODUKT MARKE_KERN MARKE_HERSTELLER MARKE_KURZ \
           MARKE_WEB MARKE_FEED MARKE_DATEI
}
