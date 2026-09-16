#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/logind/run.sh -- DIE ABNAHME DER RUNDE LOGIND (P-002/P-003).
#
# WAS DIESE RUNDE GEMESSEN HAT UND WARUM SIE UEBERHAUPT STATTFAND:
#
# Der Auftrag nannte P-002 (grafischer Login/Sperrbildschirm) und P-003
# (Ausschalten aus der Oberflaeche) als offen. NACHGESEHEN, BEVOR
# GEBAUT: beide sind auf `main` und mit Bildern belegt -- P-002 aus der
# Runde ANMELDUNG (Zweig `anmeldung`, gemergt in 996d74e), P-003 aus der
# Runde ENERGIE (Zweig `energie`, gemergt in a298db7). `OFFEN.md` ist in
# diesem Punkt VERALTET; P-003 steht dort selbst schon als erledigt,
# P-002 nicht.
#
# Was WIRKLICH fehlte, stand in den Berichten dieser Runden als
# ausdruecklich offen benannter Rest -- und genau das misst dieser
# Laeufer:
#
#   1. ABMELDEN MELDETE NICHT AB (docs/RUNDE-ANMELDUNG.md, 5.2;
#      docs/RUNDE-ENERGIE.md, 3.4). Der Menuepunkt startete
#      `/bin/desktop` neu, UNTER DERSELBEN KENNUNG. Die Sitzung blieb
#      offen. Solange es keine Anmeldung gab, war das ehrlich; mit
#      Anmeldung ist es falsch -- wer abmeldet und weggeht, laesst seine
#      Sitzung offen stehen.
#
#   2. `/users/justin` FEHLTE (docs/RUNDE-ANMELDUNG.md, 5.4).
#      `/etc/passwd` verspricht es als Heimatverzeichnis; im Abbild gab
#      es nur `/users/root/`.
#
# ABSCHNITTE
#   1  das Abbild traegt, was die Anmeldung braucht (statisch)
#   2  das Heimatverzeichnis: da, und es gehoert justin
#   3  die Anmeldung kommt VOR dem Schreibtisch, und uid wechselt
#   4  ein falsches Kennwort wird abgewiesen und verzoegert
#   5  ABMELDEN beendet die Sitzung und holt den Anmeldeschirm
#   6  GEGENPROBE: ohne `anmeldung` bleibt der alte Weg unveraendert
#   7  die Oberflaeche haelt die Regel (check-ui)
#
#   bash tools/logind/run.sh [<bauverzeichnis>]
#
# Ohne Bauverzeichnis wird eines gebaut. Ein vorhandenes wird
# WIEDERVERWENDET -- die Platte ist knapp, und der Bau dauert Minuten.
set -uo pipefail
# DEN BAUM AUS DEM SKRIPTPFAD FINDEN, aber NUR wenn er stimmt. `$0` ist
# ein relativer Pfad, sobald das Skript aus einem anderen Verzeichnis
# gerufen wird -- `dirname` liefert dann `.` und `cd ./../..` landet
# irgendwo. Gemessen: aus /tmp gerufen stand `pwd` auf `/`, und jeder
# Aufruf von `tools/osum/mkfs.py` schlug fehl, ohne dass eine Zusage es
# gesagt haette. Also wird geprueft, dass wir wirklich im Baum stehen.
SELBST=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
cd "$SELBST/../.." || { echo "== der Baum ist von $SELBST aus nicht erreichbar" >&2; exit 1; }
[ -f tools/osum/mkfs.py ] || { echo "== $(pwd) ist nicht der Osum-Baum" >&2; exit 1; }
WURZEL=$(pwd)
mkdir -p "$WURZEL/.logind-mess"

BUILD=${1:-/root/lg-img}
OK=0
FAIL=0

ok()   { echo "  OK    $*"; OK=$((OK + 1)); }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }
info() { echo "        $*"; }
kopf() { echo; echo "== $*"; }

# ---------------------------------------------------------------- bauen
if [ ! -f "$BUILD/osum.mb" ] || [ ! -f "$BUILD/root.img" ]; then
    kopf "0. bauen"
    bash tools/usbimg/build.sh "$BUILD" > "$WURZEL/.logind-mess/bau.log" 2>&1 \
        || { tail -20 "$WURZEL/.logind-mess/bau.log"; bad "der Bau ist fehlgeschlagen"; \
             echo; echo "LOGIND: $OK bestanden, $FAIL gescheitert"; exit 1; }
    ok "Kern und Wurzel gebaut"
else
    kopf "0. das vorhandene Bauverzeichnis wird benutzt"
    info "$BUILD ($(stat -c%s "$BUILD/osum.mb") Oktette Kern)"
fi

LISTE="$BUILD/liste.txt"
[ -f "$LISTE" ] || python3 tools/osum/mkfs.py list "$BUILD/root.img" > "$LISTE" 2>&1

# =============================================== 1. WAS IM ABBILD LIEGT
kopf "1. das Abbild traegt, was die Anmeldung braucht"
# OHNE DIESE DATEIEN IST JEDE MESSUNG WEITER UNTEN SINNLOS. Die Runde
# ANMELDUNG hat genau hier ihre eigentliche Luecke gefunden: die
# Programme waren gebaut und gemessen, sie standen nur in keinem Abbild.
for f in /bin/glogin /bin/lock /bin/login /bin/passwd /bin/su \
         /bin/sperrwache /etc/shadow /etc/passwd /etc/group \
         /etc/login.conf /etc/sperre.conf; do
    if grep -qE "(^|[[:space:]])${f}([[:space:]]|\$)" "$LISTE"; then
        ok "im Abbild: $f"
    else
        bad "FEHLT im Abbild: $f"
    fi
done

# /etc/shadow muss PBKDF2-Eintraege tragen und KEIN Klartextkennwort.
SHAD=$(python3 tools/osum/mkfs.py cat "$BUILD/root.img" /etc/shadow 2>/dev/null)
if echo "$SHAD" | grep -q '\$osum1\$'; then
    ok "/etc/shadow traegt \$osum1\$-Eintraege (PBKDF2)"
    info "$(echo "$SHAD" | wc -l) Zeilen, Runden $(echo "$SHAD" | sed -n 's/.*\$osum1\$\([0-9]*\)\$.*/\1/p' | head -1)"
else
    bad "/etc/shadow hat keine \$osum1\$-Eintraege"
fi
# DIE GEGENPROBE, die fehlschlagen MUSS: kein Anfangskennwort im
# Klartext irgendwo im Abbild. Ohne sie misst man das Format und nicht
# das Geheimnis.
if grep -aq 'startkennwort' "$BUILD/root.img"; then
    bad "GEGENPROBE: 'startkennwort' steht im KLARTEXT im Abbild"
else
    ok "GEGENPROBE: 'startkennwort' steht NICHT im Klartext im Abbild"
fi
if grep -aq 'osumroot' "$BUILD/root.img"; then
    bad "GEGENPROBE: 'osumroot' steht im KLARTEXT im Abbild"
else
    ok "GEGENPROBE: 'osumroot' steht NICHT im Klartext im Abbild"
fi

# ========================================= 2. DAS HEIMATVERZEICHNIS
kopf "2. das Heimatverzeichnis von justin (docs/RUNDE-ANMELDUNG.md 5.4)"
# /etc/passwd VERSPRICHT ES. Ein Pfad, den die Kontendatei nennt und den
# es nicht gibt, ist ein gebrochenes Versprechen: `glogin` legt die
# Rechte ab und startet den Schreibtisch als uid 1000, und jedes
# Programm, das danach etwas Eigenes ablegen will (die Einstellungen
# schreiben /users/<name>/config/locale), schreibt ins Leere.
HEIM=$(python3 tools/osum/mkfs.py cat "$BUILD/root.img" /etc/passwd 2>/dev/null \
       | sed -n 's/^justin:[^:]*:[^:]*:[^:]*:[^:]*:\([^:]*\):.*/\1/p')
if [ "$HEIM" = "/users/justin" ]; then
    ok "/etc/passwd nennt als Heimat: $HEIM"
else
    bad "/etc/passwd nennt eine andere Heimat: '$HEIM'"
fi
for d in /users/justin/ /users/justin/config/; do
    if grep -qE "(^|[[:space:]])${d}([[:space:]]|\$)" "$LISTE"; then
        ok "im Abbild: $d"
    else
        bad "FEHLT im Abbild: $d"
    fi
done
# RECHTE UND EIGENTUM SIND DER PUNKT, nicht die blosse Existenz. Ohne
# `@0700:1000:1000` gehoerte das Verzeichnis root mit 0755 (mkfs-Vorgabe)
# -- dann koennte justin in seinem eigenen Zuhause nichts anlegen, und
# jeder andere koennte hineinsehen.
M=$(python3 tools/osum/mkfs.py meta "$BUILD/root.img" /users/justin 2>/dev/null)
if [ "$M" = "/users/justin 700 1000 1000" ]; then
    ok "es gehoert justin und nur ihm: $M"
else
    bad "Rechte/Eigentum falsch: '$M' (erwartet '/users/justin 700 1000 1000')"
fi
M2=$(python3 tools/osum/mkfs.py meta "$BUILD/root.img" /users/justin/config 2>/dev/null)
if [ "$M2" = "/users/justin/config 700 1000 1000" ]; then
    ok "auch config/: $M2"
else
    bad "config/ Rechte falsch: '$M2'"
fi
# GEGENPROBE: roots Heimat darf NICHT justin gehoeren.
MR=$(python3 tools/osum/mkfs.py meta "$BUILD/root.img" /users/root 2>/dev/null)
case "$MR" in
    *" 0 0") ok "GEGENPROBE: /users/root gehoert weiter root ($MR)" ;;
    *)       bad "GEGENPROBE: /users/root gehoert nicht mehr root ($MR)" ;;
esac

# ========================================== DER LAEUFER FUER DIE LAEUFE
# Ein Lauf, ein Bild, ein Bericht. Die Tasten gehen ueber den
# QEMU-Monitor, wie in tools/anmeldung/shot.sh -- derselbe Weg, mit dem
# die Runde ANMELDUNG ihre Bilder gemacht hat.
BEL="$WURZEL/belege/logind"
mkdir -p "$BEL"

# DIE EINGABETASTE HEISST IM QEMU-MONITOR `ret` UND NICHT `kp_enter`.
# Gemessen, und es hat diese Abnahme einen Lauf gekostet: mit
# `kp_enter` standen die Buchstaben im Bericht (`key: s`, `key: t`, ...),
# aber die Zeile `key: [enter]` fehlte -- das Kennwort wurde getippt und
# nie abgeschickt, und die Abnahme meldete voellig zu Recht
# "'glogin: angemeldet' fehlt". Die uebrigen Laeufer dieses Baums
# nehmen ueberall `ret` (pruef/abnahme2.py, pruef/ausschalten.py).
lauf() {
    # lauf <name> <sekunden> <extra-kernelwoerter> <taste ...>
    local name=$1 sek=$2 extra=$3; shift 3
    # VORLAUF 22 UND NICHT 12. Gemessen: bei 12 Sekunden war das
    # erste Bild zu 96 % schwarz -- `glogin: bereit` und seine sieben
    # Rechtecke standen im Bericht, aber der Fensterserver hatte noch
    # nicht uebertragen. Ein Bild, das vor dem ersten `present`
    # entsteht, zeigt den Zustand vor dem Malen und nicht den
    # Anmeldeschirm. Die Tasten kamen trotzdem an (der Vorlauf gilt
    # nur fuer die erste); zu messen war nur das Bild falsch.
    SEKUNDEN=$sek VORLAUF=${VORLAUF_LAUF:-22} APPEND_EXTRA="$extra" \
        bash tools/anmeldung/shot.sh "$BUILD" "$BEL/$name.png" "$@" \
        > "$BEL/$name.lauf" 2>&1
    echo "$BEL/$name.txt"
}

tinte() {
    python3 - "$1" <<'PY' 2>/dev/null
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB'); w,h=im.size
p=im.load(); n=0; t=0
for y in range(0,h,4):
    for x in range(0,w,4):
        t+=1
        if p[x,y]!=(0,0,0): n+=1
print(int(100*n/t))
PY
}

# ================================ 3. DIE ANMELDUNG KOMMT VOR DEM DESKTOP
kopf "3. die Anmeldung kommt VOR dem Schreibtisch (P-002)"
# `anmeldung` schaltet den Weg ein: der Kern startet /bin/glogin statt
# /bin/desktop (kernel/kgui.fi, desk_start). Getippt wird das richtige
# Kennwort -- und danach MUSS der Schreibtisch unter uid 1000 laufen und
# nicht als root. Das ist der ganze Befund P-002.
T3=$(lauf anmelden 70 "anmeldung" \
     '#foto:anmeldeschirm' \
     s t a r t k e n n w o r t ret @45 '#foto:desktop')
if [ -f "$T3" ]; then
    grep -qa 'anmeldung vor schreibtisch' "$T3" \
        && ok "der Kern startet die Anmeldung vor dem Schreibtisch" \
        || bad "'anmeldung vor schreibtisch' steht nicht im Bericht"
    grep -qaE 'glogin: bereit' "$T3" \
        && ok "der Anmeldeschirm ist bereit" \
        || bad "'glogin: bereit' fehlt"
    grep -qa 'glogin: angemeldet als justin' "$T3" \
        && ok "angemeldet als justin" \
        || bad "'glogin: angemeldet als justin' fehlt"
    # DIE ZAHL, DIE P-002 BEANTWORTET.
    if grep -qa 'glogin: uid=1000' "$T3"; then
        ok "der Schreibtisch laeuft unter uid=1000 und NICHT als root"
    else
        bad "'glogin: uid=1000' fehlt -- der Schreibtisch waere weiter root"
        info "$(grep -a 'glogin: uid' "$T3" | head -2)"
    fi
    grep -qaE 'glogin: desktop pid=[0-9]+' "$T3" \
        && ok "und er hat den Schreibtisch gestartet" \
        || bad "'glogin: desktop pid=' fehlt"
    # DAS BILD: steht ueberhaupt etwas darauf? Ein Schreibtisch, der
    # nicht malt, ist ein schwarzer Schirm mit gruenen Haken darunter.
    if [ -f "$BEL/anmelden-desktop.png" ]; then
        TI=$(tinte "$BEL/anmelden-desktop.png")
        if [ -n "$TI" ] && [ "$TI" -ge 20 ]; then
            ok "BILD: der Schreibtisch steht ($TI % Tinte)"
        else
            bad "BILD: der Schirm ist fast leer (${TI:-?} % Tinte)"
        fi
    else
        bad "BILD: kein Bild vom Schreibtisch entstanden"
    fi
else
    bad "Abschnitt 3: kein Bericht entstanden"
fi

# ==================================== 4. EIN FALSCHES KENNWORT
kopf "4. ein falsches Kennwort wird abgewiesen -- und verzoegert"
# EIN ANMELDESCHIRM, DER FALSCHE KENNWOERTER DURCHLAESST, ist keiner;
# einer, der sie ohne Verzoegerung abweist, laedt zum Durchprobieren
# ein. Beides wird hier gemessen, und die Verzoegerung mit der Uhr der
# MASCHINE (glogin meldet sie selbst), nicht mit der des Wirts.
T4=$(lauf falsch 55 "anmeldung" \
     f a l s c h ret @30 '#foto:abgewiesen')
if [ -f "$T4" ]; then
    grep -qa 'glogin: abgewiesen' "$T4" \
        && ok "das falsche Kennwort wurde abgewiesen" \
        || bad "'glogin: abgewiesen' fehlt"
    W=$(sed -n 's/.*glogin: gewartet \([0-9]*\) ms.*/\1/p' "$T4" | head -1)
    if [ -n "$W" ] && [ "$W" -ge 1000 ]; then
        ok "und danach mindestens 1000 ms gewartet (gemessen: $W ms)"
    else
        bad "die Verzoegerung fehlt oder ist zu kurz (gemessen: '${W:-keine}')"
    fi
    # DIE WICHTIGSTE ZUSAGE DES ABSCHNITTS: kein Weg an der Anmeldung
    # vorbei. Nach einem Fehlversuch darf KEIN Schreibtisch stehen.
    if grep -qa 'glogin: angemeldet' "$T4"; then
        bad "nach einem falschen Kennwort wurde trotzdem angemeldet"
    else
        ok "GEGENPROBE: kein 'angemeldet' -- kein Weg an der Anmeldung vorbei"
    fi
    # UND DAS KENNWORT STEHT NICHT IM BERICHT.
    if grep -qaE 'startkennwort|osumroot' "$T4"; then
        bad "ein Kennwort steht im seriellen Mitschnitt"
    else
        ok "GEGENPROBE: kein Kennwort im seriellen Mitschnitt"
    fi
else
    bad "Abschnitt 4: kein Bericht entstanden"
fi

# ======================================== 5. ABMELDEN (DIESE RUNDE)
kopf "5. ABMELDEN beendet die Sitzung und holt den Anmeldeschirm"
# DAS IST DER PUNKT, DEN DIESE RUNDE GEBAUT HAT -- und er bekommt einen
# EIGENEN Laeufer, weil er echte Mausklicks braucht.
#
# WARUM NICHT MIT TASTEN HIER IM SKRIPT: ausprobiert und gemessen
# verworfen. Die Reihenfolge der Bedienelemente im Startmenue ist keine
# Zusage -- `launcher.fi` setzt den Fokus auf das Suchfeld, und mit
# einem Tabulator zu viel startete die Eingabetaste den TEXTEDITOR
# statt das Energiemenue zu oeffnen. `pruef/abmelden.py` liest deshalb
# die LAGE des Energieknopfs aus dem Bericht des Programms selbst
# (`launcher: rect id=4`) und klickt dorthin -- derselbe Weg, mit dem
# die Runde ENERGIE ihre Bilder gemacht hat (pruef/oneshot.py).
#
# DAS ABBILD MUSS DAFUER MIT `UITRACE=1` GEBAUT SEIN. Ohne
# `/etc/uitrace` ist die Oberflaeche STUMM (build.sh:792), es gibt kein
# `launcher: rect`, und jeder Klick raet.
if grep -qE "(^|[[:space:]])/etc/uitrace([[:space:]]|\$)" "$LISTE"; then
    AB="$WURZEL/.logind-mess/abmelden.log"
    if python3 pruef/abmelden.py "$BUILD" "$WURZEL/belege/logind" > "$AB" 2>&1; then
        # JEDE EINZELNE ZUSAGE DES LAEUFERS WIRD HIER MITGEZAEHLT und
        # nicht zu einer Sammelzeile verdichtet: eine Abnahme, die "ein
        # anderes Skript war gruen" meldet, sagt nicht, WAS gruen war.
        while IFS= read -r z; do
            ok "${z#  OK    }"
        done < <(grep '^  OK    ' "$AB")
        grep -E '^ABMELDEN:' "$AB" | sed 's/^/        /'
    else
        bad "pruef/abmelden.py ist gefallen"
        grep -E '^  (OK|FAIL)|^ABMELDEN:' "$AB" | tail -16 | sed 's/^/        /'
    fi
else
    bad "das Abbild hat kein /etc/uitrace -- mit UITRACE=1 bauen"
    info "ohne den Schalter meldet die Oberflaeche nichts (build.sh:792)"
fi

# =================================== 6. GEGENPROBE: DER ALTE WEG
kopf "6. GEGENPROBE: ohne 'anmeldung' ist der alte Weg unveraendert"
# Jeder Pruefstand dieses Baums, der `desk` schreibt, faehrt OHNE das
# Wort `anmeldung`. Wuerde diese Runde dort etwas aendern, fielen
# fremde Abnahmen um -- also wird ausdruecklich gemessen, dass sich
# dort NICHTS aendert.
T6=$(lauf ohne 45 "" @10 '#foto:direkt')
if [ -f "$T6" ]; then
    grep -qa 'desk: OHNE anmeldung' "$T6" \
        && ok "ohne das Wort meldet der Kern den alten Weg" \
        || bad "'desk: OHNE anmeldung' fehlt"
    grep -qaE 'desk: start /bin/desktop' "$T6" \
        && ok "und startet den Schreibtisch direkt" \
        || bad "'desk: start /bin/desktop' fehlt"
    # NICHT auf das WORT `glogin` pruefen: der Kern listet beim Start
    # den Inhalt von /bin, und dort LIEGT die Datei (`... glogin:1
    # lock:1 login:1 ...`). Gemessen: diese Zusage war einmal rot,
    # obwohl gar kein Anmeldeschirm lief. Gefragt ist, ob er GESTARTET
    # wurde -- also die Startzeile und seine eigene Meldung.
    if grep -qaE 'start /bin/glogin|glogin: bereit' "$T6"; then
        bad "ohne das Wort lief trotzdem glogin"
        info "$(grep -aE 'start /bin/glogin|glogin: bereit' "$T6" | head -2)"
    else
        ok "GEGENPROBE: glogin wurde nicht gestartet (kein 'start /bin/glogin')"
    fi
    if grep -qa 'abmelden:' "$T6"; then
        bad "ohne Sitzung lief trotzdem eine Abmeldung"
    else
        ok "GEGENPROBE: keine Abmeldung ohne Sitzung"
    fi
else
    bad "Abschnitt 6: kein Bericht entstanden"
fi

# ============================================ 7. DIE OBERFLAECHE
kopf "7. die Oberflaeche haelt die Regel"
# Justins Vorgabe steht im Kopf von tools/check-ui.sh. Diese Runde hat
# im Starter nur den WEG hinter dem Menuepunkt getauscht und kein
# Bedienelement angefasst -- gemessen wird es trotzdem.
if bash tools/check-ui.sh > "$WURZEL/.logind-mess/ui.log" 2>&1; then
    ok "check-ui.sh PASSED"
    info "$(grep -E '^ +[0-9]+ (Dateien|Programme)' "$WURZEL/.logind-mess/ui.log" | head -2 | tr '\n' ' ')"
else
    bad "check-ui.sh ist gefallen"
    tail -12 "$WURZEL/.logind-mess/ui.log"
fi

echo
echo "LOGIND: $OK bestanden, $FAIL gescheitert"
echo "Belege: $BEL"
[ "$FAIL" = 0 ]
