import re
import sys

conf = open(sys.argv[1]).read()
build = open(sys.argv[2], encoding="latin-1").read()
allowed = re.findall(r"^command_allowed\s*=\s*(\S+)", conf, re.M)
reads = re.findall(r"^read\s*=\s*(\S+)", conf, re.M)
progs = set()
for line in build.splitlines():
    if "orientbus act settingsd" in line or "glogin lock login passwd su" in line:
        progs.update(re.findall(r"[a-z0-9]+", line))
for name in ("act", "svc"):
    if "/bin/" + name not in allowed:
        sys.exit("/bin/%s is not in command_allowed" % name)
    if name not in progs:
        sys.exit("%s is not in the stick PROGS list" % name)
for path in ("/etc/jarvismini.conf", "/etc/apprights.conf", "/etc/wmplug.conf", "/etc/hotkeys.conf"):
    if path not in reads:
        sys.exit("%s is not readable" % path)
for path in reads:
    if path in ("/etc/shadow", "/etc/passwd", "/etc/", "/", "/etc/wlan.conf", "/etc/dbgsrv.token"):
        sys.exit("secret path readable: %s" % path)
print("ok")
