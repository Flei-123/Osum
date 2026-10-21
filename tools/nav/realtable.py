import re, sys

def catalogue(path):
    d = {}
    for ln in open(path, encoding="utf-8"):
        m = re.match(r"^([a-z0-9._-]+) = (.*)$", ln.rstrip("\n"))
        if m:
            d[m.group(1)] = m.group(2)
    return d

def routes(path):
    out, last, app = [], None, None
    for ln in open(path, encoding="utf-8"):
        w = ln.split("#")[0].split()
        if not w:
            continue
        if w[0] == "app":
            app = w[1]
            out.append({"uri": app + "://", "title": w[2], "kw": None, "flags": [], "dyn": False})
        elif w[0] == "route":
            last = {"uri": w[1], "title": w[2], "kw": None, "flags": w[5:], "dyn": "dynamic" in w[5:]}
            out.append(last)
        elif w[0] == "kw" and last:
            last["kw"] = w[1]
    return out

def main():
    routes_file, locale, mode = sys.argv[1], sys.argv[2], sys.argv[3]
    cat = catalogue(locale)
    rs = routes(routes_file)
    if mode == "case":
        print("%% load")
        sys.stdout.write(open(routes_file, encoding="utf-8").read())
        print("%% run")
        for r in rs:
            t = cat.get(r["title"], "")
            k = cat.get(r["kw"], "") if r["kw"] else ""
            print("index %s %s | %s" % (r["uri"], t, k))
        for r in rs:
            if r["dyn"]:
                continue
            t = cat.get(r["title"], "")
            print("find %s %s" % (r["uri"], t))
            if r["kw"]:
                print("find %s %s" % (r["uri"], cat.get(r["kw"], "").split()[0]))
        print("lint")
    else:
        bad = 0
        for r in rs:
            for key in (r["title"], r["kw"]):
                if key and key not in cat:
                    print("missing key", key, locale)
                    bad += 1
            if len(cat.get(r["title"], "")) > 38:
                print("label too long", r["title"])
                bad += 1
        print("keycheck bad=%d routes=%d" % (bad, len(rs)))
        sys.exit(1 if bad else 0)

main()
