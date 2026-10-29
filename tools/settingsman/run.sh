#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsman/run.sh -- host test of the SETTINGS manifest (r136, docs/SETTINGS-MANIFEST.md). No VM, seconds.
#
#   bash tools/settingsman/run.sh
#
# 1. the parser lib/settingsman/manifest.fi (built as tools/settingsman/dump.fi) and the second reader
#    tools/settingsman/manifest.py give the SAME text for every case in tools/settingsman/cases/ and for the real
#    page kernel/user/settings.d/builtin.settings, and both match the golden file (*.expect);
# 2. limits (280 items, 32 pages, string pool) -- both readers agree and say the expected code;
# 3. the accounts page is WIRED: every field key of the manifest is bound in kernel/user/settings.fi (ab_names), every
#    label is a catalogue key in en AND de, the Konten page no longer builds the book button by hand;
# 4. the CATALOGUE (r143): several manifests (built-in page + packages /apps/<app>.prog/SETTINGS) in one catalogue --
#    tools/settingsman/catalog.fi and `manifest.py --catalog` agree on every case in tools/settingsman/catalog/ and
#    on the catalogue limits; a rejected file leaves the catalogue as it was; no package can speak for another app;
# 4b. package pages (r149): read/write lines, pakete/social/SETTINGS against ACTIONS, the window loads + draws the catalogue;
# 5. MUTATIONS: each broken copy of the parser must turn step 1-4 red.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PY="python3 -I tools/settingsman/manifest.py"
MAN=kernel/user/settings.d/builtin.settings

build() { # libdir out
    FIRNLIB="$1" vendor/firn/bin/firnc --profile=app tools/settingsman/dump.fi -o "$2" > "$2.build" 2>&1
}

echo "== 1. both readers + golden =="
if build "$ROOT/lib" "$T/dump"; then ok "dump.fi builds against lib/settingsman"; else
    bad "dump.fi does not build"; grep -v '^warning' "$T/dump.build" | head; echo "SETTINGSMAN: $pass passed, $fail failed"; exit 1; fi

compare_all() { # dump-binary label -> number of differences
    local bin=$1 n=0 f b
    for f in tools/settingsman/cases/*.txt; do
        b=${f%.txt}
        "$bin" < "$f" > "$T/out.fi" 2>/dev/null
        cmp -s "$T/out.fi" "$b.expect" || n=$((n+1))
    done
    "$bin" < $MAN > "$T/out.fi" 2>/dev/null
    cmp -s "$T/out.fi" tools/settingsman/builtin.expect || n=$((n+1))
    echo "$n"
}
D=$(compare_all "$T/dump")
if [ "$D" = 0 ]; then ok "parser matches the golden file for all $(ls tools/settingsman/cases/*.txt | wc -l) cases + the accounts page"; else bad "parser differs from golden in $D files"; fi

nd=0
for f in tools/settingsman/cases/*.txt $MAN; do
    $PY < "$f" > "$T/py.out"; "$T/dump" < "$f" > "$T/fi.out"
    cmp -s "$T/py.out" "$T/fi.out" || { nd=$((nd+1)); echo "    differs: $f"; }
done
if [ "$nd" = 0 ]; then ok "second reader (python) agrees on every file"; else bad "python and Firn reader differ on $nd files"; fi
for f in tools/settingsman/cases/*.txt; do
    b=${f%.txt}
    case "$(basename "$b")" in
        ok_*) head -1 "$b.expect" | grep -q '^ok ' || bad "$(basename "$b") should be accepted" ;;
        rej_*) head -1 "$b.expect" | grep -q '^error ' && grep -q '^tables items=0 pages=0$' "$b.expect" || bad "$(basename "$b") should be rejected with empty tables" ;;
    esac
done
ok "golden files: every ok_* is accepted, every rej_* rejected with empty tables"
head -1 tools/settingsman/builtin.expect | grep -q '^ok app=settings items=216 pages=24 warns=0$' \
    && ok "settings manifest: accounts, network, display, personal, system and tools pages, no warnings" || bad "accounts page header: $(head -1 tools/settingsman/builtin.expect)"

echo "== 2. limits =="
python3 -I - "$T" <<'PY'
import sys
t = sys.argv[1]
hdr = "manifest 1\napp demo\n"
def w(name, body): open(f"{t}/{name}.txt", "w").write(hdr + body)
w("items280", "page a t s g\n" + "".join(f"field k{i} text\n" for i in range(280)))
w("items281", "page a t s g\n" + "".join(f"field k{i} text\n" for i in range(281)))
w("pages32", "".join(f"page p{i} t s g\n" for i in range(32)))
w("pages33", "".join(f"page p{i} t s g\n" for i in range(33)))
w("pool", "page a t s g\n" + "".join(f"field {'k%02d' % i + 'x' * 36} text {'l%02d' % i + 'y' * 36}\n" for i in range(210)))
PY
lim() { # name expected-first-line
    $PY < "$T/$1.txt" > "$T/$1.py"; "$T/dump" < "$T/$1.txt" > "$T/$1.fi" 2>/dev/null
    if cmp -s "$T/$1.py" "$T/$1.fi" && head -1 "$T/$1.fi" | grep -q "^$2"; then ok "$1: $(head -1 "$T/$1.fi")"; else bad "$1: expected '$2', Firn '$(head -1 "$T/$1.fi")', python '$(head -1 "$T/$1.py")'"; fi
}
lim items280 "ok app=demo items=280 "
lim items281 "error 8 "
lim pages32 "ok app=demo items=0 pages=32 "
lim pages33 "error 8 "
lim pool "error 9 "

echo "== 3. the accounts page is wired =="
python3 -I - <<'PY' && ok "wiring checks" || bad "wiring checks (see FAIL lines above)"
import re, sys
src = open("kernel/user/settings.fi", encoding="utf-8").read()
man = open("kernel/user/settings.d/builtin.settings", encoding="utf-8").read()
en = open("locale/en/messages", encoding="utf-8", errors="replace").read()
de = open("locale/de/messages", encoding="utf-8", errors="replace").read()
rc = 0
def bad(m):
    global rc; rc = 1; print("  FAIL  " + m)
pages, labels, cur = {}, [], None
conds = {}
for line in man.splitlines():
    w = line.split("#")[0].split()
    if not w: continue
    if w[0] == "page":
        cur = w[1]; pages[cur] = []
    elif w[0] in ("when", "unless"):
        conds.setdefault(cur, []).append(w[1])
    elif w[0] == "field":
        pages[cur].append(w[1])
        if len(w) > 3 and w[3] != "-": labels.append(w[3])
    elif w[0] in ("label", "note"): labels.append(w[1])
fields = pages["accounts"]
for bf, pgs in (("accounts", ("accounts",)), ("network", ("network",)), ("display", ("display", "display2", "display3")), ("personal", ("time", "lock", "password", "pin", "language", "wifi", "presets", "about")), ("system", ("taskbar", "effects", "usbnet", "proto", "update", "presetsel")), ("tools", ("sync", "bridge", "system", "rights", "netv"))):
    bound = [x for x in open("kernel/user/settings.d/%s.bind" % bf, encoding="utf-8").read().split("\n") if x]
    allf = [f for pg in pgs for f in pages[pg]]
    for f in allf:
        if f not in bound: bad("field %s has no binding in %s.bind" % (f, bf))
    cks = [c for pg in pgs for c in conds.get(pg, [])]
    for c in cks:
        if c not in bound: bad("condition %s has no binding in %s.bind" % (c, bf))
    for b in bound:
        if b not in allf and b not in cks: bad("binding %s is not a field of the pages of %s.bind" % (b, bf))
    if len(set(allf)) != len(allf): bad("duplicate field keys in the pages of %s.bind" % bf)
if not re.search(r"^field password secret ", man, re.M): bad("the password field of the accounts page is not type secret (shown in clear text)")
for k in sorted(set(labels)):
    for nm, cat in (("en", en), ("de", de)):
        if not re.search(r"^" + re.escape(k) + r" = ", cat, re.M): bad("catalogue key %s missing in %s" % (k, nm))
# acct_id: every action/entry/list key maps to a K_ constant that exists
for ix, k in re.findall(r"if ix == (\d+) \{ return (K_[A-Z]+) \}", src):
    if not re.search(r"^const %s: u64 = \d+" % k, src, re.M): bad("%s is not defined" % k)
if "fuiscene.button(left, msg.get((&k_k_book" in src: bad("the book button is built by hand again")
if '__include_str("settings.d/accounts.bind")' not in src: bad("the binding names are not embedded in settings.fi")
if '__include_str("settings.d/builtin.settings")' not in src: bad("the manifest is not embedded in settings.fi")
if "manifest.page_find(" not in src: bad("page_accounts does not read the manifest")
if '__include_str("settings.d/network.bind")' not in src: bad("the network binding names are not embedded in settings.fi")
if "fuiscene.label(left, (&l_nzust" in src: bad("the Network page is built by hand again")
if '__include_str("settings.d/display.bind")' not in src: bad("the display binding names are not embedded in settings.fi")
if "fuiscene.label(left, (&l_schirm" in src: bad("the Display page is built by hand again")
if '__include_str("settings.d/personal.bind")' not in src: bad("the personal binding names are not embedded in settings.fi")
for fnname in ("page_taskbar", "page_effects", "page_usbnet", "page_proto", "page_update", "page_vorl"):
    m = re.search(r"fn %s\(left: usize, right: usize\) \{\n(.*?)\n\}\n" % fnname, src, re.S)
    if not m or "page_man(4," not in m.group(1) or m.group(1).count("\n") != 0: bad("%s is not a one-line page_man wrapper" % fnname)
for fnname in ("page_sync", "page_bruecke", "page_system", "page_rechte", "page_netv"):
    m = re.search(r"fn %s\(left: usize, right: usize\) \{\n(.*?)\n\}\n" % fnname, src, re.S)
    if not m or "page_man(5," not in m.group(1) or m.group(1).count("\n") != 0: bad("%s is not a one-line page_man wrapper" % fnname)
if '__include_str("settings.d/tools.bind")' not in src: bad("the tools binding names are not embedded in settings.fi")
if "fn net_tables" in src or "fuiscene.label(left, (&l_yprov" in src: bad("a tools page is built by hand again")
if "fn man_shown" in src: bad("man_shown is back: conditions belong in the manifest (when/unless)")
for fnname in ("page_time", "page_benut", "page_passw", "page_pin", "page_sprache", "page_wifi", "page_vtrans", "page_info"):
    m = re.search(r"fn %s\(left: usize, right: usize\) \{\n(.*?)\n\}\n" % fnname, src, re.S)
    if not m or "page_man(3," not in m.group(1) or m.group(1).count("\n") != 0: bad("%s is not a one-line page_man wrapper" % fnname)
sys.exit(rc)
PY

FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc --profile=app tools/settingsman/bind.fi -o "$T/bind" > "$T/bind.build" 2>&1 \
    && "$T/bind" > "$T/bind.out"
python3 -I - > "$T/bind.exp" <<'PY'
names = [x for x in open("kernel/user/settings.d/accounts.bind").read().split("\n") if x]
cur = None
for line in open("kernel/user/settings.d/builtin.settings"):
    w = line.split("#")[0].split()
    if w and w[0] == "page": cur = w[1]
    if w and w[0] == "field" and cur == "accounts":
        print("%s=%d" % (w[1], names.index(w[1])))
print("unknown=4294967295 prefix=4294967295 longer=4294967295")
PY
if cmp -s "$T/bind.out" "$T/bind.exp"; then ok "names_index (fn acct_bind) gives every key its line number; unknown/prefix/longer keys are refused"; else bad "binding numbers differ: $(diff "$T/bind.out" "$T/bind.exp" | head -3 | tr '\n' ' ')"; fi

echo "== 4. catalogue: several manifests (r143) =="
build_cat() { # libdir out
    FIRNLIB="$1" vendor/firn/bin/firnc --profile=app tools/settingsman/catalog.fi -o "$2" > "$2.build" 2>&1
}
if build_cat "$ROOT/lib" "$T/cat"; then ok "catalog.fi builds against lib/settingsman"; else
    bad "catalog.fi does not build"; grep -v '^warning' "$T/cat.build" | head; fi
nd=0; ng=0; nc=0
for f in tools/settingsman/catalog/*.txt; do
    nc=$((nc+1))
    "$T/cat" < "$f" > "$T/c.fi" 2>/dev/null; python3 -I tools/settingsman/manifest.py --catalog < "$f" > "$T/c.py"
    cmp -s "$T/c.fi" "$T/c.py" || { nd=$((nd+1)); echo "    differs: $f"; }
    cmp -s "$T/c.fi" "${f%.txt}.expect" || { ng=$((ng+1)); echo "    golden differs: $f"; }
    case "$(basename "$f")" in
        ok_*) grep -q ' error ' "${f%.txt}.expect" && bad "$(basename "$f") should have no rejected file" ;;
        rej_*) grep -q ' error ' "${f%.txt}.expect" || bad "$(basename "$f") should reject a file" ;;
    esac
done
[ "$nd" = 0 ] && ok "second reader agrees on all $nc catalogue cases" || bad "python and Firn reader differ on $nd catalogue cases"
[ "$ng" = 0 ] && ok "catalogue output matches the golden file for all $nc cases" || bad "catalogue output differs from golden in $ng cases"
python3 -I - "$T" <<'PY'
import sys
t = sys.argv[1]
def sec(kind, app, body): return "%% " + kind + "\nmanifest 1\napp " + app + "\n" + body
def w(name, parts): open(f"{t}/cl_{name}.txt", "w").write("".join(parts))
one = "page p t s g\n"
w("apps8", [sec("add", f"a{i}", one) for i in range(8)])
w("apps9", [sec("add", f"a{i}", one) for i in range(9)])
p11 = lambda i: sec("add", f"a{i}", "".join(f"page p{j} t s g\n" for j in range(11)))
w("pages44", [p11(i) for i in range(4)])
w("pages45", [p11(i) for i in range(4)] + [sec("add", "a4", one)])
i85 = lambda i: sec("add", f"a{i}", one + "".join(f"field k{j} text\n" for j in range(85)))
w("items340", [i85(i) for i in range(4)])
w("items341", [i85(i) for i in range(4)] + [sec("add", "a4", one + "field k text\n")])
big = lambda i, tail="": sec("add", f"a{i}", one + "".join(f"field {'k%02d' % j + 'x' * 36} text {'l%02d' % j + 'y' * 36}\n" for j in range(66)) + tail)
w("pool_cat", [big(0), big(1), big(2), big(3)])
w("pool_leak", [big(0), big(1, "field Bad text\n"), big(2), big(3)])
PY
clim() { # name expected-line-pattern
    python3 -I tools/settingsman/manifest.py --catalog < "$T/cl_$1.txt" > "$T/cl_$1.py"; "$T/cat" < "$T/cl_$1.txt" > "$T/cl_$1.fi" 2>/dev/null
    if cmp -s "$T/cl_$1.py" "$T/cl_$1.fi" && grep -q "$2" "$T/cl_$1.fi"; then ok "catalogue $1: $(grep -m1 "$2" "$T/cl_$1.fi")"; else bad "catalogue $1: expected '$2' (Firn '$(grep -m1 -e ' error ' "$T/cl_$1.fi")', python '$(grep -m1 -e ' error ' "$T/cl_$1.py")')"; fi
}
clim apps8 "^catalog apps=8 pages=8 items=0"
clim apps9 "^add 9 error 8 line 2"
clim pages44 "^catalog apps=4 pages=44 items=0"
clim pages45 "^add 5 error 8 "
clim items340 "^catalog apps=4 pages=4 items=340"
clim items341 "^add 5 error 8 "
clim pool_cat "^add 4 error 9 "
clim pool_leak "^add 4 ok "

echo "== 4b. package pages (r149): pakete/social/SETTINGS + the Settings window =="
"$T/dump" < pakete/social/SETTINGS > "$T/social.fi" 2>/dev/null; python3 -I tools/settingsman/manifest.py < pakete/social/SETTINGS > "$T/social.py"
if cmp -s "$T/social.fi" "$T/social.py" && cmp -s "$T/social.fi" tools/settingsman/social.expect && grep -q '^ok app=social' "$T/social.fi"; then ok "pakete/social/SETTINGS: both readers agree and match the golden file"; else bad "pakete/social/SETTINGS: readers or golden differ ($(head -1 "$T/social.fi"))"; fi
python3 -I - <<'PY' && ok "package page wiring: keys in en+de, actions in ACTIONS, own-namespace rule, window loads and draws the catalogue" || bad "package page wiring (see lines above)"
import re, sys
rc = 0
def bad(m):
    global rc; rc = 1; print("    " + m)
man = open("pakete/social/SETTINGS", encoding="utf-8").read()
acts = open("pakete/social/ACTIONS", encoding="utf-8").read()
en = open("locale/en/messages", encoding="utf-8").read(); de = open("locale/de/messages", encoding="utf-8").read()
src = open("kernel/user/settings.fi", encoding="utf-8").read()
app = None; cur = None; labels = []; binds = []
for line in man.splitlines():
    w = line.split("#")[0].split()
    if not w: continue
    if w[0] == "app": app = w[1]
    elif w[0] == "page": labels.append(w[2])
    elif w[0] in ("label", "note"): labels.append(w[1])
    elif w[0] == "field":
        cur = w; labels += w[3:4]
    elif w[0] in ("read", "write"): binds.append((cur[1], cur[2], w[0], w[1]))
for k in sorted(set(labels)):
    for nm, cat in (("en", en), ("de", de)):
        if not re.search(r"^" + re.escape(k) + r" = ", cat, re.M): bad("catalogue key %s missing in %s" % (k, nm))
blocks = {m.group(1): m.group(2) for m in re.finditer(r"^action (\S+) .*?\n((?:  .*\n|\n(?=  ))*)", acts, re.M)}
for key, ty, kind, act in binds:
    if not act.startswith(app + "."): bad("%s %s: action %s is outside the namespace %s." % (key, kind, act, app))
    if act not in blocks: bad("%s: action %s is not in ACTIONS" % (key, act)); continue
    b = blocks[act]
    rkey = re.sub(r"\.[0-9]+$", ".N", key)
    if kind == "read" and not re.search(r"^  returns %s " % re.escape(rkey), b, re.M): bad("%s: %s does not return %s" % (key, act, rkey))
    if kind == "write" and ty == "bool" and not re.search(r"^  arg %s bool " % re.escape(key), b, re.M): bad("%s: %s has no bool arg %s" % (key, act, key))
    if kind == "write" and ty in ("text", "secret") and not re.search(r"^  arg %s string " % re.escape(key), b, re.M): bad("%s: %s has no string arg %s" % (key, act, key))
for k in ("settings.catpkg", "settings.pkg.ok", "settings.pkg.ask", "settings.pkg.err", "settings.pkg.nobus", "settings.pkg.deny"):
    for nm, cat in (("en", en), ("de", de)):
        if not re.search(r"^" + re.escape(k) + r" = ", cat, re.M): bad("catalogue key %s missing in %s" % (k, nm))
for need in ("manifest.add_pkg(", '".prog/SETTINGS', "page_pkg(cl, cr, reiter - R_ANZ)", "pkg_init()", "pkg_cat(", "tab_key(p)", "key >= K_PKGTAB0", "kind == 999"):
    if need not in src: bad("settings.fi lacks: " + need)
# every action call goes through the namespace check
for fn in ("fn pkg_click", "fn pkg_read_page"):
    body = src.split(fn, 1)[1].split("\nfn ", 1)[0]
    if "pkg_prefix_ok(" not in body: bad(fn + " calls an action without pkg_prefix_ok")
if "static mut nav_vis: [u64; 48]" not in src: bad("sidebar tables are too small for R_ANZ + PKG_MAX")
sys.exit(rc)
PY

echo "== 5. mutations of the parser =="
mutate() { # name old new
    local d="$T/m_$1"
    rm -rf "$d"; mkdir -p "$d"; cp -r lib "$d/lib"
    python3 -I - "$d/lib/settingsman/manifest.fi" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    print("MUTATION-ANCHOR-MISSING"); sys.exit(2)
open(p, "w").write(s.replace(old, new, 1))
PY
    [ "$?" = 0 ] || { bad "mutation $1: anchor missing (the parser changed, update this script)"; return; }
    if ! build "$d/lib" "$d/dump"; then bad "mutation '$1' does not compile"; return; fi
    local n=0 f
    for f in tools/settingsman/cases/*.txt $MAN "$T"/items2*.txt "$T"/pages*.txt "$T"/pool.txt; do
        timeout 10 "$d/dump" < "$f" > "$d/o.txt" 2>/dev/null
        case "$f" in
            */cases/*) cmp -s "$d/o.txt" "${f%.txt}.expect" || n=$((n+1)) ;;
            *builtin.settings) cmp -s "$d/o.txt" tools/settingsman/builtin.expect || n=$((n+1)) ;;
            *) b=$(basename "$f" .txt); cmp -s "$d/o.txt" "$T/$b.py" || n=$((n+1)) ;;
        esac
    done
    if FIRNLIB="$d/lib" vendor/firn/bin/firnc --profile=app tools/settingsman/bind.fi -o "$d/bind" > /dev/null 2>&1; then
        timeout 10 "$d/bind" > "$d/b.txt" 2>/dev/null; cmp -s "$d/b.txt" "$T/bind.exp" || n=$((n+1))
    else n=$((n+1)); fi
    if build_cat "$d/lib" "$d/cat"; then
        for f in tools/settingsman/catalog/*.txt "$T"/cl_*.txt; do
            timeout 10 "$d/cat" < "$f" > "$d/c.txt" 2>/dev/null
            case "$f" in
                */catalog/*) cmp -s "$d/c.txt" "${f%.txt}.expect" || n=$((n+1)) ;;
                *) b=$(basename "$f" .txt); cmp -s "$d/c.txt" "$T/$b.py" || n=$((n+1)) ;;
            esac
        done
    else n=$((n+1)); fi
    if [ "$n" -gt 0 ]; then ok "mutation '$1' is caught ($n files differ)"; else bad "mutation '$1' SURVIVED"; fi
}
mutate version-any '!word_eq(1, (&kw_one[0]) as u64, 1)' 'false'
mutate dup-page-ok 'if text_eq(pool_ptr(pg_id[(p) as usize]), pool_ptr(id)) {' 'if false {'
mutate dup-field-ok 'if it_kind[(i) as usize] == K_FIELD && text_eq(' 'if false && text_eq('
mutate dup-field-global 'var i: u64 = pg_first[(n_pages - 1) as usize]' 'var i: u64 = 0'
mutate unknown-type-rejects '        warns = warns + 1
        pend_cond = 0
        return 1
    }
    var label: u64 = 0' '        return fail(E_ITEM, line)
    }
    var label: u64 = 0'
mutate unknown-word-rejects '    // unknown line word: skipped, counted
    warns = warns + 1
    return 1' '    return fail(E_ITEM, line)'
mutate reject-keeps-tables '        n_items = base_items
        n_pages = base_pages' '        n_pages = base_pages'
mutate action-without-label 'if ty == T_ACTION && label == 0 {' 'if false {'
mutate note-lines-unchecked 'if wlen[2] != 1 || c < 49 || c > 57 {' 'if false {'
mutate column-sticks 'n_pages = n_pages + 1
    cur_col = 0' 'n_pages = n_pages + 1'
mutate comment-not-skipped 'if c == 35 {
                    i = e' 'if false {
                    i = e'
mutate underscore-refused 'c == 46 || c == 45 || c == 95' 'c == 46 || c == 45'
mutate app-name-40 'if !name_ok(1, 24) {' 'if !name_ok(1, 40) {'
mutate page-len-wrong 'pg_len[(n_pages - 1) as usize] = pg_len[(n_pages - 1) as usize] + 1' 'pg_len[(n_pages - 1) as usize] = pg_len[(n_pages - 1) as usize] + 2'
mutate two-apps 'if st != 1 || nw != 2 {
            return fail(E_APP, line)' 'if nw != 2 {
            return fail(E_APP, line)'
mutate item-limit 'if n_items - base_items >= MAX_ITEMS ||' 'if n_items - base_items >= MAX_ITEMS + 1 ||'
mutate page-limit 'if n_pages - base_pages >= MAX_PAGES ||' 'if n_pages - base_pages >= MAX_PAGES + 1 ||'
mutate pool-limit 'if pool_n - base_pool + n + 1 > POOL_MAX ||' 'if pool_n - base_pool + n + 1 > POOL_MAX + 1000 ||'
mutate default-lost 'def = put_word(4)' 'def = 0'
mutate bind-longer-key 'if same && e > at && rd(key, e - at) == 0 {' 'if same && e > at {'
mutate bind-index-skips '        ix = ix + 1
    }
    return NONE' '        ix = ix + 2
    }
    return NONE'
mutate col-ignored 'it_col[i] = cur_col' 'it_col[i] = 0'
# the catalogue (r143)
mutate dup-app-ok 'if app_find(pool_ptr(app_off)) != NONE {' 'if false {'
mutate pkg-name-unchecked 'if expect_app != 0 && !text_eq(pool_ptr(app_off), expect_app) {' 'if false {'
mutate rollback-items 'n_items = base_items
        n_pages = base_pages' 'n_pages = base_pages'
mutate rollback-pages '        n_pages = base_pages
        pool_n = base_pool' '        pool_n = base_pool'
mutate rollback-pool '        pool_n = base_pool
        n_apps = base_apps' '        n_apps = base_apps'
mutate rollback-apps '        n_apps = base_apps
        return ERR' '        return ERR'
mutate field-before-page-global 'if n_pages == base_pages {
            return fail(E_NO_PAGE, line)
        }
        return do_field(nw, line)' 'if n_pages == 0 {
            return fail(E_NO_PAGE, line)
        }
        return do_field(nw, line)'
mutate column-before-page-global 'if n_pages == base_pages {
            return fail(E_NO_PAGE, line)
        }
        if nw != 2 {
            return fail(E_COLUMN, line)' 'if n_pages == 0 {
            return fail(E_NO_PAGE, line)
        }
        if nw != 2 {
            return fail(E_COLUMN, line)'
mutate dup-page-across-apps 'var p: u64 = base_pages
    while p < n_pages {
        if text_eq(pool_ptr(pg_id' 'var p: u64 = 0
    while p < n_pages {
        if text_eq(pool_ptr(pg_id'
mutate page-app-wrong 'pg_app[i] = n_apps - 1' 'pg_app[i] = 0'
mutate app-first-wrong 'ap_first[(n_apps) as usize] = n_pages' 'ap_first[(n_apps) as usize] = 0'
mutate app-page-count-last 'return n_pages - ap_first[(a) as usize]' 'return n_pages'
mutate app-page-count-mid 'if a + 1 < n_apps {' 'if false {'
mutate lookup-all-apps 'var p: u64 = ap_first[(a) as usize]
    while p < e {' 'var p: u64 = 0
    while p < e {'
mutate cat-apps-limit 'if n_apps >= MAX_APPS {' 'if n_apps >= MAX_APPS + 1 {'
mutate cat-pages-limit '|| n_pages >= CAT_PAGES {' '|| n_pages >= CAT_PAGES + 1 {'
mutate cat-items-limit '|| n_items >= CAT_ITEMS {' '|| n_items >= CAT_ITEMS + 1 {'
mutate cat-pool-limit '|| pool_n + n + 1 > CAT_POOL {' '|| pool_n + n + 1 > CAT_POOL + 1000 {'
mutate load-keeps-catalogue 'reset()
    return add_man(buf, len)' 'return add_man(buf, len)'
mutate warns-carry 'warns = 0
    too_many = 0
    last_field = 0
    pend_cond = 0
    pend_neg = 0
    cur_buf = buf' 'too_many = 0
    last_field = 0
    pend_cond = 0
    pend_neg = 0
    cur_buf = buf'
mutate bind-needs-field 'if nw != 2 || was_field == 0 {' 'if nw != 2 {'
mutate bind-read-twice 'if wr == 0 && it_read[i] != 0 {' 'if false {'
mutate bind-write-twice 'if wr == 1 && it_write[i] != 0 {' 'if false {'
mutate bind-swapped 'it_read[i] = a' 'it_write[i] = a'
mutate bind-chain-broken 'last_field = 1 // the other of read/write may follow' 'last_field = 0'
mutate bind-name-unchecked 'return fail(E_NAME, line)
    }
    let i: usize = (n_items - 1) as usize' 'return 1
    }
    let i: usize = (n_items - 1) as usize'
mutate when-lost 'it_cond[i] = pend_cond' 'it_cond[i] = 0'
mutate unless-lost 'it_neg[i] = pend_neg' 'it_neg[i] = 0'
mutate when-dangling-ok 'if pend_cond != 0 && !is_item_word() {' 'if false {'
mutate when-eof-ok 'if err == 0 && pend_cond != 0 {' 'if false {'
mutate when-sticks 'it_neg[i] = pend_neg
    pend_cond = 0' 'it_neg[i] = pend_neg
    pend_neg = 0'
mutate type-slider-lost 'return T_SLIDER' 'return 0'
mutate type-table-lost 'return T_TABLE' 'return 0'
mutate type-canvas-lost 'return T_CANVAS' 'return 0'
mutate row-gap-lost 'return add_item(K_ROW, 0, 0, 0, 0, gap, line)' 'return add_item(K_ROW, 0, 0, 0, 0, 0, line)'
mutate row-gap-digits 'if c < 48 || c > 57 {
                    return fail(E_ITEM, line)' 'if false {
                    return fail(E_ITEM, line)'
mutate app-find-prefix 'if text_eq(pool_ptr(ap_name[(a) as usize]), name) {' 'if rd(pool_ptr(ap_name[(a) as usize]), 0) == rd(name, 0) {'

echo "SETTINGSMAN: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
