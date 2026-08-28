#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/lib/qemu.sh -- EINE STELLE, DIE SAGT, WOMIT QEMU RECHNET.
#
# Bis zu dieser Runde stand in keinem Laeufer ein `-accel`, und damit nahm
# QEMU zwangsweise TCG -- reine Softwareemulation. Auf einem Wirt mit
# /dev/kvm ist das der groesste einzelne Zeitfresser der Abnahme.
#
# GEMESSEN (tools/build-kernel.sh Stufe 0, -m 512, "osum nopwr", je 3 Laeufe,
# AMD EPYC 7571, 12 Kerne):
#
#     -accel tcg    4319 ms Mittel
#     -accel kvm     941 ms Mittel      -> 4,6x
#
# Diese Datei wird von den Laeufern eingebunden (`. tools/lib/qemu.sh`) und
# liefert zwei Dinge:
#
#     $OSUM_QEMU_ACCEL   "kvm" oder "tcg" -- der Name allein
#     $QEMU_X86          "qemu-system-x86_64 -accel <accel>"
#
# $QEMU_X86 ist ABSICHTLICH eine Variable und keine Shell-Funktion: fast
# jeder Aufruf im Baum steht hinter `timeout <n>`, und `timeout` ist ein
# externes Programm -- es kann keine Shell-Funktion ausfuehren. Die
# Variable wird UNGEQUOTET expandiert (`timeout 90 $QEMU_X86 -kernel ...`);
# ihr Inhalt besteht aus drei Woertern ohne Leerzeichen darin, also ist das
# Wortsplitting hier genau das Gewuenschte und kein Versehen.
#
# ----------------------------------------------------------------------
# WER ENTSCHEIDET, IN DIESER REIHENFOLGE
#
#   1. $OSUM_ACCEL=tcg|kvm   -- ausdruecklicher Wunsch, schlaegt alles.
#      Damit laesst sich derselbe Abschnitt unter beiden Beschleunigern
#      messen, und genau dafuer ist die Variable da.
#   2. Die AUSNAHMELISTE (tools/lib/accel-ausnahmen.txt) -- Abschnitte,
#      die unter KVM nachweislich falsch messen oder fallen. Jeder
#      Eintrag hat eine Begruendung. Sie laesst sich mit
#      $OSUM_ACCEL_FORCE=1 fuer eine Messung ausschalten (NUR zum Messen,
#      nicht im Regelbetrieb).
#   3. Sonst: kvm, wenn /dev/kvm les- UND schreibbar ist und die
#      QEMU-Binaerdatei kvm ueberhaupt kennt. Andernfalls tcg.
#
# ----------------------------------------------------------------------
# WAS DIESE DATEI AUSDRUECKLICH NICHT ANFASST
#
#   tools/hv/run.sh   testet den EIGENEN Hypervisor mit `-cpu qemu64,+vmx`
#                     bzw. `+svm` und setzt `-accel tcg` selbst, hart im
#                     Quelltext. Verschachtelte Virtualisierung ist ein
#                     anderes Thema; die Runde misst ausdruecklich, dass
#                     TCG kein VT-x anbietet. Bleibt TCG.
#   tools/smp/run.sh  setzt `-accel "tcg,thread=$mode"` und MISST den
#                     Unterschied zwischen single und multi. Unter KVM
#                     gibt es diesen Unterschied nicht -- die Messung
#                     waere weg. Bleibt TCG.
#   tools/arm/run.sh  ist AArch64 auf einem x86-Wirt. Falscher Bogen,
#                     KVM ist dort gar nicht moeglich. Bleibt TCG.
#
# Diese drei stehen NICHT in der Ausnahmeliste, weil sie gar nicht erst
# umgestellt wurden: in ihrem Quelltext steht weiterhin `qemu-system-*`
# und nicht `$QEMU_X86`. Wer dort `-accel` sucht, findet es an Ort und
# Stelle.

# ----------------------------------------------------------------------
# DIE AUSNAHMELISTE
#
# Schluessel ist der VERZEICHNISNAME unter tools/ bzw. tests/ (also das,
# was `basename $(dirname $0)` liefert): "k16", "net", "theme" ...
#
# Ein Eintrag heisst: dieser Abschnitt laeuft auf TCG, obwohl KVM da ist.
# Jeder Eintrag braucht eine Begruendung mit Datum und Messung. Wer einen
# Eintrag entfernt, muss den Abschnitt unter KVM gruen gemessen haben.

osum__accel_liste() {
    if [ -n "${OSUM_ACCEL_LISTE:-}" ]; then printf '%s' "$OSUM_ACCEL_LISTE"; return; fi
    printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/accel-ausnahmen.txt"
}

osum__accel_ausnahme() { # <schluessel> -> 0 wenn in der Liste
    local key=$1 datei
    datei=$(osum__accel_liste)
    [ -f "$datei" ] || return 1
    # Format je Zeile:  <schluessel><Leerzeichen><Begruendung>
    # Zeilen, die mit # anfangen, und leere Zeilen zaehlen nicht.
    grep -qE "^[[:space:]]*${key}([[:space:]]|\$)" "$datei"
}

osum__accel_grund() { # <schluessel> -> die Begruendung auf stdout
    local key=$1 datei
    datei=$(osum__accel_liste)
    [ -f "$datei" ] || return 0
    sed -n "s/^[[:space:]]*${key}[[:space:]]\\+//p" "$datei" | head -1
}

# ----------------------------------------------------------------------
# KANN DIESER WIRT KVM?

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

    # Ausdruecklicher Wunsch schlaegt die Ausnahmeliste -- aber wenn der
    # Abschnitt auf der Liste steht und trotzdem auf KVM gezwungen wird,
    # soll das im Protokoll stehen. Sonst wundert sich der Naechste, warum
    # ein bekannter Fall wieder rot ist.
    if [ "$OSUM_QEMU_ACCEL" = kvm ] && [ -n "$key" ] \
       && osum__accel_ausnahme "$key"; then
        OSUM_ACCEL_GRUND="$OSUM_ACCEL_GRUND (STEHT AUF DER AUSNAHMELISTE: $(osum__accel_grund "$key"))"
    fi

    QEMU_X86="qemu-system-x86_64 -accel $OSUM_QEMU_ACCEL"
    export OSUM_QEMU_ACCEL QEMU_X86 OSUM_ACCEL_GRUND
}

# Beim Einbinden gleich waehlen. Der Schluessel kommt aus dem Pfad des
# aufrufenden Skripts: tools/k16/run.sh -> "k16", tests/theme/run.sh ->
# "theme". Laesst sich mit $OSUM_ACCEL_KEY ueberschreiben, fuer Skripte,
# die anders heissen als ihr Abschnitt (tools/tunnel/kosten.sh -> tunnel).
osum__key_aus_pfad() {
    local p=${OSUM_ACCEL_KEY:-}
    [ -n "$p" ] && { printf '%s' "$p"; return; }
    p=${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-$0}}
    p=$(cd "$(dirname "$p")" 2>/dev/null && pwd)
    printf '%s' "$(basename "${p:-.}")"
}

osum_accel_waehlen "$(osum__key_aus_pfad)"

# Eine Zeile ins Protokoll, damit in JEDEM Laeuferlog steht, womit
# gerechnet wurde. Ohne die Zeile ist eine Zeitangabe wertlos.
[ "${OSUM_ACCEL_STILL:-0}" = "1" ] || \
    echo "accel: $OSUM_QEMU_ACCEL ($OSUM_ACCEL_GRUND)"
