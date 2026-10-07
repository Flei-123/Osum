#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/english/count.py -- COUNT THE GERMAN LEFT IN THE CODE, AND GUARD IT.

Rule (Justin, 07.10.2026): code is English -- identifiers, file names, program names, comments, log and
error texts, test names, commit messages. German lives in the user-facing catalogs (locale/) only.

What is counted, per file (tracked files only):

  ident    occurrences of identifiers with a German segment (code regions of .fi / .s files)
  comment  comment lines that read as German (stop words)
  logtext  string literals in .fi / .sh / .py that read as German and are NOT catalog keys
           (console / log / error texts; user texts come from locale/, not from literals)
  file     1 if the file name has a German segment (a program is a file in kernel/user)

and where it is not counted: locale/ (the catalogs), vendor/, generated data, binary files, the German word
list itself (tools/english/), and the files listed in tools/english/allow.txt (one path prefix per line,
`#` comments; every entry needs a reason on the line above it).

Modes:
  count.py                       print the totals and the 25 worst files
  count.py --json                the same as JSON (for project_metric and the baseline)
  count.py --check               compare with tools/english/baseline.json: a file may only get LESS German
                                 (a new file starts at zero); exit 1 and a list when something grew
  count.py --update              write the baseline (only ever lower than before unless --force)
  count.py --diff <base>         the NEW code guard: scan only the lines added since <base>
                                 (`git diff <base>`); exit 1 if an added line is German
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from dict import SEG          # noqa: E402
from firnlex import spans     # noqa: E402

# ---------------------------------------------------------------- the word lists
# German identifier segments: the renaming dictionary's keys that really are German (their English
# value differs), minus the ones that are also English words, plus what the audits found.
AMBIG = {"bin", "die", "was", "tag", "will", "man", "rest", "stand", "fest", "tut", "kon", "mit", "mal",
         "last", "laut", "typ", "ort", "nach", "alt", "frei", "voll", "eng", "roh", "kern", "wer", "von",
         "hin", "her", "bis", "sich", "rund", "fund", "punkt", "satz", "bund", "ende", "ganz", "aus",
         "auf", "bei", "das", "der", "ein", "eine", "oder", "und", "vor", "wie", "zu", "an", "im", "ob"}
EXTRA = {"zeiger", "breite", "hoehe", "gross", "groesse", "fenster", "schrift", "farbe", "knopf", "feld",
         "meldung", "pruefung", "laenge", "zaehler", "gerat", "geraet", "geraete", "papierkorb", "drucke",
         "dateiop", "dispctl", "praesenz", "tresor", "sperrwache", "netzmess", "kontocli", "auswerfen",
         "reiter", "krume", "baum", "ordner", "datei", "verzeichnis", "pfad", "sortiere", "zeile",
         "spalte", "tabelle", "leiste", "wahl", "zeig", "zeigt", "uebernehmen", "abbrechen", "einstellungen",
         "ausgabe", "eingabe", "gesperrt", "schluessel", "anmeldung", "konto", "benutzer", "passwort",
         "schreib", "lies", "fassung", "stufe", "stapel", "halde", "bereit", "fehler", "neu", "leer"}
GERMAN = ({k for k, v in SEG.items() if k != v and len(k) >= 3} | EXTRA) - AMBIG

# stop words of German prose (comments, log texts)
STOP = {"der", "die", "das", "und", "nicht", "ist", "ein", "eine", "einen", "einem", "einer", "wird", "werden",
        "wurde", "mit", "fuer", "für", "von", "zu", "zum", "zur", "den", "dem", "des", "auf", "bei", "aus",
        "wenn", "oder", "sich", "dass", "kein", "keine", "keiner", "nur", "auch", "noch", "wie", "als",
        "sind", "war", "hat", "haben", "kann", "muss", "soll", "es", "im", "am", "um", "nach", "vor", "über",
        "ueber", "unter", "weil", "damit", "dann", "oben", "unten", "alle", "jede", "jeder", "jedes", "gibt",
        "bleibt", "steht", "liegt", "dieser", "diese", "dieses", "man", "zwei", "drei", "vier", "ohne",
        "gegen", "durch", "schon", "mehr", "bis", "seit", "dort", "hier", "doch", "aber", "also"}
UMLAUT = re.compile("[äöüßÄÖÜ]")

CODE_EXT = {".fi", ".s", ".S", ".c", ".h", ".py", ".sh", ".js", ".ld", ".json", ".conf", ".txt", ".tsv",
            ".md", ""}
SKIP_PREFIX = ("locale/", "vendor/", "tools/english/", "docs/shots/", "docs/belege/", "docs/", "generated/",
               "assets/", "pkg/", "pakete/", "LICENSES/", "THIRD_PARTY", "0x")
SKIP_NAMES = {"LICENSE", "LICENSE.MIT", "LICENSE.MIT.old", "COPYING"}
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
WORD = re.compile(r"[A-Za-zÄÖÜäöüß]+")


def allowed(path, allow):
    return any(path.startswith(a) for a in allow)


def load_allow():
    p = os.path.join(HERE, "allow.txt")
    out = []
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            ln = ln.strip()
            if ln and not ln.startswith("#"):
                out.append(ln)
    return out


def segs(tok):
    s = re.sub(r"([a-z])([A-Z])", r"\1_\2", tok).lower()
    return [x for x in re.split(r"[_0-9]+", s) if len(x) >= 3]


def german_ident(tok):
    return any(x in GERMAN for x in segs(tok))


def german_text(s):
    """Prose test: two stop words, or one stop word and an umlaut, or a German identifier-like word pair."""
    if UMLAUT.search(s):
        return True
    ws = [w.lower() for w in WORD.findall(s)]
    if len(ws) < 3:
        return False
    hits = sum(1 for w in ws if w in STOP)
    if hits >= 2:
        return True
    return hits >= 1 and sum(1 for w in ws if w in GERMAN) >= 1


def catalog_like(s):
    # a literal that is a catalog key ("explorer.cmd") or a path / format, not prose
    return bool(re.fullmatch(r"[A-Za-z0-9_.\-/:%=\\ ]*", s)) and (" " not in s.strip() or "." in s)


def scan_fi(text):
    ident = 0
    comment = 0
    logtext = 0
    for kind, a, b in spans(text):
        seg = text[a:b]
        if kind == "code":
            for m in IDENT.finditer(seg):
                if german_ident(m.group(0)):
                    ident += 1
        elif kind == "cmt":
            for ln in seg.splitlines():
                if german_text(ln.lstrip("/* ").strip()):
                    comment += 1
        elif kind == "str":
            body = seg[1:-1]
            if " " in body and german_text(body) and not catalog_like(body):
                logtext += 1
    return ident, comment, logtext


def scan_script(text, ext):
    comment = 0
    logtext = 0
    for ln in text.splitlines():
        s = ln.strip()
        if s.startswith("#") and not s.startswith("#!"):
            if german_text(s.lstrip("# ")):
                comment += 1
        elif ext == ".py" and "#" in ln:
            c = ln.split("#", 1)[1]
            if german_text(c):
                comment += 1
        for m in re.finditer(r'(?:echo|print|say|bad|ok|info)\b[^"\']*["\']([^"\']{8,})["\']', ln):
            if german_text(m.group(1)):
                logtext += 1
    return 0, comment, logtext


def tracked():
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
    return out


def file_german(path):
    base = os.path.basename(path)
    stem = os.path.splitext(base)[0]
    # only the files that are programs, tests, tools and sources count as "named"; docs excluded above
    return 1 if any(x in GERMAN for x in segs(stem) + [s for s in re.split(r"[_.\-]", stem.lower()) if len(s) >= 3]) else 0


def scan_all():
    allow = load_allow()
    res = {}
    for path in tracked():
        if path.startswith(SKIP_PREFIX) or os.path.basename(path) in SKIP_NAMES or allowed(path, allow):
            continue
        ext = os.path.splitext(path)[1]
        if ext not in CODE_EXT:
            continue
        full = os.path.join(ROOT, path)
        try:
            if os.path.getsize(full) > 3_000_000:
                continue
            text = open(full, encoding="utf-8", errors="strict").read()
        except Exception:
            continue
        if ext in (".fi", ".s", ".S"):
            i, c, l = scan_fi(text) if ext == ".fi" else (0, scan_script(text.replace(";", "\n#"), ext)[1], 0)
        elif ext in (".py", ".sh", ".js", ".c", ".h"):
            i, c, l = scan_script(text, ext)
        else:
            i = c = l = 0
        f = file_german(path)
        if i or c or l or f:
            res[path] = {"ident": i, "comment": c, "logtext": l, "file": f}
    return res


def totals(res):
    t = {"ident": 0, "comment": 0, "logtext": 0, "file": 0}
    for v in res.values():
        for k in t:
            t[k] += v[k]
    t["files_with_german"] = len(res)
    return t


def weight(v):
    return v["ident"] + v["comment"] + v["logtext"] + 20 * v["file"]


def check(res):
    bp = os.path.join(HERE, "baseline.json")
    if not os.path.exists(bp):
        print("count.py: no baseline.json -- run --update first")
        return 1
    base = json.load(open(bp))["files"]
    bad = []
    for p, v in sorted(res.items()):
        b = base.get(p, {"ident": 0, "comment": 0, "logtext": 0, "file": 0})
        for k in ("ident", "comment", "logtext", "file"):
            if v[k] > b[k]:
                bad.append("%s: %s %d -> %d" % (p, k, b[k], v[k]))
    t = totals(res)
    if bad:
        print("GERMAN GREW (new code must be English; a file may only get LESS German):")
        for b in bad[:60]:
            print("  " + b)
        print("count.py: FAIL, %d place(s)" % len(bad))
        return 1
    print("count.py: OK -- identifiers %d, comment lines %d, log texts %d, german file names %d (%d files)"
          % (t["ident"], t["comment"], t["logtext"], t["file"], t["files_with_german"]))
    return 0


def update(res, force):
    bp = os.path.join(HERE, "baseline.json")
    old = json.load(open(bp))["files"] if os.path.exists(bp) else {}
    new = {}
    for p, v in res.items():
        o = old.get(p)
        if o and not force:
            v = {k: min(v[k], o[k]) for k in v}
        new[p] = v
    json.dump({"files": new, "totals": totals(res)}, open(bp, "w"), indent=0, sort_keys=True)
    print("baseline written: %s" % totals(res))
    return 0


def diff_guard(base):
    out = subprocess.run(["git", "diff", "-U0", base, "--", "."], cwd=ROOT, capture_output=True, text=True).stdout
    cur = None
    bad = []
    allow = load_allow()
    for ln in out.splitlines():
        if ln.startswith("+++ b/"):
            cur = ln[6:]
        elif ln.startswith("+") and not ln.startswith("+++") and cur:
            if cur.startswith(SKIP_PREFIX) or allowed(cur, allow):
                continue
            ext = os.path.splitext(cur)[1]
            if ext not in CODE_EXT:
                continue
            body = ln[1:]
            hit = None
            if ext == ".fi" or ext == ".s":
                i, c, l = scan_fi(body)
                if i:
                    hit = "identifier"
                elif c:
                    hit = "comment"
                elif l:
                    hit = "text"
            else:
                i, c, l = scan_script(body, ext)
                if c or l:
                    hit = "comment/text"
            if hit:
                bad.append("%s: %s: %s" % (cur, hit, body.strip()[:110]))
    for p in subprocess.run(["git", "diff", "--name-status", "--diff-filter=A", base], cwd=ROOT,
                            capture_output=True, text=True).stdout.splitlines():
        path = p.split("\t")[-1]
        if not path.startswith(SKIP_PREFIX) and not allowed(path, allow) and file_german(path):
            bad.append("%s: new file with a German name" % path)
    if bad:
        print("count.py --diff: GERMAN IN NEW CODE (%d):" % len(bad))
        for b in bad[:80]:
            print("  " + b)
        return 1
    print("count.py --diff: OK -- the lines added since %s are English" % base)
    return 0


def main():
    a = sys.argv[1:]
    if a and a[0] == "--diff":
        return diff_guard(a[1] if len(a) > 1 else "origin/main")
    res = scan_all()
    if "--check" in a:
        return check(res)
    if "--update" in a:
        return update(res, "--force" in a)
    t = totals(res)
    if "--json" in a:
        print(json.dumps({"totals": t}))
        return 0
    print("German left in code: identifiers %d, comment lines %d, log texts %d, german file names %d, files %d"
          % (t["ident"], t["comment"], t["logtext"], t["file"], t["files_with_german"]))
    for p, v in sorted(res.items(), key=lambda kv: -weight(kv[1]))[:25]:
        print("  %6d  %s  (ident %d, comment %d, text %d, name %d)" % (weight(v), p, v["ident"], v["comment"],
                                                                     v["logtext"], v["file"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
