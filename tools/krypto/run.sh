#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/krypto/run.sh -- DIE ABNAHME DER RUNDE KRYPTO (K-019).
#
# DIE FRAGE DIESER RUNDE: liegen die Daten von OrientOS verschluesselt
# auf dem Blech, und kommt man ohne Passphrase wirklich nicht daran?
#
# WIE HIER GEMESSEN WIRD, und warum es so und nicht anders geht:
#
#   DER WIRT IST DIE GEGENSTELLE, mit FREMDEM Werkzeug -- `argon2-cffi`
#   (die Referenzumsetzung von RFC 9106), `cryptography` (OpenSSL
#   darunter) und `hashlib`. Keine Zeile Osum-Code ist daran beteiligt.
#
#   ES WIRD IN BEIDE RICHTUNGEN GEMESSEN. Was OrientOS verschluesselt,
#   muss der Wirt entschluesseln koennen -- und was der WIRT anlegt,
#   muss OrientOS aufmachen koennen. Die zweite Richtung ist die
#   schaerfere: sie faellt aus, sobald OrientOS irgendwo etwas anderes
#   rechnet als die Norm, auch wenn es mit sich selbst einig bleibt.
#
#   UND DAZU DIE VEROEFFENTLICHTEN VEKTOREN: FIPS 180-4 ueber
#   `hashlib`, RFC 7693 (BLAKE2b), RFC 9106 (Argon2id) und IEEE 1619
#   (XTS) ueber OpenSSL.
#
# Eine Kryptoumsetzung, die nur gegen sich selbst geprueft ist, ist
# wertlos -- das ist der erste Satz des Auftrags, und dieser Laeufer ist
# seine Einloesung.
#
# WAS GEMESSEN WIRD, in dieser Reihenfolge:
#
#   1. Die Speicherkarte von kdata (0 Kollisionen) und der Bereich
#      dieser Runde an der ZUGETEILTEN Adresse.
#   2. Der Bau: Kern und das Orakel aus denselben lib/crypto-Dateien.
#   3. Die Rechnung gegen die Normen und gegen OpenSSL, mit der
#      negativen Haelfte (was abgelehnt werden MUSS).
#   4. Anlegen, Dateisystem, bekannter Baum -- dann NEUSTART, Passphrase,
#      jede SHA-256.
#   5. Die Gegenproben: falsche Passphrase, gar nicht entsperrt,
#      beschaedigter Kopfsatz. Alle drei mit DERSELBEN Antwort.
#   6. Das Rohgeraet: kein Klartext, keine Signatur, Entropie.
#   7. Der Schluesselplatz-Wechsel: neue Passphrase dazu, alte weg,
#      Daten unveraendert.
#   8. Die Gegenprobe mit fremden Augen, beide Richtungen.
#
# Aufruf:  bash tools/krypto/run.sh
#          OSUM_KRYPTO_SCHNELL=1   ohne die langen Vektorschleifen
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op soll
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl gefunden (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
gleich() { # name soll ist
    if [ "$2" = "$3" ]; then ok "$1"
    else
        bad "$1"
        printf '        soll: %s\n' "$(printf '%s' "$2" | head -c 200)"
        printf '        ist : %s\n' "$(printf '%s' "$3" | head -c 200)"
    fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da" || ok "$3"; }

# Ein Wert aus der seriellen Ausgabe ("krypto: name=zahl").
kwert() { # datei name
    grep -a -m1 -oE "$2=[0-9]+" "$1" 2>/dev/null | head -1 | cut -d= -f2
}
ksagt() { # datei name soll beschreibung
    local got; got=$(kwert "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- keine Zeile '$2='"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2=$got)"
    else bad "$4 -- $2=$got, erwartet $3"; fi
}

echo "== 0. die Vorbedingungen =="
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "KRYPTO: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; }
command -v python3 >/dev/null 2>&1 || {
    echo "KRYPTO: uebersprungen, python3 fehlt"; exit 0; }

# DAS FREMDE WERKZEUG. Ohne argon2-cffi und cryptography gibt es keine
# unabhaengige Gegenrechnung -- und dann ist dieser Laeufer wertlos und
# sagt das, statt gruen zu werden.
PY=python3
for kandidat in "${OSUM_KRYPTO_PY:-}" /root/.krypto-venv/bin/python python3; do
    [ -n "$kandidat" ] || continue
    command -v "$kandidat" >/dev/null 2>&1 || [ -x "$kandidat" ] || continue
    if "$kandidat" -c 'import argon2.low_level, cryptography' 2>/dev/null; then
        PY=$kandidat; break
    fi
done
if ! "$PY" -c 'import argon2.low_level, cryptography' 2>/dev/null; then
    echo "KRYPTO: uebersprungen -- argon2-cffi und/oder cryptography fehlen."
    echo "  Ohne eine UNABHAENGIGE Umsetzung waere diese Abnahme ein"
    echo "  Selbstgespraech. Abhilfe:"
    echo "    python3 -m venv /root/.krypto-venv"
    echo "    /root/.krypto-venv/bin/pip install argon2-cffi cryptography"
    exit 0
fi
ok "das fremde Werkzeug ist da ($PY: argon2-cffi, cryptography)"
if command -v argon2 >/dev/null 2>&1; then
    ok "dazu der argon2-Befehl der Distribution (zweite fremde Umsetzung)"
fi

# ---------------------------------------------------- 1. die Speicherkarte

echo "== 1. die Speicherkarte von kdata =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Karte: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/karte.txt" | head -10
fi
hat "$TMPD/karte.txt" "0 Kollisionen" "keine zwei Bereiche ueberschneiden sich"

# DER BEREICH DIESER RUNDE LIEGT, WO ER ZUGETEILT WURDE. Fuenf Runden
# hintereinander haben sich dieselbe freie Seite genommen; diese hier
# hat ihre Adresse VOR der Runde bekommen.
v=$(grep -aE "^const CRYPT_OFF: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ "$(( v ))" = "$(( 0x113000 ))" ]; then
    ok "CRYPT_OFF = $v -- genau die zugeteilte Adresse"
else
    bad "CRYPT_OFF = ${v:-fehlt}, zugeteilt war 0x113000"
fi
m=$(grep -aE "^const CRYPT_MAX: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
    | head -1 | grep -oE '0x[0-9A-Fa-f]+')
if [ "$(( v + m ))" -le "$(( 0x118000 ))" ]; then
    ok "und endet bei $(printf '0x%X' $(( v + m ))), also nicht hinter 0x118000"
else
    bad "der Bereich ragt ueber 0x118000 hinaus"
fi

# GEGENPROBE ZUR KARTE: den Bereich auf eine fremde Adresse legen MUSS
# anschlagen. Ohne diese Zeilen prueft die Karte nur das, woran jemand
# gedacht hat.
mkdir -p "$TMPD/koll/arch/x86_64"
cp kernel/*.fi "$TMPD/koll/" 2>/dev/null
cp kernel/arch/x86_64/*.fi "$TMPD/koll/arch/x86_64/" 2>/dev/null
sed -i 's/^const CRYPT_OFF: u64 = 0x113000$/const CRYPT_OFF: u64 = 0x108000/' \
    "$TMPD/koll/kstate.fi"
if python3 tools/kernel/memmap.py "$TMPD/koll" > "$TMPD/karte2.txt" 2>&1; then
    bad "GEGENPROBE: CRYPT_OFF auf WMP_OFF gelegt und der Pruefer schweigt"
else
    ok "GEGENPROBE: CRYPT_OFF auf WMP_OFF gelegt -- der Kartenpruefer schlaegt an"
fi

# --------------------------------------------------------------- 2. bauen

echo "== 2. bauen =="
if bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/bau.log" 2>&1; then
    ok "der Kern baut ($(stat -c %s "$TMPD/k0.mb") Oktette)"
else
    bad "der Kern laesst sich nicht bauen"
    sed 's/^/        /' "$TMPD/bau.log" | tail -12
    echo "KRYPTO: $pass bestanden, $fail gescheitert"; exit 1
fi

mkdir -p .probe
if $FIRNC tools/krypto/orakel.fi -o .probe/korakel 2> "$TMPD/orakel.err"; then
    ok "tools/krypto/orakel.fi baut gegen lib/crypto/ (dieselben Dateien wie der Kern)"
else
    bad "tools/krypto/orakel.fi laesst sich nicht bauen"
    sed 's/^/        /' "$TMPD/orakel.err" | head -20
    echo "KRYPTO: $pass bestanden, $fail gescheitert"; exit 1
fi
# Ein Orakel, das nie FAIL sagt, misst nichts.
if [ "$(echo 'quatsch' | ./.probe/korakel)" = "FAIL" ]; then
    ok "das Orakel lehnt Unsinn ab (sagt FAIL)"
else
    bad "das Orakel sagt zu 'quatsch' nicht FAIL"
fi

# ------------------------------------- 3. die Rechnung gegen die Normen

echo "== 3. die Rechnung gegen die Normen und gegen OpenSSL =="
if [ "${OSUM_KRYPTO_SCHNELL:-0}" = 1 ]; then
    echo "  (uebersprungen, OSUM_KRYPTO_SCHNELL=1)"
else
    "$PY" tools/krypto/gegen.py vektoren ./.probe/korakel \
        > "$TMPD/vekt.txt" 2>&1
    for gruppe in blake2b argon2 xts negativ; do
        z=$(grep -a -m1 "^$gruppe " "$TMPD/vekt.txt")
        g=$(echo "$z" | grep -oE '[0-9]+/[0-9]+' | cut -d/ -f1)
        n=$(echo "$z" | grep -oE '[0-9]+/[0-9]+' | cut -d/ -f2)
        if [ -n "$g" ] && [ "$g" = "$n" ]; then
            ok "$gruppe: $g/$n gegen die fremde Umsetzung"
        else
            bad "$gruppe: ${g:-?}/${n:-?}"
            grep -a "$gruppe" "$TMPD/vekt.txt" | head -3 | sed 's/^/        /'
        fi
    done
fi

# DER OFFIZIELLE VEKTOR AUS RFC 9106, ueber den argon2-Befehl der
# Distribution -- eine DRITTE Umsetzung neben unserer und argon2-cffi.
if command -v argon2 >/dev/null 2>&1; then
    soll=$(printf 'password' | argon2 somesaltsomesalt -id -t 3 -m 5 -p 4 \
        -l 32 -v 13 -r 2>/dev/null)
    ist=$(echo "argon2id 70617373776f7264 736f6d6573616c74736f6d6573616c74 3 32 4 32" \
        | ./.probe/korakel)
    gleich "Argon2id t=3 m=32 p=4 gegen den argon2-Befehl" "$soll" "$ist"
fi

# ------------------------------------------------ 4. die volle Kette

echo "== 4. anlegen, schreiben, NEUSTART, entsperren, nachrechnen =="
BLOCKS=8192
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ > "$TMPD/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht" \
    || bad "mkfs.py scheitert"

# Kleine Argon2-Parameter: der Abnahmelauf misst die RECHNUNG, nicht die
# Geduld. Sie stehen im Kopfsatz, also wird auch mit ihnen aufgemacht --
# ein Schalter, der im Messlauf etwas anderes rechnet als im Betrieb,
# waere unehrlich.
KP="kryptot=1 kryptom=64 kryptop=1"

lauf() { # name abbild kommandozeile [zeitlimit]
    local name=$1 img=$2 app=$3 t=${4:-300}
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$img,format=raw,if=ide,index=0" > /dev/null 2>&1
    return 0
}

cp --sparse=always "$TMPD/root.img" "$TMPD/a.img"
lauf a1 "$TMPD/a.img" "osum nopwr kryptoneu kryptotest kryptobaum kryptopw=geheim $KP"
ksagt "$TMPD/a1.txt" "neu"      1 "die Platte wird angelegt"
ksagt "$TMPD/a1.txt" "selbst"   1 "der Selbsttest der Rechnung"
ksagt "$TMPD/a1.txt" "fsformat" 1 "das Dateisystem darauf"
ksagt "$TMPD/a1.txt" "kopfda"   1 "der Kopfsatz steht nach dem Formatieren noch"
ksagt "$TMPD/a1.txt" "mount"    1 "eingehaengt"
ksagt "$TMPD/a1.txt" "baum"     4 "vier Dateien geschrieben"

# DER NEUSTART. Das ist der Unterschied zwischen "der Puffer stimmt
# noch" und "es steht auf der Platte".
lauf a2 "$TMPD/a.img" "osum nopwr kryptoauf kryptopruef kryptopw=geheim $KP"
ksagt "$TMPD/a2.txt" "auf"    1 "nach dem Neustart mit der Passphrase aufgemacht"
ksagt "$TMPD/a2.txt" "fehler" 0 "ohne Fehlversuch"
ksagt "$TMPD/a2.txt" "mount"  1 "und eingehaengt"

# Die vier Pruefsummen gegen `hashlib` auf dem WIRT.
python3 - "$TMPD/soll.txt" <<'PYEOF'
import hashlib, sys
laengen = [100, 700, 5000, 40000]
with open(sys.argv[1], "w") as f:
    for i, n in enumerate(laengen):
        b = bytes(((i * 37 + k * 7 + 3) & 255) for k in range(n))
        f.write("k%d %s\n" % (i, hashlib.sha256(b).hexdigest()))
PYEOF
gut=0
while read -r nm soll; do
    ist=$(grep -a -m1 "krypto: sha ${nm#k} = " "$TMPD/a2.txt" | sed 's/.*= //' \
        | tr -d '\r\000')
    if [ "$ist" = "$soll" ]; then gut=$((gut+1)); fi
done < "$TMPD/soll.txt"
num "SHA-256 der Dateien stimmen (gegen hashlib auf dem Wirt)" "$gut" eq 4

# ------------------------------------------------- 5. die Gegenproben

echo "== 5. die Gegenproben =="
cp --sparse=always "$TMPD/a.img" "$TMPD/b.img"
lauf b1 "$TMPD/b.img" "osum nopwr kryptoauf kryptofalsch kryptopruef kryptopw=geheim $KP"
ksagt "$TMPD/b1.txt" "auf"    0 "die FALSCHE Passphrase macht nicht auf"
ksagt "$TMPD/b1.txt" "fehler" 1 "und wird gezaehlt"
ksagt "$TMPD/b1.txt" "mount"  0 "ohne Schluessel laesst sich nichts einhaengen"

# DIE ANTWORT DARF NICHT VERRATEN, WIE NAH MAN DRAN WAR. Die Zeile bei
# falscher Passphrase muss Zeichen fuer Zeichen die sein, die auch ein
# beschaedigter Kopfsatz bekommt.
cp --sparse=always "$TMPD/a.img" "$TMPD/c.img"
python3 - "$TMPD/c.img" <<'PYEOF'
import sys
# 16 Oktette mitten in den Schluesselplatz 0 kippen.
with open(sys.argv[1], "r+b") as f:
    f.seek(0x140)
    f.write(b"\xff" * 16)
PYEOF
lauf c1 "$TMPD/c.img" "osum nopwr kryptoauf kryptopruef kryptopw=geheim $KP"
ksagt "$TMPD/c1.txt" "auf"    0 "ein beschaedigter Kopfsatz wird abgewiesen"
ksagt "$TMPD/c1.txt" "fehler" 1 "sauber, nicht mit Muell"
zb=$(grep -a -m1 'krypto: auf=' "$TMPD/b1.txt" | tr -d '\r\000')
zc=$(grep -a -m1 'krypto: auf=' "$TMPD/c1.txt" | tr -d '\r\000')
gleich "falsche Passphrase und kaputter Kopf geben DIESELBE Zeile" "$zb" "$zc"

# Ganz ohne Entsperrung: das Dateisystem MUSS scheitern. Das ist der
# Beleg, dass wirklich verschluesselt auf der Platte steht.
cp --sparse=always "$TMPD/a.img" "$TMPD/d.img"
lauf d1 "$TMPD/d.img" "osum nopwr kryptoroh kryptopruef"
ksagt "$TMPD/d1.txt" "roh"   1 "der Kopfsatz wird gefunden"
ksagt "$TMPD/d1.txt" "mount" 0 "aber ohne Passphrase haengt nichts ein"

# --------------------------------------------------- 6. das Rohgeraet

echo "== 6. das Rohgeraet: was sieht man ohne Passphrase? =="
"$PY" tools/krypto/gegen.py roh "$TMPD/a.img" > "$TMPD/roh.txt" 2>&1
sed 's/^/        /' "$TMPD/roh.txt"
for s in "OFS-Superblock" "OFS-Kennung gedreht" "NTFS" "FAT"; do
    w=$(grep -a -m1 "roh: sig $s = " "$TMPD/roh.txt" | sed 's/.*= //')
    num "keine $s-Signatur im Datenbereich" "${w:-99}" eq 0
done
unter7=$(grep -a -m1 'unter7=' "$TMPD/roh.txt" | grep -oE 'unter7=[0-9]+' | cut -d= -f2)
num "kein beschriebener Sektor mit Entropie unter 7.0 Bit/Oktett" "${unter7:-99}" eq 0
txt=$(grep -a -m1 'textfolgen16=' "$TMPD/roh.txt" | cut -d= -f2)
num "keine lesbare Zeichenkette ab 16 Zeichen" "${txt:-99}" eq 0

# ------------------------------------------ 7. der Schluesselplatz-Wechsel

echo "== 7. die Passphrase wechseln, ohne die Daten anzufassen =="
cp --sparse=always "$TMPD/root.img" "$TMPD/e.img"
lauf e1 "$TMPD/e.img" "osum nopwr kryptoneu kryptobaum kryptopw=alt $KP"
ksagt "$TMPD/e1.txt" "baum" 4 "der Baum steht (Passphrase 'alt')"
lauf e2 "$TMPD/e.img" "osum nopwr kryptoauf kryptowechs kryptokill kryptopw=alt kryptopw2=neu $KP"
ksagt "$TMPD/e2.txt" "wechsel" 1 "Platz 1 bekommt die neue Passphrase"
ksagt "$TMPD/e2.txt" "kill"    1 "Platz 0 wird geloescht"
ksagt "$TMPD/e2.txt" "plaetze" 1 "danach ist genau ein Platz belegt"
lauf e3 "$TMPD/e.img" "osum nopwr kryptoauf kryptopruef kryptopw=alt $KP"
ksagt "$TMPD/e3.txt" "auf" 0 "die ALTE Passphrase oeffnet nichts mehr"
lauf e4 "$TMPD/e.img" "osum nopwr kryptoauf kryptopruef kryptopw=neu $KP"
ksagt "$TMPD/e4.txt" "auf"   1 "die NEUE oeffnet dieselbe Platte"
ksagt "$TMPD/e4.txt" "platz" 1 "und zwar ueber Platz 1"
ksagt "$TMPD/e4.txt" "mount" 1 "eingehaengt"
gut=0
while read -r nm soll; do
    ist=$(grep -a -m1 "krypto: sha ${nm#k} = " "$TMPD/e4.txt" | sed 's/.*= //' \
        | tr -d '\r\000')
    if [ "$ist" = "$soll" ]; then gut=$((gut+1)); fi
done < "$TMPD/soll.txt"
num "die Daten sind nach dem Wechsel unveraendert (kein Sektor neu verschluesselt)" \
    "$gut" eq 4
# Und der geloeschte Platz ist wirklich genullt und nicht nur abgehakt.
python3 - "$TMPD/e.img" > "$TMPD/platz0.txt" <<'PYEOF'
import sys
d = open(sys.argv[1], "rb").read(4096)
sl = d[0x100:0x200]
print("null=%d" % (1 if sl == b"\0" * 256 else 0))
PYEOF
ksagt "$TMPD/platz0.txt" "null" 1 "der geloeschte Platz ist genullt, nicht nur leer gemeldet"

# --------------------------------- 8. die Gegenprobe mit fremden Augen

echo "== 8. die Gegenprobe mit fremden Augen, BEIDE Richtungen =="

# RICHTUNG 1: was OrientOS geschrieben hat, macht der Wirt auf.
"$PY" tools/krypto/gegen.py lies "$TMPD/a.img" geheim > "$TMPD/g1.txt" 2>&1
sed 's/^/        /' "$TMPD/g1.txt"
ksagt "$TMPD/g1.txt" "summe" 1 "der Wirt haelt die Pruefsumme des Kopfes fuer richtig"
auf=$(grep -a -m1 '^auf: ' "$TMPD/g1.txt" | awk '{print $2}')
num "der Wirt macht den Schluesselplatz mit Argon2id+XTS auf" "${auf:-0}" eq 1
hat "$TMPD/g1.txt" "SFO-MUSO" \
    "und findet darunter den OFS-Superblock (die Sektorrechnung stimmt)"

# UND DIE DATEIEN SELBST, mit fremdem Werkzeug aus dem Geheimtext
# geholt -- bis in die zweifach indirekten Zeiger der 40000er Datei.
"$PY" tools/krypto/gegen.py baum "$TMPD/a.img" geheim > "$TMPD/g2.txt" 2>&1
sed 's/^/        /' "$TMPD/g2.txt"
g=$(grep -a -m1 'baum: gut=' "$TMPD/g2.txt" | grep -oE 'gut=[0-9]+' | cut -d= -f2)
num "der Wirt liest ALLE vier Dateien aus dem Geheimtext" "${g:-0}" eq 4

# RICHTUNG 2, DIE SCHAERFERE: der WIRT legt einen Traeger an, den
# OrientOS nie gesehen hat -- fremder Hauptschluessel, fremdes Salz,
# fremde Ableitung. OrientOS muss ihn aufmachen UND darauf schreiben.
"$PY" tools/krypto/gegen.py schreib "$TMPD/f.img" fremdpw 1 64 1 "$BLOCKS" \
    > "$TMPD/g3.txt" 2>&1
hat "$TMPD/g3.txt" "schrieb:" "der Wirt legt einen eigenen Traeger an"
lauf f1 "$TMPD/f.img" "osum nopwr kryptoauf kryptofs kryptobaum kryptopw=fremdpw $KP"
ksagt "$TMPD/f1.txt" "auf"      1 "OrientOS macht den FREMDEN Kopfsatz auf"
ksagt "$TMPD/f1.txt" "fsformat" 1 "und legt sein Dateisystem darauf an"
ksagt "$TMPD/f1.txt" "baum"     4 "und schreibt die vier Dateien"
# Und der Kreis schliesst sich: der Wirt liest sie wieder.
"$PY" tools/krypto/gegen.py baum "$TMPD/f.img" fremdpw > "$TMPD/g4.txt" 2>&1
sed 's/^/        /' "$TMPD/g4.txt"
g=$(grep -a -m1 'baum: gut=' "$TMPD/g4.txt" | grep -oE 'gut=[0-9]+' | cut -d= -f2)
num "der Wirt liest zurueck, was OrientOS auf SEINEN Traeger schrieb" \
    "${g:-0}" eq 4

# Und die falsche Passphrase scheitert auch beim Wirt.
if "$PY" tools/krypto/gegen.py lies "$TMPD/a.img" falschefalsche \
        > "$TMPD/g5.txt" 2>&1; then
    bad "GEGENPROBE: der Wirt macht mit der falschen Passphrase auf"
else
    ok "GEGENPROBE: auch der Wirt macht mit der falschen Passphrase nicht auf"
fi

# ------------------------------------------------------- 9. die Oberflaeche

echo "== 9. die Oberflaeche =="
if bash tools/check-ui.sh > "$TMPD/ui.txt" 2>&1; then
    ok "check-ui.sh PASSED"
else
    bad "check-ui.sh faellt"
    tail -5 "$TMPD/ui.txt" | sed 's/^/        /'
fi

echo
echo "KRYPTO: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
