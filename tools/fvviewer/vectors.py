#!/usr/bin/env python3
"""tools/fvviewer/vectors.py -- compare lib/fv/{proto,session}.fi (via the vt
binary) with the Rust contract file tests/orientos-vectors.json, byte for byte.

  python3 -I tools/fvviewer/vectors.py <vt-binary> <vectors.json>

Checks: encode() of every viewer message, decode of every host message,
reject list, handshake (hello shape, ask answer, password proof for each
Argon2 case, session key, 4 digit code, result 0x04/0x05), AES-GCM data
frames both directions through session.seal_msg/open_msg (replay, tamper,
wrong direction, truncated), relay JSON.
Exit 0 = all equal.
"""
import json
import subprocess
import sys

VT, JSON = sys.argv[1], sys.argv[2]
d = json.load(open(JSON))
ok = bad = 0


def run(*args):
    r = subprocess.run([VT] + [str(a) for a in args], capture_output=True, timeout=120)
    if r.returncode != 0:
        return "RC%d %s" % (r.returncode, r.stderr.decode(errors="replace")[:80])
    return r.stdout.decode()


def check(name, got, want):
    global ok, bad
    if got == want:
        ok += 1
    else:
        bad += 1
        print("  FAIL  %s\n        got : %r\n        want: %r" % (name, str(got)[:300], str(want)[:300]))


def hx(s):
    return s.encode().hex() if s else "-"


# ------------------------------------------------------------------ encode
def enc_args(m):
    t = bytes.fromhex(m["hex"])[0]
    f = m["fields"]
    if t == 0x26:
        return ["caps", int(f["h264"])]
    if t == 0x30:
        return ["move", f["x"], f["y"]]
    if t == 0x31:
        return ["button", f["button"], int(f["down"])]
    if t == 0x32:
        return ["wheel", f["lines"]]
    if t == 0x33:
        return ["key", f["code"], int(f["named"]), int(f["down"])]
    if t == 0x35:
        return ["keyvk", f["vk"], int(f["ext"]), int(f["down"])]
    if t == 0x36:
        return ["special", f["code"]]
    if t == 0x37:
        return ["clip", hx(f["text"])]
    if t == 0x40:
        return ["ping", f["ts"]]
    if t == 0x41:
        return ["pong", f["ts"]]
    if t == 0x62:
        return ["needkey"]
    if t == 0x39:
        return ["setmon", f["index"]]
    return None


nenc = 0
for m in d["proto"]:
    a = enc_args(m)
    if a is None:
        continue
    nenc += 1
    check("enc " + m["name"], run("enc", *a).strip(), m["hex"])
print("  encode: %d messages" % nenc)


# ------------------------------------------------------------------ decode
def dec_want(m):
    t = bytes.fromhex(m["hex"])[0]
    f = m["fields"]
    if t == 0x20:
        return "screen %d %d\n" % (f["width"], f["height"])
    if t == 0x21:
        j = f["jpeg"]
        return "frame %d %d %d %s\n" % (f["width"], f["height"], len(j) // 2, j or "-")
    if t == 0x22:
        s = "tiles %d %d %d\n" % (f["width"], f["height"], len(f["tiles"]))
        for x in f["tiles"]:
            s += "tile %d %d %d %d %d %s\n" % (x["x"], x["y"], x["w"], x["h"], len(x["jpeg"]) // 2, x["jpeg"] or "-")
        return s + "tiles-end %d\n" % len(f["tiles"])
    if t == 0x23:
        return "cursor %d %d %d\n" % (f["x"], f["y"], int(f["visible"]))
    if t == 0x24:
        s = "mons %d %d\n" % (f["active"], len(f["list"]))
        for x in f["list"]:
            s += "mon %d %d %d %s\n" % (x["w"], x["h"], int(x["primary"]), hx(x["name"]))
        return s
    if t == 0x37:
        return "clip %s\n" % hx(f["text"])
    if t == 0x40:
        return "ping %d\n" % f["ts"]
    if t == 0x41:
        return "pong %d\n" % f["ts"]
    return "other %d\n" % t


ndec = 0
for m in d["proto"]:
    if m["dir"] == "V->H":
        continue
    ndec += 1
    check("dec " + m["name"], run("dec", m["hex"]), dec_want(m))
print("  decode: %d messages" % ndec)

for r in d["proto_reject"]:
    out = run("dec", r["hex"] or "-")
    # no decoded message may come out; types without a decoder are ignored
    check("reject " + r["name"], out.split(" ")[0].strip() in ("reject", "other"), True)
print("  reject: %d byte strings" % len(d["proto_reject"]))

# ------------------------------------------------------------------ handshake
h = d["handshake"]
host_pub = h["host_public"]
name_hex = h["ask_device_name"].encode().hex()
ack_main = h["hello_ack_frame_H_to_V"]
out = run("hs", h["client_secret"], ack_main, "ask", name_hex, "04")
want = ("hello_len 33 tag 1\npub %s\nanswer %s\nstate 2\nkey %s\ncode %s\nresult 1 state 3\n"
        % (h["client_public"], h["ask_frame_V_to_H"], h["session_key"], h["session_code"].encode().hex()))
check("handshake ask (pub, answer 0x06, key, code, OK)", out, want)
out = run("hs", h["client_secret"], ack_main, "ask", name_hex, "05")
check("handshake denied (0x05)", out.splitlines()[-1], "result 2 state 4")
out = run("hs", h["client_secret"], ack_main, "ask", name_hex, "07")
check("handshake unknown result byte", out.splitlines()[-1], "result 0 state 2")
# a bad hello_ack must fail the session, not crash
for nm, ack in (("short", ack_main[:-2]), ("wrong tag", "03" + ack_main[2:]), ("empty", ack_main[:2])):
    out = run("hs", h["client_secret"], ack, "ask", name_hex)
    check("handshake bad ack (%s) fails" % nm, "answer -\nstate 5\n" in out, True)

for c in d["argon2"]["cases"]:
    ack = "02" + host_pub + c["salt"]
    out = run("hs", h["client_secret"], ack, "pw", c["password_utf8_hex"])
    ans = [l for l in out.splitlines() if l.startswith("answer ")]
    check("password proof (Argon2id) " + c["name"], ans[0][7:] if ans else out, c["proof_frame_V_to_H"])
print("  handshake: ask + %d password cases" % len(d["argon2"]["cases"]))

# ------------------------------------------------------------------ cipher
ci = d["cipher"]
key = ci["key"]
v2h = ci["viewer_to_host"]
h2v = ci["host_to_viewer"]
out = run("sess", key, "seal", *[x["plaintext_hex"] for x in v2h]).split("\n")
check("session closed: seal refused", out[0], "closed_seal 0")
check("seal viewer->host frames (%d)" % len(v2h), out[1:1 + len(v2h)], [x["frame_hex"] for x in v2h])
out = run("sess", key, "open", *[x["frame_hex"] for x in h2v]).split("\n")
check("open host->viewer frames (%d)" % len(h2v), out[1:1 + len(h2v)], ["ok:" + x["plaintext_hex"] for x in h2v])
f0, f1 = h2v[0]["frame_hex"], h2v[1]["frame_hex"]
tamper = f0[:-2] + ("%02x" % (int(f0[-2:], 16) ^ 1))
tamper_ct = f0[:40] + ("%02x" % (int(f0[40:42], 16) ^ 0x80)) + f0[42:]
out = run("sess", key, "open", f0, f0, f1, f1, tamper, tamper_ct, f0[:20], "-",
          v2h[0]["frame_hex"], "11" + f1[2:]).split("\n")[1:]
check("replay / tamper / direction / short", out[:10],
      ["ok:" + h2v[0]["plaintext_hex"], "fail", "ok:" + h2v[1]["plaintext_hex"], "fail",
       "fail", "fail", "fail", "fail", "fail", "fail"])
# a forged frame must not advance the counter: tamper first, then the real one
out = run("sess", key, "open", tamper, tamper_ct, f0).split("\n")[1:]
check("failed frame does not burn the counter", out[:3], ["fail", "fail", "ok:" + h2v[0]["plaintext_hex"]])
print("  cipher: %d + %d frames" % (len(v2h), len(h2v)))

# ------------------------------------------------------------------ relay
check("relay connect json", run("relay", "connect", "123456789").strip(), h["relay_connect_json"])
check("relay connect rejects non-digits", run("relay", "connect", "12a45").strip(), "reject")
check("relay connect rejects 33 digits", run("relay", "connect", "1" * 33).strip(), "reject")
for text, kind in (('{"t":"paired"}', 1), ('{"t":"error","msg":"offline"}', 2), ('{"t":"peer_gone"}', 3),
                   ('{"t":"ping"}', 4), ('{"t":"bye"}', 5), ('{"t":"zzz"}', 9), ('{}', 0), ('{"t": "paired"}', 1)):
    check("relay kind " + text, run("relay", "kind", text.encode().hex()).strip(), str(kind))
check("relay str msg", run("relay", "str", '{"t":"error","msg":"offline"}'.encode().hex(), "msg").strip(), "offline")
check("relay str absent", run("relay", "str", '{"t":"paired"}'.encode().hex(), "msg").strip(), "none")

print("FVVIEWER VECTORS: %d ok, %d fail" % (ok, bad))
sys.exit(0 if bad == 0 else 1)
