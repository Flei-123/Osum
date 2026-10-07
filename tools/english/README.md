# tools/english -- the German->English renaming of the source tree

WHY THIS DIRECTORY EXISTS. OrientOS grew up German: `breite`, `hoehe`, `laden`,
`sichern`, `mal_balken`. The kernel is meant to be read by people who do not
speak German, so the identifiers become English. The comments follow in a
separate pass; the reasoning they carry is the most valuable part of this
project and is translated in full, not shortened.

WHAT IS RENAMED, AND WHAT IS NOT. ONLY identifiers in the source text. NOT
string literals, NOT file formats, NOT configuration keys, NOT device files.
`marke.conf` keeps its name on disk, `/etc/taskbar.conf` keeps its name, and a
German word inside a `"..."` stays exactly as it is. `firnlex.py` splits every
`.fi` file into code / string / comment regions and the renamer writes to the
code regions only; every file is checked afterwards, and the run aborts if a
single string or comment byte moved.

THE FIVE TRAPS, found in the dry run, each of which broke the build:

  1. A file-scoped rename must also follow the `module.name(` call sites in
     OTHER files and the module's `export { }` list. 84 such places.
  2. Order: the qualified pass runs BEFORE the plain identifier pass. Otherwise
     `bild.breite` has already become `image.breite` and no longer matches.
  3. `error` and `true` are RESERVED WORDS in Firn. `fehler` and `wahr` cannot
     take them; they became `err` and `is_true`. Every new name is tested
     against the real compiler before use.
  4. File renames come LAST. The per-file map is keyed on the old path, so
     renaming `zeiger.fi` first leaves its own `groesse` untranslated.
  5. The tools rename with the code. `tools/check-ui.sh` hardcodes function
     names in its allowlist; if they are not renamed too, the check fails.

GENERIC NAMES. `laden`, `sichern`, `breit`, `hoehe`, `mal` are declared in more
than one file. They are renamed ONLY inside the file that owns them, plus that
module's qualified call sites -- never globally, or the rename reaches into a
foreign module.

  tools/english/apply.py            the renamer (--apply to write)
  tools/english/modrename.py        module/file renames
  tools/english/firnlex.py          code/string/comment splitter
  tools/english/rename_final.tsv    the table: old -> new, scope, declaring files

## THE GUARD (07.10.2026, standing rule of Justin)

Code is English: identifiers, file names, program names, comments, log / error texts, test names, commit
messages. German lives in the catalogs (`locale/`) only. New code is English from the first line.

  tools/english/count.py            count what is left (identifiers, comment lines, log texts, German file names)
  tools/english/count.py --check    fail when any file got MORE German than `baseline.json`
  tools/english/count.py --update   lower the baseline (it only ever goes down, `--force` to raise)
  tools/english/count.py --diff B   fail when a line ADDED since commit B is German (new code guard)
  tools/english/run.sh              the three checks as one acceptance section (test.sh section 58)
  tools/english/allow.txt           path prefixes where German is allowed, every entry with its reason

Stages (each a small merge, nothing stored is broken -- formats, files on disk and the wire keep their names or
get an alias): 1. program names / CLI (old names stay as aliases for the bridge), 2. identifiers (the renamer
above), 3. file names, 4. comments (translated, not shortened), 5. log texts.
