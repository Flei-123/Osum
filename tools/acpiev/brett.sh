#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/acpiev/brett.sh -- WAS AUF JUSTINS BRETT NACHZUMESSEN IST.
#
# ==================================================================
# WARUM ES DIESE DATEI GIBT
# ==================================================================
#
# Alles, was die Runde ACPI-EREIGNISSE misst, misst sie auf QEMU. Was
# dort NICHT geht, ist genau der Teil, der zaehlt:
#
#   * QEMU 7.2 hat KEINEN Deckel (kein Geraet, auch nicht in 9.x) und
#     KEINEN Akku (`-device battery` erst ab QEMU 8.2). Beide sind
#     in `tools/acpiev/asl/laptop.asl` NACHGEBAUT, und das GPE-Bit
#     wird von Hand gezogen (`evfake`).
#   * Damit ist NICHT gemessen: dass ein echtes Brett das Bit wirklich
#     zieht, dass es das RICHTIGE Bit ist, und dass das Loeschen den
#     Unterbrechungssturm verhindert, den `kernel/hw.fi` seit Runde
#     BLECHVIER beschreibt.
#   * GEMESSEN IST auf QEMU: die Einschalttaste (die kann QEMU
#     wirklich, `system_powerdown` zieht den SCI), der ganze Weg
#     GPE-Methode -> `Notify` -> `_LID`/`_BST`/`_PSR` -> Wert, die
#     Umschaltung in den ACPI-Modus, und die Register-/Namensrechnung
#     (`evself`).
#
# Diese Datei sagt, was am echten Brett zu tun und abzulesen ist.
#
# ==================================================================
# SO WIRD GEMESSEN
# ==================================================================
#
#   1. Vom Stick starten (tools/usbimg/build.sh) und die serielle
#      Leitung mitschneiden. Ohne Serienanschluss: `evdump` weglassen
#      und die Messtafel benutzen (`tafel`).
#
#   2. Kernelzeile:
#
#        acpiev evdump evself
#
#      `evself` rechnet Namen und Register nach (kostet nichts),
#      `evdump` legt jedes Ereignis auf die Leitung.
#
#   3. DIE ERSTE ZEILE IST DER BEFUND:
#
#        acpiev: ready=1 why=0 sci=9 gpearm=N meth=M lid=L batt=B ...
#
#      ready=1   die Ereignisse stehen.
#      why       0 = laeuft. 1 = keine FADT. 2 = kein Interpreter.
#                3 = Namensraum liess sich nicht halten. 4 = mit
#                `noacpiev` abgeschaltet. 5 = die FADT nennt keine
#                Leitung.
#      sci       die Leitung. Auf den meisten Brettern 9.
#      mode      0 = nichts getan, 1 = war schon im ACPI-Modus,
#                2 = kein SMI_CMD (nichts zu tun), 3 = UMGESCHALTET,
#                4 = geschrieben, aber SCI_EN kam nicht. BEI 4 IST
#                ETWAS FAUL -- dann bleibt das Brett im Legacy-Modus
#                und meldet nichts.
#      meth      wie viele `\_GPE._Lxx`/`_Exx` die Firmware hat.
#                EIN LAPTOP HAT WELCHE. Steht hier 0, ist entweder
#                der Namensraum nicht da oder die Firmware legt ihre
#                Ereignisse anders ab (dann sagen die `gpe b=`-Zeilen
#                nichts, und das ist der Befund).
#      lid       1 = offen, 0 = zu, 2 = kein `_LID` gefunden.
#      batt      1 = ein Akku mit `_BST`.
#      pwrb      1 = ein Geraet PNP0C0C (Einschalttaste).
#
#   4. DIE ZEILEN DANACH nennen jedes GPE-Bit einzeln:
#
#        acpiev: gpe b=0x1B art=0 on=1
#
#      art 0 = `_Lxx` (pegelgesteuert), 1 = `_Exx` (flankengesteuert).
#      on=0 HEISST: das Bit liegt AUSSERHALB der GPE-Bloecke der FADT
#      und wurde NICHT scharf geschaltet. Das ist kein Fehler dieses
#      Kerns, sondern eine Wache -- siehe den Kommentar in
#      `gpe_sts_port`.
#
#   5. JETZT DIE HARDWARE BEDIENEN, und nach jedem Schritt die
#      Berichtszeile ansehen (sie kommt mit `evdump` von selbst alle
#      200 Durchlaeufe):
#
#      a) DECKEL ZUKLAPPEN.   Erwartet: eine Zeile
#                             `acpiev: ev gpe b=0x..`, danach
#                             `acpiev: deckel zu -- gesperrt`, und der
#                             Sperrbildschirm auf dem Schirm.
#                             `lid=` muss von 1 auf 0 springen.
#      b) DECKEL AUFKLAPPEN.  `lid=` zurueck auf 1,
#                             `acpiev: deckel auf`. NICHT entsperrt --
#                             das ist Absicht.
#      c) NETZTEIL ZIEHEN.    `ac=` von 1 auf 0, und `ev=` steigt.
#      d) NETZTEIL STECKEN.   `ac=` zurueck auf 1.
#      e) EINSCHALTTASTE KURZ DRUECKEN (nicht halten!).
#                             `acpiev: ev taste`, `irqs=` steigt,
#                             `sts=` hat Bit 8 (0x0100).
#                             Das Energiemenue muss aufgehen.
#      f) EINE VIERTELSTUNDE LAUFEN LASSEN, nichts tun.
#                             `irqs=` darf NICHT ins Uferlose steigen.
#                             DAS IST DIE STURM-PROBE: steigt sie um
#                             Tausende je Sekunde, wird ein Statusbit
#                             nicht geloescht, und genau davor warnt
#                             `kernel/hw.fi` seit Runde BLECHVIER.
#                             Dann: `noacpiev` auf die Kernelzeile,
#                             und die `gpe b=`-Zeilen des Laufs
#                             hierherschicken.
#
#   6. AKKU: `pct=` muss sich ueber die Zeit aendern und zur Anzeige
#      des BIOS passen. Weicht es ab, ist `_BIF` schuld (die letzte
#      volle Ladung) -- `PG_BATREMAIN` und `PG_BATFULL` ueber
#      `/bin/power` ausgeben lassen und mit dem BIOS vergleichen.
#
# ==================================================================
# WENN ETWAS NICHT GEHT
# ==================================================================
#
# Der haeufigste Fall ist `meth=0` oder `on=0` ueberall. Dann bitte
# MIT `amldump` neu starten: der Kern legt die ganzen ACPI-Tabellen
# als Hexzeilen auf die Leitung, und
#
#     python3 tools/aml/disasm.py ns   TABELLE.bin
#     python3 tools/aml/pflichtenheft.py TABELLE.bin
#
# sagen dann, was in DIESER Firmware wirklich steht und welche
# Opcodes ihr fehlen. Das ist derselbe Weg, mit dem das Pflichtenheft
# dieser Runde entstanden ist -- nur mit echten Tabellen statt mit
# nachgebauten.
set -uo pipefail
cd "$(dirname "$0")/../.."

echo "Diese Datei ist eine ANLEITUNG und kein Testlauf."
echo "Sie beschreibt, was auf echter Hardware nachzumessen ist."
echo
echo "Kernelzeile:   acpiev evdump evself"
echo "Bei Verdacht:  acpiev amldump   (Tabellen auf die Leitung)"
echo
echo "Die Schritte stehen im Kopf dieser Datei:"
sed -n '/^# *5\. JETZT DIE HARDWARE/,/^# *6\./p' "$0" | sed 's/^# \{0,1\}//'
