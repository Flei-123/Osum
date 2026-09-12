#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sync/run.sh -- RUNDE SYNC: der Abgleich zweier Geraete ueber
# einen Server, der nichts mitlesen kann.
#
# Was hier gemessen wird, und in welcher Reihenfolge:
#
#   1. BAUEN. Kern, Programme, das gehostete Orakel. Kein Programm mit
#      einem undefinierten Namen.
#   2. DIE BAUSTEINE GEGEN IHRE NORMEN (tools/sync/vectors.py, auf dem
#      WIRT): scrypt gegen RFC 7914 und Pythons hashlib, HKDF gegen
#      RFC 5869, XChaCha20-Poly1305 gegen libsodium, der
#      Wiederherstellungscode hin und zurueck samt Tippfehlern.
#   3. (a) ZWEI SYSTEME, EIN KONTO. Auf A eine Datei anlegen, abgleichen;
#      der WIRT nimmt den Speicher, wie ein Anbieter ihn haette, und
#      setzt damit Geraet B auf; auf B erscheint die Datei -- OKTETT FUER
#      OKTETT verglichen, aus dem Plattenabbild und nicht aus einem
#      Mitschnitt der seriellen Leitung.
#   4. (b) DER SERVER SIEHT NICHTS. Der ganze Speicher wird nach einem
#      bekannten Klartext durchsucht -- Oktette, Namen, Wurzel.
#   5. (c) DER WIEDERERKENNUNGSANGRIFF, mit und ohne HMAC, beide
#      Ergebnisse gemessen. Mit Gegenprobe: mit dem Schluessel werden
#      dieselben Dateien sehr wohl gefunden.
#   6. (d) FALSCHE PASSPHRASE -- kein Teilklartext, keine Auskunft. Und
#      der Wiederherstellungscode holt den Zugang zurueck.
#   7. (e) EIN BOESARTIGER SERVER: geaenderte, alte, fremde, zu grosse
#      Bloecke und eine luegende Wurzel. Der Rueckschritt ist der
#      wichtigste Fall.
#   8. (f) ABBRUCH MITTEN IM ABGLEICH, 30 mal mit SIGKILL. Danach ist der
#      lokale Zustand gueltig und der Abgleich nimmt wieder auf.
#   9. (g) KONFLIKT: dieselbe Datei auf beiden Geraeten geaendert --
#      BEIDE Fassungen sind da.
#  10. (h) DER TRESOR: Frist, Recht, und ein Geheimnis, das nie in eine
#      Datei kommt.
#  11. (i) OHNE KONTO geht alles weiter -- und der Umzug per Stick
#      (`backup` aus Runde TRESOR) ist unveraendert.
#  12. (j) VIER ABSICHTLICH KAPUTTE FASSUNGEN, die den Test wirklich
#      fallen lassen muessen.
#  13. DIE MESSUNGEN.
#
# Verwendung:  bash tools/sync/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
BLOCKS=6144
PROGS="sh ls cat echo mkdir rm cp sync tresor backup key bsect"

TMPD=$(mktemp -d)
# WAS BEIM ABBRUCH ZURUECKBLEIBEN DARF: nichts. (j3) muss kernel/user/sync.fi
# kurz durch eine kaputte Fassung ersetzen -- ein Programm baut nur aus
# seinem eigenen Pfad, da hilft kein FIRNLIB. Also legt es vorher eine
# Kopie unter $TMPD/sync.sicher, und dieser Trap spielt sie auch dann
# zurueck, wenn der Lauf mit Strg-C oder einem Signal endet.
aufraeumen() {
    if [ -s "$TMPD/sync.sicher" ]; then
        cp "$TMPD/sync.sicher" kernel/user/sync.fi
    fi
    rm -rf "$TMPD"
}
trap aufraeumen EXIT INT TERM

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
feld() { tr -cd '\11\12\15\40-\176' < "$1" | grep -a "^$2: " | tail -1 | sed "s/^$2: //"; }
feld_n() { tr -cd '\11\12\15\40-\176' < "$1" | grep -a "^$2: " | sed -n "$3p" | sed "s/^$2: //"; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SYNC: uebersprungen, qemu fehlt"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SYNC: uebersprungen, python3 fehlt"; exit 0; }

# =====================================================================
echo "== 1. bauen =="
# =====================================================================
mkdir -p .probe
if $FIRNC tools/sync/oracle.fi -o .probe/syncoracle 2>"$TMPD/e"; then
    ok "tools/sync/oracle.fi baut gegen lib/crypto/ und lib/sync/"
else
    bad "das Orakel baut nicht"; head -12 "$TMPD/e" | sed 's/^/        /'
fi

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "firnc0 baut den Kern" \
    || { bad "firnc0 baut den Kern nicht"; sed 's/^/        /' "$TMPD/b0.txt" | head -12; }
[ -f "$TMPD/k0.img" ] || { echo "SYNC: $pass passed, $((fail+1)) failed"; exit 1; }

bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/bprog.txt" 2>&1 \
    && ok "firnc0 baut $(echo $PROGS | wc -w) Programme in Ring 3" \
    || { bad "firnc0 baut nicht alle Programme"
         sed 's/^/        /' "$TMPD/bprog.txt" | head -14; }
[ -f "$TMPD/bin/sync.elf" ] || { echo "SYNC: $pass passed, $((fail+1)) failed"; exit 1; }

undef=""
for p in sync tresor; do
    u=$(nm -u "$TMPD/bin/$p.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "weder /bin/sync noch /bin/tresor hat einen undefinierten Namen" \
               || bad "undefinierte Namen:$undef"
note "/bin/sync: $(stat -c%s "$TMPD/bin/sync.elf") Oktette, /bin/tresor: $(stat -c%s "$TMPD/bin/tresor.elf") Oktette"

# Und die zweite Stufe: derselbe Quelltext durch den Uebersetzer, der
# selbst in Firn geschrieben ist.
if bash tools/sync/build.sh "$TMPD/bin1" 1 sync tresor > "$TMPD/b1.txt" 2>&1; then
    ok "firnc1 baut sync und tresor ebenfalls"
else
    note "firnc1 hat nicht gebaut -- gemessen wird mit firnc0"
    sed 's/^/        /' "$TMPD/b1.txt" | head -6
fi

# =====================================================================
echo "== 2. die Bausteine gegen ihre Normen (auf dem Wirt) =="
# =====================================================================
if python3 tools/sync/vectors.py > "$TMPD/vec.txt" 2>&1; then
    grep -E '^  ' "$TMPD/vec.txt" | sed 's/^/     /'
    ok "$(tail -1 "$TMPD/vec.txt")"
else
    bad "die Testvektoren sind durchgefallen"
    tail -25 "$TMPD/vec.txt" | sed 's/^/        /'
fi

# =====================================================================
# Die Werkzeuge, mit denen ein Geraet gebaut und wieder ausgelesen wird.
# =====================================================================
# spec_von <wirtsverzeichnis> <praefix im abbild>  -> mkfs-Argumente
spec_von() {
    local hd=$1 pre=$2
    [ -d "$hd" ] || return 0
    ( cd "$hd" && find . -type d | sed 's|^\./\{0,1\}||' | while read -r d; do
        [ -z "$d" ] && echo "$pre/" || echo "$pre/$d/"
      done
      find . -type f | sed 's|^\./||' | while read -r f; do
        echo "$pre/$f=$hd/$f"
      done )
}

# hol <abbild> <praefix> <zielverzeichnis>
hol() {
    local img=$1 pre=$2 ziel=$3
    rm -rf "$ziel"; mkdir -p "$ziel"
    python3 tools/osum/mkfs.py list "$img" 2>/dev/null | awk '{print $1}' \
    | grep "^$pre/" | while read -r p; do
        local rel=${p#"$pre/"}
        if [ "${p%/}" != "$p" ]; then
            mkdir -p "$ziel/${rel%/}"
        else
            mkdir -p "$ziel/$(dirname "$rel")"
            python3 tools/osum/mkfs.py cat "$img" "$p" > "$ziel/$rel" 2>/dev/null
        fi
    done
}

# geraet <abbild> <skriptdatei> <kontoverz|-> <storeverz|-> <datenverz|-> <tresorverz|->
geraet() {
    local img=$1 skript=$2 kd=$3 sd=$4 dd=$5 td=$6
    local spec=""
    [ "$kd" != "-" ] && spec="$spec $(spec_von "$kd" /konto)"
    [ "$sd" != "-" ] && spec="$spec $(spec_von "$sd" /store)"
    [ "$dd" != "-" ] && spec="$spec $(spec_von "$dd" /daten)"
    [ "$td" != "-" ] && spec="$spec $(spec_von "$td" /tresor)"
    python3 tools/osum/mkfs.py build "$img" $BLOCKS \
        /bin/ /t/ /proc/ /dev/ /konto/ /store/ /daten/ /tresor/ /system/ \
        $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
        /t/s.sh="$skript" \
        $spec > "$TMPD/mkfs.txt" 2>&1
}

lauf() { # <abbild> <name>  -> Beendigungscode
    bash tools/sync/lauf.sh "$TMPD/k0.img" "$1" "$TMPD/$2.txt" /t/s.sh
}

klar() { tr -cd '\11\12\15\40-\176' < "$TMPD/$1.txt" | grep -v '^elf:'; }

# =====================================================================
echo "== 3. (a) zwei Systeme, ein Konto =="
# =====================================================================
PASS=geheimeslosungswort
NP=256   # scrypt N fuer den Testlauf -- die Begruendung steht in kbund.fi B2
RP=8

mkdir -p "$TMPD/daten/unter"
printf 'die erste zeile\nGEHEIMNIS-4711 steht hier\n' > "$TMPD/daten/a.txt"
head -c 9000 /dev/urandom > "$TMPD/daten/unter/b.bin"
printf 'hallo\n' > "$TMPD/daten/klein.txt"
printf '100 farbe blau\n100 sprache de\n' > "$TMPD/daten/EINST"
# EINE DATEI, DIE NICHT IN EINE ZEILE PASST. Ihre Bloecke heissen
# zusammen 49 x 65 = 3185 Oktette -- mehr als die 1024 einer
# Verzeichniszeile. Bis diese Datei hier stand, war der groesste Prueffall
# 9000 Oktette gross, und ALLES darueber fiel STILL aus dem Abgleich:
# `datei_zeile` scheiterte an einem Feld von 700 Oktetten, der Aufrufer
# machte mit `continue` weiter, und der Lauf meldete "fertig". Das ist
# der schlimmste denkbare Ausgang, und kein einziger Test sah ihn.
head -c 200000 /dev/urandom > "$TMPD/daten/gross.bin"
# Eine Datei, die der Nutzer NICHT hat -- fuer den Angriff in (c).
mkdir -p "$TMPD/fremd"
printf 'diese datei hat er nicht\n' > "$TMPD/fremd/x.txt"

cat > "$TMPD/sA.sh" <<EOS
echo ==NEU==
sync neu /konto $PASS eigen /store $NP $RP
echo ==AB==
sync abgleich /konto /daten $PASS
echo ==END==
EOS
geraet "$TMPD/A.img" "$TMPD/sA.sh" - - "$TMPD/daten" - \
    && ok "mkfs.py baut Geraet A" || bad "mkfs.py fehlgeschlagen"
rc=$(lauf "$TMPD/A.img" A)
is "Geraet A endet ordentlich" "$rc" "21"
klar A > "$TMPD/A.log"
hat "$TMPD/A.log" "wiederherstellungscode: " "A zeigt den Wiederherstellungscode"
hat "$TMPD/A.log" "ACHTUNG: ohne Passphrase UND ohne Wiederherstellungscode" \
    "und die Warnung steht VOR dem Anlegen"
CODE=$(grep -a '^wiederherstellungscode: ' "$TMPD/A.log" | tail -1 | sed 's/^wiederherstellungscode: //')
note "Code: $CODE"
is "der Code hat 65 Zeichen" "${#CODE}" "65"
is "A meldet fertig" "$(klar A | grep -c '^fertig')" "1"
A_DAT=$(feld "$TMPD/A.txt" dateien)
A_BLK=$(feld "$TMPD/A.txt" bloecke)
A_NEU=$(feld "$TMPD/A.txt" neubloecke)
A_GEN=$(feld "$TMPD/A.txt" generation)
is "A sieht 5 Dateien" "$A_DAT" "5"
is "A legt alle Bloecke neu ab" "$A_NEU" "$A_BLK"
is "A schreibt Generation 1" "$A_GEN" "1"

hol "$TMPD/A.img" /store "$TMPD/store1"
hol "$TMPD/A.img" /konto "$TMPD/kontoA"
[ -f "$TMPD/store1/PACK" ] && ok "der Speicher hat PACK, INDEX und ROOT" \
                           || bad "der Speicher ist unvollstaendig"
note "Speicher: PACK $(stat -c%s "$TMPD/store1/PACK" 2>/dev/null) Oktette, INDEX $(stat -c%s "$TMPD/store1/INDEX" 2>/dev/null), ROOT $(stat -c%s "$TMPD/store1/ROOT" 2>/dev/null)"

# Geraet B: dasselbe Konto (nur der KOPF reist), derselbe Speicher, ein
# LEERER Datenbaum. Mehr braucht ein zweites Geraet nicht -- kein
# ZAEHLER, kein BASIS, keine Anmeldung.
mkdir -p "$TMPD/kontoB"
cp "$TMPD/kontoA/KOPF" "$TMPD/kontoB/KOPF"
mkdir -p "$TMPD/leer"
cat > "$TMPD/sB.sh" <<EOS
echo ==AB==
sync abgleich /konto /daten $PASS
echo ==LS==
ls /daten
echo ==END==
EOS
geraet "$TMPD/B.img" "$TMPD/sB.sh" "$TMPD/kontoB" "$TMPD/store1" "$TMPD/leer" - \
    && ok "mkfs.py baut Geraet B (nur KOPF und Speicher, kein ZAEHLER)" \
    || bad "mkfs.py fehlgeschlagen"
rc=$(lauf "$TMPD/B.img" B)
is "Geraet B endet ordentlich" "$rc" "21"
klar B > "$TMPD/B.log"
B_RUNTER=$(feld "$TMPD/B.txt" heruntergel)
B_EINST=$(feld "$TMPD/B.txt" einstellungen)
# DREI DOKUMENTE, NICHT VIER. `heruntergel` zaehlt Dokumente. Die vierte
# Datei ist `EINST`, und die kommt NICHT ueber denselben Weg herunter:
# Einstellungen werden je Schluessel gemischt (letzter Schreiber gewinnt,
# mit Verlauf) und nicht als Datei kopiert -- der Grund steht in
# `kernel/user/sync.fi` im Kopf. Dass EINST trotzdem und Oktett fuer
# Oktett ankommt, misst der Vergleich aus dem Plattenabbild weiter unten.
# Die frueheren "4" hier war schlicht falsch gezaehlt.
is "B holt 4 Dokumente herunter" "$B_RUNTER" "4"
[ -n "$B_EINST" ] && [ "$B_EINST" -gt 0 ] \
    && ok "und EINST kommt ueber den Einstellungsweg: $B_EINST Schluessel gemischt" \
    || bad "B hat keine Einstellung gemischt: '$B_EINST'"
is "B meldet fertig" "$(klar B | grep -c '^fertig')" "1"

# DER EIGENTLICHE NACHWEIS: der WIRT liest B's Baum aus dem Abbild.
hol "$TMPD/B.img" /daten "$TMPD/datenB"
gleich=0
ungleich=""
for f in a.txt klein.txt EINST unter/b.bin gross.bin; do
    if [ -f "$TMPD/datenB/$f" ] && cmp -s "$TMPD/daten/$f" "$TMPD/datenB/$f"; then
        gleich=$((gleich+1))
    else
        ungleich="$ungleich $f"
    fi
done
is "(a) alle fuenf Dateien sind auf B Oktett fuer Oktett dieselben" "$gleich" "5"
note "darunter gross.bin mit 200000 Oktetten -- 49 Bloecke, deren Namen als eigene Kette (K-Form) abgelegt sind"
[ -n "$ungleich" ] && note "ungleich:$ungleich"
note "verglichen wurde aus dem Plattenabbild, nicht aus der seriellen Leitung"

# =====================================================================
echo "== 4./5. (b) der Server sieht nichts, (c) der Wiedererkennungsangriff =="
# =====================================================================
cp "$TMPD/kontoA/KOPF" "$TMPD/store1/KOPF"   # der Angreifer darf den Kopf haben
if python3 tools/sync/schnueffel.py "$TMPD/store1" "$TMPD/daten" "$PASS" \
    "$NP" "$RP" --habe "$TMPD/daten/a.txt" "$TMPD/daten/klein.txt" \
    "$TMPD/daten/unter/b.bin" "$TMPD/daten/gross.bin" \
    --habe-nicht "$TMPD/fremd/x.txt" \
    > "$TMPD/schn.txt" 2>&1; then
    sed 's/^/     /' "$TMPD/schn.txt"
    ok "$(tail -1 "$TMPD/schn.txt")"
else
    sed 's/^/     /' "$TMPD/schn.txt"
    bad "der Schnueffler hat etwas gefunden"
fi
rm -f "$TMPD/store1/KOPF"

# =====================================================================
echo "== 6. (d) falsche Passphrase, und der Weg zurueck =="
# =====================================================================
cat > "$TMPD/sD.sh" <<EOS
echo ==FALSCH==
sync abgleich /konto /daten diesistfalsch
echo ==FASTRICHTIG==
sync auf /konto ${PASS}x
echo ==CODE==
sync code /konto $CODE
echo ==CODEFALSCH==
sync code /konto 00000-00000-00000-00000-00000-00000-00000-00000-00000-00000-00000
echo ==RICHTIG==
sync auf /konto $PASS
echo ==END==
EOS
geraet "$TMPD/D.img" "$TMPD/sD.sh" "$TMPD/kontoB" "$TMPD/store1" "$TMPD/leer" -
rc=$(lauf "$TMPD/D.img" D)
is "der Passphrasenlauf endet ordentlich" "$rc" "21"
klar D > "$TMPD/D.log"
absch() { sed -n "/^==$1==/,/^==/p" "$TMPD/D.log"; }
absch FALSCH | grep -qa 'falsche Passphrase' \
    && ok "(d) eine falsche Passphrase wird abgewiesen" \
    || bad "(d) eine falsche Passphrase wird NICHT abgewiesen"
absch FALSCH | grep -qa 'fertig' \
    && bad "(d) der Abgleich lief trotzdem" \
    || ok "(d) und es wird NICHTS abgeglichen"
absch FASTRICHTIG | grep -qa 'falsche Passphrase' \
    && ok "(d) ein einziges Zeichen daneben reicht" \
    || bad "(d) eine fast richtige Passphrase kam durch"
absch CODE | grep -qa 'konto: auf' \
    && ok "(d) der Wiederherstellungscode holt den Zugang zurueck" \
    || bad "(d) der Wiederherstellungscode wirkt nicht"
absch CODEFALSCH | grep -qa 'nicht gueltig' \
    && ok "(d) ein erfundener Code wird abgewiesen" \
    || bad "(d) ein erfundener Code kam durch"
absch RICHTIG | grep -qa 'konto: auf' \
    && ok "(d) und die richtige Passphrase geht weiterhin" \
    || bad "(d) die richtige Passphrase geht nicht mehr"
# KEIN TEILKLARTEXT: im ganzen Lauf darf der Klartext nirgends auftauchen.
nicht "$TMPD/D.log" "GEHEIMNIS-4711" "(d) kein Teilklartext im ganzen Lauf"

# =====================================================================
echo "== 7. (e) ein boesartiger Server =="
# =====================================================================
cat > "$TMPD/sE.sh" <<EOS
echo ==AB==
sync abgleich /konto /daten $PASS
echo ==LS==
ls /daten
echo ==END==
EOS
boese_lauf() { # <was> <erwarteter text> <name> [extra]
    local was=$1 erw=$2 nm=$3 extra=${4:-}
    rm -rf "$TMPD/sb-$nm"; cp -r "$TMPD/store1" "$TMPD/sb-$nm"
    python3 tools/sync/boese.py "$was" "$TMPD/sb-$nm" $extra > "$TMPD/boese-$nm.txt" 2>&1
    note "$was: $(cat "$TMPD/boese-$nm.txt")"
    geraet "$TMPD/E-$nm.img" "$TMPD/sE.sh" "$TMPD/kontoB" "$TMPD/sb-$nm" "$TMPD/leer" -
    lauf "$TMPD/E-$nm.img" "E-$nm" > /dev/null
    klar "E-$nm" > "$TMPD/E-$nm.log"
    if grep -qa "$erw" "$TMPD/E-$nm.log"; then
        ok "(e) $was wird erkannt und abgelehnt"
    else
        bad "(e) $was wird NICHT erkannt"
        grep -a 'sync:\|fehler\|fertig' "$TMPD/E-$nm.log" | head -4 | sed 's/^/        /'
    fi
}
boese_lauf aendern      "fehler"      aendern
boese_lauf fremd        "fehler"      fremd
boese_lauf gross        "fehler"      gross
boese_lauf wurzelluege  "gefaelscht"  luege
boese_lauf halbe        "gefaelscht"  halbe

# DER RUECKSCHRITT -- der wichtigste Fall. Er braucht ein Geraet, das
# schon eine hoehere Generation gesehen hat, also einen ZAEHLER.
rm -rf "$TMPD/kontoR"; cp -r "$TMPD/kontoA" "$TMPD/kontoR"
printf '9\n' > "$TMPD/kontoR/ZAEHLER"
rm -rf "$TMPD/sb-rueck"; cp -r "$TMPD/store1" "$TMPD/sb-rueck"
geraet "$TMPD/E-rueck.img" "$TMPD/sE.sh" "$TMPD/kontoR" "$TMPD/sb-rueck" "$TMPD/leer" -
lauf "$TMPD/E-rueck.img" E-rueck > /dev/null
klar E-rueck > "$TMPD/E-rueck.log"
if grep -qa 'RUECKSCHRITT' "$TMPD/E-rueck.log"; then
    ok "(e) DER RUECKSCHRITT wird erkannt (Zaehler 9, Speicher bietet 1)"
else
    bad "(e) DER RUECKSCHRITT wird NICHT erkannt -- ein Server kann alte Daten unterschieben"
    grep -a 'sync:\|generation' "$TMPD/E-rueck.log" | head -4 | sed 's/^/        /'
fi
# Die GEGENPROBE: derselbe Speicher mit einem Zaehler, der passt, geht.
rm -rf "$TMPD/kontoR2"; cp -r "$TMPD/kontoA" "$TMPD/kontoR2"
printf '1\n' > "$TMPD/kontoR2/ZAEHLER"
geraet "$TMPD/E-ok.img" "$TMPD/sE.sh" "$TMPD/kontoR2" "$TMPD/store1" "$TMPD/leer" -
lauf "$TMPD/E-ok.img" E-ok > /dev/null
klar E-ok > "$TMPD/E-ok.log"
grep -qa 'fertig' "$TMPD/E-ok.log" \
    && ok "(e) GEGENPROBE: mit passendem Zaehler laeuft derselbe Speicher durch" \
    || bad "(e) GEGENPROBE: auch der heile Speicher wird abgelehnt"

# =====================================================================
echo "== 8. (f) Abbruch mitten im Abgleich, 30 mal =="
# =====================================================================
mkdir -p "$TMPD/gross"
i=0
while [ $i -lt 12 ]; do
    head -c 12000 /dev/urandom > "$TMPD/gross/d$i.bin"
    i=$((i+1))
done
# ZWEI ABGLEICHE UND NICHT EINER, und das ist der Kern dieses
# Abschnitts. Beim ersten Anlauf stand hier nur einer -- und in 30 von
# 30 Faellen lag danach GAR KEINE Wurzel auf der Platte, weil die Wurzel
# ZULETZT geschrieben wird und der Systemstart den groessten Teil der
# Laufzeit frisst. "Nie eine halbe Wurzel gefunden" war damit eine
# Aussage ueber null Faelle, und das ist keine Aussage.
#
# Jetzt laeuft der erste Abgleich durch (Generation 1 liegt, ROOT ist
# da), dann aendert sich der Baum, und der ZWEITE wird abgeschossen.
# Damit ist in fast jedem Abbruch eine Wurzel auf der Platte, und die
# Frage "ganz oder halb" hat einen Gegenstand.
cat > "$TMPD/sF.sh" <<EOS
sync neu /konto $PASS eigen /store $NP $RP
sync abgleich /konto /daten $PASS
echo ==ERSTER-DURCH==
cp /daten/d0.bin /daten/n0.bin
cp /daten/d1.bin /daten/n1.bin
cp /daten/d2.bin /daten/n2.bin
cp /daten/d3.bin /daten/n3.bin
cp /daten/d4.bin /daten/n4.bin
cp /daten/d5.bin /daten/n5.bin
sync abgleich /konto /daten $PASS
echo ==END==
EOS
geraet "$TMPD/F0.img" "$TMPD/sF.sh" - - "$TMPD/gross" -

# ZUERST MESSEN, DANN SCHIESSEN. Frueher stand hier ein fester Zeitraum
# von 1 bis 4 Sekunden. Das ist geraten, und auf einem Wirt unter Last
# war es falsch geraten: der Abbruch kam, bevor das Konto ueberhaupt
# angelegt war. Ergebnis: 30 Laeufe, 0 Wurzeln, kein Konto -- und ein
# roter Test, der nichts ueber das Programm sagte, sondern nur ueber die
# Laune des Wirtes. Also wird EIN Lauf ungestoert zu Ende gefahren und
# gestoppt; die Abbrueche liegen dann zwischen 20 % und 95 % DIESER Zeit.
cp "$TMPD/F0.img" "$TMPD/Fv.img"
tv0=$(date +%s%N)
SYNC_TIMEOUT=900 lauf "$TMPD/Fv.img" Fv > /dev/null
tv1=$(date +%s%N)
F_VOLL=$(( (tv1 - tv0) / 1000000 ))
klar Fv > "$TMPD/Fv.log"
grep -qa '^==END==' "$TMPD/Fv.log" \
    && ok "(f) der ungestoerte Vergleichslauf kommt durch: $F_VOLL ms" \
    || bad "(f) schon der ungestoerte Lauf kommt nicht durch"
[ "$F_VOLL" -lt 1500 ] && F_VOLL=1500
rm -f "$TMPD/Fv.img"

kills=0
gefunden=0
konten=0
halbe=0
letztes=""
n=0
while [ $n -lt 30 ]; do
    cp "$TMPD/F0.img" "$TMPD/F-$n.img"
    : > "$TMPD/F.txt"
    # KEIN `timeout` DAVOR. `timeout 900 qemu &` macht `$!` zur Nummer
    # des TIMEOUT-Prozesses; `kill -9 $!` erschlaegt dann den Waechter
    # und laesst QEMU weiterlaufen -- in ein Abbild hinein, das der
    # Laeufer im selben Augenblick herausliest. Gebraucht wird der
    # Waechter hier ohnehin nicht: dieser Abschnitt schiesst JEDEN Lauf
    # selbst ab.
    qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/F.txt" -display none -no-reboot \
        -drive "file=$TMPD/F-$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    qp=$!
    # 45 BIS 99 % UND NICHT 20 BIS 95. Die Wurzel wird ZULETZT
    # geschrieben -- erst alle Bloecke, dann `ROOT`. Ein Fenster, das bei
    # 95 % aufhoert, trifft die Stelle nie: der erste Lauf dieses
    # Abschnitts brach 30 von 30 Mal ab, BEVOR ueberhaupt eine Wurzel auf
    # der Platte lag, und "keine halbe Wurzel gefunden" war damit eine
    # Aussage ueber nichts. Interessant ist genau der schmale Streifen
    # zwischen dem ersten Block und der fertigen Wurzel.
    # 50 BIS 99 %: der erste Abgleich ist dann durch (die Wurzel liegt),
    # der zweite ist mittendrin. Das ist der Streifen, der etwas misst.
    ms=$(( (F_VOLL * 50 / 100) + (RANDOM % (F_VOLL * 49 / 100)) ))
    sleep "$(awk "BEGIN{print $ms/1000}")"
    if kill -0 "$qp" 2>/dev/null; then
        kill -9 "$qp" 2>/dev/null
        kills=$((kills+1))
    fi
    wait "$qp" 2>/dev/null
    # Was auf der Platte steht, muss ENTWEDER kein oder ein GANZES ROOT
    # sein -- niemals ein halbes.
    hol "$TMPD/F-$n.img" /store "$TMPD/fs-$n" 2>/dev/null
    hol "$TMPD/F-$n.img" /konto "$TMPD/fk-$n" 2>/dev/null
    if [ -f "$TMPD/fk-$n/KOPF" ]; then
        konten=$((konten+1))
        letztes=$n
        # NUR DAS LETZTE BRAUCHBARE ABBILD BLEIBT LIEGEN. Dreissig
        # Abbilder zu je 24 MiB sind 720 MiB, und ein Testlauf, der die
        # Platte des Wirtes vollschreibt, faellt nicht nur selbst um,
        # sondern nimmt alles andere mit -- genau das ist hier einmal
        # passiert.
        rm -f "$TMPD/Flast.img"
        mv "$TMPD/F-$n.img" "$TMPD/Flast.img"
    fi
    rm -f "$TMPD/F-$n.img"
    rm -rf "$TMPD/fk-$n"
    if [ -f "$TMPD/fs-$n/ROOT" ]; then
        gefunden=$((gefunden+1))
        # GANZ heisst: Kopfwort, Generation, Blockname und Siegel, und
        # sonst nichts. Eine halbe Wurzel waere ein zerrissener Zustand.
        if ! grep -qaE '^osumwurzel1 [0-9]+ [0-9a-f]{64} [0-9a-f]{64}$' \
                "$TMPD/fs-$n/ROOT"; then
            halbe=$((halbe+1))
            note "Lauf $n: ROOT ist nicht ganz: $(head -c 120 "$TMPD/fs-$n/ROOT" | tr -d '\n')"
        fi
    fi
    n=$((n+1))
done
note "$kills von 30 Laeufen wurden wirklich mit SIGKILL abgebrochen"
note "Abbruchfenster: 50-99 % von $F_VOLL ms"
is "(f) 30 Abbrueche gefahren" "$n" "30"
num_ge=$gefunden
note "$num_ge davon hatten schon eine Wurzel auf der Platte, $konten ein Konto"
# EINE ZUSAGE UEBER NULL FAELLE IST KEINE ZUSAGE. "keine halbe Wurzel"
# heisst nur dann etwas, wenn ueberhaupt Wurzeln da waren.
[ "$num_ge" -ge 1 ] \
    && ok "(f) $num_ge Abbrueche lagen NACH dem Schreiben der Wurzel" \
    || bad "(f) kein einziger Abbruch traf die Wurzel -- (f) misst die falsche Stelle"
is "(f) KEINE halbe Wurzel, in keinem der 30 Faelle" "$halbe" "0"
[ "$kills" -ge 15 ] \
    && ok "(f) die Abbrueche trafen wirklich mitten hinein: $kills von 30" \
    || bad "(f) nur $kills von 30 Laeufen liefen ueberhaupt noch -- das Fenster passt nicht"
[ "$konten" -ge 1 ] \
    && ok "(f) mindestens ein abgebrochener Lauf hatte schon ein Konto: $konten" \
    || bad "(f) kein einziger Abbruch hat es bis zum Konto geschafft"
# Weitergefahren wird der LETZTE Abbruch, der ueberhaupt ein Konto hat --
# und nicht blind der letzte Lauf.
if [ -n "$letztes" ]; then
    cp "$TMPD/Flast.img" "$TMPD/F.img"
    note "weitergefahren wird Lauf $letztes"
fi

# Der Wiederaufnahmetest: der zuletzt abgebrochene Zustand wird
# weitergefahren, und danach ist der Baum vollstaendig.
cat > "$TMPD/sF2.sh" <<EOS
echo ==AB==
sync abgleich /konto /daten $PASS
echo ==END==
EOS
hol "$TMPD/F.img" /konto "$TMPD/kontoF"
hol "$TMPD/F.img" /store "$TMPD/storeF"
if [ -f "$TMPD/kontoF/KOPF" ]; then
    geraet "$TMPD/F2.img" "$TMPD/sF2.sh" "$TMPD/kontoF" "$TMPD/storeF" "$TMPD/gross" -
    rc=$(lauf "$TMPD/F2.img" F2)
    klar F2 > "$TMPD/F2.log"
    grep -qa 'fertig' "$TMPD/F2.log" \
        && ok "(f) nach dem Abbruch nimmt der Abgleich wieder auf und wird fertig" \
        || bad "(f) nach dem Abbruch kommt der Abgleich nicht mehr durch"
    # und das Ergebnis stimmt: ein drittes Geraet holt sich alles daraus
    hol "$TMPD/F2.img" /store "$TMPD/storeF2"
    mkdir -p "$TMPD/kontoF2"; cp "$TMPD/kontoF/KOPF" "$TMPD/kontoF2/KOPF"
    geraet "$TMPD/F3.img" "$TMPD/sB.sh" "$TMPD/kontoF2" "$TMPD/storeF2" "$TMPD/leer" -
    lauf "$TMPD/F3.img" F3 > /dev/null
    hol "$TMPD/F3.img" /daten "$TMPD/datenF3"
    g=0
    i=0
    while [ $i -lt 12 ]; do
        cmp -s "$TMPD/gross/d$i.bin" "$TMPD/datenF3/d$i.bin" && g=$((g+1))
        i=$((i+1))
    done
    is "(f) und alle 12 Dateien kommen danach heil beim naechsten Geraet an" "$g" "12"
    # Und die sechs Kopien, die der abgeschossene ZWEITE Abgleich
    # hochladen wollte: entweder ganz da oder gar nicht da -- niemals
    # halb. Wieviele es sind, haengt davon ab, wann der Schuss fiel;
    # dass keine davon zerrissen ist, haengt am Programm.
    hin=0; kaputt=0
    i=0
    while [ $i -lt 6 ]; do
        if [ -f "$TMPD/datenF3/n$i.bin" ]; then
            if cmp -s "$TMPD/gross/d$i.bin" "$TMPD/datenF3/n$i.bin"; then
                hin=$((hin+1))
            else
                kaputt=$((kaputt+1))
            fi
        fi
        i=$((i+1))
    done
    note "vom abgebrochenen zweiten Abgleich kamen $hin von 6 Kopien ganz an"
    is "(f) und KEINE davon kam halb an" "$kaputt" "0"
else
    bad "(f) nach den Abbruechen gibt es kein Konto mehr"
fi

# =====================================================================
echo "== 8b. der eigene Datentraeger laeuft voll =="
# =====================================================================
# NICHT AUS DER AUFGABE, SONDERN AUS EINEM MESSFEHLER. Der Messabschnitt
# unten meldete einmal 245 Bloecke statt 302, einen INDEX, der auf dem
# Wirt leer ankam, und einen Mehraufwand von MINUS 16,9 %. Der Grund war
# nicht das Programm, sondern das Abbild: 3 MiB, und die Bloecke passten
# nicht hinein. Damit ist die Frage aufgeworfen, die niemand gestellt
# hatte -- was tut der Abgleich, wenn der eigene Datentraeger voll
# laeuft? Er darf NICHT "fertig" sagen und er darf KEINE Wurzel
# schreiben, denn eine Wurzel verspricht Bloecke, die es nicht gibt.
mkdir -p "$TMPD/vollmess"
i=0
while [ $i -lt 20 ]; do
    head -c 51200 /dev/urandom > "$TMPD/vollmess/v$i.bin"
    i=$((i+1))
done
cat > "$TMPD/sV.sh" <<EOS
echo ==AB==
sync neu /konto $PASS eigen /store $NP $RP
sync abgleich /konto /daten $PASS
echo ==END==
EOS
BLOCKS_ALT=$BLOCKS
BLOCKS=4400   # 1 MiB Daten, aber nur rund 600 KiB frei
geraet "$TMPD/V.img" "$TMPD/sV.sh" - - "$TMPD/vollmess" -
BLOCKS=$BLOCKS_ALT
SYNC_TIMEOUT=900 lauf "$TMPD/V.img" V > /dev/null
klar V > "$TMPD/V.log"
grep -qa '^fertig' "$TMPD/V.log" \
    && bad "der volle Datentraeger meldet trotzdem fertig" \
    || ok "ein voller Datentraeger meldet NICHT fertig"
grep -qa '^sync: fehler' "$TMPD/V.log" \
    && ok "sondern einen Fehler: $(grep -a '^sync: fehler' "$TMPD/V.log" | tail -1)" \
    || bad "und er meldet auch keinen Fehler -- der Abbruch ist still"
grep -qa '^sync: bei:' "$TMPD/V.log" \
    && ok "und er nennt die Datei, an der es riss: $(grep -a '^sync: bei:' "$TMPD/V.log" | tail -1 | sed 's/^sync: bei:  *//')" \
    || bad "aber nicht, WO es riss"
is "und er schreibt KEINE Wurzel (Generation bleibt 0)" \
   "$(feld "$TMPD/V.txt" generation)" "0"
hol "$TMPD/V.img" /store "$TMPD/storeV"
[ -f "$TMPD/storeV/ROOT" ] \
    && bad "es liegt trotzdem eine Wurzel im Speicher" \
    || ok "im Speicher liegt keine Wurzel, nur Oktette, auf die niemand zeigt"

# =====================================================================
echo "== 9. (g) der Konflikt =="
# =====================================================================
# B aendert a.txt und gleicht ab -> Speicher 2
cat > "$TMPD/sG1.sh" <<EOS
echo ==AB1==
sync abgleich /konto /daten $PASS
echo ==AENDERN==
echo VON-B > /daten/a.txt
echo ==AB2==
sync abgleich /konto /daten $PASS
echo ==END==
EOS
geraet "$TMPD/G1.img" "$TMPD/sG1.sh" "$TMPD/kontoB" "$TMPD/store1" "$TMPD/leer" -
lauf "$TMPD/G1.img" G1 > /dev/null
klar G1 > "$TMPD/G1.log"
hol "$TMPD/G1.img" /store "$TMPD/store2"
grep -qa 'fertig' "$TMPD/G1.log" && ok "(g) B aendert a.txt und laedt hoch" \
                                 || bad "(g) B kommt nicht durch"

# A aendert dieselbe Datei anders und trifft auf Speicher 2
cat > "$TMPD/sG2.sh" <<EOS
echo ==AENDERN==
echo VON-A > /daten/a.txt
echo ==AB==
sync abgleich /konto /daten $PASS
echo ==LS==
ls /daten
echo ==KONF==
sync konflikte /konto
echo ==A==
cat /daten/a.txt
echo ==K==
cat /daten/a.txt.konflikt
echo ==END==
EOS
geraet "$TMPD/G2.img" "$TMPD/sG2.sh" "$TMPD/kontoA" "$TMPD/store2" "$TMPD/daten" -
lauf "$TMPD/G2.img" G2 > /dev/null
klar G2 > "$TMPD/G2.log"
G_KONF=$(feld "$TMPD/G2.txt" konflikte)
is "(g) A meldet genau einen Konflikt" "$G_KONF" "1"
hol "$TMPD/G2.img" /daten "$TMPD/datenG"
[ -f "$TMPD/datenG/a.txt.konflikt" ] \
    && ok "(g) die fremde Fassung liegt als a.txt.konflikt daneben" \
    || bad "(g) es gibt keine zweite Fassung -- etwas ist still verloren gegangen"
if [ -f "$TMPD/datenG/a.txt" ] && [ -f "$TMPD/datenG/a.txt.konflikt" ]; then
    x=$(cat "$TMPD/datenG/a.txt"); y=$(cat "$TMPD/datenG/a.txt.konflikt")
    is "(g) die eigene Fassung ist geblieben" "$x" "VON-A"
    is "(g) und die fremde ist auch da" "$y" "VON-B"
fi
sed -n '/^==KONF==/,/^==A==/p' "$TMPD/G2.log" | grep -qa '/a.txt' \
    && ok "(g) sync konflikte nennt den Pfad" \
    || bad "(g) sync konflikte nennt den Pfad nicht"

# =====================================================================
echo "== 10. (h) der Tresor =="
# =====================================================================
cat > "$TMPD/sH.sh" <<EOS
echo ==OHNE==
tresor gib /tresor bank
echo ==AUF==
tresor auf /konto /tresor $PASS 300
echo ==LEGEN==
tresor legen /tresor bank GEHEIMNIS-4711
echo ==LISTE==
tresor liste /tresor
echo ==GIB==
tresor gib /tresor bank
echo ==ZU==
tresor zu /tresor
echo ==NACHZU==
tresor gib /tresor bank
echo ==FALSCHPASS==
tresor auf /konto /tresor falschespass 300
echo ==KURZ==
tresor auf /konto /tresor $PASS 1
echo ==WARTEN==
sleep 3
echo ==NACHFRIST==
tresor gib /tresor bank
echo ==END==
EOS
geraet "$TMPD/H.img" "$TMPD/sH.sh" "$TMPD/kontoA" "$TMPD/store1" "$TMPD/leer" -
rc=$(lauf "$TMPD/H.img" H)
klar H > "$TMPD/H.log"
habs() { sed -n "/^==$1==/,/^==/p" "$TMPD/H.log"; }
habs OHNE | grep -qa 'keine offene Sitzung' \
    && ok "(h) ohne Sitzung gibt es kein Geheimnis" \
    || bad "(h) ohne Sitzung kam etwas heraus"
habs AUF | grep -qa 'tresor: auf' && ok "(h) der Tresor geht mit der Passphrase auf" \
                                  || bad "(h) der Tresor geht nicht auf"
habs LEGEN | grep -qa 'gelegt' && ok "(h) ein Geheimnis laesst sich ablegen" \
                               || bad "(h) das Ablegen scheitert"
habs GIB | grep -qa 'GEHEIMNIS-4711' \
    && ok "(h) und mit offener Sitzung wieder herausholen" \
    || bad "(h) das Geheimnis kommt nicht zurueck"
habs NACHZU | grep -qa 'keine offene Sitzung' \
    && ok "(h) nach 'tresor zu' ist er zu" \
    || bad "(h) nach 'tresor zu' ist er NICHT zu"
habs FALSCHPASS | grep -qa 'falsche Passphrase' \
    && ok "(h) eine falsche Passphrase oeffnet den Tresor nicht" \
    || bad "(h) eine falsche Passphrase oeffnete den Tresor"
habs NACHFRIST | grep -qa 'Frist ist abgelaufen' \
    && ok "(h) nach der Frist ist der Tresor von selbst zu" \
    || bad "(h) die Frist wirkt nicht"
# DER KLARTEXT LIEGT IN KEINER DATEI. Der Wirt sucht ihn im ganzen Abbild.
hol "$TMPD/H.img" /tresor "$TMPD/tresorH"
found=0
for f in "$TMPD/tresorH"/*; do
    [ -f "$f" ] && grep -qaF "GEHEIMNIS-4711" "$f" && found=$((found+1))
done
is "(h) der Klartext steht in KEINER Datei des Tresors" "$found" "0"
[ -f "$TMPD/tresorH/G-bank" ] && ok "(h) das Geheimnis liegt als G-bank da (versiegelt)" \
                             || bad "(h) G-bank fehlt"

# DAS RECHT: ohne den Sitzungsschluessel in /system kommt niemand daran.
# Der Wirt nimmt ihn weg -- das ist genau der Fall "ein Programm ohne
# Recht".
hol "$TMPD/H.img" /tresor "$TMPD/tresorH2"
cat > "$TMPD/sH2.sh" <<'EOS'
echo ==OHNERECHT==
tresor gib /tresor bank
echo ==END==
EOS
geraet "$TMPD/H2.img" "$TMPD/sH2.sh" "$TMPD/kontoA" "$TMPD/store1" "$TMPD/leer" "$TMPD/tresorH2"
lauf "$TMPD/H2.img" H2 > /dev/null
klar H2 > "$TMPD/H2.log"
# Die Sitzungsdatei aus dem alten Lauf ist mitgereist, /system/tresor.sit
# aber nicht -- also fehlt genau das Recht.
if grep -qa 'kein Recht\|keine offene Sitzung\|Frist' "$TMPD/H2.log"; then
    ok "(h) ohne den Sitzungsschluessel in /system kommt kein Geheimnis heraus"
else
    bad "(h) ohne Sitzungsschluessel kam ein Geheimnis heraus"
fi
nicht "$TMPD/H2.log" "GEHEIMNIS-4711" "(h) und der Klartext steht auch nicht im Protokoll"

# =====================================================================
echo "== 11. (i) ohne Konto geht alles weiter =="
# =====================================================================
cat > "$TMPD/sI.sh" <<'EOS'
echo ==KEINKONTO==
sync abgleich /konto /daten egal
echo ==ARBEIT==
echo hallo > /daten/neu.txt
cat /daten/neu.txt
echo ==BACKUP==
backup save /daten /store s1
echo ==RESTORE==
backup restore /store s1 /leer
echo ==END==
EOS
mkdir -p "$TMPD/leer2"
python3 tools/osum/mkfs.py build "$TMPD/I.img" $BLOCKS \
    /bin/ /t/ /proc/ /dev/ /daten/ /store/ /leer/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    /daten/a.txt="$TMPD/daten/a.txt" /t/s.sh="$TMPD/sI.sh" >/dev/null 2>&1
rc=$(lauf "$TMPD/I.img" I)
klar I > "$TMPD/I.log"
is "(i) der Lauf ohne Konto endet ordentlich" "$rc" "21"
sed -n '/^==KEINKONTO==/,/^==ARBEIT==/p' "$TMPD/I.log" | grep -qa 'gibt es nicht' \
    && ok "(i) ohne Konto sagt sync das klar und tut sonst nichts" \
    || bad "(i) ohne Konto passiert etwas Unerwartetes"
sed -n '/^==ARBEIT==/,/^==BACKUP==/p' "$TMPD/I.log" | grep -qa 'hallo' \
    && ok "(i) und das System arbeitet ganz normal weiter" \
    || bad "(i) das System arbeitet nicht weiter"
sed -n '/^==BACKUP==/,/^==END==/p' "$TMPD/I.log" | grep -qa 'restored files' \
    && ok "(i) die Sicherung der Runde TRESOR ist unveraendert benutzbar" \
    || bad "(i) die Sicherung ist kaputt gegangen"

# =====================================================================
echo "== 12. (j) vier absichtlich kaputte Fassungen =="
# =====================================================================
# Eine Zusage ohne Gegenprobe ist eine Behauptung. Diese drei muessen
# den Test WIRKLICH fallen lassen.
mkdir -p "$TMPD/kaputt"

# (j1) Der Name ist wieder der blanke SHA-256 -- der Wiedererkennungs-
#      angriff muss aufgehen.
cp lib/sync/chain.fi "$TMPD/kaputt/kette.fi.orig"
python3 - "$TMPD" <<'PY'
import sys, re
d = sys.argv[1]
s = open("lib/sync/chain.fi").read()
s = s.replace("""fn block_name(namekey: u64, p: u64, n: u64, out: u64) {
    sha256.hmac(namekey, KEYLEN as usize, p, n as usize, out)
}""", """fn block_name(namekey: u64, p: u64, n: u64, out: u64) {
    sha256.hash(p, n as usize, out)
}""")
open(d + "/kaputt/kette-naiv.fi", "w").write(s)
PY
# GEBAUT WIRD GEGEN EINE KOPIE DES BIBLIOTHEKSBAUMS, nicht gegen den
# Arbeitsbaum. Die frueheren Fassungen dieses Tests haben lib/sync/chain.fi
# ueberschrieben und hinterher zurueckkopiert -- was genau so lange gut
# geht, bis der Lauf dazwischen abbricht. Dann steht die KAPUTTE Fassung
# im Arbeitsbaum, und der naechste Lauf misst Unsinn.
cp -a lib "$TMPD/lib-naiv"
cp "$TMPD/kaputt/kette-naiv.fi" "$TMPD/lib-naiv/sync/kette.fi"
if FIRNLIB="$TMPD/lib-naiv" $FIRNC tools/sync/oracle.fi \
        -o "$TMPD/naivoracle" 2>/dev/null; then
    # Mit dem naiven Namen muss der Angriff aufgehen: der Name eines
    # bekannten Blocks IST dessen SHA-256.
    r=$(python3 - "$TMPD" <<'PY'
import binascii, hashlib, os, subprocess, sys
d = sys.argv[1]
blk = os.urandom(4096)
p = subprocess.run([d + "/naivoracle"],
                   input="name %s %s\n" % ("00" * 32,
                                           binascii.hexlify(blk).decode()),
                   capture_output=True, text=True)
print("JA" if p.stdout.strip() == hashlib.sha256(blk).hexdigest() else "NEIN")
PY
)
    is "(j1) GEGENPROBE: mit dem blanken SHA-256 geht der Angriff auf" "$r" "JA"
else
    bad "(j1) die kaputte Fassung baut nicht -- die Gegenprobe misst nichts"
fi

# (j2) Das AAD faellt weg -- ein Block unter fremdem Namen muss dann
#      durchgehen.
# WAS HIER GEMESSEN WIRD, UND WARUM ES NICHT DAS IST, WAS ERST
# DASTAND. Der erste Anlauf hat nur das AAD weggenommen und erwartet,
# dass ein Block dann unter fremdem Namen aufgeht. Er ging NICHT auf --
# und das war kein Fehler des Tests, sondern eine Auskunft ueber den
# Aufbau: Schluessel UND Nonce eines Blocks kommen selbst aus dem Namen
# (`kb = HMAC(K_INHALT, name)`), also ist ein Block schon dadurch an
# seinen Platz gebunden. Das AAD ist der zweite Riegel an derselben Tuer.
#
# Gemessen wird deshalb BEIDES:
#   ohneaad     nur das AAD faellt weg  -> muss TROTZDEM dichthalten
#   losgeloest  AAD weg UND Schluessel/Nonce nicht mehr aus dem Namen
#               -> jetzt MUSS der fremde Name durchgehen
python3 - "$TMPD" <<'PYX'
import sys
d = sys.argv[1]
s = open("lib/sync/chain.fi").read()
mit = """    chacha.xaead_seal((&kb[0]) as u64, (&nc[0]) as u64, name,
        NAMELEN as usize, p, n as usize, out)"""
ohne = """    chacha.xaead_seal((&kb[0]) as u64, (&nc[0]) as u64, name,
        0, p, n as usize, out)"""
assert s.count(mit) == 1
t = s.replace(mit, ohne)
auf_mit = """    let ok: bool = chacha.xaead_open((&kb[0]) as u64, (&nc[0]) as u64,
        name, NAMELEN as usize, ct, n as usize, out)"""
auf_ohne = """    let ok: bool = chacha.xaead_open((&kb[0]) as u64, (&nc[0]) as u64,
        name, 0, ct, n as usize, out)"""
assert t.count(auf_mit) == 1
t = t.replace(auf_mit, auf_ohne)
open(d + "/kaputt/kette-ohneaad.fi", "w").write(t)

# Und die wirklich losgeloeste Fassung: das AAD ist weg UND Schluessel
# und Nonce haengen nicht mehr am Namen, sondern an einer festen
# Zeichenkette. Damit ist die Bindung an den Platz vollstaendig weg.
alt_k = """    block_schluessel(inhaltkey, name, (&kb[0]) as u64)
    block_nonce(inhaltkey, name, (&nc[0]) as u64)"""
neu_k = """    var fest: [u8; 33] = "osum-sync-block-ohne-namensbindg\\0"
    block_schluessel(inhaltkey, (&fest[0]) as u64, (&kb[0]) as u64)
    block_nonce(inhaltkey, (&fest[0]) as u64, (&nc[0]) as u64)"""
assert t.count(alt_k) == 2, t.count(alt_k)
open(d + "/kaputt/kette-losgeloest.fi", "w").write(t.replace(alt_k, neu_k))
PYX
if cmp -s "$TMPD/kaputt/kette-ohneaad.fi" lib/sync/chain.fi; then
    bad "(j2) die kaputte Fassung ist mit dem Original identisch -- sie misst nichts"
else
    # UND JETZT DER EIGENTLICHE NACHWEIS. Frueher stand hier nur ein
    # `cmp`: "die Datei ist anders". Das beweist ueber die Zusage nichts.
    # Das AAD ist der NAME des Blocks; es bindet den Block an seinen
    # Platz. Faellt es weg, laesst sich ein Block, der unter Namen A
    # versiegelt wurde, unter Namen B oeffnen -- genau der Angriff
    # "fremd" aus (e). Also wird das GEMESSEN: mit AAD scheitert das
    # Oeffnen unter falschem Namen, ohne AAD gelingt es.
    cp -a lib "$TMPD/lib-ohneaad"
    cp "$TMPD/kaputt/kette-ohneaad.fi" "$TMPD/lib-ohneaad/sync/kette.fi"
    cp -a lib "$TMPD/lib-los"
    cp "$TMPD/kaputt/kette-losgeloest.fi" "$TMPD/lib-los/sync/kette.fi"
    b1=nein; b2=nein
    FIRNLIB="$TMPD/lib-ohneaad" $FIRNC tools/sync/oracle.fi \
        -o "$TMPD/aadoracle" 2>/dev/null && b1=ja
    FIRNLIB="$TMPD/lib-los" $FIRNC tools/sync/oracle.fi \
        -o "$TMPD/losoracle" 2>/dev/null && b2=ja
    if [ "$b1" = ja ] && [ "$b2" = ja ]; then
        r=$(python3 - "$TMPD" <<'PYX'
import binascii, os, subprocess, sys
d = sys.argv[1]
k = os.urandom(32)
na, nb = os.urandom(32), os.urandom(32)
blk = os.urandom(4096)
hx = lambda b: binascii.hexlify(b).decode()


def frage(prog, zeile):
    p = subprocess.run([prog], input=zeile + "\n",
                       capture_output=True, text=True)
    return p.stdout.strip()


aus = []
for nam, prog in (("ECHT", ".probe/syncoracle"),
                  ("OHNEAAD", d + "/aadoracle"),
                  ("LOS", d + "/losoracle")):
    ct = frage(prog, "seal %s %s %s" % (hx(k), hx(na), hx(blk)))
    auf = frage(prog, "open %s %s %s" % (hx(k), hx(nb), ct))
    aus.append("%s=%s" % (nam, "FAIL" if auf == "FAIL" else "OFFEN"))
print(" ".join(aus))
PYX
)
        is "(j2) GEGENPROBE: der Block haengt am Namen -- und woran genau" \
           "$r" "ECHT=FAIL OHNEAAD=FAIL LOS=OFFEN"
        note "das AAD allein traegt die Bindung NICHT: Schluessel und Nonce tun es."
        note "Erst wenn auch die weg sind (LOS), geht ein Block unter fremdem Namen auf."
    else
        bad "(j2) die kaputten Fassungen bauen nicht (ohneaad=$b1 losgeloest=$b2)"
    fi
fi

# (j3) Der Rueckschrittschutz wird ausgebaut: ein Zaehler, der nie
#      steigt, muss den Rueckschrittfall aus (e) durchgehen lassen.
cp kernel/user/sync.fi "$TMPD/sync.sicher"
sed 's/^    if g < zaehler {$/    if false {/' kernel/user/sync.fi > "$TMPD/kaputt/sync-ohneschutz.fi"
if ! cmp -s "$TMPD/kaputt/sync-ohneschutz.fi" kernel/user/sync.fi; then
    cp "$TMPD/kaputt/sync-ohneschutz.fi" kernel/user/sync.fi
    if bash tools/sync/build.sh "$TMPD/binj" 0 sync >/dev/null 2>&1; then
        cp "$TMPD/bin/sync.elf" "$TMPD/bin/sync.elf.sicher"
        cp "$TMPD/binj/sync.elf" "$TMPD/bin/sync.elf"
        geraet "$TMPD/J3.img" "$TMPD/sE.sh" "$TMPD/kontoR" "$TMPD/sb-rueck" "$TMPD/leer" -
        lauf "$TMPD/J3.img" J3 > /dev/null
        klar J3 > "$TMPD/J3.log"
        if grep -qa 'RUECKSCHRITT' "$TMPD/J3.log"; then
            bad "(j3) auch ohne Schutz wird der Rueckschritt gemeldet -- der Test misst ihn nicht"
        else
            ok "(j3) GEGENPROBE: ohne den Zaehlervergleich geht der Rueckschritt durch"
        fi
        cp "$TMPD/bin/sync.elf.sicher" "$TMPD/bin/sync.elf"
    else
        bad "(j3) die kaputte Fassung baut nicht"
    fi
    cp "$TMPD/sync.sicher" kernel/user/sync.fi
else
    bad "(j3) der Schnitt hat nichts geaendert -- die Gegenprobe misst nichts"
fi

# (j4) DIE STILLE LUECKE. Die alte Fassung zurueckgebaut: die Namen einer
#      Datei passen wieder nur in 700 Oktette, und eine Datei, die sich
#      nicht darstellen laesst, wird im Baum einfach uebersprungen. Dann
#      MUSS gross.bin aus dem Abgleich fallen -- und der Lauf muss
#      trotzdem "fertig" melden. Genau das war der Zustand, den kein
#      Test der Runde gesehen hat, weil die groesste Pruefdatei 9000
#      Oktette hatte.
cp kernel/user/sync.fi "$TMPD/sync.sicher"
python3 - kernel/user/sync.fi "$TMPD/kaputt/sync-still.fi" <<'PYS'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
s = s.replace("if nat + NAMEHEX + 2 >= NAMBUF {", "if nat + NAMEHEX + 2 >= NAMINLINE {")
s = s.replace("""                    merk_pfad((&relp[0]) as u64)
                    io.close(dfd[depth as usize])
                    return false""",
              """                    relp[keep as usize] = 0 as u8
                    continue""")
open(sys.argv[2], 'w', encoding='utf-8').write(s)
PYS
if ! cmp -s "$TMPD/kaputt/sync-still.fi" kernel/user/sync.fi; then
    cp "$TMPD/kaputt/sync-still.fi" kernel/user/sync.fi
    if bash tools/sync/build.sh "$TMPD/binj4" 0 sync >/dev/null 2>&1; then
        cp "$TMPD/bin/sync.elf" "$TMPD/bin/sync.elf.sicher"
        cp "$TMPD/binj4/sync.elf" "$TMPD/bin/sync.elf"
        mkdir -p "$TMPD/j4store" "$TMPD/j4leer"
        cat > "$TMPD/sJ4.sh" <<EOS
sync neu /konto $PASS eigen /store $NP $RP
sync abgleich /konto /daten $PASS
echo ==END==
EOS
        geraet "$TMPD/J4a.img" "$TMPD/sJ4.sh" - - "$TMPD/daten" -
        lauf "$TMPD/J4a.img" J4a > /dev/null
        klar J4a > "$TMPD/J4a.log"
        j4dat=$(feld "$TMPD/J4a.txt" dateien)
        if grep -qa '^fertig' "$TMPD/J4a.log" && [ "$j4dat" = "4" ]; then
            ok "(j4) GEGENPROBE: mit dem alten 700-Oktett-Feld faellt gross.bin still aus dem Abgleich -- $j4dat statt 5 Dateien, und der Lauf meldet trotzdem fertig"
        else
            bad "(j4) die alte Fassung verhaelt sich nicht wie erwartet: dateien=$j4dat, fertig=$(grep -ca '^fertig' "$TMPD/J4a.log")"
        fi
        cp "$TMPD/bin/sync.elf.sicher" "$TMPD/bin/sync.elf"
    else
        bad "(j4) die kaputte Fassung baut nicht"
    fi
    cp "$TMPD/sync.sicher" kernel/user/sync.fi
else
    bad "(j4) der Rueckbau hat nichts geaendert -- die Gegenprobe misst nichts"
fi

# =====================================================================
echo "== 12b. der voreingestellte Preis der Schluesselableitung =="
# =====================================================================
# ALLE ANDEREN ABSCHNITTE FAHREN MIT N=256, damit sie in QEMU nicht
# ewig brauchen. Damit misst KEINER von ihnen, was ein echtes Konto
# kostet -- und der Kopf von `kbund.fi` behauptete, der voreingestellte
# Preis sei N=16384 (16 MiB). Das ist auf diesem System UNMOEGLICH: die
# grosse Arena aus Runde K16 ist 6 MiB, also ist bei r=8 bei N=4096
# Schluss. Gemessen: mit N=16384 scheitert `sync neu`, und danach geht
# der Tresor nie auf. Hier steht beides -- dass die Voreinstellung
# wirklich laeuft, und dass die Zahl darueber wirklich scheitert.
cat > "$TMPD/sP.sh" <<EOS
echo ==VOR==
date -u
sync neu /konto $PASS eigen /store
date -u
tresor neu /konto /tresor $PASS
date -u
tresor auf /konto /tresor $PASS 60
date -u
echo ==ZUVIEL==
sync neu /konto2 $PASS eigen /store2 16384 8
echo ==END==
EOS
mkdir -p "$TMPD/leer2"
PROGS_ALT=$PROGS
if ! echo "$PROGS" | grep -qw date; then
    PROGS="$PROGS date"
    bash tools/sync/build.sh "$TMPD/bin" 0 date >/dev/null 2>&1
fi
geraet "$TMPD/P.img" "$TMPD/sP.sh" - - "$TMPD/leer2" -
PROGS=$PROGS_ALT
SYNC_TIMEOUT=900 lauf "$TMPD/P.img" P > /dev/null
klar P > "$TMPD/P.log"
grep -qa '^konto: auf' "$TMPD/P.log" \
    && ok "der VOREINGESTELLTE Preis (N=4096, r=8, 4 MiB) legt ein Konto an" \
    || bad "der voreingestellte Preis legt KEIN Konto an -- die Voreinstellung ist kaputt"
grep -qa '^tresor: auf' "$TMPD/P.log" \
    && ok "und der Tresor geht damit auf" \
    || bad "und der Tresor geht damit NICHT auf"
sed -n '/^==ZUVIEL==/,$p' "$TMPD/P.log" | grep -qa 'fehler' \
    && ok "GEGENPROBE: N=16384 (16 MiB) scheitert -- die Arena hat 6 MiB" \
    || bad "N=16384 kam durch -- dann stimmt die Grenze im Kopf von kbund.fi nicht"
# Die Zeiten aus der Uhr des Systems (`date -u` gibt Millisekunden
# Betriebsdauer). Keine Zusage mit fester Zahl -- sie haengen vom Wirt ab.
python3 - "$TMPD/P.log" <<'PYT'
import re, sys
marke = None; letzte = None; namen = ["sync neu", "tresor neu", "tresor auf"]
i = 0
for z in open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines():
    z = z.strip()
    m = re.match(r'^up (\d+) ms$', z)
    if not m:
        continue
    t = int(m.group(1))
    if letzte is not None and i < len(namen):
        print("        %-12s %5d ms (N=4096, r=8, im System)" % (namen[i], t - letzte))
        i += 1
    letzte = t
PYT

# =====================================================================
echo "== 13. die Messungen =="
# =====================================================================
# Der Durchsatz: ein voller Abgleich und einer, bei dem sich eine
# Kleinigkeit geaendert hat. KEINE Zusage mit fester Zahl -- die Zeiten
# haengen vom Wirt ab, und ein Test, der bei Last umfaellt, misst den
# Wirt und nicht das Programm.
mkdir -p "$TMPD/mess"
i=0
while [ $i -lt 20 ]; do
    head -c 51200 /dev/urandom > "$TMPD/mess/m$i.bin"
    i=$((i+1))
done
cat > "$TMPD/sM.sh" <<EOS
sync neu /konto $PASS eigen /store $NP $RP
echo ==VOLL==
sync abgleich /konto /daten $PASS
echo ==NOCHMAL==
sync abgleich /konto /daten $PASS
echo ==KLEIN==
echo eine-kleine-aenderung > /daten/m0.bin
sync abgleich /konto /daten $PASS
echo ==END==
EOS
# EIN GROESSERES ABBILD FUER DIE MESSUNG. Mit den 6144 Bloecken
# (3 MiB), die fuer alle anderen Geraete reichen, ist der Datentraeger
# nach etwa 245 der 302 Bloecke VOLL -- und dann misst dieser Abschnitt
# nicht den Abgleich, sondern die Groesse des Abbilds. Genau das ist
# passiert: 245 Bloecke statt 302, ein INDEX, der auf dem Wirt leer
# ankam, und ein gerechneter Mehraufwand, der nichts bedeutete.
BLOCKS_ALT=$BLOCKS
BLOCKS=16384
geraet "$TMPD/M.img" "$TMPD/sM.sh" - - "$TMPD/mess" -
BLOCKS=$BLOCKS_ALT
# EIGENES ZEITLIMIT. Drei Abgleiche ueber 1 MiB in einem einzigen
# Systemstart brauchen laenger als die 300 Sekunden, die fuer einen
# gewoehnlichen Lauf reichen -- und auf einem Wirt, der nebenbei andere
# Testreihen faehrt, noch einmal deutlich laenger. Lief die Messung ins
# Limit, standen hier vorher leere Zahlen und zwei Zusagen fielen, ohne
# dass am Programm irgendetwas falsch war.
t0=$(date +%s%N)
SYNC_TIMEOUT=1800 lauf "$TMPD/M.img" M > /dev/null
t1=$(date +%s%N)
klar M > "$TMPD/M.log"
grep -qa '^==END==' "$TMPD/M.log" \
    && ok "der Messlauf ist wirklich bis zum Ende gekommen" \
    || bad "der Messlauf ist nicht fertig geworden -- die Zahlen unten sind wertlos"
M_GESAMT=$(( (t1 - t0) / 1000000 ))
M_BLK=$(feld_n "$TMPD/M.txt" bloecke 1)
M_NEU1=$(feld_n "$TMPD/M.txt" neubloecke 1)
M_NEU2=$(feld_n "$TMPD/M.txt" neubloecke 2)
M_NEU3=$(feld_n "$TMPD/M.txt" neubloecke 3)
M_GES1=$(feld_n "$TMPD/M.txt" gesendet 1)
M_GES3=$(feld_n "$TMPD/M.txt" gesendet 3)
M_LES1=$(feld_n "$TMPD/M.txt" gelesen 1)
note "1 MiB in 20 Dateien: $M_BLK Bloecke, erster Lauf $M_NEU1 neu ($M_GES1 Oktette gesendet)"
note "zweiter Lauf: $M_NEU2 neue Bloecke; nach einer kleinen Aenderung: $M_NEU3"
note "alle drei Laeufe samt Anlegen des Kontos und Systemstart: $M_GESAMT ms (accel=$OSUM_QEMU_ACCEL)"
# WORAUS DIE 302 BLOECKE BESTEHEN, damit die Zahl nachrechenbar ist:
#   260  Daten      20 Dateien zu 51200 Oktetten, je 13 Bloecke
#                   (12 volle und ein auf 4096 aufgefuellter)
#    40  Namen      je Datei 13 Namen zu 65 Oktetten = 845 -- zu viel
#                   fuer eine Verzeichniszeile, also K-Form: ein Block
#                   Text und ein Kopfblock je Datei
#     2  Verzeichnis
# Steht hier eine kleinere Zahl, ist eine Datei aus dem Abgleich
# gefallen. Genau das war der Fall: 201 Bloecke, weil jede Datei nach
# 10 Bloecken abbrach und der Baum sie still uebersprang.
is "der Messlauf meldet dreimal fertig" "$(grep -ca '^fertig' "$TMPD/M.log")" "3"
is "der volle Abgleich sieht alle 20 Dateien" "$(feld_n "$TMPD/M.txt" dateien 1)" "20"
[ -n "$M_BLK" ] && [ "$M_BLK" -ge 300 ] \
    && ok "der volle Abgleich sieht alle Bloecke: $M_BLK (260 Daten + 40 Namensketten + Verzeichnis)" \
    || bad "der volle Abgleich sieht nur $M_BLK Bloecke -- erwartet werden 302"
is "und er legt jeden davon neu ab" "$M_NEU1" "$M_BLK"
is "der zweite Lauf schreibt NULL neue Bloecke" "$M_NEU2" "0"
[ -n "$M_NEU3" ] && [ "$M_NEU3" -le 3 ] \
    && ok "eine kleine Aenderung kostet $M_NEU3 neue Bloecke, nicht $M_NEU1" \
    || bad "eine kleine Aenderung kostet $M_NEU3 Bloecke"

# DER MEHRAUFWAND, GEGEN DEN KLARTEXT UND NICHT GEGEN "gelesen".
#
# Hier stand einmal `(gesendet - gelesen) / gelesen` -- und das Ergebnis
# war MINUS 8,3 %, also ein Verfahren, das beim Verschluesseln Platz
# spart. Der Fehler: `gelesen` zaehlt die Oktette, die aus dem Baum
# GELESEN wurden (Bloecke, aufgefuellt, auch die schon bekannten),
# `gesendet` nur die NEUEN Bloecke. Zwei verschiedene Mengen.
#
# Richtig ist der Vergleich mit dem, was der Nutzer wirklich hat: die
# Summe der Dateigroessen auf dem WIRT gegen die Groesse von PACK auf dem
# Server. Darin steckt beides -- die 16 Oktette Siegel je Block UND das
# Auffuellen des letzten Blocks jeder Datei, das der teurere Posten ist.
hol "$TMPD/M.img" /store "$TMPD/storeM"
M_KLAR=$(du -sb "$TMPD/mess" | cut -f1)
M_PACK=$(stat -c%s "$TMPD/storeM/PACK" 2>/dev/null || echo 0)
M_IDX=$(stat -c%s "$TMPD/storeM/INDEX" 2>/dev/null || echo 0)
if [ "$M_KLAR" -gt 0 ] && [ "$M_PACK" -gt 0 ]; then
    proz=$(awk "BEGIN{printf \"%.1f\", ($M_PACK+$M_IDX-$M_KLAR)*100.0/$M_KLAR}")
    sieg=$(awk "BEGIN{printf \"%.2f\", 16*100.0/4096}")
    note "Klartext $M_KLAR Oktette -> Speicher $M_PACK (PACK) + $M_IDX (INDEX) = Mehraufwand ${proz} %"
    note "davon Siegel ${sieg} % je Block; der Rest ist das Auffuellen auf 4096 und das Verzeichnis"
    awk "BEGIN{exit !($M_PACK+$M_IDX > $M_KLAR)}" \
        && ok "der Speicher ist groesser als der Klartext, wie er muss" \
        || bad "der Speicher ist KLEINER als der Klartext -- da stimmt eine Zahl nicht"
else
    bad "der Mehraufwand laesst sich nicht rechnen: Klartext $M_KLAR, PACK $M_PACK"
fi

# DER DURCHSATZ. `sync` sagt seit dieser Runde selbst, wie lange es
# gedauert hat (`sekunden:`) -- die Gesamtzeit der virtuellen Maschine
# enthaelt Systemstart und das Anlegen des Kontos und taugt dafuer nicht.
M_S1=$(feld_n "$TMPD/M.txt" sekunden 1)
M_S2=$(feld_n "$TMPD/M.txt" sekunden 2)
M_S3=$(feld_n "$TMPD/M.txt" sekunden 3)
note "Dauer der drei Abgleiche: $M_S1 s (voll), $M_S2 s (nichts neu), $M_S3 s (eine Aenderung)"
if [ -n "$M_S1" ] && [ "$M_S1" -gt 0 ]; then
    # IN KiB/s UND NICHT IN MiB/s. In MiB/s stand hier "0.00" -- eine
    # Zahl, die nichts sagt, weil der Abgleich in QEMU eben langsam ist
    # (rund 4 KiB/s bei 1 MiB in 247 s). Eine Einheit, in der die
    # Messung als Null erscheint, ist die falsche Einheit.
    kbs=$(awk "BEGIN{printf \"%.1f\", $M_KLAR/1024.0/$M_S1}")
    kbs3=$(awk "BEGIN{printf \"%.1f\", $M_KLAR/1024.0/$M_S3}")
    note "erster voller Abgleich: ${kbs} KiB/s; nach einer kleinen Aenderung ${kbs3} KiB/s"
    note "(in QEMU auf einem Wirt unter Last -- das misst die Emulation mit, nicht nur das Verfahren)"
fi

# Der Speicherbedarf der Schluesselableitung und ihre Zeit, auf dem WIRT
# gemessen (in QEMU waere es die Emulation, nicht das Verfahren).
python3 - "$TMPD" > "$TMPD/kdf.txt" <<'PY'
import binascii, os, subprocess, sys, time
d = sys.argv[1]
O = ".probe/syncoracle"
for (N, r) in [(256, 8), (1024, 8), (4096, 8), (16384, 8)]:
    t = time.time()
    subprocess.run([O], input="scrypt %s %s %d %d 1 32\n"
                   % (binascii.hexlify(b"passphrase").decode(),
                      binascii.hexlify(os.urandom(16)).decode(), N, r),
                   capture_output=True, text=True)
    el = (time.time() - t) * 1000
    print("  N=%-6d r=%d  Speicher %7d KiB  %7.1f ms"
          % (N, r, (N + 2) * 128 * r // 1024, el))
PY
sed 's/^/     /' "$TMPD/kdf.txt"
# EINE ZUSAGE OHNE PRUEFUNG IST KEINE ZUSAGE. Hier stand ein blankes
# `ok` -- es meldete "gemessen" auch dann, wenn die Datei gar nicht
# entstanden war. Jetzt zaehlt, dass alle vier Stufen wirklich drinstehen.
is "die Schluesselableitung: vier Stufen gemessen (auf dem Wirt, firnc0)" \
   "$(grep -c 'N=' "$TMPD/kdf.txt" 2>/dev/null || echo 0)" "4"

# Der Blockindex bei 10 000 Dateien -- gerechnet aus dem Format, das
# oben gemessen wurde: je Block eine Zeile aus 64 Hexziffern, zwei
# Tabulatoren, Offset und Laenge.
python3 - <<'PY'
n = 10000
# eine Datei kleiner als 4096 Oktette = ein Block; dazu das Verzeichnis
zeile = 64 + 1 + 9 + 1 + 4 + 1     # name TAB offset TAB laenge NL
print("  Blockindex bei 10 000 Dateien (je ein Block): %d Oktette = %.1f KiB"
      % (n * zeile, n * zeile / 1024.0))
print("  im Speicher (32 Oktette Name + 2 x 8 Zahl je Block): %d KiB"
      % (n * 48 // 1024))
PY
note "gerechnet aus dem Format, dessen Zeilen oben gemessen wurden"

echo
echo "SYNC: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
