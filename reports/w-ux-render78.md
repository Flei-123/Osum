# w-ux-render78 interim
## (c) xremoted autostart / host ID (analysis)
- HP was on build 6020 (e6e1accde, 12.11.) until 6347 (19.11.). The persistent home /var/xremote came with 230f77d89 (14.11.). The old home /run/xremote is RAM, so every reboot created a new identity.txt (17.11. 18:56 = first manual start after a reboot). Build 6347 keeps the ID in /var.
- HP /etc/inittab has no xremote line (install time, OTA does not touch /etc). glogin starts xremoted only at sign-in; at the login screen after a reboot nothing runs, and a crashed xremoted is never respawned.
- Fix planned: glogin starts xremoted when the login screen appears; xremoted idles until a taskbar exists.

## status 11:50
- (c) glogin bug found: xremoted was exec'd without argv[0], so the "already running" guard (any_named) never matched; each sign-in could start another copy. Fixed (argv[0]="xremoted"), glogin now also starts it at the sign-in screen. Gate tools/xremote/autostart.sh 7/0 (counter-proof old tree: never starts).
- (a) cause: host grabs the draw surface in 64 KiB chunks (47 syscalls per 1280x800 frame); presents/compose run in between => rows from different frames (tear). Fix: kernel snapshot of the draw surface at row 0 under L_GUI + cp lock (kernel/ui/shotsnap.fi, shot.fi source()). Gate tools/grabtear/run.sh: snapshot mixed=0 of 40; counter-proof noshotsnap mixed=40 of 40.
- (c) identity: xremoted flushes identity.txt once the host created it (freeze reset could lose the unflushed file).
