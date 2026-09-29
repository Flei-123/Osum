#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/social/chat.sh -- THE FLEITEC PROVIDER'S CHAT, LOGIN AND INVITES,
# against a real FirnChat relay and a real fleikontakte, on the host.
#
#   bash tools/social/chat.sh
#   FIRNCHAT_BIN=/path/to/firnchat/bin   (default: the FirnChat repo's bin/)
#
# kernel/app/socfleitec.fi is a program with Linux's system call numbers,
# so the very same source runs on the host as a plain Linux program --
# one account per configuration file (-c), exactly as /etc/social/providers
# gives it on OrientOS. Two OrientOS devices (justin's, anna's) and one
# FirnChat command line client (bob's, stage-1 wire) talk to each other:
#
#   1. login: an unpaired device gets a pairing code (exit 4); the person
#      types it into her profile (POST /api/kontakte/koppeln); asked again,
#      the device gets its own access token -- written into its file;
#      the relay's key is pinned
#   2. chat, end to end: justin -> anna (sealed per device), anna -> justin,
#      what justin wrote shows as an own-device copy ('out') on his
#      second device; nothing twice (the relay's cursor, the replay window)
#   3. interoperability: bob's FirnChat client -> justin's OrientOS device
#      and back (the stage-1 construction unchanged)
#   4. strangers are dropped; a relay with another key is refused (pin)
#   5. invites: invite with a target, the answer brings it; join: the
#      answer brings the target of the one asked; a joinable activity
#   6. login with a token made by hand
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
FCB=${FIRNCHAT_BIN:-/root/jarvis/projects/u_DiS4in7esMF1/firnchat/bin}

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
fin() { echo "SOCIAL-CHAT: $pass passed, $fail failed"; exit $(( fail > 0 )); }

T=$(mktemp -d)
PIDS=""
trap 'for p in $PIDS; do kill $p 2>/dev/null; done; rm -rf "$T"' EXIT

echo "== 0. build"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if vendor/firn/bin/firnc -o "$T/sf" kernel/app/socfleitec.fi > "$T/b.txt" 2>&1; then
    ok "socfleitec builds as a host program"
else
    bad "socfleitec does not build"; head -20 "$T/b.txt" | sed 's/^/        /'; fin
fi
for b in firnchat fleikontakte; do
    [ -x "$FCB/$b" ] || { bad "no $FCB/$b (FirnChat: bash build.sh)"; fin; }
done

python3 -c "import secrets; print(secrets.token_hex(32))" > "$T/jarvis.secret"
cat > "$T/anbieter.conf" <<EOF
[jarvis]
typ = jwt
cookie = fleitec_session
geheimnis = $T/jarvis.secret
auto-konto = ja
EOF
mkdir -p "$T/web"
"$FCB/fleikontakte" --port 0 --daten "$T/daten" --anbieter-conf "$T/anbieter.conf" \
    --web-dir "$T/web" > "$T/k.out" 2> "$T/k.err" &
PIDS="$PIDS $!"
KP=""; for _ in $(seq 1 50); do KP=$(sed -n 's/^FLEIKONTAKTE listening \([0-9]*\)$/\1/p' "$T/k.out"); [ -n "$KP" ] && break; sleep 0.1; done
mkdir -p "$T/relay"
( cd "$T" && exec "$FCB/firnchat" serve 0 "$T/relay" 0 --kontakte-port "$KP" ) > "$T/r.out" 2>&1 &
PIDS="$PIDS $!"
RP=""; for _ in $(seq 1 50); do RP=$(sed -n 's/^FIRNCHAT listening \([0-9]*\).*/\1/p' "$T/r.out" | head -1); [ -n "$RP" ] && break; sleep 0.1; done
[ -n "$KP" ] && [ -n "$RP" ] && ok "fleikontakte ($KP) and the relay ($RP) run" || { bad "servers did not start"; cat "$T/r.out"; fin; }

SECRET=$(cat "$T/jarvis.secret")
cat > "$T/api.py" <<'PY'
import base64, hashlib, hmac, json, sys, time, urllib.request
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()
def mint(secret, uid, name):
    now = int(time.time())
    h = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(',', ':')).encode())
    p = b64(json.dumps({"uid": uid, "name": name, "iat": now, "exp": now + 7200}, separators=(',', ':')).encode())
    s = b64(hmac.new(secret.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest())
    return f"{h}.{p}.{s}"
port, secret, who, path = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
body = json.loads(sys.argv[5]) if len(sys.argv) > 5 else None
tok = mint(secret, "u_" + who.upper(), who.capitalize())
req = urllib.request.Request(f"http://127.0.0.1:{port}{path}",
    data=None if body is None else json.dumps(body).encode(),
    method="GET" if body is None else "POST",
    headers={"Cookie": "fleitec_session=" + tok, "Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        print(r.read().decode())
except urllib.error.HTTPError as e:
    print(json.dumps({"status": e.code}))
PY
api() { python3 "$T/api.py" "$KP" "$SECRET" "$@"; }
jf() { python3 -c "import json,sys; j=json.load(sys.stdin); print($1)"; }
for u in justin anna bob carla; do api $u /api/kontakte/profil > /dev/null; done
for u in anna bob; do
    api justin /api/kontakte/anfragen "{\"konto\":\"u_${u^^}\"}" > /dev/null
    api $u /api/kontakte/annehmen '{"konto":"u_JUSTIN"}' > /dev/null
done

conf() { printf 'url=http://127.0.0.1:%s\nrelay=127.0.0.1:%s\n' "$KP" "$RP" > "$T/$1.conf"; }
sf() { local c=$1; shift; "$T/sf" v1 "-c$T/$c.conf" "$@"; }
pair() { # pair <conf> <person>
    local out code
    out=$(sf "$1" login); local rc=$?
    code=$(printf '%s\n' "$out" | awk -F'\t' '$1=="pair"{gsub(/ /,"",$2); print $2}')
    [ "$rc" = 4 ] && [ ${#code} = 8 ] || { echo "no code (rc=$rc): $out"; return 1; }
    api "$2" /api/kontakte/koppeln "{\"code\":\"$code\",\"label\":\"OrientOS\"}" > /dev/null
    sf "$1" login > "$T/$1.login"; return $?
}

echo "== 1. login"
conf J
out=$(sf J login); rc=$?
[ "$rc" = 4 ] && printf '%s' "$out" | grep -q "^pair	[0-9]\{4\} [0-9]\{4\}	" \
    && ok "an unpaired device gets an eight digit pairing code (exit 4)" || bad "login unpaired: rc=$rc $out"
[ -s "$T/J.conf.key" ] && [ "$(stat -c %a "$T/J.conf.key")" = 600 ] \
    && ok "the device key was made, mode 0600" || bad "no device key file"
[ -s "$T/J.conf.pin" ] && ok "the relay's key is pinned on first use" || bad "no pin"
if pair J justin; then
    grep -q "^account	u_JUSTIN	" "$T/J.login" && ok "typed into the profile, the device gets its own token: account u_JUSTIN" \
        || bad "login after pairing: $(cat "$T/J.login")"
else bad "pairing justin: $(cat "$T/J.login" 2>/dev/null)"; fi
grep -q '^token=fkz1\.u_JUSTIN\.' "$T/J.conf" && ok "the token is in justin's configuration" || bad "no token written"
"$T/sf" v1 -c "$T/J.conf" hello | grep -q "^account	u_JUSTIN" && ok "hello names the account (from the token, no network; -c <conf> as two words too)" || bad "hello without account"
conf A; pair A anna && grep -q "^account	u_ANNA" "$T/A.login" && ok "anna's OrientOS device is paired too" || bad "anna pairing"
conf J2; pair J2 justin && ok "justin's second OrientOS device is paired" || bad "J2 pairing"
api justin /api/kontakte/profil | jf "sum(1 for g in j['profil']['geraete'] if g.get('art')=='fc')" > "$T/n"
[ "$(cat "$T/n")" = 2 ] && ok "justin's profile lists both devices" || bad "justin's devices: $(cat "$T/n")"
sf J contacts > "$T/c.txt"
grep -q "^c	u_ANNA	friend	" "$T/c.txt" && ok "contacts with the device's own token" || bad "contacts: $(head -3 "$T/c.txt")"

echo "== 2. chat, end to end"
sf J send u_ANNA "Hallo Anna, von OrientOS" > "$T/s1.txt"; rc=$?
[ "$rc" = 0 ] && grep -q "^sent	1	" "$T/s1.txt" && ok "justin -> anna: sealed for her one device" || bad "send: rc=$rc $(cat "$T/s1.txt")"
sf A inbox > "$T/a1.txt"
grep -q "^m	u_JUSTIN	[0-9]*	in	Hallo Anna, von OrientOS$" "$T/a1.txt" && ok "anna's inbox: the text, from u_JUSTIN, in" || bad "anna inbox: $(cat "$T/a1.txt")"
sf A inbox > "$T/a2.txt"
grep -q "^m	" "$T/a2.txt" && bad "the second inbox brought it again" || ok "asked again: nothing twice"
sf J2 inbox > "$T/j2.txt"
grep -q "^m	u_ANNA	[0-9]*	out	Hallo Anna, von OrientOS$" "$T/j2.txt" && ok "justin's second device has the own-device copy (out, in anna's conversation)" \
    || bad "J2 inbox: $(cat "$T/j2.txt")"
sf A send u_JUSTIN "Hi Justin! Läuft?" > /dev/null
sf J inbox > "$T/j1.txt"
grep -q "^m	u_ANNA	[0-9]*	in	Hi Justin! Läuft?$" "$T/j1.txt" && ok "anna -> justin (UTF-8 intact)" || bad "justin inbox: $(cat "$T/j1.txt")"
sf J2 inbox > "$T/j2b.txt"
grep -q "^m	u_ANNA	[0-9]*	in	Hi Justin! Läuft?$" "$T/j2b.txt" && ok "... on both of justin's devices" || bad "J2 got no copy of anna's message"
s1=$(cat "$T/J.conf.seq"); sf J send u_ANNA "zwei" > /dev/null; s2=$(cat "$T/J.conf.seq")
[ "$s2" -gt "$s1" ] && ok "the sequence number moves on (kept in <conf>.seq: $s1 -> $s2)" || bad "seq did not move"

echo "== 3. with FirnChat's own client"
( cd "$T" && "$FCB/firnchat" id "$T/bob.id" ) > "$T/bid.txt" 2>&1
BOBPUB=$(head -c 128 "$T/bob.id" | tail -c 64)
api bob /api/kontakte/geraet "{\"art\":\"fc\",\"wert\":\"$BOBPUB\",\"label\":\"Bob-PC\"}" > /dev/null
JPUB=$(head -c 128 "$T/J.conf.key" | tail -c 64)
( cd "$T" && "$FCB/firnchat" send "$JPUB" "Servus vom FirnChat-Client" "$RP" "$T/bob.id" ) > "$T/bs.txt" 2>&1
sf J inbox > "$T/j3.txt"
grep -q "^m	u_BOB	[0-9]*	in	Servus vom FirnChat-Client$" "$T/j3.txt" && ok "bob's FirnChat client -> justin's OrientOS device" \
    || bad "justin from bob: $(cat "$T/j3.txt") / $(cat "$T/bs.txt")"
sf J send u_BOB "Antwort aus OrientOS" > /dev/null
( cd "$T" && "$FCB/firnchat" recv "$RP" "$T/bob.id" ) > "$T/br.txt" 2>&1
grep -q "Antwort aus OrientOS" "$T/br.txt" && ok "justin's OrientOS device -> bob's FirnChat client" || bad "bob recv: $(cat "$T/br.txt")"

echo "== 4. strangers and the pin"
( cd "$T" && "$FCB/firnchat" id "$T/carla.id" ) > /dev/null 2>&1
CPUB=$(head -c 128 "$T/carla.id" | tail -c 64)
api carla /api/kontakte/geraet "{\"art\":\"fc\",\"wert\":\"$CPUB\",\"label\":\"C\"}" > /dev/null
( cd "$T" && "$FCB/firnchat" send "$JPUB" "Werbung" "$RP" "$T/carla.id" ) > /dev/null 2>&1
sf J inbox > "$T/j4.txt"
grep -q "Werbung" "$T/j4.txt" && bad "a stranger's message came through" || ok "a stranger (not in the book) is dropped"
grep -q "^ok	0	1$" "$T/j4.txt" && ok "... and counted as dropped" || note "inbox said: $(tail -1 "$T/j4.txt")"
cp "$T/J.conf.pin" "$T/pin.keep"; printf '%064d\n' 0 > "$T/J.conf.pin"
sf J inbox > "$T/j5.txt"; rc=$?
[ "$rc" = 3 ] && grep -q "pinned" "$T/j5.txt" && ok "a relay with another key than the pinned one is refused (exit 3)" || bad "pin: rc=$rc $(cat "$T/j5.txt")"
cp "$T/pin.keep" "$T/J.conf.pin"

echo "== 5. invites and a joinable activity"
sf J invite u_ANNA invite "mc://10.0.0.5:25565" Minecraft > "$T/i1.txt"; rc=$?
INV=$(awk -F'\t' '$1=="i"{print $2}' "$T/i1.txt")
[ "$rc" = 0 ] && [ ${#INV} = 16 ] && ok "justin invites anna (an id of 16 hex)" || bad "invite: rc=$rc $(cat "$T/i1.txt")"
sf A invites > "$T/i2.txt"
grep -q "^i	$INV	u_JUSTIN	in	invite	open	[0-9]*		Minecraft$" "$T/i2.txt" \
    && ok "anna sees it: from justin, invite, open, no target yet" || bad "anna invites: $(cat "$T/i2.txt")"
sf A answer "$INV" yes > "$T/i3.txt"
grep -q "^i	$INV	u_JUSTIN	in	invite	accepted	[0-9]*	mc://10.0.0.5:25565	Minecraft$" "$T/i3.txt" \
    && ok "anna says yes and gets the target" || bad "answer: $(cat "$T/i3.txt")"
sf J invites | grep -q "^i	$INV	u_ANNA	out	invite	accepted	" && ok "justin sees: accepted" || bad "justin invites"
sf A invite u_JUSTIN join - Minecraft > "$T/i4.txt"
INV2=$(awk -F'\t' '$1=="i"{print $2}' "$T/i4.txt")
sf J answer "$INV2" yes "mc://10.0.0.5:25565" > /dev/null
sf A invites | grep -q "^i	$INV2	u_JUSTIN	out	join	accepted	[0-9]*	mc://10.0.0.5:25565	" \
    && ok "anna asked to join; justin's yes brings her his target" || bad "join flow"
sf J activity -j Minecraft > /dev/null
sf A contacts | awk -F'\t' '$2=="u_JUSTIN"{print $8, $11}' > "$T/act.txt"
[ "$(cat "$T/act.txt")" = "Minecraft 1" ] && ok "a joinable activity: anna's book says Minecraft, joinable 1" || bad "joinable: '$(cat "$T/act.txt")'"
sf J activity Minecraft > /dev/null
sf A contacts | awk -F'\t' '$2=="u_JUSTIN"{print $11}' | grep -qx 0 && ok "without -j: not joinable" || bad "joinable stays"
sf J invite u_CARLA invite - X > /dev/null; rc=$?
[ "$rc" = 3 ] && ok "a stranger cannot be invited (denied)" || bad "invite stranger: rc=$rc"

echo "== 6. a token made by hand"
TOK=$(api justin /api/kontakte/zugang '{}' | jf "j['token']")
conf H
sf H login token "$TOK" | grep -q "^account	u_JUSTIN$" && ok "login token <fkz1...>: taken, account named" || bad "login token"
sf H contacts | grep -q "^c	u_ANNA	" && ok "... and it works" || bad "hand-made token does not work"
sf H login token "nonsense" > /dev/null; rc=$?
[ "$rc" = 1 ] && ok "a malformed token is refused" || bad "malformed token rc=$rc"
fin
