#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/lib/userprog.sh -- EIN Programm aus kernel/user/ bauen, mit dem
# Profil, das IN DER WURZELDATEI STEHT.
#
# RUNDE GRUNDLINIE (A-016). Seit Runde 31 kommen die Bedienelemente aus
# fUi, fUi rechnet in `f64` und benutzt `std.rt`, und beides ist unter
# `profile kernel` gesperrt. Die sieben Programme mit Oberflaeche
# (desktop, taskbar, settings, launcher, explorer, widgetdemo, taskmgr)
# tragen deshalb `profile app` in ihrer ersten Zeile.
#
# DREISSIG LAEUFER HABEN DAS NICHT GELESEN. Sie riefen firnc ohne
# `--profile` auf, bekamen das Vorgabeprofil `kernel` und daran:
#
#     error: the module 'std.rt' belongs to the standard library and is
#     not available in profile 'kernel'   (vendor/firn/lib/fui/render.fi)
#
# In NETVIEW sind das allein sechs der sechsunddreissig Fehler ("the
# graphical userland does not build"). Es ist kein Fehler des Systems --
# der Kern baut, der Stick baut --, sondern einer der Laeufer.
#
# tools/look/shot.sh macht es seit Runde 31 richtig, tools/usbimg/build.sh
# hat es in Runde ABBILD (8d81950) nachgezogen. Diese Datei ist dieselbe
# Regel an EINER Stelle, damit die naechste Umstellung nicht wieder
# dreissig Dateien einzeln braucht:
#
#   * DAS PROFIL WIRD GELESEN, NICHT GETIPPT. Wessen Wurzeldatei
#     `profile app` sagt, wird mit `--profile=app` uebersetzt.
#   * KEIN crt.o IM PROFIL app. Firns eigenes `_start` ist dann schon im
#     Objekt; ein zweites aus crt.o gibt "multiple definition of `_start`"
#     -- das ist A-015.
#   * `-c` IM PROFIL app. Ohne das versucht firnc gleich zu binden und
#     sagt "input file is the same as output file"; im Profil `kernel`
#     faellt das nicht auf, weil dort ohnehin nur ein Objekt entsteht.
#
# GEBRAUCH:
#     . tools/lib/userprog.sh
#     up_build <cc> <programm> <objekt> <elf> <crt.o> <user.ld> <stufe> [fehlerdatei]
#
# Rueckgabe 0 = gebaut. Bei 1 steht der Text des Uebersetzers bzw. des
# Binders in der Fehlerdatei (Vorgabe <objekt>.err).

# up_profile <wurzeldatei> -> druckt "app" oder "kernel"
up_profile() {
    if grep -qa '^profile app' "$1" 2>/dev/null; then
        printf 'app\n'
    else
        printf 'kernel\n'
    fi
}

# up_build <cc> <prog> <obj> <elf> <crt> <uld> <stufe> [err]
up_build() {
    local cc="$1" prog="$2" obj="$3" elf="$4" crt="$5" uld="$6" stufe="$7"
    local err="${8:-$3.err}"
    local src="kernel/user/$prog.fi"
    local prof="" usecrt="$crt"

    [ -f "$src" ] || { echo "up_build: $src fehlt" > "$err"; return 1; }

    if [ "$(up_profile "$src")" = app ]; then
        prof="--profile=app"
        usecrt=""
    fi

    # shellcheck disable=SC2086
    "$cc" $prof -c "$src" -o "$obj" > "$err" 2>&1 || return 1
    ld -T "$uld" --defsym=USER_ENTRY="_F$stufe.u_start" \
        -o "$elf" $usecrt "$obj" >> "$err" 2>&1 || return 1
    strip --strip-all "$elf" 2>/dev/null
    return 0
}
