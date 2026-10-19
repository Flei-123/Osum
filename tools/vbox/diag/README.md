# tools/vbox/diag -- laptop-side VirtualBox diagnosis helpers (copy to C:\Users\justi\vbl\)
- `allcpu.ps1 -Sec N`: host CPU per VirtualBoxVM/VBoxHeadless pid (boss VM vs headless test VM; headless = VBoxHeadless, NOT VirtualBoxVM).
- `regs.ps1 -N n`: rip/rsp/cr3/rflags per vCPU (debugvm). Resolve: `nm -n <image dir>/osum.mb`; rflags bit 0x200 = IF. All vCPUs in idt.halt/sched.idle_wait+0x8c (HLT) while the host burns a core = host/VMM side wake storm, not a guest spin.
- `threads.ps1`: per-thread CPU of the test VM process.
Restart order after a VM restart: kill the `python` odbc proxy + delete odb.proxy.pid BEFORE `start`, else odbwait attaches to the dead pipe.
