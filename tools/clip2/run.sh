#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/clip2/run.sh -- RUNDE CLIP-2: DAS ZIEL EINER ZIEHBEWEGUNG.
#
#   bash tools/clip2/run.sh [arbeitsverzeichnis]
#
# WAS S-002 WIRKLICH WAR. Die Offenliste sagte, `drag_take`/`drag_an`/
# `drag_drop` stuenden "inzwischen in wlib und ulib" und genommen werde
# nur im Editor -- der Dateimanager habe "kein Drop-Ziel". Der erste
# Teil stimmt, der zweite war zu kurz gegriffen: es fehlte NICHT nur
# ein Aufruf im Dateimanager. Es fehlte die MELDUNG. `wlib.on_up`
# (jetzt :6100) kannte das Loslassen, gab es aber an kein Programm
# weiter, und `s_down` ist bei einer Ziehbewegung, die in einem ANDEREN
# Fenster angefangen hat, null -- der alte Rumpf war fertig, bevor er
# zum Ablegen kam. Ohne diese Naht kann kein Programm ein Ziel sein,
# ohne `wlibc` an `wlib` vorbei zu rufen.
#
# DIE FUENF PUNKTE, und jeder hat eine Gegenprobe, die FALLEN muss:
#
#   1. DIE NAHT. `wlib` meldet `K_DROP`, wenn ueber einem angemeldeten
#      Fenster losgelassen wird, waehrend der Ziehplatz voll ist.
#      Gemessen an `explorer: drops N` auf der Leitung.
#      Gegenprobe: ohne `drop_an` darf nichts gemeldet werden.
#   2. DIE TAT. Eine Datei wird aus /data auf den Ordner `bilder`
#      gezogen. Danach ist sie DORT und nicht mehr in /data.
#      Gemessen vom WIRT im Plattenabbild, nicht am Bild.
#   3. DIE INODE. Verschoben heisst umgehaengt: die Inodenummer vor
#      und nach dem Ablegen ist DIESELBE, und der Inhalt auch.
#      Das ist der Unterschied zwischen `rename` und kopieren.
#   4. DAS ZIEL OHNE ORDNER. Auf eine DATEI abgelegt landet das Stueck
#      im angezeigten Ordner und nicht "in" der Datei.
#   5. DER LEERLAUF. Ablegen im selben Ordner tut NICHTS und macht
#      keinen Konfliktdialog auf.
#
# Gemessen wie in jeder Runde davor: eine Maschine, ein Drehbuch mit
# echten Maus-Ereignissen (`ziehvon` -- druecken, in Schritten fahren,
# loslassen), serielle Ausgabe gegen die Erwartung, und das
# Plattenabbild danach vom WIRT gelesen.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
SHOTS=${CLIP2_SHOTS:-$ROOT/.clip2-shots}
mkdir -p "$SHOTS"
RES=${RES:-1280x800}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaE "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- fehlt: $2"; }
hatnicht() { grep -qaE "$2" "$1" 2>/dev/null && bad "$3 -- '$2' sollte NICHT da sein" || ok "$3"; }
letzte() { grep -aoE "$2" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'; }
groesste() { grep -aoE "$2" "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "CLIP-2: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi

# =================================================== 1. der Quelltext
#
# DREI AUSSAGEN, die von aussen NICHT zu sehen sind und deshalb hier
# gefragt werden: dass die Naht in der Bibliothek liegt (und nicht im
# Programm an ihr vorbei), dass das Verschieben ueber `expakt` geht
# (und damit ueber `io.rename`), und dass der Dateimanager keine Datei
# selbst anfasst.
echo "== 1. Quelltext =="
grep -qE '^const K_DROP: u64 = [0-9]+' kernel/user/wlib.fi \
    && ok "wlib kennt K_DROP" || bad "wlib kennt kein K_DROP"
grep -qE 'fire\(d, K_DROP, zeile, w\)' kernel/user/wlib.fi \
    && ok "on_up feuert K_DROP" || bad "on_up feuert kein K_DROP"
grep -qE 'fn drop_an\(' kernel/user/wlib.fi \
    && ok "wlib hat drop_an (ein Fenster meldet sich als Ziel an)" \
    || bad "wlib hat kein drop_an"
grep -qE 'wlib\.drop_an\(true\)' kernel/user/explorer.fi \
    && ok "der Dateimanager meldet sich als Ablegeziel an" \
    || bad "der Dateimanager meldet sich nicht an"
grep -qE 'fn ablegen\(' kernel/user/explorer.fi \
    && ok "der Dateimanager hat eine Ablegefunktion" \
    || bad "der Dateimanager hat keine Ablegefunktion"
grep -qE 'expakt\.einfuegen' kernel/user/explorer.fi \
    && ok "abgelegt wird ueber expakt.einfuegen (also io.rename)" \
    || bad "das Ablegen geht an expakt vorbei"
# Der Dateimanager fasst weiterhin keine Datei selbst an.
if grep -qE 'io\.(create|write_all|unlink)\(' kernel/user/explorer.fi; then
    bad "explorer.fi fasst Dateien selbst an"
else
    ok "explorer.fi fasst keine Datei selbst an"
fi
# GEGENPROBE ZUR NAHT: das Ablegen darf NICHT an wlib vorbeigehen.
if grep -qE 'wlibc\.drag_take' kernel/user/explorer.fi; then
    bad "der Dateimanager ruft wlibc.drag_take an der Bibliothek vorbei"
else
    ok "Gegenprobe: kein wlibc.drag_take im Dateimanager"
fi

# ======================================================== 2. der Bau
echo "== 2. bauen =="
export DESIGNBUILD=${DESIGNBUILD:-/tmp/osum-clip2-build}
bash tools/design/capture.sh "$OUT/bau" nurbau=ja res="$RES" \
    > "$OUT/bau.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: der Bau"; tail -20 "$OUT/bau.log"; exit 1; }
ok "Kern und Programme uebersetzen"

# ======================================================== 3. der Lauf
#
# DAS DREHBUCH. Zeile 0 der Tabelle ist `bilder` (Verzeichnisse
# zuerst), Zeile 1 `notizen`, ab Zeile 2 die Dateien in Namensfolge:
# alpha, beta, delta, epsilon, gamma, zeta. Gezogen wird `alpha.txt`
# (Zeile 2) auf `bilder` (Zeile 0).
echo "== 3. der Lauf =="
cat > "$OUT/dreh.txt" <<'DREH'
warteauf explorer: ready || 240
warte 8
foto 20-vorher
# --- PUNKT 5 ZUERST: ABLEGEN IM SELBEN ORDNER TUT NICHTS.
#     `notizen` (Zeile 1) auf `beta.txt` (Zeile 3) -- Ziel ist damit
#     /data, und dort liegt `notizen` schon.
ziehvon ftabzeile1 ftabzeile3
warte 6
foto 21-leerlauf
# --- PUNKT 2/3: DIE TAT. alpha.txt (Zeile 2) auf bilder (Zeile 0).
ziehvon ftabzeile2 ftabzeile0
warte 8
foto 22-abgelegt
# --- PUNKT 4: AUF EINE DATEI ABGELEGT -> in den ANGEZEIGTEN Ordner.
#     Erst in `bilder` hineingehen, dort liegt jetzt alpha.txt.
doppelauf ftabzeile0
warteauf explorer: cd /data/bilder || 60
warte 5
foto 23-in-bilder
DREH

bash tools/design/capture.sh "$OUT/lauf" res="$RES" \
    extra='nostart wigapp=/bin/explorer' uitrace=yes vorherbild=ja drehbuch="$OUT/dreh.txt" \
    > "$OUT/lauf.log" 2>&1
S="$OUT/lauf/serial.txt"
if [ ! -s "$S" ]; then
    echo "FEHLGESCHLAGEN: keine serielle Ausgabe"; tail -20 "$OUT/lauf.log"; exit 1
fi
hat "$S" 'explorer: ready' "der Dateimanager ist hochgekommen"
grep -qa 'KEIN RECHTECK GEMELDET' "$OUT/lauf.log" \
    && bad "ein ziehvon fand sein Rechteck nicht (siehe lauf.log)" \
    || ok "jedes ziehvon hat seine zwei Rechtecke gefunden"

# ----------------------------------------- Punkt 1: die Naht meldet sich
echo "== 4. Punkt 1: die Naht =="
hat "$S" 'explorer: drops [0-9]+' "wlib meldet das Ablegen (K_DROP)"
dn=$(groesste "$S" 'explorer: drops [0-9]+')
[ "${dn:-0}" -ge 2 ] 2>/dev/null \
    && ok "Punkt 1: $dn Ablegungen gemeldet" \
    || bad "Punkt 1: nur ${dn:-0} Ablegungen gemeldet -- erwartet >= 2"

# ------------------------------------- Punkt 2/5: was die Leitung sagt
echo "== 5. Punkt 2 und 5: die Tat und der Leerlauf =="
hat "$S" 'expl: drop /data/alpha\.txt q=/data/bilder' \
    "Punkt 2: alpha.txt wurde auf /data/bilder abgelegt"
hat "$S" 'expl: drop /data/notizen q=/data gleich' \
    "Punkt 5: das Ablegen im selben Ordner wurde als 'gleich' erkannt"
# Der Leerlauf darf KEINEN Konfliktdialog ausgeloest haben.
hatnicht "$S" 'explorer: dlgrect' \
    "Punkt 5: kein Dialog beim Ablegen im selben Ordner"
# Die Ergebniszeile steht seit dieser Runde FUER SICH ("expl: drop* rc=
# .. z= ..") -- vorher lief sie ohne Zeilenende in die naechste Meldung
# von `expakt` hinein, und kein Muster traf sie.
drc=$(grep -aoE 'expl: drop\* rc=[0-9]+' "$S" | tail -1 \
      | grep -oE '[0-9]+$')
[ "${drc:-1}" = "0" ] \
    && ok "Punkt 2: das Ablegen meldete rc=0" \
    || bad "Punkt 2: das Ablegen meldete rc=${drc:-?}"

# =========================================== 6. DIE PLATTE, VOM WIRT
#
# HIER WIRD GEMESSEN UND NICHT GEGLAUBT. Alles davor ist, was das
# PROGRAMM sagt; das hier ist, was auf der PLATTE steht. Die beiden
# auseinanderzuhalten ist der Sinn dieses Abschnitts -- ein Programm,
# das "rc=0" meldet und nichts getan hat, faellt genau hier auf.
echo "== 6. die Platte (vom Wirt gelesen) =="
IMG="$OUT/lauf/disk.img"
if [ ! -s "$IMG" ]; then
    bad "kein Plattenabbild zum Nachsehen"
else
    # DIE INODE VON VORHER, UND ZWAR AUS DEM RICHTIGEN ABBILD.
    #
    # GEMESSEN am 18.09.2026: hier stand `$OUT/bau/disk.img`, und der
    # Vergleich meldete "inode anders 104 105" fuer eine Datei, die in
    # Wahrheit sauber umgehaengt worden war. Der Grund ist, dass
    # `capture.sh` JE AUFRUF ein eigenes Abbild baut (`mkfs.py` mit
    # `--time=$(date +%s)`): der Bau-Aufruf und der Lauf-Aufruf
    # vergeben verschiedene Inodenummern, und die Nummer aus dem einen
    # Abbild sagt ueber das andere nichts.
    #
    # Also wird die Nummer aus DEM Abbild gelesen, in dem auch gemessen
    # wird -- aus der Sicherung, die dieser Laeufer vor dem Start
    # zieht. Ohne diese Sicherung ist Punkt 3 nicht messbar, und ein
    # Punkt, der nicht messbar ist, wird hier nicht gruen gemeldet.
    VOR=""
    if [ -s "$OUT/lauf/disk.img.vorher" ]; then
        VOR=$(python3 tools/clip2/lies.py "$OUT/lauf/disk.img.vorher" \
              2>/dev/null \
              | grep -oE '^da /data/alpha\.txt ino=[0-9]+' \
              | grep -oE '[0-9]+$')
    fi
    if [ -n "$VOR" ]; then
        ok "die Inode von /data/alpha.txt vor dem Lauf: $VOR"
    else
        bad "MESSUNG UNVOLLSTAENDIG: die Inode vor dem Lauf ist nicht lesbar"
    fi
    python3 tools/clip2/lies.py "$IMG" ${VOR:+"$VOR"} \
        > "$OUT/platte.txt" 2>"$OUT/platte.err"
    if [ -s "$OUT/platte.txt" ]; then
        cat "$OUT/platte.txt"
        # Punkt 2: alpha.txt ist in /data/bilder und NICHT mehr in /data.
        grep -qE '^da /data/bilder/alpha\.txt ' "$OUT/platte.txt" \
            && ok "Punkt 2: alpha.txt liegt in /data/bilder" \
            || bad "Punkt 2: alpha.txt liegt NICHT in /data/bilder"
        grep -qE '^weg /data/alpha\.txt' "$OUT/platte.txt" \
            && ok "Punkt 2: alpha.txt ist nicht mehr in /data" \
            || bad "Punkt 2: alpha.txt liegt noch in /data -- kopiert statt verschoben?"
        # Punkt 3: dieselbe Inode, derselbe Inhalt.
        grep -qE '^inode gleich' "$OUT/platte.txt" \
            && ok "Punkt 3: dieselbe Inodenummer -- umgehaengt, nicht kopiert" \
            || bad "Punkt 3: die Inodenummer hat sich geaendert"
        grep -qE '^inhalt ok' "$OUT/platte.txt" \
            && ok "Punkt 3: der Inhalt ist unveraendert ('eins')" \
            || bad "Punkt 3: der Inhalt stimmt nicht"
        # Punkt 5: notizen ist geblieben, wo es war.
        grep -qE '^da /data/notizen ' "$OUT/platte.txt" \
            && ok "Punkt 5: notizen liegt unveraendert in /data" \
            || bad "Punkt 5: notizen ist verschwunden"
    else
        bad "das Abbild liess sich nicht lesen"; head -5 "$OUT/platte.err"
    fi
fi

# ================================== 7. DIE GEGENPROBE, DIE FALLEN MUSS
#
# WARUM DIESER ABSCHNITT DA IST. Runde GRUNDLINIE-2 hat dreizehn
# Gegenproben gefunden, die NICHTS gemessen haben -- sie meldeten
# gruen, weil der Kern flach kopiert wurde und der `sed` ins Leere
# griff. Also wird hier zuerst geprueft, dass die Gegenprobe ueberhaupt
# GREIFT: die Zeile, die entfernt wird, MUSS vorher da sein, und der
# Bau MUSS danach noch durchlaufen.
echo "== 7. die Gegenprobe: ohne drop_an meldet wlib nichts =="
GEG=$OUT/gegen
mkdir -p "$GEG"
cp kernel/user/explorer.fi "$GEG/explorer.fi.orig"
# DIE WIEDERHERSTELLUNG HAENGT NICHT AM GUTEN ENDE.
#
# Gelernt am 18.09.2026, zweimal: wird der Laeufer waehrend der
# Gegenprobe abgebrochen (Strg+C, Zeitlimit, ein `pkill` von aussen),
# bleibt `wlib.drop_an(false)` im Quelltext stehen -- der Zweig traegt
# dann die ABGESCHALTETE Fassung, und der naechste Lauf misst die
# Gegenprobe statt der Sache. Ein `trap` stellt die Datei auch dann
# zurueck.
wiederher() {
    if [ -s "$GEG/explorer.fi.orig" ]; then
        cp "$GEG/explorer.fi.orig" kernel/user/explorer.fi
    fi
}
trap wiederher EXIT INT TERM
if ! grep -qE '^\s*wlib\.drop_an\(true\)' kernel/user/explorer.fi; then
    bad "GEGENPROBE GREIFT NICHT: 'wlib.drop_an(true)' steht gar nicht da"
else
    ok "Gegenprobe greift: die Zeile 'wlib.drop_an(true)' ist da"
    sed -i 's/^\(\s*\)wlib\.drop_an(true)/\1wlib.drop_an(false)/' \
        kernel/user/explorer.fi
    if grep -qE '^\s*wlib\.drop_an\(false\)' kernel/user/explorer.fi; then
        ok "Gegenprobe: die Anmeldung ist auf false gesetzt"
        export DESIGNBUILD=/tmp/osum-clip2-gegen
        bash tools/design/capture.sh "$GEG/bau" nurbau=ja res="$RES" \
            > "$GEG/bau.log" 2>&1
        if [ $? -ne 0 ]; then
            bad "GEGENPROBE MISST NICHTS: der Bau ohne drop_an lief nicht durch"
            tail -10 "$GEG/bau.log"
        else
            ok "Gegenprobe: der Bau ohne drop_an laeuft durch"
            cp "$OUT/dreh.txt" "$GEG/dreh.txt"
            bash tools/design/capture.sh "$GEG/lauf" res="$RES" \
                extra='nostart wigapp=/bin/explorer' uitrace=yes \
                drehbuch="$GEG/dreh.txt" > "$GEG/lauf.log" 2>&1
            GS="$GEG/lauf/serial.txt"
            if [ ! -s "$GS" ]; then
                bad "GEGENPROBE MISST NICHTS: keine serielle Ausgabe"
            else
                # Sie muss ueberhaupt gelaufen sein ...
                if grep -qaE 'explorer: ready' "$GS"; then
                    ok "Gegenprobe: der Dateimanager kam auch ohne drop_an hoch"
                    # ... und DANN darf nichts abgelegt worden sein.
                    hatnicht "$GS" 'explorer: drops [0-9]+' \
                        "GEGENPROBE: ohne drop_an meldet wlib kein Ablegen"
                    hatnicht "$GS" 'expl: drop ' \
                        "GEGENPROBE: ohne drop_an legt der Dateimanager nichts ab"
                    GIMG="$GEG/lauf/disk.img"
                    if [ -s "$GIMG" ]; then
                        python3 tools/clip2/lies.py "$GIMG" \
                            > "$GEG/platte.txt" 2>/dev/null
                        grep -qE '^da /data/alpha\.txt ' "$GEG/platte.txt" \
                            && ok "GEGENPROBE: alpha.txt blieb in /data" \
                            || bad "GEGENPROBE MISST NICHTS: alpha.txt ist trotzdem weg"
                    fi
                else
                    bad "GEGENPROBE MISST NICHTS: der Dateimanager kam nicht hoch"
                fi
            fi
        fi
    else
        bad "GEGENPROBE GREIFT NICHT: der sed hat nichts geaendert"
    fi
    cp "$GEG/explorer.fi.orig" kernel/user/explorer.fi
    grep -qE '^\s*wlib\.drop_an\(true\)' kernel/user/explorer.fi \
        && ok "der Quelltext ist wiederhergestellt" \
        || bad "ACHTUNG: der Quelltext ist NICHT wiederhergestellt"
fi

# ============================================================ 8. Bilder
echo "== 8. die Bilder =="
if python3 -c "import PIL" 2>/dev/null; then
    python3 - "$OUT/lauf" <<'PY'
import glob, os, sys
from PIL import Image
for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.ppm"))):
    Image.open(p).convert("RGB").save(p[:-4] + ".png")
PY
    n=0
    for f in "$OUT/lauf"/*.png; do
        [ -e "$f" ] || continue
        n=$((n+1)); cp "$f" "$SHOTS/"
    done
    [ "$n" -ge 3 ] && ok "$n Aufnahmen entstanden" || bad "nur $n Aufnahmen"
else
    echo "  (Pillow fehlt, keine Bilder)"
fi

echo
echo "================= CLIP-2 ================="
echo "  gruen $pass   rot $fail"
echo "  Ablage: $OUT"
[ "$fail" -eq 0 ] || exit 1
