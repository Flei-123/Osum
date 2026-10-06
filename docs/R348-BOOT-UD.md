# r348: the boot crash after "ring3: back in ring 0" (measured 06.10.2026, NOT fixed)

Machine: `tools/design/eh6.sh` as `tools/zreap/run.sh` builds it (gfx, xHCI + usb-kbd + usb-mouse,
1 core, `nosched noproc nofs`), KVM. Boot loop without gdb: 1 of 40 boots dies
(and 3 of 3 collected crashes look the same):

    ring3: back in ring 0
    *** EXCEPTION 6 #UD   rip=0x67   cs=0x8  rflags=0x10202  rsp=0x8fc680  ss=0x10
    rax=1 rbx=0x9500 rbp=0x314 r10=0x92a800 ... (pid 1, "ANDERE KERNE: keiner")

* It is **not** the r378 race (1 core, boot task, with the r378 fix it still happens).
* It does **not** happen without a screen (`tools/execsmp/crash.sh 60 1`: 0 of 60).
* Same place every time: the kernel stack of the boot task (0x8bf000..0x8ff000), the
  word at 0x8fc678 = stack top - 0x2988. A `ret` pops 0x67 from it (other build: 0xc7 one
  word lower). The stack above it holds old `fb.*`/`wm.*` frames (text drawing), the live
  callers are gone: the slot is not a return address any more.
* `gdb` on KVM (hardware breakpoints work, software ones do not): a conditional
  hardware watchpoint on 0x8fc678 ("value between 1 and 0xfff"), armed at `unmap_user`
  (the first thing after the excursion), saw **no CPU write** before the exception frame
  itself. So the word was not written by code running on the CPU after the excursion:
  either it was already wrong at that moment, or a device wrote it (DMA), or `rbp`/`rsp`
  were off by a word at the `leave`/`ret` (rbp=0x314 is not a frame pointer).
* Next: watch the same word from the START of `user.run` (not only after), and compare
  `rbp`/`rsp` at every `leave_user`; check the devices that DMA (xHCI rings live in kdata,
  not near the stack; IDE is PIO) and the `fb` text path that runs after the excursion.

Tools used: `/tmp/r348/loop.sh`-style boot loop (KVM, 40 boots) and `gdb -batch` with
`target remote` + `hbreak _F0.trap__report` (copy of the commands is in the roadmap note).
