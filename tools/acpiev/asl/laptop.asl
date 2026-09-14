// SPDX-License-Identifier: GPL-2.0-only
// tools/acpiev/asl/laptop.asl -- EIN DECKEL UND EIN AKKU, ALS METHODEN.
//
// ==================================================================
// WARUM ES DIESE TABELLE GIBT
// ==================================================================
//
// QEMU 7.2 hat WEDER einen Deckel NOCH einen Akku. `-device battery`
// kam erst mit QEMU 8.2, ein Deckelgeraet gibt es bis heute nicht, und
// `qom-set` hat nichts, worauf es zeigen koennte. Das ist ein
// GUELTIGER BEFUND und keine Ausrede -- er steht so im Bericht der
// Runde. Ohne eine Tabelle von aussen gaebe es an dieser Maschine
// nichts zu messen.
//
// Was es gibt, ist `-acpitable`: QEMU nimmt eine fertige Tabelle
// entgegen, rechnet die Pruefsumme und haengt sie in die XSDT ein.
// Also wird der Laptop hier NACHGEBAUT.
//
// ==================================================================
// WAS HIER ANDERS IST ALS IN `tools/k18/ssdt.py`
// ==================================================================
//
// Runde K18 hat dasselbe getan und musste `_BST` als KONSTANTES Paket
// hinschreiben (`Name(_BST, Package(4){...})`), weil `kernel/batt.fi`
// die Tabellen nur ABSUCHT und keinen Interpreter hat. Im Kopf jener
// Datei steht ehrlich, dass damit der handelsuebliche Laptop NICHT
// erledigt ist.
//
// HIER SIND ES METHODEN. `_LID`, `_BST`, `_BIF` und `_PSR` RECHNEN --
// sie lesen aus einer Operationsregion, verzweigen, multiplizieren und
// bauen ihr Paket zur Laufzeit zusammen, genau wie auf einem echten
// Brett. Eine Tabelle, die `kernel/batt.fi` NICHT lesen kann, und die
// deshalb misst, ob der Interpreter wirklich laeuft.
//
// DIE WERTE KOMMEN AUS DEM SPEICHER, NICHT AUS DER TABELLE. Die
// Operationsregion `LPST` liegt auf einer festen Adresse im unteren
// Speicher; der Messlauf schreibt dort hinein und aendert damit
// Deckelstellung und Ladestand WAEHREND DIE MASCHINE LAEUFT. Anders
// liesse sich "der Ladestand aendert sich und die Leiste zeigt es"
// nicht messen.
//
//   LPST + 0   Deckel: 1 = offen, 0 = zu
//   LPST + 1   Ladestand in Prozent (0..100)
//   LPST + 2   Zustand: 1 = entlaedt, 2 = laedt, 0 = voll
//   LPST + 3   Netzteil: 1 = am Netz
//
// Die Adresse steht auch in `tools/acpiev/run.sh` und in
// `docs/RUNDE-ACPI-EREIGNISSE.md`; sie ist mit Bedacht gewaehlt
// (0x9F00 liegt im letzten Kilooktett unter 640 KiB, das kein Kern
// benutzt und das QEMU als konventionellen Speicher fuehrt).

DefinitionBlock ("", "SSDT", 2, "OSUM", "LAPTOP", 0x00000001)
{
    Scope (\_SB)
    {
        // Der Zustand, den der Testlauf von aussen setzt.
        OperationRegion (LPST, SystemMemory, 0x9F00, 0x10)
        Field (LPST, ByteAcc, NoLock, Preserve)
        {
            XLID, 8,   // Deckel
            XPCT, 8,   // Prozent
            XSTA, 8,   // Zustand
            XACP, 8    // Netzteil
        }

        // ------------------------------------------------ der Deckel
        Device (LID0)
        {
            Name (_HID, EisaId ("PNP0C0D"))
            Method (_STA, 0, NotSerialized) { Return (0x0F) }
            // EINE METHODE, KEIN NAME. Sie liest und verzweigt --
            // `kernel/batt.fi` koennte das nicht.
            Method (_LID, 0, NotSerialized)
            {
                If (LEqual (XLID, Zero))
                {
                    Return (Zero)
                }
                Return (One)
            }
        }

        // ------------------------------------------- die Einschalttaste
        Device (PWRB)
        {
            Name (_HID, EisaId ("PNP0C0C"))
            Name (_UID, Zero)
            Method (_STA, 0, NotSerialized) { Return (0x0F) }
        }

        // ------------------------------------------------ der Akku
        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, One)
            Method (_STA, 0, NotSerialized) { Return (0x1F) }

            Name (PBIF, Package (0x0D)
            {
                One,          // Einheit: 0 = mWh, 1 = mAh
                0x1388,       // Auslegungskapazitaet: 5000
                0x1388,       // letzte volle Ladung: 5000
                One,          // Technik
                0x2A30,       // Auslegungsspannung: 10800 mV
                0x01F4,       // Warnung bei 500
                0x00C8,       // Untergrenze bei 200
                0x0A, 0x0A,
                "OSUM-BAT", "0001", "LION", "fleitec"
            })

            // `_BIF` RECHNET die letzte volle Ladung ein -- damit in
            // der Abnahme steht, dass die Methode wirklich lief und
            // nicht nur ein Paket abgeschrieben wurde.
            Method (_BIF, 0, NotSerialized)
            {
                Store (0x1388, Index (PBIF, 0x02))
                Return (PBIF)
            }

            Name (PBST, Package (0x04) { Zero, Zero, Zero, 0x2A30 })

            // DIE METHODE, UM DIE ES GEHT. Sie liest den Prozentwert,
            // rechnet ihn in eine Restkapazitaet um und setzt den
            // Zustand -- mit If/Else und Multiply, also mit dem, was
            // ein echtes `_BST` auch tut.
            Method (_BST, 0, NotSerialized)
            {
                Store (XSTA, Local0)
                Store (Local0, Index (PBST, Zero))
                // Restkapazitaet = Prozent * 5000 / 100 = Prozent * 50
                Store (XPCT, Local1)
                Multiply (Local1, 0x32, Local2)
                Store (Local2, Index (PBST, 0x02))
                // Strom: beim Laden 0, sonst 1000
                If (LEqual (Local0, 0x02))
                {
                    Store (Zero, Index (PBST, One))
                }
                Else
                {
                    Store (0x03E8, Index (PBST, One))
                }
                Store (0x2A30, Index (PBST, 0x03))
                Return (PBST)
            }
        }

        // ------------------------------------------------ das Netzteil
        Device (ADP0)
        {
            Name (_HID, "ACPI0003")
            Method (_STA, 0, NotSerialized) { Return (0x0F) }
            Method (_PSR, 0, NotSerialized)
            {
                If (LEqual (XACP, Zero))
                {
                    Return (Zero)
                }
                Return (One)
            }
            Name (_PCL, Package (0x01) { \_SB })
        }
    }

    // ================================================ die GPE-Methoden
    //
    // QEMUs eigene DSDT hat `\_GPE._E01` und `_E02` (PCI-Hotplug und
    // CPU-Hotplug). Diese Tabelle legt DREI weitere dazu. Ausgeloest
    // werden sie im Messlauf von Hand (`evfake`), weil es an dieser
    // Maschine keine Hardware gibt, die sie ziehen wuerde -- und genau
    // das ist der Befund.
    //
    // DIE BITNUMMERN SIND GEMESSEN UND NICHT GERATEN. Die erste
    // Fassung nahm 0x10, 0x11 und 0x12 -- "Bits, die QEMU nicht
    // benutzt". Der Kern hat sie gefunden (meth=5) und NICHT scharf
    // geschaltet (on=0), und er hatte recht: QEMUs GPE0-Block ist
    // VIER Oktette lang, also zwei Status- und zwei Freigabeoktette,
    // also die Bits 0..15. Bit 0x10 ist Bit 16 und liegt AUSSERHALB
    // des Blocks -- `gpe_sts_port` gibt dafuer 0 zurueck, und ein Bit
    // ohne Register laesst sich nicht freigeben. Das ist die Wache,
    // die verhindert, dass der Kern in einen fremden Anschluss
    // schreibt.
    //
    // Genommen werden deshalb 0x03, 0x04 und 0x05: im Block, und von
    // QEMUs eigener DSDT nicht belegt (die benutzt 0x01 und 0x02).
    Scope (\_GPE)
    {
        // Der Deckel.
        Method (_L03, 0, NotSerialized)
        {
            Notify (\_SB.LID0, 0x80)
        }
        // Der Akku.
        Method (_L04, 0, NotSerialized)
        {
            Notify (\_SB.BAT0, 0x80)
        }
        // Das Netzteil -- und der Akku gleich mit, weil sich mit dem
        // Netzteil auch der Ladezustand aendert. ZWEI `Notify` in
        // EINER Methode: genau der Fall, fuer den der Ring in
        // `amlev.fi` sechzehn Plaetze hat und nicht einen.
        Method (_L05, 0, NotSerialized)
        {
            Notify (\_SB.ADP0, 0x80)
            Notify (\_SB.BAT0, 0x80)
        }
    }
}
