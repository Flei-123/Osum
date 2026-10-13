# SECURITY-TOCTOU-KERNEL -- user-space facing paths (W-TOCTOU-A, 13.10.2026)

Audit of the OrientOS kernel for time-of-check/time-of-use (double-fetch) bugs on memory an attacker can change
while the kernel runs: user pointers of syscalls, shared buffers (wayd/compositor), memfd/SHM, futex words, bus data.
Method: read of `kernel/sys/sys.fi`, `sysgui.fi`, `kernel/sched/futex.fi`, `kernel/fs/unixsock.fi`, `kernel/user/wayd.fi`,
`wmd.fi`, plus a script that flags a user reader called twice with the same address expression inside one function
(`readers = user_word, user_word32, get32, get16, get_user64, get64u, peek`). Driver part (MMIO/DMA rings, descriptors
in guest/device memory): `docs/SECURITY-TOCTOU-KERNEL-DRIVERS.md` (W-TOCTOU-B, pending when this was written).
Background: <https://github.com/xoreaxeaxeax/schrodingers-toctou> -- the optimizer may duplicate a load from
attacker-writable memory, so "read into a local, check the local" is not enough unless the compiler is told the
load is single (volatile / read_once). A `read_once`/snapshot primitive from the Firn side (`docs/SECURITY-TOCTOU.md`)
was NOT in main on 13.10. (git fetch); until then the rule below is the only defence.

## Result in one paragraph
The syscall layer is mostly sound by construction: user data comes in through `copy_in` (page-wise copy into a kernel
bounce buffer, each octet read once) or `peek`/`user_word` (one octet at a time, translated and checked per octet),
and the kernel then works on the copy. execve argv/envp, ioctl, sendto/netlink/bus/writev/epoll_ctl/select/timer
structures all follow that rule. Found: one real read-back double fetch (pipe2), one overflow panic in a length
helper, one unchecked translate, one cached-physical-address-across-sleep, a stride validation hole in wayd, and
several design-level items (unenforced F_SEAL_WRITE, CLOEXEC mask width, global scratch buffers) listed below.

Rule used (keep it): read every user value ONCE into a local (or bounce buffer), validate the local, use the local;
never `translate` an address once and keep the physical address across a sleep, a lock release or a second syscall step.

## Findings

| ID | Risk | Where | Problem | Status |
|----|------|-------|---------|--------|
| K-01 | medium | `kernel/sys/sys.fi` `dispatch` UB_PIPE2 (old lines 2873-2884) | `pipe2` wrote the two new fds to the user `int[2]`, then READ THEM BACK (`user_word32(a0)`, twice) to apply O_CLOEXEC/O_NONBLOCK. A second thread can rewrite the array in between: the flag lands on an arbitrary other fd of the process (clears nothing, but sets CLOEXEC/NONBLOCK on e.g. a socket the program relies on); an unmapped page reads as 0 and flags fd 0. | FIXED: `do_pipe_flags` applies the flags to the kernel's own `fd0/fd1`. Test `toctou.pipe2_*`. |
| K-02 | high (DoS) | `sys.fi` `page_up` (used by munmap `do_unmap` 8014, mmap, mremap, shm map) | `v + PAGE - 1` is the CHECKED add (HAERTUNG-2: overflow -> `osum_panic`). `munmap(addr, ~0)` or any length > 2^64-4096 stops the kernel from ring 3 -- the same class as the `user_ok` bug the fuzzer found. | FIXED: wrapping add; length rounds to 0 pages, callers already reject 0. Test `toctou.munmap_huge_len_*`, `mmap_huge_len_fails`. |
| K-03 | low | `kernel/sys/sysgui.fi` WM_CREATE title loop (old 922) | `kstate.get8(proc.translate(...))` after `user_ok`: if another thread unmaps the page in between, `translate` is 0 and the kernel reads physical address 0 into the window title (also no `stac` window). | FIXED: uses the checked reader `sys.peek` (exported). |
| K-05 | medium | `kernel/user/wayd.fi` `on_shm_pool` CREATE_BUFFER (~668-700) and `surface_commit`/`blit_sub` (~814-990) | The pool check only covered `off + h*stride <= size`. `w` was never compared with `stride`; commit reads `w*4` octets per row, `w` is a client 32-bit value (windows are created with `w<<16`). A client reads far past its own pool: wayd faults (every Wayland client loses its window) or draws memory of other pools. Not a race, but it is the "stride/size" check of the task. | FIXED: `w in 1..16384` and `w*4 <= stride`, else `wl_shm.invalid_stride` (code 1). May conflict with W-DEMAND (branch `staff/orientos-mv71vc9o`), which edits the same function (error codes); take both. |
| K-06 | medium-low | `kernel/sched/futex.fi` `lock_pi` (369-403) | `phys` is translated once, then the loop sleeps (`sleep_on`) and re-reads/CASes that PHYSICAL address after waking. If another thread of the process `munmap`s the futex page meanwhile and the frame is reused, `cas32` writes a TID/WAITERS bit into a foreign page. | FIXED: `phys` re-translated every round (EFAULT if gone). `t_futex` is the regression test. |
| K-07 | medium | `sys.fi` F_ADD_SEALS (~7147), `map_shm` (~7864), `unixsock.shm_add_seals` | `F_SEAL_WRITE` is accepted and stored, never enforced: writable mappings stay writable, `map_shm` PROT_WRITE ignores the seal, adding it does not check existing writable mappings. A receiver that relies on a sealed memfd (check size/content, then use) can be fooled -- the textbook memfd TOCTOU. Only SHRINK/GROW are enforced (`do_ftruncate` ~16892). | OPEN. Fix: refuse `F_SEAL_WRITE` with -EBUSY while `unixsock.map_*` knows a writable mapping; refuse PROT_WRITE in `map_shm` and writes in `write_of` for K_SHM when sealed. wayd does not rely on it today. |
| K-08 | medium | `sys.fi` `cx_put/cx_get` (17262) | The close-on-exec set is ONE u64 per task (`1 << fd`), but `file.MAX_FD` is 512 since W-LIMITS. For fd >= 64 the bit is lost (or the shift is undefined): O_CLOEXEC fds leak across execve. Not a race but a missed check at use time. | FIXED (13.10., W-TOCTOU-C): 512-bit set per task at kstate.CX_OFF (0x595000, 64 octets x 128 tasks); test t_cloexec (descriptors >= 64, child inherits only unflagged). |
| K-09 | low | `do_recvmsg` (~16740-16780), `do_pipe_flags` | fds are allocated/popped first, `put32` to user memory afterwards; on EFAULT they leak (SCM_RIGHTS fds stay in the table, pipe fds too). | OPEN. Free on failure. |
| K-10 | low | `do_sendmsg`/`do_recvmsg` | `iovlen` is not capped (writev 1024, netlink 64). Each entry is `user_ok`-checked, so it is bounded only by mapped memory; zero-length entries make a long non-preemptible loop. | OPEN. Cap at 1024 (-EMSGSIZE). |
| K-11 | low | `wayd.fi` `dispatch` (1304), `str_arg` (1462) | `len` of the message is passed nowhere; handlers read fixed argument offsets and `str_arg` trusts the in-message string length up to `max` (<= 32). A short message makes wayd read stale bytes of the client input buffer or, at the end of `IN_CAP`, the first bytes of the NEXT client's buffer into a window title. The input buffer itself is private, so there is no race. | OPEN. Check `len >= 8 + wlproto arg size` in `drain`, bound `str_arg` by the message. |
| K-12 | info | `kernel/fs/unixsock.fi` `send_bytes/recv_bytes`, `sys.fi` `WL_SCRATCH/WL_PATH` (16333) | One GLOBAL scratch page (0xFE000, 0xFF000) for sendmsg/recvmsg/send/recv on unix sockets, filled by `copy_in` and consumed by the ring copy; `blockb` is per core, these are not. Ring head/tail updates have no lock. Two cores in unix-socket syscalls at once can mix payloads of two processes (copy-in of A overwritten by B before `send_bytes`). I did NOT verify whether unix-socket syscalls are serialised elsewhere. | OPEN, verify with SMP>=2 stress (two senders, distinct patterns). Fix: use `blockb(state)` (MSG_MAX 2048 fits a page) and a lock around the ring update. |
| K-13 | medium (SMP) | all `copy_in/copy_out/peek/poke/user_word*`, `futex.rd32`, `clear_child_tid`, `wig.fetch/store` | `translate` -> physical address -> access, with no lock against `do_unmap`/`page_drop` on another core of the same process. Between translate and access the frame can be freed and handed to another process (write: corruption of a foreign page; read: leak). Window is a few instructions per page, so hard to hit, but threads share the address space and this is the attacker model. | OPEN, design item. Options: per-address-space rwlock held across the copy page loop and taken exclusive in munmap/page_drop; or frame refcount pinned during the copy. |

## Reviewed and sound (no change)
- `execve`/`spawn` argv and envp (`sys.fi` 9040-9150, 9420-9460): each pointer word read once, each string copied
  by `fetch_name` (byte-wise, `user_ok` per octet, bounded); counts are checked against the local copy.
- `do_ioctl`, `do_sendto`, `nl_send_of`, `nl_sendmsg`, `do_bus` (BUS_SEND..NOTIPOST), `do_setgroups`, `do_wgset`, audio
  write, `shot_copy`: bounce buffer first, work on the copy; lengths multiplied only after a bound check.
- `do_writev`/`do_epoll_ctl`/`do_epoll_wait`/select/timerfd: every user word read once; the iovec array is walked
  entry by entry, each entry read once into locals.
- `do_sendmsg` SCM_RIGHTS: `cmsg_len` read once into `clen`, checked `<= ctllen` (already `user_ok`-ed), fds read once.
- futex WAIT: value compared once, under the futex lock, right before queuing (`sleep_on`); PI paths use CAS.
- memfd ftruncate never frees frames (only size changes) and `map_shm` takes a reference, so a mapped SHM page cannot
  vanish under wayd/wmd. wayd keeps `w/h/stride/base` in its own table, not in shared memory; pixel reads
  (`surface_commit`, `blit_sub` read a pixel twice for run-length) can tear colours but drive no index or length.
- wmd/compositor shared window buffers: geometry comes from a kernel snapshot (`snap` + `same_tab`), the mapped buffer
  is read as pixels only.
- Byte-wise multi-octet reads (`user_word`, `get32`) are not atomic (torn reads). Every use feeds a pointer that is
  `user_ok`-checked afterwards or a value that is only compared once, so torn values are harmless today; keep it so.

## Rules for new code
1. Syscall structure from user space: `copy_in` the whole struct into `blockb(state)` (or a local array) and read fields
   from the copy. Never call `user_word`/`get32` twice for the same field.
2. Never apply a result "to what the user buffer now says" (K-01): use the kernel's own value.
3. A physical address from `translate` lives only inside one `stac/clac` window (K-06, K-13).
4. Lengths from user space: bound first, multiply after, use `+%` only where wrap is the check (`user_ok`), never in
   rounding helpers (K-02).
5. Shared pools/buffers (wayd, SHM, bus segments): geometry in a private table, validated at creation; shared memory
   gives pixels/bytes only.
6. When the Firn `read_once`/snapshot primitive lands in main, replace "local copy by hand" in the places above (copy_in
   byte loops are `kstate.get8` calls; whether the Firn backend can duplicate such a load was not checked here).

## Tests
`tools/unterbau/t_toctou.c` (accept.txt: `toctou.*`): pipe2 flags on a quiet array and under a racing writer, huge
munmap/mmap lengths. `t_futex` (27/0) for K-06. K-05 is covered by the wayland/foot gates (`tools/wayland/run.sh`,
`tools/foot/run.sh`); no dedicated negative test yet (needs a client with stride < 4*width).
