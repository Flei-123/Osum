#!/usr/bin/env bash
#
# GEMESSEN (tools/build-kernel.sh Stufe 0, -m 512, "osum nopwr", je 3 Laeufe,
# AMD EPYC 7571, 12 Kerne):
#
#     -accel tcg    4319 ms Mittel
#     -accel kvm     941 ms Mittel      -> 4,6x
#
# ----------------------------------------------------------------------
# WER ENTSCHEIDET, IN DIESER REIHENFOLGE
#

# ----------------------------------------------------------------------
# DIE AUSNAHMELISTE
#

osum__accel_liste() {
    if [ -n "${OSUM_ACCEL_LISTE:-}" ]; then printf '%s' "$OSUM_ACCEL_LISTE"; return; fi
    printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/accel-ausnahmen.txt"
}

osum__accel_ausnahme() { # <schluessel> -> 0 wenn in der Liste
    local key=$1 datei
    datei=$(osum__accel_liste)
    [ -f "$datei" ] || return 1
    grep -qE "^[[:space:]]*${key}([[:space:]]|\$)" "$datei"
}

osum__accel_grund() { # <schluessel> -> die Begruendung auf stdout
    local key=$1 datei
    datei=$(osum__accel_liste)
    [ -f "$datei" ] || return 0
    sed -n "s/^[[:space:]]*${key}[[:space:]]\\+//p" "$datei" | head -1
}

osum_kvm_da() {
    [ -r /dev/kvm ] && [ -w /dev/kvm ] || return 1
    command -v qemu-system-x86_64 >/dev/null 2>&1 || return 1
    qemu-system-x86_64 -accel help 2>/dev/null | grep -qx 'kvm' || return 1
    return 0
}

# ----------------------------------------------------------------------
# DIE WAHL

osum_accel_waehlen() {
    local key=${1:-}
    local wunsch=${OSUM_ACCEL:-auto}

    case "$wunsch" in
        tcg)
            OSUM_QEMU_ACCEL=tcg
            OSUM_ACCEL_GRUND="OSUM_ACCEL=tcg"
            ;;
        kvm)
            if osum_kvm_da; then
                OSUM_QEMU_ACCEL=kvm
                OSUM_ACCEL_GRUND="OSUM_ACCEL=kvm"
            else
                OSUM_QEMU_ACCEL=tcg
                OSUM_ACCEL_GRUND="OSUM_ACCEL=kvm verlangt, aber /dev/kvm ist nicht nutzbar"
            fi
            ;;
        auto|"")
            if [ -n "$key" ] && [ "${OSUM_ACCEL_FORCE:-0}" != "1" ] \
               && osum__accel_ausnahme "$key"; then
                OSUM_QEMU_ACCEL=tcg
                OSUM_ACCEL_GRUND="Ausnahmeliste: $(osum__accel_grund "$key")"
            elif osum_kvm_da; then
                OSUM_QEMU_ACCEL=kvm
                OSUM_ACCEL_GRUND="/dev/kvm ist da"
            else
                OSUM_QEMU_ACCEL=tcg
                OSUM_ACCEL_GRUND="kein nutzbares /dev/kvm"
            fi
            ;;
        *)
            echo "tools/lib/qemu.sh: OSUM_ACCEL=$wunsch kenne ich nicht" >&2
            OSUM_QEMU_ACCEL=tcg
            OSUM_ACCEL_GRUND="unbekannter Wert, tcg als Rueckfall"
            ;;
    esac

    if [ "$OSUM_QEMU_ACCEL" = kvm ] && [ -n "$key" ] \
       && osum__accel_ausnahme "$key"; then
        OSUM_ACCEL_GRUND="$OSUM_ACCEL_GRUND (STEHT AUF DER AUSNAHMELISTE: $(osum__accel_grund "$key"))"
    fi

    QEMU_X86="qemu-system-x86_64 -accel $OSUM_QEMU_ACCEL"
    export OSUM_QEMU_ACCEL QEMU_X86 OSUM_ACCEL_GRUND
}

osum__key_aus_pfad() {
    local p=${OSUM_ACCEL_KEY:-}
    [ -n "$p" ] && { printf '%s' "$p"; return; }
    p=${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-$0}}
    p=$(cd "$(dirname "$p")" 2>/dev/null && pwd)
    printf '%s' "$(basename "${p:-.}")"
}

osum_accel_waehlen "$(osum__key_aus_pfad)"

[ "${OSUM_ACCEL_STILL:-0}" = "1" ] || \
    echo "accel: $OSUM_QEMU_ACCEL ($OSUM_ACCEL_GRUND)"
