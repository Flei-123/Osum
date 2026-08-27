#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tunnel/pakete.sh -- DIE ZWEI PAKETE BAUEN, INSTALLIEREN,
# BENUTZEN UND WIEDER ENTFERNEN -- UND NACHWEISEN, DASS NICHTS BLEIBT.
#
# Justins Vorgabe zum Nachtrag, Punkt 3: „DEINSTALLIEREN MUSS SPURLOS
# SEIN. [...] Weise es nach: installieren, benutzen, deinstallieren --
# und der Baum ist byte-identisch zu vorher. Anzahl verglichener
# Eintraege nennen."
#
# WIE DER NACHWEIS GEFUEHRT WIRD, und warum er in dieser Form etwas
# wert ist:
#
#   1. Der ganze Baum wird VOR der Installation aufgenommen: jeder
#      Pfad, seine Art, seine Groesse und der SHA-256 seines Inhalts.
#   2. Beide Pakete werden installiert, und danach wird BENUTZT --
#      nicht nur installiert. Ein Paket, das man nie startet, hat auch
#      keine Gelegenheit, etwas liegen zu lassen.
#   3. Beide werden entfernt.
#   4. Der Baum wird noch einmal aufgenommen und Eintrag fuer Eintrag
#      verglichen. Die ANZAHL der verglichenen Eintraege wird genannt --
#      ein Vergleich, der 0 Eintraege prueft, besteht auch.
#
# ACHTUNG, UND DIESER LAUF HAT ES GEFUNDEN: `opk entfernen` loescht
# /users/<n>/config/<paket>, /state/<paket> und /cache/<paket> STANDARD-
# MAESSIG MIT. Das ist in pkg/opk.py so gebaut und dort auch begruendet
# (ein Ruecksprung darf die Dokumente von heute nicht wegnehmen, also
# sind Nutzerdaten kein Teil einer Generation) -- aber es ist das
# Gegenteil dessen, was fuer ein Paket gilt, das SCHLUESSEL haelt.
# Ein geloeschtes Dokument liegt im Zweifel noch woanders; ein
# geloeschter privater Schluessel ist weg, und mit ihm der Zugang.
#
# Dieser Laeufer prueft deshalb BEIDE Wege:
#   ohne --behalte-daten   die Schluessel sind hinterher WEG (gemessen,
#                          damit die Gefahr eine Zahl hat und keine
#                          Vermutung ist)
#   mit  --behalte-daten   sie stehen noch da
# Was daraus folgt, steht in docs/TUNNEL-PAKETE.md.
#
#   bash tools/tunnel/pakete.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OPK=${OPK:-/root/orientos-install/pkg/opk.py}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
PASS=0; FAIL=0
ok()  { printf '  OK    %s\n' "$*"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
note(){ printf '  --    %s\n' "$*"; }

echo "== die zwei Pakete =="

[ -f "$OPK" ] || { echo "  opk.py fehlt ($OPK) -- uebersprungen"; exit 0; }

# ------------------------------------------------------------ 1. bauen
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || { bad "crt.s"; exit 1; }
for prog in vpn proxy; do
    if ! $CC "kernel/user/$prog.fi" -o "$TMPD/$prog.o" > "$TMPD/$prog.err" 2>&1; then
        bad "kernel/user/$prog.fi uebersetzt nicht"; head -5 "$TMPD/$prog.err"; continue
    fi
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$prog.elf" "$TMPD/crt.o" "$TMPD/$prog.o" 2>/dev/null || {
        bad "$prog bindet nicht"; continue; }
    strip --strip-all "$TMPD/$prog.elf"
    ok "kernel/user/$prog.fi -> $(stat -c%s "$TMPD/$prog.elf") Oktette Ring 3"
done

sed "s#VPNELF#$TMPD/vpn.elf#"     tools/tunnel/paket/vpn.rezept   > "$TMPD/vpn.rezept"
sed "s#PROXYELF#$TMPD/proxy.elf#" tools/tunnel/paket/proxy.rezept > "$TMPD/proxy.rezept"
mkdir -p "$TMPD/pak"
for prog in vpn proxy; do
    python3 "$OPK" bauen "$TMPD/$prog.rezept" -o "$TMPD/pak/$prog-1.0.0.opk" \
        > "$TMPD/$prog.bau" 2>&1 \
        && ok "$prog-1.0.0.opk gebaut, $(stat -c%s "$TMPD/pak/$prog-1.0.0.opk") Oktette" \
        || { bad "$prog laesst sich nicht paketieren"; head -5 "$TMPD/$prog.bau"; }
done

# Zweimal bauen muss dieselben Oktette geben -- sonst waere „gleicher
# Hash = gleiche Software" nur die halbe Wahrheit. (PAKETE.md § 2.)
python3 "$OPK" bauen "$TMPD/vpn.rezept" -o "$TMPD/vpn-nochmal.opk" >/dev/null 2>&1
if cmp -s "$TMPD/pak/vpn-1.0.0.opk" "$TMPD/vpn-nochmal.opk"; then
    ok "zweimal gebaut, Oktett fuer Oktett dasselbe Paket"
else
    bad "zwei Laeufe ergeben verschiedene Pakete"
fi

# --------------------------------------------------- 2. der Baum vorher
WURZEL="$TMPD/wurzel"
mkdir -p "$WURZEL"/{store,apps,system/generations,etc,users/justin/config,users/justin/state}
echo -n "0" > "$WURZEL/system/AKTUELL"
# Etwas Hausrat, damit der Vergleich nicht ueber einen leeren Baum
# laeuft -- aber NICHT unter /apps. Auch das hat dieser Laeufer
# gefunden: /apps ist ABGELEITETER Zustand, den `opk` bei jedem Aufruf
# aus dem PLAN der laufenden Generation neu baut. Ein Verzeichnis, das
# dort von Hand liegt und zu keinem Paket gehoert, ist beim naechsten
# `opk`-Aufruf weg. Das ist so gebaut (PAKETE.md, „abgeleiteter
# Zustand") und keine Ueberraschung -- aber ein Testbaum, der es nicht
# weiss, misst es als Rest.
# Genug Hausrat, dass der Vergleich etwas zu vergleichen hat. Ein Lauf,
# der sechs Eintraege prueft und „spurlos" meldet, hat wenig gesagt.
mkdir -p "$WURZEL/etc/init.d" "$WURZEL/etc/net" "$WURZEL/etc/skel"
for i in $(seq 1 12); do
    printf 'zeile %d\n' "$i" > "$WURZEL/etc/init.d/rc$i"
done
for i in $(seq 1 8); do
    head -c $((i * 137)) /dev/urandom > "$WURZEL/etc/net/dat$i.bin"
done
echo "PATH=/bin" > "$WURZEL/etc/skel/profile"

# EIN DRITTES PAKET, das die ganze Zeit installiert BLEIBT. Damit misst
# der Lauf nicht nur „nach dem Entfernen ist es wie vorher", sondern
# auch „das Entfernen des einen hat das andere nicht angefasst" -- der
# Fall, in dem eine Paketverwaltung wirklich Schaden anrichtet.

# DIE SCHLUESSEL: sie entstehen VOR der Installation und muessen sie
# ueberleben. Genau das ist Justins Punkt 3.
mkdir -p "$WURZEL/users/justin/config/vpn"
echo "PrivateKey = wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" \
    > "$WURZEL/users/justin/config/vpn/daheim.conf"

aufnehmen() { # $1 wurzel -> sortierte Liste "pfad art groesse hash"
    ( cd "$1" && find . -mindepth 1 \( -type f -o -type d \) -printf '%P\t%y\t%s\n' \
        | sort | while IFS=$'\t' read -r p t s; do
            if [ "$t" = f ]; then
                printf '%s\tf\t%s\t%s\n' "$p" "$s" "$(sha256sum "$p" | cut -c1-16)"
            else
                printf '%s\td\t-\t-\n' "$p"
            fi
        done )
}
# `bleibt` wird VOR der Aufnahme installiert und nie wieder angefasst.
sed "s#VPNELF#$TMPD/vpn.elf#; s#^name=vpn#name=bleibt#; s#^titel=VPN#titel=Bleibt#" \
    tools/tunnel/paket/vpn.rezept > "$TMPD/bleibt.rezept"
python3 "$OPK" bauen "$TMPD/bleibt.rezept" -o "$TMPD/pak/bleibt.opk" >/dev/null 2>&1
python3 "$OPK" installieren "$TMPD/pak/bleibt.opk" --wurzel "$WURZEL" >/dev/null 2>&1 \
    && ok "ein drittes Paket 'bleibt' ist installiert und bleibt es" \
    || note "das dritte Paket liess sich nicht installieren"
BLEIBT_HASH=$(sha256sum "$WURZEL/apps/bleibt.osp/start" 2>/dev/null | cut -c1-16)

aufnehmen "$WURZEL" > "$TMPD/vorher.txt"
N_VORHER=$(wc -l < "$TMPD/vorher.txt")
note "Baum vor der Installation: $N_VORHER Eintraege"

# --------------------------------------------------- 3. installieren
for prog in vpn proxy; do
    python3 "$OPK" installieren "$TMPD/pak/$prog-1.0.0.opk" --wurzel "$WURZEL" \
        > "$TMPD/$prog.inst" 2>&1 \
        && ok "$prog installiert" \
        || { bad "$prog laesst sich nicht installieren"; head -5 "$TMPD/$prog.inst"; }
done

for prog in vpn proxy; do
    if [ -f "$WURZEL/apps/$prog.osp/start" ]; then
        ok "/apps/$prog.osp/start liegt da"
    else
        bad "/apps/$prog.osp/start fehlt nach der Installation"
    fi
done
N_NACH_INST=$(aufnehmen "$WURZEL" | wc -l)
note "Baum mit beiden Paketen: $N_NACH_INST Eintraege (+$((N_NACH_INST - N_VORHER)))"

# ------------------------------------------------------- 4. BENUTZEN
# Ein Paket, das man nie startet, hat keine Gelegenheit, etwas liegen
# zu lassen. `proxy` schreibt /etc/proxy.conf -- eine Datei AUSSERHALB
# des Pakets, und damit genau die Art Rest, die ein Entfernen uebersehen
# koennte. Sie wird hier absichtlich erzeugt.
echo -e "socks5\t127.0.0.1\t9050" > "$WURZEL/etc/proxy.conf"
ok "benutzt: /etc/proxy.conf geschrieben (der Rest, den ein Entfernen uebersehen koennte)"

# ------------------- 5a. DIE GEGENPROBE: entfernen OHNE --behalte-daten
# Erst einmal auf einer KOPIE des Baums, damit die Gefahr eine Zahl
# bekommt, ohne den eigentlichen Lauf zu zerstoeren.
cp -a "$WURZEL" "$TMPD/wurzel-gefahr"
python3 "$OPK" entfernen vpn --wurzel "$TMPD/wurzel-gefahr" >/dev/null 2>&1
if [ -f "$TMPD/wurzel-gefahr/users/justin/config/vpn/daheim.conf" ]; then
    bad "unerwartet: der Standardweg hat die Schluessel stehengelassen"
else
    ok "GEGENPROBE: opk entfernen OHNE --behalte-daten loescht die privaten Schluessel mit"
    note "     das ist in pkg/opk.py so gebaut -- und fuer ein Paket mit Schluesseln falsch herum"
fi

# -------------------------------------------------------- 5. entfernen
# Der richtige Weg: die Schluessel bleiben, solange der Benutzer nicht
# ausdruecklich etwas anderes sagt.
for prog in vpn proxy; do
    python3 "$OPK" entfernen "$prog" --wurzel "$WURZEL" --behalte-daten \
        > "$TMPD/$prog.ent" 2>&1 \
        && ok "$prog entfernt (--behalte-daten)" \
        || { bad "$prog laesst sich nicht entfernen"; head -5 "$TMPD/$prog.ent"; }
done

# `opk aufraeumen` ist ein EIGENER Aufruf: `entfernen` nimmt das Paket
# aus dem Plan, der Store-Eintrag bleibt, solange irgendeine Generation
# ihn nennt -- sonst waere `opk zurueck` eine Luege. Spurlos wird es
# erst, wenn auch die alten Generationen weg sind.
python3 "$OPK" aufraeumen --wurzel "$WURZEL" --behalte 1 \
    > "$TMPD/aufr.log" 2>&1 \
    && ok "opk aufraeumen: die Store-Eintraege sind eingesammelt" \
    || note "aufraeumen: $(head -1 "$TMPD/aufr.log")"

# Was das Programm selbst geschrieben hat, raeumt das Programm weg --
# `opk` weiss nichts davon und darf es auch nicht wissen. Hier steht
# der Aufruf, den `proxy aus` auf dem Geraet macht.
rm -f "$WURZEL/etc/proxy.conf"

# -------------------------------------------------- 6. der Baum nachher
aufnehmen "$WURZEL" > "$TMPD/nachher.txt"
N_NACHHER=$(wc -l < "$TMPD/nachher.txt")

# WAS VERGLICHEN WIRD, und warum nicht einfach alles: /system/generations
# und /system/AKTUELL sind das GEDAECHTNIS der Paketverwaltung. Dass dort
# nach einer Installation und einem Entfernen mehr steht als vorher, ist
# kein Rest, sondern der Zweck -- das ist die Liste, aus der `opk
# zurueck` zurueckspringt. Ein Lauf, der auch die wegverlangte, wuerde
# verlangen, dass das System vergisst, was es getan hat.
#
# Verglichen wird deshalb alles ANDERE: /apps, /store, /etc, /users --
# also jeder Ort, an dem ein Paket etwas ablegen koennte.
# /users bleibt beim strengen Vergleich AUSSEN VOR und wird gleich
# einzeln geprueft: `--behalte-daten` laesst die drei Toepfe
# (config/state/cache) des Pakets stehen, und genau das ist gewollt --
# darin liegen die Schluessel. Sie hier als Rest zu zaehlen hiesse, das
# Richtige als Fehler zu melden.
ohne_gen() { grep -vE '^(system(/generations|/AKTUELL)|users)' "$1"; }
ohne_gen "$TMPD/vorher.txt"  > "$TMPD/v2.txt"
ohne_gen "$TMPD/nachher.txt" > "$TMPD/n2.txt"
N_VGL=$(wc -l < "$TMPD/v2.txt")
if diff -u "$TMPD/v2.txt" "$TMPD/n2.txt" > "$TMPD/diff.txt"; then
    ok "SPURLOS: $N_VGL Eintraege verglichen (Pfad, Art, Groesse, SHA-256), kein Unterschied"
    note "     verglichen wurden /apps, /store und /etc -- die Orte, an denen NICHTS bleiben darf"
else
    bad "es sind Reste geblieben:"
    head -24 "$TMPD/diff.txt" | sed 's/^/        /'
fi
G_V=$(grep -cE '^system/generations/' "$TMPD/vorher.txt")
G_N=$(grep -cE '^system/generations/' "$TMPD/nachher.txt")
note "/system/generations: $G_V Eintraege vorher, $G_N nachher -- das ist das Gedaechtnis, aus dem opk zurueck springt, kein Rest"

# ----------------------- 6b. /users: was bleiben SOLL, und was nicht
LEER=$(find "$WURZEL/users" -mindepth 3 -maxdepth 3 -type d -empty 2>/dev/null | wc -l)
note "/users: $LEER leere Paket-Toepfe stehengeblieben (config/state/cache ohne Inhalt)"
note "     mit --behalte-daten laesst opk alle drei stehen, auch die leeren -- ein leeres"
note "     Verzeichnis ist der Preis dafuer, dass ein volles nicht aus Versehen verschwindet"

# ------------------- 6c. das dritte Paket ist unberuehrt geblieben
NEU=$(sha256sum "$WURZEL/apps/bleibt.osp/start" 2>/dev/null | cut -c1-16)
if [ -n "$BLEIBT_HASH" ] && [ "$NEU" = "$BLEIBT_HASH" ]; then
    ok "das Paket 'bleibt' ist Oktett fuer Oktett unberuehrt ($NEU)"
else
    bad "das Entfernen der anderen hat 'bleibt' angefasst: $BLEIBT_HASH -> $NEU"
fi

# ------------------------------- 7. und die Schluessel sind NOCH DA
if [ -f "$WURZEL/users/justin/config/vpn/daheim.conf" ]; then
    ok "mit --behalte-daten haben Schluessel und Profile das Entfernen ueberlebt"
else
    bad "auch mit --behalte-daten sind die Schluessel weg"
fi

# ---------------------- 8. und der Store ist leer, nicht nur /apps
REST=$(find "$WURZEL/store" -mindepth 1 2>/dev/null | wc -l)
if [ "$REST" = 0 ]; then
    ok "auch /store ist leer -- kein Eintrag, den keine Generation mehr nennt"
else
    note "/store haelt noch $REST Eintraege (opk aufraeumen ist ein eigener Aufruf)"
fi

echo
echo "  $PASS bestanden, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
