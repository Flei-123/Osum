# w-bootterm83 interim
- Cause 1: kgstage creates the kernel console window "Terminal -- sh" (app=terminal) at boot; console tty sink = window, so every GUI program (stdout inherited from kernel spawns/taskbar) writes its debug lines there. With nobootterm it is only hidden; the taskbar Terminal pin finds it (app=terminal) and WA_TOGGLE shows it = "Terminal 1" full of spam.
- Cause 2: taskmgr prints "taskmgr: reset" every sample (takt/10) unconditionally; it is a trace line, not a reset loop.
- Plan: login/nobootterm boots create no console window (tty sink stays serial); taskmgr reset lines only with `report`; gate tools/bootterm updated + counter-proof.
