#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsman/run.sh -- host test of the SETTINGS manifest (r136, docs/SETTINGS-MANIFEST.md). No VM, seconds.
#
#   bash tools/settingsman/run.sh
#
# 1. the parser lib/settingsman/manifest.fi (built as tools/settingsman/dump.fi) and the second reader
#    tools/settingsman/manifest.py give the SAME text for every case in tools/settingsman/cases/ and for the real
#    page kernel/user/settings.d/accounts.settings, and both match the golden file (*.expect);
# 2. limits (80 items, 8 pages, string pool) -- both readers agree and say the expected code;
# 3. the accounts page is WIRED: every field key of the manifest is bound in kernel/user/settings.fi (ab_names), every
#    label is a catalogue key in en AND de, the Konten page no longer builds the book button by hand;
# 4. MUTATIONS: each broken copy of the parser must turn step 1/2 red.
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
MAN=kernel/user/settings.d/accounts.settings

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
    cmp -s "$T/out.fi" tools/settingsman/accounts.expect || n=$((n+1))
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
head -1 tools/settingsman/accounts.expect | grep -q '^ok app=settings items=16 pages=1 warns=0$' \
    && ok "accounts page: 1 page, 16 items, no warnings" || bad "accounts page header: $(head -1 tools/settingsman/accounts.expect)"

echo "== 2. limits =="
python3 -I - "$T" <<'PY'
import sys
t = sys.argv[1]
hdr = "manifest 1\napp demo\n"
def w(name, body): open(f"{t}/{name}.txt", "w").write(hdr + body)
w("items80", "page a t s g\n" + "".join(f"field k{i} text\n" for i in range(80)))
w("items81", "page a t s g\n" + "".join(f"field k{i} text\n" for i in range(81)))
w("pages8", "".join(f"page p{i} t s g\n" for i in range(8)))
w("pages9", "".join(f"page p{i} t s g\n" for i in range(9)))
w("pool", "page a t s g\n" + "".join(f"field {'k%02d' % i + 'x' * 36} text {'l%02d' % i + 'y' * 36}\n" for i in range(60)))
PY
lim() { # name expected-first-line
    $PY < "$T/$1.txt" > "$T/$1.py"; "$T/dump" < "$T/$1.txt" > "$T/$1.fi" 2>/dev/null
    if cmp -s "$T/$1.py" "$T/$1.fi" && head -1 "$T/$1.fi" | grep -q "^$2"; then ok "$1: $(head -1 "$T/$1.fi")"; else bad "$1: expected '$2', Firn '$(head -1 "$T/$1.fi")', python '$(head -1 "$T/$1.py")'"; fi
}
lim items80 "ok app=demo items=80 "
lim items81 "error 8 "
lim pages8 "ok app=demo items=0 pages=8 "
lim pages9 "error 8 "
lim pool "error 9 "

echo "== 3. the accounts page is wired =="
python3 -I - <<'PY' && ok "wiring checks" || bad "wiring checks (see FAIL lines above)"
import re, sys
src = open("kernel/user/settings.fi", encoding="utf-8").read()
man = open("kernel/user/settings.d/accounts.settings", encoding="utf-8").read()
en = open("locale/en/messages", encoding="utf-8", errors="replace").read()
de = open("locale/de/messages", encoding="utf-8", errors="replace").read()
rc = 0
def bad(m):
    global rc; rc = 1; print("  FAIL  " + m)
bound = [x for x in open("kernel/user/settings.d/accounts.bind", encoding="utf-8").read().split("\n") if x]
fields, labels = [], []
for line in man.splitlines():
    w = line.split("#")[0].split()
    if not w: continue
    if w[0] == "field":
        fields.append(w[1])
        if len(w) > 3: labels.append(w[3])
    elif w[0] in ("label", "note"): labels.append(w[1])
for f in fields:
    if f not in bound: bad("field %s has no binding in accounts.bind" % f)
for b in bound:
    if b not in fields: bad("binding %s is not a field of the manifest" % b)
if len(set(fields)) != len(fields): bad("duplicate field keys")
for k in sorted(set(labels)):
    for nm, cat in (("en", en), ("de", de)):
        if not re.search(r"^" + re.escape(k) + r" = ", cat, re.M): bad("catalogue key %s missing in %s" % (k, nm))
# acct_id: every action/entry/list key maps to a K_ constant that exists
for ix, k in re.findall(r"if ix == (\d+) \{ return (K_[A-Z]+) \}", src):
    if not re.search(r"^const %s: u64 = \d+" % k, src, re.M): bad("%s is not defined" % k)
if "fuiscene.button(left, msg.get((&k_k_book" in src: bad("the book button is built by hand again")
if '__include_str("settings.d/accounts.bind")' not in src: bad("the binding names are not embedded in settings.fi")
if '__include_str("settings.d/accounts.settings")' not in src: bad("the manifest is not embedded in settings.fi")
if "manifest.page_find(" not in src: bad("page_konto does not read the manifest")
sys.exit(rc)
PY

FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc --profile=app tools/settingsman/bind.fi -o "$T/bind" > "$T/bind.build" 2>&1 \
    && "$T/bind" > "$T/bind.out"
python3 -I - > "$T/bind.exp" <<'PY'
names = [x for x in open("kernel/user/settings.d/accounts.bind").read().split("\n") if x]
for line in open("kernel/user/settings.d/accounts.settings"):
    w = line.split("#")[0].split()
    if w and w[0] == "field":
        print("%s=%d" % (w[1], names.index(w[1])))
print("unknown=4294967295 prefix=4294967295 longer=4294967295")
PY
if cmp -s "$T/bind.out" "$T/bind.exp"; then ok "names_index (fn acct_bind) gives every key its line number; unknown/prefix/longer keys are refused"; else bad "binding numbers differ: $(diff "$T/bind.out" "$T/bind.exp" | head -3 | tr '\n' ' ')"; fi

echo "== 4. mutations of the parser =="
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
    for f in tools/settingsman/cases/*.txt $MAN "$T"/items8*.txt "$T"/pages*.txt "$T"/pool.txt; do
        timeout 10 "$d/dump" < "$f" > "$d/o.txt" 2>/dev/null
        case "$f" in
            */cases/*) cmp -s "$d/o.txt" "${f%.txt}.expect" || n=$((n+1)) ;;
            *accounts.settings) cmp -s "$d/o.txt" tools/settingsman/accounts.expect || n=$((n+1)) ;;
            *) b=$(basename "$f" .txt); cmp -s "$d/o.txt" "$T/$b.py" || n=$((n+1)) ;;
        esac
    done
    if FIRNLIB="$d/lib" vendor/firn/bin/firnc --profile=app tools/settingsman/bind.fi -o "$d/bind" > /dev/null 2>&1; then
        timeout 10 "$d/bind" > "$d/b.txt" 2>/dev/null; cmp -s "$d/b.txt" "$T/bind.exp" || n=$((n+1))
    else n=$((n+1)); fi
    if [ "$n" -gt 0 ]; then ok "mutation '$1' is caught ($n files differ)"; else bad "mutation '$1' SURVIVED"; fi
}
mutate version-any '!word_eq(1, (&kw_one[0]) as u64, 1)' 'false'
mutate dup-page-ok 'if text_eq(pool_ptr(pg_id[(p) as usize]), pool_ptr(id)) {' 'if false {'
mutate dup-field-ok 'if it_kind[(i) as usize] == K_FIELD && text_eq(' 'if false && text_eq('
mutate dup-field-global 'var i: u64 = pg_first[(n_pages - 1) as usize]' 'var i: u64 = 0'
mutate unknown-type-rejects '        warns = warns + 1
        return 1
    }
    var label: u64 = 0' '        return fail(E_ITEM, line)
    }
    var label: u64 = 0'
mutate unknown-word-rejects '    // unknown line word: skipped, counted
    warns = warns + 1
    return 1' '    return fail(E_ITEM, line)'
mutate reject-keeps-tables '        n_items = 0
        n_pages = 0
        return ERR' '        return ERR'
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
mutate item-limit 'if n_items >= MAX_ITEMS {' 'if n_items >= MAX_ITEMS + 1 {'
mutate page-limit 'if n_pages >= MAX_PAGES {' 'if n_pages >= MAX_PAGES + 1 {'
mutate pool-limit 'if pool_n + n + 1 > POOL_MAX {' 'if pool_n + n + 1 > POOL_MAX + 1000 {'
mutate default-lost 'def = put_word(4)' 'def = 0'
mutate bind-longer-key 'if same && e > at && rd(key, e - at) == 0 {' 'if same && e > at {'
mutate bind-index-skips '        ix = ix + 1
    }
    return NONE' '        ix = ix + 2
    }
    return NONE'
mutate col-ignored 'it_col[i] = cur_col' 'it_col[i] = 0'

echo "SETTINGSMAN: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
