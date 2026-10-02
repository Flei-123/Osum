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
