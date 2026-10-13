#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvviewer/run.sh -- FreeViewer viewer libs (M1 part): host gate.
#   1. lib/net/ws.fi against Python `websockets` (normal + 1-octet reads)
#   2. counter-check: a wrong Sec-WebSocket-Accept must be refused
#   3. compile-check of lib/fv/{cryptoif,proto,session}.fi (MOCK crypto)
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
vendor/firn/bin/firnc tools/fvviewer/wstest.fi -o "$D/wstest" > "$D/b.log" 2>&1 && ok "wstest builds" || { bad "wstest build"; head -5 "$D/b.log"; }
timeout 100 python3 tools/fvviewer/wstest.py "$D/wstest" | grep -q "WSTEST PASS" && ok "ws.fi vs websockets (7/16/64-bit, fragments, ping, close)" || bad "ws.fi vs websockets"
timeout 150 python3 tools/fvviewer/wstest.py "$D/wstest" slow | grep -q "WSTEST PASS" && ok "ws.fi, one octet per read" || bad "ws.fi slow"
# counter-check: server answers 101 with a WRONG accept value
python3 - "$D/wstest" <<'PY' && ok "wrong Accept is refused" || bad "wrong Accept was accepted"
import socket, subprocess, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(1)
p = subprocess.Popen([sys.argv[1], str(s.getsockname()[1])], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
c, _ = s.accept(); c.recv(4096)
c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: AAAAAAAAAAAAAAAAAAAAAAAAAAA=\r\n\r\n")
out = p.communicate(timeout=20)[0].decode()
sys.exit(0 if "bad upgrade answer" in out and "UPGRADED" not in out else 1)
PY
printf 'import fv.proto\nimport fv.session\nimport fv.cryptoif\nimport net.ws\nfn main() -> i32 {\n    var s: session.Sess = session.sess_new()\n    return 0\n}\n' > "$D/c.fi"
vendor/firn/bin/firnc "$D/c.fi" -o "$D/c" > "$D/c.log" 2>&1 && ok "lib/fv/{proto,session,cryptoif} compile" || { bad "lib/fv compile"; head -5 "$D/c.log"; }
echo "FVVIEWER: $pass ok, $fail fail"
[ "$fail" = 0 ]
