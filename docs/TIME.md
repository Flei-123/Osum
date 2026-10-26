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

## N-003 / N-004 / B-003 / R-007 -- the clock state, the network clock v2, rules as a table (26.10.2026)

### The clock state ("time not set") and TLS

The kernel knows three states (`kernel/sched/clockstate.fi`, shown in `/proc/clock` as
`clock state=unset|rtc|set`):

| state | meaning |
| --- | --- |
| `unset` | the wall clock is below the floor (`lib/ntp/bounds.fi`, 2026-10-01) or above 2100: a dead battery, a reset RTC. Nobody ever set the clock. |
| `rtc` | the value came from the hardware clock and is plausible. Not verified by anything. |
| `set` | somebody set it: `clock_settime`, `adjtimex`, `sntp`. |

`clock_gettime(16)` (`CLOCK_CHECKED`, `lib/ntp/abi.fi`) is `CLOCK_REALTIME` that answers `-ENODATA` while the state
is `unset`. All TLS callers take the time from `lib/tls/clockgate.fi` (`now_trusted()`), which turns that into `0`,
and `x509.verify_chain` with `now == 0` refuses with `V_CLOCK` (`fetch: verify REFUSED clock_not_set`) -- it does
not compare certificate dates against a clock the kernel knows is void, and it never skips the check. The taskbar
shows its `?` next to the time while the state is `unset` (as before while the network clock service has failed).
The floor is a constant: raise it with the build date when images are cut; a too-low floor only weakens the
check, a too-high one would refuse good clocks.

Not covered: a `rtc` state clock that is plausible but wrong is judged by the certificate dates only (measured:
`tools/time/tls.sh` cases B and C, "not yet valid" and "expired", then fixed by one `sntp`).

### The network clock v2 (`kernel/user/sntp.fi`, `lib/ntp/`)

* Pure parts in `lib/ntp/` (packet build/validate, offset and delay from the four timestamps, source selection,
  step/slew policy), checked against a Python model by `tools/ntp/run.sh`; the socket part is `lib/ntp/client.fi`.
* NTP era from a pivot (the floor), not from "below 2^31"; a server time before the floor or after 2100 is
  not plausible and refused before anything is set.
* Four samples per server (`BURST_SAMPLES`), the one with the smallest delay wins -- the first query of a boot
  waits for ARP and showed 935 ms round trip and a 459 ms wrong offset before this (measured).
* Several servers: `server=a,b,c` in `/etc/ntp.conf` (default `0..3.pool.ntp.org`), up to four distinct
  addresses. The largest group of offsets within 1 s of each other must hold at least `minsources=` (default 2,
  never more than the number of resolved sources) and a strict majority; its median is used. One liar among
  three is outvoted, two sources that disagree move nothing. A single configured server is accepted alone.
* Policy (`lib/ntp/policy.fi`): below 1 ms nothing; up to 128 ms the clock is slewed (`adjtimex`,
  `ADJ_OFFSET_SINGLESHOT`, 500 ppm in `kernel/sched/clockslew.fi`); above, stepped to the nanosecond
  (`clock_settime` takes `tv_nsec` now); a step beyond 1000 s is only taken while the clock was never set
  (first sync of a machine with a dead battery) -- an already synchronised clock is not dragged away
  (`sntp -f` forces it). `adjtimex` mode 0 returns `TIME_ERROR` until the clock was set, which is how `sntp` learns it.
* Kiss-o'-death: `RATE` doubles the interval of the service (64 s .. 3600 s), `DENY`/`RSTR` drop the answer; the
  retry schedule (10 s, 30 s, 5 min) is in `policy.fi`. Output keeps `sntp: from <host> offset=<s>s` and adds
  `offset_ms=`.
* NOT done: authentication (NTS, RFC 8915). The majority rule and the plausibility bounds stop nonsense and a
  single forger; an attacker on the path who answers for ALL sources can still send a plausible wrong time.

### The hardware clock convention per setting (B-003)

`/etc/time.conf` takes `rtc=utc` or `rtc=local` next to `offset=`/`rule=`. `sntp boot` passes it to the kernel
with the zone (`SETTZ` argument bits 9 and 10, `lib/ntp/abi.fi`); while nobody has set the clock the kernel
re-reads the chip's raw value in the new convention (`time.set_rtc_utc`). The settings program keeps the line when
it rewrites the zone. The boot word `rtcutc` still works; the config wins once `sntp boot` has run.

### Zones: rules are a table now

`lib/tz/rules.fi` holds one row per rule (month, first day of the search window, weekday, time, UTC or local
standard reference, hemisphere): EU, US/CA, AU, NZ, Chile, Cuba, Israel, Egypt. `lib/tz/tz.fi` has one
interpreter instead of one branch per rule. `tools/tz/gen.py` classifies every zone against IANA tzdata and
refuses what no rule reproduces: 83 zones now (Santiago, Havana, Jerusalem, Cairo added), Casablanca stays out
(its offset follows Ramadan). `rule=<name>` in `/etc/time.conf` and `/proc/clock` use `rules.rule_name`.

### Measured

* `tools/ntp/run.sh` (host): 61 checks, 0 failed (random packets/sample sets against a Python model).
* `tools/tz/run.sh`: 83 zones x 4,294,637 instants equal IANA tzdata.
* `tools/time/run.sh`, `boot.sh`, `tls.sh` (QEMU): see the commit message for the numbers.
* After a step the offset to the server is -1 ms (before: up to a second); a 10.8 ms offset is slewed and half of it
  is left after 11 s (kernel `slew_ns`).
* Found, not fixed: in QEMU/KVM the guest clock runs about 0.09 % (~900 ppm) slow against the host (the TSC is
  calibrated against the 100 Hz tick over 200 ms, `time.calibrate`). The hourly sync bounds it to a few seconds.
  A PM-timer window or an NTP frequency correction would fix it.
