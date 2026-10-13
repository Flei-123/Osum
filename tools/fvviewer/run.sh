#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvviewer/run.sh -- FreeViewer viewer libs (M1 part): host gate.
#   1. lib/net/ws.fi against Python `websockets` (normal + 1-octet reads)
#   2. counter-check: a wrong Sec-WebSocket-Accept must be refused
#   3. compile-check of lib/fv/{crypto,proto,session}.fi (real crypto)
#   4. vt.fi (lib/fv/proto + session) against the Rust contract file
#      tests/orientos-vectors.json, byte for byte (tools/fvviewer/vectors.py) + counter-check
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
printf 'import fv.proto\nimport fv.session\nimport fv.crypto\nimport net.ws\nfn main() -> i32 {\n    var s: session.Sess = session.sess_new()\n    return 0\n}\n' > "$D/c.fi"
vendor/firn/bin/firnc "$D/c.fi" -o "$D/c" > "$D/c.log" 2>&1 && ok "lib/fv/{proto,session,crypto} compile" || { bad "lib/fv compile"; head -5 "$D/c.log"; }
RUSTVEC=${FVV_RUST_VECTORS:-/root/projects/freeviewer/tests/orientos-vectors.json}
if [ -f "$RUSTVEC" ]; then
    vendor/firn/bin/firnc tools/fvviewer/vt.fi -o "$D/vt" > "$D/vt.log" 2>&1 && ok "vt builds" || { bad "vt build"; head -5 "$D/vt.log"; }
    python3 -I tools/fvviewer/vectors.py "$D/vt" "$RUSTVEC" > "$D/vec.txt" 2>&1
    if [ $? -eq 0 ]; then ok "proto+session equal the Rust vectors ($(tail -1 "$D/vec.txt"))"; else bad "vectors differ"; head -12 "$D/vec.txt"; fi
    # counter-check: a flipped byte in the contract file must make the comparison fail
    python3 -I - "$RUSTVEC" "$D/bad.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
c = d["argon2"]["cases"][0]
c["proof_frame_V_to_H"] = c["proof_frame_V_to_H"][:-2] + ("00" if c["proof_frame_V_to_H"][-2:] != "00" else "01")
d["proto"][2]["hex"] = d["proto"][2]["hex"][:-2] + "ee"
json.dump(d, open(sys.argv[2], "w"))
PY
    python3 -I tools/fvviewer/vectors.py "$D/vt" "$D/bad.json" > "$D/vec2.txt" 2>&1 && bad "counter-check: a wrong vector was accepted" || ok "counter-check: a flipped byte is caught"
else
    echo "  SKIP  Rust vectors not found ($RUSTVEC)"
fi
echo "FVVIEWER: $pass ok, $fail fail"
[ "$fail" = 0 ]
