# Test OrientOS from a Windows laptop (X-Remote)

1. **Windows:** copy `freeviewer.exe` (0.30.0, signed, from `/root/projects/freeviewer/dist-0.30.0/`) to the laptop and start it. No installer, no RDP.
2. **OrientOS:** open the Store, search `remote`, install **Remote control** (package `xremote`, needs the network right `net`).
3. **OrientOS:** open a Terminal and switch it on: `act call settings.set key=remote.enabled value=true`. Confirm the system dialog (switching on is a critical setting).
4. **OrientOS:** wait about 10 s, then show the ID and the password: `act call settings.get key=remote.id` and `act call settings.get key=remote.password`. Fallback: `cat /run/xremote.state /run/xremote.info`.
5. **Windows:** in FreeViewer choose "Connect to a computer", enter the 9-digit ID and the password, press Connect. The OrientOS desktop appears; mouse and keyboard work.
6. The password is new on every switch-on. The host only runs while someone is signed in (not at the login screen).
7. **Stop:** `act call settings.set key=remote.enabled value=false`, or press `Super+Esc` (emergency stop for remote input).
8. Relay: `wss://freeviewer.fleitec.com/fv/ws` (default, nothing to configure). Status line: `cat /run/xremote.info` (`service=running`).
9. Not there yet: there is no Settings window page for the switch (terminal only), and the package is only in the Store after the Boss applies the next feed stand.
