import json
import os
import time
import urllib.error
import urllib.request

BASE = os.environ.get("HW_WALK_BRIDGE", "http://127.0.0.1:8090")
ADMIN_KEY_FILE = os.environ.get("HW_WALK_ADMIN_KEY_FILE", "/srv/bruecke/verwalter.key")
ADMIN_HEADER = "X-Bridge-Admin"


class Reply:
    def __init__(self, http, job_status, text):
        self.http, self.job_status, self.text = http, job_status, text

    @property
    def exit_code(self):
        first = self.text.split("\n", 1)[0].split()
        if len(first) == 2 and first[0] == "ende" and first[1].isdigit():
            return int(first[1])
        return None

    @property
    def body(self):
        parts = self.text.split("\n", 1)
        return parts[1] if len(parts) == 2 and parts[0].startswith("ende ") else self.text

    @property
    def refused(self):
        return self.http == 200 and self.job_status in ("failed", "rejected", "denied")

    @property
    def done(self):
        return self.http == 200 and self.exit_code is not None


class Bridge:
    def __init__(self, device="", base=BASE, key_file=ADMIN_KEY_FILE, key=None):
        self.base = base
        self.device = device
        if key is None:
            with open(key_file) as f:
                key = f.read().strip()
        self.key = key

    def request(self, method, path, body=None, key="", timeout=40):
        headers = {"Content-Type": "application/json"}
        use = self.key if key == "" else key
        if use is not None:
            headers[ADMIN_HEADER] = use
        data = json.dumps(body).encode() if body is not None else None
        rq = urllib.request.Request(self.base + path, method=method, data=data, headers=headers)
        try:
            with urllib.request.urlopen(rq, timeout=timeout) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read()
        except OSError as e:
            return 0, {}, str(e).encode()

    def devices(self):
        code, _, body = self.request("GET", "/bridge/devices")
        if code != 200:
            raise RuntimeError("bridge server: HTTP %s %s" % (code, body[:80]))
        return json.loads(body).get("devices", [])

    def pick_device(self, wanted=""):
        items = self.devices()
        if wanted:
            hit = [d for d in items if d.get("device_id") == wanted or d.get("kennung") == wanted]
        else:
            hit = [d for d in items if d.get("connected") or d.get("verbunden")]
        if not hit:
            raise RuntimeError("no connected device%s" % (" named " + wanted if wanted else ""))
        hit.sort(key=lambda d: d.get("last_seen_s") if d.get("last_seen_s") is not None else d.get("zuletzt_gesehen_s") or 1e9)
        item = hit[0]
        self.device = item.get("device_id") or item.get("kennung")
        return item

    def online(self):
        for d in self.devices():
            if (d.get("device_id") or d.get("kennung")) == self.device:
                return bool(d.get("connected") or d.get("verbunden"))
        return False

    def submit(self, kind, target="", value="", ttl=120):
        code, _, body = self.request("POST", "/bridge/job", dict(
            device=self.device, kind=kind, target=target, value=value, ttl_s=ttl))
        if code != 200:
            return None, code, body.decode("latin1")
        return json.loads(body)["id"], code, ""

    def collect(self, job_id, timeout):
        end = time.time() + timeout
        while time.time() < end:
            code, headers, body = self.request("GET", "/bridge/fetch?device=%s&id=%s" % (self.device, job_id), timeout=35)
            if code == 200:
                return Reply(200, headers.get("X-Bridge-Status", ""), body.decode("latin1"))
            if code != 404:
                return Reply(code, "", body.decode("latin1"))
        return Reply(0, "timeout", "")

    def job(self, kind, target="", value="", timeout=90):
        job_id, code, err = self.submit(kind, target, value)
        if job_id is None:
            return Reply(code, "", err)
        return self.collect(job_id, timeout)

    def run(self, command, timeout=90):
        return self.job("run", command, timeout=timeout)

    def read(self, path, timeout=90):
        return self.job("read", path, timeout=timeout)
