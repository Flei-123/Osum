# SPDX-License-Identifier: GPL-2.0-only
import html
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SYSTEM_APPS_DIR = os.path.join(ROOT, "assets", "apps")

SCHEMA_ID = "orientos.manifest/2"
LAUNCHER_LIMIT = 1023
LAUNCHER_KEYS = ["name", "info", "keys", "revision", "fassung", "net", "exec", "icon", "menu", "hideif"]
KEYS_V1 = ["name", "info", "exec", "icon", "keys", "revision", "fassung", "net", "menu", "hideif"]
KEYS_V2 = ["manifest", "id", "version", "author", "license", "min_os", "perm", "service", "actions",
           "opens", "needs", "sandbox", "kind", "outputs", "web.entry", "web.font", "web.memory"]
REQUIRED = ["name", "info", "manifest", "id", "version"]
STRICT_REQUIRED = ["kind", "outputs", "author", "license", "revision"]

KINDS = ("gui", "app", "service")
OUTPUTS = ("native", "web")
MENUS = ("show", "hidden")
NET_MODES = ("real", "filtered", "faked", "none")
DEFAULT_WEB_ENTRY = "app.wasm"
DEFAULT_WEB_MEMORY_MIB = 256
WEB_MEMORY_RANGE = (16, 4096)

ENFORCED = "enforced"
IMPLICIT = "implicit"
DECLARED = "declared"

PERMS = {
    "net": (ENFORCED, None, "network access; build writes net=real, else net=none (netview, docs/NETVIEW.md); web: same-origin fetch only"),
    "notify": (ENFORCED, "notify", "post notifications (bus NOTIPOST)"),
    "clipboard.read": (ENFORCED, "clipboard.read", "read the clipboard (bus CLIPGET)"),
    "clipboard.write": (ENFORCED, "clipboard.write", "write the clipboard (bus CLIPSET)"),
    "mic": (ENFORCED, None, "record from the microphone (SYS_OSUM_AUDREAD)"),
    "fs.home": (ENFORCED, None, "read/write outside the app data folder; only needed by an app that says sandbox=files"),
    "audio.play": (ENFORCED, None, "play sound"),
    "hotkey": (ENFORCED, None, "a global shortcut: hotkeyd binds a key (from /etc/hotkeys.conf) to one of the app's named bus actions; the app never sees the keys"),
    "window.float": (ENFORCED, None, "a window above the normal ones (layer L_FLOAT, never above the lock screen or task bar)"),
    "files.open": (IMPLICIT, "file.open", "open files through the picker; the app gets name and content, never a path"),
    "files.save": (IMPLICIT, "file.save", "save a file through the picker; the app gives name, type and content, never a path"),
    "dialog": (IMPLICIT, "dialog", "message and confirm dialogs owned by the system"),
    "storage": (IMPLICIT, "storage", "key/value storage private to the app (/data/<name>/services/ ; web: localStorage)"),
}
WEB_PERMS = {"net", "files.open", "files.save", "clipboard.read", "clipboard.write", "dialog", "storage"}
SERVICE_PERMS = ("files.open", "files.save", "clipboard.read", "clipboard.write", "dialog", "storage")


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def err(self, line, msg):
        self.errors.append("line %d: %s" % (line, msg) if line else msg)

    def warn(self, line, msg):
        self.warnings.append("line %d: %s" % (line, msg) if line else msg)


def parse_info(text, rep):
    out = {}
    for no, raw in enumerate(text.split("\n"), 1):
        line = raw.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "=" not in line:
            rep.err(no, "not a key=value line: %r" % line[:40])
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k in out:
            rep.err(no, "duplicate key '%s' (first at line %d)" % (k, out[k][1]))
            continue
        out[k] = (v.strip(), no)
    return out


def short_of(app_id):
    return app_id.rsplit(".", 1)[-1]


def system_names():
    try:
        return {n[:-4] for n in os.listdir(SYSTEM_APPS_DIR) if n.endswith(".osp")}
    except OSError:
        return set()


def csv(v):
    return [x.strip() for x in v.split(",") if x.strip()]


def launcher_head_end(data):
    last = -1
    pos = 0
    keys = tuple(k.encode() + b"=" for k in LAUNCHER_KEYS)
    for raw in data.split(b"\n"):
        if raw.startswith(keys):
            last = max(last, pos + len(raw))
        pos += len(raw) + 1
    return last


def check_identity(f, rep, system, project):
    short = None
    if "id" in f:
        v, no = f["id"]
        if not re.fullmatch(r"[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*){1,5}", v):
            rep.err(no, "id '%s': reverse-DNS, lower case, 2-6 parts (org.example.app)" % v)
        else:
            short = short_of(v)
            if not re.fullmatch(r"[a-z][a-z0-9]{0,15}", short):
                rep.err(no, "last part of id ('%s') is the bundle name: [a-z][a-z0-9]{0,15}" % short)
                short = None
            elif system:
                folder = os.path.basename(os.path.abspath(project or ".")).removesuffix(".osp")
                if project and folder != short:
                    rep.err(no, "bundle name '%s' differs from its folder '%s'" % (short, folder))
            elif short in system_names():
                rep.err(no, "bundle name '%s' collides with a system app" % short)
    if "version" in f and not re.fullmatch(r"\d{1,4}\.\d{1,4}\.\d{1,4}", f["version"][0]):
        rep.err(f["version"][1], "version '%s': MAJOR.MINOR.PATCH" % f["version"][0])
    if "name" in f and not (1 <= len(f["name"][0]) <= 31):
        rep.err(f["name"][1], "name: 1..31 characters")
    if "info" in f and not (1 <= len(f["info"][0]) <= 80):
        rep.err(f["info"][1], "info: 1..80 characters")
    if "revision" not in f and "fassung" not in f:
        rep.err(0, "missing required key 'revision'")
    for rev_key in ("revision", "fassung"):
        if rev_key in f and not re.fullmatch(r"\d{1,6}", f[rev_key][0]):
            rep.err(f[rev_key][1], "%s: a whole number (raise it with every release)" % rev_key)
    if "min_os" in f and not re.fullmatch(r"\d{1,6}(\.\d{1,6}){0,2}", f["min_os"][0]):
        rep.err(f["min_os"][1], "min_os: 1-3 dotted numbers")
    elif "min_os" in f:
        rep.warn(f["min_os"][1], "min_os is declared only: the OS has no version number to compare yet")
    return short


def check_perms(f, rep):
    if "sandbox" in f and f["sandbox"][0] != "files":
        rep.err(f["sandbox"][1], "sandbox: files")
    if "net" in f:
        if f["net"][0] not in NET_MODES:
            rep.err(f["net"][1], "net: real|filtered|faked|none")
        if "perm" in f and ("net" in csv(f["perm"][0])) != (f["net"][0] != "none"):
            rep.err(f["net"][1], "net=%s contradicts perm" % f["net"][0])
    if "perm" not in f:
        return
    seen = set()
    for p in csv(f["perm"][0]):
        if p not in PERMS:
            rep.err(f["perm"][1], "unknown permission '%s' (osdk.py perms)" % p)
        elif p in seen:
            rep.err(f["perm"][1], "permission '%s' twice" % p)
        elif PERMS[p][0] == DECLARED:
            rep.warn(f["perm"][1], "perm '%s' is declared only: the system does not enforce it yet" % p)
        seen.add(p)


def check_kind_outputs(f, rep, project):
    kind = f["kind"][0] if "kind" in f else None
    if kind is not None and kind not in KINDS:
        rep.err(f["kind"][1], "kind '%s': gui|app|service" % kind)
    if kind == "service" and "service" not in f:
        rep.err(f["kind"][1], "kind=service needs a service= bus name")
    if "service" in f and kind not in (None, "service"):
        rep.err(f["service"][1], "service= is declared but kind=%s" % kind)
    outs = []
    if "outputs" in f:
        outs = csv(f["outputs"][0])
        for o in outs:
            if o not in OUTPUTS:
                rep.err(f["outputs"][1], "outputs '%s': native|web" % o)
        if not outs or len(set(outs)) != len(outs):
            rep.err(f["outputs"][1], "outputs: a non-empty list without duplicates")
    web_keys = [k for k in f if k.startswith("web.")]
    if web_keys and "web" not in outs:
        rep.err(f[web_keys[0]][1], "%s needs outputs to contain web" % web_keys[0])
    if "web" in outs:
        check_web(f, rep, kind, project)
    if "menu" in f and f["menu"][0] not in MENUS:
        rep.err(f["menu"][1], "menu: show|hidden")
    if "icon" in f and not re.fullmatch(r"[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*", f["icon"][0]):
        rep.err(f["icon"][1], "icon: a relative path inside the bundle")
    if "icon" in f and ".." in f["icon"][0].split("/"):
        rep.err(f["icon"][1], "icon: a relative path inside the bundle")


def check_web(f, rep, kind, project):
    line = f["outputs"][1]
    if kind == "service":
        rep.err(line, "a bus service has no web output")
    perms = csv(f["perm"][0]) if "perm" in f else []
    for p in perms:
        if p in PERMS and p not in WEB_PERMS:
            rep.err(f["perm"][1], "perm '%s' has no web backend" % p)
    if "web.entry" in f and not re.fullmatch(r"[A-Za-z0-9._-]{1,48}\.wasm", f["web.entry"][0]):
        rep.err(f["web.entry"][1], "web.entry: a .wasm file name")
    if "web.font" in f and not re.fullmatch(r"[A-Za-z0-9._-]{1,48}\.ttf", f["web.font"][0]):
        rep.err(f["web.font"][1], "web.font: a .ttf file name")
    if "web.memory" in f:
        v = f["web.memory"][0]
        lo, hi = WEB_MEMORY_RANGE
        if not (v.isdigit() and lo <= int(v) <= hi):
            rep.err(f["web.memory"][1], "web.memory: MiB, %d..%d" % (lo, hi))
    if project:
        icon = f["icon"][0] if "icon" in f else "symbol.svg"
        if not icon.endswith(".svg") or not os.path.isfile(os.path.join(project, icon)):
            rep.err(line, "outputs=web needs an SVG icon (symbol.svg or icon=<file>.svg) in the project")


def check_lists(f, rep, short, project):
    if "service" in f:
        for s in csv(f["service"][0]):
            if len(s) > 16:
                rep.err(f["service"][1], "service '%s': a bus name has at most 16 octets" % s)
            elif not re.fullmatch(r"[a-z][a-z0-9.]*", s):
                rep.err(f["service"][1], "service '%s': [a-z][a-z0-9.]*" % s)
            elif short and s != short and not s.startswith(short + "."):
                rep.err(f["service"][1], "service '%s' is outside the app's namespace '%s'" % (s, short))
    for e in csv(f["opens"][0]) if "opens" in f else []:
        if not re.fullmatch(r"[a-z0-9]{1,8}", e):
            rep.err(f["opens"][1], "opens '%s': a file extension, 1..8 of [a-z0-9]" % e)
    for n in csv(f["needs"][0]) if "needs" in f else []:
        if not re.fullmatch(r"(os|app:[a-z][a-z0-9.-]*)>=\d{1,6}(\.\d{1,6}){0,2}", n):
            rep.err(f["needs"][1], "needs '%s': os>=N or app:<id>>=N" % n)
    if "actions" in f:
        check_actions(f, rep, short, project)


def check_actions(f, rep, short, project):
    rel = f["actions"][0]
    if not project:
        return
    p = os.path.join(project, rel)
    if ".." in rel or os.path.isabs(rel):
        rep.err(f["actions"][1], "actions: a path inside the project")
    elif not os.path.isfile(p):
        rep.err(f["actions"][1], "actions file '%s' missing" % rel)
    else:
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "actionbus", "manifest.py"), "check", p],
                           capture_output=True, text=True)
        if r.returncode != 0:
            rep.err(f["actions"][1], "actions file refused: " + (r.stdout + r.stderr).strip().split("\n")[-1])
        elif short:
            m = re.search(r"^app\s+(\S+)", open(p).read(), re.M)
            if not m or m.group(1) != short:
                rep.err(f["actions"][1], "ACTIONS 'app' must be '%s'" % short)


def check_strict(f, rep):
    for k in STRICT_REQUIRED:
        if k not in f or not f[k][0]:
            rep.err(f[k][1] if k in f else 0, "strict: missing or empty key '%s'" % k)
    if "fassung" in f:
        rep.err(f["fassung"][1], "strict: legacy key 'fassung', use 'revision'")


def lint(info_path, project=None, strict=False, system=False):
    rep = Report()
    try:
        data = open(info_path, "rb").read()
    except OSError as e:
        rep.err(0, "cannot read %s: %s" % (info_path, e))
        return rep, {}
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        rep.err(0, "INFO is not UTF-8")
        return rep, {}
    f = parse_info(text, rep)
    known = set(KEYS_V1 + KEYS_V2)
    for k, (v, no) in f.items():
        if k not in known and not k.startswith("x-"):
            rep.err(no, "unknown key '%s' (custom keys start with x-)" % k)
    for k in REQUIRED:
        if k not in f:
            rep.err(0, "missing required key '%s'" % k)
    if "manifest" in f and f["manifest"][0] != "2":
        rep.err(f["manifest"][1], "manifest=%s: this tool reads manifest=2" % f["manifest"][0])
    end = launcher_head_end(data)
    if end >= LAUNCHER_LIMIT:
        rep.err(0, "launcher keys end at octet %d; appdir reads 1023 -- move comments behind them" % end)
    short = check_identity(f, rep, system, project)
    check_perms(f, rep)
    check_kind_outputs(f, rep, project)
    check_lists(f, rep, short, project)
    if strict:
        check_strict(f, rep)
    return rep, {k: v[0] for k, v in f.items()}


def service_calls(perms):
    return sorted(PERMS[p][1] for p in perms if p in PERMS and PERMS[p][1] and p in SERVICE_PERMS)


def normalize(f):
    perms = csv(f.get("perm", ""))
    kind = f.get("kind") or ("service" if "service" in f else "app")
    outs = csv(f["outputs"]) if "outputs" in f else ["native"]
    revision = f.get("revision", f.get("fassung", "0"))
    net = f.get("net") or ("real" if "net" in perms else None)
    m = {
        "schema": SCHEMA_ID,
        "id": f["id"],
        "name": f["name"],
        "info": f["info"],
        "keys": csv(f.get("keys", "")),
        "version": f["version"],
        "revision": int(revision),
        "kind": kind,
        "outputs": outs,
        "menu": f.get("menu", "show"),
        "permissions": perms,
        "services": service_calls(perms),
    }
    for src, dst in (("author", "author"), ("license", "license"), ("min_os", "min_os"), ("icon", "icon"),
                     ("hideif", "hide_if"), ("sandbox", "sandbox")):
        if src in f:
            m[dst] = f[src]
    for key in ("service", "opens", "needs"):
        if key in f:
            m[key] = csv(f[key])
    if "actions" in f:
        m["actions"] = f["actions"]
    if "native" in outs:
        m["native"] = {"entry": f.get("exec", "start")}
        if net:
            m["native"]["net"] = net
    if "web" in outs:
        m["web"] = web_section(f, perms)
    custom = {k: v for k, v in f.items() if k.startswith("x-")}
    if custom:
        m["custom"] = custom
    return m


def web_section(f, perms):
    caps = []
    if service_calls(perms):
        caps.append("services")
    if "net" in perms:
        caps.append("fetch")
    web = {
        "entry": f.get("web.entry", DEFAULT_WEB_ENTRY),
        "memory_mib": int(f.get("web.memory", DEFAULT_WEB_MEMORY_MIB)),
        "capabilities": caps,
    }
    if "web.font" in f:
        web["font"] = f["web.font"]
    return web


def page(m):
    web = m["web"]
    head = ['<meta charset="utf-8">', "<title>%s</title>" % html.escape(m["name"])]
    if web["capabilities"]:
        head.append('<meta name="firn-capabilities" content="%s">' % ",".join(web["capabilities"]))
    font = ' data-font="%s"' % html.escape(web["font"]) if "font" in web else ""
    head.append('<link rel="application" type="application/wasm" href="%s"%s>' % (html.escape(web["entry"]), font))
    return "<!doctype html>\n<html>\n<head>\n%s\n</head>\n<body></body>\n</html>\n" % "\n".join(head)
