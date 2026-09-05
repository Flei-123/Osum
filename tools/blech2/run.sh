#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/blech2/run.sh -- DIE ABNAHME DER RUNDE BLECH2.
#
#   bash tools/blech2/run.sh [--kern <osum.mb> --root <root.img>] \
#                            [--sek 60] [--hz 1000] [--aus <verzeichnis>]
#
# ======================================================================
# WAS JUSTINS FOTO VOM 05.09.2026, 22:46 GESAGT HAT -- UND WAS HIER
# NACHGEMESSEN WIRD
# ======================================================================
#
# Ryzen, Huawei 3440x1440, Limine UEFI, USB-Tastatur und -Maus, alles
# laeuft -- und auf der Tafel standen drei Zahlen, die im Pruefstand nie
# aufgefallen waren:
#
#   Zeile 4   RING 5226 VERL 1283   ein Viertel der Ereignisse "verloren"
#   Zeile 7   LEISTE ... TK 643     "643 Titel beschnitten"
#   Zeile 16  ISR VERL 4 SPAET 1    nachgetragene Zeitgebermarken
#
# Dazu: das Terminal voll mit `taskbar:`-Messzeilen, und ein Limine-
# Eintrag, der mitten im Wort aufhoerte.
#
# Was davon ein Fehler war und was ein falsches Messgeraet, steht in
# STATUS-BLECH2.md. Dieser Laeufer stellt die Bedingungen des Fotos in
# QEMU her -- 3440x1440 mit `fbpad=16` (gemeldete Breite 3424 bei einer
# Zeilenbreite von 13760, der Fall echter Firmware), xHCI mit
# USB-Tastatur und USB-Maus, ein Bewegungsstrom in der Groessenordnung
# einer echten Maus -- und misst:
#
#   A. QMP-MAUS. tools/blech2/maus.py schickt 60 s lang mit 1000 Hz
#      `input-send-event` (QEMU fasst das im HID-Geraet auf ~100 Berichte
#      je Sekunde zusammen -- die Rate einer gewoehnlichen Maus), alle 2 s
#      ein Klick auf die Schreibtischflaeche, danach 20 Tasten in das
#      Terminal. Zusagen: VERL 0 und Zeile 4 GRUEN, TK 0, jeder Klick
#      kommt an (gesendet == K == kl), der Titel "Terminal -- sh" steht
#      BILDPUNKTGENAU im Foto (checkshot.py tkette), das Terminal traegt
#      keine langen Messzeilen, die `taskbar:`-Zeilen stehen weiter auf
#      der Leitung, keine Tafelzeile ist zu lang (LG 0).
#   B. KERNSTROM 1000 Hz. `mausflut=1000` erzeugt die Pakete IM KERN --
#      echte tausend je Sekunde, jedes durch `wm.on_mouse`, alle 250 ein
#      Klick. Zusagen: VERL 0, K == D im selben Anstrich (kein Klick
#      zwischen Zeiger und Ring verloren), KOAL > 0 (die Koaleszenz
#      arbeitet).
#   C. KERNSTROM 4000 Hz. Dasselbe mit vierfacher Rate -- 40 Pakete je
#      Schleifenrunde, mehr als der Ring Plaetze hat. Ohne Koaleszenz
#      fiele hier alles um.
#
# Und der Bau selbst prueft die Menuetexte (tools/usbimg/build.sh):
# kein Eintrag laenger als 60 Zeichen NACH dem Einsetzen des Namens.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

SEK=60
HZ=1000
KERN=""
ROOT=""
AUS=""
while [ $# -gt 0 ]; do
    case $1 in
        --kern) KERN=$2; shift 2 ;;
        --root) ROOT=$2; shift 2 ;;
        --sek) SEK=$2; shift 2 ;;
        --hz) HZ=$2; shift 2 ;;
        --aus) AUS=$2; shift 2 ;;
        *) echo "unbekannt: $1"; exit 2 ;;
    esac
done
TMPD=${AUS:-$(mktemp -d)}
mkdir -p "$TMPD"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }
is() { # was ist soll
    if [ "${2:-}" = "$3" ]; then ok "$1: $2"; else bad "$1: '${2:-leer}' (erwartet $3)"; fi
}
gt() { # was ist mehr-als
    if [ -n "${2:-}" ] && [ "$2" -gt "$3" ] 2>/dev/null; then ok "$1: $2 (> $3)"; else bad "$1: '${2:-leer}' (soll > $3)"; fi
}
hat() { # datei muster text
    if grep -qa "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3 -- '$2' fehlt in $1"; fi
}
# Eine Zahl aus der LETZTEN Tafelzeile mit dieser Nummer: `zahl <tafel.txt> <zeile> <schluessel>`
# liest "... SCHLUESSEL 123 ..." oder "... SCHLUESSEL123 ...".
zahl() {
    grep -a "^$2 " "$1" | tail -1 | sed -n "s/.*[ ]$3 *\([0-9][0-9]*\).*/\1/p"
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "BLECH2: uebersprungen, qemu-system-x86_64 fehlt"; exit 0
fi

echo "== 1. bauen =="
if [ -z "$KERN" ]; then
    if bash tools/usbimg/build.sh "$TMPD/bau" > "$TMPD/build.txt" 2>&1; then
        ok "tools/usbimg/build.sh laeuft durch (Kern, Wurzel, limine.conf)"
    else
        bad "das Abbild laesst sich nicht bauen"
        tail -20 "$TMPD/build.txt"
        echo "BLECH2: $pass bestanden, $fail gescheitert"
        exit 1
    fi
    KERN="$TMPD/bau/osum.mb"
    ROOT="$TMPD/bau/root.img"
    L=$(grep -E '^/' "$TMPD/bau/limine.conf" | sed 's|^/*||' \
        | awk '{ if (length($0) > m) m = length($0) } END { print m }')
    if [ "${L:-99}" -le 60 ]; then
        ok "limine.conf: laengster Menueeintrag $L Zeichen (<= 60)"
    else
        bad "limine.conf: laengster Menueeintrag $L Zeichen (> 60)"
    fi
    grep -E '^/' "$TMPD/bau/limine.conf" | sed 's|^/*||' | sed 's/^/       /'
else
    ok "Kern und Wurzel uebergeben: $KERN, $ROOT"
fi

echo
echo "== 2. drei Laeufe, gleichzeitig ($SEK s, QMP $HZ Hz) =="
bash tools/blech2/lauf.sh "$TMPD/A" "$KERN" "$ROOT" "$SEK" "$HZ" "" \
    klickfeld=1800,700,3300,1250 klick_ms=2000 tasten=20 > "$TMPD/A.out" 2>&1 &
bash tools/blech2/lauf.sh "$TMPD/B" "$KERN" "$ROOT" "$SEK" 1 "mausflut=1000" \
    klick_ms=9999999 heim=0 > "$TMPD/B.out" 2>&1 &
bash tools/blech2/lauf.sh "$TMPD/C" "$KERN" "$ROOT" "$SEK" 1 "mausflut=4000" \
    klick_ms=9999999 heim=0 > "$TMPD/C.out" 2>&1 &
wait

echo
echo "== 3. A: die QMP-Maus =="
A="$TMPD/A"
sed 's/^/       /' "$A/maus.txt"
grep -a '^[247] \|^16 \|^23 ' "$A/tafel.txt" | sed 's/^/       /'
klicks=$(sed -n 's/.* klicks=\([0-9]*\).*/\1/p' "$A/maus.txt")
rate=$(sed -n 's/.* rate_hz=\([0-9]*\).*/\1/p' "$A/maus.txt")
gt "der Strom hat QEMU wirklich erreicht (Hz)" "$rate" 300
hat "$A/serial.txt" 'taskbar: STEHT' "die Leiste steht"
gt "Berichte der USB-Maus im Kern (Zeile 1 BER)" "$(zahl "$A/tafel.txt" 1 BER)" 1000
gt "Ereignisse in Fensterringe gelegt (Zeile 4 RING)" "$(zahl "$A/tafel.txt" 4 RING)" 100
is "und daraus VERLOREN (Zeile 4 VERL)" "$(zahl "$A/tafel.txt" 4 VERL)" 0
gt "Bewegungen zusammengefasst statt verloren (Zeile 4 KOAL)" "$(zahl "$A/tafel.txt" 4 KOAL)" 0
is "Klicks beim Zeiger angekommen (Zeile 2 K) == gesendet" "$(zahl "$A/tafel.txt" 2 K)" "$klicks"
kl=$(grep -a 'eingabe:' "$A/serial.txt" | tail -1 | sed -n 's/.* kl=\([0-9]*\).*/\1/p')
is "Klicks in einen Ring gelegt (Puls kl=) == gesendet" "$kl" "$klicks"
is "Tasten im Terminal angekommen (Zeile 11 TAS)" "$(zahl "$A/tafel.txt" 11 TAS)" 20
is "Titel im Band der Tafel (Zeile 7 TK)" "$(zahl "$A/tafel.txt" 7 TK)" 0
is "keine Tafelzeile zu lang (Zeile 23 LG)" "$(zahl "$A/tafel.txt" 23 LG)" 0
hat "$A/serial.txt" 'desk: protokoll tty=' "die Schreibtischprogramme haben ein Protokoll-Terminal"
gt "die taskbar:-Zeilen stehen weiter auf der Leitung" "$(grep -ac '^taskbar: ' "$A/serial.txt")" 50
tka=$(grep -a '^wm: fen i=0 ' "$A/serial.txt" | tail -1 | sed -n 's/.* tka=\([0-9]*\).*/\1/p')
echo "       (alte TK-Zaehlweise in diesem Lauf: tka=$tka -- Schnittfenster rechts vom Titelanfang)"

# DER TITEL, BILDPUNKTGENAU. Der Server sagt in `wm: fen`, wo er den
# Titel hingemalt hat (tx, tb, tp) und in welchen Farben (tf, tg); der
# zweite Rasterer rechnet nach.
F=$(grep -a '^wm: fen i=0 ' "$A/serial.txt" | tail -1)
tx=$(printf '%s' "$F" | sed -n 's/.* tx=\([0-9]*\).*/\1/p')
tb=$(printf '%s' "$F" | sed -n 's/.* tb=\([0-9]*\).*/\1/p')
tp=$(printf '%s' "$F" | sed -n 's/.* tp=\([0-9]*\).*/\1/p')
tf=$(printf '%s' "$F" | sed -n 's/.* tf=\(0x[0-9a-f]*\).*/\1/p')
tg=$(printf '%s' "$F" | sed -n 's/.* tg=\(0x[0-9a-f]*\).*/\1/p')
rgb() { python3 -c "v=int('$1',16); print((v>>16)&255,(v>>8)&255,v&255)"; }
if [ -n "$tx" ] && [ -f "$A/shot.ppm" ]; then
    aus=$(python3 tools/gfx/checkshot.py tkette "$A/shot.ppm" assets/osum-sans.ttf \
        "$tp" "$tx" "$tb" $(rgb "$tf") $(rgb "$tg") "Terminal -- sh" 2>&1)
    if [ $? -eq 0 ]; then
        ok "der Titel 'Terminal -- sh' steht vollstaendig im Bild bei $tx,$tb -- $aus"
    else
        bad "der Titel stimmt im Bild nicht: $aus"
    fi
else
    bad "kein Titelort (wm: fen tx=) oder kein Bild"
fi

# DAS TERMINAL OHNE MESSZEILEN. `taskbar: text start x=32 base=50 ...`
# ist ueber 40 Zeichen lang; was die Shell selbst schreibt ("sh: ready,
# osum"), ist kurz. Also: rechts von Spalte 22 darf in der ganzen
# Fensterflaeche KEINE Tinte stehen. Auf dem Foto vom 05.09. stand dort
# Zeile fuer Zeile Text.
W=$(grep -a '^wm: fen i=0 ' "$A/serial.txt" | tail -1)
wx=$(printf '%s' "$W" | sed -n 's/.* x=\([0-9]*\).*/\1/p')
wy=$(printf '%s' "$W" | sed -n 's/.* y=\([0-9]*\).*/\1/p')
ww=$(printf '%s' "$W" | sed -n 's/.* w=\([0-9]*\).*/\1/p')
if [ -n "$wx" ] && [ -f "$A/shot.ppm" ]; then
    tinte=$(python3 - "$A/shot.ppm" "$wx" "$wy" "$ww" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
p = d.split(b'\n', 3); W, H = map(int, p[1].split()); px = p[3]
wx, wy, ww = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
def at(x, y):
    i = (y * W + x) * 3; return px[i:i+3]
# Rand 4, Titelleiste 44 (uisc 2), Zelle 20 breit: Spalte 22 beginnt bei 4 + 22*20
x0 = wx + 4 + 22 * 20; x1 = wx + 4 + ww - 8
y0 = wy + 44 + 4; y1 = min(wy + 44 + 700, H - 100)
# RUNDE BLECH2, KORREKTUR DER MESSUNG: das Terminal malt seine Zeilen
# ABWECHSELND auf zwei Untergruende (Streifen). "ungleich EINER
# Hintergrundfarbe" zaehlt darum jede zweite Zeile komplett mit und
# meldet 73920 Tintenpunkte, wo gar kein Text steht -- das Bild zeigt
# nur kurze `sh:`-Zeilen. Gezaehlt wird deshalb gegen die BEIDEN
# Streifenfarben, und die holt sich die Messung aus derselben Spalte
# ganz rechts, wo nie Text stehen kann.
bgs = set()
for y in range(y0, y1):
    bgs.add(at(x1 - 2, y))
n = sum(1 for y in range(y0, y1) for x in range(x0, x1) if at(x, y) not in bgs)
print(n)
PY
)
    # Der Zeiger darf dort stehen (er ist ~10 Punkte gross); eine
    # einzige `taskbar:`-Messzeile brachte auf Justins Foto Tausende.
    if [ "${tinte:-999}" -le 200 ]; then
        ok "keine Messzeilen rechts von Spalte 22 im Terminal (Tinte $tinte, nur der Zeiger)"
    else
        bad "Tinte rechts von Spalte 22 im Terminal (Messzeilen): $tinte (erwartet <= 200)"
    fi
else
    bad "keine Fenstergeometrie fuer das Terminal"
fi

for lauf in B C; do
    echo
    echo "== 4. $lauf: der Kernstrom ($([ $lauf = B ] && echo 1000 || echo 4000) Hz) =="
    D="$TMPD/$lauf"
    grep -a '^[247] \|^16 \|^23 ' "$D/tafel.txt" | sed 's/^/       /'
    gt "Pakete beim Zeiger (Zeile 2 M)" "$(zahl "$D/tafel.txt" 2 M)" 20000
    gt "Klicks beim Zeiger (Zeile 2 K)" "$(zahl "$D/tafel.txt" 2 K)" 100
    is "Klicks in einen Ring gelegt (Zeile 2 D) == K" "$(zahl "$D/tafel.txt" 2 D)" "$(zahl "$D/tafel.txt" 2 K)"
    is "VERLOREN (Zeile 4 VERL)" "$(zahl "$D/tafel.txt" 4 VERL)" 0
    gt "zusammengefasst (Zeile 4 KOAL)" "$(zahl "$D/tafel.txt" 4 KOAL)" 10000
    is "Titel im Band (Zeile 7 TK)" "$(zahl "$D/tafel.txt" 7 TK)" 0
    is "keine Tafelzeile zu lang (Zeile 23 LG)" "$(zahl "$D/tafel.txt" 23 LG)" 0
    hat "$D/serial.txt" '^tafel: 23 SICHER WA 0 ' "kein Stapelueberlauf (WA 0)"
done

echo
echo "== 5. der Zeitgeber (Zeile 16), zur Einordnung =="
for lauf in A B C; do
    printf '       %s: %s\n' "$lauf" "$(grep -a '^16 ' "$TMPD/$lauf/tafel.txt" | tail -1)"
done
echo "       VERL sind Marken, die der Zyklenzaehler nachtragen musste; LM sagt, in welcher"
echo "       Sekunde zuletzt. Unter KVM kommt das vom Wirt (der Kern traegt LAPIC-Marken nicht"
echo "       nach, wenn der vCPU steht); die Uhr bleibt richtig (Zeile 19 RTC == KRN)."

echo
echo "Bilder: $TMPD/A/shot.png  $TMPD/B/shot.png  $TMPD/C/shot.png"
echo "BLECH2: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ]
