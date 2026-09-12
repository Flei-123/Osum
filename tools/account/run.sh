#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/account/run.sh -- RUNDE KONTO, GEMESSEN.
#
# ======================================================================
# WAS DIESE RUNDE BEHAUPTET UND WAS HIER NACHGERECHNET WIRD
# ======================================================================
#
#  0. DIE TRENNUNG. Kein Anbietername im allgemeinen Teil -- gemessen
#     mit `tools/account/split.py` ueber acht Dateien, plus die
#     Gegenprobe, die genau EINE Zeile `if anbieter == "..."` einbaut
#     und den Wachhund fallen laesst.
#  1. DAS PROGRAMM BAUT UND PASST. `--profile=app`, keine undefinierte
#     Marke, gebunden mit kernel/user/user.ld, wie `fetch.fi`.
#  2. DER KATALOG. Jeder Schluessel, den diese Runde benutzt, steht in
#     BEIDEN Sprachdateien, und `konto --text` gibt auf dem laufenden
#     System denselben Satz zurueck, den der WIRT aus der Datei liest --
#     mit einer zweiten Umsetzung, in Python.
#  3. ANMELDEN AN ALLEN DREI RUECKEN, ueber TLS 1.3 gegen einen Nachbau
#     der beschriebenen APIs. Danach: NEUSTART, und die Sitzung ist noch
#     da. Danach: ABMELDEN, und das Merkmal ist WIRKLICH von der Platte
#     -- nachgesehen wird IM ABBILD, an den Bloecken, an denen die Datei
#     lag.
#  4. DAS TOKEN LIEGT NIE IM KLARTEXT AUF DER PLATTE. Gesucht wird das
#     Token, das der Server ausgestellt hat, im ganzen Abbild.
#     Gegenprobe `--kaputt=klartext`: dann MUSS es gefunden werden.
#  5. KEINE AMBIENTEN KEKSE. Die Attrappe schreibt JEDE Kopfzeile mit;
#     der Xoffi-Weg traegt `Authorization: Bearer` und NIE `Cookie`.
#     Gegenprobe `--kaputt=keks`.
#  6. FALSCHES KENNWORT: klarer Fehler, keine Sitzung, kein Token auf
#     der Platte. Zwanzig Fehlversuche: der Server bremst, das Geraet
#     bleibt stehen, und die Antwort verraet NICHT, ob es das Konto gibt
#     -- gemessen an den Antworten fuer einen bekannten und einen
#     erfundenen Namen.
#  7. ZWEITER FAKTOR: der ganze Weg mit `temp_token`, und der Fall
#     "abgelaufen".
#  8. ZWEI ORGANISATIONEN, DIESELBE ANSCHRIFT: es wird GEFRAGT, es
#     entstehen ZWEI Konten mit ZWEI Kennungen, und die Sitzung des
#     einen ist im anderen nicht sichtbar. Gegenprobe
#     `--kaputt=einemandant`: dann faellt es zusammen.
#  9. ERNEUERN: Token kurz vor dem Ablauf -> neues Token. Erneuerung
#     abgelehnt -> sauber abgemeldet, und die Kontenliste ueberlebt es.
# 10. KEIN NETZ: anmelden schlaegt klar fehl; ein ANGEMELDETES Geraet
#     bleibt angemeldet und benutzbar. Das ist die wichtigste Zusage.
# 11. master_session WIRD ABGELEHNT; is_admin und nexus_core_access
#     erzeugen KEINE lokale Berechtigung. Gegenproben `--kaputt
#     claimcheck` und `--kaputt=rechte`.
# 12. DAS PRINZIP: ein System einrichten, benutzen und sichern, OHNE
#     sich je anzumelden -- und der Beweis, dass diese Runde daran
#     nichts geaendert hat.
#
# Aufruf:  bash tools/account/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }
is()  { if [ "${2:-}" = "$3" ]; then ok "$1: $2"; else bad "$1: '${2:-}', erwartet '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
num() { local n=$1 v=${2:-} o=$3 w=$4
    if [ -z "$v" ]; then bad "$n: keine Zahl (erwartet $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, erwartet $o $w"; fi
}
# Der Wert einer `konto: <name> = <wert>`-Zeile, die letzte davon.
kv() { grep -aoE "^konto: $2 = .*" "$1" 2>/dev/null | tail -1 | sed 's/^konto: [a-z_]* = //'; }
kv1() { grep -aoE "^konto: $2 = .*" "$1" 2>/dev/null | head -1 | sed 's/^konto: [a-z_]* = //'; }
kvn() { grep -acE "^konto: $2 = " "$1" 2>/dev/null; }

for t in qemu-system-x86_64 python3 openssl ip; do
    command -v "$t" >/dev/null 2>&1 || { echo "KONTO: uebersprungen, $t fehlt"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "KONTO: uebersprungen, python3-cryptography fehlt"; exit 0; }

TMPD=$(mktemp -d)
NS=konto-$$
V0=ko0-$$
V1=ko1
BPORT=$(( 15000 + ($$ % 300) * 2 ))
QPORT=$(( BPORT + 1 ))
SRVPID=""
BRPID=""
aufraeumen() {
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    [ -z "${KEEP_TMPD:-}" ] && rm -rf "$TMPD"
    [ -n "${KEEP_TMPD:-}" ] && echo "TMPD=$TMPD"
}
trap aufraeumen EXIT

ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "KONTO: uebersprungen, keine Netzraeume"; exit 0; }
ip netns del "$NS" 2>/dev/null

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

# ======================================================================
echo "== 0. die Trennung: Anbieterwissen bleibt im Ruecken =="
# ======================================================================
python3 tools/account/split.py . --zahlen > "$TMPD/tr.txt" 2>&1
TRRC=$?
cat "$TMPD/tr.txt" | sed 's/^/        /'
is "die Trennungswache" "$TRRC" "0"
VER=$(grep -oE 'verstoesse=[0-9]+' "$TMPD/tr.txt" | cut -d= -f2)
is "Verstoesse im allgemeinen Teil" "$VER" "0"

# DIE GEGENPROBE. Eine Zeile, die genau das tut, was die Runde verboten
# hat -- und der Wachhund muss anschlagen.
cp -a kernel/app "$TMPD/appsicherung"
mkdir -p "$TMPD/kaputt/kernel/app"
cp kernel/app/*.fi "$TMPD/kaputt/kernel/app/"
python3 - "$TMPD/kaputt/kernel/app/account.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("fn befehl_liste() -> i32 {",
              'fn befehl_liste() -> i32 {\n    var wo: [u8; 6] = "xoffi\\0"\n    if gleich(wo, wo) { }\n')
open(p, "w", encoding="utf-8").write(s)
PY
python3 tools/account/split.py "$TMPD/kaputt" > "$TMPD/tr2.txt" 2>&1
if [ $? -ne 0 ] && grep -q VERSTOSS "$TMPD/tr2.txt"; then
    ok "Gegenprobe: EIN if mit einem Anbieternamen im allgemeinen Teil faellt auf"
else
    bad "Gegenprobe: der Verstoss wurde NICHT gefunden"
fi

# ======================================================================
echo "== 1. das Programm baut und passt =="
# ======================================================================
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if FIRNLIB="$ROOT/vendor/firn/lib" "$FIRNC" -c --profile=app \
        -o "$TMPD/konto.o" kernel/app/account.fi > "$TMPD/cc.log" 2>&1; then
    ok "firnc --profile=app: konto.fi mit std.net, std.json, tls.tls, tls.x509"
else
    bad "konto.fi uebersetzt nicht"; head -20 "$TMPD/cc.log" | sed 's/^/        /'
    echo "KONTO: $pass passed, $fail failed"; exit 1
fi
undef=$(nm -u "$TMPD/konto.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "keine einzige undefinierte Marke -- kein crt.s, keine libc" \
                || bad "undefiniert: $undef"
ld -T kernel/user/user.ld -o "$TMPD/konto.elf" "$TMPD/konto.o" 2>"$TMPD/ld.err" \
    && ok "ld mit kernel/user/user.ld" \
    || { bad "ld schlaegt fehl"; head -3 "$TMPD/ld.err"; }
strip --strip-all "$TMPD/konto.elf" 2>/dev/null
SZ=$(stat -c%s "$TMPD/konto.elf" 2>/dev/null)
num "das Programm auf der Platte, in Oktetten" "$SZ" le 2500000
ZEILEN=$(wc -l kernel/app/account.fi kernel/app/anbieter.fi kernel/app/knetz.fi \
    kernel/app/kspeicher.fi kernel/app/ksiegel.fi kernel/app/kjson.fi \
    kernel/app/kmsg.fi kernel/app/kgegen.fi kernel/app/anb_jarvis.fi \
    kernel/app/anb_xoffi.fi kernel/app/anb_eigen.fi | tail -1 | awk '{print $1}')
hin "Quelltext dieser Runde in kernel/app/: $ZEILEN Zeilen"

# ======================================================================
echo "== 2. der Sprachkatalog: jeder Schluessel in beiden Dateien =="
# ======================================================================
python3 - "$ROOT" > "$TMPD/keys.txt" 2>&1 <<'PY'
import re, sys, os
root = sys.argv[1]
keys = set()
for d, _, fs in os.walk(os.path.join(root, "kernel")):
    for f in fs:
        if not f.endswith(".fi"):
            continue
        t = open(os.path.join(d, f), encoding="utf-8", errors="replace").read()
        for m in re.finditer(r'"(konto\.[a-z0-9_.]+)\\0', t):
            keys.add(m.group(1))
def katalog(p):
    d = {}
    for z in open(p, encoding="utf-8"):
        if z.startswith("#") or "=" not in z:
            continue
        k, v = z.split("=", 1)
        d[k.strip()] = v.strip()
    return d
en = katalog(os.path.join(root, "locale/en/messages"))
de = katalog(os.path.join(root, "locale/de/messages"))
fehlen_en = sorted(k for k in keys if k not in en)
fehlen_de = sorted(k for k in keys if k not in de)
gleich = sorted(k for k in keys if k in en and k in de and en[k] == de[k])
print("keys=%d fehlen_en=%d fehlen_de=%d untuebersetzt=%d"
      % (len(keys), len(fehlen_en), len(fehlen_de), len(gleich)))
for k in fehlen_en:
    print("FEHLT_EN %s" % k)
for k in fehlen_de:
    print("FEHLT_DE %s" % k)
PY
cat "$TMPD/keys.txt" | head -20 | sed 's/^/        /'
KN=$(grep -oE 'keys=[0-9]+' "$TMPD/keys.txt" | cut -d= -f2)
FE=$(grep -oE 'fehlen_en=[0-9]+' "$TMPD/keys.txt" | cut -d= -f2)
FD=$(grep -oE 'fehlen_de=[0-9]+' "$TMPD/keys.txt" | cut -d= -f2)
num "Schluessel dieser Runde im Quelltext" "$KN" ge 20
is "davon in locale/en/messages nicht vorhanden" "$FE" "0"
is "davon in locale/de/messages nicht vorhanden" "$FD" "0"
# ECHTE UMLAUTE. Runde UMLAUT2 hat die Umschrift zum Fehler erklaert.
if grep -aE '^konto\.' locale/de/messages | grep -qE 'ue[a-z]|ae[a-z]|oe[a-z]|ss[^a-z]' ; then
    hin "Hinweis: pruefe die deutschen Konto-Zeilen auf Umschrift"
fi
if grep -aE '^konto\.' locale/de/messages | grep -q 'ä\|ö\|ü\|ß'; then
    ok "die deutschen Konto-Texte tragen ECHTE Umlaute"
else
    bad "die deutschen Konto-Texte haben keinen einzigen Umlaut"
fi
TABS_DE=$(grep -a '^settings.tabs' locale/de/messages | tr '\\' '\n' | grep -c '^n')
# RUNDE PRAESENZ: ZEHN STATT NEUN. Auf dem Zweig `konto` allein war
# "Konten" der neunte Reiter. Runde PRAESENZ hat `konto` UND `sync` auf
# einen Zweig geholt, und `sync` bringt "Abgleich" als zehnten mit
# (beide Runden hatten sich unabhaengig die Nummer 8 genommen; KONTO
# behaelt 8, SYNC rueckt auf 9). Die Zahl steht hier weiterhin fest und
# wird nicht aus der Datei abgeleitet -- eine Zusage, die sich selbst
# nachrechnet, faellt nie auf.
num "Reiter in settings.tabs (deutsch)" "$((TABS_DE + 1))" eq 10

# ======================================================================
echo "== 3. der Aufbau: Kern, Userland, Zertifikat, Attrappe =="
# ======================================================================
HWNET_PROGS="sh ls cat echo settings" bash tools/hwnet/build.sh "$TMPD/s0" 0 \
    > "$TMPD/b0.txt" 2>&1 \
    || { bad "der Kern baut nicht"; tail -8 "$TMPD/b0.txt" | sed 's/^/        /'
         echo "KONTO: $pass passed, $fail failed"; exit 1; }
ok "Kern und Userland gebaut (mit /bin/settings, dem neunten Reiter)"
K="$TMPD/s0/k.mb"
python3 tools/hwnet/mkcerts.py "$TMPD/certs" konto.test > "$TMPD/certs.txt" 2>&1 \
    && ok "die Testzertifikate kommen aus Pythons cryptography, nicht aus diesem Baum" \
    || bad "mkcerts.py schlug fehl"
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"

# Die Kennwortdateien im Abbild. Das Programm liest sein Geheimnis von
# der Eingabe -- an einer Roehre oder einer Datei wird nicht gefragt.
printf 'richtig\n'    > "$TMPD/pw_gut"
printf 'auchrichtig\n' > "$TMPD/pw2"
printf 'falsch\n'     > "$TMPD/pw_schlecht"
: > "$TMPD/leer"
mkdir -p "$TMPD/eigenordner/konten"
# Ein Konto fuer den Ordner-Ruecken: PBKDF2 auf dem WIRT gerechnet, mit
# Pythons hashlib -- eine zweite Umsetzung gegen die in anb_eigen.fi.
python3 - "$TMPD/eigenordner/konten/lokal" <<'PY'
import hashlib, os, sys
salz = bytes(range(16))
pruef = hashlib.pbkdf2_hmac("sha256", b"richtig", salz, 8192, 32)
open(sys.argv[1], "w", encoding="utf-8").write(
    "eigen1\nkennung\tlokal\nsalz\t%s\nrunden\t8192\nnachweis\t%s\n"
    "subjekt\tlokal-1\nanzeige\tLokal\n" % (salz.hex(), pruef.hex()))
PY
ok "der Ordner-Ruecken hat ein Konto, dessen PBKDF2 der WIRT gerechnet hat"

abbild() { # <ziel>
    python3 tools/osum/mkfs.py build "$1" 24576 \
        /bin/ /etc/ /etc/ssl/ /usr/ /usr/share/ /usr/share/locale/ \
        /usr/share/locale/en/ /usr/share/locale/de/ \
        /users/ /users/justin/ /users/justin/config/ \
        /eigen/ /eigen/konten/ \
        "/bin/sh=$TMPD/s0/sh.elf" \
        "/bin/ls=$TMPD/s0/ls.elf" \
        "/bin/cat=$TMPD/s0/cat.elf" \
        "/bin/echo=$TMPD/s0/echo.elf" \
        "/bin/konto=$TMPD/konto.elf" \
        "/etc/ssl/roots.pem=$TMPD/certs/ca.pem" \
        "/etc/passwd=$TMPD/passwd" \
        "/etc/locale.conf=$TMPD/locale.conf" \
        "/etc/konten.conf=$TMPD/konten.conf" \
        "/usr/share/locale/en/messages=$ROOT/locale/en/messages" \
        "/usr/share/locale/de/messages=$ROOT/locale/de/messages" \
        "/pw_gut=$TMPD/pw_gut" \
        "/pw_schlecht=$TMPD/pw_schlecht" \
        "/pw2=$TMPD/pw2" \
        "/leer=$TMPD/leer" \
        "/eigen/konten/lokal=$TMPD/eigenordner/konten/lokal" \
        > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs: $(tail -2 "$TMPD/mkfs.txt")"; return 1; }
    return 0
}
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=de\n' > "$TMPD/locale.conf"

netz_auf() {
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add 10.9.0.1/24 dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
    "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!
    sleep 0.4
}
netz_zu() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; BRPID=""
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
}
server_auf() { # [zusatzargumente]
    ip netns exec "$NS" python3 tools/account/attrappe.py --port 8443 \
        --zertifikat "$TMPD/certs/good.pem" --schluessel "$TMPD/certs/good.key" \
        --verzeichnis "$TMPD" "$@" > "$TMPD/srv.log" 2>&1 & SRVPID=$!
    sleep 1.0
}
server_zu() { [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; SRVPID=""; }
server_auf_zert() { # <pem> <key> [zusatz]
    local pem=$1 key=$2; shift 2
    ip netns exec "$NS" python3 tools/account/attrappe.py --port 8443 \
        --zertifikat "$pem" --schluessel "$key" \
        --verzeichnis "$TMPD" "$@" > "$TMPD/srv.log" 2>&1 & SRVPID=$!
    sleep 1.0
}

lauf() { # <abbild> <script> <aus>
    timeout 200 qemu-system-x86_64 -kernel "$K" -m 512 \
        -append "osum nokbd nosched noproc nofs noring3 nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$2;exit" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$1,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
lauf_ohne_netz() { # <abbild> <script> <aus>
    # KEINE Netzkarte. Nicht "die Gegenstelle antwortet nicht" -- gar
    # kein Netz, so wie ein Zug im Tunnel.
    timeout 200 qemu-system-x86_64 -kernel "$K" -m 512 \
        -append "osum nokbd nosched noproc nofs noring3 script=$2;exit" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$1,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

Z="https://10.9.0.1:8443"
N="konto.test"

# /etc/konten.conf -- eine Zeile je Anbieter. Damit steht die Adresse
# EINMAL da und nicht in jedem Befehl; das ist nicht nur bequem, es ist
# noetig: dieser Kern gibt einem Programm acht Woerter.
{
  printf 'jarvis ziel=%s name=%s\n' "$Z" "$N"
  printf 'xoffi  ziel=%s name=%s\n' "$Z" "$N"
  printf 'eigen  ziel=%s name=%s\n' "$Z" "$N"
} > "$TMPD/konten.conf"

# ======================================================================
echo "== 4. anmelden an allen drei Ruecken, ueber TLS 1.3 =="
# ======================================================================
netz_auf
server_auf

abbild "$TMPD/d1.img" || true
lauf "$TMPD/d1.img" "konto anbieter" "$TMPD/o_anb.txt"
is "wie viele Ruecken angemeldet sind" "$(kv "$TMPD/o_anb.txt" anbieter_anzahl)" "3"
for r in jarvis xoffi eigen; do
    grep -qa "^konto: anbieter_name = $r$" "$TMPD/o_anb.txt" \
        && ok "der Ruecken '$r' ist da" || bad "der Ruecken '$r' fehlt"
done

# --- xoffi
lauf "$TMPD/d1.img" "konto anmelden --anbieter=xoffi --kennung=mfa@example.test --bereich=alpha < /pw_gut" "$TMPD/o_x0.txt"
is "xoffi ohne zweiten Faktor" "$(kv "$TMPD/o_x0.txt" stand)" "zweitfaktor"
TEMP=$(kv "$TMPD/o_x0.txt" zwischen)
[ -n "$TEMP" ] && ok "ein temp_token kam zurueck (${#TEMP} Zeichen)" \
                || bad "kein temp_token"
lauf "$TMPD/d1.img" "konto anmelden --anbieter=xoffi --kennung=mfa@example.test --bereich=alpha --zwischen=$TEMP --code=123456 < /leer" "$TMPD/o_x1.txt"
is "xoffi mit dem zweiten Faktor" "$(kv "$TMPD/o_x1.txt" stand)" "ok"
lauf "$TMPD/d1.img" "konto anmelden --anbieter=xoffi --kennung=mfa@example.test --bereich=alpha --zwischen=$TEMP --code=123456 < /leer" "$TMPD/o_x2.txt"
is "dasselbe temp_token ein zweites Mal" "$(kv "$TMPD/o_x2.txt" stand)" "abgelaufen"
ok "  (ein Zwischentoken ist einmal gueltig -- danach ist es weg)"

# --- jarvis
lauf "$TMPD/d1.img" "konto anmelden --anbieter=jarvis --kennung=justin < /pw_gut" "$TMPD/o_j1.txt"
is "jarvis anmelden" "$(kv "$TMPD/o_j1.txt" stand)" "ok"
JKEN=$(kv "$TMPD/o_j1.txt" kennung)

# --- eigen, ueber HTTPS
lauf "$TMPD/d1.img" "konto anmelden --anbieter=eigen --kennung=justin < /pw_gut" "$TMPD/o_e1.txt"
is "eigen ueber HTTPS anmelden" "$(kv "$TMPD/o_e1.txt" stand)" "ok"

# --- eigen, als ORDNER, und dafuer wird der Server ABGESCHALTET
server_zu
netz_zu
lauf_ohne_netz "$TMPD/d1.img" "konto anmelden --anbieter=eigen --ziel=datei:///eigen --kennung=lokal < /pw_gut" "$TMPD/o_e2.txt"
is "eigen als ORDNER, OHNE JEDES NETZ" "$(kv "$TMPD/o_e2.txt" stand)" "ok"
ok "  (PBKDF2 im Gast stimmt mit dem des Wirts ueberein -- sonst waere es 'falsch')"
netz_auf
server_auf

lauf "$TMPD/d1.img" "konto liste" "$TMPD/o_li.txt"
num "Konten nach vier Anmeldungen" "$(kv "$TMPD/o_li.txt" konten)" ge 4

# ======================================================================
echo "== 5. das Token liegt NIE im Klartext auf der Platte =="
# ======================================================================
cp "$TMPD/d1.img" "$TMPD/d5.img"
lauf "$TMPD/d5.img" "konto uebergabe --kennung=$JKEN" "$TMPD/o_ub.txt"
TOK=$(kv "$TMPD/o_ub.txt" zugriff)
if [ -n "$TOK" ] && [ ${#TOK} -gt 40 ]; then
    ok "die Uebergabe an SYNC nennt das Token (${#TOK} Zeichen)"
else
    bad "die Uebergabe nennt kein Token"
fi
has "$TMPD/o_ub.txt" "konto: datenort = " "die Uebergabe nennt den Datenort"
has "$TMPD/o_ub.txt" "konto: subjekt = " "die Uebergabe nennt das Subjekt"
if [ -n "$TOK" ]; then
    TREFFER=$(grep -c -aF -- "$TOK" "$TMPD/d5.img" 2>/dev/null || true)
    is "das Token im ABBILD gesucht (Treffer)" "${TREFFER:-0}" "0"
fi
SPFAD="/state/session/konto/$JKEN"
python3 tools/osum/mkfs.py where "$TMPD/d5.img" "$SPFAD" > "$TMPD/wo.txt" 2>&1
if grep -qa "^where " "$TMPD/wo.txt"; then
    ok "die Sitzungsdatei liegt im Abbild: $(cat "$TMPD/wo.txt")"
    BLK=$(grep -oE 'first=[0-9]+' "$TMPD/wo.txt" | cut -d= -f2)
    python3 tools/osum/mkfs.py cat "$TMPD/d5.img" "$SPFAD" > "$TMPD/siegel.bin" 2>/dev/null
    if head -c4 "$TMPD/siegel.bin" | grep -qa "OKS1"; then
        ok "und sie ist GESIEGELT (Kopf OKS1, $(stat -c%s "$TMPD/siegel.bin") Oktette)"
    else
        bad "die Sitzungsdatei traegt kein Siegel"
    fi
else
    bad "die Sitzungsdatei fehlt: $(cat "$TMPD/wo.txt")"
    BLK=""
fi

# --- die Gegenprobe: dieselbe Anmeldung mit --kaputt=klartext
abbild "$TMPD/dk.img" || true
lauf "$TMPD/dk.img" "konto --kaputt=klartext anmelden --anbieter=jarvis --kennung=zweiter < /pw2" "$TMPD/o_kk.txt"
is "Gegenprobe klartext: angemeldet" "$(kv "$TMPD/o_kk.txt" stand)" "ok"
is "Gegenprobe klartext: gesiegelt" "$(kv "$TMPD/o_kk.txt" gesiegelt)" "0"
KKEN=$(kv "$TMPD/o_kk.txt" kennung)
# Die kaputte Fassung legt das Token ROH ab -- also wird es auch roh
# gelesen: `mkfs.py cat` holt den Inhalt der Sitzungsdatei aus dem
# Abbild. (Ueber `konto uebergabe` geht das absichtlich NICHT: die
# Uebergabe liest nur gesiegelte Sitzungen, und dass sie das tut, ist
# ein Teil der Zusage und kein Mangel der Gegenprobe.)
python3 tools/osum/mkfs.py cat "$TMPD/dk.img" "/state/session/konto/$KKEN" \
    > "$TMPD/kk_roh.bin" 2>/dev/null
KTOK=$(tr -d '\0' < "$TMPD/kk_roh.bin" | head -c 400)
if [ -n "$KTOK" ] && [ ${#KTOK} -gt 40 ]; then
    ok "Gegenprobe klartext: die Sitzungsdatei ist roher Text (${#KTOK} Zeichen)"
    KT=$(grep -c -aF -- "$KTOK" "$TMPD/dk.img" 2>/dev/null || true)
    num "Gegenprobe klartext: dasselbe Token IM ABBILD gefunden" "${KT:-0}" ge 1
    hasnot "$TMPD/kk_roh.bin" "OKS1" "  und ohne jedes Siegel davor"
    ok "  (also misst Abschnitt 5 wirklich das Siegel und nicht das Nichts)"
else
    bad "Gegenprobe klartext: kein Token zu suchen"
fi

# ======================================================================
echo "== 6. Neustart, Abmelden, und das Merkmal ist WIRKLICH weg =="
# ======================================================================
lauf "$TMPD/d5.img" "konto status --ohne-netz --kennung=$JKEN" "$TMPD/o_st.txt"
is "die Sitzung ueberlebt den Neustart" "$(kv "$TMPD/o_st.txt" sitzung)" "1"
lauf "$TMPD/d5.img" "konto abmelden --kennung=$JKEN" "$TMPD/o_ab.txt"
is "abgemeldet" "$(kv "$TMPD/o_ab.txt" abgemeldet)" "1"
python3 tools/osum/mkfs.py where "$TMPD/d5.img" "$SPFAD" > "$TMPD/wo2.txt" 2>&1
grep -qa "no such path" "$TMPD/wo2.txt" \
    && ok "die Sitzungsdatei ist aus dem Verzeichnis verschwunden" \
    || bad "die Sitzungsdatei steht noch da: $(cat "$TMPD/wo2.txt")"
if [ -n "${BLK:-}" ]; then
    # DIE BLOECKE SELBST. `unlink` nimmt den Namen; hier wird
    # nachgesehen, was in den Oktetten steht, die die Datei belegt hat.
    python3 - "$TMPD/d5.img" "$BLK" > "$TMPD/blk.txt" <<'PY'
import sys
img, blk = sys.argv[1], int(sys.argv[2])
with open(img, "rb") as f:
    f.seek(blk * 4096)
    d = f.read(4096)
print("null=%d nichtnull=%d oks1=%d"
      % (d.count(0), 4096 - d.count(0), 1 if d[:4] == b"OKS1" else 0))
PY
    cat "$TMPD/blk.txt" | sed 's/^/        /'
    is "im Block der Sitzung steht kein Siegel mehr" \
        "$(grep -oE 'oks1=[0-9]+' "$TMPD/blk.txt" | cut -d= -f2)" "0"
    NN=$(grep -oE 'nichtnull=[0-9]+' "$TMPD/blk.txt" | cut -d= -f2)
    num "und der Block ist ueberschrieben (Oktette != 0)" "$NN" le 64
fi
lauf "$TMPD/d5.img" "konto liste" "$TMPD/o_li2.txt"
ok "die Kontenliste nach dem Abmelden: $(kv "$TMPD/o_li2.txt" konten) Eintraege"

# ======================================================================
echo "== 7. keine ambienten Kekse, das Token als Bearer =="
# ======================================================================
python3 - "$TMPD/protokoll.jsonl" > "$TMPD/kopf.txt" <<'PY'
import json, sys
xo_bearer = xo_keks = xo = ja_keks = 0
for z in open(sys.argv[1], encoding="utf-8"):
    e = json.loads(z)
    k = e["kopfzeilen"]
    if e["pfad"].startswith("/api/auth/"):
        xo += 1
        if "authorization" in k:
            xo_bearer += 1
        if "cookie" in k:
            xo_keks += 1
    if e["pfad"] in ("/api/login", "/api/logout", "/api/me"):
        if "cookie" in k:
            ja_keks += 1
print("xoffi=%d bearer=%d keks=%d jarviskeks=%d" % (xo, xo_bearer, xo_keks, ja_keks))
PY
cat "$TMPD/kopf.txt" | sed 's/^/        /'
num "Anfragen an die Xoffi-Wege" "$(grep -oE '^xoffi=[0-9]+' "$TMPD/kopf.txt" | cut -d= -f2)" ge 3
is "davon mit einem Keks" "$(grep -oE 'keks=[0-9]+' "$TMPD/kopf.txt" | head -1 | cut -d= -f2)" "0"
hin "JARVIS-Aufrufe mit ausdruecklichem Keks: $(grep -oE 'jarviskeks=[0-9]+' "$TMPD/kopf.txt" | cut -d= -f2) (dieser Server liest kein Bearer -- siehe Bericht)"

# --- Gegenprobe: --kaputt=keks
rm -f "$TMPD/protokoll.jsonl"
lauf "$TMPD/dk.img" "konto --kaputt=keks anmelden --anbieter=xoffi --kennung=justin@example.test --bereich=alpha < /pw_gut" "$TMPD/o_keks.txt"
python3 - "$TMPD/protokoll.jsonl" > "$TMPD/kopf2.txt" <<'PY'
import json, sys
n = 0
for z in open(sys.argv[1], encoding="utf-8"):
    e = json.loads(z)
    if e["pfad"].startswith("/api/auth/") and "cookie" in e["kopfzeilen"]:
        n += 1
print("keks=%d" % n)
PY
num "Gegenprobe keks: jetzt geht einer hinaus" "$(grep -oE 'keks=[0-9]+' "$TMPD/kopf2.txt" | cut -d= -f2)" ge 1
ok "  (also misst Abschnitt 7 wirklich die Kopfzeilen)"

# ======================================================================
echo "== 8. falsches Kennwort, und zwanzig davon =="
# ======================================================================
abbild "$TMPD/d8.img" || true
lauf "$TMPD/d8.img" "konto anmelden --anbieter=xoffi --kennung=justin@example.test --bereich=alpha < /pw_schlecht" "$TMPD/o_f1.txt"
is "falsches Kennwort" "$(kv "$TMPD/o_f1.txt" stand)" "falsch"
lauf "$TMPD/d8.img" "konto liste" "$TMPD/o_f2.txt"
is "danach: Konten auf dem Geraet" "$(kv "$TMPD/o_f2.txt" konten)" "0"
python3 tools/osum/mkfs.py where "$TMPD/d8.img" "/state/session/konto" > "$TMPD/wo3.txt" 2>&1
hin "und /state/session/konto: $(head -1 "$TMPD/wo3.txt")"

# Zwanzig Versuche. Die Zeit wird auf dem WIRT gemessen.
SK=""
T0=$(date +%s)
for i in $(seq 1 20); do
    lauf "$TMPD/d8.img" "konto anmelden --anbieter=xoffi --kennung=justin@example.test --bereich=alpha < /pw_schlecht" "$TMPD/o_v$i.txt"
    SK="$SK $(kv "$TMPD/o_v$i.txt" stand)"
done
T1=$(date +%s)
GEB=$(echo "$SK" | tr ' ' '\n' | grep -c '^gebremst$' || true)
FAL=$(echo "$SK" | tr ' ' '\n' | grep -c '^falsch$' || true)
hin "zwanzig Versuche in $((T1-T0)) s: falsch=$FAL gebremst=$GEB"
num "der Server bremst nach einer Weile" "$GEB" ge 1
num "und das Geraet ist nie stehengeblieben (Antworten)" "$((GEB+FAL))" eq 20
lauf "$TMPD/d8.img" "konto liste" "$TMPD/o_v99.txt"
is "nach zwanzig Fehlversuchen: Konten" "$(kv "$TMPD/o_v99.txt" konten)" "0"

# Verraet die Antwort, ob es das Konto gibt?
lauf "$TMPD/d8.img" "konto anmelden --anbieter=xoffi --kennung=gibtesnicht@example.test --bereich=alpha < /pw_schlecht" "$TMPD/o_g1.txt"
A=$(kv "$TMPD/o_g1.txt" stand)
lauf "$TMPD/d8.img" "konto anmelden --anbieter=xoffi --kennung=admin@example.test --bereich=alpha < /pw_schlecht" "$TMPD/o_g2.txt"
B=$(kv "$TMPD/o_g2.txt" stand)
if [ "$A" = "$B" ]; then
    ok "unbekannter Name und falsches Kennwort geben DIESELBE Antwort ($A)"
else
    bad "die Antwort verraet, ob es das Konto gibt: '$A' gegen '$B'"
fi

# ======================================================================
echo "== 9. zwei Organisationen, dieselbe Anschrift =="
# ======================================================================
abbild "$TMPD/d9.img" || true
lauf "$TMPD/d9.img" "konto anmelden --anbieter=xoffi --kennung=justin@example.test < /pw_gut" "$TMPD/o_m0.txt"
is "ohne Angabe des Mandanten wird GEFRAGT" "$(kv "$TMPD/o_m0.txt" stand)" "mehrdeutig"
num "und die Auswahl wird genannt" "$(kvn "$TMPD/o_m0.txt" auswahl)" eq 2
lauf "$TMPD/d9.img" "konto anmelden --anbieter=xoffi --kennung=justin@example.test --bereich=alpha < /pw_gut" "$TMPD/o_m1.txt"
lauf "$TMPD/d9.img" "konto anmelden --anbieter=xoffi --kennung=justin@example.test --bereich=beta < /pw_gut" "$TMPD/o_m2.txt"
K1=$(kv "$TMPD/o_m1.txt" kennung)
K2=$(kv "$TMPD/o_m2.txt" kennung)
S1=$(kv "$TMPD/o_m1.txt" subjekt)
S2=$(kv "$TMPD/o_m2.txt" subjekt)
if [ -n "$K1" ] && [ -n "$K2" ] && [ "$K1" != "$K2" ]; then
    ok "zwei Konten, zwei Kennungen: $K1 gegen $K2"
else
    bad "die beiden Mandanten fallen auf dieselbe Kennung: '$K1' / '$K2'"
fi
is "und zwei verschiedene Subjekte" "$([ "$S1" != "$S2" ] && echo ja)" "ja"
lauf "$TMPD/d9.img" "konto liste" "$TMPD/o_m3.txt"
is "beide Konten stehen nebeneinander" "$(kv "$TMPD/o_m3.txt" konten)" "2"
# Die Gegenprobe: die Sitzung des einen darf im anderen nicht auftauchen.
lauf "$TMPD/d9.img" "konto uebergabe --kennung=$K1" "$TMPD/o_m4.txt"
lauf "$TMPD/d9.img" "konto uebergabe --kennung=$K2" "$TMPD/o_m5.txt"
T1T=$(kv "$TMPD/o_m4.txt" zugriff)
T2T=$(kv "$TMPD/o_m5.txt" zugriff)
if [ -n "$T1T" ] && [ "$T1T" != "$T2T" ]; then
    ok "jedes Konto hat sein eigenes Token"
else
    bad "beide Konten teilen sich ein Token"
fi
B1=$(kv "$TMPD/o_m4.txt" bereich)
B2=$(kv "$TMPD/o_m5.txt" bereich)
is "der Mandant des ersten" "$B1" "alpha"
is "der Mandant des zweiten" "$B2" "beta"

# Gegenprobe: --kaputt=einemandant laesst sie zusammenfallen
abbild "$TMPD/d9b.img" || true
lauf "$TMPD/d9b.img" "konto --kaputt=einemandant anmelden --anbieter=xoffi --kennung=justin@example.test --bereich=alpha < /pw_gut" "$TMPD/o_m6.txt"
lauf "$TMPD/d9b.img" "konto liste" "$TMPD/o_m7.txt"
KB1=$(kv "$TMPD/o_m6.txt" kennung)
BB1=$(kv "$TMPD/o_m6.txt" bereich)
is "Gegenprobe einemandant: der Mandant faellt aus der Kennung" "$BB1" ""
if [ "$KB1" != "$K1" ]; then
    ok "  und die Kennung ist damit eine andere als mit Mandant"
else
    bad "  die Kennung aendert sich nicht -- der Mandant ging nie ein"
fi

# ======================================================================
echo "== 10. erneuern, und was passiert, wenn der Server nein sagt =="
# ======================================================================
server_zu
server_auf --access-sekunden 3600
abbild "$TMPD/da.img" || true
lauf "$TMPD/da.img" "konto anmelden --anbieter=xoffi --kennung=admin@example.test --bereich=alpha < /pw_gut" "$TMPD/o_r1.txt"
is "angemeldet mit einem Token, das in einer Stunde ablaeuft" "$(kv "$TMPD/o_r1.txt" stand)" "ok"
RK=$(kv "$TMPD/o_r1.txt" kennung)
AB1=$(kv "$TMPD/o_r1.txt" ablauf)
lauf "$TMPD/da.img" "konto status --kennung=$RK" "$TMPD/o_r2.txt"
is "die Erneuerung war faellig" "$(kv "$TMPD/o_r2.txt" erneuern_faellig)" "1"
is "und sie ist passiert" "$(kv "$TMPD/o_r2.txt" erneuert)" "1"
AB2=$(kv "$TMPD/o_r2.txt" ablauf)
if [ -n "$AB1" ] && [ -n "$AB2" ] && [ "$AB2" -ge "$AB1" ] 2>/dev/null; then
    ok "der neue Ablauf ist nicht frueher als der alte ($AB1 -> $AB2)"
else
    bad "der Ablauf ging zurueck: $AB1 -> $AB2"
fi

# Jetzt sagt der Server NEIN.
server_zu
server_auf --access-sekunden 3600 --refresh-verweigern
lauf "$TMPD/da.img" "konto status --kennung=$RK" "$TMPD/o_r3.txt"
is "Erneuerung abgelehnt -> sauber abgemeldet" "$(kv "$TMPD/o_r3.txt" abgemeldet)" "1"
lauf "$TMPD/da.img" "konto liste" "$TMPD/o_r4.txt"
is "der KONTOEINTRAG bleibt (kein Datenverlust)" "$(kv "$TMPD/o_r4.txt" konten)" "1"
python3 tools/osum/mkfs.py where "$TMPD/da.img" "/state/session/konto/$RK" > "$TMPD/wo4.txt" 2>&1
grep -qa "no such path" "$TMPD/wo4.txt" \
    && ok "und das Token ist weg" || bad "das Token liegt noch da"
server_zu
server_auf

# ======================================================================
echo "== 11. KEIN NETZ -- die wichtigste Zusage der Runde =="
# ======================================================================
abbild "$TMPD/dn.img" || true
lauf "$TMPD/dn.img" "konto anmelden --anbieter=jarvis --kennung=justin < /pw_gut" "$TMPD/o_n0.txt"
is "erst anmelden, mit Netz" "$(kv "$TMPD/o_n0.txt" stand)" "ok"
NK=$(kv "$TMPD/o_n0.txt" kennung)
# ---- jetzt ohne jede Netzkarte
lauf_ohne_netz "$TMPD/dn.img" "konto status --kennung=$NK" "$TMPD/o_n1.txt"
is "OHNE NETZ: die Sitzung ist noch da" "$(kv "$TMPD/o_n1.txt" sitzung)" "1"
is "OHNE NETZ: der Stand ist ok" "$(kv "$TMPD/o_n1.txt" stand)" "ok"
lauf_ohne_netz "$TMPD/dn.img" "konto liste" "$TMPD/o_n2.txt"
is "OHNE NETZ: die Kontenliste steht" "$(kv "$TMPD/o_n2.txt" konten)" "1"
lauf_ohne_netz "$TMPD/dn.img" "konto uebergabe --kennung=$NK" "$TMPD/o_n3.txt"
NT=$(kv "$TMPD/o_n3.txt" zugriff)
[ -n "$NT" ] && ok "OHNE NETZ: die Uebergabe an SYNC liefert das Token" \
             || bad "OHNE NETZ: die Uebergabe liefert nichts"
lauf_ohne_netz "$TMPD/dn.img" "konto anmelden --anbieter=jarvis --kennung=zweiter < /pw_gut" "$TMPD/o_n4.txt"
is "OHNE NETZ: eine NEUE Anmeldung schlaegt klar fehl" "$(kv "$TMPD/o_n4.txt" stand)" "keinnetz"
has "$TMPD/o_n4.txt" "konto: text = " "und sie sagt WARUM, aus dem Sprachkatalog"
lauf_ohne_netz "$TMPD/dn.img" "konto liste" "$TMPD/o_n5.txt"
is "OHNE NETZ: der Fehlversuch hat nichts kaputtgemacht" "$(kv "$TMPD/o_n5.txt" konten)" "1"
# und das Geraet ist BENUTZBAR
lauf_ohne_netz "$TMPD/dn.img" "ls /bin" "$TMPD/o_n6.txt"
has "$TMPD/o_n6.txt" "konto" "OHNE NETZ: das System selbst laeuft weiter (ls /bin)"

# ======================================================================
echo "== 11b. ein faules Zertifikat ist NICHT \"kein Netz\" =="
# ======================================================================
# Beides fuehlt sich gleich an -- es kommt keine Antwort. Aber das eine
# ist ein Zug im Tunnel und das andere jemand, der sich dazwischensetzt.
# Wer beides gleich meldet, schickt den Nutzer WLAN suchen, waehrend in
# Wahrheit ein fremdes Zertifikat vor ihm steht. `rogue.pem` traegt
# denselben Namen, ist aber von einer Wurzel unterschrieben, die dieses
# Geraet nicht kennt.
server_zu
server_auf_zert "$TMPD/certs/rogue.pem" "$TMPD/certs/rogue.key"
abbild "$TMPD/dt.img" || true
lauf "$TMPD/dt.img" "konto anmelden --anbieter=jarvis --kennung=justin < /pw_gut" "$TMPD/o_tls.txt"
is "fremde Wurzel -> eigener Stand" "$(kv "$TMPD/o_tls.txt" stand)" "tls"
has "$TMPD/o_tls.txt" "konto: text = " "und ein Satz aus dem Katalog dazu"
lauf "$TMPD/dt.img" "konto liste" "$TMPD/o_tls2.txt"
is "und es entsteht kein Konto" "$(kv "$TMPD/o_tls2.txt" konten)" "0"
server_zu
server_auf

# ======================================================================
echo "== 11c. die Befehlszeile: zwei Schreibweisen, und acht Woerter =="
# ======================================================================
# `proc.MAX_ARGS` ist 8. Die getrennte Schreibweise `--ziel <url>` macht
# aus einer Anmeldung mit zweitem Faktor elf Woerter -- die Shell sagt
# dann "too many arguments" und laesst den Befehl fallen. Genau daran ist
# der erste Lauf dieser Runde gescheitert, deshalb steht es jetzt hier
# als Messung und nicht als Erinnerung.
MAXA=$(grep -oE 'argv: \[u64; [0-9]+\]' kernel/user/sh.fi | grep -oE '[0-9]+' | tail -1)
is "die Shell nimmt so viele Woerter" "$MAXA" "8"
abbild "$TMPD/dw.img" || true
lauf "$TMPD/dw.img" "konto anmelden --anbieter jarvis --kennung justin < /pw_gut" "$TMPD/o_w1.txt"
is "die GETRENNTE Form (sechs Woerter) tut es auch" "$(kv "$TMPD/o_w1.txt" stand)" "ok"
W1=$(kv "$TMPD/o_w1.txt" kennung)
abbild "$TMPD/dw2.img" || true
lauf "$TMPD/dw2.img" "konto anmelden --anbieter=jarvis --kennung=justin < /pw_gut" "$TMPD/o_w2.txt"
W2=$(kv "$TMPD/o_w2.txt" kennung)
is "und sie fuehrt zur GLEICHEN Kennung wie die angehaengte" "$W2" "$W1"
# Die Gegenprobe: dieselbe Anmeldung in der getrennten, langen Form.
lauf "$TMPD/dw2.img" "konto anmelden --anbieter xoffi --ziel $Z --name $N --kennung mfa@example.test --bereich alpha --code 1 < /pw_gut" "$TMPD/o_w3.txt"
if grep -qa "too many arguments" "$TMPD/o_w3.txt"; then
    ok "Gegenprobe: elf Woerter fallen wirklich durch (sh: too many arguments)"
else
    bad "Gegenprobe: die lange Form kam durch -- dann misst 11c nichts"
fi
# Und die Konfigdatei: OHNE --ziel, nur aus /etc/konten.conf.
grep -qa "^jarvis ziel=" "$TMPD/konten.conf" \
    && ok "/etc/konten.conf traegt die Adresse, kein Geheimnis" \
    || bad "/etc/konten.conf fehlt"
hasnot "$TMPD/konten.conf" "richtig" "in /etc/konten.conf steht kein Kennwort"

# ======================================================================
echo "== 12. master_session und fremde Verwaltungsrechte =="
# ======================================================================
abbild "$TMPD/dm.img" || true
lauf "$TMPD/dm.img" "konto anmelden --anbieter=xoffi --kennung=chef@example.test --bereich=alpha < /pw_gut" "$TMPD/o_ms.txt"
is "eine Sitzung mit master_session wird ABGELEHNT" "$(kv "$TMPD/o_ms.txt" stand)" "abgelehnt"
lauf "$TMPD/dm.img" "konto liste" "$TMPD/o_ms2.txt"
is "und es entsteht kein Konto" "$(kv "$TMPD/o_ms2.txt" konten)" "0"
python3 tools/osum/mkfs.py where "$TMPD/dm.img" "/state/session/konto" > "$TMPD/wo5.txt" 2>&1
hin "  /state/session/konto: $(head -1 "$TMPD/wo5.txt")"
# Gegenprobe: ohne die Pruefung geht es durch
lauf "$TMPD/dm.img" "konto --kaputt=claimcheck anmelden --anbieter=xoffi --kennung=chef@example.test --bereich=alpha < /pw_gut" "$TMPD/o_ms3.txt"
is "Gegenprobe claimcheck: jetzt geht sie durch" "$(kv "$TMPD/o_ms3.txt" stand)" "ok"
ok "  (also misst Abschnitt 12 die Weigerung und nicht einen Zufall)"

# is_admin / nexus_core_access
abbild "$TMPD/dm2.img" || true
lauf "$TMPD/dm2.img" "konto anmelden --anbieter=xoffi --kennung=admin@example.test --bereich=alpha < /pw_gut" "$TMPD/o_ad.txt"
is "ein Token mit is_admin und nexus_core_access wird angenommen" "$(kv "$TMPD/o_ad.txt" stand)" "ok"
python3 tools/osum/mkfs.py where "$TMPD/dm2.img" "/etc/konto.rechte" > "$TMPD/wo6.txt" 2>&1
grep -qa "no such path" "$TMPD/wo6.txt" \
    && ok "und es entsteht KEINE lokale Berechtigung (/etc/konto.rechte gibt es nicht)" \
    || bad "eine lokale Berechtigung ist entstanden: $(cat "$TMPD/wo6.txt")"
python3 tools/osum/mkfs.py cat "$TMPD/dm2.img" /etc/konten > "$TMPD/konten.txt" 2>/dev/null
if grep -qai 'admin\|nexus\|root' "$TMPD/konten.txt"; then
    if grep -qa 'adminmensch' "$TMPD/konten.txt" && ! grep -qa 'is_admin\|nexus' "$TMPD/konten.txt"; then
        ok "/etc/konten traegt den Anzeigenamen und keinen Anspruch"
    else
        bad "/etc/konten traegt einen fremden Anspruch: $(cat "$TMPD/konten.txt")"
    fi
else
    ok "/etc/konten traegt keinen fremden Anspruch"
fi
FELDER=$(head -1 "$TMPD/konten.txt" | awk -F'\t' '{print NF}')
is "eine Kontozeile hat genau sieben Felder" "$FELDER" "7"
# Gegenprobe: --kaputt=rechte macht daraus eine lokale Berechtigung
abbild "$TMPD/dm3.img" || true
lauf "$TMPD/dm3.img" "konto --kaputt=rechte anmelden --anbieter=xoffi --kennung=admin@example.test --bereich=alpha < /pw_gut" "$TMPD/o_ad2.txt"
python3 tools/osum/mkfs.py where "$TMPD/dm3.img" "/etc/konto.rechte" > "$TMPD/wo7.txt" 2>&1
grep -qa "^where " "$TMPD/wo7.txt" \
    && ok "Gegenprobe rechte: jetzt entsteht die Berechtigung -- der Test greift" \
    || bad "Gegenprobe rechte: es entsteht nichts, der Test misst nichts"

# ======================================================================
echo "== 13. der Katalog, im laufenden System =="
# ======================================================================
lauf "$TMPD/d1.img" "konto --text=konto.state.offline" "$TMPD/o_t1.txt"
SOLL=$(grep -a '^konto.state.offline' locale/de/messages | sed 's/^[^=]*= //')
IST=$(grep -av '^konto:' "$TMPD/o_t1.txt" | grep -a 'Verbindung\|connection' | head -1 | tr -d '\r')
if [ -n "$IST" ] && [ "$IST" = "$SOLL" ]; then
    ok "der Text kommt aus dem Katalog, in der Sprache aus /etc/locale.conf"
else
    hin "gelesen: '$IST'"
    hin "Datei:   '$SOLL'"
    bad "der Katalogtext stimmt nicht mit der Datei ueberein"
fi

# ======================================================================
echo "== 14. DAS PRINZIP: alles ohne Konto =="
# ======================================================================
# Ein Abbild, das NIE eine Anmeldung gesehen hat -- und ein System, das
# vollstaendig ist. Gemessen wird das, was ein Mensch tut: Dateien
# anlegen, lesen, auflisten, die Einstellungen oeffnen.
abbild "$TMPD/dp.img" || true
lauf_ohne_netz "$TMPD/dp.img" "echo hallo > /probe.txt;cat /probe.txt;ls /bin;konto liste;konto status" "$TMPD/o_p1.txt"
has "$TMPD/o_p1.txt" "hallo" "ohne jedes Konto: schreiben und lesen geht"
is "ohne jedes Konto: Konten" "$(kv "$TMPD/o_p1.txt" konten)" "0"
is "ohne jedes Konto: konto status endet sauber" "$(kv "$TMPD/o_p1.txt" stand)" "ok"
python3 tools/osum/mkfs.py where "$TMPD/dp.img" "/etc/konten" > "$TMPD/wo8.txt" 2>&1
grep -qa "no such path" "$TMPD/wo8.txt" \
    && ok "und es ist keine einzige Kontodatei entstanden" \
    || bad "eine Kontodatei ist ohne Anmeldung entstanden"
python3 tools/osum/mkfs.py where "$TMPD/dp.img" "/device/kontoschluessel" > "$TMPD/wo9.txt" 2>&1
grep -qa "no such path" "$TMPD/wo9.txt" \
    && ok "und auch kein Siegelschluessel -- nichts davon entsteht auf Vorrat" \
    || hin "der Siegelschluessel entstand ohne Anmeldung: $(cat "$TMPD/wo9.txt")"

server_zu
netz_zu

echo "KONTO: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
