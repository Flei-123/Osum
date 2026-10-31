#!/usr/bin/env bash
#
#   bash tools/logind/run.sh [<bauverzeichnis>]
#
set -uo pipefail
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

kopf "1. das Abbild traegt, was die Anmeldung braucht"
for f in /bin/glogin /bin/lock /bin/login /bin/passwd /bin/su \
         /bin/idlelock /etc/shadow /etc/passwd /etc/group \
         /etc/login.conf /etc/sperre.conf; do
    if grep -qE "(^|[[:space:]])${f}([[:space:]]|\$)" "$LISTE"; then
        ok "im Abbild: $f"
    else
        bad "FEHLT im Abbild: $f"
    fi
done

SHAD=$(python3 tools/osum/mkfs.py cat "$BUILD/root.img" /etc/shadow 2>/dev/null)
if echo "$SHAD" | grep -q '\$osum1\$'; then
    ok "/etc/shadow traegt \$osum1\$-Eintraege (PBKDF2)"
    info "$(echo "$SHAD" | wc -l) Zeilen, Runden $(echo "$SHAD" | sed -n 's/.*\$osum1\$\([0-9]*\)\$.*/\1/p' | head -1)"
else
    bad "/etc/shadow hat keine \$osum1\$-Eintraege"
fi
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
MR=$(python3 tools/osum/mkfs.py meta "$BUILD/root.img" /users/root 2>/dev/null)
case "$MR" in
    *" 0 0") ok "GEGENPROBE: /users/root gehoert weiter root ($MR)" ;;
    *)       bad "GEGENPROBE: /users/root gehoert nicht mehr root ($MR)" ;;
esac

BEL="$WURZEL/belege/logind"
mkdir -p "$BEL"

lauf() {
    # lauf <name> <sekunden> <extra-kernelwoerter> <taste ...>
    local name=$1 sek=$2 extra=$3; shift 3
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

kopf "3. die Anmeldung kommt VOR dem Schreibtisch (P-002)"
T3=$(lauf anmelden 100 "anmeldung" \
     '#foto:anmeldeschirm' \
     s t a r t k e n n w o r t ret @45 '#foto:desktop' meta_l @60 '#foto:menu')
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
    if grep -qa 'glogin: uid=1000' "$T3"; then
        ok "der Schreibtisch laeuft unter uid=1000 und NICHT als root"
    else
        bad "'glogin: uid=1000' fehlt -- der Schreibtisch waere weiter root"
        info "$(grep -a 'glogin: uid' "$T3" | head -2)"
    fi
    # W-U (r1059): the launcher starts hidden at boot, BEFORE the sign-in. Its footer user must be read again when the menu is
    # shown (Super after the sign-in), or it keeps "root" all session (z11).
    grep -qa 'launcher: uid=1000 user=justin' "$T3" \
        && ok "Startmenue: the footer user is justin after the sign-in (not root)" \
        || bad "'launcher: uid=1000 user=justin' fehlt -- das Startmenue behielte 'root' (r1059)"
    grep -qaE 'glogin: desktop pid=[0-9]+' "$T3" \
        && ok "und er hat den Schreibtisch gestartet" \
        || bad "'glogin: desktop pid=' fehlt"
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
    if grep -qa 'glogin: angemeldet' "$T4"; then
        bad "nach einem falschen Kennwort wurde trotzdem angemeldet"
    else
        ok "GEGENPROBE: kein 'angemeldet' -- kein Weg an der Anmeldung vorbei"
    fi
    if grep -qaE 'startkennwort|osumroot' "$T4"; then
        bad "ein Kennwort steht im seriellen Mitschnitt"
    else
        ok "GEGENPROBE: kein Kennwort im seriellen Mitschnitt"
    fi
else
    bad "Abschnitt 4: kein Bericht entstanden"
fi

kopf "5. ABMELDEN beendet die Sitzung und holt den Anmeldeschirm"
#
if grep -qE "(^|[[:space:]])/etc/uitrace([[:space:]]|\$)" "$LISTE"; then
    AB="$WURZEL/.logind-mess/abmelden.log"
    if python3 pruef/abmelden.py "$BUILD" "$WURZEL/belege/logind" > "$AB" 2>&1; then
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

kopf "6. GEGENPROBE: ohne 'anmeldung' ist der alte Weg unveraendert"
T6=$(lauf ohne 45 "" @10 '#foto:direkt')
if [ -f "$T6" ]; then
    grep -qa 'desk: OHNE anmeldung' "$T6" \
        && ok "ohne das Wort meldet der Kern den alten Weg" \
        || bad "'desk: OHNE anmeldung' fehlt"
    grep -qaE 'desk: start /bin/desktop' "$T6" \
        && ok "und startet den Schreibtisch direkt" \
        || bad "'desk: start /bin/desktop' fehlt"
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
