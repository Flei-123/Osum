# TIME — die Uhr im Alltag (DAILY-DRIVER, 02.10.2026)

Drei Dinge, die ein täglich benutztes System von seiner Uhr braucht, und die
bis hierher gefehlt haben:

1. **Sommerzeit nach Regel.** Die Startzeile trug `tz=120` fest (Mitteleuropa
   im Sommer): von der letzten Oktober- bis zur letzten Märzsonntag eine Stunde
   zu viel. Jetzt ist `tz=` der **Normalzeit-Versatz** (`tz=60` für Wien) und
   `tzrule=eu` (oder der Systemaufruf `SYS_OSUM_SETTZ` 1971) schaltet die
   EU-Regel zu: Sommerzeit von 01:00 UTC am letzten Märzsonntag bis 01:00 UTC am
   letzten Oktobersonntag. `time.tz_min` (`I_TZMIN`) liefert den Versatz **zum
   jetzigen Zeitpunkt**; `I_TZBASE`/`I_TZRULE` die beiden Teile. Alle
   Startzeilen der Stick-Einträge und des Installers stehen auf
   `tz=60 tzrule=eu`.
2. **Die Uhr stellen.** `clock_settime` (Linux 227, nur root, nur
   `CLOCK_REALTIME`, nur 2024..2100) verschiebt `TIME_BOOT` — die monotone Uhr
   springt nie — und schreibt die Hardware-Uhr (`time.rtc_write`, nur im
   24-Stunden-Modus), damit der nächste Start es nicht zurücknimmt.
3. **Die Uhr aus dem Netz.** `/bin/sntp` (RFC 4330, Client): `sntp [-n]
   [host[:port]]`, `sntp boot` als Dienst (vom Schreibtischstart gerufen):
   wendet `/etc/time.conf` (`offset=`, `rule=eu|none`) an und stellt mit
   `auto=true` in `/etc/ntp.conf` die Uhr, sobald das Netz da ist, und alle
   `abstand` Sekunden. Abgesichert: zufälliger gebundener Quellport, 64-Bit-
   Nonce im Sendefeld (muss im Originate-Feld zurückkommen), Quelladresse und
   -port geprüft, abgelehnt werden Modus ≠ 4, Stratum 0, Leap-Indikator 3,
   kurze Pakete, Zeiten außerhalb 2024..2100; NTP-Ära 1 (ab 2036) wird gelesen.
   **Nicht** authentifiziert (kein NTS): wer auf dem Weg sitzt, kann eine
   plausible falsche Zeit schicken.

Das Einstellungsfenster (Reiter *Zeit*) zeigt, was der Kern hat, und hat die
Wahl *Mitteleuropa (Sommerzeit automatisch)*; die Taskleiste und die
Dateizeiten im Explorer folgen derselben Regel (Dateizeiten je nach dem
Zeitpunkt der Datei, nicht nach heute).

Das persönliche Abbild liefert `offset=60 rule=eu` und `auto=true`; das
öffentliche UTC und `auto=false` — ein Download, der beim ersten Start von
selbst einen Server fragt, ist genau das, was das öffentliche Abbild vermeidet.

Messung: `bash tools/time/run.sh` (QEMU, `tools/time/fakentp.py` als
Gegenstelle): Stand, Sommerzeitwechsel an sechs Zeitpunkten, fünf fehlerhafte
Antwortarten, NTP-Ära 1, Gegenprobe ohne `tzrule`.

Nicht messbar in QEMU: ob die CMOS-Uhr eines echten Brettes annimmt, was
`rtc_write` hineinschreibt (der Aufruf wird gemacht, sein Ergebnis nicht
geprüft); ein echter NTP-Server im echten Netz.

## r544 -- the clock was 2 h ahead after the boot (11.10.2026, found on the real Dell)

The Dell's first network sync said `offset=-7199s`: the clock was two hours
AHEAD for the first minutes of every boot. Cause: `time.tz_anwenden` (takes
the zone off the hardware clock, which holds LOCAL time by default) was
called only from `mode_of` -- and `mode_of` (command line) runs in
`kernel_main` at line 246, `time.init` (reads the RTC) at line 311. The call
found nothing to convert, `init` then stored the raw local RTC value as UTC,
and the display added the zone once more. Every VM test hid it because QEMU's
RTC is UTC by default and the old fixed `tz=120` lines happened to add it back.

Fix: `kernel_main` calls `tz_anwenden` again right after `time.init`; the
function converts once (`tz_done`) and never after somebody set the clock
(`clock_moved`). A boot line without `tz=` leaves the door open: the first
SETTZ (`sntp boot` from /etc/time.conf) does the one conversion.

Convention (unchanged, ECHTHARDWARE-1): the chip holds LOCAL time unless the
boot line says `rtcutc`. `rtc_write` (after `clock_settime`) writes local too.

Measured with `tools/time/boot.sh` (QEMU `-rtc base=...,clock=vm`, fake NTP
server saying the true UTC; the first `date` and `sntp -n` run before anything
may set the clock): offset to the true time on main vs fixed -- RTC local
11:00 summer 7201 s vs 1 s; no zone on the boot line 7202 s vs 2 s; local
03:30 on 25.10. (winter) 3601 s vs 2 s; local winter 3602 s vs 1 s.

`sntp boot` retries: at once, then every 10 s for a minute, every 30 s for the
next minute, every 5 minutes until it works (the Dell log shows the first
try failing with `cannot resolve host` before the lease and the sync later).
