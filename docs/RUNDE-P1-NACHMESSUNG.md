# Round P1 re-measurement (26.10.2026, main 86b03ca5)

| Item | Status | Evidence |
|---|---|---|
| A-014 `memmap.py` | already fixed | `python3 tools/kernel/memmap.py`: 148 regions, 12 vectors, 0 collisions (the constant is `RAND_OFF`, `MARGIN_OFF` never existed) |
| A-015 `fas` double `_start` | already fixed | cause was `rt.rt` vs `std.rt` (patch 0005); k16 binds 237 of 238 programs, all fUi programs included |
| A-016 profile `kernel` instead of `app` | already fixed | `tools/lib/userprog.sh` (`up_build`); netview, customres, paint, display, tiling, netmon: no `not available in profile` anywhere |

New in this round: `fas` knew no `rep stosq` (`bench`, line 687); added (`F3 48 AB`, byte-identical to GNU as). k16 section 1: 237 -> 238 of 238.

## Open (red before and after, not build errors)

- k16: osum.s vs wirt.s differ (char 73), executable differs, `nobigmem` counter-proofs
- netview: 12 red (state icons, quick settings Escape/tile, page load 46 octets)
- tiling: 4 red (window 1/2 pixels)
- display: syscall number range 1810..1819 reused in snipgrab/powerd
- paint: `wm.fi` blend formula string missing
