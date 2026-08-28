# Zwischenstand — Runde INIT

Zweig `init`, abgezweigt von `mergeline` (4f844b5), Arbeitsbaum
`/root/osum-init`. **Nicht nach `main` gemergt.**

---

## 0. Die Ausgangslage, nachgesehen statt geglaubt

Der Auftrag sagte: „`/etc/inittab` ist leer bzw. nicht vorhanden. Es gibt
keine Möglichkeit, Dienste zu starten, zu überwachen und bei Absturz neu
zu starten." Das ist **zur Hälfte richtig**, und die andere Hälfte ist
wichtiger.

**Was WIRKLICH schon da war** (`git show mergeline:kernel/user/init.fi`,
475 Zeilen, Runde K13):

| Behauptet in der Doku | Im Baum von `mergeline` |
|---|---|
| `/sbin/init` als Prozess 1 | **da** — `kernel/user/init.fi`, der Kern startet ihn in `kmain.osum` |
| `/etc/inittab` mit `once`/`respawn`/`ctrl`/`off` | **da** — `read_tab()`, Format `name:art:befehl` |
| Waisen einsammeln | **da** — `harvest()`, `wait4(-1, WNOHANG)` in der Schleife |
| Neustart abgestürzter Dienste | **da**, aber nur **gedrosselt** (200 ms Pause), **nicht begrenzt** |
| Herunterfahren über echtes ACPI | **da** — SIGTERM, 2 s, SIGKILL, `reboot(RB_POWEROFF)` |
| `/bin/svc start\|stop\|status\|restart` | **da** — über `/run/svc.cmd` und `/run/svc.state` |

**Was WIRKLICH gefehlt hat:**

1. **`/etc/inittab` liegt in keinem Abbild, das dieses Repo baut.** Die
   einzige Stelle im ganzen Baum, die eine anlegt, ist
   `tools/k13/run.sh` — in einem temporären Verzeichnis, für die Dauer
   des Testlaufs. Ein installiertes Osum bootet ohne inittab, `init`
   sagt `init: /etc/inittab fehlt` und gibt 1 zurück. Insofern hatte der
   Auftrag recht: **in der Praxis gab es keine Dienstverwaltung**, weil
   die Datei nirgends entsteht.
2. **Kein Rückfall-Zähler.** Die 200-ms-Pause ist eine Drosselung, keine
   Grenze: ein Dienst, der beim Start sofort stirbt, wird für immer
   fünfmal je Sekunde neu gestartet. Genau der Fall, den der Auftrag
   „kocht die Maschine" nennt.
3. **Kein Runlevel, kein Ziel.** Jede Zeile lief immer.
4. **Keine Protokolldatei je Dienst.** Alles ging auf die Konsole.
5. **Keine Abhängigkeit „erst nach Netz".**
6. **Kein `/bin/shutdown`, kein `/bin/reboot`** — nur `svc shutdown`.
7. **`RB_RESTART` war kein Neustart.** `kernel/sys.fi` schickte ihn in
   `power.shutdown()`, also in den Ausgang des Prüfstands: die Maschine
   blieb stehen und kam nicht wieder.
8. **`MAX_SVC = 8`.**

**Messung der Ausgangslage:** `bash tools/k13/run.sh` auf `mergeline` →
**99 Zusagen, 0 Fehler**. Das ist die Zahl, die nach dieser Runde nicht
kleiner sein darf.

---

## 1. Was diese Runde ändert

*(wird während der Runde fortgeschrieben)*
