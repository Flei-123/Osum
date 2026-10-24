#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import join as J

ok = J.ok


def conf_text(ssid=b"OsumNetz", psk=b"einpasswort123", eol=b"\n"):
    return b"ssid " + ssid + eol + b"psk " + psk + eol


def pmk_ref(psk, ssid):
    return hashlib.pbkdf2_hmac("sha1", psk, ssid, 4096, 32).hex()


def parse_all():
    cases = {
        "good": conf_text(),
        "crlf": conf_text(eol=b"\r\n"),
        "no_final_newline": b"ssid OsumNetz\npsk einpasswort123",
        "reversed": b"psk einpasswort123\nssid OsumNetz\n",
        "spaces_in_ssid": conf_text(ssid=b"Mein Netz 5 GHz"),
        "spaces_in_psk": conf_text(psk=b"ein pass wort 123"),
        "noise_lines": b"# comment\nfoo bar\nssid OsumNetz\n\nxyz\npsk einpasswort123\nssidx 1\n",
        "last_wins": b"ssid Alt\npsk altespasswort1\nssid OsumNetz\npsk einpasswort123\n",
        "psk_min8": conf_text(psk=b"12345678"),
        "psk_max63": conf_text(psk=b"p" * 63),
        "ssid_max32": conf_text(ssid=b"s" * 32),
        "empty": b"",
        "no_ssid": b"psk einpasswort123\n",
        "no_psk": b"ssid OsumNetz\n",
        "psk_short7": conf_text(psk=b"1234567"),
        "psk_long64": conf_text(psk=b"p" * 64),
        "ssid_long33": conf_text(ssid=b"s" * 33),
        "ssid_empty": b"ssid \npsk einpasswort123\n",
        "psk_empty": b"ssid OsumNetz\npsk \n",
    }
    names = list(cases)
    out = J.run(["conf " + J.hx(cases[n]) for n in names for _ in (0,)])
    res = {}
    k = 0
    for n in names:
        a = out[k].split()
        b = out[k + 1].split()
        k += 2
        res[n] = (a, b)
    return cases, res


def field(a, key):
    return a[a.index(key) + 1]


def check_parse():
    print("== /etc/wlan.conf parser ==")
    cases, res = parse_all()
    good_names = ["good", "crlf", "no_final_newline", "reversed", "spaces_in_ssid", "spaces_in_psk",
                  "noise_lines", "last_wins", "psk_min8", "psk_max63", "ssid_max32"]
    for n in good_names:
        a, b = res[n]
        text = cases[n]
        ssid = b"OsumNetz"
        psk = b"einpasswort123"
        if n == "spaces_in_ssid":
            ssid = b"Mein Netz 5 GHz"
        if n == "spaces_in_psk":
            psk = b"ein pass wort 123"
        if n == "psk_min8":
            psk = b"12345678"
        if n == "psk_max63":
            psk = b"p" * 63
        if n == "ssid_max32":
            ssid = b"s" * 32
        ok(field(a, "rc") == "0" and field(a, "ssid") == ssid.hex() and int(field(a, "psklen")) == len(psk),
           "parse %s: ssid and psk taken" % n)
        ok(field(a, "pmk") == pmk_ref(psk, ssid), "parse %s: PMK equals PBKDF2-HMAC-SHA1 reference" % n)
        ok(field(b, "psklen") == "0" and field(b, "psk0") == "0" and field(b, "pmk0") == "0",
           "parse %s: secrets cleared after clear" % n)
    want = {"empty": -300, "no_ssid": -301, "no_psk": -302, "psk_short7": -304, "psk_long64": -304,
            "ssid_long33": -303, "ssid_empty": -303, "psk_empty": -304}
    for n, rc in want.items():
        a, b = res[n]
        ok(int(field(a, "rc")) == rc and field(a, "pmk") == "-", "reject %s: rc %d, no PMK computed" % (n, rc))


def auto_line(conf, **kw):
    line, zp, tk = J.scenario(**kw)
    f = line.split(" ")
    return "auto " + J.hx(conf) + " " + " ".join(f[3:]), zp, tk


def parse_auto(lines):
    au = [l for l in lines if l.startswith("auto ")][0].split()
    return {"state": int(au[2]), "rc": int(au[4]), "tries": int(au[6]), "wait": int(au[8])}


def check_auto():
    print("== autostart: conf -> PMK -> join -> DHCP ==")
    names = ["good", "wrong_psk", "no_conf", "short_psk", "no_ssid_conf", "no_net", "auth_denied", "no_offer",
             "ssid_in_conf_differs", "good_crlf"]
    scs = {
        "good": auto_line(conf_text()),
        "wrong_psk": auto_line(conf_text(psk=b"falschespasswort")),
        "no_conf": auto_line(b""),
        "short_psk": auto_line(conf_text(psk=b"1234567")),
        "no_ssid_conf": auto_line(b"psk einpasswort123\n"),
        "no_net": auto_line(conf_text(), beacon="none"),
        "auth_denied": auto_line(conf_text(), auth=13),
        "no_offer": auto_line(conf_text(), skip=("offer",)),
        "ssid_in_conf_differs": auto_line(conf_text(ssid=b"Fremdnetz")),
        "good_crlf": auto_line(conf_text(eol=b"\r\n")),
    }
    out = J.run([scs[n][0] for n in names])
    runs = J.split_runs(out)
    ok(len(runs) == len(names), "all %d autostart scenarios produced a result" % len(names))
    if len(runs) != len(names):
        print("\n".join(out[:12]))
        return
    r = {n: (J.Result(runs[i]), parse_auto(runs[i])) for i, n in enumerate(names)}
    g, ga = r["good"]
    ok(ga["state"] == 5 and ga["rc"] == 0 and ga["tries"] == 1 and ga["wait"] == 0, "good conf: state up, rc 0, no wait")
    ok(g.rc == 0 and g.may == 1 and g.dhcp is not None and g.dhcp["ip"] == J.ip2i("192.168.0.50"),
       "good conf: joined, lease 192.168.0.50")
    ok(len(g.tx) == 7 and g.tx[0] == J.ref_auth() and g.tx[1] == J.ref_assoc(6),
       "good conf: same frames as the direct join path")
    ok(r["good_crlf"][1]["state"] == 5, "CRLF conf joins too")
    w, wa = r["wrong_psk"]
    ok(wa["state"] == 6 and wa["rc"] == -111 and wa["wait"] == 102, "wrong password in conf: retry state, MIC error, backoff 2")
    ok(w.may == 0 and w.dhcp is None and len(w.tx) == 3, "wrong password in conf: no data, no DHCP, no message 4")
    n, na = r["no_conf"]
    ok(na["state"] == 1 and na["rc"] == -300 and na["wait"] == 102, "no conf: state no-conf, nothing transmitted")
    ok(len(n.tx) == 0 and n.may == 0, "no conf: radio untouched")
    s, sa = r["short_psk"]
    ok(sa["state"] == 2 and sa["rc"] == -304 and len(s.tx) == 0, "short password in conf: bad-conf, nothing transmitted")
    q, qa = r["no_ssid_conf"]
    ok(qa["state"] == 2 and qa["rc"] == -301 and len(q.tx) == 0, "conf without ssid: bad-conf, nothing transmitted")
    nn, nna = r["no_net"]
    ok(nna["state"] == 6 and nna["rc"] == -102 and len(nn.tx) == 0, "network not in the air: retry, nothing transmitted")
    d, da = r["auth_denied"]
    ok(da["state"] == 6 and da["rc"] == -112 and len(d.tx) == 1, "auth refused: retry after one frame")
    o, oa = r["no_offer"]
    ok(oa["state"] == 6 and oa["rc"] == -201 and o.may == 1, "joined but no DHCP offer: retry with -201")
    f, fa = r["ssid_in_conf_differs"]
    ok(fa["state"] == 6 and fa["rc"] == -102 and len(f.tx) == 0, "conf names another network: not joined")
    print("== backoff ==")
    b = J.run(["backoff"])[0].split()
    steps = [int(x.rstrip("!")) for x in b[1:10]]
    ok(steps == [2, 4, 8, 16, 32, 64, 64, 64, 64], "backoff doubles to the 64 cap: %s" % steps)
    ok(not any(x.endswith("!") for x in b[1:10]), "never due before the wait is over")
    ok(b[10] == "waitdrv" and b[11] == "0" and b[12] == "0", "waiting for driver clears the wait")
    ok(bytes.fromhex(b[14]) == b"retry", "state names are stable")


check_parse()
check_auto()
print("RESULT pass=%d fail=%d" % (J.PASS, J.FAIL))
sys.exit(1 if J.FAIL else 0)
