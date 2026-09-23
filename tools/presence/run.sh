#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/presence/run.sh -- RUNDE PRAESENZ: die Abnahme.
#
# Gemessen wird gegen ECHTE Osum-Gaeste unter QEMU und gegen den ECHTEN
# Kontodienst (node, TLS 1.3) -- nicht gegen Nachbauten im Speicher.
#
# Die Abschnitte:
#   1. bauen (Kern, /bin/praesenz, /bin/freunde)
#   2. der Dienst am Bus: anmelden, setzen, verteilen
#   3. UNSICHTBAR -- die Zusage, dass nichts hinausgeht
#   4. die Erlaubnisliste (opt-in je App)
#   5. der Kontodienst: Freundschaft, Praesenz binnen 2 s, Chat
#   6. der Server sieht KEINEN Klartext (mit Gegenprobe)
#   7. Offline-Postfach, Abriss, Wiederverbinden
#   8. Justins Regel: 0 Zeichenaufrufe ausserhalb wlib, 0 Farbwerte
#   9. kdata gegen memmap.py, Schirmbilder
#  10. zwanzig Laeufe ohne Panik
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
is()  { if [ "${2:-}" = "$3" ]; then ok "$1: $2"; else bad "$1: '${2:-}', erwartet '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
num() { local n=$1 v=${2:-} o=$3 w=$4
    if [ -z "$v" ]; then bad "$n: keine Zahl (erwartet $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, erwartet $o $w"; fi
}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
BLOCKS=20000
PROGS="sh ls cat echo sleep praesenz freunde desktop taskbar"
: "${OSUM_QEMU_ACCEL:=tcg}"

echo "== 1. bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
FIRNC=vendor/firn/bin/firnc
[ -x "$FIRNC" ] || { echo "PRAESENZ: firnc0 fehlt"; exit 1; }

mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 baut $(echo $PROGS | wc -w) Programme in Ring 3"
else
    bad "firnc0 baut die Programme nicht"; sed 's/^/        /' "$TMPD/b.txt" | head -12
fi
[ -f "$TMPD/bin/praesenz.elf" ] && ok "/bin/praesenz ist da" || bad "/bin/praesenz fehlt"
[ -f "$TMPD/bin/freunde.elf" ] && ok "/bin/freunde ist da" || bad "/bin/freunde fehlt"
note "/bin/praesenz: $(stat -c%s "$TMPD/bin/praesenz.elf" 2>/dev/null) Oktette, /bin/freunde: $(stat -c%s "$TMPD/bin/freunde.elf" 2>/dev/null)"

if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "der Kern baut"
else
    bad "der Kern baut nicht"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
fi

# ---------------------------------------------------------------- QEMU
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "PRAESENZ: uebersprungen, qemu fehlt"; echo "PRAESENZ: $pass passed, $fail failed"; exit 0; }

# EIN GERAET MIT SCHRIFTEN. `/lib/mono.ttf` und `/lib/sans.ttf` sind
# NICHT Beiwerk: ohne sie meldet der Kern "ttf: keine Schrift gefunden",
# der Fensterserver kommt nicht hoch, und JEDES Fensterprogramm bleibt
# still. Genau daran lagen vier rote Zusagen in Abschnitt 9, und keine
# davon lag am Programm -- der Gast hatte schlicht keine Schrift.
# tools/glyph/run.sh legt sie aus demselben Grund an dieselbe Stelle.
geraet() { # <abbild> <skript> [etcverz]
    local img=$1 skript=$2 ed=${3:-}
    local -a A=(build "$img" $BLOCKS /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf"
        "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /proc/ /dev/ /system/ /etc/)
    local p
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/t/s.sh=$skript")
    if [ -n "$ed" ] && [ -d "$ed" ]; then
        local f
        for f in "$ed"/*; do
            [ -f "$f" ] && A+=("/etc/$(basename "$f")=$f")
        done
    fi
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1
}

lauf() { # <abbild> <ausgabename> [ms]
    local img=$1 nm=$2 ms=${3:-25000}
    qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd bus script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local qp=$!
    local w=0
    while [ $w -lt "$ms" ] && kill -0 "$qp" 2>/dev/null; do sleep 0.25; w=$((w+250)); done
    kill -9 "$qp" 2>/dev/null; wait "$qp" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
}

# =====================================================================
echo "== 2. der Dienst am Bus =="
# =====================================================================
# Der Dienst laeuft im Hintergrund, ein zweiter Prozess schickt ihm
# etwas, und danach wird gefragt, was steht. Genau der Weg, den eine App
# auch geht.
cat > "$TMPD/s2.sh" <<'EOS'
praesenz dienst 4000 &
praesenz setzen certus "liest xoffi.ai"
praesenz fokus edit
echo ==FERTIG==
EOS
geraet "$TMPD/A.img" "$TMPD/s2.sh"
lauf "$TMPD/A.img" o2
has "$TMPD/o2.klar" "praesenz: dienst nummer=" "der Dienst meldet sich am Bus an"
DNR=$(grep -a 'praesenz: dienst nummer=' "$TMPD/o2.klar" | head -1 | sed 's/.*nummer=//' | tr -cd '0-9')
num "die Dienstnummer ist eine Zahl" "${DNR:-}" ge 0
hasnot "$TMPD/o2.klar" "praesenz: der Bus sagt nein" "kein abgelehnter Ruf"
hasnot "$TMPD/o2.klar" "PANIK" "keine Panik im Gast"

# =====================================================================
echo "== 3. UNSICHTBAR: es geht wirklich nichts hinaus =="
# =====================================================================
# Die Zusage ist nicht "das Fenster zeigt nichts", sondern "der Text
# verlaesst das Programm nicht". Also: Text setzen, unsichtbar schalten,
# und dann im GANZEN Mitschnitt nach dem Text suchen.
cat > "$TMPD/s3.sh" <<'EOS'
praesenz dienst 8000 &
praesenz setzen certus GEHEIMTEXT4711
praesenz unsichtbar an
praesenz zeigen
echo ==FERTIG==
EOS
mkdir -p "$TMPD/etc3"
printf 'text certus edit\n' > "$TMPD/etc3/praesenz.conf"
geraet "$TMPD/B.img" "$TMPD/s3.sh" "$TMPD/etc3"
lauf "$TMPD/B.img" o3
has "$TMPD/o3.klar" "zustand=unsichtbar" "der Zustand steht auf unsichtbar"
# Der Text darf in der Anzeige NICHT auftauchen, solange unsichtbar gilt.
UZ=$(grep -a 'praesenz: zustand=unsichtbar' "$TMPD/o3.klar" | grep -c 'GEHEIMTEXT4711' || true)
is "der Statustext steht NICHT in der unsichtbaren Zeile" "$UZ" "0"
# Gegenprobe: sichtbar zeigt ihn sehr wohl -- sonst misst der Test nichts.
cat > "$TMPD/s3b.sh" <<'EOS'
praesenz dienst 8000 &
praesenz setzen certus GEHEIMTEXT4711
praesenz zeigen
echo ==FERTIG==
EOS
geraet "$TMPD/B2.img" "$TMPD/s3b.sh" "$TMPD/etc3"
lauf "$TMPD/B2.img" o3b
has "$TMPD/o3b.klar" "GEHEIMTEXT4711" "Gegenprobe: sichtbar zeigt den Text sehr wohl"

# =====================================================================
echo "== 4. die Erlaubnisliste: opt-in je App =="
# =====================================================================
# OHNE /etc/praesenz.conf darf KEINE App einen Text setzen.
cat > "$TMPD/s4.sh" <<'EOS'
praesenz dienst 8000 &
praesenz setzen certus VERBOTENERTEXT
praesenz zeigen
echo ==FERTIG==
EOS
geraet "$TMPD/C.img" "$TMPD/s4.sh"          # kein /etc/praesenz.conf
lauf "$TMPD/C.img" o4
hasnot "$TMPD/o4.klar" "VERBOTENERTEXT" "ohne Erlaubnisdatei setzt keine App einen Text"
# Und eine App, die NICHT in der Liste steht, darf auch nicht.
mkdir -p "$TMPD/etc4"
printf 'text edit karte\n' > "$TMPD/etc4/praesenz.conf"   # certus fehlt
geraet "$TMPD/C2.img" "$TMPD/s4.sh" "$TMPD/etc4"
lauf "$TMPD/C2.img" o4b
hasnot "$TMPD/o4b.klar" "VERBOTENERTEXT" "eine App ausserhalb der Liste bekommt keinen Text"

# =====================================================================
echo "== 5..7. der Kontodienst: Freunde, Praesenz, Chat =="
# =====================================================================
# Der Node-Laeufer misst den Server ueber echtes TLS mit echten
# Ed25519-Schluesseln. Er bringt seine eigene Gegenprobe mit.
if command -v node >/dev/null 2>&1 && [ -f /root/jarvis/test/praesenzd.test.mjs ]; then
    if node /root/jarvis/test/praesenzd.test.mjs > "$TMPD/nd.txt" 2>&1; then
        NPP=$(grep -a 'PRAESENZD:' "$TMPD/nd.txt" | sed 's/.*: \([0-9]*\) passed.*/\1/')
        NFF=$(grep -a 'PRAESENZD:' "$TMPD/nd.txt" | sed 's/.*passed, \([0-9]*\) failed.*/\1/')
        num "der Kontodienst: bestandene Zusagen" "${NPP:-0}" ge 30
        is  "der Kontodienst: rote Zusagen" "${NFF:-1}" "0"
        # Die Zusagen, auf die es in dieser Runde ankommt, einzeln:
        has "$TMPD/nd.txt" "B sieht den Status von A" "Praesenz kommt beim Freund an"
        has "$TMPD/nd.txt" "Klartext im gesamten Servermaterial gefunden: 0" \
            "DER SERVER SIEHT KEINEN KLARTEXT (0 Treffer)"
        has "$TMPD/nd.txt" "Gegenprobe: die Suche findet den Klartext" \
            "und die Gegenprobe zeigt, dass die Suche funktioniert"
        has "$TMPD/nd.txt" "die Nachricht liegt im Postfach" "Offline-Zustellung"
        has "$TMPD/nd.txt" "ein Fremder darf nicht schreiben" "kein Chat ohne Freundschaft"
        MS=$(grep -a 'binnen 2 s' "$TMPD/nd.txt" | sed 's/.*gemessen: \([0-9]*\) ms.*/\1/')
        num "Praesenz beim Freund (ms)" "${MS:-9999}" lt 2000
    else
        bad "der Laeufer des Kontodienstes ist rot"
        tail -20 "$TMPD/nd.txt" | sed 's/^/        /'
    fi
else
    hin "node oder test/praesenzd.test.mjs fehlt -- Abschnitt 5..7 uebersprungen"
fi

# =====================================================================
echo "== 8. Justins Regel: nur wlib, keine festen Farben =="
# =====================================================================
# 0 direkte Zeichenaufrufe ausserhalb wlib, 0 feste Farbwerte.
UI=kernel/user/freunde.fi
# OHNE KOMMENTARZEILEN ZAEHLEN. Der erste Lauf dieses Abschnitts war rot,
# und der einzige Treffer war der Kommentar, der sagt, dass es diese
# Aufrufe hier NICHT gibt ("KEIN wlibc.rect, KEIN wlibc.text"). Ein
# Waechter, der seine eigene Beschriftung fuer einen Verstoss haelt,
# misst nichts -- er meldet nur, dass jemand ueber ihn geschrieben hat.
CODE="$TMPD/ui-ohne-kommentar.fi"
sed 's|//.*$||' "$UI" > "$CODE"
ZEICH=$(grep -cE 'wlibc\.(rect|fill|text|blit|line|pixel|rring|glyph)' "$CODE" || true)
is "direkte Zeichenaufrufe in freunde.fi" "$ZEICH" "0"
# Runde ENGLISCH: mal_* heisst jetzt draw_* -- beide Namen suchen, sonst
# ist "0 Treffer" nur das Ergebnis eines veralteten Musters.
MAL=$(grep -cE 'mal_flaeche|mal_text|mal_balken|mal_punkt|mal_linie|draw_area|draw_text|draw_bar|draw_point|draw_line' "$CODE" || true)
is "direkte mal_*-Aufrufe in freunde.fi" "$MAL" "0"
# Ein Farbwert sieht aus wie 0xRRGGBB.
FARB=$(grep -cE '0x[0-9a-fA-F]{6}' "$CODE" || true)
is "feste Farbwerte in freunde.fi" "$FARB" "0"
# GEGENPROBE: derselbe Waechter muss anschlagen, wenn wirklich einer
# drinsteht. Sonst ist "0 Treffer" auch das Ergebnis eines kaputten
# Suchmusters.
printf 'fn x() { wlibc.rect(1,2,3,4, 0xff00ff) }\n' > "$TMPD/gegen.fi"
GZ=$(grep -cE 'wlibc\.(rect|fill|text|blit|line|pixel|rring|glyph)' "$TMPD/gegen.fi" || true)
GF=$(grep -cE '0x[0-9a-fA-F]{6}' "$TMPD/gegen.fi" || true)
if [ "$GZ" -ge 1 ] && [ "$GF" -ge 1 ]; then
    ok "Gegenprobe: der Waechter erkennt einen echten Verstoss"
else
    bad "Gegenprobe: der Waechter erkennt nicht einmal einen echten Verstoss"
fi
# Und die Texte kommen aus dem Sprachkatalog und nicht aus dem Programm.
MSGN=$(grep -c 'msg.get' "$UI" || true)
num "Texte aus dem Sprachkatalog (msg.get)" "$MSGN" ge 5
# Die Schluessel stehen in BEIDEN Katalogen.
FEHLT=0
for k in $(grep -oE '"freunde\.[a-z]+' "$UI" | tr -d '"' | sort -u); do
    grep -qa "^$k " locale/de/messages || FEHLT=$((FEHLT+1))
    grep -qa "^$k " locale/en/messages || FEHLT=$((FEHLT+1))
done
is "Sprachschluessel, die in einem Katalog fehlen" "$FEHLT" "0"
DEU=$(grep -a '^freunde\.' locale/de/messages | grep -c 'ä\|ö\|ü\|ß' || true)
num "deutsche freunde-Texte mit echten Umlauten" "$DEU" ge 1

# =====================================================================
echo "== 9. kdata und die Schirmbilder =="
# =====================================================================
MM=$(python3 tools/kernel/memmap.py 2>&1 | tail -1)
note "$MM"
KOL=$(printf '%s' "$MM" | sed 's/.*, \([0-9]*\) Kollisionen.*/\1/')
is "Kollisionen in kdata" "${KOL:-x}" "0"

# Die Leiste einmal zeichnen und ein Bild davon machen.
#
# EIN FENSTERPROGRAMM BRAUCHT EINEN FENSTERSERVER. Der erste Lauf dieses
# Abschnitts startete `freunde` ueber ein Shell-Skript wie ein
# Kommandozeilenprogramm -- ohne `gfx wm wig desk` gibt es kein Fenster,
# `wlib.begin` sagt nein, und das Programm meldet gar nichts. Vier rote
# Zusagen, und keine davon lag am Programm. Gestartet wird deshalb wie
# in tools/glyph/run.sh: ueber `wigapp`, mit laufendem Schreibtisch.
mkdir -p docs/shots/praesenz
geraet "$TMPD/D.img" "$TMPD/s2.sh"
qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" \
    -kernel "$TMPD/k0.img" -m 512 -vga std \
    -append "osum vfs bus gfx wm wig desk wmhold wiglong wmdauer wigapp=/bin/freunde,--demo,--rahmen,400 wighalt=40 r3alle nokbd" \
    -serial "file:$TMPD/o9.txt" -display none -no-reboot \
    -drive "file=$TMPD/D.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -monitor "unix:$TMPD/mon,server,nowait" >/dev/null 2>&1 &
QP=$!
sleep 12
if [ -S "$TMPD/mon" ] && command -v socat >/dev/null 2>&1; then
    printf 'screendump %s\n' "$ROOT/docs/shots/praesenz/leiste.ppm" \
        | timeout 10 socat - "unix-connect:$TMPD/mon" >/dev/null 2>&1 || true
fi
sleep 2
kill -9 "$QP" 2>/dev/null; wait "$QP" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/o9.txt" > "$TMPD/o9.klar" 2>/dev/null || true
if [ -f docs/shots/praesenz/leiste.ppm ]; then
    # PPM -> PNG. `convert` (ImageMagick) gibt es auf diesem Wirt nicht;
    # Pythons Pillow ist da, und ein PPM ist ohnehin ein Format, das man
    # notfalls von Hand liest. Bleibt beides aus, bleibt das PPM liegen
    # -- ein Bild in einem sperrigen Format ist mehr als kein Bild.
    if command -v convert >/dev/null 2>&1; then
        convert docs/shots/praesenz/leiste.ppm docs/shots/praesenz/leiste.png 2>/dev/null \
            && rm -f docs/shots/praesenz/leiste.ppm
    else
        python3 -c "from PIL import Image; Image.open('docs/shots/praesenz/leiste.ppm').save('docs/shots/praesenz/leiste.png')" 2>/dev/null \
            && rm -f docs/shots/praesenz/leiste.ppm
    fi
    ok "ein Schirmbild der Freundesleiste entstand"
else
    hin "kein Schirmbild (socat/monitor fehlt) -- kein Fehler dieser Runde"
fi
EIN=$(grep -a 'freunde: eintraege=' "$TMPD/o9.klar" | head -1 | sed 's/.*eintraege=\([0-9]*\).*/\1/')
is "die Leiste zeigt die vier Demo-Freunde" "${EIN:-x}" "4"
has "$TMPD/o9.klar" "angemeldet=1" "mit Konto zeigt sie die Liste"

# OHNE Konto: ein Satz, keine leere Liste.
geraet "$TMPD/E.img" "$TMPD/s2.sh"
qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" \
    -kernel "$TMPD/k0.img" -m 512 -vga std \
    -append "osum vfs bus gfx wm wig desk wmhold wiglong wmdauer wigapp=/bin/freunde,--schuss wighalt=30 r3alle nokbd" \
    -serial "file:$TMPD/o9b.txt" -display none -no-reboot \
    -drive "file=$TMPD/E.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
QB=$!
w=0
while [ $w -lt 30000 ] && kill -0 "$QB" 2>/dev/null; do sleep 0.25; w=$((w+250)); done
kill -9 "$QB" 2>/dev/null; wait "$QB" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/o9b.txt" > "$TMPD/o9b.klar" 2>/dev/null || true
has "$TMPD/o9b.klar" "angemeldet=0" "ohne Konto sagt die Leiste das"
E0=$(grep -a 'freunde: eintraege=' "$TMPD/o9b.klar" | head -1 | sed 's/.*eintraege=\([0-9]*\).*/\1/')
is "und zeigt keine erfundenen Freunde" "${E0:-x}" "0"

# =====================================================================
echo "== 10. zwanzig Laeufe ohne Panik =="
# =====================================================================
PANIK=0; LEER=0
for n in $(seq 1 20); do
    cp "$TMPD/A.img" "$TMPD/L.img"
    qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 4 \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd bus script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/L.txt" -display none -no-reboot \
        -drive "file=$TMPD/L.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    qp=$!
    w=0
    while [ $w -lt 25000 ] && kill -0 "$qp" 2>/dev/null; do sleep 0.25; w=$((w+250)); done
    kill -9 "$qp" 2>/dev/null; wait "$qp" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$TMPD/L.txt" > "$TMPD/L.klar" 2>/dev/null || true
    grep -qa 'PANIK\|panic' "$TMPD/L.klar" && PANIK=$((PANIK+1))
    grep -qa 'praesenz: dienst nummer=' "$TMPD/L.klar" || LEER=$((LEER+1))
done
is "Panik in 20 Laeufen mit -smp 4" "$PANIK" "0"
is "Laeufe, in denen der Dienst nicht hochkam" "$LEER" "0"

echo
echo "PRAESENZ: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
