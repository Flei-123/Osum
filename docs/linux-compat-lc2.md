# LC-2 design: remaining Linux syscalls

State after LC-1 (kernel/sys/syscompat.fi): t_sysgap GAP 69 -> 33. Remaining gaps, in order of value:

1. POSIX timers (222-226): new fd-less timer table per process in sched; expiry raises the signal through sched/signal.fi (SIGEV_SIGNAL first, SIGEV_THREAD_ID second). Reuse the timerfd tick source in fs/evfd.fi.
2. pidfd (434, 424, 438): new file kind K_PIDFD in fs/file.fi; poll readiness = task zombie; pidfd_send_signal maps to signal.send by pid captured at open.
3. SysV IPC (29-31, 64-66, 68-71): one table module ipc/sysv.fi; shm reuses unixsock shm pages (K_SHM backing), sem and msg are counters/queues behind a single lock.
4. ptrace (101): needs a stop-on-syscall hook in sys.fi dispatch (syshook.enter) and a tracee state in taskslot (T_TRACER, T_TRACESTOP). Order: TRACEME, ATTACH, CONT, PEEK/POKE (sysuser.peek/poke on the tracee mm), then SYSCALL stops and GETREGS. Needs wait4 integration for stop reports.
5. Rest stays ENOSYS on purpose: bpf, seccomp, userfaultfd, io_uring, perf_event_open, fanotify, pkey_*, process_vm_*, kcmp, memfd_secret.

Each step gets a t_* check in tools/unterbau and a pinned line in fixed.txt.
