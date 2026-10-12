# BRANCHES — remote branches not merged into main (12.10.2026)

Snapshot of `origin` against `origin/main` `03124085` (ACCEL phase 1, worker w-accel1). `ahead` = commits only on the branch,
`behind` = commits only on main, `merge vs main` = `git merge-tree --write-tree origin/main <branch>`:
`no net change` = the merge would not change main (content already in main), `clean merge` = would merge, `CONFLICT` = would not.
The file-overlap numbers in "why" are `git diff --diff-filter=A <merge-base> <branch>` files that exist / are identical on main - an ASSESSMENT by overlap, not a code review.

Decisions: **delete** = fully contained in main, remote ref removed (tip hash below, restore with `git push origin <tip>:refs/heads/<name>`);
**owner** = another worker is on it, do not merge/delete; **drop-candidate** = most content already on main, check the rest, then archive (tag) + delete;
**keep** = unique work not on main; **rebase-or-drop** = old lineage, owner decides; **Boss** = product decision.
Rule: only branches fully contained in main are deleted; everything else stays until a human/worker decides. `unterbau` (local, not on origin) is handled in the report (rebased, gates, merge).

| branch | tip | ahead | behind | last commit | merge vs main | decision | why |
|---|---|---|---|---|---|---|---|
| `lizenz` | 75a31837 | 1 | 1522 | 2026-09-05 | clean merge | **Boss** | relicensing PROPOSAL, not armed; product decision |
| `action-bus-4` | 14a71dd9 | 0 | 511 | 2026-09-29 | no net change | **delete** | ancestor of main (fully merged) |
| `avx-ota` | 5c591248 | 1 | 1619 | 2026-09-01 | no net change | **delete** | merge-tree against main: no net change (content in main) |
| `avx-ota2` | 2ba8ade2 | 1 | 1614 | 2026-09-01 | no net change | **delete** | same as avx-ota |
| `ota-kontroll` | e2e5fc93 | 1 | 1623 | 2026-09-01 | no net change | **delete** | merge-tree against main: no net change (content in main) |
| `runde-clip2` | 075a95fb | 0 | 805 | 2026-09-18 | no net change | **delete** | ancestor of main (fully merged); local checkouts keep their own ref |
| `blechecht2` | f94b1395 | 2 | 1540 | 2026-09-03 | CONFLICT | **drop-candidate** | 27 of 30 added files are on main (19 identical); check the 3 others, then tag+delete |
| `certus` | f5cabe85 | 12 | 1814 | 2026-08-28 | CONFLICT | **drop-candidate** | 46 of 59 added files on main (30 identical); Certus lives on main; check 13 rest |
| `gauntlet-best` | ef7ec415 | 10 | 954 | 2026-09-14 | CONFLICT | **drop-candidate** | old gauntlet experiment (score 77/100), only 3 doc files added |
| `inventory` | 4517fd21 | 3 | 2080 | 2026-08-27 | CONFLICT | **drop-candidate** | SPDX headers: main already carries them (build scripts, tools); 216 files modified, conflicts |
| `snip` | c4faea8d | 6 | 1821 | 2026-08-28 | CONFLICT | **drop-candidate** | 34 of 45 added files on main (26 identical); snip gate not on main -> check tools/snip first |
| `speicherdruck` | 07ae9290 | 5 | 1031 | 2026-09-14 | CONFLICT | **drop-candidate** | 3 of 3 added files on main; tools/oom exists on main |
| `supersearch` | 6354ea77 | 12 | 1826 | 2026-08-29 | CONFLICT | **drop-candidate** | 35 of 46 added files on main (27 identical); supersearch gate not on main -> check tools/supersearch first |
| `demux` | 6c0215f0 | 11 | 1857 | 2026-08-28 | CONFLICT | **keep** | unique: tools/demux + audio/video demux, not on main (roadmap P-009 no video decoder) |
| `feedback` | 8a548666 | 8 | 1864 | 2026-08-29 | CONFLICT | **keep** | unique: tools/feedback, 10 of 30 added files on main |
| `haertung` | 7124a1fd | 2 | 1679 | 2026-08-30 | CONFLICT | **keep** | unique: kernel/hard.fi + tools/haertung; main has tools/hardening (other lineage) |
| `media1` | 0da09c03 | 10 | 1857 | 2026-08-28 | CONFLICT | **keep** | unique: tools/media1, not on main (P-009) |
| `netprofil` | ba90bf8e | 5 | 1696 | 2026-08-30 | CONFLICT | **keep** | unique: kernel/netprof.fi + tools/netprofil |
| `nvmeq` | 6589ee93 | 7 | 1779 | 2026-08-30 | CONFLICT | **keep** | unique: tools/nvmeq (NVMe queues), not on main |
| `ofs4` | e64a8884 | 2 | 1660 | 2026-09-01 | CONFLICT | **keep** | unique: tools/ofs4 (journal v4?), main has ofs3 + OFS journal; check, then drop |
| `ring` | 65f09fdd | 3 | 1779 | 2026-08-30 | CONFLICT | **keep** | unique: kernel/ring.fi + tools/ring, not on main |
| `standby` | ef3812f1 | 4 | 1643 | 2026-08-30 | CONFLICT | **keep** | S3 reached main by another route (tools/s3*); branch has tools/standby + kernel/sleep.fi: check, then drop |
| `viewer` | 47369aff | 15 | 1857 | 2026-08-29 | CONFLICT | **keep** | unique: tools/viewer + 9 kernel/user files, 1 of 30 on main |
| `wmplugin` | a7ca947a | 51 | 954 | 2026-09-14 | CONFLICT | **keep** | 51 commits, 219 passed; main has tools/wmplug (other lineage); check, then merge or drop |
| `feat-cursor` | b727b322 | 1 | 4 | 2026-10-11 | clean merge | **owner: worker cursor** | do not touch (design round, gates open) |
| `feat-features` | 5fc3331b | 2 | 3 | 2026-10-11 | clean merge | **owner: worker features** | do not touch (notifc, gate 8/4) |
| `staff/orientos-store-redesign` | c1639aad | 1 | 4 | 2026-10-11 | clean merge | **owner: worker store** | do not touch (WIP, not compiled) |
| `staff/w-tokens-glass` | f14a8109 | 1 | 2 | 2026-10-11 | clean merge | **owner: worker tokens** | do not touch (noglass word) |
| `w-caret` | b2ec4992 | 1 | 8 | 2026-10-11 | clean merge | **owner: worker glass/caret** | contained as cherry-pick in w-glassdev; do not touch |
| `w-glassdev` | 3b6ab2f5 | 3 | 4 | 2026-10-11 | clean merge | **owner: worker glass** | do not touch |
| `w-present` | 66d3d9d4 | 2 | 8 | 2026-10-11 | clean merge | **owner: worker present** | do not touch |
| `w-settings` | e7272f79 | 1 | 4 | 2026-10-11 | clean merge | **owner: worker settings** | do not touch |
| `w-vblank` | 11fbabc7 | 4 | 5 | 2026-10-11 | clean merge | **owner: worker vblank** | do not touch (superseded by w-vblank-rebased) |
| `w-vblank-rebased` | 4f71b616 | 4 | 4 | 2026-10-11 | clean merge | **owner: worker vblank** | do not touch |
| `a11y` | 4b0f10f3 | 5 | 1857 | 2026-08-28 | CONFLICT | **rebase-or-drop** | a11y gate exists on main (58/0, rebuilt later); branch has 16 files not on main; owner decides |
| `struktur` | 5cd41df9 | 5 | 1624 | 2026-09-02 | CONFLICT | **rebase-or-drop** | restructure round (70 files modified), 1624 behind; renames conflict with main |
| `struktur-vec` | 67491cc0 | 3 | 1624 | 2026-09-02 | CONFLICT | **rebase-or-drop** | as struktur |

## Hygiene (same snapshot)
- Reaper rule: a worktree whose HEAD is an ancestor of `origin/main` and whose `git status` is clean may be removed (`git worktree remove`) together with its branch. Dirty merged worktrees (`/root/osum-r537`, `/root/osum-jd`) hold untracked experiments - not removed.
- Re-generate the table: the script is a 40-line `git for-each-ref` + `git merge-tree` loop (see the report of w-accel1-dev-loop-phase-1); keep decisions in this file, not in chat reports.
