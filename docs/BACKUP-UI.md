# BACKUP-UI.md -- backing up from the file manager

*Round TRESOR, second addendum, 27.08.2026. Every number here comes from
a run of `tools/tresor/run.sh` § 12.*

---

## 1. What the owner asked for

> Plug in a USB stick, go into it in the file manager, say "save a backup
> here" -- done.

That is the whole requirement, and it is the right one. The second
question was whether that produces "a backup file, a ZIP or something".

**It does not, and that is the interesting part.** What appears on the
stick is a **directory**. The rest of this document is why, because the
answer carries the whole design.

---

## 2. Why not one file

A single archive is the obvious shape and the wrong one. Three reasons,
and all three are measured rather than argued:

### A lump cannot share

Back the same tree up twice into a ZIP and you have two ZIPs of the full
size. Do it daily for a month and you have thirty. Here every snapshot
shares its blocks with every other one:

| | octets written |
|---|---:|
| first backup of the tree | 45,056 |
| **second backup, nothing changed** | **0** |

Not "a bit less". **Zero.** The second run reads all 44,384 octets again
and writes nothing, because it asks "do I already have these octets" and
the hash answers. There is no change journal and no timestamp to be wrong
about.

### A lump cannot be partially rewritten

Change one octet inside a large file in a ZIP and the archive is written
again from the start. Here:

| | new blocks | octets written |
|---|---:|---:|
| the tree, first time | 11 | 45,056 |
| **one octet changed in a 16,384-octet file** | **1** | **4,096** |

**11× less written for a one-octet edit.** Only the 4,096-octet block
that actually contains the changed octet is new.

### A lump cannot be browsed cheaply

Every snapshot here is a **text file** listing paths and the blocks they
are made of. So the file manager can show a snapshot as a folder and pull
**one file** out of it without unpacking anything. That is § 5, and it is
the part that actually gets used.

### Deduplication is not just between backups

The same file in three different folders:

| | |
|---|---:|
| blocks seen | 6 |
| **blocks that were new** | **2** |
| octets read | 24,576 |
| **octets written** | **8,192** |

One copy on the disk, three names in the snapshot.

### Who else does it this way

Apple's Time Machine is a directory of shared files, not a growing image
-- the same idea. Windows' "Backup" writes a lump, which is why it is
slow, why the second one takes as long as the first, and why nobody uses
it twice. This is not a novel design; it is the one that works.

---

## 3. What is actually on the stick

```
<the folder you pointed at>/
    PACK               every distinct block, appended
    INDEX              one line per block: <hash> <offset> <length>
    S-sicherung1       a snapshot: a text file, complete in itself
    S-sicherung2       another one, sharing all of PACK
```

A snapshot reads like this:

```
backup1 4096 2026-08-27 09:14:22
/a.txt      100644  20000  3f2a...,9c11...,...
/sub        40755   0      -
/sub/c.txt  100644  8000   77de...
end         3       44384
```

**The date is real.** It comes from the CMOS clock through `SYS_SYSINFO`,
the same source `/bin/date` reads. The *files* have no timestamps in this
filesystem (an OFS inode has nowhere to put one -- `kernel/fs.fi`), but
the snapshot does, and "which one is from last week" is the question
people actually ask of a backup. This is also why the file manager's
"Zeit" column, empty since round K15, finally has something to show.

**The `end` line is the safety.** See § 6.

---

## 4. Making a backup

Right-click a directory or a mounted volume → **"Backup hierhin
sichern"**.

* If there is **no** store there yet, it asks once: *"Hier ein Backup
  anlegen?"*
* If there **is** one, it does not ask and does not put a second store
  next to the first -- it adds **another snapshot** into the existing one.
  That is the whole point: snapshot two costs almost nothing.

While it runs, the dialog shows **files, octets, and how many of those
octets were new**:

```
Dateien: 24  Oktette: 44384  neu: 4096
```

The **"neu"** number is the one worth watching. On the second run it is
small, and the user can see it -- that is the visible difference between
this and a ZIP that starts from nothing every time.

At the end the same line becomes the summary, and the run also reports
on the serial line so it can be measured rather than admired:

```
explorer: backup ziel=/sicherung name=sicherung1 dateien=3 oktette=44384 neu=45056 rc=0
```

**What gets backed up is `/data`**, and that is stated here rather than
buried: the target you point at is where it is *written*, not what is
*read*.

---

## 5. Getting things back

This is the part that matters, and it is deliberately not a big "restore"
button.

Go **into** a backup directory in the file manager. It does not show you
`PACK` and `INDEX` -- it shows the **snapshots**, with the date they were
taken, how many files they hold and how big they are. That is view 1.

Go into a snapshot and you are in view 2: **the files, as folders and
files, exactly as they were**. You can walk down into subdirectories the
way you walk down anywhere else. Right-click → **"Zurueckholen"** brings
back either one file (in a snapshot) or a whole snapshot (in the list).

So "this one file from last week" is an ordinary copy, not a
production. Restored things land in **`/data`** -- a fixed, stated
destination, because inside a snapshot there is no "here" on the disk to
put them.

Renaming and deleting are not offered inside a snapshot: there is no file
there, only a line in a text file. Offering buttons that cannot work is
worse than not offering them.

---

## 6. Honest limits

These are limits of the system today, not of the design, and they are
listed because finding them out during a restore would be the worst
possible time.

* **OFS still has a 2 MiB cap per volume.** Round OFS3 is lifting it. A
  backup onto a **FAT32 stick works today** (`kernel/fat.fi` writes, 2007
  lines); an *OFS* backup is pointlessly small until OFS3 lands.
* **No network backup.** TLS is not finished in this tree (round Certus
  B6 is on it), and a backup transport that cannot be trusted with the
  octets is not a backup transport. **A stick or a second disk, and
  nothing else.** The seam is a path, so adding a network target later is
  a small job.
* **No encryption of the store.** What that means for a stolen backup
  stick is in `docs/CRYPTO-ERASE.md`, and it is not comfortable.
* **The window does not accept input while a backup runs.** Progress is
  drawn, but the run is synchronous -- there is no Cancel button, because
  a button that is drawn and cannot be clicked is a lie. The *mechanism*
  for stopping is there (the progress hook can stop the run) and the
  cleanup path it uses is the same one a failure uses, which is tested.
* **Fixed 4096-octet blocks.** Append to a file and one block changes;
  insert at the front and every block after it is new. Measured at its
  worst in `docs/THEFT.md` § 6. Content-defined chunking is the fix and
  is not in this round.
* **At most 1024 distinct blocks per run** (4 MiB of distinct data), and
  directory nesting at most 8 deep. The program says so and fails rather
  than writing a store it cannot describe.

### When the disk fills up

This one is not a limit but a promise, and it is the reason for the `end`
line and the `T-` file:

1. blocks go into `PACK` first;
2. the snapshot is written under a **temporary name** `T-<name>`;
3. `INDEX` is extended only after the blocks are really in `PACK`;
4. `S-<name>` appears **last**, and only if everything before it worked.

A run that dies anywhere leaves some octets in `PACK` that nothing points
at -- wasted space, and a head start for the next run, since the index
finds them again by their hashes -- plus possibly a `T-` file, which no
reader looks at. **It never leaves an `S-` that promises octets that were
never written.**

And even if one somehow survived, it would have no `end` line, and
`restore`, `verify` and the snapshot list all refuse a snapshot without
one. Measured: after a run that fails half way, the store contains **no
`S-` file and no `T-` file**, the listing is empty, and a restore attempt
says there is no such snapshot -- all three checked against the disk
image, not against the program's own claims.

This kernel has no `rename` (round K11 said so and it is still true), so
step 4 is a copy of a small text file followed by an unlink rather than a
rename. If that copy fails, the half-written `S-` is removed again.

---

## 7. What is measured, and what is not

This matters more than the rest of the document, so it is not at the
bottom by accident -- it is here because the next person to touch this
needs to know exactly how far the ground is solid.

**Measured, 148 assertions in `tools/tresor/run.sh`:**

* the store itself -- deduplication within a backup and between backups,
  the zero-octet second run, the 11× cheaper one-octet edit;
* restore of a single file and of a whole tree, compared **octet for
  octet out of the disk image**, not against the program's own claims;
* the incomplete-snapshot guarantee: after a run that fails half way, the
  store holds **no `S-` file and no `T-` file**, the listing is empty, and
  a restore attempt is refused.

**Built and compiling, but NOT measured end to end:**

* **the context menu entry itself.** `tools/tresor/gui.sh` boots the
  window server and the file manager, reads their reported rectangles and
  gets as far as proving that the right mouse button opens a window --
  and then fails to land the click on the tree row that navigates up out
  of `/data`. Everything after that click goes nowhere.

So: the *engine* under the button is proven, and it is literally the same
module the button calls (§ 8). The *wiring between the menu item and that
engine* is not proven, and this document does not pretend it is. The
runner is left in the tree, red and clearly labelled, rather than
quietly deleted or wired into `test.sh` where it would turn a green
suite red.

Two things did come out of the attempt and are worth keeping: the file
manager now reports the geometry of its **menu** (`explorer: menurect`)
and its **dialog** (`explorer: dlgrect`), the way it already reported
every widget rectangle. The missing third one -- where the rows of the
tree list sit inside its rectangle -- is exactly what the next attempt
needs.

## 8. One implementation, two front ends

The file manager does **not** have its own copy of "walk a tree and hash
it". Both it and `/bin/backup` call `kernel/user/bstore.fi`.

The alternative was to let the file manager run `/bin/backup` and scrape
its output. That would have been less code on the day and a second
definition of the format for ever after -- and the day the two disagree
is the day somebody needs a restore.

What the file manager adds is a progress hook, which is a function
pointer `bstore` calls after every file. That is the entire seam.
