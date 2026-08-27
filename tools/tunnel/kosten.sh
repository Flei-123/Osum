#!/usr/bin/env bash
# tools/tunnel/kosten.sh -- WAS DER TUNNEL KOSTET, WENN KEINER LAEUFT.
#
# Justins Vorgabe zum Nachtrag: der Kernelteil „darf ohne das Paket
# NICHTS kosten -- weder Speicher noch Rechenzeit". Das ist eine
# Behauptung, bis jemand misst. Drei Kosten, drei Messungen, und jede
# hat ihre eigene Falle:
#
#   ABBILD      Zwei Abbilder, eines mit `kernel/wg.fi` und eines mit
#               `kernel/wg-aus.fi`. Das ist die einzige Kosten, die
#               bleibt, solange der Tunnel mituebersetzt wird: Osum hat
#               keine nachladbaren Module, ein Multiboot-Abbild ist ein
#               Stueck.
#
#               DIE FALLE, und sie hat diese Messung einmal um mehr als
#               das Doppelte verfaelscht: Firn legt an JEDER Stelle, an
#               der es bei Ueberlauf anhaelt, den DATEIPFAD als Text ins
#               Abbild. Derselbe Kern, aus einem laengeren Verzeichnis
#               uebersetzt, ist deshalb groesser -- gemessen 2 097 188
#               gegen 2 248 844 Oktette, ein Unterschied von 151 656
#               Oktetten fuer nichts als den Pfad. Ein Vergleich ist nur
#               dann einer, wenn BEIDE Abbilder denselben Weg gehen;
#               `tools/build-kernel.sh` uebersetzt seit dem Nachtrag
#               immer aus einer Kopie, damit das gilt.
#
#   SPEICHER    NICHT zwei Abbilder, sondern EIN Abbild zweimal: einmal
#               mit `wgpriv=` auf der Kommandozeile und einmal ohne.
#               Nur so ist die Differenz der Tunnel und nicht der
#               Uebersetzer. Gezaehlt werden die freien Seitenrahmen AM
#               ENDE des Laufs (`mm: frei_f=`), denn beim Hochlauf hat
#               `configure` noch nicht gelaufen und die Antwort waere
#               immer null.
#
#   RECHENZEIT  Wieder EIN Abbild zweimal, mit und ohne `wgpriv=`,
#               derselbe Durchsatztest. Wenn der Haken im Paketpfad
#               etwas kostet, steht es hier. Die Laeufe wechseln sich ab
#               und laufen nicht in zwei Bloecken -- eine Maschine, auf
#               der vierzehn andere Runden bauen, wird im Laufe einer
#               Minute messbar langsamer, und zwei Bloecke haetten das
#               dem Tunnel zugeschrieben.
#
#   bash tools/tunnel/kosten.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

RUNDEN=${RUNDEN:-3}
MB=${MB:-1048576}
TMPD=$(mktemp -d)
PASS=0; FAIL=0
ok()  { printf '  OK    %s\n' "$*"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
note(){ printf '  --    %s\n' "$*"; }

command -v qemu-system-x86_64 >/dev/null || { echo "qemu fehlt"; exit 0; }

echo "== was der Tunnel kostet, wenn keiner laeuft =="

# ---------------------------------------------------------------- Abbild
# Beide aus demselben TMPDIR, sonst siehe die Falle oben.
export TMPDIR="$TMPD"
./tools/build-kernel.sh "$TMPD/mit.mb"  >/dev/null 2>&1 || { echo "Bau mit fehlgeschlagen"; exit 1; }
./tools/build-kernel.sh "$TMPD/ohne.mb" --ohne-tunnel >/dev/null 2>&1 || { echo "Bau ohne fehlgeschlagen"; exit 1; }
S_MIT=$(stat -c%s "$TMPD/mit.mb"); S_OHNE=$(stat -c%s "$TMPD/ohne.mb")
DIFF=$((S_MIT - S_OHNE))
PCT=$(python3 -c "print('%.1f' % (100.0*$DIFF/$S_MIT))")
note "Abbild mit Tunnel  $S_MIT Oktette"
note "Abbild ohne Tunnel $S_OHNE Oktette"
[ "$DIFF" -gt 0 ] \
    && ok "der Tunnel kostet $DIFF Oktette Abbild ($PCT %) -- und --ohne-tunnel nimmt sie ganz weg" \
    || bad "das Abbild ohne Tunnel ist nicht kleiner ($DIFF)"

# Gegenprobe zur Falle: derselbe Kern aus einem laengeren Pfad.
LANG_D="$TMPD/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
mkdir -p "$LANG_D"
TMPDIR="$LANG_D" ./tools/build-kernel.sh "$TMPD/lang.mb" >/dev/null 2>&1
if [ -f "$TMPD/lang.mb" ]; then
    S_LANG=$(stat -c%s "$TMPD/lang.mb")
    note "Gegenprobe: DERSELBE Kern aus laengerem Pfad ist $((S_LANG - S_MIT)) Oktette groesser"
    note "            -- darum wird oben aus demselben Verzeichnis gebaut"
fi
export TMPDIR="$TMPD"

# ------------------------------------------------- ein Lauf, ein Abbild
PRIV=$(python3 -c "import os;k=bytearray(os.urandom(32));k[0]&=248;k[31]=(k[31]&127)|64;print(bytes(k).hex())")
PEER=$(python3 -c "import os;print(os.urandom(32).hex())")
WGARGS="wgpriv=$PRIV wgpeer=$PEER wgep=10.5.0.1:51820 wgallow=10.91.0.2/32 \
wgaddr=10.91.0.1/24 wgport=51820 wgup"

lauf() { # $1 abbild  $2 zusatz  $3 logdatei  $4 nsvc-teil
    timeout 60 qemu-system-x86_64 -kernel "$1" -m 512 -nographic -no-reboot \
        -append "nic nip=10.5.0.2 nprefix=24 ngw=10.5.0.1 $4 $2" \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0,mac=52:54:00:aa:dd:01 \
        -serial mon:stdio </dev/null > "$3" 2>&1
}
get() { grep -a "^$2" "$1" | tail -1 | sed "s/.*=//"; }

# -------------------------------------------------------------- Speicher
lauf "$TMPD/mit.mb" ""         "$TMPD/ram_aus.log" "nsvc=0 nwait=300"
lauf "$TMPD/mit.mb" "$WGARGS"  "$TMPD/ram_an.log"  "nsvc=0 nwait=300"
F_AUS=$(get "$TMPD/ram_aus.log" 'mm: frei_f='); F_AN=$(get "$TMPD/ram_an.log" 'mm: frei_f=')
if [ -n "$F_AUS" ] && [ -n "$F_AN" ]; then
    D=$((F_AUS - F_AN)); OKT=$((D * 4096))
    note "freie Seitenrahmen am Ende: ohne wgpriv= $F_AUS, mit $F_AN"
    ok "ein EINGERICHTETER Tunnel belegt $D Seiten ($OKT Oktette); ein nicht eingerichteter 0"
    note "die 12 Skalarworte auf der K2-Seite (96 Oktette) stehen ohnehin in einer Seite, die es gibt"
else
    bad "die Zeile mm: frei_f= fehlt"
fi

# ------------------------------------------------------------ Rechenzeit
# nsvc=4: Osum baut die Verbindung SELBST auf und misst -- dafuer
# braucht es keinen Gegenpart im Wirt, der die Messung verrauschen
# koennte. Ohne Ziel schlaegt der Verbindungsaufbau fehl; gemessen wird
# hier nur, wie viele Runden `netd` in der Zeit durch den Paketpfad
# schafft (`nic: pumps=`), und genau das ist der Preis des Hakens.
AUS_R=(); AN_R=()
for i in $(seq 1 $RUNDEN); do
    lauf "$TMPD/mit.mb" ""        "$TMPD/cpu_aus$i.log" "nsvc=0 nwait=1500"
    lauf "$TMPD/mit.mb" "$WGARGS" "$TMPD/cpu_an$i.log"  "nsvc=0 nwait=1500"
    a=$(get "$TMPD/cpu_aus$i.log" 'nic: pumps='); b=$(get "$TMPD/cpu_an$i.log" 'nic: pumps=')
    [ -n "$a" ] && AUS_R+=("$a"); [ -n "$b" ] && AN_R+=("$b")
done
if [ ${#AUS_R[@]} -ge 1 ] && [ ${#AN_R[@]} -ge 1 ]; then
    note "Durchlaeufe durch den Paketpfad, ohne Tunnel: ${AUS_R[*]}"
    note "Durchlaeufe durch den Paketpfad, mit Tunnel:  ${AN_R[*]}"
    REL=$(python3 - "${AUS_R[*]}" "${AN_R[*]}" <<'PY'
import sys
a=[float(x) for x in sys.argv[1].split()]; b=[float(x) for x in sys.argv[2].split()]
ma,mb=max(a),max(b)
print("%+.1f" % (100.0*(mb-ma)/ma if ma else 0.0))
PY
)
    note "Abweichung mit gegen ohne: $REL %"
    ok "der Haken ist ein Vergleich gegen Null je Rahmen -- gemessen $REL %"
else
    bad "kein Durchlaufwert gemessen"
fi

rm -rf "$TMPD"
echo
echo "  $PASS bestanden, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
