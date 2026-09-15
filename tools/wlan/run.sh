#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/run.sh -- RUNDE WLAN: 802.11 OHNE EINE EINZIGE KARTE.
#
# ==================================================================
# WARUM DIESER ABSCHNITT ALS EINZIGER KEIN QEMU STARTET
# ==================================================================
#
# Jeder andere Abschnitt dieser Abnahme bootet einen Kernel. Dieser
# nicht, und der Grund ist gemessen und nicht gemeint:
#
#     $ qemu-system-x86_64 -device help | grep -icE 'wifi|802\.11|iwl'
#     2
#     267:name "athlon-v1-x86_64-cpu"
#     268:name "athlon-x86_64-cpu"
#
# QEMU hat KEIN 802.11-Geraet. Es gibt keinen `-device iwlwifi`, es gibt
# keinen Weg, einen Intel AX200 zu emulieren, und es hat auch nie einen
# gegeben. Ein Kernel in QEMU koennte also keinen einzigen
# WLAN-Rahmen erzeugen oder empfangen -- ihn zu booten wuerde nichts
# messen ausser der Bootzeit.
#
# Die ganze Begruendung, mit Zeilenzahlen und Firmwaregroessen, steht in
# `docs/WLAN-BEFUND.md`. Der Kurzfassung nach: die Haelfte von WLAN, die
# Protokoll und Krypto ist, laesst sich ohne Hardware bauen UND messen.
# Die andere Haelfte ist der Treiber, sie ist die groessere, und sie
# laesst sich auf diesem Rechner nicht einmal ansatzweise pruefen. Diese
# Runde hat die erste Haelfte gebaut und die zweite bewusst nicht
# angefangen.
#
# ==================================================================
# WAS HIER LAEUFT
# ==================================================================
#
#   1. `tools/wlan/oracle.fi` wird gebaut. Es bindet DIESELBEN
#      Dateien unter `lib/crypto/` und `lib/wlan/`, die der Kern
#      binden wird -- keine zweite Fassung, kein Nachbau. Das ist
#      dasselbe Werkzeug, das die Runden TUNNEL und UPDATE fuer
#      Ed25519 gebaut haben.
#   2. `tools/wlan/vektoren.py` misst gegen die Normen (FIPS 197,
#      RFC 3394, RFC 4493, RFC 6070, IEEE 802.11i und 802.11-2012),
#      gegen OpenSSL und -- das ist der Teil, der wirklich zaehlt --
#      gegen eine ECHTE AUFZEICHNUNG eines echten WPA2-Netzes.
#   3. `tools/wlan/fuzz.py` wirft verstuemmelte Rahmen hinein und
#      prueft unter valgrind, dass nie neben den Puffer gegriffen wird.
#
# Verwendung:  bash tools/wlan/run.sh [--schnell]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${OUT:-/tmp/wlan-run}
mkdir -p "$OUT" .probe
SCHNELL=${1:-}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# =====================================================================
echo "== 0. der Messplatz: dieselben Quelltexte, die der Kern bindet =="
# =====================================================================

# Erst der Beweis, dass QEMU nichts beitragen kann. Er steht hier und
# nicht nur im Kommentar, damit er bei jedem Lauf neu gemessen wird --
# wenn QEMU eines Tages ein 802.11-Geraet bekommt, faellt das hier auf.
if command -v qemu-system-x86_64 > /dev/null 2>&1; then
    WIFIDEV=$(qemu-system-x86_64 -device help 2>&1 \
        | sed -n '/Network devices/,/^$/p' \
        | grep -icE 'wifi|802\.11|wlan|iwl|mt79|ath[0-9]' || true)
    if [ "$WIFIDEV" = "0" ]; then
        ok "QEMU $(qemu-system-x86_64 --version | head -1 | awk '{print $4}') hat 0 WLAN-Geraete -- dieser Abschnitt kann und darf kein QEMU starten"
    else
        bad "QEMU meldet $WIFIDEV WLAN-Geraete -- dann gehoert docs/WLAN-BEFUND.md Abschnitt 5 neu geschrieben"
    fi
else
    ok "kein QEMU vorhanden -- fuer diesen Abschnitt ohne Belang"
fi

$FIRNC tools/wlan/oracle.fi -o .probe/worakel 2> "$OUT/orakel.err" \
    && ok "tools/wlan/oracle.fi baut gegen lib/crypto/ und lib/wlan/ (dieselben Dateien wie der Kern)" \
    || { bad "tools/wlan/oracle.fi laesst sich nicht bauen"; head -20 "$OUT/orakel.err"; }

if [ ! -x .probe/worakel ]; then
    echo "WLAN: ohne Orakel geht nichts weiter."
    echo "WLAN: $pass Zusagen, $((fail+1)) Fehler"
    exit 1
fi

# Die Gegenprobe zum Messplatz selbst: ein Orakel, das nie FAIL sagt,
# misst nichts. Es MUSS eine Zeile ablehnen koennen.
if [ "$(echo 'quatsch' | ./.probe/worakel)" = "FAIL" ]; then
    ok "das Orakel lehnt eine unbekannte Zeile ab (es sagt nicht zu allem ja)"
else
    bad "das Orakel antwortet auch auf Unsinn -- dann sagt kein FAIL etwas aus"
fi

# Und dass die eingecheckte Aufzeichnung die ist, die sie zu sein
# behauptet. Sie ist die Grundlage der staerksten Zusage dieser Runde.
if [ -f tools/wlan/mitschnitt.txt ]; then
    N=$(grep -c '^beacon ' tools/wlan/mitschnitt.txt)
    E=$(grep -c '^eapol' tools/wlan/mitschnitt.txt)
    D=$(grep -c '^daten ' tools/wlan/mitschnitt.txt)
    ok "die Aufzeichnung liegt bei: $N Beacons, $E Handschlagnachrichten, $D verschluesselte Rahmen aus einem echten WPA2-Netz"
else
    bad "tools/wlan/mitschnitt.txt fehlt"
fi

# =====================================================================
echo
echo "== 1..8. die Rechnung gegen Normen, OpenSSL und die Aufzeichnung =="
# =====================================================================
python3 tools/wlan/vektoren.py $SCHNELL 2>&1 | tee "$OUT/vektoren.txt"
VRC=${PIPESTATUS[0]}
VP=$(grep -c '^  OK    ' "$OUT/vektoren.txt" || true)
VF=$(grep -c '^  FAIL  ' "$OUT/vektoren.txt" || true)
pass=$((pass + VP))
fail=$((fail + VF))

# =====================================================================
echo
echo "== 9. der Fuzz-Lauf: verstuemmelte Rahmen unter valgrind =="
# =====================================================================
python3 tools/wlan/fuzz.py $SCHNELL 2>&1 | tee "$OUT/fuzz.txt"
FP=$(grep -c '^  OK    ' "$OUT/fuzz.txt" || true)
FF=$(grep -c '^  FAIL  ' "$OUT/fuzz.txt" || true)
pass=$((pass + FP))
fail=$((fail + FF))

# =====================================================================
echo
echo "== 10. was diese Runde NICHT kann, gemessen =="
# =====================================================================
#
# Ein Abschnitt, der Zusagen ueber ABWESENHEIT macht. Er steht hier,
# weil `docs/WLAN-BEFUND.md` Behauptungen darueber aufstellt, was fehlt,
# und eine Behauptung ohne Gegenprobe ist eine Meinung.
# Gesucht wird nach einem TREIBER, nicht nach dem Wort: eine
# PCI-Nummer einer WLAN-Karte im Quelltext waere der Anfang eines
# Treibers. In Kommentaren darf ueber AX200 geredet werden -- in
# lib/wlan/channel.fi steht ein ganzer Absatz darueber, warum die
# Firmware ihre eigene Regulatorik mitbringt.
# RUNDE WLAN-2, AUF merge6 BERICHTIGT. Diese Wache war auf mergeline2
# gruen und wurde auf merge6 beim ersten Lauf ROT -- zu Recht gemeldet,
# aber aus dem falschen Grund. In `kernel/netdev.fi` stehen seit Runde
# BLECH drei Zeilen
#
#     tab_line(0x8086, 0x2723, 0x00) // Wi-Fi 6 AX200
#
# und in `kernel/chipname.fi` die zugehoerigen Namen. Das ist NICHT der
# Anfang eines Treibers -- es ist genau Punkt 1 der Fortsetzungsliste
# aus docs/WLAN-BEFUND.md Abschnitt 8: eine Maschine mit einem AX200
# soll seine Nummer NENNEN statt still zu bleiben. Die dritte Spalte
# von `tab_line` ist der Treiber, und sie ist 0x00 = keiner.
#
# Die Wache prueft deshalb ab jetzt das, worauf es ankommt: dass keine
# WLAN-Nummer an einen TREIBER gebunden ist. Eine Nummer mit 0x00
# dahinter ist erwuenscht; eine Nummer mit etwas anderem dahinter waere
# ein Treiber, von dem der Befund nichts weiss.
WLTAB=$(grep -rhn 'tab_line(0x8086, *0x\(2723\|2725\|[Aa]0[Ff]0\)' --include=*.fi kernel/ 2>/dev/null || true)
WLBOUND=$(printf '%s\n' "$WLTAB" | grep -v '0x00)' | grep -c 'tab_line' || true)
WLNAMED=$(printf '%s\n' "$WLTAB" | grep -c 'tab_line' || true)
if [ "$WLBOUND" != "0" ]; then
    bad "eine WLAN-PCI-Nummer haengt an einem Treiber -- dann gibt es einen, den docs/WLAN-BEFUND.md nicht kennt"
else
    ok "keine WLAN-PCI-Nummer ist an einen Treiber gebunden ($WLNAMED benannt, alle mit Treiber 0x00): es gibt KEINEN Treiber, so wie docs/WLAN-BEFUND.md sagt"
fi
# Und die Gegenprobe dazu, damit diese Wache nicht gruen werden kann,
# indem die Nummern einfach verschwinden: Punkt 1 der Fortsetzungsliste
# IST erledigt, und das soll gemessen bleiben.
if [ "$WLNAMED" -ge 3 ]; then
    ok "Punkt 1 der Fortsetzungsliste ist auf merge6 erledigt: AX200/AX201/AX210 werden mit Namen gemeldet statt still zu bleiben"
else
    bad "die WLAN-Karten werden nicht mehr benannt -- Punkt 1 der Fortsetzungsliste ist verlorengegangen"
fi
if grep -rqn 'fn sae_\|dragonfly\|hunting' --include=*.fi lib/wlan/ 2>/dev/null; then
    bad "SAE ist angefangen worden, ohne dass es Testvektoren gibt"
else
    ok "SAE ist NICHT gebaut -- Begruendung in docs/WLAN-BEFUND.md Abschnitt 6"
fi
if grep -rqn 'TKIP wird\|fn tkip' --include=*.fi lib/wlan/ 2>/dev/null; then
    bad "TKIP ist umgesetzt worden -- es ist gebrochen und gehoert nicht hierher"
else
    ok "TKIP und WEP sind NICHT umgesetzt, nur erkannt und abgelehnt"
fi

Z=$(cat lib/wlan/*.fi lib/crypto/sha1.fi lib/crypto/aes.fi | wc -l)
ok "die Runde in Zeilen: $Z in lib/wlan/ und den zwei neuen lib/crypto/-Dateien"

# =====================================================================
echo
echo "== 11. RUNDE WLAN-3: der GANZE Weg gegen das simulierte Geraet =="
# =====================================================================
#
# Suchlauf -> Netzwahl -> Auth/Assoz -> 4-Wege -> Schluessel ->
# verschluesseltes Datenpaket hin UND zurueck -> DHCP -> HTTP.
# Jeder Schritt eine eigene Zusage mit Zahl, dazu die Gegenproben, die
# fehlschlagen MUESSEN, und die echten DHCP-Pakete aus der
# Aufzeichnung. Die Begruendung, warum das der weiteste Punkt ist, den
# man ohne eine Karte erreichen kann, steht in docs/RUNDE-WLAN3.md.
python3 tools/wlan/vollweg.py 2>&1 | tee "$OUT/vollweg.txt"
VWP=$(grep -c '^  OK    ' "$OUT/vollweg.txt" || true)
VWF=$(grep -c '^  FAIL  ' "$OUT/vollweg.txt" || true)
pass=$((pass + VWP))
fail=$((fail + VWF))

echo
if [ "$fail" -eq 0 ]; then
    echo "WLAN: $pass Zusagen, 0 Fehler"
    exit 0
else
    echo "WLAN: $pass Zusagen, $fail FEHLER"
    exit 1
fi
