# Linux compatibility: open Unterbau checks (measured 14.10.2026, main 69faec01)

Source: `ONLY="t_procfs t_misc t_limits t_mem t_proc t_threads" heavy bash tools/unterbau/run.sh` (KVM, 1 core).
Result on main: **226 PASS / 240 checks, 14 open (LC-001 since fixed: +1 PASS)** (6 FAIL, 8 GAP). The "30 open" of the older metric is stale
(`t_limits` is 8/8 now; `t_mem` 47/48; `t_misc` 69/70; `t_threads` 24/25).
Hidden gap: `misc.prctl_name_roundtrip` is only emitted when `prctl_get_name` works, so it counted as neither.

Effort: S = hours, M = a day, L = several days / layout change. Relevance: 3 = blocks the program class, 2 = degrades, 1 = rare.
Columns musl / busybox / Docker (runc, Go) / Firefox.

| # | check | cause (file) | effort | musl | busybox | Docker | Firefox | status |
|---|-------|--------------|--------|------|---------|--------|---------|--------|
| 1 | threads.fd_table_shared_between_threads | `clone(CLONE_THREAD)` copies the descriptor/handle table; Linux shares it (CLONE_FILES). `file.fi` fd_check/handle tables are per task slot. Fix idea: resolve the table owner = thread-group leader in `fd_check/fd_handle/fd_set_rights/fd_free/fd_alloc` + `handle.resolve_num`, and do not drop fds when a non-leader thread exits | L | 3 | 1 | 3 (Go runtime opens fds in any thread) | 3 | **fixed (LC-001, 16.10.2026)**: `clone(CLONE_THREAD\|CLONE_FILES)` shares the leader's table (`T_FDOWN` = owner slot+pid, `file.owner`); `fork`/`vfork`/thread without CLONE_FILES still copy; sockets + descriptors close with the LAST user (`file.release_use`), the leader's reaper closes a left-over table; FD_CLOEXEC marks follow the owner. Open: concurrent `fd_alloc` of two threads on SMP is not atomic; exec in a thread keeps the other threads (no kill) |
| 2 | procfs.shm_create + procfs.path_dev_shm | `/dev` is devfs (create = EPERM) and the image has no `/dev/shm`. Fix idea: mount a RAM-backed fs (K_SHM objects exist in `unixsock.fi`) or an OFS dir at `/dev/shm`; `shm_open`, `sem_open`, Mesa/Wayland/Chromium IPC need it | M | 3 | 0 | 2 | 3 | open |
| 3 | procfs.self_exe_readlink | procfs has no symlink node type (`vfsops` has only dir/file). Needs: remember the exec path per task (T_ARG area / new word) + readlink hook for `/proc/<pid>/exe`; also `/proc/self/cwd`, `fd/N` links | M | 2 | 1 | 3 (runc re-execs `/proc/self/exe`) | 3 (finds its own dir) | open |
| 4 | procfs.sys_cpu_online / possible / cache | `/sys` is an empty image directory, no sysfs. Fix idea: second procfs mount flavour at `/sys` with a small static tree (`devices/system/cpu/{online,possible,present}`, `cpu0/cache/index0/size`) fed from the real CPU count | M | 1 | 0 | 2 (Go: `/sys/fs/cgroup`, cpu count) | 3 (`sched_getaffinity` fallback, jemalloc/Rust `num_cpus`) | open |
| 5 | mem.mmap_file_shared | DONE (LC-006b, partial): `mmap(MAP_SHARED, file fd)` = shared page object, write-back on msync/munmap/exit. LIMITS: max 256 pages (1 MiB) per mapping (bigger = ENOMEM), no MAP_FIXED, write(2) after mapping is not seen and is overwritten at write-back, no timer write-back, overlapping mappings with a different start offset are separate objects, read-only MAP_SHARED is a snapshot, race when two processes map first at the same time (two objects) | L | 2 | 0 | 2 | 3 |
| 6 | procfs.self_maps_names_libc | The kernel keeps no mapping list, so `/proc/self/maps` lines have no file name. Needs a small VMA table (start, end, inode/path) written by mmap/exec/dlopen | L | 1 | 0 | 1 | 2 (crash reporter, `dl_iterate_phdr` is fine) | open |
| 7 | procfs.path_dev_dri / procfs.sys_drm | No DRM device and no GPU driver (roadmap G-012). Firefox/Mesa fall back to software rendering | L (driver) | 0 | 0 | 0 | 2 | blocked on G-012, not a lie to fake |
| 8 | proc.system_exit_status / proc.popen | Test image has the Osum shell as `/bin/sh` (no POSIX `-c`). With busybox as `/bin/sh` (`BBSH=1`, run.sh section 3c) both PASS | S (ship busybox as `/bin/sh` in `tools/usbimg/build.sh`) | 3 (`system`/`popen`) | 3 | 3 | 2 | test-image artefact, passes in the busybox run |
| 9 | misc.prctl_get_name (+ hidden prctl_name_roundtrip) | `PR_GET_NAME` returned EINVAL (kernel kept no name) | S | 1 | 1 | 2 | 2 (thread names) | **fixed on branch w-lc1** (comm in two free task words, exec sets basename, fork/clone inherit, `/proc/<pid>/status` Name) |

## Order of work
1. #9 (done), #8 (image change), #3, #2 (cheap and used by every big program).
2. #4 (sysfs view), then #1 (descriptor table sharing — biggest, needs its own round with the handle table).
3. #5, #6 together (VMA table + shared file pages), #7 after G-012.

Notes
* Free words in the task record (TASK_BYTES 1024): 680, 760 were free and are now `T_COMMA/T_COMMB`; 1016 is the last free word.
* Text constants / K2 scalar side: no new offsets were added.
