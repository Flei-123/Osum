#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/certus/quoten.sh -- DIE DREI QUOTEN VON CERTUS, SELBST NACHGEMESSEN.
#
# Die Runde CERTUS haette die Zahlen aus den Firn-Rundenprotokollen
# abschreiben koennen. Sie tut es nicht: die drei Pruefstaende, die den
# Motor gegen FREMDE Testsammlungen messen, werden hier noch einmal
# gefahren, mit dem festgenagelten Uebersetzer aus vendor/firn.
#
#   1. HTML   -- die offizielle html5lib-Baumbau-Sammlung (1936 Faelle,
#                aus web-platform-tests), ungefiltert.
#   2. LAYOUT -- die offiziellen Web Platform Tests, Korpus B2
#                (186 Dateien aus css/css-flexbox, css/CSS2, css/css-box,
#                css/css-sizing, css/css-position, css/css-align).
#   3. JS     -- test262 von tc39, die repraesentative Stichprobe, mit der
#                auch `tools/js/run.sh --fast` misst. Ein Fall, der eine
#                Sprachfunktion braucht, die es nicht gibt, zaehlt als
#                FEHLER wie jeder andere; nichts wird herausgefiltert.
#
# Aufruf:  bash tools/certus/quoten.sh <firn-baum> [ausgabe.json]
#
# <firn-baum> ist ein AUSGEPACKTER Firn-Commit MIT SYMBOLISCHEN VERWEISEN
# (git archive | tar -x). Nicht vendor/firn/lib -- dort hat `cp -rL` die
# neun Verweise aufgeloest, und lib/std/rt.fi und lib/rt/rt.fi sind
# seitdem zwei Dateien mit demselben Modulnamen. Der Uebersetzer bricht
# darauf mit 40 Fehlern ab; das ist in docs/CERTUS-STATUS.md vermerkt.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

FIRN=${1:-}
AUS=${2:-$ROOT/.certus-work/quoten.json}
[[ -d ${FIRN}/lib ]] || { echo "Firn-Baum fehlt: $FIRN" >&2; exit 1; }
FIRNC=$ROOT/vendor/firn/bin/firnc
[[ -x $FIRNC ]] || { echo "Uebersetzer fehlt: $FIRNC" >&2; exit 1; }

W=$ROOT/.certus-work/quoten
mkdir -p "$W"
export FIRNLIB="$FIRN/lib"

echo "== 1. die drei Treiber uebersetzen =="
"$FIRNC" -o "$W/b1parse" "$FIRN/lib/browser/parse_main.fi" 2>"$W/b1.log" \
    && echo "   b1parse  ok" || { echo "   b1parse  FEHLER"; tail -3 "$W/b1.log"; }
"$FIRNC" -o "$W/b2" "$FIRN/lib/layout/b2_main.fi" 2>"$W/b2.log" \
    && echo "   b2       ok" || { echo "   b2       FEHLER"; tail -3 "$W/b2.log"; }
"$FIRNC" -o "$W/jsrun" "$FIRN/lib/js/run_main.fi" 2>"$W/js.log" \
    && echo "   jsrun    ok" || { echo "   jsrun    FEHLER"; tail -3 "$W/js.log"; }

cd "$FIRN"

echo "== 2. HTML: die html5lib-Baumbau-Sammlung, ungefiltert =="
python3 tools/domb1/harness.py "$W/b1parse" --json "$W/html.json" \
    2>&1 | tail -5

echo "== 3. LAYOUT: die Web Platform Tests, Korpus B2 =="
python3 tools/layoutb2/harness.py "$W/b2" --json "$W/layout.json" \
    2>&1 | tail -12

echo "== 4. JS: test262, die repraesentative Stichprobe =="
if [[ ! -d $W/t262/test ]]; then
    mkdir -p "$W/t262"
    tar xzf testdata/test262/test262-subset.tar.gz -C "$W/t262"
fi
export T262="$W/t262"
SAMPLE="language/types language/asi language/block-scope language/literals \
language/white-space language/line-terminators language/comments \
language/punctuators language/reserved-words language/keywords \
language/rest-parameters language/destructuring built-ins/Math \
built-ins/JSON built-ins/Boolean built-ins/NativeErrors"
python3 - "$W" $SAMPLE <<'PY'
import json, os, subprocess, sys
work, dirs = sys.argv[1], sys.argv[2:]
tot = passed = 0
reasons = {}
for d in dirs:
    out = os.path.join(work, "r_%s.json" % d.replace("/", "_"))
    subprocess.run(["python3", "tools/js/harness_run.py",
                    os.path.join(work, "jsrun"), "--dir", "test/" + d,
                    "--json", out], stdout=subprocess.DEVNULL)
    try:
        j = json.load(open(out))
    except Exception:
        continue
    tot += j["total"]; passed += j["passed"]
    for k, v in j.get("reasons", {}).items():
        reasons[k] = reasons.get(k, 0) + v
json.dump({"total": tot, "passed": passed, "failed": tot - passed,
           "reasons": reasons}, open(os.path.join(work, "js.json"), "w"))
print("   Faelle   : %d" % tot)
print("   bestanden: %d" % passed)
print("   Quote    : %.2f%%" % (100.0 * passed / tot if tot else 0))
for k in sorted(reasons, key=lambda x: -reasons[x]):
    print("      %-22s %6d" % (k, reasons[k]))
PY

python3 - "$W" "$AUS" <<'PY'
import json, os, sys
w, aus = sys.argv[1], sys.argv[2]
out = {}
for name, f in (("html", "html.json"), ("layout", "layout.json"),
                ("js", "js.json")):
    p = os.path.join(w, f)
    if os.path.exists(p):
        try:
            out[name] = json.load(open(p))
        except Exception as e:
            out[name] = {"fehler": str(e)}
os.makedirs(os.path.dirname(aus), exist_ok=True)
json.dump(out, open(aus, "w"), indent=2)
print("geschrieben: " + aus)
PY
