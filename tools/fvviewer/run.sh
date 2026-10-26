#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
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

# ---- 4b: lib/fv/input.fi (key + pointer mapping) against an independent model of the wire format
vendor/firn/bin/firnc tools/fvviewer/it.fi -o "$D/it" > "$D/it.log" 2>&1 && ok "it (input test driver) builds" || { bad "it build"; head -5 "$D/it.log"; }
if [ -x "$D/it" ]; then
    python3 -I tools/fvviewer/inputtest.py "$D/it" > "$D/in.txt" 2>&1 && ok "input.fi: $(tail -1 "$D/in.txt")" || { bad "input.fi mapping"; head -8 "$D/in.txt"; }
    printf '#!/bin/sh\necho x\n' > "$D/fakeit"; chmod +x "$D/fakeit"
    python3 -I tools/fvviewer/inputtest.py "$D/fakeit" > /dev/null 2>&1 && bad "counter-check: a wrong mapping was accepted" || ok "counter-check: a wrong mapping is caught"
fi

# ---- 5+6: the app (kernel/user/fvviewer.fi) against the synthetic Rust test host
# Needs the Rust test-host binary (FV_BIN, default /root/abbilder/fv-testhost/freeviewer; build:
#   CARGO_TARGET_DIR=<dir> /root/jarvis/bin/heavy cargo build   in /root/projects/freeviewer) and node.
FVBIN=${FV_BIN:-/root/abbilder/fv-testhost/freeviewer}
FVREPO=${FVV_RUST_REPO:-/root/projects/freeviewer}
THPID=""
stop_th() { [ -n "$THPID" ] && kill "$THPID" 2>/dev/null; wait "$THPID" 2>/dev/null; THPID=""; }
trap 'stop_th; rm -rf "$D"' EXIT
start_th() { # sets PORT ID
    PORT=$((17200 + RANDOM % 600))
    bash "$FVREPO/tools/orientos-testhost.sh" --port "$PORT" --bin "$FVBIN" > "$D/th.log" 2>&1 &
    THPID=$!
    ID=""
    for _ in $(seq 1 100); do
        ID=$(awk '/^ID /{print $2; exit}' "$D/th.log" 2>/dev/null)
        [ -n "$ID" ] && break
        sleep 0.2
    done
    [ -n "$ID" ]
}
echo "  == app: kernel/user/fvviewer.fi =="
if vendor/firn/bin/firnc kernel/user/fvviewer.fi -o "$D/fvv" > "$D/fvv.log" 2>&1; then
    ok "fvviewer.fi builds (Linux host binary)"
else
    bad "fvviewer.fi build"; head -8 "$D/fvv.log"
fi
if [ -x "$FVBIN" ] && [ -x "$D/fvv" ] && command -v node >/dev/null; then
    if start_th; then
        PWD_TH=testpass123
        timeout 90 "$D/fvv" -t 127.0.0.1 "$PORT" "$ID" "$PWD_TH" > "$D/h1.txt" 2>&1
        grep -q "^FVV: .* 0 FAIL" "$D/h1.txt" && ok "host: password mode, all checks ($(grep -c '^  ok' "$D/h1.txt") ok)" \
            || { bad "host: password mode"; tail -12 "$D/h1.txt"; }
        sleep 1
        grep -q "TESTHOST input: MouseButton button=0 down=true" "$D/th.log" && grep -q "TESTHOST input: Clipboard len=8 text=fvv-clip" "$D/th.log" \
            && ok "host: the test host logged the click and the clipboard text" || bad "host: input not logged by the test host"
        for want in "Key code=97 named=false down=true" "Key code=2 named=true down=true" "KeyVk vk=17 ext=false down=true" "KeyVk vk=67 ext=false down=true" "Special code=1" "Key code=34 named=true down=true" "KeyVk vk=37 ext=true down=true" "Special code=4"; do
            grep -q "TESTHOST input: $want" "$D/th.log" && ok "host: key message logged: $want" || bad "host: key message missing in the test host log: $want"
        done
        timeout 90 "$D/fvv" -t 127.0.0.1 "$PORT" "$ID" wrong-password > "$D/h2.txt" 2>&1 && bad "host: wrong password was accepted" \
            || { grep -q "FAIL  handshake" "$D/h2.txt" && ok "host: wrong password is refused (counter-check)" || bad "host: wrong password: no clean refusal"; }
        sleep 1
        timeout 130 "$D/fvv" -t 127.0.0.1 "$PORT" "$ID" -a > "$D/h3.txt" 2>&1
        grep -q "^FVV: .* 0 FAIL" "$D/h3.txt" && ok "host: ask mode, all checks" || { bad "host: ask mode"; tail -12 "$D/h3.txt"; }
        stop_th
    else
        bad "test host did not start"; head -5 "$D/th.log"
    fi
else
    echo "  SKIP  app run against the Rust test host: need FV_BIN ($FVBIN), node, a built app. Nothing is claimed."
fi
if [ -x "$FVBIN" ] && command -v qemu-system-x86_64 >/dev/null && command -v node >/dev/null && [ "${FVV_QEMU:-1}" = 1 ]; then
    echo "  == app inside ${MARKE_PRODUKT} (QEMU, test host on 10.0.2.2) =="
    HWNET_PROGS="sh ls cat echo dhcp" bash tools/hwnet/build.sh "$D/s0" 0 > "$D/b0.txt" 2>&1 && ok "kernel + userland built" \
        || { bad "kernel/userland build"; tail -5 "$D/b0.txt"; }
    if vendor/firn/bin/firnc -c --profile=app -o "$D/fvv.o" kernel/user/fvviewer.fi > "$D/fvv2.err" 2>&1 \
        && ld -T kernel/user/user.ld -o "$D/fvv.elf" "$D/fvv.o" 2>>"$D/fvv2.err" && strip --strip-all "$D/fvv.elf"; then
        ok "fvviewer built as a ring 3 app ($(stat -c%s "$D/fvv.elf") octets)"
    else
        bad "fvviewer ring 3 build"; head -8 "$D/fvv2.err"
    fi
    if [ -f "$D/s0/k.mb" ] && [ -f "$D/fvv.elf" ] && start_th; then
        python3 tools/osum/mkfs.py build "$D/disk.img" 32768 /bin/ \
            /bin/sh="$D/s0/sh.elf" /bin/ls="$D/s0/ls.elf" /bin/cat="$D/s0/cat.elf" /bin/echo="$D/s0/echo.elf" \
            /bin/dhcp="$D/s0/dhcp.elf" /bin/fvviewer="$D/fvv.elf" > "$D/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$D/mkfs.txt"; }
        timeout 300 qemu-system-x86_64 -kernel "$D/s0/k.mb" -m 512 \
            -append "osum nokbd nosched noproc nofs modfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=dhcp;fvviewer -t 10.0.2.2 $PORT $ID testpass123;exit" \
            -serial "file:$D/vm.txt" -display none -no-reboot \
            -drive "file=$D/disk.img,format=raw,if=ide,index=0" -netdev user,id=n0 -device e1000,netdev=n0 \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
        grep -a -E '^\s+(ok|FAIL)|FVV:|code' "$D/vm.txt" | head -14 | sed 's/^/        /'
        grep -aq "FVV: .* 0 FAIL" "$D/vm.txt" && ok "${MARKE_PRODUKT}: password mode, all checks (Argon2id 19 MiB, JPEG, tiles, ping, click)" \
            || bad "${MARKE_PRODUKT}: fvviewer -t failed -- serial tail: $(tail -c 300 "$D/vm.txt" | tr '\n' ' ')"
        sleep 1
        grep -q "TESTHOST input: MouseButton button=0 down=true" "$D/th.log" && ok "${MARKE_PRODUKT}: the test host logged the click from the guest" \
            || bad "${MARKE_PRODUKT}: no click in the test host log"
        stop_th
    fi
else
    echo "  SKIP  QEMU part (need FV_BIN, qemu-system-x86_64, node). Nothing is claimed."
fi
echo "FVVIEWER: $pass ok, $fail fail"
[ "$fail" = 0 ]
