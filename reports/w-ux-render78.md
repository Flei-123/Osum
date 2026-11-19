# w-ux-render78 interim
## (c) xremoted autostart / host ID (analysis)
- HP was on build 6020 (e6e1accde, 12.11.) until 6347 (19.11.). The persistent home /var/xremote came with 230f77d89 (14.11.). The old home /run/xremote is RAM, so every reboot created a new identity.txt (17.11. 18:56 = first manual start after a reboot). Build 6347 keeps the ID in /var.
- HP /etc/inittab has no xremote line (install time, OTA does not touch /etc). glogin starts xremoted only at sign-in; at the login screen after a reboot nothing runs, and a crashed xremoted is never respawned.
- Fix planned: glogin starts xremoted when the login screen appears; xremoted idles until a taskbar exists.
