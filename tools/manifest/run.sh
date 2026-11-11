#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
O="python3 tools/sdk/osdk.py"
SCHEMA=docs/manifest-v2.schema.json

echo "== 1. every shipped INFO passes --strict --system =="
n=0; badn=0
for f in assets/apps/*/INFO pakete/*/INFO; do
    n=$((n+1)); $O check "$f" --strict --system >/dev/null 2>&1 || { badn=$((badn+1)); echo "     refused: $f"; }
done
[ "$badn" = 0 ] && [ "$n" -ge 27 ] && ok "$n INFO files strict-clean" || bad "$badn of $n INFO files refused"

echo "== 2. template, all kinds =="
for k in gui app service; do
    $O new org.example.t$k --kind $k --dir "$TMPD/$k" --author Tester >/dev/null 2>&1 && $O check "$TMPD/$k" --strict >/dev/null 2>&1 && ok "kind $k: new + check --strict" || bad "kind $k"
done
$O new org.example.tweb --kind gui --outputs native,web --dir "$TMPD/web" --author Tester >/dev/null 2>&1 && $O check "$TMPD/web" --strict >/dev/null 2>&1 && ok "outputs native,web with symbol.svg" || bad "web template"
$O new org.example.tsw --kind service --outputs native,web --dir "$TMPD/sw" >/dev/null 2>&1 && bad "service with web output accepted" || ok "service + web refused at new"

echo "== 3. counter-probes: each mutation refused for the right reason =="
mut() {
    rm -rf "$TMPD/m"; cp -r "$TMPD/web" "$TMPD/m"; sed -i "$1" "$TMPD/m/INFO"
    out=$($O check "$TMPD/m" --strict 2>&1); rc=$?
    if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$2"; then ok "refused: $2"; else bad "not refused for '$2' ($1)"; fi
}
while IFS='|' read -r sedx want; do mut "$sedx" "$want"; done <<'EOT'
s/^kind=.*/kind=wizard/|kind 'wizard'
s/^outputs=.*/outputs=desktop/|outputs 'desktop'
s/^outputs=.*/outputs=web,web/|without duplicates
s/^outputs=.*/outputs=native/;$a web.entry=app.wasm|needs outputs to contain web
$a web.entry=../x.wasm|web.entry
$a web.font=font.otf|web.font
$a web.memory=99999|web.memory
$a web.memory=8|web.memory
s/^perm=.*/perm=hotkey/|has no web backend
s/^perm=.*/perm=files.write/|unknown permission 'files.write'
s/^perm=.*/perm=dialog,dialog/|permission 'dialog' twice
s/^perm=.*/perm=notify/|has no web backend
$a menu=maybe|menu: show|hidden
$a icon=../x.svg|icon
s/^author=.*/author=/|missing or empty key 'author'
/^kind=/d|missing or empty key 'kind'
/^outputs=/d|missing or empty key 'outputs'
s/^revision=/fassung=/|legacy key 'fassung'
EOT
rm -rf "$TMPD/nosvg"; cp -r "$TMPD/web" "$TMPD/nosvg"; rm -f "$TMPD/nosvg/symbol.svg"; out=$($O check "$TMPD/nosvg" 2>&1); echo "$out" | grep -qF "needs an SVG icon" && ok "web output without symbol.svg refused" || bad "web without svg accepted"
rm -rf "$TMPD/m"; cp -r "$TMPD/service" "$TMPD/m"; sed -i 's/^kind=.*/kind=gui/' "$TMPD/m/INFO"
out=$($O check "$TMPD/m" 2>&1); echo "$out" | grep -qF "service= is declared but kind=gui" && ok "service= with kind=gui refused" || bad "service/kind mismatch accepted"
rm -rf "$TMPD/m"; cp -r "$TMPD/service" "$TMPD/m"; sed -i '/^service=/d' "$TMPD/m/INFO"
out=$($O check "$TMPD/m" 2>&1); echo "$out" | grep -qF "kind=service needs a service=" && ok "kind=service without service= refused" || bad "kind=service without bus name accepted"

echo "== 4. compatibility: old v1 INFO =="
printf 'name=Old\ninfo=An old app\nkeys=old\nfassung=3\nmanifest=2\nid=org.example.old\nversion=1.2.3\n' > "$TMPD/oldinfo"
$O check "$TMPD/oldinfo" >/dev/null 2>&1 && ok "old keys (fassung, no kind/outputs) accepted by default" || bad "old INFO refused by default"
$O check "$TMPD/oldinfo" --strict >/dev/null 2>&1 && bad "old INFO accepted by --strict" || ok "old INFO refused by --strict"
mkdir -p "$TMPD/mig/old.osp"; cp "$TMPD/oldinfo" "$TMPD/mig/old.osp/INFO"
$O migrate "$TMPD/mig/old.osp/INFO" --write >/dev/null 2>&1
sed -i 's/^id=.*/id=com.fleitec.old/;s/^version=.*/version=1.2.3/' "$TMPD/mig/old.osp/INFO"
$O check "$TMPD/mig/old.osp/INFO" --strict --system >/dev/null 2>&1 && ok "migrate makes an old INFO strict-clean" || bad "migrated INFO refused"
before=$(sha256sum "$TMPD/mig/old.osp/INFO"); $O migrate "$TMPD/mig/old.osp/INFO" --write >/dev/null 2>&1; [ "$before" = "$(sha256sum "$TMPD/mig/old.osp/INFO")" ] && ok "migrate is idempotent" || bad "migrate changed a migrated INFO"
grep -q '^revision=3' "$TMPD/mig/old.osp/INFO" && ok "fassung became revision (value kept)" || bad "fassung not converted"

echo "== 5. normalized JSON against the schema =="
python3 -I - "$SCHEMA" "$TMPD" <<'EOP' && ok "all manifests validate; schema mutants rejected" || bad "schema check"
import json, subprocess, sys, glob, copy
import jsonschema
schema = json.load(open(sys.argv[1]))
jsonschema.Draft202012Validator.check_schema(schema)
v = jsonschema.Draft202012Validator(schema)
paths = sorted(glob.glob("assets/apps/*/INFO") + glob.glob("pakete/*/INFO")) + [sys.argv[2] + "/web/INFO"]
last = None
for p in paths:
    flag = [] if p.startswith(sys.argv[2]) else ["--system"]
    out = subprocess.run(["python3", "tools/sdk/osdk.py", "manifest", p] + flag, capture_output=True, text=True)
    if out.returncode:
        sys.exit("manifest failed for %s: %s" % (p, out.stdout))
    m = json.loads(out.stdout)
    errs = list(v.iter_errors(m))
    if errs:
        sys.exit("%s: %s" % (p, errs[0].message))
    last = m
mutants = [lambda m: m.pop("id"), lambda m: m.update(kind="wizard"), lambda m: m["permissions"].append("root"),
           lambda m: m.update(outputs=["web"]) or m.pop("web", None), lambda m: m.update(extra=1),
           lambda m: m["web"].update(memory_mib=1)]
for mut in mutants:
    c = copy.deepcopy(last)
    mut(c)
    if not list(v.iter_errors(c)):
        sys.exit("schema accepted a mutant")
EOP

echo "== 6. services mapping and page output =="
rm -rf "$TMPD/p"; cp -r "$TMPD/web" "$TMPD/p"; $O new org.example.tweb --kind gui --outputs native,web --dir "$TMPD/p2" --author T --perm files.open,clipboard.write,net >/dev/null 2>&1
j=$($O manifest "$TMPD/p2")
echo "$j" | python3 -c "import json,sys;m=json.load(sys.stdin);assert m['services']==['clipboard.write','file.open'],m['services'];assert m['web']['capabilities']==['services','fetch'];assert m['native']['net']=='real'" && ok "perm -> services calls and web capabilities" || bad "mapping wrong"
pg=$($O manifest "$TMPD/p2" --format page); echo "$pg" | grep -qF 'name="firn-capabilities" content="services,fetch"' && echo "$pg" | grep -qF 'rel="application" type="application/wasm" href="app.wasm"' && ok "page: capabilities meta + application link" || bad "page output"
$O manifest "$TMPD/gui" --format page >/dev/null 2>&1 && bad "page for a native-only app" || ok "page refused without web output"

echo "== 7. store index =="
python3 tools/sdk/storeindex.py assets/apps pakete --system --out "$TMPD/idx.json" 2>"$TMPD/idx.err" && python3 -c "
import json,sys
d=json.load(open('$TMPD/idx.json'));p=d['packages']
assert d['schema']=='orientos.store-index/2' and len(p)>=27
assert [x['id'] for x in p]==sorted(x['id'] for x in p)
assert any(x['id']=='com.fleitec.mail' and x['kind']=='gui' and x['permissions']==['net'] for x in p)
assert any(x['id']=='com.fleitec.xremote' and x['kind']=='app' for x in p)" && ok "index of $(python3 -c "import json;print(len(json.load(open('$TMPD/idx.json'))['packages']))") packages, sorted, new keys emitted" || bad "index"
mkdir -p "$TMPD/dup/a.osp" "$TMPD/dup/b.osp"; cp "$TMPD/mig/old.osp/INFO" "$TMPD/dup/a.osp/INFO"; cp "$TMPD/mig/old.osp/INFO" "$TMPD/dup/b.osp/INFO"
python3 tools/sdk/storeindex.py "$TMPD/dup" --system >/dev/null 2>&1 && bad "duplicate id accepted" || ok "duplicate id refused"
python3 tools/sdk/storeindex.py "$TMPD/mig" --system --opk "$TMPD" --require-files >/dev/null 2>&1 && bad "missing package file accepted" || ok "missing package file refused with --require-files"
head -c 100 /dev/urandom > "$TMPD/old-1.2.3.opk"
python3 tools/sdk/storeindex.py "$TMPD/mig" --system --opk "$TMPD" > "$TMPD/fi.json" && grep -q '"sha256"' "$TMPD/fi.json" && ok "package file hash and size attached" || bad "no file hash"

echo "MANIFEST: $pass passed, $fail failed"
[ "$fail" = 0 ]
