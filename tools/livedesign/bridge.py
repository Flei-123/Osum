import base64
import json
import os
import time
import urllib.error
import urllib.request

BASE = os.environ.get("LIVEDESIGN_BRIDGE", "http://127.0.0.1:8090")
KEY_FILE = os.environ.get("LIVEDESIGN_KEY", "/srv/bruecke/verwalter.key")


class Bridge:
    def __init__(self, device=None):
        with open(KEY_FILE) as f:
            self.key = f.read().strip()
        self.device = device or os.environ.get("LIVEDESIGN_DEVICE") or self.connected_device()

    def request(self, method, path, body=None, timeout=40):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(BASE + path, method=method, data=data,
                                     headers={"X-Bruecke-Verwalter": self.key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read()
        except OSError as e:
            return 0, {}, str(e).encode()

    def connected_device(self):
        status, _, body = self.request("GET", "/bruecke/geraete")
        if status != 200:
            raise SystemExit("livedesign: bridge server answered HTTP %s" % status)
        live = [g["kennung"] for g in json.loads(body)["geraete"]
                if g.get("verbunden") and g["kennung"].startswith("osum-")]
        if len(live) != 1:
            raise SystemExit("livedesign: expected exactly one connected OrientOS device, found %s; set LIVEDESIGN_DEVICE" % live)
        return live[0]

    def job(self, kind, target="", value="", timeout=90):
        status, _, body = self.request("POST", "/bruecke/auftrag",
                                       dict(geraet=self.device, art=kind, ziel=target, wert=value, ttl_s=120))
        if status != 200:
            raise SystemExit("livedesign: job %s refused: HTTP %s %s" % (kind, status, body[:120]))
        job_id = json.loads(body)["id"]
        end = time.time() + timeout
        while time.time() < end:
            status, headers, payload = self.request("GET", "/bruecke/holen?geraet=%s&id=%s" % (self.device, job_id), timeout=35)
            if status == 200:
                return headers.get("X-Bruecke-Status", ""), payload
            if status != 404:
                raise SystemExit("livedesign: result of job %s: HTTP %s" % (job_id, status))
        raise SystemExit("livedesign: device did not answer job %s (%s) within %d s" % (job_id, kind, timeout))

    def command(self, line, timeout=90):
        status, payload = self.job("command", line, timeout=timeout)
        return status, payload.decode("utf-8", "replace")

    def write_file(self, path, data, timeout=300):
        status, payload = self.job("write", path, "b64:" + base64.b64encode(data).decode(), timeout=timeout)
        return status, payload.decode("utf-8", "replace")

    def photo(self, out_path):
        self.command("/bin/jarvisctl screenshot", timeout=30)
        status, payload = self.job("photo", timeout=60)
        if payload[:4] != b"\x89PNG":
            raise SystemExit("livedesign: no PNG came back (status %s)" % status)
        with open(out_path, "wb") as f:
            f.write(payload)
        return len(payload)
