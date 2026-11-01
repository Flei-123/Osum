#!/usr/bin/env bash
#
# Verwendung:  bash tools/caps/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

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
    timeout 90 $QEMU_X86 -kernel "$1" -m 128 -append "$2" \
        -serial "file:$3" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

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
    echo "== Stufe $stage: firnc$stage =="
    IMG="$TMPD/osum$stage.mb"
    if ! bash tools/build-kernel.sh "$IMG" --stufe "$stage" > "$TMPD/build$stage.log" 2>&1; then
        bad "firnc$stage: the kernel cannot be built"
        sed 's/^/        /' "$TMPD/build$stage.log" | head -10
        continue
    fi
    ok "firnc$stage: Kernel gebaut ($(stat -c%s "$IMG") Oktette)"

    OUT="$TMPD/caps$stage.txt"
    rc=0
    run_kernel "$IMG" "$APPEND" "$OUT" || rc=$?
    if [ "$rc" -eq 21 ]; then
        ok "firnc$stage: the kernel exits by itself (21), no exception"
    else
        bad "firnc$stage: Beendigungscode $rc, erwartet 21"
        tail -20 "$OUT" | sed 's/^/        /'
    fi

    has "$OUT" "cap: handles instead of ambient" \
        "firnc$stage: der Abschnitt laeuft"

    i=0
    while [ $i -lt ${#ZUSAGEN[@]} ]; do
        schluessel=${ZUSAGEN[$i]}
        klartext=${ZUSAGEN[$((i+1))]}
        i=$((i+2))
        if grep -qaF "[ ok ] $schluessel" "$OUT"; then
            ok "firnc$stage: $klartext ($schluessel)"
        else
            bad "firnc$stage: $klartext ($schluessel)"
            grep -aF "$schluessel" "$OUT" | sed 's/^/        /' | head -2
        fi
    done
    hasnot "$OUT" "[FAIL]" "firnc$stage: keine gefallene Zusage in Ring 3"

    n=$(grep -acF "caps: 18/18 proofs" "$OUT")
    if [ "$n" -eq 2 ]; then
        ok "firnc$stage: both runs report 18 of 18 commitments"
    else
        bad "firnc$stage: $n runs with 18/18, expected 2"
    fi
    n=$(grep -acF "cap: ring 3 exit=0" "$OUT")
    if [ "$n" -eq 2 ]; then
        ok "firnc$stage: both runs leave ring 3 with 0 failed commitments"
    else
        bad "firnc$stage: $n runs with exit=0, expected 2"
        grep -a 'cap: ring 3 exit=' "$OUT" | sed 's/^/        /'
    fi

    zeile=$(grep -a 'cap: slot t1=' "$OUT" | tail -1)
    t1=$(echo "$zeile" | sed -n 's/.*t1=\([0-9]*\).*/\1/p')
    t2=$(echo "$zeile" | sed -n 's/.*t2=\([0-9]*\).*/\1/p')
    left=$(echo "$zeile" | sed -n 's/.*left=\([0-9]*\).*/\1/p')
    if [ "${t1:-x}" = "${t2:-y}" ]; then
        ok "firnc$stage: the second process got the same slot ($t1)"
    else
        bad "firnc$stage: different slots ($t1 / $t2) -- the commitment measures nothing"
    fi
    if [ "${left:-0}" -eq 16 ]; then
        ok "firnc$stage: the predecessor left 16 of 16 handles behind"
    else
        bad "firnc$stage: the predecessor left $left handles behind, expected 16"
    fi

    seiten=$(readelf -S "$IMG.elf" 2>/dev/null | grep -A1 '\.utext' | tail -1 \
             | awk '{print $1}')
    if [ -n "${seiten:-}" ]; then
        expected=$(( 0x$seiten / 4096 ))
        actual=$(grep -a '^proc: pages=' "$OUT" | head -1 | sed 's/.*=//')
        if [ "${actual:-0}" -eq "$expected" ]; then
            ok "firnc$stage: all $expected pages of .utext are mapped"
        else
            bad "firnc$stage: $actual pages mapped, .utext has $expected"
        fi
        kacheln=$(( (soll * 4096 + 0x1FFFFF) / 0x200000 ))
        echo "        (.utext: $expected Seiten, $kacheln 2-MiB-Kachel(n))"
    fi

    if grep -qa 'cap: first .*differ=1' "$OUT"; then
        ok "firnc$stage: two processes, same slot, different handles"
    else
        bad "firnc$stage: the handles of two processes are equal"
        grep -a 'cap: first' "$OUT" | sed 's/^/        /'
    fi

    OHNE="$TMPD/ohne$stage.txt"
    rc=0
    run_kernel "$IMG" "$APPEND_OHNE" "$OHNE" || rc=$?
    [ "$rc" -eq 21 ] && ok "firnc$stage: control run without caps also ends with 21" \
                     || bad "firnc$stage: control run without caps ends with $rc"
    has "$OHNE" "cap: skipped" "firnc$stage: ohne das Wort caps wird der Abschnitt uebersprungen"
    hasnot "$OHNE" "caps: " "firnc$stage: ohne caps meldet niemand Zusagen"
    hasnot "$OHNE" "cap: ring 3" "firnc$stage: ohne caps laeuft kein Handle-Programm"
    saeubern() {
        sed -e 's/0x[0-9a-f]*/0xX/g' -e 's/[0-9][0-9]*/N/g' \
            -e '/^caps*:/d' -e '/^  \[/d' -e '/^mb: /d' "$1"
    }
    saeubern "$OUT"  | sort > "$TMPD/a$stage"
    saeubern "$OHNE" | sort > "$TMPD/b$stage"
    if diff -q "$TMPD/a$stage" "$TMPD/b$stage" >/dev/null; then
        ok "firnc$stage: the rest of the kernel behaves unchanged"
    else
        bad "firnc$stage: the rest of the kernel changed"
        diff "$TMPD/a$stage" "$TMPD/b$stage" | head -10 | sed 's/^/        /'
    fi
done

# 6. Beide Uebersetzer haben dasselbe gemessen.
if [ -f "$TMPD/caps0.txt" ] && [ -f "$TMPD/caps1.txt" ]; then
    for f in 0 1; do
        grep -aE '^  \[|^caps: ' "$TMPD/caps$f.txt" > "$TMPD/z$f"
    done
    if diff -q "$TMPD/z0" "$TMPD/z1" >/dev/null; then
        ok "firnc0 and firnc1: the same report from ring 3, line for line"
    else
        bad "firnc0 and firnc1 report different things"
        diff "$TMPD/z0" "$TMPD/z1" | head -10 | sed 's/^/        /'
    fi
fi

echo
echo "CAPS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
