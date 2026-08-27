# ORPHANS.md -- the one kind of program a backup has to carry

*Round TRESOR, addendum of 27.08.2026. Every number here comes from a run
of `tools/tresor/run.sh` § 11.*

This document is the contract between two programs in two repositories:
`opk` in the OrientOS tree, which knows which packages could be fetched
again, and `/bin/backup` in Osum, which stores octets. It exists because
neither of them can answer the question alone.

---

## 1. Three rules, and nothing else

A backup of this system obeys exactly three rules. There is no fourth,
and no special case hiding under one of them.

| # | rule | what it covers | why |
|---|---|---|---|
| **1** | **ALWAYS backed up** | `PLAN`, `system/secrets/`, `users/<who>/config/`, `users/<who>/state/` | this is the work and the credentials. Nothing else on the machine can produce it. |
| **2** | **NEVER backed up** | `store/` entries a source can deliver, `apps/`, `etc/`, `users/<who>/cache/` | every one of these is an *output*: derived from the PLAN, or derived from use. Storing it would be storing something that is already safe somewhere else. |
| **3** | **ONLY IF ORPHANED** | `store/<entry>` for a package **no registered source can deliver** | the argument for rule 2 is that the octets can be fetched again. Where that is false, rule 2 is false with it, and only there. |

Rule 3 is not a loophole in rule 2 — it is the precondition of rule 2
made explicit. Rule 2 never said "programs are not valuable"; it said
"programs are reachable". A package that is not reachable was never
covered by it.

Measured on the tree in § 11 of the runner: rule 2 keeps about 99 % of the
disk out of the backup (`docs/BACKUP.md` § 2, PLAN2's measurement: backup
set 44 076 of 3 571 511 octets, 1.23 %). Rule 3 adds back only what is
genuinely irreplaceable, and § 4 below is what that costs.

---

## 2. The question, stated precisely

> **Which store entries would a rebuild on a NEW machine be unable to
> fetch, given this PLAN and these sources?**

Note what the question is *not*. It is not "which packages did I build
myself" — that is a claim about history, and history is not what breaks a
restore. Reachability **now** is:

* a package built here and later published becomes reachable, and drops
  off the list by itself;
* a package that came from a source which has since dropped it becomes
  orphaned, and appears on the list.

A "built locally" flag would get both of those wrong, and would get them
wrong silently.

---

## 3. The interface

A plain text file. No header, no comments, no ordering requirement.

```
8c3851919b9fcd2a889d
a1b2c3d4e5f60718293a
```

* **One store entry name per line**, `\n` terminated. That is a
  *directory name under `store/`* — not a full hash. Today `opk` makes it
  the first `KURZ = 20` hex digits of the package's SHA-256.
* **Lower case hex only.** `backup` refuses anything else, and that check
  is load-bearing: it is what stops `../..` or an absolute path from ever
  reaching the filesystem, so a broken or hostile list cannot make the
  backup walk out of the store and swallow the rest of the disk.
* **16 to 64 digits.** Deliberately a range, not a constant, so `opk` may
  change its shortening rule without `backup` needing to be changed with
  it.
* **Empty lines are skipped.** An **empty file** means nothing is
  orphaned, and is *not* an error — it is the normal case on a machine
  whose packages all come from a source.
* **A name whose store entry is missing is an error**, and a loud one.
  `backup save` fails and says which entry. A backup that silently
  skipped the one thing it existed to carry would be worse than no
  backup.

### Why a name and not a hash

`backup` treats the line as an opaque path component. The shortening rule
lives in `opk`, which owns it. If `backup` recomputed it, a change on that
side would break backups on this side — silently, and only noticed on the
day somebody needed a restore.

### Who produces it

`opk`, because it is the only program that knows which sources are
registered and what they hold. Round PLAN2 is adding the subcommand.
Until it lands, `tools/tresor/orphans.py` is the reference producer: it
imports the real `opk.py` and uses its own `Wurzel`, `Plan.hashes()`,
`quelle_lesen()` and `kurz()`, so it cannot drift from how the package
manager actually thinks.

Verified against a real tree with one published and one self-built
package:

```
$ python3 tools/tresor/orphans.py --root /tmp/orph/root --source /tmp/orph/src
8c3851919b9fcd2a889d
2 package(s) in the plan, 1 source(s), 1 ORPHANED
   8c3851919b9fcd2a889d  8c3851919b9fcd2a...  mine
```

The published package `hallo` is correctly absent. When `opk orphans`
exists, this script becomes the cross-check rather than the source, and
the two outputs should be asserted equal.

### How it is consumed

```
backup save <set> <store> <name> [orphans [tree]]
```

* `<set>` is the backup set — rule 1. It is walked in full.
* `[orphans]` is the file above.
* `[tree]` is the tree whose `store/` the entries live under. It defaults
  to `<set>`, and is a separate argument because the backup set and the
  store are deliberately *not* the same directory.

Each listed entry is walked at `<tree>/store/<name>` and lands in the
snapshot under `/store/<name>` — the path a restore has to put it back
at. It goes into the **same** pack and the **same** snapshot as everything
else, so it deduplicates against the rest of the backup and `restore`,
`get` and `verify` need to know nothing about orphans at all.

---

## 4. What the exception costs, measured

From `tools/tresor/run.sh` § 11: the same backup set, saved twice into two
fresh stores, once without an orphan list and once with one. The set is
sized to match the real one PLAN2 measured (44,076 octets), so the
percentage is comparable to a real machine rather than to a toy.

| run | orphan entries | octets written |
|---|---:|---:|
| no orphan list | 0 | 43,092 |
| with one orphan | **1** | **72,220** |

**+29,128 octets, +67.6 %** for one 29,104-octet program and its 24-octet
`PAKET` metadata.

That is the honest shape of the trade, and it is not flattering: a single
self-built program can be two thirds again the size of everything else
worth keeping. It is still the right call. The alternative is not a
smaller backup — it is a restore that stops at a hash nobody can resolve,
and a program that is simply gone.

It also shows why rule 3 must stay *narrow*. Applied to every package
instead of only the unreachable ones, the same backup would carry the
whole store and the 1.23 % figure of rule 2 would collapse.

The runner asserts three things about the cost, rather than describing it:

1. `orphan entries` is **0** without a list and **1** with one;
2. the growth in `written bytes` equals the reported `orphan bytes`
   **exactly** — so the extra octets are all accounted for and nothing
   else changed;
3. an empty list costs **0**.

### The proof that it actually works

The convincing test is not a restore on the machine that made the backup —
that machine still has the package. So the runner builds a **second disk
image that contains only the backup store**: no tree, no backup set, no
package. The octets cannot come from anywhere but `PACK`.

On that machine:

* `backup restore` rebuilds the tree, `backup verify` reports `corrupt: 0`;
* the restored `/out/store/<entry>/start` is **executed**, and prints its
  line — which also proves `restore` applies the mode, because a program
  without its execute bit is a file, not a program;
* the host reads the restored file **out of the disk image** and compares
  it with the original: byte for byte identical.

### A gap this addendum closed

`restore` recorded the mode in the snapshot and then dropped it on the way
back — H6 claimed "the mode is kept" and only half of it was true. Nobody
had noticed because nothing restored before had needed to *run*. It now
calls `chmod` (syscall 90) for files and directories, with the permission
bits masked off the type bits.

---

## 5. What this side does not check, and why

`backup` does **not** verify that a listed entry really is unreachable. It
cannot: it has no source list, no network, and no opinion about what a
source is. It stores what it is told to store.

A wrong list therefore costs one of two things:

* an entry that was reachable after all — wasted space, and nothing worse;
* an entry left off the list — a program that is gone after a restore.

Both faults belong to the producer, which is the side that has the
information. What this side *does* enforce is the shape of every line and
the existence of every entry, so that a typo cannot pass silently.
