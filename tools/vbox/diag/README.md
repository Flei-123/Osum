# tools/vbox/diag -- laptop-side VirtualBox diagnosis helpers (copy to C:\Users\justi\vbl\)
- `allcpu.ps1 -Sec N`: host CPU per VirtualBoxVM/VBoxHeadless pid (boss VM vs headless test VM; headless = VBoxHeadless, NOT VirtualBoxVM).
- `regs.ps1 -N n`: rip/rsp/cr3/rflags per vCPU (debugvm). Resolve: `nm -n <image dir>/osum.mb`; rflags bit 0x200 = IF. All vCPUs in idt.halt/sched.idle_wait+0x8c (HLT) while the host burns a core = host/VMM side wake storm, not a guest spin.
- `threads.ps1`: per-thread CPU of the test VM process.
Restart order after a VM restart: kill the `python` odbc proxy + delete odb.proxy.pid BEFORE `start`, else odbwait attaches to the dead pipe.
- `tm.ps1 -Sec N`: two `debugvm statistics` samples of the test VM: per-vCPU executing/halted/other as % of wall time (/TM/CPU/NN/cNs*) and the biggest NEM/EM/PDM per-second rates (ExitHalt, ExitPortIo, ...). In the 99 % state compare halted% vs host CPU.
- `ab.ps1 -Url .. -ShaXz .. -ShaRaw .. -Tag t`: one whole A/B round in the background (stop, fetch, swapdisk, start headless, ODB, login, settle, host CPU samples, tm); log `C:\Users\justi\vbl\ab-<Tag>.log`. Start via Invoke-CimMethod Win32_Process Create. Boss VM shows up as the other ~100 % pid (noise).
