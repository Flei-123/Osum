#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/caps/run.sh -- DER BEWEIS, DASS RING 3 NUR NOCH DAS DARF,
# WAS IN SEINEM HANDLE STEHT.
#
# Die POSIX-Schicht der Runde K4 arbeitet mit UMGEBUNGSAUTORITAET: ein
# Prozess bekommt die Deskriptoren 0, 1 und 2 geschenkt, `open` sucht in
# einem globalen Wurzelbaum, und eine geratene kleine Zahl ist mit etwas
# Glueck ein offener Deskriptor. Das ist die Bauart von 1970.
#
# Diese Runde bringt das Gegenteil daneben -- portiert aus OrientOS'
# nativer ABI (`libs/osum-abi-native/`, Rust, no_std): eine Handle-Tabelle
# je Prozess (`kernel/cap.fi`), eine zweite Aufrufnummerierung ab 2000
# (`kernel/sys.fi`, `native`), und ein Programm in Ring 3, das damit
# arbeitet (`kernel/uprog.fi`, `u_caps`).
#
# WAS HIER GEMESSEN WIRD, und warum jede Zusage eine Gegenprobe hat:
#
#   1. ACHTZEHN ZUSAGEN AUS RING 3. Nicht der Kernel behauptet, seine
#      Tabelle sei richtig -- ein unprivilegiertes Programm jenseits des
#      Schutzwalls sagt Zeile fuer Zeile, was es darf und was nicht. Jede
#      Zeile wird hier EINZELN nachgelesen; eine Sammelzahl allein waere
#      zu leicht.
#   2. RECHT FEHLT != HANDLE FALSCH. Das gueltige Handle ohne Leserecht
#      gibt -2 (RightsDenied), das gefaelschte -1 (BadHandle). POSIX hat
#      fuer beides nur -EBADF, und das ist der Unterschied, um den es
#      geht.
#   3. NICHTS WIRD GEERBT. Der erste Lauf macht seine Tabelle absichtlich
#      voll (16 von 16). Der zweite Lauf bekommt DENSELBEN Platz in der
#      Aufgabentabelle und zaehlt trotzdem GENAU EIN Handle.
#   4. ZWEI PROZESSE, DERSELBE PLATZ, VERSCHIEDENE HANDLES. Der
#      Wuerfelwert der Tabelle geht in die Generation ein.
#   5. DIE GEGENPROBE: ohne das Wort `caps` auf der Kommandozeile
#      passiert nichts von alledem -- und der uebrige Kernel verhaelt sich
#      Zeile fuer Zeile wie vorher.
#   6. BEIDE UEBERSETZER. firnc0 und firnc1 bauen denselben Kernel, und
#      er sagt beide Male dasselbe.
#
# Verwendung:  bash tools/caps/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "CAPS: skipped, qemu-system-x86_64 is not available"
    exit 0
fi

run_kernel() { # abbild anhang ausgabe
    timeout 90 qemu-system-x86_64 -kernel "$1" -m 128 -append "$2" \
        -serial "file:$3" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

# Die achtzehn Zusagen, die das Programm in Ring 3 meldet. Sie stehen hier
# im Klartext, damit eine geloeschte oder umbenannte Zusage auffaellt --
# und nicht nur eine kleinere Gesamtzahl.
ZUSAGEN=(
 "version"           "die ABI meldet ihre Fassung"
 "count-is-one"      "die Tabelle haelt genau EIN Handle"
 "write-ok"          "schreiben durch das Handle gibt die Laenge zurueck"
 "inspect"           "Auskunft ueber das eigene Handle"
 "read-denied"       "lesen ohne R_READ: RightsDenied, NICHT BadHandle"
 "handle-zero"       "das Handle 0 ist kein stdin"
 "forged-gen"        "eine erfundene Generation trifft nichts"
 "slot-range"        "ein Platz ausserhalb der Tabelle trifft nichts"
 "unknown-nr"        "eine Nummer, die es in dieser ABI nicht gibt"
 "transfer-nopid"    "uebertragen an eine pid, die es nicht gibt"
 "dup-less"          "vervielfaeltigen mit kleinerer Rechtemenge"
 "dup-write"         "die Kopie darf schreiben"
 "dup-nodup"         "die Kopie darf sich NICHT selbst vervielfaeltigen"
 "close"             "schliessen"
 "after-close"       "nach dem Schliessen trifft das Handle nichts mehr"
 "close-twice"       "zweimal schliessen ist ein Fehler, kein Absturz"
 "exhausted"         "eine volle Tabelle sagt Exhausted"
 "alive"             "und der Kernel lebt danach"
)

APPEND="osum nokbd nosched nofs noring3 caps"
APPEND_OHNE="osum nokbd nosched nofs noring3"

for stufe in 0 1; do
    echo "== Stufe $stufe: firnc$stufe =="
    IMG="$TMPD/osum$stufe.mb"
    if ! bash tools/build-kernel.sh "$IMG" --stufe "$stufe" > "$TMPD/build$stufe.log" 2>&1; then
        bad "firnc$stufe: der Kernel laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/build$stufe.log" | head -10
        continue
    fi
    ok "firnc$stufe: Kernel gebaut ($(stat -c%s "$IMG") Oktette)"

    OUT="$TMPD/caps$stufe.txt"
    rc=0
    run_kernel "$IMG" "$APPEND" "$OUT" || rc=$?
    if [ "$rc" -eq 21 ]; then
        ok "firnc$stufe: der Kernel beendet sich selbst (21), keine Ausnahme"
    else
        bad "firnc$stufe: Beendigungscode $rc, erwartet 21"
        tail -20 "$OUT" | sed 's/^/        /'
    fi

    has "$OUT" "cap: handles instead of ambient" \
        "firnc$stufe: der Abschnitt laeuft"

    # 1. Jede einzelne Zusage aus Ring 3.
    i=0
    while [ $i -lt ${#ZUSAGEN[@]} ]; do
        schluessel=${ZUSAGEN[$i]}
        klartext=${ZUSAGEN[$((i+1))]}
        i=$((i+2))
        if grep -qaF "[ ok ] $schluessel" "$OUT"; then
            ok "firnc$stufe: $klartext ($schluessel)"
        else
            bad "firnc$stufe: $klartext ($schluessel)"
            grep -aF "$schluessel" "$OUT" | sed 's/^/        /' | head -2
        fi
    done
    hasnot "$OUT" "[FAIL]" "firnc$stufe: keine gefallene Zusage in Ring 3"

    # 2. Beide Laeufe des Programms melden die volle Zahl und gehen mit 0.
    n=$(grep -acF "caps: 18/18 proofs" "$OUT")
    if [ "$n" -eq 2 ]; then
        ok "firnc$stufe: beide Laeufe melden 18 von 18 Zusagen"
    else
        bad "firnc$stufe: $n Laeufe mit 18/18, erwartet 2"
    fi
    n=$(grep -acF "cap: ring 3 exit=0" "$OUT")
    if [ "$n" -eq 2 ]; then
        ok "firnc$stufe: beide Laeufe verlassen Ring 3 mit 0 gefallenen Zusagen"
    else
        bad "firnc$stufe: $n Laeufe mit exit=0, erwartet 2"
        grep -a 'cap: ring 3 exit=' "$OUT" | sed 's/^/        /'
    fi

    # 3. NICHTS WIRD GEERBT: derselbe Platz der Aufgabentabelle, der
    #    Vorgaenger liess 16 Handles stehen, der Nachfolger zaehlt eines.
    zeile=$(grep -a 'cap: slot t1=' "$OUT" | tail -1)
    t1=$(echo "$zeile" | sed -n 's/.*t1=\([0-9]*\).*/\1/p')
    t2=$(echo "$zeile" | sed -n 's/.*t2=\([0-9]*\).*/\1/p')
    left=$(echo "$zeile" | sed -n 's/.*left=\([0-9]*\).*/\1/p')
    if [ "${t1:-x}" = "${t2:-y}" ]; then
        ok "firnc$stufe: der zweite Prozess bekam denselben Platz ($t1)"
    else
        bad "firnc$stufe: verschiedene Plaetze ($t1 / $t2) -- die Zusage misst nichts"
    fi
    if [ "${left:-0}" -eq 16 ]; then
        ok "firnc$stufe: der Vorgaenger liess 16 von 16 Handles stehen"
    else
        bad "firnc$stufe: der Vorgaenger liess $left Handles stehen, erwartet 16"
    fi

    # 3b. JEDE SEITE VON `.utext` IST WIRKLICH ABGEBILDET. Das ist die
    #     Zusage hinter `user.map_user_pt`: der Abschnitt, den Ring 3
    #     sehen darf, ist mit dieser Runde ueber eine 2-MiB-Kachel
    #     hinausgewachsen (unter firnc1), und eine einzige geteilte
    #     Seitentabelle haette die erste Kachel mit der zweiten
    #     ueberschrieben. Gegenprobe von Hand: mit ausgebautem Fix bleibt
    #     derselbe Kernel unmittelbar nach dem APIC-Abschnitt stehen
    #     (Beendigungscode 0 statt 21).
    seiten=$(readelf -S "$IMG.elf" 2>/dev/null | grep -A1 '\.utext' | tail -1 \
             | awk '{print $1}')
    if [ -n "${seiten:-}" ]; then
        soll=$(( 0x$seiten / 4096 ))
        ist=$(grep -a '^proc: pages=' "$OUT" | head -1 | sed 's/.*=//')
        if [ "${ist:-0}" -eq "$soll" ]; then
            ok "firnc$stufe: alle $soll Seiten von .utext sind abgebildet"
        else
            bad "firnc$stufe: $ist Seiten abgebildet, .utext hat $soll"
        fi
        kacheln=$(( (soll * 4096 + 0x1FFFFF) / 0x200000 ))
        echo "        (.utext: $soll Seiten, $kacheln 2-MiB-Kachel(n))"
    fi

    # 4. Der Wuerfelwert: derselbe Platz, verschiedene Handle-Werte.
    if grep -qa 'cap: first .*differ=1' "$OUT"; then
        ok "firnc$stufe: zwei Prozesse, derselbe Platz, verschiedene Handles"
    else
        bad "firnc$stufe: die Handles zweier Prozesse sind gleich"
        grep -a 'cap: first' "$OUT" | sed 's/^/        /'
    fi

    # 5. DIE GEGENPROBE. Ohne das Wort `caps` gibt es die Schicht nicht --
    #    und der Rest des Kernels sagt Zeile fuer Zeile dasselbe wie
    #    vorher. Das ist die Zusage, dass diese Runde nichts umgebaut hat.
    OHNE="$TMPD/ohne$stufe.txt"
    rc=0
    run_kernel "$IMG" "$APPEND_OHNE" "$OHNE" || rc=$?
    [ "$rc" -eq 21 ] && ok "firnc$stufe: Gegenprobe ohne caps endet ebenfalls mit 21" \
                     || bad "firnc$stufe: Gegenprobe ohne caps endet mit $rc"
    has "$OHNE" "cap: skipped" "firnc$stufe: ohne das Wort caps wird der Abschnitt uebersprungen"
    hasnot "$OHNE" "caps: " "firnc$stufe: ohne caps meldet niemand Zusagen"
    hasnot "$OHNE" "cap: ring 3" "firnc$stufe: ohne caps laeuft kein Handle-Programm"
    # Alles ausserhalb des Capability-Abschnitts muss in beiden Laeufen
    # gleich sein.
    # Die Zeile `mb: ... cmd=...` enthaelt die Kommandozeile selbst und
    # unterscheidet sich damit zwangslaeufig -- sie faellt heraus.
    saeubern() {
        sed -e 's/0x[0-9a-f]*/0xX/g' -e 's/[0-9][0-9]*/N/g' \
            -e '/^caps*:/d' -e '/^  \[/d' -e '/^mb: /d' "$1"
    }
    # SORTIERT verglichen, und das mit Absicht: die Reihenfolge zweier
    # Zeilen zweier gleichzeitig laufender Prozesse haengt am Zeitgeber
    # und ist zwischen zwei Laeufen nicht dieselbe. Was hier gemessen
    # wird, ist, dass KEINE Zeile hinzukommt, wegfaellt oder anders
    # lautet.
    saeubern "$OUT"  | sort > "$TMPD/a$stufe"
    saeubern "$OHNE" | sort > "$TMPD/b$stufe"
    if diff -q "$TMPD/a$stufe" "$TMPD/b$stufe" >/dev/null; then
        ok "firnc$stufe: der uebrige Kernel verhaelt sich unveraendert"
    else
        bad "firnc$stufe: der uebrige Kernel hat sich geaendert"
        diff "$TMPD/a$stufe" "$TMPD/b$stufe" | head -10 | sed 's/^/        /'
    fi
done

# 6. Beide Uebersetzer haben dasselbe gemessen.
if [ -f "$TMPD/caps0.txt" ] && [ -f "$TMPD/caps1.txt" ]; then
    for f in 0 1; do
        grep -aE '^  \[|^caps: ' "$TMPD/caps$f.txt" > "$TMPD/z$f"
    done
    if diff -q "$TMPD/z0" "$TMPD/z1" >/dev/null; then
        ok "firnc0 und firnc1: Zeile fuer Zeile derselbe Bericht aus Ring 3"
    else
        bad "firnc0 und firnc1 melden Verschiedenes"
        diff "$TMPD/z0" "$TMPD/z1" | head -10 | sed 's/^/        /'
    fi
fi

echo
echo "CAPS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
